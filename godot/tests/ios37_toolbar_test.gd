## Headless test of lane IOS-37's command toolbar (scripts/touch/command_toolbar.gd through scripts/touch/touch_controls.gd), against a stand-in HUD: no game,
## no extension needed.
##  * the strip shows in a game (a HUD with command_hotkey), inside the view at the top, 44 pt cells; hidden with the option off and while a mouse is in use;
##  * a tap presses the button's key as the CommandMap has it (Select army: Q; Stop: S; Home base: H; Last event: Space; a group: its digit), the Menu
##    Escape, Attack move the selection's Attack Move hotkey, Deselect the HUD's deselect_all; no mouse event reaches the game;
##  * a hold shows the help line and presses nothing; sliding off and lifting does nothing; a second finger cancels;
##  * Groups opens the groups' row; a hold on a group presses Ctrl+digit (Ctrl down first, up last) once, with nothing selected nothing;
##  * Deselect and Stop are disabled with nothing selected (a tap on them does nothing), Attack move without the selection's button.
## The game's own check is the touch self-test (touch_selftest.gd _toolbar_check: the metas the game made).
##
##   godot --headless --path godot --script res://tests/ios37_toolbar_test.gd
##
## Exit codes: 0 pass, 1 fail.
extends SceneTree

const TouchControls := preload("res://scripts/touch/touch_controls.gd")


## InGameHudNode's calls the touch layer and the toolbar make
class StubHud:
	extends Node
	var selection: Array = [7]
	var deselects := 0
	var attack := {"found": true, "key": "a", "enabled": true}

	func touch_button_at(_p: Vector2) -> Dictionary:
		return {"kind": "", "target": "", "autocast": false, "costs": false, "name": "", "slot": -1, "rect": Rect2(), "command": ""}

	func nearest_button(p: Vector2, _radius: float) -> Dictionary:
		return {"snapped": false, "position": p, "reason": "far", "target": ""}

	func touch_placement_at(_p: Vector2) -> Dictionary:
		return {"placing": false, "line_build": false, "world": true, "builds": 0}

	func get_command_map() -> Array:
		return [{"name": "SELECT_ALL", "key": "KEY_Q", "transition": 0, "ctrl": false, "shift": false, "alt": false, "game": true},
			{"name": "STOP", "key": "KEY_S", "transition": 0, "ctrl": false, "shift": false, "alt": false, "game": true},
			{"name": "VIEW_HOME_BASE", "key": "KEY_H", "transition": 0, "ctrl": false, "shift": false, "alt": false, "game": true},
			{"name": "VIEW_LAST_RADAR_EVENT", "key": "KEY_SPACE", "transition": 0, "ctrl": false, "shift": false, "alt": false, "game": true},
			{"name": "SELECT_TEAM3", "key": "KEY_3", "transition": 0, "ctrl": false, "shift": false, "alt": false, "game": true},
			{"name": "CREATE_TEAM3", "key": "KEY_3", "transition": 0, "ctrl": true, "shift": false, "alt": false, "game": true}]

	func get_selection() -> Array:
		return selection

	func deselect_all() -> bool:
		deselects += 1
		var had := not selection.is_empty()
		selection = []
		return had

	func command_hotkey(_command: String) -> Dictionary:
		return attack

	func hold_help(_on: bool) -> void:
		pass

	func set_touch_help(_on: bool) -> void:
		pass

	func set_edge_scroll(_on: bool) -> void:
		pass

	func set_view_options(_options: Dictionary) -> void:
		pass


## the key and mouse events the game would see
class Recorder:
	extends Node
	var keys: Array = []
	var mouse := 0

	func _input(event: InputEvent) -> void:
		var k := event as InputEventKey
		if k != null:
			keys.append([OS.get_keycode_string(k.physical_keycode), k.pressed, k.ctrl_pressed])
		elif event is InputEventMouseButton:
			mouse += 1


var _failures := 0
var _controls: Node
var _hud: StubHud
var _rec: Recorder


func _initialize() -> void:
	var code: int = await _run()
	print("IOS37 TOOLBAR %s" % ["PASS" if code == 0 else "FAIL"])
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
	_controls.active = true
	_controls.set_process(true)
	Input.emulate_mouse_from_touch = false
	_controls._scale = 1.0
	_controls._hud = _hud
	_controls._apply_edge_scroll()
	await _wait(0.6)  # past a TOOLBAR_POLL_MS: the strip is made and shown
	var t = _controls._toolbar
	_check(t != null and t.is_shown(), "the toolbar shows in a game")
	if t == null:
		return 1
	var r: Rect2 = t.rect()
	_check(r.position == Vector2(6, 4), "it starts at the view's top left, MARGIN_PT and TOP_PT in: %s" % [r])
	_check(Rect2(t.state().buttons.army.rect).size == Vector2(44, 44), "a button is a 44 pt cell: %s" % [t.state().buttons.army.rect])

	# taps: the CommandMap's keys, no mouse event
	await _tap_button("army")
	_check(_rec.keys == [["Q", true, false], ["Q", false, false]], "Select army presses Q: %s" % [_rec.keys])
	await _tap_button("stop")
	_check(_rec.keys == [["S", true, false], ["S", false, false]], "Stop presses S: %s" % [_rec.keys])
	await _tap_button("base")
	_check(_rec.keys == [["H", true, false], ["H", false, false]], "Home base presses H: %s" % [_rec.keys])
	await _tap_button("event")
	_check(_rec.keys == [["Space", true, false], ["Space", false, false]], "Last event presses Space: %s" % [_rec.keys])
	await _tap_button("attack")
	_check(_rec.keys == [["A", true, false], ["A", false, false]], "Attack move presses the selection's hotkey A: %s" % [_rec.keys])
	await _tap_button("menu")
	_check(_rec.keys == [["Escape", true, false], ["Escape", false, false]], "Menu presses Escape: %s" % [_rec.keys])
	_check(_rec.mouse == 0, "no mouse event reached the game: %d" % _rec.mouse)

	# a hold: the help line, no key; sliding off: nothing; a second finger: nothing
	_rec.keys.clear()
	var stop: Vector2 = Rect2(t.state().buttons.stop.rect).get_center()
	_down(0, stop)
	await _wait(0.6)
	var tip := str(t.state().tip)
	_up(0, stop)
	await _wait(0.1)
	_check(tip.begins_with("Stop (S)") and _rec.keys.is_empty(), "a hold shows the help (\"%s\") and presses nothing: %s" % [tip, _rec.keys])
	_down(0, stop)
	_move(0, stop + Vector2(0, 80))
	_up(0, stop + Vector2(0, 80))
	await _wait(0.1)
	_check(_rec.keys.is_empty(), "sliding off and lifting presses nothing: %s" % [_rec.keys])
	_down(0, stop)
	_down(1, stop + Vector2(300, 300))
	_up(0, stop)
	_up(1, stop + Vector2(300, 300))
	await _wait(0.1)
	_check(_rec.keys.is_empty(), "a second finger cancels the press: %s" % [_rec.keys])

	# control groups: the row; a hold on 3 makes the group (Ctrl+3, once); a tap selects it (3)
	await _tap_button("groups")
	_check(t.state().drawer and t.state().buttons.group3.visible, "Groups opens the groups' row")
	_rec.keys.clear()
	var g3: Vector2 = Rect2(t.state().buttons.group3.rect).get_center()
	_down(0, g3)
	await _wait(0.75)
	_up(0, g3)
	await _wait(0.1)
	_check(_rec.keys == [["Ctrl", true, true], ["3", true, true], ["3", false, true], ["Ctrl", false, false]],
		"a hold on 3 presses Ctrl+3 once, Ctrl around it: %s" % [_rec.keys])
	_check(int(_controls.stats.groups_made) == 1, "counted as a group made")
	await _tap_button("group3")
	_check(_rec.keys == [["3", true, false], ["3", false, false]], "a tap on 3 presses 3: %s" % [_rec.keys])

	# Deselect: the HUD's deselect_all; then Deselect and Stop are disabled and do nothing, nor does a group's hold
	await _tap_button("deselect")
	_check(_hud.deselects == 1 and _hud.selection.is_empty(), "Deselect calls deselect_all")
	await _wait(0.4)  # a TOOLBAR_POLL_MS: the states follow the selection
	_check(not t.is_enabled("deselect") and not t.is_enabled("stop"), "Deselect and Stop are disabled with nothing selected")
	await _tap_button("stop")
	_check(_rec.keys.is_empty(), "a tap on the disabled Stop presses nothing: %s" % [_rec.keys])
	_down(0, g3)
	await _wait(0.75)
	_up(0, g3)
	await _wait(0.1)
	_check(_rec.keys.is_empty() and str(t.state().tip).begins_with("Select units first"), "a group's hold with nothing selected makes nothing: %s" % [
		_rec.keys])
	_hud.attack = {"found": false, "key": "", "enabled": false}
	await _wait(0.4)
	_check(not t.is_enabled("attack"), "Attack move is disabled without the selection's button")

	# the option off, and a mouse in use: hidden
	_controls.set_toolbar(false)
	await _wait(0.4)
	_check(not t.is_shown(), "the option off hides it")
	_controls.set_toolbar(true)
	_controls._mouse = true
	await _wait(0.4)
	_check(not t.is_shown(), "a mouse in use hides it")
	_controls._mouse = false
	await _wait(0.4)
	_check(t.is_shown(), "and it is back")
	return 0 if _failures == 0 else 1


func _tap_button(id: String) -> void:
	_rec.keys.clear()
	var at: Vector2 = Rect2(_controls._toolbar.state().buttons[id].rect).get_center()
	_down(0, at)
	await _wait(0.05)
	_up(0, at)
	await process_frame


func _down(index: int, at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = true
	_controls._touch(e)


func _up(index: int, at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = false
	_controls._touch(e)


func _move(index: int, at: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = index
	d.position = at
	_controls._drag(d)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
