## Headless test of lane IOS-45 in the touch layer (scripts/touch/touch_controls.gd): the input events of the extension's input bridge
## (engine/src/GodotDevice/GodotIOSTouch.mm, the shared design after daisyhasacat/openbfme-godot), with a stand-in for IOSInputDevices: no game, no
## extension needed.
##  * IOS-17: a mouse is in use only once a pointer showed itself (the bridge's motion), never because GameController lists one; the touch layer's own
##    mouse events (TOUCH_DEVICE) and an Apple Pencil's (PENCIL_DEVICE) are no mouse; a trackpad's scroll or pinch is; when the last mouse goes (the
##    count drops to 0) touch play is back until a pointer shows itself again; on a desktop (no IOSInputDevices) no mouse event counts;
##  * IOS-14: the bridge's scroll (InputEventPanGesture, the macOS scale) becomes wheel notches, one per WHEEL_STEP_PT (up for a scroll that moves the
##    content down), a shorter scroll one notch once it pauses; the gesture itself is handled (no Godot list scrolls twice);
##  * IOS-14: the bridge's release of a key Godot missed names no side: a right modifier's press is released as it was pressed (KEY_LOCATION_RIGHT);
##    Godot's own release adds nothing; the keys still held are released when the app loses the focus.
## The click logic of the bridge itself is the engine's unit test (engine/tests/test_ios_pointer.cpp); the device behaviour wants an iPad.
##
##   godot --headless --path godot --script res://tests/ios45_touch_test.gd
##
## Exit codes: 0 pass, 1 fail.
extends SceneTree

const TouchControls := preload("res://scripts/touch/touch_controls.gd")


class Recorder:
	extends Node
	var buttons: Array = []
	var keys: Array = []

	func _input(event: InputEvent) -> void:
		var b := event as InputEventMouseButton
		if b != null:
			buttons.append([b.button_index, b.pressed, b.device])
		var k := event as InputEventKey
		if k != null:
			keys.append([k.physical_keycode, k.pressed, k.location, k.device])


## the extension's IOSInputDevices: GCMouse's count is set by the test
class StubDevices:
	extends RefCounted
	var mice := 1

	func status() -> Dictionary:
		return {"mice": mice, "keyboard": true, "on_mac": false}


var _failures := 0
var _controls: Node
var _rec: Recorder


func _initialize() -> void:
	var code: int = await _run()
	print("IOS45 TOUCH %s" % ["PASS" if code == 0 else "FAIL"])
	quit(code)


func _check(ok: bool, what: String) -> void:
	print("  ", "ok   " if ok else "FAIL ", what)
	if not ok:
		_failures += 1


func _run() -> int:
	_rec = Recorder.new()
	root.add_child(_rec)
	_controls = TouchControls.new()
	root.add_child(_controls)
	await process_frame
	# what _ready does on a phone (here it saw neither "mobile" nor --touch)
	_controls.active = true
	_controls.set_process(true)
	Input.emulate_mouse_from_touch = false

	# ---- a desktop: no IOSInputDevices, no mouse event is the bridge's -------------------------------------------------------------------------------
	_controls._input(_motion(Vector2(100, 100), 0))
	_check(not _controls.mouse_connected() and not _controls._pointer_seen, "a desktop: no mouse in use (no IOSInputDevices)")

	# ---- IOS-17: in use once it shows itself ---------------------------------------------------------------------------------------------------------
	var devices := StubDevices.new()
	_controls._devices = devices
	_controls._mice = 1
	await _wait(0.4)
	_check(not _controls.mouse_connected() and not _controls._mouse, "a mouse GameController lists (the Duo's phantom) is not in use")
	_controls._bridge_event(_motion(Vector2(100, 100), TouchControls.TOUCH_DEVICE))
	_controls._bridge_event(_button(Vector2(100, 100), true, TouchControls.TOUCH_DEVICE))
	_check(not _controls.mouse_connected(), "the touch layer's own mouse events are no mouse")
	_controls._bridge_event(_button(Vector2(100, 100), true, TouchControls.PENCIL_DEVICE))
	_controls._bridge_event(_motion(Vector2(110, 100), TouchControls.PENCIL_DEVICE))
	_controls._bridge_event(_button(Vector2(110, 100), false, TouchControls.PENCIL_DEVICE))
	_check(not _controls.mouse_connected() and int(_controls.stats.pencil_presses) == 1, "an Apple Pencil's stroke is no mouse (one Pencil press counted)")
	_controls._bridge_event(_motion(Vector2(200, 120), 0))
	await _wait(0.1)
	_check(_controls.mouse_connected() and _controls._mouse, "the bridge's hover: a mouse in use (within a frame)")

	# the last mouse goes: touch play again
	devices.mice = 0
	await _wait(0.4)
	_check(not _controls.mouse_connected() and not _controls._mouse, "the last mouse went: no mouse in use")
	# a trackpad's scroll or pinch shows a pointer too (a host that lists no GCMouse keeps it: the reset is on a count that drops)
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 1.1
	_controls._bridge_event(pinch)
	await _wait(0.4)
	_check(_controls.mouse_connected() and _controls._mouse, "a trackpad's pinch: a pointer in use, kept with no GCMouse listed")
	_controls._pointer_seen = false

	# ---- IOS-14: scrolling in wheel notches ----------------------------------------------------------------------------------------------------------
	_rec.buttons.clear()
	_scroll(30.0)  # 30 points that move the content down (a wheel turned up): two notches, 6 points over
	await _wait(0.05)
	_check(_wheels() == [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_UP], "a 30 pt scroll is two wheel-up notches at once: %s" % [_wheels()])
	await _wait(0.3)
	_check(_wheels().size() == 2, "its 6 pt over makes no notch when it ends: %s" % [_wheels()])
	_check(_rec.buttons.all(func(b): return b[2] == TouchControls.TOUCH_DEVICE), "the notches are the touch layer's own events: %s" % [_rec.buttons])
	_rec.buttons.clear()
	_scroll(-4.0)
	await _wait(0.05)
	_check(_wheels().is_empty(), "a 4 pt scroll the other way: no notch while it lasts")
	await _wait(0.3)
	_check(_wheels() == [MOUSE_BUTTON_WHEEL_DOWN], "... one wheel-down notch once it paused: %s" % [_wheels()])
	_check(_controls.mouse_connected(), "a scroll shows a pointer")

	# ---- IOS-14: a missed key release ----------------------------------------------------------------------------------------------------------------
	_rec.keys.clear()
	_controls._on_window_input(_key(KEY_CTRL, true, KEY_LOCATION_RIGHT))
	_controls._on_window_input(_key(KEY_CTRL, false, KEY_LOCATION_UNSPECIFIED))  # the bridge's release (GCKeyboard): no side
	await _wait(0.05)
	_check(_rec.keys == [[KEY_CTRL, false, KEY_LOCATION_RIGHT, TouchControls.BRIDGE_DEVICE]] and not _controls._keys_down.has(KEY_CTRL),
		"the bridge's release of the right Control: released again as pressed (right): %s" % [_rec.keys])
	_rec.keys.clear()
	_controls._on_window_input(_key(KEY_SHIFT, true, KEY_LOCATION_RIGHT))
	_controls._on_window_input(_key(KEY_SHIFT, false, KEY_LOCATION_RIGHT))  # Godot's own
	_controls._on_window_input(_key(KEY_A, true, KEY_LOCATION_UNSPECIFIED))
	_controls._on_window_input(_key(KEY_A, false, KEY_LOCATION_UNSPECIFIED))
	await _wait(0.05)
	_check(_rec.keys.is_empty() and _controls._keys_down.is_empty(), "Godot's own releases add nothing: %s" % [_rec.keys])
	_controls._on_window_input(_key(KEY_UP, true, KEY_LOCATION_UNSPECIFIED))
	_controls._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _wait(0.05)
	_check(_rec.keys == [[KEY_UP, false, KEY_LOCATION_UNSPECIFIED, TouchControls.BRIDGE_DEVICE]], "a key held as the focus goes is released: %s" % [_rec.keys])

	_controls._devices = null
	return 1 if _failures > 0 else 0


func _motion(at: Vector2, device: int) -> InputEventMouseMotion:
	var m := InputEventMouseMotion.new()
	m.device = device
	m.position = at
	m.global_position = at
	return m


func _button(at: Vector2, down: bool, device: int) -> InputEventMouseButton:
	var b := InputEventMouseButton.new()
	b.device = device
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = down
	b.position = at
	b.global_position = at
	return b


## `points` of UIKit scrolling (+: the content moves down) as the bridge reports it: pan gestures of the macOS scale, in three steps
func _scroll(points: float) -> void:
	for i in 3:
		var pan := InputEventPanGesture.new()
		pan.position = Vector2(300, 200)
		pan.delta = Vector2(0, -points / 3.0 * TouchControls.PAN_PER_PT)
		_controls._bridge_event(pan)


func _key(code: Key, down: bool, location: KeyLocation) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.keycode = code
	k.pressed = down
	k.location = location
	return k


func _wheels() -> Array:
	return _rec.buttons.filter(func(b): return b[1]).map(func(b): return b[0])


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
