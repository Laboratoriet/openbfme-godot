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
##   one finger, hold ........... right click (deselect / cancel) with a short vibration; on a HUD button its help instead (lane IOS-21, below)
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
## Lane IOS-21 (the owner's decision, 2026-11-03: "hold shows info"), information without a hover:
##   hold on a HUD button ....... its help box at once (no tooltip delay) for as long as the finger stays, with a lighter vibration; lifting does
##                                nothing (a preview, never a press); sliding off past SLOP_PT ends it. The HUD buttons: the Palantir's (the arc,
##                                its keys, the portrait: the selection's name and help), the side command bar, the spell book, the hero bar, the
##                                radial bubbles (InGameHudNode.touch_button_at, the clicks' own hit test with the HUD size). The world, the radar
##                                and a menu over the game keep the hold's right click. The help box shows only for a held finger (set_touch_help):
##                                the pointer a tap leaves on a button opens none. A mouse in use (IOS-14) gives the desktop's hover back.
##   two taps on an ability ..... toggle its autocast (the right press of lane AUTOCAST-1), only on a button whose right press does that
##                                (touch_button_at's "autocast": an AutoAbility power or weapon of the Palantir / side bar). Its first tap waits
##                                DOUBLE_TAP_MS for a second one before it presses (else a double tap would cast the power, or start its aiming,
##                                on the way to the toggle). Every other button keeps two taps as two presses (a bubble queues two units).
##   (production cancel ........ was the hold on a bubble (its right press); now a two-finger tap whose middle is on the bubble, the one right click
##                                left on a HUD button: an open question for the owner)
##
## Lane IOS-23 (the owner's decisions, 2026-11-03), a building's placement for fingers. While a build button waits for its site (InGameHudNode
## touch_placement_at: placing, and the finger came down on the world), a finger would hide the ghost under it, so:
##   finger down ................ the pointer, and with it the ghost (PlaceEventTranslator follows the live pointer), goes GHOST_OFFSET_PT above the
##                                fingertip (clamped into the view); valid / invalid colouring as with a mouse
##   drag ....................... the ghost follows the finger at that offset (no selection box, no rotation: the left button is not held)
##   lift after a drag .......... the ghost stays there and waits for ✓ / ✕ (lane IOS-26, below). A lift whose ghost point is on the HUD offers
##                                nothing (the ghost is under the HUD) and the placement stays
##   tap ........................ lane IOS-26: the ghost goes under the tap point (no offset: no finger is left over it) and waits for ✓ / ✕
##   hold (still finger) ........ the right click: cancels the placement; once the finger has moved, holding still no longer cancels (it can rest)
##   two-finger tap ............. the right click: cancels; a second finger during the drag stops the ghost where it is (pan / zoom / twist the camera)
##   walls ...................... Begin Wall Span: the same gesture; the span's ghost segments (PlacementIcons::updateWall, the span planner's tiles) run
##                                from the hub to the ghost's point, and ✓ builds the span to it (MSG_WALL_HUB_CONSTRUCT_SPAN)
## Rotation: retail turns the ghost with a drag after the press; on touch the drag is the position, so a placement keeps its PlacementViewAngle (an
## open question for the owner: a second finger's twist, or a rotate button). A mouse (IOS-14) keeps the desktop's placement.
##
## Lane IOS-26 (the owner's decision, 2026-11-04: "still a bit hard to not place a building accidentally"; "✓ / ✕ by the ghost"): no finger places
## a building by itself. A lift or a tap leaves the ghost at its point and shows two buttons beside it (placement_confirm.gd: ✕ left, ✓ right):
##   ✓ .......................... the left click at the ghost's point (IOS-23's lift, unchanged: the press anchors, the release places, or refuses with
##                                retail's message and BadBuildingPlacementSound; then the placement and the buttons stay). While the ghost is red
##                                (get_placement's legal code, the ghost's own tint) ✓ is dimmed, and a tap on it still asks the game, whose refusal
##                                says why. Walls: a line build skips the legality test (RW 0x83E7FE), so ✓ is never dimmed for a span
##   ✕ .......................... the right click at the ghost's point: cancels the placement (as the hold does)
##   a finger on the world ...... hides the buttons and moves the ghost again by IOS-23's rules (a drag: 60 pt above the finger; a tap: under it); they
##                                come back where it stops. Anywhere on the world, not only on the ghost: one rule, the same as the first time
##   a finger on the HUD ........ ends the wait (the HUD tap goes through as before; a new build button starts its own ghost)
##   two fingers ................ the camera moves; the ghost keeps its point on the ground (the pointer follows it, InGameHudNode.world_to_pixel); the
##                                buttons hide while the fingers are down and come back beside it. A ghost whose point leaves the view (or goes under
##                                the HUD) keeps its buttons hidden until the point is back. A second finger that comes down before the first one moved
##                                puts the ghost back where it waited (the start of a pan, not a new spot)
##   a mouse (IOS-14) ........... its first motion ends the wait: the mouse has the pointer, and a mouse click places as retail's does
## A finger on ✓ / ✕ presses it (the disc shrinks); lifting on it activates it, sliding off and lifting does nothing, a second finger cancels it.
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
const GHOST_OFFSET_PT := 60.0    # lane IOS-23 (the owner's decision): a placement's ghost sits this far above the fingertip (points)
const GHOST_INSET_PX := 2.0      # lane IOS-23: an offset point above the view's top edge is put this far inside it
const CONFIRM_POLL_MS := 100     # lane IOS-26: while ✓ / ✕ wait, the placement, the ghost's legality and its pixel are read this often ...
const CONFIRM_TRACK_MS := 600    # ... and every frame while two fingers move the camera and this long after (the zoom eases in)
const CONFIRM_RETRY_MS := 400    # lane IOS-26: a ✓ the game did not take (the placement still on after this) shows the buttons again
const CONFIRM_CLEAR_WORLD := 40.0  # lane IOS-26: the ground radius ✓ / ✕ keep clear of the ghost's point (a farm's footprint: the Mac stand-in's
                                   # GondorFarm ghost is ~125 px half wide at ~3.5 px per world unit); the HUD has no footprint query
const CONFIRM_SIDE_MAX_PT := 140.0 # ... but never farther than this from the ghost (zoomed far in, a building is bigger than the view's middle)

const PlacementConfirm := preload("res://scripts/touch/placement_confirm.gd")

enum Gesture { NONE, PENDING, DRAG, HELD, TWO, SCROLL, INFO, PLACE, CONFIRM }  # INFO: lane IOS-21, a finger held on a HUD button shows its help
                                                                               # PLACE: lane IOS-23, a finger drags a building's ghost
                                                                               # CONFIRM: lane IOS-26, a finger on ✓ / ✕

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
	"list_scrolls": 0, "pointer_touches": 0, "mouse_buttons": 0, "wheel_notches": 0, "repaired_key_releases": 0, "infos": 0, "autocast_taps": 0,
	"waited_taps": 0, "place_drags": 0, "place_lifts": 0, "place_lifts_on_hud": 0, "place_taps": 0, "place_confirms": 0, "place_cancels": 0}
var _placing := false            # lane IOS-23: the one-finger gesture began on the world while a placement waited for its site (the ghost is offset)
var _confirm: CanvasLayer = null # lane IOS-26: placement_confirm.gd, made the first time it is needed
var _confirming := false         # lane IOS-26: a placement's ghost waits for ✓ / ✕ at _ghost_px
var _ghost_px := Vector2.INF     # its window pixel (the pointer is kept there)
var _anchor := Vector2.INF       # its ground point (INF: the HUD could not say; the ghost then keeps its pixel)
var _confirm_line := false       # a wall span (✓ never dimmed)
var _confirm_poll_ms := 0
var _track_until := 0
var _committed_ms := -1          # ✓ tapped on a legal ghost: the buttons went; they come back if the placement is still on CONFIRM_RETRY_MS later
var _pressed := ""               # the button a CONFIRM gesture's finger pressed
var _waiting := {}               # lane IOS-21: a tap on an autocast ability waiting for a second one: {"at": the press point, "due": msec, "second":
                                 # a finger came down on it in time (its tap is the second, however long it stays)}
var _touch_help := -1            # lane IOS-21: the touch help the HUD was last given (-1: none yet)
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
	if not _waiting.is_empty() and Time.get_ticks_msec() >= int(_waiting.due) and not _waiting.get("second", false):
		_press_waiting()  # lane IOS-21: no second tap came: the first one's press
	if _confirming:
		_poll_confirm(Time.get_ticks_msec())
	# the hold: a still finger that stays down becomes a right click while it is still down (the player feels it fire); lane IOS-21: on a HUD button
	# it shows the button's help instead, until the finger lifts
	if _gesture == Gesture.PENDING and _fingers.has(_first) and Time.get_ticks_msec() - int(_fingers[_first].at) >= LONG_PRESS_MS:
		var at: Vector2 = _fingers[_first].pos
		_press_waiting()
		var button := _hud_button(at)
		if not button.is_empty():
			_move(button.position)  # the pointer on the button (the tap assist's point): the help box's provider is the button under it
			_hud.hold_help(true)
			Input.vibrate_handheld(10)
			_gesture = Gesture.INFO
			stats.infos += 1
			return
		_click(MOUSE_BUTTON_RIGHT, at)
		Input.vibrate_handheld(15)
		_gesture = Gesture.HELD
		stats.holds += 1
		_end_confirm()  # lane IOS-26: the hold cancelled the placement the buttons waited on


func _touch(e: InputEventScreenTouch) -> void:
	var now := Time.get_ticks_msec()
	if e.pressed:
		_fingers[e.index] = {"start": e.position, "pos": e.position, "at": now}
		if not _waiting.is_empty() and (_fingers.size() > 1 or e.position.distance_to(_waiting.at) > DOUBLE_TAP_PT * _scale):
			_press_waiting()  # lane IOS-21: a finger elsewhere is no second tap: the waiting press goes first
		elif not _waiting.is_empty() and now <= int(_waiting.due):
			_waiting["second"] = true  # its tap toggles the autocast; a hold or a drag of it presses the waiting tap first
		match _fingers.size():
			1:
				_gesture = Gesture.PENDING
				_first = e.index
				# lane IOS-26: a finger on ✓ / ✕ presses it; the pointer (the ghost) stays where it is
				var on: String = _confirm.hit(e.position) if _confirming else ""
				if on != "":
					_gesture = Gesture.CONFIRM
					_pressed = on
					_confirm.set_pressed(on)
					return
				_placing = _placement_drag_at(e.position)
				if _confirming:
					if _placing:
						_confirm.hide_now()  # the finger moves the ghost again; the buttons come back where it stops
						_committed_ms = -1
					else:
						_end_confirm()  # a finger on the HUD (or a menu over the game) ends the wait
				# the pointer goes where the finger is (the game's hover, the cursor's picture); lane IOS-23: a placement's ghost above it
				_move(ghost_point(e.position) if _placing else e.position)
			2:
				_end_info()
				if _gesture == Gesture.DRAG:
					_button(MOUSE_BUTTON_LEFT, false, _fingers[_first].pos)  # a second finger ends the drag where it is
				# (a list scroll just stops: it pressed nothing)
				# lane IOS-26: two fingers move the camera; the ghost keeps its ground point and the buttons wait for the fingers to lift
				if _gesture == Gesture.CONFIRM:
					_confirm.set_pressed("")
				elif _gesture == Gesture.PENDING and _placing and _confirming:
					_move(_ghost_px)  # the first finger had not moved: the start of a pan, not a new spot; the ghost goes back
				elif _gesture == Gesture.PLACE:
					_offer_confirm(ghost_point(_fingers[_first].pos), false)  # the drag stops the ghost here; ✓ / ✕ after the camera gesture
				if _confirming:
					_confirm.hide_now()
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
	var camera_gesture := _gesture == Gesture.TWO or _gesture == Gesture.HELD
	match _gesture:
		Gesture.PENDING:
			if _placing:
				_offer_confirm(e.position)  # lane IOS-26: a tap puts the ghost under the tap point and waits for ✓ / ✕
				stats.place_taps += 1
			else:
				_tap(e.position, now)  # up before the hold fired and without moving: a tap
		Gesture.DRAG:
			_button(MOUSE_BUTTON_LEFT, false, e.position)
		Gesture.PLACE:
			if _offer_confirm(ghost_point(e.position)):  # lane IOS-26: lifting leaves the ghost there and waits for ✓ / ✕
				stats.place_lifts += 1
		Gesture.CONFIRM:
			if _confirm.hit(e.position) == _pressed:  # lifted on the button it pressed (sliding off and lifting does nothing)
				if _pressed == "build":
					_confirm_build()
				else:
					_confirm_cancel()
			if is_instance_valid(_confirm):
				_confirm.set_pressed("")
			_pressed = ""
		Gesture.INFO:
			_end_info()  # lane IOS-21: lifting ends the preview; nothing is pressed
		Gesture.TWO:
			if _fingers.size() == 2 and not _two_moved and now - _two_start_ms <= TAP_MAX_MS:
				_click(MOUSE_BUTTON_RIGHT, _centroid())
				stats.two_finger_taps += 1
				_end_confirm()  # lane IOS-26: the two-finger tap cancelled the placement
	_fingers.erase(e.index)
	if _fingers.is_empty():
		_gesture = Gesture.NONE
		_first = -1
		_placing = false
		_pressed = ""
		if camera_gesture and _confirming:
			_track_until = now + CONFIRM_TRACK_MS  # lane IOS-26: the camera may still ease (a zoom); the buttons come back beside the ghost
			_follow_anchor(true)
	elif _gesture == Gesture.TWO:
		_gesture = Gesture.HELD  # one finger of two lifted: nothing more until both are up (no surprise click or box)


func _drag(e: InputEventScreenDrag) -> void:
	if not _fingers.has(e.index):
		return
	_fingers[e.index].pos = e.position
	match _gesture:
		Gesture.PENDING:
			if e.index == _first and _placing:
				# lane IOS-23: the ghost follows the finger at its offset from the first move; past the slop it is a placement drag (no tap, no hold)
				_move(ghost_point(e.position))
				if e.position.distance_to(_fingers[e.index].start) > SLOP_PT * _scale:
					_press_waiting()
					_gesture = Gesture.PLACE
					stats.place_drags += 1
			elif e.index == _first and e.position.distance_to(_fingers[e.index].start) > SLOP_PT * _scale:
				_press_waiting()
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
		Gesture.PLACE:
			if e.index == _first:
				_move(ghost_point(e.position))
		Gesture.CONFIRM:
			if e.index == _first:  # lane IOS-26: the button looks pressed while the finger is on it
				_confirm.set_pressed(_pressed if _confirm.hit(e.position) == _pressed else "")
		Gesture.INFO:
			if e.index == _first and e.position.distance_to(_fingers[e.index].start) > SLOP_PT * _scale:
				_end_info()  # lane IOS-21: sliding off ends the help; the finger does nothing more until it lifts
				_gesture = Gesture.HELD
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
	# lane IOS-21: the second tap on an autocast ability toggles its autocast (its right press); the first tap's press is dropped
	if not _waiting.is_empty():
		if double or _waiting.get("second", false):
			var on: Vector2 = _waiting.at
			_waiting = {}
			_click(MOUSE_BUTTON_RIGHT, on)
			stats.autocast_taps += 1
			stats.double_taps += 1
			_last_tap_ms = -100000
			return
		_press_waiting()
	if not double and _hud_button(at, assist.position).get("autocast", false):
		_waiting = {"at": assist.position, "due": now + DOUBLE_TAP_MS}
		stats.waited_taps += 1
		stats.taps += 1
		_last_tap_ms = now
		_last_tap_pos = at
		return
	_click(MOUSE_BUTTON_LEFT, assist.position, double)
	if double:
		stats.double_taps += 1
		_last_tap_ms = -100000  # a third tap starts over
	else:
		stats.taps += 1
		_last_tap_ms = now
		_last_tap_pos = at


## lane IOS-21: the HUD button a finger at `at` is on ({} none): touch_button_at's answer at the tap assist's point (`assisted`, else asked here), with
## "position" the point the pointer goes to. Only over a game's HUD (the menus' hold stays the right click), with an extension that has the call
func _hud_button(at: Vector2, assisted := Vector2.INF) -> Dictionary:
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_button_at"):
		return {}
	var point: Vector2 = assisted if assisted.is_finite() else assist_probe(at).position
	var r: Dictionary = hud.touch_button_at(point)
	if str(r.get("kind", "")) == "":
		return {}
	r["position"] = point
	return r


## lane IOS-23: a finger coming down at `at` drags a placement's ghost: a build button waits for its site and the finger is on the world (not on the
## HUD, the radar or a menu over the game). An extension without the query (built before lane IOS-23) keeps the old gestures
func _placement_drag_at(at: Vector2) -> bool:
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_placement_at"):
		return false
	var r: Dictionary = hud.touch_placement_at(at)
	return bool(r.get("placing", false)) and bool(r.get("world", false))


## lane IOS-23: where a finger at `at` puts a placement's ghost: GHOST_OFFSET_PT above it, kept inside the view (a finger near the top edge holds
## the ghost at the edge; the sides and the bottom cannot be left, as the offset is straight up)
func ghost_point(at: Vector2) -> Vector2:
	var p := at - Vector2(0.0, GHOST_OFFSET_PT * _scale)
	var size := get_viewport().get_visible_rect().size
	return p.clamp(Vector2(GHOST_INSET_PX, GHOST_INSET_PX), size - Vector2(GHOST_INSET_PX, GHOST_INSET_PX))


## lane IOS-26: a lift or a tap leaves the ghost at `at` (window pixels) to wait for ✓ / ✕, shown beside it now (`show`) or once a camera gesture
## ends (true: the ghost waits). A point on the HUD (the ghost dragged over the Palantir) offers nothing: the ghost is under the HUD, and the placement
## stays for another try
func _offer_confirm(at: Vector2, show := true) -> bool:
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_placement_at"):
		return false
	var r: Dictionary = hud.touch_placement_at(at)
	if not bool(r.get("placing", false)) or not bool(r.get("world", false)):
		if bool(r.get("placing", false)):
			stats.place_lifts_on_hud += 1
		_end_confirm()
		return false
	_move(at)
	_ghost_px = at
	var ground: Vector2 = hud.pixel_to_world(at)
	_anchor = ground if ground.is_finite() and ground.x > -1e8 else Vector2.INF  # (-1e9, -1e9): no ground under the pixel
	_confirm_line = bool(r.get("line_build", false))
	_confirming = true
	_committed_ms = -1
	_confirm_poll_ms = Time.get_ticks_msec()
	if _confirm == null:
		_confirm = PlacementConfirm.new()
		_confirm.setup(_scale)
		add_child(_confirm)
	if show:
		_show_confirm(true)
	return true


## lane IOS-26: ✓ and ✕ beside the waiting ghost, and ✓'s look for its legality. A building: left and right of it, clear of a farm-sized footprint
## at the camera's zoom. A wall span: across the span's line at its end (the ghost segments' direction), else beyond the end
func _show_confirm(animate: bool) -> void:
	var hud := _game_hud()
	var side := 0.0
	var axis := Vector2.RIGHT
	var away: Array = [Vector2.UP, Vector2.DOWN]
	if hud != null and _confirm_line:
		var dir := _span_direction(hud)
		if dir != Vector2.ZERO:
			axis = dir.orthogonal() if dir.orthogonal().x >= 0.0 else -dir.orthogonal()  # across the line: ✓ to the right (above a level span), ✕ opposite
			away = [dir]
	elif hud != null and _anchor.is_finite():
		side = _clear_side(hud)
	_confirm.show_at(_ghost_px, _safe_rect(), _off_hud, animate, side, axis, away)
	_refresh_validity()


## lane IOS-26: pixels from the ghost's point to a button's centre that clear CONFIRM_CLEAR_WORLD of ground around it at the camera's zoom (the larger
## of the ground's two axes on screen), a disc's radius and a little more (0: the HUD could not say)
func _clear_side(hud: Node) -> float:
	var o: Vector2 = hud.world_to_pixel(_anchor)
	var x: Vector2 = hud.world_to_pixel(_anchor + Vector2(CONFIRM_CLEAR_WORLD, 0))
	var y: Vector2 = hud.world_to_pixel(_anchor + Vector2(0, CONFIRM_CLEAR_WORLD))
	if o.x < -1e8 or x.x < -1e8 or y.x < -1e8:
		return 0.0
	var reach := maxf(o.distance_to(x), o.distance_to(y)) + (PlacementConfirm.DIAMETER_PT * 0.5 + 6.0) * _scale
	return minf(reach, CONFIRM_SIDE_MAX_PT * _scale)


## lane IOS-26: a wall span's direction on screen, from its hub to the ghost: the hub is the placement's source (get_placement().source, its position
## from the game's GameWorld); without it, the ghost segments' end farthest from the ghost. ZERO when neither says
func _span_direction(hud: Node) -> Vector2:
	var far := Vector2.INF
	var scene := get_tree().current_scene
	var world = scene.get("_world") if scene != null else null
	if hud.has_method("get_placement") and world != null and world.has_method("get_object"):
		var hub: Dictionary = world.get_object(int(hud.get_placement().get("source", 0)))
		if hub.get("ok", false):
			var p: Vector2 = hud.world_to_pixel(Vector2(float(hub.x), float(hub.y)))
			if p.x > -1e8:
				far = p
	if not far.is_finite() and hud.has_method("get_placement_ghost_state"):
		var icons: Array = hud.get_placement_ghost_state().get("icons", [])
		if icons.size() >= 2:
			for i in [icons[0], icons[icons.size() - 1]]:
				var p: Vector2 = hud.world_to_pixel(Vector2(float(i.get("x", 0.0)), float(i.get("y", 0.0))))
				if p.x > -1e8 and (not far.is_finite() or p.distance_to(_ghost_px) > far.distance_to(_ghost_px)):
					far = p
	if not far.is_finite() or far.distance_to(_ghost_px) < 1.0:
		return Vector2.ZERO
	return (_ghost_px - far).normalized()


## lane IOS-26: a pixel the buttons may cover: on the world, not on the HUD (the Palantir, the side bar, a radial bubble, the radar)
func _off_hud(at: Vector2) -> bool:
	var hud := _game_hud()
	return hud != null and bool(hud.touch_placement_at(at).get("world", false))


## lane IOS-26: the view less the notch, the rounded corners and the home bar on a phone (the screen's safe area: Godot's iOS window is the screen)
func _safe_rect() -> Rect2:
	var view := get_viewport().get_visible_rect()
	if OS.has_feature("mobile"):
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if safe.has_area():
			view = view.intersection(safe)
	return view


## lane IOS-26: ✓ is dimmed while the ghost is red (the HUD's legal code for it, judged by PlaceEventTranslator as for a mouse). A wall span is never
## dimmed: its release skips the legality test (RW 0x83E7FE) and the span planner builds what it can
func _refresh_validity() -> void:
	var hud := _game_hud()
	if _confirm_line or hud == null or not hud.has_method("get_placement"):
		_confirm.set_build_enabled(true)
		return
	_confirm.set_build_enabled(int(hud.get_placement().get("legal", 0)) == 0)


## lane IOS-26: ✓: the left click at the ghost's point, IOS-23's lift (the press anchors, the release places, or refuses with retail's message and
## sound and the mode stays). On a legal ghost the buttons go at once; a ✓ the game did not take brings them back (_poll_confirm)
func _confirm_build() -> void:
	var legal: bool = _confirm.build_enabled()
	_click(MOUSE_BUTTON_LEFT, _ghost_px)
	stats.place_confirms += 1
	Input.vibrate_handheld(10)
	if legal:
		_confirm.hide_now()
		_committed_ms = Time.get_ticks_msec()


## lane IOS-26: ✕: the right click at the ghost's point (the hold's cancel; the pointer stays on the ghost)
func _confirm_cancel() -> void:
	_click(MOUSE_BUTTON_RIGHT, _ghost_px)
	stats.place_cancels += 1
	_end_confirm()


func _end_confirm() -> void:
	if not _confirming:
		return
	_confirming = false
	_anchor = Vector2.INF
	_ghost_px = Vector2.INF
	_committed_ms = -1
	_track_until = 0
	if _confirm != null:
		_confirm.hide_now()


## lane IOS-26, while the ghost waits: the placement still on (else the wait ends: placed, cancelled by a key or the game, the builder gone), the ghost
## on its ground point (the camera may have moved), ✓'s legality. Every CONFIRM_POLL_MS; every frame while the camera may move
func _poll_confirm(now: int) -> void:
	var camera := _gesture == Gesture.TWO or _gesture == Gesture.HELD or now < _track_until
	if not camera and now - _confirm_poll_ms < CONFIRM_POLL_MS:
		return
	_confirm_poll_ms = now
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_placement_at"):
		_end_confirm()
		return
	var px := _anchor_pixel(hud)
	var r: Dictionary = hud.touch_placement_at(px)
	if not bool(r.get("placing", false)):
		_end_confirm()
		return
	if _placing and (_gesture == Gesture.PENDING or _gesture == Gesture.PLACE):
		return  # a finger is putting the ghost somewhere new
	_settle(px, bool(r.get("world", false)), _gesture == Gesture.NONE)
	if _committed_ms >= 0 and now - _committed_ms >= CONFIRM_RETRY_MS and _gesture == Gesture.NONE:
		_committed_ms = -1  # the game kept the placement after ✓ (no money, a full queue: its message says so): the buttons again
		_show_confirm(true)
	if _confirm.is_shown():
		_refresh_validity()


## lane IOS-26: the waiting ghost's pixel now: its ground point through the drawn camera (the pixel it waited at when the HUD had no ground point)
func _anchor_pixel(hud: Node) -> Vector2:
	if _anchor.is_finite():
		var p: Vector2 = hud.world_to_pixel(_anchor)
		if p.is_finite() and p.x > -1e8:
			return p
	return _ghost_px


## lane IOS-26: the ghost back on its ground point after the camera moved (`show`: and its buttons, if they were hidden)
func _follow_anchor(show: bool) -> void:
	var hud := _game_hud()
	if hud == null or not hud.has_method("touch_placement_at"):
		return
	var px := _anchor_pixel(hud)
	_settle(px, bool(hud.touch_placement_at(px).get("world", false)), show)


## the pointer (the ghost) and the buttons to `px`. A point off the view or under the HUD hides the buttons and leaves the pointer: the ghost stays
## visible where it was, and its buttons come back when its point does (or a finger puts it somewhere new)
func _settle(px: Vector2, world: bool, show: bool) -> void:
	if not world or not get_viewport().get_visible_rect().has_point(px):
		_confirm.hide_now()
		return
	if px.distance_to(_ghost_px) > 1.5:  # the ground point's round trip may differ by a pixel: no jitter
		_ghost_px = px
		_move(px)
		_confirm.move_to(px)
	if show and not _confirm.is_shown() and _committed_ms < 0:
		_show_confirm(true)


## lane IOS-21: the waiting tap's press, now (a second tap did not come, or another gesture began)
func _press_waiting() -> void:
	if _waiting.is_empty():
		return
	var at: Vector2 = _waiting.at
	_waiting = {}
	_click(MOUSE_BUTTON_LEFT, at)


## lane IOS-21: a held finger's help ends (the HUD hides the box with its own count down)
func _end_info() -> void:
	if _gesture == Gesture.INFO and is_instance_valid(_hud):
		_hud.hold_help(false)


## lane IOS-21: the help box shows only for a held finger, unless a mouse is in use (its hover is the desktop's)
func _apply_touch_help() -> void:
	var on := 0 if _mouse else 1
	if _touch_help != on and _hud.has_method("set_touch_help"):
		_hud.set_touch_help(on == 1)
		_touch_help = on


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
		if _confirming:
			_follow_anchor(false)  # lane IOS-26: the ghost keeps its ground point under the moving camera
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
	_apply_touch_help()


## the game's HUD node while a game is on screen (null in the menus); edge scrolling goes off for touch the first time it is found
func _game_hud() -> Node:
	if is_instance_valid(_hud) and _hud.is_inside_tree():
		return _hud
	var found := get_tree().root.find_children("*", "InGameHudNode", true, false)
	_hud = found[0] if not found.is_empty() else null
	_touch_help = -1  # a new game's HUD starts with the desktop's hover help
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
					_end_confirm()  # lane IOS-26: the mouse takes the pointer, and with it the ghost; its click places as retail's
					_mouse_motion(e.position, int(e.buttons))
			"button":
				_end_confirm()
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
