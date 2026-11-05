## Headless test of lane IOS-40 in the touch layer (scripts/touch/touch_controls.gd, "Button taps"), against a stand-in HUD: no game, no extension needed.
##  * "costs" (the touch default): a tap on a costing button shows its help (hold_help on) and arms it (the gold ring) without a press; a second tap uses it
##    (one left press) and it stays armed, so a third is one more use; a tap elsewhere disarms and goes on as its own tap; the arm runs out after ARM_MS; a quick (non-costing) button presses
##    at once; a tap on another costing button moves the arm there; the same button holding another command arms again; a hold on the armed button is
##    IOS-21's preview and presses nothing; a drag disarms;
##  * an autocast ability: a quick double tap toggles its autocast (the right press only), "tap, read, tap" uses it (the left press only); with
##    lane IOS-42's "Autocast tap" off (OpenBFMETouchAutocastTap = no) the quick double tap arms and uses it;
##  * "all" previews the quick button too; "act" presses a costing button on the first tap.
## The game's own check is the touch self-test (touch_selftest.gd _preview_check: the builder's real build button); the engine's the unit tests "ios40".
##
##   godot --headless --path godot --script res://tests/ios40_touch_test.gd
##
## Exit codes: 0 pass, 1 fail.
extends SceneTree

const TouchControls := preload("res://scripts/touch/touch_controls.gd")

const COST := Rect2(100, 100, 50, 50)   # a build button (DOZER_CONSTRUCT)
const COST2 := Rect2(200, 100, 50, 50)  # another (UNIT_BUILD)
const AUTO := Rect2(300, 100, 50, 50)   # an ability with autocast (SPECIAL_POWER)
const QUICK := Rect2(400, 100, 50, 50)  # stop
const WORLD := Vector2(600, 400)


## InGameHudNode's calls the touch layer makes, answered from the rects
class StubHud:
	extends Node
	var held: Array = []
	var touch_help: Array = []
	var cost_name := "Command_Build"

	func touch_button_at(p: Vector2) -> Dictionary:
		for r in [[COST, "cost", cost_name, true, false], [COST2, "cost2", "Command_Recruit", true, false], [AUTO, "auto", "Command_Blade", true, true],
				[QUICK, "quick", "Command_Stop", false, false]]:
			if Rect2(r[0]).has_point(p):
				return {"kind": "movie", "target": r[1], "name": r[2], "costs": r[3], "autocast": r[4], "slot": -1, "rect": r[0], "command": ""}
		return {"kind": "", "target": "", "autocast": false, "costs": false, "name": "", "slot": -1, "rect": Rect2(), "command": ""}

	func nearest_button(p: Vector2, _radius: float) -> Dictionary:
		return {"snapped": false, "position": p, "reason": "far", "target": ""}

	func hold_help(on: bool) -> void:
		held.append(on)

	func set_touch_help(on: bool) -> void:
		touch_help.append(on)

	func set_edge_scroll(_on: bool) -> void:
		pass

	func set_view_options(_options: Dictionary) -> void:
		pass


## the mouse presses the touch layer makes (button, position)
class Recorder:
	extends Node
	var presses: Array = []

	func _input(event: InputEvent) -> void:
		var b := event as InputEventMouseButton
		if b != null and b.pressed:
			presses.append([b.button_index, b.position])


var _failures := 0
var _controls: Node
var _hud: StubHud
var _rec: Recorder


func _initialize() -> void:
	var code: int = await _run()
	print("IOS40 TOUCH %s" % ["PASS" if code == 0 else "FAIL"])
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
	await _wait(0.5)  # the first frames of a headless start can be slow (ios21_touch_test.gd)
	_check(_controls.button_taps == "costs", "the default is \"Preview what costs\": %s" % _controls.button_taps)
	var c := COST.get_center()

	# 1. tap: the help and the ring, no press; tap again: one left press at the button, still armed; again: a second press (tap, tap, tap queues two)
	await _tap(c)
	await _wait(0.25)
	var armed: Dictionary = _controls.armed_state()
	_check(_rec.presses.is_empty(), "the first tap presses nothing: %s" % [_rec.presses])
	_check(_hud.held == [true], "the first tap shows the help: %s" % [_hud.held])
	_check(armed.armed and armed.ring.get("visible", false) and Vector2(armed.ring.centre) == c, "the button is armed, the ring around it: %s" % [armed])
	await _tap(c)
	await _wait(0.3)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, c]], "the second tap presses it once: %s" % [_rec.presses])
	_check(_hud.held == [true] and _controls.armed_state().armed, "and it stays armed, its help on: %s" % [_hud.held])
	await _tap(c)
	await _wait(0.1)
	await _tap(c)
	await _wait(0.2)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, c], [MOUSE_BUTTON_LEFT, c], [MOUSE_BUTTON_LEFT, c]], "each further tap is one more use, quick ones too: %s" % [
		_rec.presses])
	_controls._disarm()
	_check(_hud.held == [true, false], "disarmed: the help off: %s" % [_hud.held])
	_reset()

	# 2. tap, then a tap elsewhere: disarmed, and the other tap is its own (a left click on the world)
	await _tap(c)
	await _tap(WORLD)
	await _wait(0.3)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, WORLD]], "a tap elsewhere disarms and goes on as its own tap: %s" % [_rec.presses])
	_check(_hud.held == [true, false] and not _controls.armed_state().armed, "the help went: %s" % [_hud.held])
	_reset()

	# 3. the arm runs out
	await _tap(c)
	await _wait(_controls.ARM_MS / 1000.0 + 0.3)
	_check(not _controls.armed_state().armed and _hud.held == [true, false] and _rec.presses.is_empty(), "the arm runs out after %d ms: %s %s" % [
		_controls.ARM_MS, _hud.held, _rec.presses])
	await _tap(c)
	await _wait(0.2)
	_check(_rec.presses.is_empty() and _controls.armed_state().armed, "a tap after the time out arms again, no press: %s" % [_rec.presses])
	_controls._disarm()
	_reset()

	# 4. a quick button presses at once, no arm
	await _tap(QUICK.get_center())
	await _wait(0.2)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, QUICK.get_center()]] and _hud.held.is_empty(), "a quick button presses on the first tap: %s" % [_rec.presses])
	_reset()

	# 5. a tap on another costing button moves the arm there (no press)
	await _tap(c)
	await _wait(0.25)
	await _tap(COST2.get_center())
	await _wait(0.2)
	_check(_rec.presses.is_empty() and str(_controls.armed_state().key) == "movie:cost2" and _hud.held == [true, false, true],
		"another costing button takes the arm: %s %s" % [_controls.armed_state(), _hud.held])
	_controls._disarm()
	_reset()

	# 6. the same button with another command (the selection changed): a first tap again
	await _tap(c)
	await _wait(0.25)
	_hud.cost_name = "Command_Other"
	await _tap(c)
	await _wait(0.2)
	_check(_rec.presses.is_empty() and str(_controls.armed_state().name) == "Command_Other", "a button holding another command arms again: %s" % [_rec.presses])
	_hud.cost_name = "Command_Build"
	_controls._disarm()
	_reset()

	# 7. a hold on the armed button is IOS-21's preview: no press, the arm goes
	await _tap(c)
	await _wait(0.25)
	_down(c)
	await _wait(0.6)
	_up(c)
	await _wait(0.2)
	_check(_rec.presses.is_empty() and not _controls.armed_state().armed, "a hold on the armed button presses nothing: %s" % [_rec.presses])
	_check(int(_controls.stats.infos) == 1, "it was an info hold")
	_reset()

	# 8. a drag from the armed button disarms (and uses nothing)
	var uses := int(_controls.stats.armed_uses)
	await _tap(c)
	await _wait(0.25)
	_down(c)
	_move(c + Vector2(60, 0))
	_up(c + Vector2(60, 0))
	await _wait(0.2)
	# (the drag itself is the HUD's left press-drag-release from where it began, as before: never the armed button's use)
	_check(not _controls.armed_state().armed and int(_controls.stats.armed_uses) == uses, "a drag disarms, no use: %s" % [_rec.presses])
	_reset()

	# 9. an autocast ability: a quick double tap toggles (the right press only); tap, read, tap uses it (the left press only)
	var a := AUTO.get_center()
	await _tap(a)
	await _wait(0.1)
	await _tap(a)
	await _wait(0.25)
	_check(_presses() == [[MOUSE_BUTTON_RIGHT, a]] and int(_controls.stats.autocast_taps) == 1, "a quick double tap toggles the autocast: %s" % [_rec.presses])
	_reset()
	await _tap(a)
	await _wait(0.6)
	await _tap(a)
	await _wait(0.3)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, a]], "tap, read, tap uses the ability: %s" % [_rec.presses])
	_controls._disarm()
	_reset()
	# lane IOS-42: Options > Touch > "Autocast tap" off: a quick double tap on the armed ability is a use, never the toggle
	_controls.apply_options({"OpenBFMETouchAutocastTap": "no"})
	await _tap(a)
	await _wait(0.1)
	await _tap(a)
	await _wait(0.25)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, a]] and int(_controls.stats.autocast_taps) == 1, "IOS-42 Autocast tap off: a quick double tap arms, then uses: %s" % [_rec.presses])
	_controls._disarm()
	_controls.apply_options({})
	_check(_controls.autocast_double_tap, "IOS-42: the key absent is the default (on)")
	_reset()

	# 10. "all": the quick button too; "act": the costing button at once
	_controls.set_button_taps("all")
	await _tap(QUICK.get_center())
	await _wait(0.2)
	_check(_rec.presses.is_empty() and _controls.armed_state().armed, "\"Preview all\" previews a quick button: %s" % [_rec.presses])
	_controls.set_button_taps("act")
	_check(not _controls.armed_state().armed, "\"Act at once\" disarms")
	_reset()
	await _tap(c)
	await _wait(0.2)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, c]] and _hud.held.is_empty(), "\"Act at once\" presses a costing button on the first tap: %s" % [_rec.presses])
	return 0 if _failures == 0 else 1


func _presses() -> Array:
	return _rec.presses.map(func(p): return [p[0], Vector2(p[1])])


func _reset() -> void:
	_rec.presses.clear()
	_hud.held.clear()


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
