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
##   two fingers, twist ......... turn the camera (lane IOS-15; past an 8 degree turn, so pinches and pans do not turn it)
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
##
## Lane IOS-14, a mouse, a trackpad and a hardware keyboard (an iPad's, the simulator's with the Mac's pointer captured, the iPhone build on an
## Apple Silicon Mac). Godot's iOS layer knows no mouse: a click reaches it as a screen touch (left only: a tap on release, a hold a right click),
## with no hover, no right button and no wheel. The extension's IOSPointer (engine/src/GodotDevice/IOSPointerBridge.mm, iOS builds only; on a
## desktop ClassDB has no such class and nothing below runs) reads them from UIKit and GameController; _pump_bridge makes them mouse events:
##   the pointer ................ mouse motion as it hovers: the game's hover, tooltips and edge scrolling (kept on while a mouse is there)
##   a click .................... the left button pressed and released when the button is (no tap delay, no hold), drags with the button held
##   right / middle button ...... GCMouse's (or UIKit's secondary click)
##   wheel, two-finger scroll ... wheel notches, one per WHEEL_STEP_PT of scrolling (a shorter scroll still one notch)
## The de-duplication: UIKit hands Godot each click as a screen touch too. The bridge's touch observer on Godot's view sees that touch before
## the view does and records where it began when it is the pointer's: a touch of type indirect pointer, or (UIKit's compatibility mode, without
## UIApplicationSupportsIndirectInputEvents) a direct touch beginning within 6 pt of the last hover or within 150 ms of GCMouse's left button.
## A screen touch here that begins within 2 px of such a record (at most 1 s old; each record matches once) is the mouse's: that index's whole
## sequence (its drags and its release) is dropped, the bridge's own button events stand for it. Every other touch is a finger and keeps the
## controls above, with a mouse connected too; a release of an index this node never saw pressed (Godot sends stray ones) is dropped as well.
## The pointer: fingers move it as before (a tap is a click where the finger is); bridge motion is not applied while a finger is down, and the
## next hover puts it back under the mouse.
## Keys: on the Mac host Godot's iOS layer delivers a hardware key's press but never its release (the game then holds an arrow key forever).
## Godot's presses stay as they are (they carry the layout's character); GCKeyboard's release of a key whose press Godot delivered and whose
## release Godot did not is sent as that press's release (_repair_key_releases). Where Godot's own release does come, nothing is added.

const TAP_MAX_MS := 280          # a finger down longer than this is not a tap
const LONG_PRESS_MS := 450       # a still finger held this long is a right click
const SLOP_PT := 10.0            # movement under this is still a tap / hold (points)
const DOUBLE_TAP_MS := 320       # two taps within this ...
const DOUBLE_TAP_PT := 24.0      # ... and this distance are a double click
const PINCH_STEP := 0.12         # a 12 % change of the fingers' distance is one wheel notch
const TWIST_START_DEG := 8.0     # lane IOS-15: the fingers must turn this much before the camera turns (a pinch or pan wobbles a little)
const ASSIST_PT := 9.0           # lane IOS-10: the tap assist's reach from a button's edge (points)
const ASSIST_TIE_PT := 3.0       # lane IOS-10: a second button within this much of the nearest one's distance makes the tap ambiguous: no assist
const WHEEL_STEP_PT := 12.0      # lane IOS-14: a wheel notch per this much scrolling (UIKit points); to tune from the "TOUCH IOS-14 scroll" lines
const KEY_UP_GRACE_MS := 30      # lane IOS-14: a keyboard release waits this long for Godot's own (a host that delivers it gets no second one) ...
const KEY_UP_WAIT_MS := 250      # ... and this long for a press Godot delivers late
const BRIDGE_DEVICE := 0x14      # lane IOS-14: the device id of the key releases made here (Godot's own keys are device 0)
const LEAVE_INSET_PX := 8.0      # lane IOS-14: on the Mac host a pointer that left the window over an edge is put this far inside it

enum Gesture { NONE, PENDING, DRAG, HELD, TWO, SCROLL }

var active := false
var _gesture := Gesture.NONE
var _fingers := {}               # index -> {"start": Vector2, "pos": Vector2, "at": int}
var _first := -1                 # the finger of a one-finger gesture
var _two_start_ms := 0
var _two_moved := false
var _pinch_base := 0.0           # the fingers' distance at the last wheel notch
var _last_centroid := Vector2.ZERO
var _twist_base := 0.0           # lane IOS-15: the fingers' angle at the start of the two-finger gesture, then at the last turn
var _twisting := false
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
var stats := {"taps": 0, "double_taps": 0, "drags": 0, "holds": 0, "pans": 0, "zoom_notches": 0, "two_finger_taps": 0, "twists": 0, "assisted_taps": 0,
	"list_scrolls": 0, "pointer_touches": 0, "mouse_buttons": 0, "wheel_notches": 0, "repaired_key_releases": 0}
var _pointer: RefCounted = null  # lane IOS-14: the extension's IOSPointer (iOS builds only)
var _mouse := false              # lane IOS-14: a mouse or trackpad is there (the bridge says)
var _on_mac := false             # lane IOS-14: the iPhone / iPad build on an Apple Silicon Mac (its pointer can leave the window)
var _pointer_touches := {}       # lane IOS-14: Godot's touch index -> true: a click of the mouse (the bridge reports its buttons itself)
var _wheel_acc := 0.0           # lane IOS-14: scrolling not yet a whole notch (points)
var _wheel_notches := 0         # notches of the scroll gesture in progress
var _wheel_logged := 0
var _keys_down := {}             # lane IOS-14: physical keycode -> Godot's press of it whose release Godot has not delivered
var _key_ups := {}               # physical keycode -> when the keyboard (GCKeyboard) released it, not yet matched to a Godot press


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
	print("TOUCH tap assist %s (%.0f pt), list scrolling %s, twist turns the camera (IOS-15)" % ["on" if tap_assist else "off", ASSIST_PT, "on" if list_scroll else "off"])
	if ClassDB.class_exists("IOSPointer"):
		_pointer = ClassDB.instantiate("IOSPointer")
		var started: bool = _pointer.start()
		var status: Dictionary = _pointer.status()
		_on_mac = bool(status.get("on_mac", false))
		print("TOUCH IOS-14 mouse and keyboard bridge %s: %s" % ["on" if started else "NOT STARTED (no view)", status])
		get_tree().root.window_input.connect(_on_window_input)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--touch-selftest="):
			var test: Node = preload("res://scripts/touch/touch_selftest.gd").new()
			add_child(test)
			test.start(self, a.trim_prefix("--touch-selftest="))


func is_active() -> bool:
	return active


## lane IOS-15: a mouse or trackpad is in use (a Mac running the iPhone build has one). IOS-17: only once its pointer showed itself (hovered,
## clicked): the iPhone Duo lists a GameController mouse with nothing paired, which switched touch play to the desktop's right-click orders
func mouse_connected() -> bool:
	return _pointer != null and bool(_pointer.status().get("pointer_seen", false))


## lane IOS-17: the edge scrolling a game gets from the player's option (game_options.gd view_options, and here when a mouse comes or goes). The
## option's "retail" scrolls in a full-screen window, which Godot's iOS window always is: on touch it is off until a mouse is in use, as a finger
## near an edge (the Palantir's buttons sit at the bottom edge) is not a wish to scroll. "always" / "off" stay the player's
func edge_scroll_mode(option: String) -> String:
	_edge_option = option
	if not active or option != "retail":
		return option
	return "retail" if _mouse else "off"


var _edge_option := "retail"  # lane IOS-17: the player's OpenBFMEEdgeScroll as game_options.gd last applied it
var _mouse_check_ms := 0      # lane IOS-17: the bridge's status is read four times a second, not every frame


var _logged_inputs := 0  # lane IOS-14: the first input events of a mobile run are logged (what the device delivers: keys, touches, mouse)


func _input(event: InputEvent) -> void:
	if OS.has_feature("mobile") and _logged_inputs < 3000 and not event is InputEventScreenDrag and not event is InputEventMouseMotion:
		_logged_inputs += 1
		print("TOUCH INPUT %d ms: %s" % [Time.get_ticks_msec(), event.as_text() if not event is InputEventKey else "key %s physical %s pressed %s echo %s" % [
			OS.get_keycode_string((event as InputEventKey).keycode), OS.get_keycode_string((event as InputEventKey).physical_keycode),
			(event as InputEventKey).pressed, (event as InputEventKey).echo]])
	if event is InputEventScreenTouch:
		if not _pointer_touch(event):
			_touch(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if not _pointer_touches.has(event.index):
			_drag(event)
		get_viewport().set_input_as_handled()


var _status_ms := 0           # lane IOS-14: the bridge's counters are logged when they change (at most every 10 s)
var _status_last := ""


func _process(_delta: float) -> void:
	if _pointer != null:
		_pump_bridge()
		if Time.get_ticks_msec() - _status_ms > 10000:
			_status_ms = Time.get_ticks_msec()
			var now := JSON.stringify(_pointer.status())
			if now != _status_last:
				_status_last = now
				print("TOUCH IOS-14 status: ", now)
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
				_twist_base = _finger_angle()
				_twisting = false
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
	if not _two_moved and (c.distance_to(_last_centroid) > SLOP_PT * _scale or absf(d - _pinch_base) > SLOP_PT * _scale
			or absf(wrapf(_finger_angle() - _twist_base, -PI, PI)) >= deg_to_rad(TWIST_START_DEG)):  # lane IOS-15: a twist alone moves too
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
		# lane IOS-15, twist: the camera turns with the fingers (the original turns it with the middle button or numpad 4 / 6); only past
		# TWIST_START_DEG, so a pinch or a pan does not turn it by accident
		var turn := wrapf(_finger_angle() - _twist_base, -PI, PI)
		if not _twisting and absf(turn) >= deg_to_rad(TWIST_START_DEG):
			_twisting = true
			_twist_base = _finger_angle()
			turn = 0.0
		if _twisting and turn != 0.0 and cam.has("angle"):
			hud.camera_set_angle_pitch(float(cam.angle) + turn, float(cam.pitch))  # the map turns with the fingers
			_twist_base = _finger_angle()
			stats.twists += 1
	_last_centroid = c


## lane IOS-15: the angle of the line from the first finger to the second (radians, screen axes)
func _finger_angle() -> float:
	var p: Array = _fingers.values()
	return (p[1].pos - p[0].pos).angle() if p.size() >= 2 else 0.0


func _centroid() -> Vector2:
	var sum := Vector2.ZERO
	for f in _fingers.values():
		sum += f.pos
	return sum / maxf(1.0, _fingers.size())


func _distance() -> float:
	var p: Array = _fingers.values()
	return p[0].pos.distance_to(p[1].pos) if p.size() >= 2 else 0.0


func _apply_edge_scroll() -> void:
	_hud.set_edge_scroll(_mouse)
	_hud.set_view_options({"edge_scroll_mode": edge_scroll_mode(_edge_option)})


## the game's HUD node while a game is on screen (null in the menus); edge scrolling goes off for touch the first time it is found
func _game_hud() -> Node:
	if is_instance_valid(_hud) and _hud.is_inside_tree():
		return _hud
	var found := get_tree().root.find_children("*", "InGameHudNode", true, false)
	_hud = found[0] if not found.is_empty() else null
	if _hud != null:
		# a finger near the edge is not a wish to scroll; a mouse's pointer is (lane IOS-14: on while a mouse is there, _pump_bridge follows it).
		# set_edge_scroll replaces the HUD's retail rule (scroll in a full-screen window, which Godot's iOS window always is) and edge_scroll_mode
		# maps the option's "retail" the same way (IOS-17)
		_apply_edge_scroll()
		print("TOUCH game HUD found: edge scrolling %s (option %s)" % [edge_scroll_mode(_edge_option), _edge_option])
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


# ---- lane IOS-14: the mouse, trackpad and hardware keyboard (IOSPointer) ------------------------------------------------------------------------

## A screen touch that is the mouse's click (the bridge recorded it): true, and its sequence is dropped (the bridge sent its buttons).
func _pointer_touch(e: InputEventScreenTouch) -> bool:
	if _pointer == null:
		return false
	if e.pressed:
		if _pointer.claim_touch(e.position):
			_pointer_touches[e.index] = true
			stats.pointer_touches += 1
			return true
		return false
	return _pointer_touches.erase(e.index)


func _pump_bridge() -> void:
	var now := Time.get_ticks_msec()
	if now - _mouse_check_ms >= 250:
		_mouse_check_ms = now
		var mouse := mouse_connected()
		if mouse != _mouse:
			_mouse = mouse
			print("TOUCH IOS-14 mouse %s: %s" % ["in use" if mouse else "gone", _pointer.status()])
			if is_instance_valid(_hud) and _hud.is_inside_tree():
				_apply_edge_scroll()
	for item in _pointer.poll():
		var e: Dictionary = item
		match str(e.type):
			"motion":
				if _fingers.is_empty():  # while a finger is down the finger has the pointer
					_mouse_motion(e.position, int(e.buttons))
			"button":
				_mouse_button(int(e.button) as MouseButton, bool(e.pressed), e.position, int(e.buttons), bool(e.double_click))
			"scroll":
				_mouse_scroll(e.delta, e.position, bool(e.ended))
			"key":
				_keyboard_key(int(e.physical), bool(e.pressed))
			"leave":
				_pointer_left(e.position)
	_repair_key_releases()


func _mouse_motion(at: Vector2, mask: int) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	m.button_mask = mask
	Input.parse_input_event(m)


func _mouse_button(button: MouseButton, down: bool, at: Vector2, mask: int, double: bool) -> void:
	_mouse_motion(at, mask if not down else mask & ~_mask_of(button))  # the pointer there first, the button not yet held
	var b := InputEventMouseButton.new()
	b.button_index = button
	b.pressed = down
	b.position = at
	b.global_position = at
	b.double_click = double and down
	b.button_mask = mask
	Input.parse_input_event(b)
	stats.mouse_buttons += 1


func _mask_of(button: MouseButton) -> int:
	match button:
		MOUSE_BUTTON_LEFT:
			return MOUSE_BUTTON_MASK_LEFT
		MOUSE_BUTTON_RIGHT:
			return MOUSE_BUTTON_MASK_RIGHT
		MOUSE_BUTTON_MIDDLE:
			return MOUSE_BUTTON_MASK_MIDDLE
	return 0


## The pointer stopped hovering. On the Mac host it left the window: Godot's iOS window counts as full screen, so the HUD's edge scrolling is on,
## and a pointer last seen in the edge band would scroll the camera until it came back; it is put LEAVE_INSET_PX inside instead. On an iPad the
## pointer cannot leave the screen and a hover also ends when the pointer fades: nothing is done there (a pointer parked at the edge scrolls on).
func _pointer_left(at: Vector2) -> void:
	if not _on_mac or not _fingers.is_empty():
		return
	var size := get_viewport().get_visible_rect().size
	var inside := at.clamp(Vector2(LEAVE_INSET_PX, LEAVE_INSET_PX), size - Vector2(LEAVE_INSET_PX, LEAVE_INSET_PX))
	if inside != at:
		_mouse_motion(inside, 0)


## UIKit's scrolling (+y: the content moves down, the wheel turned up, as a desktop's natural scrolling gives it) in whole notches
func _mouse_scroll(delta: Vector2, at: Vector2, ended: bool) -> void:
	if _wheel_logged < 16:
		_wheel_logged += 1
		print("TOUCH IOS-14 scroll %s pt%s" % [delta, " (end)" if ended else ""])
	_wheel_acc += delta.y
	while _wheel_acc >= WHEEL_STEP_PT:
		_wheel(MOUSE_BUTTON_WHEEL_UP, at)
		_wheel_acc -= WHEEL_STEP_PT
		_wheel_notches += 1
	while _wheel_acc <= -WHEEL_STEP_PT:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN, at)
		_wheel_acc += WHEEL_STEP_PT
		_wheel_notches += 1
	if ended:
		if _wheel_notches == 0 and absf(_wheel_acc) >= 0.5:
			_wheel(MOUSE_BUTTON_WHEEL_UP if _wheel_acc > 0.0 else MOUSE_BUTTON_WHEEL_DOWN, at)  # a wheel's one click scrolls less than a step
			_wheel_notches += 1
		stats.wheel_notches += _wheel_notches
		_wheel_acc = 0.0
		_wheel_notches = 0


## every key event Godot delivers (the root window's, before any node's _input marks it handled): which presses still wait for a release
func _on_window_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or k.device == BRIDGE_DEVICE or k.echo or k.physical_keycode == KEY_NONE:
		return  # ours; or the on-screen keyboard's typing (no physical key; it sends a press and a release itself)
	var code := int(k.physical_keycode)
	if k.pressed:
		_keys_down[code] = k
	else:
		_keys_down.erase(code)  # Godot's own release came: nothing to repair
		_key_ups.erase(code)


func _keyboard_key(physical: int, pressed: bool) -> void:
	if physical == KEY_NONE:
		return
	if pressed:
		_key_ups.erase(physical)  # pressed again: an older release is spent
	else:
		_key_ups[physical] = Time.get_ticks_msec()


func _repair_key_releases() -> void:
	if _key_ups.is_empty():
		return
	var now := Time.get_ticks_msec()
	for code in _key_ups.keys():
		var age: int = now - int(_key_ups[code])
		if _keys_down.has(code):
			if age >= KEY_UP_GRACE_MS:
				_release_key(code)
				_key_ups.erase(code)
		elif age > KEY_UP_WAIT_MS:
			_key_ups.erase(code)


func _release_key(code: int) -> void:
	var press: InputEventKey = _keys_down[code]
	_keys_down.erase(code)
	var r := press.duplicate() as InputEventKey
	r.pressed = false
	r.echo = false
	r.unicode = 0
	r.device = BRIDGE_DEVICE
	Input.parse_input_event(r)
	stats.repaired_key_releases += 1


func _notification(what: int) -> void:
	# lane IOS-14: keys held as the app loses the focus (Cmd-Tab on the Mac, the home gesture) are released: no release would ever come
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _pointer != null:
		for code in _keys_down.keys():
			_release_key(code)
		_key_ups.clear()
