## Headless test of lane IOS-23 in the touch layer (scripts/touch/touch_controls.gd), against a stand-in HUD: no game, no extension needed.
## While a building's placement waits for its site (the stand-in's touch_placement_at):
##  * a finger down on the world puts the pointer (the ghost) GHOST_OFFSET_PT above the fingertip and presses nothing; dragging moves it at that offset,
##    with no left press (no selection box); lifting is one left click at the ghost's point;
##  * a tap places at the tap point (no offset); a still hold is the right click (cancel); a drag that then rests is no hold: lifting places;
##  * the ghost's point stays inside the view at the top edge; a lift whose ghost point is on the HUD clicks nothing;
##  * a finger that starts on the HUD is not a placement drag (its tap presses there); a second finger ends the drag without a placement;
##  * without a placement a one-finger drag is still the selection box (the left press at the drag's start).
## The game's own check is the touch self-test (touch_selftest.gd: a real building and a wall span).
##
##   godot --headless --path godot --script res://tests/ios23_touch_test.gd
##
## Exit codes: 0 pass, 1 fail.
extends SceneTree

const TouchControls := preload("res://scripts/touch/touch_controls.gd")

const HUD_BAND := 80.0  # the stand-in's HUD: the bottom HUD_BAND pixels of the view ...
const TOP_HUD := 60.0   # ... and a top-centre box this high over the middle fifth of the width (the Palantir's top anchor)


## InGameHudNode's calls the touch layer makes
class StubHud:
	extends Node
	var placing := false
	var view := Vector2.ZERO

	func on_hud(p: Vector2) -> bool:
		return p.y >= view.y - HUD_BAND or (p.y < TOP_HUD and absf(p.x - view.x * 0.5) < view.x * 0.1)

	func touch_placement_at(p: Vector2) -> Dictionary:
		return {"placing": placing, "line_build": false, "world": not on_hud(p)}

	func touch_button_at(p: Vector2) -> Dictionary:
		return {"kind": "movie" if on_hud(p) else "", "target": "", "autocast": false}

	func nearest_button(p: Vector2, _radius: float) -> Dictionary:
		return {"snapped": false, "position": p, "reason": "aiming" if placing else "far", "target": ""}

	func hold_help(_on: bool) -> void:
		pass

	func set_touch_help(_on: bool) -> void:
		pass

	func set_edge_scroll(_on: bool) -> void:
		pass

	func set_view_options(_options: Dictionary) -> void:
		pass

	# the two-finger gesture's camera calls (the stand-in has no camera: nothing pans, zooms or turns)
	func pixel_to_world(_p: Vector2) -> Vector2:
		return Vector2.INF

	func get_camera() -> Dictionary:
		return {}

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


var _failures := 0
var _controls: Node
var _hud: StubHud
var _rec: Recorder


func _initialize() -> void:
	var code: int = await _run()
	print("IOS23 TOUCH %s" % ["PASS" if code == 0 else "FAIL"])
	quit(code)


func _check(ok: bool, what: String) -> void:
	print("  ", "ok   " if ok else "FAIL ", what)
	if not ok:
		_failures += 1


func _run() -> int:
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
	# what _ready does on a phone (here it saw neither "mobile" nor --touch); 2 px per point, the Mac stand-in's
	_controls.active = true
	_controls.set_process(true)
	Input.emulate_mouse_from_touch = false
	_controls._scale = 2.0
	_controls._hud = _hud
	var view: Vector2 = _controls.get_viewport().get_visible_rect().size
	_hud.view = view
	var offset := Vector2(0, TouchControls.GHOST_OFFSET_PT * 2.0)
	var f := Vector2(view.x * 0.5, view.y * 0.5)
	print("  view %s, ghost offset %s px" % [view, offset])
	await _wait(0.5)  # the first frames of a headless start can be slower than a hold (ios21_touch_test.gd): settle first

	# no placement: a one-finger drag stays the selection box (the left press at its start)
	_rec.buttons.clear()
	_down(f)
	await _drag_to(f, f + Vector2(80, 40))
	_up(f + Vector2(80, 40))
	await _wait(0.1)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, f]], "without a placement a drag is the box: the left press at its start: %s" % [_rec.buttons])
	await _wait(0.5)

	_hud.placing = true
	# finger down on the world: the pointer above the finger, nothing pressed
	_rec.buttons.clear()
	_down(f)
	await _wait(0.05)
	_check(_rec.pointer == f - offset, "finger down: the ghost's pointer %s is %s above the finger %s" % [_rec.pointer, offset, f])
	_check(_rec.buttons.is_empty(), "finger down presses nothing: %s" % [_rec.buttons])
	# drag: the pointer follows at the offset, no press (no box)
	var g := f + Vector2(-120, 50)
	await _drag_to(f, g)
	_check(_rec.pointer == g - offset, "dragging: the pointer %s follows the finger %s at the offset" % [_rec.pointer, g])
	_check(_rec.buttons.is_empty(), "dragging presses nothing (no selection box): %s" % [_rec.buttons])
	# rest past the hold time: no right click once the finger has moved
	await _wait(0.6)
	_check(_rec.buttons.is_empty(), "a placement drag that rests is no hold: %s" % [_rec.buttons])
	_up(g)
	await _wait(0.05)
	_check(_rec.buttons == [[MOUSE_BUTTON_LEFT, g - offset, true], [MOUSE_BUTTON_LEFT, g - offset, false]],
		"lifting is one left click at the ghost's point %s: %s" % [g - offset, _rec.buttons])
	_check(int(_controls.stats.place_drags) == 1 and int(_controls.stats.place_lifts) == 1, "counted: one placement drag, one lift")
	await _wait(0.5)

	# a tap places at the tap point (no offset)
	_rec.buttons.clear()
	_down(f)
	await _wait(0.05)
	_up(f)
	await _wait(0.05)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, f]], "a tap while placing clicks at the tap point %s: %s" % [f, _rec.buttons])
	await _wait(0.5)

	# a still hold: the right click (cancels the placement)
	_rec.buttons.clear()
	_down(f)
	await _wait(0.6)
	_up(f)
	await _wait(0.05)
	_check(_presses().map(func(p): return p[0]) == [MOUSE_BUTTON_RIGHT], "a still hold while placing is the right click: %s" % [_rec.buttons])
	await _wait(0.5)

	# the top edge: a finger near it keeps the ghost inside the view
	_rec.buttons.clear()
	var top := Vector2(view.x * 0.2, 30)
	_down(top)
	await _wait(0.05)
	_check(_rec.pointer == Vector2(top.x, TouchControls.GHOST_INSET_PX), "a finger %s near the top holds the ghost at the edge: %s" % [top, _rec.pointer])
	await _drag_to(top, top + Vector2(60, 0))
	_up(top + Vector2(60, 0))
	await _wait(0.05)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, Vector2(top.x + 60, TouchControls.GHOST_INSET_PX)]], "and lifting places at the edge: %s" % [_rec.buttons])
	await _wait(0.5)

	# a lift whose ghost point is on the HUD (the top-centre box) clicks nothing (the HUD would take the press); the drag still moved the ghost there
	_rec.buttons.clear()
	var under := Vector2(view.x * 0.5, TOP_HUD + offset.y + 40)  # the ghost point below the box: on the world
	var into := Vector2(view.x * 0.5, TOP_HUD + offset.y - 30)   # the ghost point inside the box
	_down(under)
	await _drag_to(under, into)
	_check(_rec.pointer == into - offset, "a drag moves the ghost onto the HUD too: %s" % [_rec.pointer])
	_up(into)
	await _wait(0.05)
	_check(_rec.buttons.is_empty() and int(_controls.stats.place_lifts_on_hud) == 1,
		"a lift with the ghost's point %s on the HUD clicks nothing: %s" % [into - offset, _rec.buttons])
	await _wait(0.5)

	# a finger that starts on the HUD is no placement drag: its tap presses there (a HUD button)
	_rec.buttons.clear()
	var button := Vector2(f.x, view.y - HUD_BAND * 0.5)
	_down(button)
	await _wait(0.05)
	_check(_rec.pointer == button, "a finger on the HUD keeps the pointer under it: %s" % [_rec.pointer])
	_up(button)
	await _wait(0.05)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, button]], "and its tap presses there: %s" % [_rec.buttons])
	await _wait(0.5)

	# a second finger during the drag ends it without a placement (it pans; the lifts click nothing)
	_rec.buttons.clear()
	_down(f)
	await _drag_to(f, f + Vector2(60, 0))
	_down(f + Vector2(-200, 0), 1)
	await _wait(0.05)
	for i in range(1, 7):
		_move(f + Vector2(60, 0) + Vector2(0, 15 * i), 0)
		_move(f + Vector2(-200, 15 * i), 1)
		await process_frame
	_up(f + Vector2(60, 90), 0)
	_up(f + Vector2(-200, 90), 1)
	await _wait(0.05)
	_check(_rec.buttons.is_empty(), "a second finger ends the placement drag; nothing is clicked: %s" % [_rec.buttons])
	return 0 if _failures == 0 else 1


## the presses of the recorded buttons: [button, position]
func _presses() -> Array:
	return _rec.buttons.filter(func(b): return b[2]).map(func(b): return [b[0], b[1]])


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


## one finger from `from` to `to` in 8 moves
func _drag_to(from: Vector2, to: Vector2) -> void:
	for i in range(1, 9):
		_move(from.lerp(to, i / 8.0))
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
