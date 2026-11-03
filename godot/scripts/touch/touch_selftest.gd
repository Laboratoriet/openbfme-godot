extends Node
## Lane IOS-2: `-- --touch --touch-selftest=<folder>` in a game (with --auto): plays the touch gestures as synthetic touch events, through the same
## Input path a phone's touches take, and reports what each did to the camera, plus a picture after each. Prints TOUCH SELFTEST PASS / FAIL.
## Lane IOS-10: last, a tap 6 pt beside the Palantir's key must be moved onto it by the tap assist and open the quit menu (closed again after).
## Lane IOS-21: then, with a builder selected, a hold on a side bar button and on the portrait shows their help while held and presses nothing; a tap
## still presses (the building's placement, cancelled again by a hold in the world: its right click); and a double tap on an autocast ability (the
## Witch-king's Morgul Blade, made for the test when the hooks allow it) toggles its autocast.

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

	var angle0: float = hud.get_camera().angle
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
	# lane IOS-15: the pan and the pinches must not have turned the camera
	var angle1: float = hud.get_camera().angle
	if absf(angle_difference(angle0, angle1)) > 0.001:
		failures.append("a pan or pinch turned the camera (%.3f -> %.3f rad)" % [angle0, angle1])
	# 2b. lane IOS-15, twist: the fingers turn 45 degrees about their middle; the camera must turn about as much
	await _twist(mid, 140.0, deg_to_rad(45.0))
	await _wait(0.4)
	var angle2: float = hud.get_camera().angle
	var turned := absf(angle_difference(angle1, angle2))
	print("TOUCH SELFTEST twist: camera angle %.3f -> %.3f rad (turned %.1f degrees for a 45 degree twist)" % [angle1, angle2, rad_to_deg(turned)])
	if turned < deg_to_rad(20.0):
		failures.append("the twist did not turn the camera (%.1f degrees)" % rad_to_deg(turned))
	await _shot("3b-after-twist")

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
	# 5. lane IOS-18: a builder selected, for the side command bar's picture at the HUD size in effect
	await _builder_picture(hud)
	# 6. lane IOS-21: hold shows info; a double tap toggles autocast
	failures.append_array(await _hold_info_check(hud))
	failures.append_array(await _autocast_check(hud))
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


## lane IOS-18: the local player's first builder (a Porter / Worker template: retail names, a test's facts) selected, then a picture of the side
## command bar it opens (no verdict: the HUD size's own checks are the hud2 palantir unit tests)
func _builder_picture(hud: Node) -> void:
	var game: Node = get_tree().current_scene
	var world = game.get("_world") if game != null else null
	if world == null:
		print("TOUCH SELFTEST builder picture: no game world")
		return
	for o in world.get_player_objects(str(game.get("_local_name"))):
		var t := str(o.template)
		if t.contains("Porter") or t.contains("Worker"):
			hud.select_object(int(o.id))
			await _wait(1.5)
			print("TOUCH SELFTEST builder picture: %s %d selected" % [t, int(o.id)])
			await _shot("6-builder-selected")
			return
	print("TOUCH SELFTEST builder picture: no builder of the local player")


## lane IOS-21: the help box's state (InGameHudNode get_hud6_state().help)
func _help(hud: Node) -> Dictionary:
	return hud.get_hud6_state().get("help", {})


## lane IOS-21: a hold on the HUD button at window point `at`: the help while held (a picture `label`), none after, nothing pressed. Its failures
func _hold_on(hud: Node, at: Vector2, what: String, label: String) -> PackedStringArray:
	var out := PackedStringArray()
	var game: Node = get_tree().current_scene
	var touched: Dictionary = hud.touch_button_at(at)
	if str(touched.get("kind", "")) == "":
		out.append("%s at %s is no HUD button for a finger (%s)" % [what, at, JSON.stringify(touched)])
		return out
	var infos0 := int(_controls.stats.infos)
	var holds0 := int(_controls.stats.holds)
	var placing0: bool = hud.get_placement().placing
	var selection0: Array = hud.get_selection() if hud.has_method("get_selection") else []
	_touch(0, at, true)
	await _wait(0.25)
	var early: Dictionary = _help(hud)  # the finger is down, not yet a hold: the touch help shows nothing (a tap would flash it otherwise)
	await _wait(0.45)
	var held: Dictionary = _help(hud)
	await _wait(0.4)  # the box's opening (its movie's Show) before the picture
	await _shot(label)
	_touch(0, at, false)
	await _wait(0.6)
	var after: Dictionary = _help(hud)
	print("TOUCH SELFTEST hold on %s at %s (%s): before the hold shown %s; held shown %s held %s bar %s name \"%s\" title \"%s\"; lifted shown %s; infos +%d, holds +%d" % [
		what, at, JSON.stringify(touched), early.get("shown"), held.get("shown"), held.get("held"), held.get("bar"), held.get("name"), held.get("title"),
		after.get("shown"), int(_controls.stats.infos) - infos0, int(_controls.stats.holds) - holds0])
	if early.get("shown", false):
		out.append("%s: the help showed before the hold" % what)
	if not held.get("shown", false) or (str(held.get("name", "")) == "" and str(held.get("title", "")) == ""):
		out.append("%s: no help while held" % what)
	if after.get("shown", false):
		out.append("%s: the help stayed after the finger lifted" % what)
	if int(_controls.stats.infos) != infos0 + 1 or int(_controls.stats.holds) != holds0:
		out.append("%s: the hold was not an info hold" % what)
	if hud.get_placement().placing != placing0:
		out.append("%s: the hold pressed the button (placement %s -> %s)" % [what, placing0, hud.get_placement().placing])
	if hud.has_method("get_selection") and hud.get_selection() != selection0:
		out.append("%s: the hold changed the selection" % what)
	if game != null and game.get("_quit_open") == true:
		out.append("%s: the hold opened the quit menu" % what)
	return out


## lane IOS-21: with the builder of _builder_picture selected: a hold on its first side bar button and one on the portrait show their help; a tap on
## the button still presses it (a placement starts, no help after it), and a hold in the world (the right click) cancels that placement
func _hold_info_check(hud: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if not hud.has_method("touch_button_at"):
		out.append("the extension has no touch_button_at (built before lane IOS-21)")
		return out
	if not _help(hud).get("touch", false):
		out.append("the HUD's help is not the touch help (set_touch_help)")
	var side := Vector2.INF
	for b in hud.get_command_buttons():
		if not b.in_palantir and str(b.command) == "DOZER_CONSTRUCT":
			var w: Dictionary = hud.find_button_window(str(b.frame))
			if w.get("found", false):
				side = Vector2(float(w.x), float(w.y))
				print("TOUCH SELFTEST hold: side bar button %s (%s) at %s" % [b.name, b.frame, side])
				break
	if not side.is_finite():
		out.append("no side bar build button of the builder on screen")
		return out
	out.append_array(await _hold_on(hud, side, "a side bar button", "7-hold-side-button"))
	var portrait := Vector2.INF
	for path in ["CommandUI.PortraitBackground", "CommandUI.Portrait"]:
		var w: Dictionary = hud.find_button_window(path)
		if w.get("found", false):
			portrait = Vector2(float(w.x), float(w.y))
			break
	if portrait.is_finite():
		out.append_array(await _hold_on(hud, portrait, "the portrait", "8-hold-portrait"))
	else:
		out.append("no portrait button on screen")
	# a tap still presses: the builder's build button starts a placement; the pointer the tap leaves on it opens no help
	await _wait(0.4)
	await _tap(side)
	await _wait(0.8)
	var placing: bool = hud.get_placement().placing
	var after: Dictionary = _help(hud)
	print("TOUCH SELFTEST tap on the side bar button: placing %s, help shown %s" % [placing, after.get("shown")])
	if not placing:
		out.append("a tap on the side bar button did not press it (no placement)")
	if after.get("shown", false):
		out.append("the help showed after a tap")
	# a hold in the world stays the right click: it cancels the placement
	var mid := get_viewport().get_visible_rect().size * Vector2(0.5, 0.35)
	await _hold(mid)
	await _wait(0.5)
	print("TOUCH SELFTEST hold in the world while placing: placing %s" % hud.get_placement().placing)
	if hud.get_placement().placing:
		out.append("a hold in the world did not cancel the placement (no right click)")
	return out


## lane IOS-21: a double tap on an autocast ability toggles its autocast, and again back; its single tap waits for the second. The auto game's
## starting units have no autocast ability, so the Witch-king (Morgul Blade, AutoAbility = Yes; test_autocast1_hud.cpp's rig) is made for the local
## player and given the blade's upgrade through the test hooks; where they refuse (a logic worker), the check SKIPs, saying so (the engine side is the
## unit test "ios21 retail ...")
func _autocast_check(hud: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var game: Node = get_tree().current_scene
	var world = game.get("_world") if game != null else null
	if world == null or int(game.get("_local_index")) < 0:
		print("TOUCH SELFTEST autocast double tap: SKIP (no game world / local player)")
		return out
	var cam: Vector2 = hud.get_camera().position
	var id := int(world.create_object("AngmarWitchking", int(game.get("_local_index")), cam.x + 60.0, cam.y + 60.0, 0.0))
	if id <= 0:
		print("TOUCH SELFTEST autocast double tap: SKIP (create_object refused: %s)" % str(world.call("get_command_errors") if world.has_method("get_command_errors") else ""))
		return out
	await _wait(0.5)
	var upgraded: bool = world.debug_stealth_scenario(id, "object_upgrade", "Upgrade_WitchkingMorgulBlade")
	world.debug_stealth_scenario(id, "unpause")
	hud.select_object(id)
	await _wait(1.5)
	var blade := {}
	for b in hud.get_command_buttons():
		if str(b.name) == "Command_WitchkingMorgulBlade":
			blade = b
	if blade.is_empty():
		print("TOUCH SELFTEST autocast double tap: SKIP (no Morgul Blade button; upgrade hook %s)" % upgraded)
		return out
	var w: Dictionary = hud.find_button_window(str(blade.frame))
	var at := Vector2(float(w.get("x", 0)), float(w.get("y", 0)))
	var touched: Dictionary = hud.touch_button_at(at) if w.get("found", false) else {}
	print("TOUCH SELFTEST autocast: Morgul Blade %s at %s: %s (upgrade hook %s)" % [blade.frame, at, JSON.stringify(touched), upgraded])
	if not touched.get("autocast", false):
		print("TOUCH SELFTEST autocast double tap: SKIP (the blade is not an autocast button here, state %s; upgrade hook %s)" % [blade.state, upgraded])
		return out
	var toggles0 := int(_controls.stats.autocast_taps)
	var auto0: bool = blade.auto_ability
	_touch(0, at, true)
	await _wait(0.06)
	_touch(0, at, false)
	await _wait(0.12)
	_touch(0, at, true)
	await _wait(0.06)
	_touch(0, at, false)
	await _wait(1.0)
	var auto1 := _auto_of(hud, "Command_WitchkingMorgulBlade")
	await _shot("9-autocast-on")
	print("TOUCH SELFTEST autocast double tap: auto %s -> %s, autocast taps +%d, placing / aiming %s" % [auto0, auto1, int(_controls.stats.autocast_taps) - toggles0,
		hud.get_placement().placing])
	if int(_controls.stats.autocast_taps) != toggles0 + 1:
		out.append("the double tap on the Morgul Blade was not an autocast tap")
	if auto1 == auto0:
		out.append("the double tap did not toggle the Morgul Blade's autocast")
	# and back
	await _tap(at)
	await _wait(0.1)
	await _tap(at)
	await _wait(1.0)
	var auto2 := _auto_of(hud, "Command_WitchkingMorgulBlade")
	print("TOUCH SELFTEST autocast double tap again: auto %s" % auto2)
	if auto2 != auto0:
		out.append("a second double tap did not toggle the autocast back")
	return out


func _auto_of(hud: Node, name: String) -> bool:
	for b in hud.get_command_buttons():
		if str(b.name) == name:
			return bool(b.auto_ability)
	return false


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


## lane IOS-15: two fingers `radius` px from `centre`, turned by `turn` radians in 12 frames
func _twist(centre: Vector2, radius: float, turn: float) -> void:
	var a := centre + Vector2(-radius, 0)
	var b := centre + Vector2(radius, 0)
	_touch(0, a, true)
	_touch(1, b, true)
	await get_tree().process_frame
	var pa := a
	var pb := b
	for i in range(1, 13):
		var r := Vector2(radius, 0).rotated(turn * i / 12.0)
		var na := centre - r
		var nb := centre + r
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
