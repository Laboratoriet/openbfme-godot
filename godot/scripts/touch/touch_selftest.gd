extends Node
## Lane IOS-2: `-- --touch --touch-selftest=<folder>` in a game (with --auto): plays the touch gestures as synthetic touch events, through the same
## Input path a phone's touches take, and reports what each did to the camera, plus a picture after each. Prints TOUCH SELFTEST PASS / FAIL.
## Lane IOS-10: last, a tap 6 pt beside the Palantir's key must be moved onto it by the tap assist and open the quit menu (closed again after).
## Lane IOS-21: then, with a builder selected, a hold on a side bar button and on the portrait shows their help while held and presses nothing; a tap
## still presses (the building's placement, cancelled again by a hold in the world: its right click); and a double tap on an autocast ability (the
## Witch-king's Morgul Blade, made for the test when the hooks allow it) toggles its autocast.
## Lane IOS-23: a building's placement by finger: the builder's build button tapped, a finger on the world puts the ghost GHOST_OFFSET_PT above it;
## dragged onto the player's own fortress (an invalid site) and lifted, the placement stays; dragged to a legal site and lifted, the structure stands
## at the ghost's point, not under the finger. Then a wall: a Men wall hub (made for the test), Begin Wall Span, a drag shows the span's ghost
## segments from the hub to the ghost's point, the lift builds them. The pictures of the drags mark the finger (a ring) and the ghost's point (a dot),
## drawn by this test only.
## Lane IOS-26: a lift no longer places: it shows ✓ / ✕ beside the ghost (off the HUD), and ✓ builds. On the fortress ✓ is dimmed and a tap on it is
## refused (the placement and the buttons stay); ✕ there cancels the placement (the build button starts it again). Pictures of the waiting ghost:
## touch-confirm-*.png.
## Lane IOS-35: with Options' One finger drag on "Move the view" (OpenBFMETouchDrag = pan, from the --options-file) step 3 checks that mode: a one-finger
## drag moves the camera (and is no box), a hold then a drag is the box; the taps and the hold as before. The placement steps then run in pan mode too
## (a ghost's drag moves the ghost, not the camera).
## Lane IOS-36 (after daisyhasacat/openbfme-godot facef81b): the refused ✓ on the fortress keeps the builder selected; the accepted ✓ deselects it.
## Lane IOS-40 ("Button taps", touch default "Preview what costs"): the builder's build button is a costing button: a tap shows its help and the gold ring
## and presses nothing; a second tap starts the placement. A tap elsewhere, and the arm window running out, disarm; the portrait (a quick button) acts at
## once; "Act at once" presses on the first tap. Pictures: touch-preview-*.png. The later steps press costing buttons with two taps (_press).
## Lane IOS-37: the command toolbar (inside the safe area at the top, 44 pt cells, off the HUD; each button's command reaches the game as its key's
## meta: Select army, Deselect, Stop, Home base, Last event, a control group made by a hold and selected by a tap, the menu; a hold shows the help and
## presses nothing; hidden under the quit menu). Pictures: touch-toolbar-*.

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
	print("TOUCH SELFTEST one finger drag: %s" % _controls.drag_mode)
	if _controls.drag_mode == "pan":
		# lane IOS-35: the drag moves the camera (no box); a hold, then a drag, is the box
		var cam0: Vector2 = hud.get_camera().position
		var drags0 := int(_controls.stats.drags)
		var from := mid + Vector2(-150, -60)
		var ground: Vector2 = hud.pixel_to_world(from)
		await _one_finger_drag(from, mid + Vector2(150, 60))
		var cam1: Vector2 = hud.get_camera().position
		var under: Vector2 = hud.pixel_to_world(mid + Vector2(150, 60))
		print("TOUCH SELFTEST finger pan: camera %s -> %s (moved %.1f); the ground under the finger %s, at the touch-down %s" % [cam0, cam1, cam0.distance_to(cam1), under, ground])
		if cam0.distance_to(cam1) < 1.0:
			failures.append("pan mode: a one-finger drag did not move the camera")
		if under.distance_to(ground) > 5.0:  # tolerance: the ground point round trip through the drawn camera and the terrain's heights (world units)
			failures.append("pan mode: the ground did not stay under the finger (%s, came down on %s)" % [under, ground])
		if int(_controls.stats.drags) != drags0:
			failures.append("pan mode: the one-finger drag was a box")
		await _shot("3c-after-finger-pan")
		await _hold_drag(mid + Vector2(-200, -120), mid + Vector2(200, 120))
		var cam2: Vector2 = hud.get_camera().position
		print("TOUCH SELFTEST hold-drag box: drags %d -> %d, camera moved %.1f" % [drags0, int(_controls.stats.drags), cam1.distance_to(cam2)])
		if cam1.distance_to(cam2) > 0.01:
			failures.append("pan mode: the hold-drag moved the camera")
		# the camera back where the finger pan found it: the later steps (the builder's walk to a placement's site) see the select mode's view
		hud.camera_look_at(cam0)
		await _wait(0.3)
	else:
		await _one_finger_drag(mid + Vector2(-200, -120), mid + Vector2(200, 120))
	# lane IOS-40: the box may have selected the fortress, whose radial bubbles then sit where the taps below go (portrait): those are costing buttons a
	# tap previews; the taps here are the world's
	if hud.has_method("deselect_all"):
		hud.deselect_all()
		await _wait(0.4)
	# and the taps go to open ground (in portrait the screen's middle is the fortress: a tap there selects it and its bubbles come up under the next)
	var open := _open_ground(hud, mid)
	await _tap(open)
	await _wait(0.5)
	await _tap(open + Vector2(40, 0))
	await _wait(0.05)
	await _tap(open + Vector2(40, 0))
	await _wait(0.5)
	await _hold(open)
	await _shot("4-after-taps")
	var s: Dictionary = _controls.stats
	print("TOUCH SELFTEST gestures: ", JSON.stringify(s))
	for k in ["drags", "taps", "double_taps", "holds", "pans", "zoom_notches"] + (["finger_pans", "box_arms"] if _controls.drag_mode == "pan" else []):
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
	# 7. lane IOS-23: placement by finger, a building and a wall span
	failures.append_array(await _placement_check(hud))
	failures.append_array(await _wall_check(hud))
	# 8. lane IOS-37: the command toolbar
	failures.append_array(await _toolbar_check(hud))
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
	# lane IOS-40: tap to preview, tap again to use (the touch default); "Act at once": a tap still presses, and the pointer it leaves opens no help
	await _wait(0.4)
	out.append_array(await _preview_check(hud, side, portrait))
	# a hold in the world stays the right click: it cancels the placement
	var mid := get_viewport().get_visible_rect().size * Vector2(0.5, 0.35)
	await _hold(mid)
	await _wait(0.5)
	print("TOUCH SELFTEST hold in the world while placing: placing %s" % hud.get_placement().placing)
	if hud.get_placement().placing:
		out.append("a hold in the world did not cancel the placement (no right click)")
	return out


## lane IOS-40: the side bar's build button `side` (a costing button) previews on the first tap and presses on the second; a tap elsewhere and the time out
## disarm; `portrait` (a quick button: no cost) acts at once; "Act at once" presses on the first tap. Leaves the placement on (the caller's hold cancels it)
func _preview_check(hud: Node, side: Vector2, portrait: Vector2) -> PackedStringArray:
	var out := PackedStringArray()
	var touched: Dictionary = hud.touch_button_at(side)
	print("TOUCH SELFTEST IOS-40 side bar button: %s; button taps %s" % [JSON.stringify(touched), _controls.button_taps])
	if not touched.get("costs", false):
		out.append("IOS-40: the builder's build button does not cost (%s)" % JSON.stringify(touched))
	if not Rect2(touched.get("rect", Rect2())).has_point(side):
		out.append("IOS-40: the build button's rectangle %s does not hold its point %s" % [touched.get("rect"), side])
	var mode0: String = _controls.button_taps
	_controls.set_button_taps("costs")
	var uses0 := int(_controls.stats.armed_uses)
	# a. the first tap: help and ring, nothing pressed
	await _tap(side)
	await _wait(0.5)  # the help box's opening and the ring's
	var armed: Dictionary = _controls.armed_state()
	var help: Dictionary = _help(hud)
	await _shot("preview-armed-" + _orient())
	print("TOUCH SELFTEST IOS-40 first tap: armed %s, help shown %s name \"%s\", placing %s, ring %s" % [armed.armed, help.get("shown"), help.get("name"),
		hud.get_placement().placing, JSON.stringify(armed.get("ring", {}))])
	if not armed.armed:
		out.append("IOS-40: the first tap on the build button did not arm it")
	if not help.get("shown", false):
		out.append("IOS-40: no help after the first tap")
	if hud.get_placement().placing:
		out.append("IOS-40: the first tap pressed the build button")
	var ring: Dictionary = armed.get("ring", {})
	if not ring.get("visible", false) or float(ring.get("alpha", 0.0)) < 0.9:
		out.append("IOS-40: no gold ring around the armed button (%s)" % JSON.stringify(ring))
	elif Vector2(ring.centre).distance_to(Rect2(touched.rect).get_center()) > 2.0 or float(ring.radius) < Rect2(touched.rect).size.x * 0.5:
		out.append("IOS-40: the ring is not around the button (%s, the button %s)" % [JSON.stringify(ring), touched.rect])
	# b. a tap elsewhere (the world above the Palantir) disarms
	var world_px := get_viewport().get_visible_rect().size * Vector2(0.5, 0.3)
	await _tap(world_px)
	await _wait(0.4)
	print("TOUCH SELFTEST IOS-40 tap elsewhere: armed %s, help shown %s" % [_controls.armed_state().armed, _help(hud).get("shown")])
	if _controls.armed_state().armed or _help(hud).get("shown", false):
		out.append("IOS-40: a tap elsewhere did not disarm")
	await _shot("preview-disarmed-" + _orient())
	# c. the time out: armed again, nothing for ARM_MS: disarmed, nothing pressed
	await _select_builder(hud)
	await _tap(side)
	await _wait(_controls.ARM_MS / 1000.0 + 0.6)
	print("TOUCH SELFTEST IOS-40 time out: armed %s, help shown %s, placing %s" % [_controls.armed_state().armed, _help(hud).get("shown"), hud.get_placement().placing])
	if _controls.armed_state().armed or _help(hud).get("shown", false) or hud.get_placement().placing:
		out.append("IOS-40: the arm did not run out after %d ms" % _controls.ARM_MS)
	# d. a quick button (the portrait) acts at once: no arm
	if portrait.is_finite():
		var arms0 := int(_controls.stats.arms)
		await _tap(portrait)
		await _wait(0.4)
		print("TOUCH SELFTEST IOS-40 portrait tap: %s, arms +%d" % [JSON.stringify(hud.touch_button_at(portrait)), int(_controls.stats.arms) - arms0])
		if int(_controls.stats.arms) != arms0:
			out.append("IOS-40: the portrait (no cost) was previewed")
		await _select_builder(hud)
	# e. tap, read, tap: the second tap presses (a placement starts), the ring flashes and goes, the help goes
	await _tap(side)
	await _wait(0.9)
	await _tap(side)
	await _wait(0.8)
	var placing: bool = hud.get_placement().placing
	await _shot("preview-used-" + _orient())
	print("TOUCH SELFTEST IOS-40 second tap: placing %s, armed %s, help shown %s, uses +%d" % [placing, _controls.armed_state().armed, _help(hud).get("shown"),
		int(_controls.stats.armed_uses) - uses0])
	if not placing:
		out.append("IOS-40: the second tap did not press the build button (no placement)")
	if _controls.armed_state().armed or _help(hud).get("shown", false):
		out.append("IOS-40: the help or the arm stayed after the second tap")
	# f. "Act at once": one tap presses (after a hold cancels this placement, and disarms); the pointer the tap leaves on it opens no help
	await _hold(get_viewport().get_visible_rect().size * Vector2(0.5, 0.35))
	await _wait(0.5)
	await _select_builder(hud)
	_controls.set_button_taps("act")
	await _tap(side)
	await _wait(0.8)
	print("TOUCH SELFTEST IOS-40 act at once: placing %s, help shown %s" % [hud.get_placement().placing, _help(hud).get("shown")])
	if not hud.get_placement().placing:
		out.append("IOS-40: \"Act at once\": a tap did not press the build button")
	if _help(hud).get("shown", false):
		out.append("the help showed after a tap")
	_controls.set_button_taps(mode0)
	return out


## a window point on open ground, and 40 px right of it too (no HUD, no object under either: InGameHudNode.nearest_button's reasons), the nearest such
## of a few to `near`; `near` when none is
func _open_ground(hud: Node, near: Vector2) -> Vector2:
	var size := get_viewport().get_visible_rect().size
	var best := near
	var best_d := INF
	for fy in [0.5, 0.4, 0.6, 0.7, 0.3, 0.8]:
		for fx in [0.5, 0.35, 0.65, 0.2, 0.8]:
			var p := size * Vector2(fx, fy)
			var ok := true
			for q in [p, p + Vector2(40, 0)]:
				var r: Dictionary = hud.nearest_button(q, 0.0) if hud.has_method("nearest_button") else {}
				ok = ok and _on_world(hud, q) and not (str(r.get("reason", "")) in ["on an object", "hit"])
			if ok and p.distance_to(near) < best_d:
				best = p
				best_d = p.distance_to(near)
	print("TOUCH SELFTEST open ground for the taps: %s" % best)
	return best


## "landscape" or "portrait": the pictures' suffix
func _orient() -> String:
	var size := get_viewport().get_visible_rect().size
	return "portrait" if size.y > size.x else "landscape"


## lane IOS-37: the metas the game made last (InGameHudNode.get_state().keys.recent, the last 32)
func _metas(hud: Node) -> Array:
	return Array(hud.get_state().get("keys", {}).get("recent", PackedStringArray()))


## lane IOS-37: the centre of toolbar button `id` (Vector2.INF: not shown)
func _tb(id: String) -> Vector2:
	var t = _controls._toolbar
	if t == null:
		return Vector2.INF
	var b: Dictionary = t.state().buttons.get(id, {})
	return Rect2(b.rect).get_center() if b.get("visible", false) else Vector2.INF


## lane IOS-37: a tap on toolbar button `id`; then whether the game made meta `meta` ("" none expected) since the tap
func _tb_tap(hud: Node, id: String, meta: String) -> bool:
	var before := _metas(hud).size()
	var count0 := _metas(hud).count(meta) if meta != "" else 0
	await _tap(_tb(id))
	await _wait(0.6)
	if meta == "":
		return true
	var after := _metas(hud)
	var made: bool = after.count(meta) > count0 or (after.size() >= 32 and before >= 32 and after.back() == meta)
	print("TOUCH SELFTEST IOS-37 toolbar %s: meta %s %s (recent %s)" % [id, meta, "made" if made else "NOT made", after.slice(maxi(0, after.size() - 4))])
	return made


## lane IOS-37: the command toolbar
func _toolbar_check(hud: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if not hud.has_method("command_hotkey"):
		out.append("IOS-37: the extension has no command_hotkey (built before lane IOS-37)")
		return out
	for i in 20:
		if _controls._toolbar != null and _controls._toolbar.is_shown():
			break
		await _wait(0.1)
	var t = _controls._toolbar
	if t == null or not t.is_shown():
		out.append("IOS-37: no command toolbar in the game")
		return out
	var cam_back: Vector2 = hud.get_camera().position  # Home base and Last event move the view; the later steps want this one
	var st: Dictionary = t.state()
	var safe: Rect2 = _controls._safe_rect()
	var r: Rect2 = st.rect
	var px: float = _controls._scale
	print("TOUCH SELFTEST IOS-37 toolbar: %s in the safe area %s (%.1f px per point)" % [r, safe, px])
	if not safe.encloses(r):
		out.append("IOS-37: the toolbar %s leaves the safe area %s" % [r, safe])
	if r.position.y - safe.position.y > 12.0 * px:
		out.append("IOS-37: the toolbar is not at the top edge (%s)" % r)
	var view := get_viewport().get_visible_rect()
	if r.end.x > safe.position.x + safe.size.x * 0.6 + 1.0:  # tolerance: a pixel of the points' rounding
		out.append("IOS-37: the toolbar reaches past 60 %% of the safe width (%.0f of %.0f): the game's messages' corner" % [r.end.x, safe.size.x])
	for id in st.buttons:
		var b: Dictionary = st.buttons[id]
		if not b.visible:
			continue
		var br: Rect2 = b.rect
		if absf(br.size.x - 44.0 * px) > 0.5 or absf(br.size.y - 44.0 * px) > 0.5:  # tolerance: half a pixel of the points' rounding
			out.append("IOS-37: toolbar button %s is not a 44 pt cell (%s)" % [id, br.size])
		if str(hud.touch_button_at(br.get_center()).get("kind", "")) != "":
			out.append("IOS-37: toolbar button %s lies on a HUD button" % id)
	await _shot("toolbar-" + _orient())
	# Select army, Deselect
	if not await _tb_tap(hud, "army", "SELECT_ALL"):
		out.append("IOS-37: Select army made no SELECT_ALL")
	var army: Array = hud.get_selection()
	print("TOUCH SELFTEST IOS-37 select army: %d selected" % army.size())
	if army.is_empty():
		out.append("IOS-37: Select army selected nothing")
	await _tb_tap(hud, "deselect", "")
	if not hud.get_selection().is_empty():
		out.append("IOS-37: Deselect left %d selected" % hud.get_selection().size())
	await _wait(0.4)
	if t.is_enabled("deselect") or t.is_enabled("stop"):
		out.append("IOS-37: Deselect / Stop are not disabled with nothing selected")
	await _shot("toolbar-disabled-" + _orient())
	# a hold shows the help and presses nothing
	await _tb_tap(hud, "army", "SELECT_ALL")
	var metas0 := _metas(hud).duplicate()
	_touch(0, _tb("stop"), true)
	await _wait(0.75)
	var tip := str(t.state().tip)
	await _shot("toolbar-help-" + _orient())
	_touch(0, _tb("stop"), false)
	await _wait(0.4)
	print("TOUCH SELFTEST IOS-37 hold on Stop: tip \"%s\"" % tip)
	if tip == "" or not tip.begins_with("Stop"):
		out.append("IOS-37: a hold on Stop showed no help (\"%s\")" % tip)
	if _metas(hud).count("STOP") != metas0.count("STOP"):
		out.append("IOS-37: the hold on Stop pressed it")
	if not await _tb_tap(hud, "stop", "STOP"):
		out.append("IOS-37: Stop made no STOP")
	# control groups: the row; a hold makes group 3 (a ring fills), a tap selects it
	await _tb_tap(hud, "groups", "")
	if not t.state().drawer or not _tb("group3").is_finite():
		out.append("IOS-37: Groups did not open the groups' row")
		return out
	var made0 := int(_controls.stats.groups_made)
	_touch(0, _tb("group3"), true)
	await _wait(0.32)
	await _shot("toolbar-group-hold-" + _orient())
	await _wait(0.4)
	_touch(0, _tb("group3"), false)
	await _wait(0.3)
	await _shot("toolbar-group-made-" + _orient())
	var made: bool = _metas(hud).has("CREATE_TEAM3")
	print("TOUCH SELFTEST IOS-37 hold on group 3: CREATE_TEAM3 %s, groups made +%d, tip \"%s\"" % [made, int(_controls.stats.groups_made) - made0, t.state().tip])
	if not made or int(_controls.stats.groups_made) != made0 + 1:
		out.append("IOS-37: a hold on group 3 did not make the group")
	await _tb_tap(hud, "deselect", "")
	if not await _tb_tap(hud, "group3", "SELECT_TEAM3"):
		out.append("IOS-37: a tap on group 3 made no SELECT_TEAM3")
	print("TOUCH SELFTEST IOS-37 group 3 selected: %d (the army had %d)" % [hud.get_selection().size(), army.size()])
	if hud.get_selection().size() != army.size():
		out.append("IOS-37: group 3 selected %d, the army it was made from %d" % [hud.get_selection().size(), army.size()])
	await _tb_tap(hud, "groups", "")
	# the view keys
	if not await _tb_tap(hud, "base", "VIEW_HOME_BASE"):
		out.append("IOS-37: Home base made no VIEW_HOME_BASE")
	if not await _tb_tap(hud, "event", "VIEW_LAST_RADAR_EVENT"):
		out.append("IOS-37: Last event made no VIEW_LAST_RADAR_EVENT")
	# Attack move: the selection's Attack Move button's hotkey (a horde made for the test where the hooks allow it)
	var game: Node = get_tree().current_scene
	var world = game.get("_world") if game != null else null
	var horde := -1
	if world != null and int(game.get("_local_index")) >= 0:
		var cam: Vector2 = hud.get_camera().position
		for name in ["GondorFighterHorde", "GondorSoldierHorde", "GondorArcherHorde"]:
			horde = int(world.create_object(name, int(game.get("_local_index")), cam.x - 40.0, cam.y + 30.0, 0.0))
			if horde > 0:
				break
	if horde > 0:
		await _wait(0.5)
		hud.select_object_with_message(horde)
		await _wait(1.2)
		var hk: Dictionary = hud.command_hotkey("ATTACK_MOVE")
		var sent0: int = t.sent.size()
		await _tb_tap(hud, "attack", "")
		print("TOUCH SELFTEST IOS-37 attack move: hotkey %s, enabled %s, sent %s" % [hk, t.is_enabled("attack"), t.sent.slice(sent0)])
		if not t.is_enabled("attack") or t.sent.size() != sent0 + 1:
			out.append("IOS-37: Attack move was not pressed for a horde (%s)" % [hk])
		await _hold(view.size * Vector2(0.5, 0.4))  # out of the attack-move mode (its right click)
	else:
		print("TOUCH SELFTEST IOS-37 attack move: SKIP (no horde template the test hooks make)")
	# Menu: the quit menu opens, and the toolbar hides under it
	await _tb_tap(hud, "menu", "")
	await _wait(1.0)
	var opened: bool = game != null and game.get("_quit_open") == true
	print("TOUCH SELFTEST IOS-37 menu: quit menu %s, toolbar shown %s" % [opened, t.is_shown()])
	if not opened:
		out.append("IOS-37: Menu did not open the quit menu")
	elif t.is_shown():
		out.append("IOS-37: the toolbar shows over the quit menu")
	if opened and game.has_method("_close_quit_menu"):
		game._close_quit_menu()
		await _wait(1.0)
	hud.camera_look_at(cam_back)
	await _wait(0.5)
	return out


## lane IOS-40: a press of the HUD button at `at` as the option has it: two taps on a previewed one, one on any other
func _press(hud: Node, at: Vector2) -> void:
	await _tap(at)
	if _controls.armed_state().armed:
		await _wait(0.45)  # past the double tap's window: a use, never an autocast toggle
		await _tap(at)


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


## lane IOS-23: the self-test's marker in its pictures: a ring where the finger is, a line up to the ghost's point and a dot there
class FingerMarker:
	extends Control
	var finger := Vector2.INF
	var ghost := Vector2.INF

	func _draw() -> void:
		if not finger.is_finite():
			return
		draw_line(finger, ghost, Color(1, 1, 1, 0.7), 2.0)
		draw_arc(finger, 22.0, 0.0, TAU, 40, Color(1.0, 0.8, 0.1), 3.0)
		draw_circle(ghost, 5.0, Color(1, 1, 1))


var _marker: FingerMarker = null


## the marker at finger `at` (Vector2.INF: hidden)
func _mark(at: Vector2) -> void:
	if _marker == null:
		var layer := CanvasLayer.new()
		layer.layer = 128
		add_child(layer)
		_marker = FingerMarker.new()
		_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_marker)
	_marker.finger = at
	_marker.ghost = _controls.ghost_point(at) if at.is_finite() else Vector2.INF
	_marker.queue_redraw()


## the local player's first builder (_builder_picture's rule), selected as a player's click selects (the logic's selection too: a construct
## message's builder is its first object); its id (-1: none)
func _select_builder(hud: Node) -> int:
	var game: Node = get_tree().current_scene
	var world = game.get("_world") if game != null else null
	if world == null:
		return -1
	for o in world.get_player_objects(str(game.get("_local_name"))):
		var t := str(o.template)
		if t.contains("Porter") or t.contains("Worker"):
			hud.select_object_with_message(int(o.id))
			await _wait(1.5)
			return int(o.id)
	return -1


## the first DOZER_CONSTRUCT button of the side command bar on screen: { position, name } ({} none)
func _build_button(hud: Node) -> Dictionary:
	for b in hud.get_command_buttons():
		if not b.in_palantir and str(b.command) == "DOZER_CONSTRUCT":
			var w: Dictionary = hud.find_button_window(str(b.frame))
			if w.get("found", false):
				return {"position": Vector2(float(w.x), float(w.y)), "name": str(b.name)}
	return {}


## the ids of the local player's objects
func _object_ids(world, player: String) -> Dictionary:
	var ids := {}
	for o in world.get_player_objects(player):
		ids[int(o.id)] = true
	return ids


## finger 0 (down) from `from` to `to` in `steps` frames
func _finger_to(from: Vector2, to: Vector2, steps := 10) -> void:
	var p := from
	for i in range(1, steps + 1):
		var n := from.lerp(to, float(i) / steps)
		_drag(0, n, n - p)
		p = n
		await get_tree().process_frame


## the window point is on the world (not the HUD) and inside the view
func _on_world(hud: Node, at: Vector2) -> bool:
	return get_viewport().get_visible_rect().has_point(at) and bool(hud.touch_placement_at(at).get("world", false))


## lane IOS-23: a building placed by a finger: the ghost follows GHOST_OFFSET_PT above it, an invalid lift keeps the placement, a legal lift builds
## at the ghost's point
func _placement_check(hud: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if not hud.has_method("touch_placement_at"):
		out.append("the extension has no touch_placement_at (built before lane IOS-23)")
		return out
	var game: Node = get_tree().current_scene
	var world = game.get("_world") if game != null else null
	var local := str(game.get("_local_name")) if game != null else ""
	if world == null or await _select_builder(hud) < 0:
		print("TOUCH SELFTEST placement: SKIP (no builder of the local player)")
		return out
	var button := _build_button(hud)
	if button.is_empty():
		out.append("placement: no side bar build button of the builder on screen")
		return out
	await _press(hud, button.position)
	await _wait(0.8)
	var pl: Dictionary = hud.get_placement()
	if not pl.placing:
		out.append("placement: a tap on %s started no placement" % button.name)
		return out
	var template := str(pl.template)
	var size := get_viewport().get_visible_rect().size
	var off := Vector2(0.0, _controls.GHOST_OFFSET_PT * _controls._scale)
	print("TOUCH SELFTEST placement: %s from %s, ghost offset %s px (%.0f pt at %.1f px per point)" % [template, button.name, off, _controls.GHOST_OFFSET_PT, _controls._scale])

	# a. an invalid site: the ghost dragged onto the player's own fortress and lifted: retail's refusal, the placement stays
	var fort := Vector2.INF
	for o in world.get_player_objects(local):
		if o.commandcenter:
			fort = hud.world_to_pixel(Vector2(float(o.x), float(o.y)))
			break
	var lifts0 := int(_controls.stats.place_lifts)
	if fort.is_finite() and _on_world(hud, fort) and _on_world(hud, fort + off) and _on_world(hud, fort + off + Vector2(0, 30)):
		_touch(0, fort + off + Vector2(0, 30), true)
		await get_tree().process_frame
		await _finger_to(fort + off + Vector2(0, 30), fort + off)
		await _wait(0.4)
		var legal := int(hud.get_placement().legal)
		_mark(fort + off)
		await _shot("10-place-invalid")
		_mark(Vector2.INF)
		_touch(0, fort + off, false)
		await _wait(0.8)
		var still: bool = hud.get_placement().placing
		var waiting := _confirm_state()
		print("TOUCH SELFTEST placement on the fortress: ghost code %d, lifted: placing %s, lifts +%d, confirm %s" % [legal, still,
			int(_controls.stats.place_lifts) - lifts0, JSON.stringify(waiting)])
		await _shot("confirm-invalid")
		if legal == 0:
			out.append("placement: the ghost on the fortress was judged legal")
		if not still:
			out.append("placement: a lift on an invalid site ended the placement")
		if int(_controls.stats.place_lifts) != lifts0 + 1:
			out.append("placement: the lift on the fortress was no placement lift")
		out.append_array(_confirm_check(hud, waiting, fort, "on the fortress"))
		if waiting.get("build_enabled", true):
			out.append("placement: ✓ is not dimmed on the fortress (ghost code %d)" % legal)
		# lane IOS-26: ✓ on the red ghost: retail's refusal, the placement and the buttons stay
		if waiting.get("shown", false):
			await _tap(waiting.build)
			await _wait(0.8)
			var after := _confirm_state()
			print("TOUCH SELFTEST ✓ on the fortress: placing %s, confirm shown %s" % [hud.get_placement().placing, after.get("shown")])
			if not hud.get_placement().placing:
				out.append("placement: ✓ on the fortress ended the placement")
			if not after.get("shown", false):
				out.append("placement: ✓ / ✕ went after a refused ✓")
			if hud.get_selection().is_empty():
				out.append("placement: a refused ✓ deselected the builder (IOS-36 deselects after an accepted one only)")
			# ✕ cancels the placement; the build button starts it again
			await _tap(after.get("cancel", waiting.cancel))
			await _wait(0.8)
			print("TOUCH SELFTEST ✕: placing %s, confirm shown %s" % [hud.get_placement().placing, _confirm_state().get("shown")])
			if hud.get_placement().placing:
				out.append("placement: ✕ did not cancel the placement")
			await _press(hud, button.position)
			await _wait(0.8)
			if not hud.get_placement().placing:
				out.append("placement: the build button did not start the placement again after ✕")
				return out
	else:
		print("TOUCH SELFTEST placement on the fortress: SKIP (the fortress at %s is not on screen with a finger below it)" % fort)

	# b. a legal site: finger down, the ghost above it; dragged until the ghost is legal, lifted: the structure at the ghost's point
	var start := size * Vector2(0.5, 0.62)
	var ids0 := _object_ids(world, local)
	_touch(0, start, true)
	await _wait(0.3)
	var p0: Dictionary = hud.get_placement()
	var ghost0 := Vector2(float(p0.x), float(p0.y))
	var want0: Vector2 = hud.pixel_to_world(_controls.ghost_point(start))
	var under0: Vector2 = hud.pixel_to_world(start)
	print("TOUCH SELFTEST placement drag: finger %s (world %s), ghost at %s, the offset point's world %s" % [start, under0, ghost0, want0])
	# tolerance: the ghost's site is PlaceEventTranslator's terrain pick of the pointer through the drawn camera, pixel_to_world the HUD's of the same pixel
	if ghost0.distance_to(want0) > 4.0:
		out.append("placement: the ghost %s is not at the offset point's ground %s" % [ghost0, want0])
	if ghost0.distance_to(under0) < 20.0:
		out.append("placement: the ghost %s is under the finger %s" % [ghost0, under0])
	var finger := start
	var legal_at := Vector2.INF
	var shot := false
	for c in [start + Vector2(-200, 40), start + Vector2(220, 30), start + Vector2(-380, -80), start + Vector2(380, -80), start + Vector2(0, 110),
			start + Vector2(-120, -140), start + Vector2(140, -150)]:
		await _finger_to(finger, c)
		finger = c
		await _wait(0.35)
		if not shot:
			shot = true
			_mark(finger)
			await _shot("11-place-drag")
			_mark(Vector2.INF)
		if int(hud.get_placement().legal) == 0 and _on_world(hud, _controls.ghost_point(finger)):
			legal_at = finger
			break
	var want: Vector2 = hud.pixel_to_world(_controls.ghost_point(finger))
	var under: Vector2 = hud.pixel_to_world(finger)
	_mark(finger)
	await _shot("12-place-before-lift")
	_mark(Vector2.INF)
	_touch(0, finger, false)
	await _wait(0.8)
	# lane IOS-26: the lift places nothing; ✓ / ✕ wait beside the ghost
	var waiting := _confirm_state()
	var code := int(hud.get_placement().legal)  # the ghost's own judgement now (a unit may have walked onto the site since the drag)
	await _shot("confirm-legal")
	print("TOUCH SELFTEST placement lift: placing %s, ghost code %d, confirm %s" % [hud.get_placement().placing, code, JSON.stringify(waiting)])
	if not hud.get_placement().placing:
		out.append("placement: the lift placed the building without ✓")
	out.append_array(_confirm_check(hud, waiting, _controls.ghost_point(finger), "on a legal site"))
	if bool(waiting.get("build_enabled", false)) != (code == 0):
		out.append("placement: ✓ %s while the ghost's code is %d" % ["enabled" if waiting.get("build_enabled", false) else "dimmed", code])
	if waiting.get("shown", false):
		await _tap(waiting.build)
	await _wait(1.5)
	await _shot("13-place-after-confirm")
	if not legal_at.is_finite():
		out.append("placement: no legal site for %s along the drag" % template)
		if hud.get_placement().placing:
			await _hold(size * Vector2(0.5, 0.35))
		return out
	var made := {}
	var best := INF
	for o in world.get_player_objects(local):
		if not ids0.has(int(o.id)) and o.structure:
			var d := Vector2(float(o.x), float(o.y)).distance_to(want)
			if d < best:
				best = d
				made = o
	print("TOUCH SELFTEST placement lift: finger %s (world %s), ghost point world %s: placing %s, new structure %s at %.1f from the ghost point, %.1f from the finger" % [
		finger, under, want, hud.get_placement().placing, made.get("template", "none"),
		best, Vector2(float(made.get("x", 0)), float(made.get("y", 0))).distance_to(under) if not made.is_empty() else -1.0])
	if hud.get_placement().placing:
		out.append("placement: the legal lift did not place (the placement is still on)")
	# tolerance: the site is the terrain point of the click's pixel; the logic may move a structure a little onto its footprint's cell grid
	if made.is_empty() or best > 12.0:
		out.append("placement: no new structure at the ghost's point %s (nearest %.1f away)" % [want, best])
	# lane IOS-36 (after daisyhasacat/openbfme-godot facef81b): the accepted ✓ deselected the builder
	var selection: Array = hud.get_selection()
	print("TOUCH SELFTEST IOS-36 after the accepted ✓: selection %s, builder deselects %d" % [selection, int(_controls.stats.builder_deselects)])
	if hud.has_method("deselect_builders") and (not selection.is_empty() or int(_controls.stats.builder_deselects) != 1):
		out.append("placement: the builder is still selected after an accepted ✓ (IOS-36): %s" % [selection])
	return out


## lane IOS-23: a wall span by finger: a Men wall hub (MenWallHubSmall, test_qa2fix_walls.cpp's) made for the local player, Begin Wall Span tapped, a drag
## shows the span's ghost segments from the hub to the ghost's point, the lift builds the span. SKIPs, saying so, where the test hooks refuse
func _wall_check(hud: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var game: Node = get_tree().current_scene
	var world = game.get("_world") if game != null else null
	if world == null or int(game.get("_local_index")) < 0 or not hud.has_method("touch_placement_at"):
		print("TOUCH SELFTEST wall: SKIP (no game world / local player)")
		return out
	var local := str(game.get("_local_name"))
	var size := get_viewport().get_visible_rect().size
	# the hub on open ground: the first of a few points whose ground has none of the player's objects near (the fortress sits left of the middle)
	var hub_px := Vector2.INF
	var hub_at := Vector2.INF
	for c in [Vector2(0.55, 0.3), Vector2(0.7, 0.3), Vector2(0.45, 0.25), Vector2(0.6, 0.45), Vector2(0.75, 0.5), Vector2(0.8, 0.25), Vector2(0.4, 0.75),
			Vector2(0.85, 0.65)]:
		var px: Vector2 = size * c
		var at: Vector2 = hud.pixel_to_world(px)
		var clear := at.is_finite() and _on_world(hud, px)
		for o in world.get_player_objects(local):
			if clear and Vector2(float(o.x), float(o.y)).distance_to(at) < 70.0:
				clear = false
		print("TOUCH SELFTEST wall: hub site %s (world %s): %s" % [px, at, "open" if clear else "taken"])
		if clear:
			hub_px = px
			hub_at = at
			break
	if not hub_px.is_finite():
		print("TOUCH SELFTEST wall: SKIP (no open ground on screen for the hub)")
		return out
	var hub := int(world.create_object("MenWallHubSmall", int(game.get("_local_index")), hub_at.x, hub_at.y, 0.0))
	if hub <= 0:
		print("TOUCH SELFTEST wall: SKIP (create_object refused: %s)" % str(world.call("get_command_errors") if world.has_method("get_command_errors") else ""))
		return out
	await _wait(0.5)
	hud.select_object_with_message(hub)
	await _wait(1.5)
	# a structure's command buttons are radial bubbles over it (HUD-6): Begin Wall Span is the hub's DOZER_CONSTRUCT bubble
	var bubble := {}
	for b in hud.get_hud6_state().get("radial", {}).get("buttons", []):
		if str(b.command) == "DOZER_CONSTRUCT":
			bubble = b
			break
	if bubble.is_empty():
		out.append("wall: the hub shows no Begin Wall Span (DOZER_CONSTRUCT) bubble: %s" % JSON.stringify(hud.get_hud6_state().get("radial", {}).get("buttons", [])))
		return out
	var rect: Rect2 = bubble.rect
	var at_bubble := rect.position + rect.size * 0.5
	print("TOUCH SELFTEST wall: %s bubble at %s for a finger: %s" % [bubble.name, at_bubble, JSON.stringify(hud.touch_button_at(at_bubble))])
	await _press(hud, at_bubble)
	await _wait(0.8)
	var probe: Dictionary = hud.touch_placement_at(size * Vector2(0.6, 0.6))
	print("TOUCH SELFTEST wall: hub %d at %s (pixel %s), %s tapped: %s" % [hub, hub_at, hub_px, bubble.name, JSON.stringify(probe)])
	if not probe.get("placing", false) or not probe.get("line_build", false):
		out.append("wall: %s started no line build" % bubble.name)
		if probe.get("placing", false):
			await _hold(size * Vector2(0.5, 0.35))
		return out
	var off := Vector2(0.0, _controls.GHOST_OFFSET_PT * _controls._scale)
	var ids0 := _object_ids(world, local)
	# the finger starts with the ghost just right of the hub and drags it along; first legal span wins (every tile's code 0)
	var finger := hub_px + Vector2(60, 0) + off
	_touch(0, finger, true)
	await _wait(0.3)
	var good := false
	var tiles := 0
	var shot := false
	var reach := minf(320.0, size.x * 0.25)  # a span the view holds in portrait too
	for end in [hub_px + Vector2(reach, 0), hub_px + Vector2(reach, -120), hub_px + Vector2(reach, 120), hub_px + Vector2(0, -220), hub_px + Vector2(-reach, 0)]:
		var to: Vector2 = end + off
		if not get_viewport().get_visible_rect().has_point(to):
			continue  # a finger stays on the screen
		await _finger_to(finger, to, 14)
		finger = to
		await _wait(0.5)
		var ghost: Dictionary = hud.get_placement_ghost_state()
		var icons: Array = ghost.get("icons", [])
		var worst := 0
		for i in icons:
			worst = maxi(worst, int(i.get("code", 0)))
		tiles = icons.size()
		print("TOUCH SELFTEST wall drag: ghost point %s: %d ghost segments, worst code %d" % [_controls.ghost_point(finger), tiles, worst])
		if not shot and tiles >= 2:
			shot = true
			_mark(finger)
			await _shot("14-wall-preview")
			_mark(Vector2.INF)
		if tiles >= 2 and worst == 0 and _on_world(hud, _controls.ghost_point(finger)):
			good = true
			break
	var want: Vector2 = hud.pixel_to_world(_controls.ghost_point(finger))
	_mark(finger)
	await _shot("15-wall-before-lift")
	_mark(Vector2.INF)
	_touch(0, finger, false)
	await _wait(0.8)
	# lane IOS-26: the lift builds nothing; ✓ / ✕ wait beside the span's end (✓ never dimmed for a span)
	var waiting := _confirm_state()
	await _shot("confirm-wall")
	print("TOUCH SELFTEST wall lift: placing %s, confirm %s" % [hud.get_placement().placing, JSON.stringify(waiting)])
	if not hud.get_placement().placing:
		out.append("wall: the lift built the span without ✓")
	out.append_array(_confirm_check(hud, waiting, _controls.ghost_point(finger), "for a wall span"))
	if not waiting.get("build_enabled", false):
		out.append("wall: ✓ is dimmed for a span")
	if waiting.get("shown", false):
		await _tap(waiting.build)
	await _wait(2.0)
	await _shot("16-wall-after-confirm")
	var walls := 0
	var far := 0.0
	for o in world.get_player_objects(local):
		if not ids0.has(int(o.id)) and int(o.id) != hub:
			walls += 1
			far = maxf(far, Vector2(float(o.x), float(o.y)).distance_to(hub_at))
	var span := hub_at.distance_to(want)
	print("TOUCH SELFTEST wall lift: span %s -> %s (%.0f long), %d segments shown, legal %s: placing %s, %d new objects, the farthest %.0f from the hub" % [
		hub_at, want, span, tiles, good, hud.get_placement().placing, walls, far])
	if tiles < 2:
		out.append("wall: the drag showed no wall line (%d ghost segments)" % tiles)
	if not good:
		out.append("wall: no legal span along the drag")
		if hud.get_placement().placing:
			await _hold(size * Vector2(0.5, 0.35))
		return out
	if hud.get_placement().placing:
		out.append("wall: the lift did not build (the placement is still on)")
	# tolerance: the span ends on a whole tile, at most a tile (the segment's length, ~ 40) short of or past the ghost's point
	if walls < 2 or absf(far - span) > 60.0:
		out.append("wall: the span was not built to the ghost's point (%d new objects, farthest %.0f, span %.0f)" % [walls, far, span])
	return out


## lane IOS-26: the confirm buttons' state ({} before the touch layer made them)
func _confirm_state() -> Dictionary:
	return _controls._confirm.state() if _controls._confirm != null else {}


## lane IOS-26: ✓ / ✕ show beside the waiting ghost at `ghost` (window pixels), at least 44 pt, inside the view and off the HUD (their centres and
## their discs' edges)
func _confirm_check(hud: Node, s: Dictionary, ghost: Vector2, where: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not s.get("shown", false):
		out.append("placement %s: no ✓ / ✕ after the lift" % where)
		return out
	# tolerance: the ghost's pixel is its ground point's round trip through the drawn camera (world_to_pixel's whole pixels)
	if Vector2(s.ghost).distance_to(ghost) > 2.0:
		out.append("placement %s: the buttons wait at %s, not at the ghost %s" % [where, s.ghost, ghost])
	var px: float = _controls._scale
	if float(s.hit_radius) * 2.0 < 44.0 * px:
		out.append("placement %s: the buttons' targets are under 44 pt" % where)
	var r := float(s.diameter) * 0.5
	var view := get_viewport().get_visible_rect()
	for k in ["build", "cancel"]:
		var c: Vector2 = s[k]
		for p in [c, c + Vector2(r, 0), c - Vector2(r, 0), c + Vector2(0, r), c - Vector2(0, r)]:
			if not view.has_point(p) or not bool(hud.touch_placement_at(p).get("world", false)):
				out.append("placement %s: %s at %s reaches off the view or onto the HUD (%s)" % [where, k, c, p])
				break
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


## lane IOS-35: a finger held still past the hold, then dragged from `from` to `to` (in pan mode the selection box)
func _hold_drag(from: Vector2, to: Vector2) -> void:
	_touch(0, from, true)
	await _wait(0.7)
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
