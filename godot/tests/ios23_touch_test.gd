## Headless test of lanes IOS-23 and IOS-26 in the touch layer (scripts/touch/touch_controls.gd, scripts/touch/placement_confirm.gd), against a
## stand-in HUD: no game, no extension needed. While a building's placement waits for its site (the stand-in's touch_placement_at):
##  * IOS-23: a finger down on the world puts the pointer (the ghost) GHOST_OFFSET_PT above the fingertip and presses nothing; dragging moves it at
##    that offset, with no left press (no selection box); a still hold is the right click (cancel); a drag that then rests is no hold;
##  * IOS-26: lifting presses nothing: the ghost stays and ✓ / ✕ show beside it (✕ left, ✓ right, at least 44 pt targets, the ghost's middle clear);
##    a new drag anywhere on the world hides them and moves the ghost again; a tap puts the ghost under the tap point (no offset) with ✓ / ✕;
##    ✓ is one left click at the ghost's point; ✕ one right click there; sliding off a button presses nothing; ✓ is dimmed on a red ghost and a tap
##    on it still clicks (the game refuses, the buttons stay); a wall span's ✓ is never dimmed, and ✓ / ✕ sit across its line at its end;
##  * the ghost keeps its ground point while two fingers pan (the buttons hide, then come back beside it); a point panned off the view hides them
##    until it is back; a second finger that comes down before the first one moved puts the ghost back;
##  * the buttons stay inside the view and off the HUD (beside the side bar both go left); a tap on the HUD, a hold or a mouse's motion (IOS-14)
##    ends the wait; a mouse click passes the touch layer untouched; the top-edge clamp; a lift whose ghost point is on the HUD offers nothing;
##  * without a placement a one-finger drag is still the selection box (the left press at the drag's start).
## The game's own check is the touch self-test (touch_selftest.gd: a real building and a wall span, built by ✓).
##
##   godot --headless --path godot --script res://tests/ios23_touch_test.gd
##
## Exit codes: 0 pass, 1 fail.
extends SceneTree

const TouchControls := preload("res://scripts/touch/touch_controls.gd")
const PlacementConfirm := preload("res://scripts/touch/placement_confirm.gd")

const HUD_BAND := 80.0   # the stand-in's HUD: the bottom HUD_BAND pixels of the view ...
const TOP_HUD := 60.0    # ... a top-centre box this high over the middle fifth of the width (the Palantir's top anchor) ...
const SIDE_BAR := 140.0  # ... and the right SIDE_BAR pixels from y 200 down (the side command bar)
const SCALE := 2.0       # px per point (the Mac stand-in's)


## InGameHudNode's calls the touch layer makes. Its "camera" is a shift: a pixel's ground point is the pixel plus the camera's position. Like the
## game, a left release on the world while placing at a legal (code 0) site or for a wall span places, and a right press cancels
class StubHud:
	extends Node
	var placing := false
	var legal := 0
	var line := false
	var view := Vector2.ZERO
	var cam := Vector2.ZERO
	var placed := 0
	var icons: Array = []  # a wall span's ghost segments (ground points)

	func on_hud(p: Vector2) -> bool:
		return p.y >= view.y - HUD_BAND or (p.y < TOP_HUD and absf(p.x - view.x * 0.5) < view.x * 0.1) or (p.x >= view.x - SIDE_BAR and p.y >= 200.0)

	func touch_placement_at(p: Vector2) -> Dictionary:
		return {"placing": placing, "line_build": line, "world": not on_hud(p)}

	func get_placement() -> Dictionary:
		return {"placing": placing, "legal": legal}

	func get_placement_ghost_state() -> Dictionary:
		return {"icons": icons if line else []}

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

	func pixel_to_world(p: Vector2) -> Vector2:
		return p + cam

	func world_to_pixel(w: Vector2) -> Vector2:
		return w - cam

	func get_camera() -> Dictionary:
		return {"position": cam}

	func camera_look_at(at: Vector2) -> void:
		cam = at

	func inject_mouse_wheel(_notches: int, _p: Vector2) -> void:
		pass

	func _input(event: InputEvent) -> void:
		var b := event as InputEventMouseButton
		if b == null or not placing:
			return
		if b.button_index == MOUSE_BUTTON_RIGHT and b.pressed:
			placing = false
		elif b.button_index == MOUSE_BUTTON_LEFT and not b.pressed and not on_hud(b.position) and (legal == 0 or line):
			placing = false
			placed += 1


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


## the IOS-14 bridge's IOSPointer: a mouse that has shown itself and has one motion to report
class StubPointer:
	extends RefCounted
	var events: Array = []

	func status() -> Dictionary:
		return {"pointer_seen": true}

	func poll() -> Array:
		var out := events
		events = []
		return out


var _failures := 0
var _controls: Node
var _hud: StubHud
var _rec: Recorder
var _offset := Vector2.ZERO


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
	# what _ready does on a phone (here it saw neither "mobile" nor --touch)
	_controls.active = true
	_controls.set_process(true)
	Input.emulate_mouse_from_touch = false
	_controls._scale = SCALE
	_controls._hud = _hud
	var view: Vector2 = _controls.get_viewport().get_visible_rect().size
	_hud.view = view
	_offset = Vector2(0, TouchControls.GHOST_OFFSET_PT * SCALE)
	var f := Vector2(view.x * 0.4, view.y * 0.5)
	print("  view %s, ghost offset %s px" % [view, _offset])
	await _wait(0.5)  # the first frames of a headless start can be slower than a hold (ios21_touch_test.gd): settle first

	# no placement: a one-finger drag stays the selection box (the left press at its start)
	_rec.buttons.clear()
	_down(f)
	await _drag_to(f, f + Vector2(80, 40))
	_up(f + Vector2(80, 40))
	await _wait(0.1)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, f]], "without a placement a drag is the box: the left press at its start: %s" % [_rec.buttons])
	await _wait(0.5)

	# ---- IOS-23: the ghost above the finger -----------------------------------------------------------------------------------------------------
	_hud.placing = true
	_rec.buttons.clear()
	_down(f)
	await _wait(0.05)
	_check(_rec.pointer == f - _offset, "finger down: the ghost's pointer %s is %s above the finger %s" % [_rec.pointer, _offset, f])
	_check(_rec.buttons.is_empty(), "finger down presses nothing: %s" % [_rec.buttons])
	var g := f + Vector2(-120, 50)
	await _drag_to(f, g)
	_check(_rec.pointer == g - _offset, "dragging: the pointer %s follows the finger %s at the offset" % [_rec.pointer, g])
	_check(_rec.buttons.is_empty(), "dragging presses nothing (no selection box): %s" % [_rec.buttons])
	await _wait(0.6)
	_check(_rec.buttons.is_empty(), "a placement drag that rests is no hold: %s" % [_rec.buttons])

	# ---- IOS-26: lifting waits for ✓ / ✕ ------------------------------------------------------------------------------------------------------------
	_up(g)
	await _wait(0.25)  # the appearing motion (180 ms) runs out
	var ghost := g - _offset
	var s := _state()
	_check(_rec.buttons.is_empty(), "lifting presses nothing: %s" % [_rec.buttons])
	_check(_rec.pointer == ghost and s.shown and s.ghost == ghost, "the ghost stays at %s and ✓ / ✕ show beside it: %s, pointer %s" % [ghost, s, _rec.pointer])
	_check(s.build.x > ghost.x and s.cancel.x < ghost.x and absf(s.build.y - ghost.y) < 1.0 and absf(s.cancel.y - ghost.y) < 1.0,
		"✓ right of the ghost, ✕ left, level with it: ✓ %s ✕ %s" % [s.build, s.cancel])
	_check(s.hit_radius * 2.0 >= 44.0 * SCALE and s.diameter >= 44.0 * SCALE, "the targets are at least 44 pt: hit %.0f px, disc %.0f px" % [s.hit_radius * 2.0, s.diameter])
	_check(s.build.distance_to(ghost) - s.diameter * 0.5 >= 30.0 * SCALE and s.cancel.distance_to(ghost) - s.diameter * 0.5 >= 30.0 * SCALE,
		"the discs leave the ghost's middle clear (30 pt)")
	_check(int(_controls.stats.place_drags) == 1 and int(_controls.stats.place_lifts) == 1, "counted: one placement drag, one lift")
	var alpha: float = _controls._confirm.get_node("ConfirmBuild").modulate.a
	_check(is_equal_approx(alpha, 1.0), "the buttons have faded in: %.2f" % alpha)

	# a new drag anywhere on the world: the buttons hide, the ghost goes above the finger, the buttons come back where it stops
	var h := Vector2(view.x * 0.3, view.y * 0.7)
	_down(h)
	await _wait(0.05)
	_check(not _state().shown and _rec.pointer == h - _offset, "a finger on the world hides ✓ / ✕ and moves the ghost above it: %s" % [_rec.pointer])
	var h2 := h + Vector2(150, -40)
	await _drag_to(h, h2)
	_up(h2)
	await _wait(0.25)
	s = _state()
	_check(_rec.buttons.is_empty() and s.shown and s.ghost == h2 - _offset and _rec.pointer == h2 - _offset,
		"the re-drag's lift: the ghost at %s with ✓ / ✕, nothing pressed: %s" % [h2 - _offset, s])

	# a tap: the ghost under the tap point (no offset), ✓ / ✕ beside it
	var t := Vector2(view.x * 0.45, view.y * 0.45)
	await _tap(t)
	await _wait(0.25)
	s = _state()
	_check(_rec.buttons.is_empty() and s.shown and s.ghost == t and _rec.pointer == t,
		"a tap puts the ghost under the tap point %s (no offset) with ✓ / ✕, nothing pressed: %s" % [t, s])
	_check(int(_controls.stats.place_taps) == 1, "counted: one placement tap")

	# sliding off ✓ and lifting presses nothing
	_down(s.build)
	await _wait(0.05)
	await _drag_to(s.build, s.build + Vector2(0, 120))
	_up(s.build + Vector2(0, 120))
	await _wait(0.15)
	_check(_rec.buttons.is_empty() and _state().shown and _hud.placing, "a finger that slides off ✓ and lifts presses nothing: %s" % [_rec.buttons])

	# a red ghost: ✓ dimmed; a tap on it still clicks (the game refuses: the placement and the buttons stay)
	_hud.legal = 3
	await _wait(0.2)
	_check(not _state().build_enabled, "✓ is dimmed while the ghost is red")
	await _tap(_state().build)
	await _wait(0.6)
	_check(_rec.buttons == _click_at(MOUSE_BUTTON_LEFT, t), "✓ on a red ghost is the left click at the ghost's point %s: %s" % [t, _rec.buttons])
	_check(_hud.placing and _state().shown and _hud.placed == 0, "refused: the placement and ✓ / ✕ stay")
	# a wall span's ✓ is never dimmed (its release skips the legality test)
	_hud.line = true
	await _tap(t)
	await _wait(0.25)
	_check(_state().build_enabled, "a wall span's ✓ is not dimmed on a red ghost")
	# a wall span from a hub left of the ghost: ✓ / ✕ across the span's line at its end, off the line
	var hub := t + Vector2(-300, 0)
	_hud.icons = []
	for i in 5:
		var at: Vector2 = _hud.pixel_to_world(hub.lerp(t, i / 4.0))
		_hud.icons.append({"x": at.x, "y": at.y, "code": 0})
	await _tap(t)
	await _wait(0.25)
	s = _state()
	_check(absf(s.build.x - t.x) < 1.0 and absf(s.cancel.x - t.x) < 1.0 and s.build.y < t.y and s.cancel.y > t.y,
		"a level wall span: ✓ above its end, ✕ below, neither on the line: ✓ %s ✕ %s, end %s" % [s.build, s.cancel, t])
	_hud.icons = []
	_hud.line = false
	_hud.legal = 0
	await _wait(0.2)
	_check(_state().build_enabled, "✓ is enabled again on a legal ghost")

	# ✓: one left click at the ghost's point; the game places, the buttons go
	_rec.buttons.clear()
	var build: Vector2 = _state().build
	await _tap(build)
	await _wait(0.05)
	_check(_rec.buttons == _click_at(MOUSE_BUTTON_LEFT, t), "✓ is one left click at the ghost's point %s: %s" % [t, _rec.buttons])
	_check(_hud.placed == 1 and not _state().shown, "the game placed; ✓ / ✕ are gone")
	await _wait(0.2)
	_check(not _controls._confirming and int(_controls.stats.place_confirms) == 2, "the wait has ended (the placement is off)")

	# ✕: one right click at the ghost's point; the placement ends
	_hud.placing = true
	await _tap(t + Vector2(40, 30))
	await _wait(0.25)
	_rec.buttons.clear()
	await _tap(_state().cancel)
	await _wait(0.05)
	_check(_rec.buttons == _click_at(MOUSE_BUTTON_RIGHT, t + Vector2(40, 30)), "✕ is one right click at the ghost's point: %s" % [_rec.buttons])
	_check(not _hud.placing and not _state().shown and int(_controls.stats.place_cancels) == 1, "✕ cancelled the placement; the buttons are gone")
	await _wait(0.5)

	# two fingers pan while the ghost waits: it keeps its ground point; the buttons hide, then come back beside it
	_hud.placing = true
	await _tap(t)
	await _wait(0.25)
	var ground: Vector2 = _hud.pixel_to_world(t)
	_rec.buttons.clear()
	var a := Vector2(view.x * 0.6, view.y * 0.4)
	var b := a + Vector2(160, 0)
	_down(a, 0)
	await _wait(0.03)
	_down(b, 1)
	await _wait(0.03)
	_check(_rec.pointer == t and not _state().shown, "a second finger before the first moved: the ghost back at %s, the buttons hidden: %s" % [t, _rec.pointer])
	for i in range(1, 9):
		_move(a + Vector2(-25 * i, 0), 0)
		_move(b + Vector2(-25 * i, 0), 1)
		await process_frame
	var panned: Vector2 = _hud.world_to_pixel(ground)
	_check(_rec.pointer.distance_to(panned) < 1.0 and not _state().shown, "panning: the ghost follows its ground point to %s: %s" % [panned, _rec.pointer])
	_up(a + Vector2(-200, 0), 0)
	_up(b + Vector2(-200, 0), 1)
	await _wait(0.3)
	s = _state()
	_check(_rec.buttons.is_empty() and s.shown and s.ghost.distance_to(panned) < 1.0 and _hud.placing,
		"after the pan ✓ / ✕ are back beside the ghost at %s; nothing pressed: %s" % [panned, s])
	# panned until the ghost's point leaves the view: the buttons hide; panned back: they return
	await _pan(Vector2(view.x * 0.3, view.y * 0.3), Vector2(-700, 0))
	await _wait(0.3)
	_check(not _state().shown and _controls._confirming, "the ghost's point panned off the view: the buttons hide, the wait stays")
	await _pan(Vector2(view.x * 0.3, view.y * 0.3), Vector2(700, 0))
	await _wait(0.3)
	_check(_state().shown and _state().ghost.distance_to(_hud.world_to_pixel(ground)) < 1.0, "panned back: the buttons return beside it: %s" % [_state()])
	_check(_rec.buttons.is_empty(), "the pans pressed nothing: %s" % [_rec.buttons])

	# a second finger during a placement drag stops the ghost there; ✓ / ✕ after the camera gesture
	var d0 := Vector2(view.x * 0.35, view.y * 0.6)
	_down(d0)
	await _drag_to(d0, d0 + Vector2(60, 0))
	_down(d0 + Vector2(-200, 0), 1)
	await _wait(0.05)
	for i in range(1, 7):
		_move(d0 + Vector2(60, 15 * i), 0)
		_move(d0 + Vector2(-200, 15 * i), 1)
		await process_frame
	_up(d0 + Vector2(60, 90), 0)
	_up(d0 + Vector2(-200, 90), 1)
	await _wait(0.3)
	s = _state()
	var held: Vector2 = d0 + Vector2(60, 0) - _offset + Vector2(0, 90)  # the drag's ghost point, then panned down with the fingers
	_check(_rec.buttons.is_empty() and s.shown and s.ghost.distance_to(held) < 1.0,
		"a second finger stops the drag's ghost and pans it; ✓ / ✕ at %s, nothing pressed: %s %s" % [held, s, _rec.buttons])

	# beside the side bar: both buttons go left of the ghost, off the bar
	var near_bar := Vector2(view.x - SIDE_BAR - 50, view.y * 0.5)
	await _tap(near_bar)
	await _wait(0.25)
	s = _state()
	var r: float = s.diameter * 0.5
	_check(s.build.x < near_bar.x and s.cancel.x < s.build.x and not _hud.on_hud(s.build + Vector2(r, 0)),
		"beside the side bar ✓ and ✕ both go left (✓ nearer): ✓ %s ✕ %s, ghost %s" % [s.build, s.cancel, near_bar])

	# the top edge: the ghost held at the edge; the buttons inside the view
	var top := Vector2(view.x * 0.2, 30)
	_down(top)
	await _wait(0.05)
	_check(_rec.pointer == Vector2(top.x, TouchControls.GHOST_INSET_PX), "a finger %s near the top holds the ghost at the edge: %s" % [top, _rec.pointer])
	await _drag_to(top, top + Vector2(60, 0))
	_up(top + Vector2(60, 0))
	await _wait(0.25)
	s = _state()
	var inside := Rect2(Vector2.ZERO, view).grow(-PlacementConfirm.MARGIN_PT * SCALE)
	_check(s.shown and s.ghost == Vector2(top.x + 60, TouchControls.GHOST_INSET_PX) and _rec.buttons.is_empty(), "lifting at the edge waits there: %s" % [s])
	_check(inside.encloses(Rect2(s.build - Vector2(r, r), Vector2(r, r) * 2.0)) and inside.encloses(Rect2(s.cancel - Vector2(r, r), Vector2(r, r) * 2.0)),
		"the buttons stay inside the view: ✓ %s ✕ %s" % [s.build, s.cancel])

	# a lift whose ghost point is on the HUD (the top-centre box) offers nothing and clicks nothing
	var under := Vector2(view.x * 0.5, TOP_HUD + _offset.y + 40)  # the ghost point below the box: on the world
	var into := Vector2(view.x * 0.5, TOP_HUD + _offset.y - 30)   # the ghost point inside the box
	_down(under)
	await _drag_to(under, into)
	_check(_rec.pointer == into - _offset, "a drag moves the ghost onto the HUD too: %s" % [_rec.pointer])
	_up(into)
	await _wait(0.1)
	_check(_rec.buttons.is_empty() and not _state().shown and not _controls._confirming and int(_controls.stats.place_lifts_on_hud) == 1,
		"a lift with the ghost's point %s on the HUD offers nothing and clicks nothing: %s" % [into - _offset, _rec.buttons])

	# a tap on the HUD while the ghost waits: the wait ends and the tap presses there
	await _tap(t)
	await _wait(0.25)
	var button := Vector2(view.x * 0.3, view.y - HUD_BAND * 0.5)
	_down(button)
	await _wait(0.05)
	_check(_rec.pointer == button and not _state().shown and not _controls._confirming, "a finger on the HUD ends the wait; the pointer under it: %s" % [_rec.pointer])
	_up(button)
	await _wait(0.05)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, button]], "and its tap presses there: %s" % [_rec.buttons])
	await _wait(0.4)

	# a still hold while the ghost waits: the right click (cancel); the wait ends
	await _tap(t)
	await _wait(0.25)
	_rec.buttons.clear()
	_down(t + Vector2(30, 0))
	await _wait(0.6)
	_up(t + Vector2(30, 0))
	await _wait(0.05)
	_check(_presses().map(func(p): return p[0]) == [MOUSE_BUTTON_RIGHT] and not _controls._confirming and not _state().shown,
		"a still hold while the ghost waits is the right click; the wait ends: %s" % [_rec.buttons])
	await _wait(0.4)

	# a mouse (IOS-14 bridge): its motion ends the wait; a mouse click passes the touch layer untouched (retail's click placement)
	_hud.placing = true
	await _tap(t)
	await _wait(0.25)
	var pointer := StubPointer.new()
	pointer.events = [{"type": "motion", "position": t + Vector2(100, 0), "buttons": 0}]
	_controls._pointer = pointer
	_controls._pump_bridge()
	_controls._pointer = null
	await _wait(0.05)
	_check(not _controls._confirming and not _state().shown and _rec.pointer == t + Vector2(100, 0), "a mouse's motion ends the wait; the mouse has the pointer")
	_rec.buttons.clear()
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.position = t + Vector2(100, 0)
		click.global_position = click.position
		Input.parse_input_event(click)
	await _wait(0.1)
	_check(_rec.buttons == _click_at(MOUSE_BUTTON_LEFT, t + Vector2(100, 0)) and _hud.placed == 2 and not _state().shown,
		"a mouse click places at once, no ✓ / ✕: %s" % [_rec.buttons])
	return 0 if _failures == 0 else 1


func _state() -> Dictionary:
	if _controls._confirm == null:
		return {"shown": false}
	return _controls._confirm.state()


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
