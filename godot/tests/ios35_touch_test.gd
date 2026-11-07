## Headless test of lane IOS-35 in the touch layer (scripts/touch/touch_controls.gd): Options > Interface > "One finger drag" (OpenBFMETouchDrag), the
## one-finger pan of daisyhasacat/openbfme-godot 607d6406 as an option, against a stand-in HUD: no game, no extension needed.
##  * the option: game_options.gd's key (default "select", choices select / pan), shown only where the touch controls are on;
##  * "select" (the default): a one-finger drag is the selection box, as before;
##  * "pan", on the battlefield: a one-finger drag moves the camera with the ground under the finger (from where it came down) and presses nothing; a
##    tap is the left click as before; a hold then a drag is the selection box (the left press where the finger came down), a hold lifted without a
##    drag the right click (at the lift, not while held), a hold that drifts within the slop too; two fingers still pan;
##  * "pan" leaves alone: a drag or a hold that starts on the HUD (a drag there is the left drag, a hold on a button its help), a placement's ghost drag
##    (IOS-23: the ghost moves, not the camera; the lift waits for ✓ / ✕), a drag with no game (the menus), an Apple Pencil's drag (the box: the
##    IOS-45 input bridge makes it a mouse's left button, device PENCIL_DEVICE: no touch reaches the touch layer).
## Lane IOS-42: Options > Touch > "Two-finger twist": while ✓ / ✕ wait, a twist turns the building's ghost (Turns building, IOS-37's default) and not the
## camera; with Turns camera (OpenBFMETouchPlaceTwist = camera) the camera and not the ghost.
## The game's own check is the touch self-test with OpenBFMETouchDrag = pan (touch_selftest.gd: the camera follows a finger, a hold-drag counts a box).
##
##   godot --headless --path godot --script res://tests/ios35_touch_test.gd
##
## Exit codes: 0 pass, 1 fail.
extends SceneTree

const TouchControls := preload("res://scripts/touch/touch_controls.gd")
const GameOptions := preload("res://scripts/game_options.gd")

const HUD_BAND := 80.0   # the stand-in's HUD: the bottom HUD_BAND pixels of the view
const SCALE := 2.0       # px per point (the Mac stand-in's)


## InGameHudNode's calls the touch layer makes. Its "camera" is a shift: a pixel's ground point is the pixel plus the camera's position
class StubHud:
	extends Node
	var placing := false
	var view := Vector2.ZERO
	var cam := Vector2.ZERO
	var helps := 0
	var angle := 0.0      # lane IOS-42: the placement's angle (set_placement_angle)
	var cam_angle := 0.0  # the camera's (camera_set_angle_pitch)

	func set_placement_angle(a: float) -> bool:
		angle = a
		return true

	func camera_set_angle_pitch(a: float, _pitch: float) -> void:
		cam_angle = a

	func on_hud(p: Vector2) -> bool:
		return p.y >= view.y - HUD_BAND

	func touch_placement_at(p: Vector2) -> Dictionary:
		return {"placing": placing, "line_build": false, "world": not on_hud(p)}

	func get_placement() -> Dictionary:
		return {"placing": placing, "legal": 0, "angle": angle}

	func get_placement_ghost_state() -> Dictionary:
		return {"icons": []}

	func touch_button_at(p: Vector2) -> Dictionary:
		return {"kind": "movie" if on_hud(p) else "", "target": "", "autocast": false}

	func nearest_button(p: Vector2, _radius: float) -> Dictionary:
		return {"snapped": false, "position": p, "reason": "far", "target": ""}

	func hold_help(on: bool) -> void:
		if on:
			helps += 1

	func set_touch_help(_on: bool) -> void:
		pass

	func set_edge_scroll(_on: bool) -> void:
		pass

	func set_view_options(_options: Dictionary) -> void:
		pass

	func pixel_to_world(p: Vector2) -> Vector2:
		return p + cam

	func world_to_pixel(w: Vector2) -> Vector2:
		return w - cam

	func get_camera() -> Dictionary:
		return {"position": cam, "angle": cam_angle, "pitch": 0.0}

	func camera_look_at(at: Vector2) -> void:
		cam = at

	func inject_mouse_wheel(_notches: int, _p: Vector2) -> void:
		pass


## the mouse events the touch layer makes: the presses / releases (button, position, pressed) and the last pointer position
class Recorder:
	extends Node
	var buttons: Array = []
	var pointer := Vector2.INF

	func _input(event: InputEvent) -> void:
		var b := event as InputEventMouseButton
		if b != null:
			buttons.append([b.button_index, b.position, b.pressed])
		var m := event as InputEventMouseMotion
		if m != null:
			pointer = m.position


## the extension's IOSInputDevices (IOS-45) with no mouse
class StubDevices:
	extends RefCounted

	func status() -> Dictionary:
		return {"mice": 0, "keyboard": false, "on_mac": false}


var _failures := 0
var _controls: Node
var _hud: StubHud
var _rec: Recorder


func _initialize() -> void:
	var code: int = await _run()
	print("IOS35 TOUCH %s" % ["PASS" if code == 0 else "FAIL"])
	quit(code)


func _check(ok: bool, what: String) -> void:
	print("  ", "ok   " if ok else "FAIL ", what)
	if not ok:
		_failures += 1


func _run() -> int:
	# the option
	var spec: Dictionary = GameOptions.EXTRAS.get("OpenBFMETouchDrag", {})
	_check(spec.get("default", "") == "select" and Array(spec.get("choices", [])) == ["select", "pan"],
		"OpenBFMETouchDrag: default select, choices select / pan: %s" % [spec])
	_check(not GameOptions.touch_available(), "headless without --touch the option is not offered (touch_available false)")

	_rec = Recorder.new()
	root.add_child(_rec)
	_hud = StubHud.new()
	root.add_child(_hud)
	# the touch layer in a viewport of the Duo stand-in's landscape size (the headless root window is 64 x 64); its mouse events still reach the root
	var stage := SubViewport.new()
	stage.size = Vector2i(1335, 939)
	root.add_child(stage)
	_controls = TouchControls.new()
	stage.add_child(_controls)
	await process_frame
	# what _ready does on a phone (here it saw neither "mobile" nor --touch)
	_controls.active = true
	_controls.set_process(true)
	Input.emulate_mouse_from_touch = false
	_controls._scale = SCALE
	_controls._hud = _hud
	var view: Vector2 = _controls.get_viewport().get_visible_rect().size
	_hud.view = view
	var f := Vector2(view.x * 0.4, view.y * 0.5)
	await _wait(0.5)  # the first frames of a headless start can be slower than a hold (ios21_touch_test.gd): settle first

	# ---- select (the default): a drag is the box -----------------------------------------------------------------------------------------------
	_check(_controls.drag_mode == "select", "the touch layer starts in select mode")
	_rec.buttons.clear()
	await _finger_drag(f, f + Vector2(120, 60))
	_check(_presses() == [[MOUSE_BUTTON_LEFT, f]] and _hud.cam == Vector2.ZERO, "select: a one-finger drag is the box (the left press at its start), the camera stays: %s" % [_rec.buttons])
	await _wait(0.4)

	# ---- pan --------------------------------------------------------------------------------------------------------------------------------------
	_controls.set_drag_mode("pan")
	_check(_controls.drag_mode == "pan", "set_drag_mode(pan)")
	var ground: Vector2 = _hud.pixel_to_world(f)
	var to := f + Vector2(-150, 90)
	_rec.buttons.clear()
	_down(f)
	await _drag_to(f, to)
	_check(_hud.pixel_to_world(to).distance_to(ground) < 0.01, "pan: the ground under the touch-down point %s stays under the finger at %s (camera %s)" % [ground, to, _hud.cam])
	_check(_rec.pointer == to, "pan: the pointer follows the finger: %s" % [_rec.pointer])
	await _wait(0.6)
	_check(_rec.buttons.is_empty(), "a pan that rests is no hold: %s" % [_rec.buttons])
	_up(to)
	await _wait(0.05)
	_check(_rec.buttons.is_empty() and int(_controls.stats.finger_pans) == 1, "pan: nothing pressed, one finger pan counted: %s" % [_rec.buttons])
	await _wait(0.4)

	# a tap: the left click there, as in select mode
	var cam0: Vector2 = _hud.cam
	_rec.buttons.clear()
	await _tap(f)
	_check(_rec.buttons == _click_at(MOUSE_BUTTON_LEFT, f) and _hud.cam == cam0, "pan: a tap is the left click at %s, the camera stays: %s" % [f, _rec.buttons])
	await _wait(0.5)

	# a hold, then a drag: the box from where the finger came down
	_rec.buttons.clear()
	_down(f)
	await _wait(0.6)
	_check(_rec.buttons.is_empty() and int(_controls.stats.box_arms) == 1, "pan: a held finger is armed and presses nothing yet: %s" % [_rec.buttons])
	var box_end := f + Vector2(140, 70)
	await _drag_to(f, box_end)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, f]] and _rec.pointer == box_end and _hud.cam == cam0,
		"pan: the armed finger's drag is the box: the left press at %s, the pointer at its end, the camera stays: %s" % [f, _rec.buttons])
	_up(box_end)
	await _wait(0.05)
	_check(_rec.buttons.size() == 2 and _rec.buttons[1] == [MOUSE_BUTTON_LEFT, box_end, false], "pan: lifting ends the box at %s: %s" % [box_end, _rec.buttons])
	await _wait(0.4)

	# a hold lifted without a drag: the right click, at the lift (a drift within the slop is still a hold)
	_rec.buttons.clear()
	var drift := f + Vector2(6, 4)
	_down(f)
	await _wait(0.6)
	_move(drift)
	await _wait(0.05)
	_check(_rec.buttons.is_empty(), "pan: the hold fires nothing while the finger is down: %s" % [_rec.buttons])
	_up(drift)
	await _wait(0.05)
	_check(_rec.buttons == _click_at(MOUSE_BUTTON_RIGHT, drift) and _hud.cam == cam0, "pan: a hold lifted without a drag is the right click at the lift %s: %s" % [drift, _rec.buttons])
	await _wait(0.4)

	# two fingers still pan
	_rec.buttons.clear()
	await _pan(Vector2(view.x * 0.3, view.y * 0.3), Vector2(100, -50))
	_check(_hud.cam.distance_to(cam0 - Vector2(100, -50)) < 0.01 and _rec.buttons.is_empty(), "pan: two fingers still pan, nothing pressed: camera %s" % [_hud.cam])
	cam0 = _hud.cam
	await _wait(0.4)

	# a drag that starts on the HUD: the left drag, as in select mode (the radar, a slider); a hold on a HUD button: its help
	var on_hud := Vector2(view.x * 0.3, view.y - HUD_BAND * 0.5)
	_rec.buttons.clear()
	await _finger_drag(on_hud, on_hud + Vector2(100, 0))
	_check(_presses() == [[MOUSE_BUTTON_LEFT, on_hud]] and _hud.cam == cam0, "pan: a drag that starts on the HUD is the left drag, the camera stays: %s" % [_rec.buttons])
	await _wait(0.4)
	_rec.buttons.clear()
	var arms := int(_controls.stats.box_arms)
	_down(on_hud)
	await _wait(0.6)
	_up(on_hud)
	await _wait(0.05)
	_check(_hud.helps == 1 and _rec.buttons.is_empty() and int(_controls.stats.box_arms) == arms, "pan: a hold on a HUD button shows its help (IOS-21), no box, nothing pressed: %s helps %d arms %d" % [_rec.buttons, _hud.helps, int(_controls.stats.box_arms)])
	await _wait(0.4)

	# a placement waiting for its site: the drag moves the ghost (IOS-23), not the camera; the lift waits for ✓ / ✕ (IOS-26)
	_hud.placing = true
	_rec.buttons.clear()
	var offset := Vector2(0, TouchControls.GHOST_OFFSET_PT * SCALE)
	var g := f + Vector2(-100, 40)
	_down(f)
	await _drag_to(f, g)
	_check(_rec.pointer == g - offset and _hud.cam == cam0 and _rec.buttons.is_empty(), "pan: a placement's drag moves the ghost %s above the finger, not the camera: %s" % [offset, _rec.pointer])
	_up(g)
	await _wait(0.25)
	_check(_controls._confirming and _controls._confirm.state().shown and _rec.buttons.is_empty(), "pan: the placement's lift waits for ✓ / ✕ as before")
	_controls._end_confirm()
	_hud.placing = false
	await _wait(0.4)

	# no game (the menus): a drag is the left drag (a list or a slider), never a pan
	_controls._hud = null
	_hud.name = "NotTheHud"  # (the touch layer looks for an InGameHudNode; the stand-in is none)
	_rec.buttons.clear()
	await _finger_drag(f, f + Vector2(0, 120))
	_check(_presses() == [[MOUSE_BUTTON_LEFT, f]] and _hud.cam == cam0, "pan: with no game a drag is the left drag (the menus): %s" % [_rec.buttons])
	_controls._hud = _hud
	await _wait(0.4)

	# an Apple Pencil (IOS-45: the input bridge makes it left-button mouse events, device PENCIL_DEVICE, never a touch): its drag is the box
	# (the left drag reaches the game as it is), the camera stays, and it is no mouse in use
	_controls._devices = StubDevices.new()
	_rec.buttons.clear()
	await _pencil_drag(f, f + Vector2(120, -60))
	_check(_presses() == [[MOUSE_BUTTON_LEFT, f]] and _hud.cam == cam0 and int(_controls.stats.pencil_presses) == 1,
		"pan: an Apple Pencil's drag is the box, the camera stays: %s" % [_rec.buttons])
	_check(not _controls.mouse_connected() and not _controls._mouse, "pan: an Apple Pencil is no mouse in use")
	_controls._devices = null
	await _wait(0.4)
	# the next finger pans again
	await _finger_drag(f, f + Vector2(50, 0))
	_check(_hud.cam == cam0 - Vector2(50, 0), "pan: the next finger pans again: camera %s" % [_hud.cam])
	await _wait(0.4)

	# back to select; an unknown value is select
	_controls.set_drag_mode("bogus")
	cam0 = _hud.cam
	_rec.buttons.clear()
	await _finger_drag(f, f + Vector2(120, 60))
	_check(_controls.drag_mode == "select" and _presses() == [[MOUSE_BUTTON_LEFT, f]] and _hud.cam == cam0, "an unknown value is select: the drag is the box again: %s" % [_rec.buttons])
	await _wait(0.4)

	# ---- lane IOS-42: Two-finger twist while ✓ / ✕ wait -------------------------------------------------------------------------------------------
	_hud.placing = true
	await _tap(f)
	await _wait(0.25)
	_check(_controls._confirming, "IOS-42: a tap during a placement waits for ✓ / ✕")
	await _twist(Vector2(view.x * 0.5, view.y * 0.35), 40.0)
	_check(absf(_hud.angle) > deg_to_rad(20.0) and _hud.cam_angle == 0.0, "IOS-42 Turns building (the default): the twist turned the ghost %.1f deg, not the camera %.1f deg" % [
		rad_to_deg(_hud.angle), rad_to_deg(_hud.cam_angle)])
	_controls.apply_options({"OpenBFMETouchPlaceTwist": "camera"})
	var turned := _hud.angle
	await _wait(0.3)
	await _twist(Vector2(view.x * 0.5, view.y * 0.35), 40.0)
	_check(_controls._confirming and _hud.angle == turned and absf(_hud.cam_angle) > deg_to_rad(20.0), "IOS-42 Turns camera: the twist turned the camera %.1f deg, not the ghost" % [
		rad_to_deg(_hud.cam_angle)])
	_controls._end_confirm()
	_controls.apply_options({})
	_hud.placing = false
	return 0 if _failures == 0 else 1


## two fingers 200 px apart about `centre` turned together by `degrees` in 10 frames, then lifted
func _twist(centre: Vector2, degrees: float) -> void:
	var r := Vector2(100, 0)
	_down(centre - r, 0)
	_down(centre + r, 1)
	await process_frame
	for i in range(1, 11):
		var turned := r.rotated(deg_to_rad(degrees) * i / 10.0)
		_move(centre - turned, 0)
		_move(centre + turned, 1)
		await process_frame
	var last := r.rotated(deg_to_rad(degrees))
	_up(centre - last, 0)
	_up(centre + last, 1)
	await process_frame


## the presses of the recorded buttons: [button, position]
func _presses() -> Array:
	return _rec.buttons.filter(func(b): return b[2]).map(func(b): return [b[0], b[1]])


## one click's records: [[button, at, true], [button, at, false]]
func _click_at(button: int, at: Vector2) -> Array:
	return [[button, at, true], [button, at, false]]


func _down(at: Vector2, index := 0) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = at
	t.pressed = true
	_controls._touch(t)


func _up(at: Vector2, index := 0) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = at
	t.pressed = false
	_controls._touch(t)


func _move(at: Vector2, index := 0) -> void:
	var d := InputEventScreenDrag.new()
	d.index = index
	d.position = at
	_controls._drag(d)


func _tap(at: Vector2) -> void:
	_down(at)
	await _wait(0.05)
	_up(at)
	await process_frame


## one finger down at `from`, dragged to `to` and lifted there
## an Apple Pencil's stroke as the input bridge hands it to Godot (GodotIOSTouch.mm emit_pencil): a left press, motion, a left release; the
## touch layer sees each as its _input would on an iOS build
func _pencil_drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.device = TouchControls.PENCIL_DEVICE
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = from
	press.global_position = from
	Input.parse_input_event(press)  # the game's copy (the Recorder)
	_controls._bridge_event(press)  # and the touch layer's look (its stage takes no input of the root's)
	await process_frame
	for i in range(1, 9):
		var m := InputEventMouseMotion.new()
		m.device = TouchControls.PENCIL_DEVICE
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.position = from.lerp(to, i / 8.0)
		m.global_position = m.position
		Input.parse_input_event(m)
		_controls._bridge_event(m)
		await process_frame
	var release := InputEventMouseButton.new()
	release.device = TouchControls.PENCIL_DEVICE
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = to
	release.global_position = to
	Input.parse_input_event(release)
	_controls._bridge_event(release)
	await process_frame


func _finger_drag(from: Vector2, to: Vector2) -> void:
	_down(from)
	await _drag_to(from, to)
	_up(to)
	await process_frame


## two fingers 160 px apart from `at` moved together by `shift` in 8 frames
func _pan(at: Vector2, shift: Vector2) -> void:
	var b := at + Vector2(160, 0)
	_down(at, 0)
	_down(b, 1)
	await process_frame
	for i in range(1, 9):
		_move(at + shift * (i / 8.0), 0)
		_move(b + shift * (i / 8.0), 1)
		await process_frame
	_up(at + shift, 0)
	_up(b + shift, 1)
	await process_frame


## one finger from `from` to `to` in 8 moves
func _drag_to(from: Vector2, to: Vector2) -> void:
	for i in range(1, 9):
		_move(from.lerp(to, i / 8.0))
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
