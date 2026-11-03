extends Node
## Lane IOS-2 (prototype, for the owner's review): touch controls for phones and tablets.
##
## The game itself only knows the mouse (InGameHudNode and AptMenuPlayer read Godot mouse events and give them to the SAGE input), so the
## touches are translated here into the mouse events a player would make, plus two camera gestures the mouse has no single event for.
## Nothing below changes the mouse path: on a desktop without --touch this node does nothing.
##
##   one finger, tap ............ left click (select; with the touch default of Alternate Mouse Setup the left click also orders)
##   one finger, two quick taps . double click (select all of that type on screen)
##   one finger, drag ........... left drag (a selection box; in a menu, a list or slider drag)
##   one finger, hold ........... right click (deselect / cancel; on an ability button: autocast) with a short vibration
##   two fingers, drag .......... pan the camera: the ground under the fingers stays under them
##   two fingers, pinch ......... zoom (the mouse wheel's notches)
##   two fingers, quick tap ..... right click at their middle
##
## Active on a mobile build (OS feature "mobile") or with `-- --touch` (to try it on a desktop with a touch screen or synthetic events).
## The thresholds are in points (DisplayServer.screen_get_scale), so they are the same physical size on any screen.
##
## Lane IOS-10 (prototype, for the owner's review), the menus and the HUD for fingers:
##   tap assist ................. a tap on no button but within ASSIST_PT of one presses that button (its centre); a tap that hits a control
##                                never moves, nor one that picks a unit / building, aims a placement, a power or a command, or lands on the
##                                radar; a tap about as near two buttons (ASSIST_TIE_PT) stays where it is. AptMenuPlayer / InGameHudNode
##                                nearest_button decide (the controls the pointer could press now). Counted in stats.assisted_taps.
##   one finger, drag on a list . scrolls the list (a mouse wheel notch per row of finger travel) instead of a press-and-drag; a drag that
##                                starts on its scroll bar still drags the bar. Menus only (over a game: while a menu has the input).
## `-- --no-tap-assist` / `-- --no-list-scroll` turn either off for a comparison.

const TAP_MAX_MS := 280          # a finger down longer than this is not a tap
const LONG_PRESS_MS := 450       # a still finger held this long is a right click
const SLOP_PT := 10.0            # movement under this is still a tap / hold (points)
const DOUBLE_TAP_MS := 320       # two taps within this ...
const DOUBLE_TAP_PT := 24.0      # ... and this distance are a double click
const PINCH_STEP := 0.12         # a 12 % change of the fingers' distance is one wheel notch
const ASSIST_PT := 9.0           # lane IOS-10: the tap assist's reach from a button's edge (points)
const ASSIST_TIE_PT := 3.0       # lane IOS-10: a second button within this much of the nearest one's distance makes the tap ambiguous: no assist

enum Gesture { NONE, PENDING, DRAG, HELD, TWO, SCROLL }

var active := false
var _gesture := Gesture.NONE
var _fingers := {}               # index -> {"start": Vector2, "pos": Vector2, "at": int}
var _first := -1                 # the finger of a one-finger gesture
var _two_start_ms := 0
var _two_moved := false
var _pinch_base := 0.0           # the fingers' distance at the last wheel notch
var _last_centroid := Vector2.ZERO
var _last_tap_ms := -100000
var _last_tap_pos := Vector2(-1000, -1000)
var _hud: Node = null            # the game's InGameHudNode while a game is on screen
var _menus: Node = null          # lane IOS-10: the shell's AptMenuPlayer (the menus' tap assist and lists)
var _scale := 1.0                # pixels per point
var tap_assist := true           # lane IOS-10
var list_scroll := true          # lane IOS-10
var _scroll_at := Vector2.ZERO   # lane IOS-10: where the list drag began (the wheel's pointer stays there)
var _scroll_anchor := 0.0        # the finger's stage y at the last notch
var _scroll_row := 0.0           # stage pixels of finger travel per notch (the list's row height)
var stats := {"taps": 0, "double_taps": 0, "drags": 0, "holds": 0, "pans": 0, "zoom_notches": 0, "two_finger_taps": 0, "assisted_taps": 0,
	"list_scrolls": 0}


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--gpu-probe"):
		add_child(preload("res://scripts/touch/gpu_probe.gd").new()) # lane IOS-7: frame cost on any platform
	active = OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")
	set_process(active)
	set_process_input(active)
	if not active:
		return
	Input.emulate_mouse_from_touch = false  # this node makes the mouse events; Godot's own translation would make a second set
	_scale = maxf(1.0, DisplayServer.screen_get_scale())
	tap_assist = not OS.get_cmdline_user_args().has("--no-tap-assist")
	list_scroll = not OS.get_cmdline_user_args().has("--no-list-scroll")
	print("TOUCH controls on (%s), %.1f px per point" % ["mobile" if OS.has_feature("mobile") else "--touch", _scale])
	print("TOUCH arguments: engine %s, game %s" % [OS.get_cmdline_args(), OS.get_cmdline_user_args()])
	print("TOUCH tap assist %s (%.0f pt), list scrolling %s" % ["on" if tap_assist else "off", ASSIST_PT, "on" if list_scroll else "off"])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--touch-selftest="):
			var test: Node = preload("res://scripts/touch/touch_selftest.gd").new()
			add_child(test)
			test.start(self, a.trim_prefix("--touch-selftest="))


func is_active() -> bool:
	return active


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_drag(event)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# the hold: a still finger that stays down becomes a right click while it is still down (the player feels it fire)
	if _gesture == Gesture.PENDING and _fingers.has(_first) and Time.get_ticks_msec() - int(_fingers[_first].at) >= LONG_PRESS_MS:
		var at: Vector2 = _fingers[_first].pos
		_click(MOUSE_BUTTON_RIGHT, at)
		Input.vibrate_handheld(15)
		_gesture = Gesture.HELD
		stats.holds += 1


func _touch(e: InputEventScreenTouch) -> void:
	var now := Time.get_ticks_msec()
	if e.pressed:
		_fingers[e.index] = {"start": e.position, "pos": e.position, "at": now}
		match _fingers.size():
			1:
				_gesture = Gesture.PENDING
				_first = e.index
				_move(e.position)  # the pointer goes where the finger is (the game's hover, the cursor's picture)
			2:
				if _gesture == Gesture.DRAG:
					_button(MOUSE_BUTTON_LEFT, false, _fingers[_first].pos)  # a second finger ends the drag where it is
				# (a list scroll just stops: it pressed nothing)
				_gesture = Gesture.TWO
				_two_start_ms = now
				_two_moved = false
				_pinch_base = _distance()
				_last_centroid = _centroid()
		return
	if not _fingers.has(e.index):
		return
	_fingers[e.index].pos = e.position
	match _gesture:
		Gesture.PENDING:
			_tap(e.position, now)  # up before the hold fired and without moving: a tap
		Gesture.DRAG:
			_button(MOUSE_BUTTON_LEFT, false, e.position)
		Gesture.TWO:
			if _fingers.size() == 2 and not _two_moved and now - _two_start_ms <= TAP_MAX_MS:
				_click(MOUSE_BUTTON_RIGHT, _centroid())
				stats.two_finger_taps += 1
	_fingers.erase(e.index)
	if _fingers.is_empty():
		_gesture = Gesture.NONE
		_first = -1
	elif _gesture == Gesture.TWO:
		_gesture = Gesture.HELD  # one finger of two lifted: nothing more until both are up (no surprise click or box)


func _drag(e: InputEventScreenDrag) -> void:
	if not _fingers.has(e.index):
		return
	_fingers[e.index].pos = e.position
	match _gesture:
		Gesture.PENDING:
			if e.index == _first and e.position.distance_to(_fingers[e.index].start) > SLOP_PT * _scale:
				if _begin_list_scroll(_fingers[e.index].start):
					_gesture = Gesture.SCROLL
					stats.list_scrolls += 1
					_scroll_list(e.position)
				else:
					_gesture = Gesture.DRAG
					stats.drags += 1
					_button(MOUSE_BUTTON_LEFT, true, _fingers[e.index].start)
					_move(e.position)
		Gesture.DRAG:
			if e.index == _first:
				_move(e.position)
		Gesture.SCROLL:
			if e.index == _first:
				_scroll_list(e.position)
		Gesture.TWO:
			_two_finger_move()


func _tap(at: Vector2, now: int) -> void:
	var double := now - _last_tap_ms <= DOUBLE_TAP_MS and at.distance_to(_last_tap_pos) <= DOUBLE_TAP_PT * _scale
	var assist := assist_probe(at)
	if assist.snapped:
		stats.assisted_taps += 1
	_click(MOUSE_BUTTON_LEFT, assist.position, double)
	if double:
		stats.double_taps += 1
		_last_tap_ms = -100000  # a third tap starts over
	else:
		stats.taps += 1
		_last_tap_ms = now
		_last_tap_pos = at


func _two_finger_move() -> void:
	if _fingers.size() != 2:
		return
	var c := _centroid()
	var d := _distance()
	if not _two_moved and (c.distance_to(_last_centroid) > SLOP_PT * _scale or absf(d - _pinch_base) > SLOP_PT * _scale):
		_two_moved = true
	if not _two_moved:
		return
	var hud := _game_hud()
	if hud != null:
		# pan: the world point under the fingers' middle stays under it
		var was: Vector2 = hud.pixel_to_world(_last_centroid)
		var now_at: Vector2 = hud.pixel_to_world(c)
		var cam: Dictionary = hud.get_camera()
		if cam.has("position") and was.is_finite() and now_at.is_finite():
			hud.camera_look_at(Vector2(cam.position) + (was - now_at))
			stats.pans += 1
		# pinch: whole wheel notches, apart (zoom in) or together (zoom out)
		if _pinch_base > 0.0:
			var ratio := d / _pinch_base
			while ratio >= 1.0 + PINCH_STEP:
				hud.inject_mouse_wheel(1, c)
				_pinch_base *= 1.0 + PINCH_STEP
				ratio = d / _pinch_base
				stats.zoom_notches += 1
			while ratio <= 1.0 / (1.0 + PINCH_STEP):
				hud.inject_mouse_wheel(-1, c)
				_pinch_base /= 1.0 + PINCH_STEP
				ratio = d / _pinch_base
				stats.zoom_notches += 1
	_last_centroid = c


func _centroid() -> Vector2:
	var sum := Vector2.ZERO
	for f in _fingers.values():
		sum += f.pos
	return sum / maxf(1.0, _fingers.size())


func _distance() -> float:
	var p: Array = _fingers.values()
	return p[0].pos.distance_to(p[1].pos) if p.size() >= 2 else 0.0


## the game's HUD node while a game is on screen (null in the menus); edge scrolling goes off for touch the first time it is found
func _game_hud() -> Node:
	if is_instance_valid(_hud) and _hud.is_inside_tree():
		return _hud
	var found := get_tree().root.find_children("*", "InGameHudNode", true, false)
	_hud = found[0] if not found.is_empty() else null
	if _hud != null:
		_hud.set_edge_scroll(false)  # a finger near the edge is not a wish to scroll
		print("TOUCH game HUD found: edge scrolling off")
	return _hud


## lane IOS-10: the shell's AptMenuPlayer (the menus), or null before it boots
func _menu_player() -> Node:
	if is_instance_valid(_menus) and _menus.is_inside_tree():
		return _menus
	_menus = null
	for p in get_tree().root.find_children("*", "AptMenuPlayer", true, false):
		if p.is_booted():
			_menus = p
			break
	return _menus


## lane IOS-10: where a tap at `at` presses: { position, snapped, target, reason } (no click, nothing counted; touch_selftest.gd asks it too).
## Over a game the HUD answers (its buttons, or a menu over it), else the menus. A tap the answer leaves alone keeps its own point.
func assist_probe(at: Vector2) -> Dictionary:
	var out := {"position": at, "snapped": false, "target": "", "reason": "off"}
	if not tap_assist:
		return out
	var source: Node = _game_hud()
	if source == null:
		source = _menu_player()
	if source == null or not source.has_method("nearest_button"):
		out.reason = "no source"  # in a game's load, or an extension built before lane IOS-10
		return out
	var r: Dictionary = source.nearest_button(at, ASSIST_PT * _scale)
	out.target = str(r.get("target", ""))
	out.reason = str(r.get("reason", ""))
	if not r.get("snapped", false):
		return out
	var runner_up := float(r.get("runner_up", -1.0))
	if runner_up >= 0.0 and runner_up - float(r.get("distance", 0.0)) < ASSIST_TIE_PT * _scale:
		out.reason = "between two"
		return out
	out.position = r.position
	out.snapped = true
	return out


## lane IOS-10: a one-finger drag that starts on a list box scrolls it (true: the gesture is a list scroll). Never over a game's world: there a
## drag is a selection box; only while a menu has the input (the save / load list over a game)
func _begin_list_scroll(start: Vector2) -> bool:
	if not list_scroll:
		return false
	var menus := _menu_player()
	if menus == null or not menus.has_method("scroll_list_at"):
		return false
	if _game_hud() != null and not menus.modal_menu():
		return false
	var list: Dictionary = menus.scroll_list_at(start)
	var row := float(list.get("row_height", 0))
	if not list.get("found", false) or row <= 0.0:
		return false  # an empty list has nothing to scroll: the drag stays a drag
	_scroll_at = start
	_scroll_row = row
	_scroll_anchor = menus.window_to_stage(start).y
	return true


## the finger's travel since the last notch, in rows: a notch each (the content follows the finger: up shows the later rows, the wheel's down)
func _scroll_list(at: Vector2) -> void:
	var menus := _menu_player()
	if menus == null:
		return
	var travel: float = _scroll_anchor - menus.window_to_stage(at).y
	while travel >= _scroll_row:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN, _scroll_at)
		_scroll_anchor -= _scroll_row
		travel -= _scroll_row
	while travel <= -_scroll_row:
		_wheel(MOUSE_BUTTON_WHEEL_UP, _scroll_at)
		_scroll_anchor += _scroll_row
		travel += _scroll_row


func _wheel(button: MouseButton, at: Vector2) -> void:
	for down in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = button
		b.pressed = down
		b.factor = 1.0
		b.position = at
		b.global_position = at
		Input.parse_input_event(b)


func _move(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if _gesture == Gesture.DRAG else 0
	Input.parse_input_event(m)


func _button(button: MouseButton, down: bool, at: Vector2, double := false) -> void:
	_move(at)
	var b := InputEventMouseButton.new()
	b.button_index = button
	b.pressed = down
	b.position = at
	b.global_position = at
	b.double_click = double and down
	b.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if down else 0
	Input.parse_input_event(b)


func _click(button: MouseButton, at: Vector2, double := false) -> void:
	_button(button, true, at, double)
	_button(button, false, at)
