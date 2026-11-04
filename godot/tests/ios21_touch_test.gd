## Headless test of lane IOS-21 in the touch layer (scripts/touch/touch_controls.gd), against a stand-in HUD: no game, no extension needed.
##  * a hold on a HUD button shows its help (hold_help on, then off when lifted) and sends no click; sliding off ends it; a hold in the world is the right click;
##  * two taps on an autocast ability are its right press (the autocast toggle) and nothing else, also when the second finger stays down past the window;
##  * one tap on an autocast ability presses it once the double tap's window has passed; a finger elsewhere presses it at once;
##  * two taps on any other button stay two left presses (the second a double click: a radial bubble queues two units).
## The game's own check is the touch self-test (touch_selftest.gd: a real side bar button and the portrait); the engine's is the unit test "ios21 retail".
##
##   godot --headless --path godot --script res://tests/ios21_touch_test.gd
##
## Exit codes: 0 pass, 1 fail.
extends SceneTree

const TouchControls := preload("res://scripts/touch/touch_controls.gd")

const AUTOCAST := Rect2(100, 100, 50, 50)  # an ability whose right press toggles its autocast
const BUTTON := Rect2(300, 100, 50, 50)    # any other HUD button (a bubble, a build button)
const WORLD := Vector2(600, 400)


## InGameHudNode's calls the touch layer makes, answered from the two rects
class StubHud:
	extends Node
	var held: Array = []
	var touch_help: Array = []

	func touch_button_at(p: Vector2) -> Dictionary:
		if AUTOCAST.has_point(p):
			return {"kind": "movie", "target": "ability", "autocast": true}
		if BUTTON.has_point(p):
			return {"kind": "radial", "target": "", "autocast": false}
		return {"kind": "", "target": "", "autocast": false}

	func nearest_button(p: Vector2, _radius: float) -> Dictionary:
		return {"snapped": false, "position": p, "reason": "hit" if AUTOCAST.has_point(p) or BUTTON.has_point(p) else "far", "target": ""}

	func hold_help(on: bool) -> void:
		held.append(on)

	func set_touch_help(on: bool) -> void:
		touch_help.append(on)

	func set_edge_scroll(_on: bool) -> void:
		pass

	func set_view_options(_options: Dictionary) -> void:
		pass


## the mouse presses the touch layer makes (button, position, double click)
class Recorder:
	extends Node
	var presses: Array = []

	func _input(event: InputEvent) -> void:
		var b := event as InputEventMouseButton
		if b != null and b.pressed:
			presses.append([b.button_index, b.position, b.double_click])


var _failures := 0
var _controls: Node
var _hud: StubHud
var _rec: Recorder


func _initialize() -> void:
	var code: int = await _run()
	print("IOS21 TOUCH %s" % ["PASS" if code == 0 else "FAIL"])
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
	_controls = TouchControls.new()
	root.add_child(_controls)
	await process_frame
	# what _ready does on a phone (here it saw neither "mobile" nor --touch)
	_controls.active = true
	_controls.set_process(true)
	Input.emulate_mouse_from_touch = false
	_controls._scale = 1.0
	_controls._hud = _hud
	_controls._apply_edge_scroll()
	_check(_hud.touch_help == [true], "the HUD's help is the touch help (no mouse): %s" % [_hud.touch_help])
	# the first frames of a headless start can be slower than a hold: a 0.6 s wait could end, and the finger lift, in the frame the hold was due
	# (an intermittent failure of the first case); settle first
	await _wait(0.5)

	var a := AUTOCAST.get_center()
	var b := BUTTON.get_center()

	# a hold on a HUD button: the help while held, no click; lifted: off, still no click
	_rec.presses.clear()
	_down(a)
	await _wait(0.6)
	_check(_hud.held == [true], "a hold on a button turns the help on: %s" % [_hud.held])
	_check(_rec.presses.is_empty(), "a hold on a button presses nothing while held: %s" % [_rec.presses])
	_up(a)
	await _wait(0.1)
	_check(_hud.held == [true, false], "lifting turns the help off: %s" % [_hud.held])
	_check(_rec.presses.is_empty(), "lifting presses nothing: %s" % [_rec.presses])
	_check(int(_controls.stats.infos) == 1 and int(_controls.stats.holds) == 0, "counted as an info hold, not a right click")
	await _wait(0.5)

	# sliding off ends the help; nothing is pressed on the way or at the lift
	_hud.held.clear()
	_rec.presses.clear()
	_down(b)
	await _wait(0.6)
	_move(b + Vector2(40, 0))
	await _wait(0.05)
	_check(_hud.held == [true, false], "sliding off past the slop ends the help: %s" % [_hud.held])
	_up(b + Vector2(40, 0))
	await _wait(0.1)
	_check(_rec.presses.is_empty() and _hud.held == [true, false], "after sliding off the lift does nothing: %s" % [_rec.presses])
	await _wait(0.5)

	# a hold in the world: the right click, as before
	_rec.presses.clear()
	_down(WORLD)
	await _wait(0.6)
	_up(WORLD)
	await _wait(0.1)
	_check(_buttons() == [MOUSE_BUTTON_RIGHT], "a hold in the world is a right click: %s" % [_rec.presses])
	await _wait(0.5)

	# two quick taps on the autocast ability: one right press (the toggle), no left press
	_rec.presses.clear()
	await _tap(a)
	await _wait(0.1)
	await _tap(a)
	await _wait(0.6)
	_check(_buttons() == [MOUSE_BUTTON_RIGHT], "a double tap on an autocast ability is its right press only: %s" % [_rec.presses])
	_check(int(_controls.stats.autocast_taps) == 1, "counted as an autocast tap")
	await _wait(0.5)

	# a slow second tap: down inside the window, up after it has passed: still the toggle
	_rec.presses.clear()
	await _tap(a)
	await _wait(0.15)
	_down(a)
	await _wait(0.25)  # past the first tap's DOUBLE_TAP_MS, still under the hold time
	_up(a)
	await _wait(0.6)
	_check(_buttons() == [MOUSE_BUTTON_RIGHT], "a slow second tap still toggles the autocast, no press: %s" % [_rec.presses])
	await _wait(0.5)

	# one tap on the autocast ability: no press at once, one left press after the double tap's window
	_rec.presses.clear()
	await _tap(a)
	await _wait(0.1)
	_check(_rec.presses.is_empty(), "a single tap on an autocast ability waits for a second: %s" % [_rec.presses])
	await _wait(0.5)
	_check(_buttons() == [MOUSE_BUTTON_LEFT], "then it presses the ability once: %s" % [_rec.presses])
	await _wait(0.5)

	# one tap on the ability and at once a tap elsewhere: the ability's press first, then the other tap's
	_rec.presses.clear()
	await _tap(a)
	await _tap(WORLD)
	await _wait(0.6)
	_check(_buttons() == [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_LEFT] and _rec.presses.size() == 2 and Vector2(_rec.presses[0][1]) == a,
		"a finger elsewhere presses the waiting ability first: %s" % [_rec.presses])
	await _wait(0.5)

	# two taps on any other button: two left presses, the second a double click (a bubble queues two units)
	_rec.presses.clear()
	await _tap(b)
	await _wait(0.1)
	await _tap(b)
	await _wait(0.6)
	_check(_buttons() == [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_LEFT] and _rec.presses.size() == 2 and not _rec.presses[0][2] and _rec.presses[1][2],
		"a double tap on another button stays two presses, the second a double click: %s" % [_rec.presses])
	return 0 if _failures == 0 else 1


func _buttons() -> Array:
	return _rec.presses.map(func(p): return p[0])


func _down(at: Vector2) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = at
	t.pressed = true
	_controls._touch(t)


func _up(at: Vector2) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = at
	t.pressed = false
	_controls._touch(t)


func _move(at: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = at
	_controls._drag(d)


func _tap(at: Vector2) -> void:
	_down(at)
	await _wait(0.05)
	_up(at)
	await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
