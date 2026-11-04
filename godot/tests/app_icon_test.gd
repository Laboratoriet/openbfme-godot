## Lane OWNERFIX-3: the generated window icon (scripts/app_icon.gd) decodes to the 256 x 256 OpenBFME icon, and the game sets it at start.
## godot --headless --path godot --script res://tests/app_icon_test.gd   ->  "APP ICON OK" and exit 0, else "APP ICON FAIL ..." and exit 1
extends SceneTree

const AppIcon := preload("res://scripts/app_icon.gd")


func _init() -> void:
	var fails: Array[String] = []
	var img: Image = AppIcon.image()
	if img == null:
		fails.append("the icon does not decode")
	else:
		if img.get_width() != 256 or img.get_height() != 256:
			fails.append("the icon is %dx%d" % [img.get_width(), img.get_height()])
		# the ring is gold on a dark tile (Godot's logo is blue and white): count the gold pixels
		var gold := 0
		for y in range(0, 256, 2):
			for x in range(0, 256, 2):
				var c := img.get_pixel(x, y)
				gold += 1 if c.a > 0.9 and c.r > 0.55 and c.r > c.b + 0.3 else 0
		if gold < 500:
			fails.append("the icon has %d gold sample pixels (the ring has thousands)" % gold)
	var mac: Image = AppIcon.image(true)
	if mac == null:
		fails.append("macOS icon does not decode")
	elif mac.get_pixel(0, 0).a != 0.0 or mac.get_pixel(128, 128).a != 1.0:
		fails.append("macOS icon needs transparent exterior and opaque tile")
	# Verify every bundled ICNS size, not just the runtime 256px image.
	var icns := FileAccess.get_file_as_bytes("res://assets/app_icon/openbfme.icns")
	var pos := 8
	var checked := 0
	while pos + 8 <= icns.size():
		var size := (int(icns[pos + 4]) << 24) | (int(icns[pos + 5]) << 16) | (int(icns[pos + 6]) << 8) | int(icns[pos + 7])
		if size < 8 or pos + size > icns.size():
			fails.append("malformed ICNS chunk")
			break
		var frame := Image.new()
		if frame.load_png_from_buffer(icns.slice(pos + 8, pos + size)) != OK:
			fails.append("ICNS frame does not decode")
		else:
			var edge := frame.get_width()
			for corner in [Vector2i(0, 0), Vector2i(edge - 1, 0), Vector2i(0, edge - 1), Vector2i(edge - 1, edge - 1)]:
				if frame.get_pixelv(corner).a != 0.0:
					fails.append("opaque corner in %dpx ICNS frame" % edge)
			if frame.get_pixel(edge / 2, edge / 2).a != 1.0:
				fails.append("tile interior is transparent in %dpx frame" % edge)
		checked += 1
		pos += size
	if checked != 5:
		fails.append("ICNS needs five frame sizes")
	# the script compiles on a thread with a small stack: a Godot thread gets the platform's default secondary stack (512 KiB on macOS and iOS),
	# and a constant written as a chain of ~800 "+" overflowed it in GDScriptAnalyzer::reduce_binary_op (this process then dies, no FAIL line)
	var loader := Thread.new()
	loader.start(_compile_and_decode)
	var width: int = loader.wait_to_finish()
	if width != 256:
		fails.append("compiled on a thread, the icon decodes to width %d" % width)
	if AppIcon.apply() != "":
		fails.append("apply: " + AppIcon.apply())
	var game := FileAccess.get_file_as_string("res://scripts/game.gd")
	if not game.contains("AppIcon.apply()"):
		fails.append("game.gd does not set the icon at start")
	if fails.is_empty():
		print("APP ICON OK")
		quit(0)
	else:
		print("APP ICON FAIL ", "; ".join(fails))
		quit(1)


## a fresh compile of scripts/app_icon.gd (not the cached one the preload made) and the width of its image; -1 when it does not load or decode
func _compile_and_decode() -> int:
	var script: GDScript = ResourceLoader.load("res://scripts/app_icon.gd", "", ResourceLoader.CACHE_MODE_IGNORE)
	if script == null:
		return -1
	var img: Image = script.call("image")
	return img.get_width() if img != null else -1
