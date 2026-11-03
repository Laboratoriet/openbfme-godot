extends Node
## Lane IOS-2: `-- --touch --touch-selftest=<folder>` in a game (with --auto): plays the touch gestures as synthetic touch events, through the same
## Input path a phone's touches take, and reports what each did to the camera, plus a picture after each. Prints TOUCH SELFTEST PASS / FAIL.
## Lane IOS-10: last, a tap 6 pt beside the Palantir's key must be moved onto it by the tap assist and open the quit menu (closed again after).

var _out := ""
var _controls: Node


func start(controls: Node, out_dir: String) -> void:
	_controls = controls
	_out = out_dir
	DirAccess.make_dir_recursive_absolute(_out)
	_run()


func _run() -> void:
	var hud: Node = null
	for i in 600:  # up to a minute for the game to be on screen
		hud = _controls._game_hud()
		if hud != null and Vector2(hud.get_camera().get("position", Vector2.INF)).is_finite():
			break
		await get_tree().create_timer(0.1).timeout
	if hud == null:
		print("TOUCH SELFTEST FAIL: no game on screen")
		return
	await _wait(2.0)
	var size := get_viewport().get_visible_rect().size
	var mid := size / 2.0
	var failures := PackedStringArray()
	await _shot("0-start")

	# 1. two-finger pan: both fingers move 300 px left; the camera must move
	var before: Vector2 = hud.get_camera().position
	await _two_finger(mid + Vector2(-80, 0), mid + Vector2(80, 0), Vector2(-300, 0), 0.0)
	var after: Vector2 = hud.get_camera().position
	print("TOUCH SELFTEST pan: camera %s -> %s (moved %.1f)" % [before, after, before.distance_to(after)])
	if before.distance_to(after) < 1.0:
		failures.append("pan did not move the camera")
	await _shot("1-after-pan")

	# 2. pinch apart (zoom in), then together (zoom out); the camera's height must change each way
	var h0: float = hud.get_camera().height_above_ground
	await _two_finger(mid + Vector2(-60, 0), mid + Vector2(60, 0), Vector2.ZERO, 200.0)
	await _wait(0.6)
	var h1: float = hud.get_camera().height_above_ground
	await _shot("2-after-pinch-in")
	await _two_finger(mid + Vector2(-260, 0), mid + Vector2(260, 0), Vector2.ZERO, -200.0)
	await _wait(0.6)
	var h2: float = hud.get_camera().height_above_ground
	print("TOUCH SELFTEST pinch: height %.1f -> %.1f (apart) -> %.1f (together)" % [h0, h1, h2])
	if not (h1 < h0 and h2 > h1):
		failures.append("pinch did not zoom in and out (heights %.1f %.1f %.1f)" % [h0, h1, h2])
	await _shot("3-after-pinch-out")

	# 3. one-finger box drag, a tap, a double tap and a hold: they must reach the game as the mouse actions (counted by the controls)
	await _one_finger_drag(mid + Vector2(-200, -120), mid + Vector2(200, 120))
	await _tap(mid)
	await _wait(0.5)
	await _tap(mid + Vector2(40, 0))
	await _wait(0.05)
	await _tap(mid + Vector2(40, 0))
	await _wait(0.5)
	await _hold(mid)
	await _shot("4-after-taps")
	var s: Dictionary = _controls.stats
	print("TOUCH SELFTEST gestures: ", JSON.stringify(s))
	for k in ["drags", "taps", "double_taps", "holds", "pans", "zoom_notches"]:
		if int(s.get(k, 0)) < 1:
			failures.append("no " + k)

	# 4. lane IOS-10, the tap assist: a tap 6 points beside the Palantir's key (its Options button), outside the key, presses it: the quit menu opens
	var assist_failures: PackedStringArray = await _assisted_tap_check(hud)
	failures.append_array(assist_failures)
	if failures.is_empty():
		print("TOUCH SELFTEST PASS")
	else:
		print("TOUCH SELFTEST FAIL: ", "; ".join(failures))


## lane IOS-10: the tap assist's check; its failures (none: passed)
func _assisted_tap_check(hud: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if not hud.has_method("nearest_button"):
		out.append("the extension has no nearest_button (built before lane IOS-10)")
		return out
	var path := "PalantirButtons.Buttons.Options"
	var at := _beside(hud, path, 6.0)
	if not at.is_finite():
		out.append("no point 6 pt beside the Palantir's key that the tap assist sends to it")
		return out
	var game: Node = get_tree().current_scene
	var assisted0 := int(_controls.stats.assisted_taps)
	await _tap(at)
	await _wait(1.5)
	var opened: bool = game != null and game.get("_quit_open") == true
	print("TOUCH SELFTEST tap assist: a tap at %s, 6 pt beside the key: assisted %d, quit menu %s" % [at, int(_controls.stats.assisted_taps) - assisted0, opened])
	await _shot("5-after-assisted-tap")
	if int(_controls.stats.assisted_taps) != assisted0 + 1:
		out.append("the tap beside the key was not assisted")
	if not opened:
		out.append("the assisted tap did not press the key (no quit menu)")
	elif game.has_method("_close_quit_menu"):
		game._close_quit_menu()
		await _wait(1.0)
	return out


## a window point `points` beside the HUD button at `path`, just outside its hit area, that the tap assist sends to it (Vector2.INF: none). It walks
## out of the button from its centre (up, left, down, right) to the first point the assist does not call a hit of it, then `points` further
func _beside(hud: Node, path: String, points: float) -> Vector2:
	var b: Dictionary = hud.find_button_window(path)
	if not b.get("found", false):
		return Vector2.INF
	var centre := Vector2(float(b.x), float(b.y))
	var px_per_pt: float = _controls._scale
	for dir in [Vector2.UP, Vector2.LEFT, Vector2.DOWN, Vector2.RIGHT]:
		var p := centre
		for i in 400:
			var r: Dictionary = hud.nearest_button(p, 0.0)
			if str(r.get("reason", "")) != "hit" or not str(r.get("target", "")).contains(path):
				break
			p += dir
		var q: Vector2 = p + dir * (points * px_per_pt)
		var probe: Dictionary = _controls.assist_probe(q)
		print("TOUCH SELFTEST tap assist probe %s: %s" % [q, JSON.stringify(probe)])
		if probe.snapped and str(probe.target).contains(path):
			return q
	return Vector2.INF


func _touch(index: int, at: Vector2, down: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = at
	t.pressed = down
	Input.parse_input_event(t)


func _drag(index: int, at: Vector2, rel: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = index
	d.position = at
	d.relative = rel
	Input.parse_input_event(d)


## two fingers at a and b move together by `shift` while their distance changes by `spread` (pixels), in 12 frames
func _two_finger(a: Vector2, b: Vector2, shift: Vector2, spread: float) -> void:
	_touch(0, a, true)
	_touch(1, b, true)
	await get_tree().process_frame
	var dir := (b - a).normalized()
	var pa := a
	var pb := b
	for i in range(1, 13):
		var f := i / 12.0
		var na := a + shift * f - dir * spread * 0.5 * f
		var nb := b + shift * f + dir * spread * 0.5 * f
		_drag(0, na, na - pa)
		_drag(1, nb, nb - pb)
		pa = na
		pb = nb
		await get_tree().process_frame
	_touch(0, pa, false)
	_touch(1, pb, false)
	await get_tree().process_frame


func _one_finger_drag(from: Vector2, to: Vector2) -> void:
	_touch(0, from, true)
	await get_tree().process_frame
	var p := from
	for i in range(1, 11):
		var n := from.lerp(to, i / 10.0)
		_drag(0, n, n - p)
		p = n
		await get_tree().process_frame
	_touch(0, to, false)
	await _wait(0.3)


func _tap(at: Vector2) -> void:
	_touch(0, at, true)
	await _wait(0.06)
	_touch(0, at, false)
	await get_tree().process_frame


func _hold(at: Vector2) -> void:
	_touch(0, at, true)
	await _wait(0.7)
	_touch(0, at, false)
	await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return  # headless: no picture
	var path := _out.path_join("touch-%s.png" % label)
	print("TOUCH SELFTEST picture %s: %s" % [path, error_string(image.save_png(path))])
