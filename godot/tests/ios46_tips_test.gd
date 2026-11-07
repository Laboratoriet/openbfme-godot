## Headless test of lane IOS-46's touch help (scripts/touch/touch_tips.gd, touch_help_card.gd through scripts/touch/touch_controls.gd), against a
## stand-in HUD: no game, no extension needed.
##  * (b) tips, the default: each tip shows once, when its moment comes (its trigger event with its context), and never again, also after a restart (the
##    tips file); ✕ dismisses it; a tip the player already did ("learned") never shows; a tip whose moment ends within MIN_READ_S comes back next time;
##    one at a time (the next waits); the panel sits in the safe area, clear of ✓ / ✕, with a 44 pt ✕;
##  * "Show tips" off (and the style "card") shows nothing; Reset tips shows them again; the touch self-test's suppression wins over the options;
##  * the wiring: a previewed button (IOS-40), a hold on a button (IOS-21), a ghost waiting for ✓ / ✕ (IOS-26) and a two-finger pan reach the tips
##    through the touch layer's own gestures; a finger on the tip is the tip's (nothing reaches the game);
##  * (a) the guide: five steps done as they happen, the placing line while a ghost waits, Skip ends it for good;
##  * (c) the card: opens with the gestures as the switches say (two columns at this size), is modal, ✕ and a tap outside close it.
##
##   godot --headless --path godot --script res://tests/ios46_tips_test.gd
##
## Exit codes: 0 pass, 1 fail.
extends SceneTree

const TouchControls := preload("res://scripts/touch/touch_controls.gd")
const TouchTips := preload("res://scripts/touch/touch_tips.gd")
const GameOptions := preload("res://scripts/game_options.gd")
const STORE := "user://ios46-test-tips.cfg"


## InGameHudNode's calls the touch layer makes
class StubHud:
	extends Node
	var selection: Array = []
	var button := {}          # what touch_button_at answers ({} none)
	var placing := false
	var builds := 0
	var camera := {"position": Vector2(100, 100), "angle": 0.0, "pitch": 0.6}

	func touch_button_at(p: Vector2) -> Dictionary:
		if not button.is_empty() and Rect2(button.rect).has_point(p):
			return button.duplicate()
		return {"kind": "", "target": "", "autocast": false, "costs": false, "name": "", "slot": -1, "rect": Rect2(), "command": ""}

	func nearest_button(p: Vector2, _radius: float) -> Dictionary:
		return {"snapped": false, "position": p, "reason": "far", "target": ""}

	func touch_placement_at(p: Vector2) -> Dictionary:
		var on_hud := not button.is_empty() and Rect2(button.rect).has_point(p)
		return {"placing": placing, "line_build": false, "world": not on_hud, "builds": builds, "legal": 0}

	func get_placement() -> Dictionary:
		return {"legal": 0, "angle": 0.0}

	func get_selection() -> Array:
		return selection

	func pixel_to_world(p: Vector2) -> Vector2:
		return p

	func world_to_pixel(p: Vector2) -> Vector2:
		return p

	func get_camera() -> Dictionary:
		return camera

	func camera_look_at(p: Vector2) -> void:
		camera.position = p

	func inject_mouse_wheel(_n: int, _p: Vector2) -> void:
		pass

	func inject_mouse_move(_p: Vector2) -> void:
		pass

	func inject_mouse_button(_b: int, _down: bool, _p: Vector2, _double := false) -> void:
		pass

	func hold_help(_on: bool) -> void:
		pass

	func set_touch_help(_on: bool) -> void:
		pass

	func set_edge_scroll(_on: bool) -> void:
		pass

	func set_view_options(_options: Dictionary) -> void:
		pass


## the mouse events the game would see
class Recorder:
	extends Node
	var mouse := 0

	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			mouse += 1


var _failures := 0
var _controls: Node
var _hud: StubHud
var _rec: Recorder
var _tips: CanvasLayer


func _initialize() -> void:
	var code: int = await _run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	print("IOS46 TIPS %s" % ["PASS" if code == 0 else "FAIL"])
	quit(code)


func _check(ok: bool, what: String) -> void:
	print("  ", "ok   " if ok else "FAIL ", what)
	if not ok:
		_failures += 1


func _run() -> int:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	_check(GameOptions.EXTRAS.OpenBFMETouchHelp.default == "tips" and GameOptions.EXTRAS.OpenBFMETouchTips.default == "yes",
		"Options: the help style defaults to tips (b), Show tips on")
	_check(GameOptions.TOUCH_KEYS.has("OpenBFMETouchHelp") and GameOptions.TOUCH_KEYS.has("OpenBFMETouchTips"), "both are touch keys")
	_rec = Recorder.new()
	root.add_child(_rec)
	_hud = StubHud.new()
	root.add_child(_hud)
	var stage := SubViewport.new()  # the Mac stand-in's landscape window (the iPhone Duo at half size)
	stage.size = Vector2i(1335, 939)
	root.add_child(stage)
	_controls = TouchControls.new()
	stage.add_child(_controls)
	await process_frame
	_controls.active = true
	_controls.set_process(true)
	Input.emulate_mouse_from_touch = false
	_controls._scale = 1.0
	_controls._hud = _hud
	_controls._make_help()
	_tips = _controls.tips
	_tips.store_path = STORE
	_tips.load_store()
	_controls.apply_options({})
	_check(_tips.style == "tips" and _tips.enabled, "apply_options' fallback: tips on (%s, %s)" % [_tips.style, _tips.enabled])
	await _wait(0.3)  # the toolbar's poll: the context (a game, no menu)

	_poll(false)  # the cases set the context themselves
	await _each_tip_once()
	_poll(true)  # the touch layer's own context: its armed button, its ghost
	await _wiring()
	_poll(false)
	await _toggle_and_reset()
	await _guide()
	_poll(true)
	await _card()
	return 0 if _failures == 0 else 1


## every tip: its moment, its trigger; shown once; ✕ dismisses; never again
func _each_tip_once() -> void:
	var cases := [
		["hold", "selected", {}, {}],
		["preview", "armed", {}, {"armed": true}],
		["autocast", "armed", {"autocast": true}, {"armed": true}],
		["unqueue", "unqueue_shown", {}, {"armed": true}],
		["place", "placement_wait", {"line": false, "twist": true}, {"placing": true}],  # then twist, while the ghost still waits
		["aim", "aim_wait", {}, {"aiming": true}],
		["camera", "drag_box", {}, {}],
	]
	for c in cases:
		var id: String = c[0]
		_context(c[3])
		_tips.event(c[1], c[2])
		await process_frame
		if _tips.current() != id:
			_check(false, "tip %s shows on '%s': the panel shows '%s' (queue %s)" % [id, c[1], _tips.current(), _tips.state().queue])
			_tips.dismiss()
			continue
		var st: Dictionary = _tips.state()
		_check(st.shown and st.text == TouchTips.TIPS[id].text, "tip %s shows on '%s': '%s'" % [id, c[1], st.text])
		var r: Rect2 = st.rect
		var safe: Rect2 = _controls._safe_rect()
		_check(safe.encloses(r), "  inside the safe area: %s in %s" % [r, safe])
		_check(_tips._action.size.x >= 44.0 and _tips._action.size.y >= 44.0, "  its ✕ is a 44 pt cell: %s" % [_tips._action.size])
		# ✕ through the touch layer: a finger on it is the tip's, no mouse event reaches the game
		var x: Vector2 = Rect2(_tips._action.global_position, _tips._action.size).get_center()
		var mouse := _rec.mouse
		_down(0, x)
		_up(0, x)
		await process_frame
		if id == "place":
			_check(_tips.current() == "twist" and _rec.mouse == mouse, "  ✕ dismisses it; the twist tip comes next while the ghost waits ('%s')" % _tips.current())
			_check(_tips.state().text == TouchTips.TIPS.twist.text, "tip twist shows after it: '%s'" % _tips.state().text)
			_tips.dismiss()
			await process_frame
		_check(_tips.current() == "" and _rec.mouse == mouse, "  ✕ dismisses it, nothing reaches the game (%s, %d mouse events)" % [_tips.current(), _rec.mouse - mouse])
		await _wait(0.25)
		_tips.event(c[1], c[2])
		await process_frame
		_check(_tips.current() != id, "  and it never shows again ('%s')" % _tips.current())
		_tips.dismiss()
		_context({})
	var counts := {}
	for s in _tips.shown_log:
		counts[s] = counts.get(s, 0) + 1
	_check(counts.size() == TouchTips.TIPS.size() and counts.values().all(func(n): return n == 1), "each tip showed exactly once: %s" % [counts])
	# remembered: a new start reads the tips file
	var again: CanvasLayer = TouchTips.new()
	again.store_path = STORE
	again.setup(1.0)
	root.add_child(again)
	_check(again.state().seen.size() == TouchTips.TIPS.size(), "after a restart all %d are still seen: %s" % [TouchTips.TIPS.size(), again.state().seen])
	again.queue_free()


func _wiring() -> void:
	_tips.reset()
	_controls.apply_options({"OpenBFMETouchHelp": "tips", "OpenBFMETouchTips": "yes"})
	# a previewed button (IOS-40's first tap): the preview tip, clear of the armed button
	_hud.button = {"kind": "movie", "target": "Farm", "costs": true, "autocast": false, "name": "Farm", "slot": -1, "rect": Rect2(1100, 600, 60, 60),
		"command": "Command_ConstructFarm"}
	_down(0, Vector2(1130, 630))
	_up(0, Vector2(1130, 630))
	await process_frame
	_check(_tips.current() == "preview", "a first tap on a costing button shows the preview tip: '%s'" % _tips.current())
	_check(not _tips.state().rect.intersects(Rect2(1100, 600, 60, 60).grow(12)), "  clear of the armed button: %s" % [_tips.state().rect])
	# the second tap uses it: the tip is learned, it goes
	_down(0, Vector2(1130, 630))
	_up(0, Vector2(1130, 630))
	await process_frame
	_check(_tips.learned("preview") and _tips.current() != "preview", "the second tap (a use) ends it as learned: %s" % [_tips.state().learned])
	_controls._disarm("test")
	_hud.button = {}
	# a hold on a HUD button (IOS-21): learned, so the selection's tip never shows
	_hud.button = {"kind": "movie", "target": "Stop", "costs": false, "autocast": false, "name": "Stop", "slot": -1, "rect": Rect2(1100, 500, 60, 60), "command": ""}
	_down(0, Vector2(1130, 530))
	await _wait(0.6)
	_up(0, Vector2(1130, 530))
	await process_frame
	_check(_tips.learned("hold"), "a hold on a button marks 'hold' learned")
	_hud.button = {}
	_tips.event("selected")
	await process_frame
	_check(_tips.current() != "hold", "so a selection does not show it: '%s'" % _tips.current())
	# a ghost waiting for ✓ / ✕ (IOS-26): the place tip, clear of ✓ / ✕ (here right under the top)
	_hud.placing = true
	_down(0, Vector2(640, 90))
	_up(0, Vector2(640, 90))
	await process_frame
	_check(_controls._confirming, "a tap with a placement waiting leaves the ghost for ✓ / ✕")
	_check(_tips.current() == "place", "the place tip shows: '%s'" % _tips.current())
	var rect: Rect2 = _tips.state().rect
	var confirm: Dictionary = _controls._confirm.state()
	_check(rect.has_area() and not rect.grow(4).has_point(confirm.build) and not rect.grow(4).has_point(confirm.cancel)
		and not rect.intersects(Rect2(Vector2(confirm.build) - Vector2(30, 30), Vector2(60, 60))),
		"  the panel keeps off ✓ / ✕: %s, ✓ %s ✕ %s" % [rect, confirm.build, confirm.cancel])
	# the moment ends within MIN_READ_S (✕ on the ghost): the tip goes and is not counted as seen
	_controls._confirm_cancel()
	_hud.placing = false
	await _wait(0.35)
	_check(_tips.current() == "" and not _tips.seen("place"), "the ghost went at once: the tip went and counts as unseen (%s)" % [_tips.state().seen])
	# a two-finger pan: 'camera' learned
	_down(0, Vector2(400, 400))
	_down(1, Vector2(500, 400))
	for i in 6:
		_move(0, Vector2(400 + 12 * i, 400))
		_move(1, Vector2(500 + 12 * i, 400))
	_up(0, Vector2(460, 400))
	_up(1, Vector2(560, 400))
	_check(_tips.learned("camera"), "a two-finger pan marks 'camera' learned")
	_tips.event("drag_box")
	await process_frame
	_check(_tips.current() != "camera", "so a box drag does not show it: '%s'" % _tips.current())
	# one at a time: two offered together show one after the other
	_poll(false)
	_tips.reset()
	_context({"armed": true})
	_tips.event("armed", {"autocast": true})
	await process_frame
	_check(_tips.current() == "preview" and _tips.state().queue == ["autocast"], "two at once: one shows, the other waits: %s %s" % [_tips.current(), _tips.state().queue])
	_tips.dismiss()
	await process_frame
	_check(_tips.current() == "autocast", "and comes after it: '%s'" % _tips.current())
	_tips.dismiss()
	_context({})


func _toggle_and_reset() -> void:
	_tips.reset()
	_controls.apply_options({"OpenBFMETouchHelp": "tips", "OpenBFMETouchTips": "no"})
	_check(not _tips.enabled, "Show tips off reaches the tips")
	for c in [["selected", {}], ["drag_box", {}]]:
		_tips.event(c[0], c[1])
	_context({"placing": true})
	_tips.event("placement_wait", {"line": false, "twist": true})
	await process_frame
	_check(_tips.current() == "" and _tips.state().queue.is_empty() and _tips.state().seen.is_empty(), "with Show tips off nothing shows or waits: %s" % [_tips.state()])
	_context({})
	_controls.apply_options({"OpenBFMETouchHelp": "card", "OpenBFMETouchTips": "yes"})
	_tips.event("selected")
	await process_frame
	_check(_tips.current() == "", "Card only: no tips either")
	_controls.apply_options({"OpenBFMETouchHelp": "tips", "OpenBFMETouchTips": "yes"})
	_tips.suppressed = true
	_tips.event("selected")
	await process_frame
	_check(_tips.current() == "", "the self-test's suppression wins over the options")
	_tips.suppressed = false
	_tips.event("selected")
	await process_frame
	_check(_tips.current() == "hold", "on again: the hold tip shows ('%s')" % _tips.current())
	_tips.dismiss()
	_tips.reset()
	_check(_tips.state().seen.is_empty() and _tips.progress().tips_known == 0, "Reset tips forgets every tip")
	_tips.event("selected")
	await process_frame
	_check(_tips.current() == "hold", "and the hold tip shows again")
	_tips.dismiss()


func _guide() -> void:
	_tips.reset()
	_controls.apply_options({"OpenBFMETouchHelp": "guide", "OpenBFMETouchTips": "yes"})
	await process_frame
	_context({})
	_check(_tips.current() == "guide:select", "the guide starts at its first step: '%s'" % _tips.current())
	_check(_tips._head.visible and _tips._action.skip and _tips._action.size.x >= 44.0, "  its head shows and its action is Skip (44 pt high)")
	_tips.event("selected")
	await process_frame
	_check(_tips.current() == "guide:move", "selecting: step 2 '%s'" % _tips.current())
	_tips.event("ordered")
	await process_frame
	_check(_tips.current() == "guide:buttons", "an order: step 3 '%s'" % _tips.current())
	_context({"placing": true})
	_tips.event("placement_wait", {"line": false, "twist": true})
	await process_frame
	_check(_tips.current() == "guide:placing", "a ghost waits: the placing line '%s'" % _tips.current())
	_tips.event("placement_built")
	_context({})
	await process_frame
	_check(_tips.current() == "guide:hold", "built (step 3 done): step 4 '%s'" % _tips.current())
	_tips.event("info")
	await process_frame
	_check(_tips.current() == "guide:camera", "a hold: step 5 '%s'" % _tips.current())
	_tips.event("camera", {"kind": "pan"})
	await process_frame
	_check(_tips.current() == "guide:camera", "a pan alone is not all of step 5")
	_tips.event("camera", {"kind": "zoom"})
	await process_frame
	_check(_tips.current() == "guide:finished" and _tips.state().guide_finished, "pan and zoom: the guide is done '%s'" % _tips.current())
	_tips.dismiss()
	# Skip
	_tips.reset()
	_context({})
	await process_frame
	_check(_tips.current() == "guide:select", "after Reset tips the guide starts again")
	var skip: Vector2 = Rect2(_tips._action.global_position, _tips._action.size).get_center()
	_down(0, skip)
	_up(0, skip)
	await process_frame
	_check(_tips.state().guide_finished and _tips.current() == "guide:finished", "Skip ends it for good, saying where the help is")
	_tips.dismiss()
	_tips.event("selected")
	await process_frame
	_check(_tips.current() == "", "no step after Skip ('%s')" % _tips.current())
	_controls.apply_options({"OpenBFMETouchHelp": "tips", "OpenBFMETouchTips": "yes"})


func _card() -> void:
	var card: CanvasLayer = _controls.help_card
	_controls.drag_mode = "pan"
	_controls.open_help_card("test")
	await process_frame
	var st: Dictionary = card.state()
	_check(st.open and st.entries == 12 and st.columns == 2, "the card opens: 12 gestures in 2 columns: %s" % [st])
	var lines: Array = card.entries(_controls.help_switches()).map(func(e): return e[2])
	_check(lines[2].begins_with("Move the view"), "its drag line follows One finger drag = Move the view: '%s'" % lines[2])
	_controls.drag_mode = "select"
	_check(_controls._safe_rect().encloses(st.card_rect), "  inside the safe area: %s" % [st.card_rect])
	# modal: a finger on the card does nothing to the game; a second finger neither
	var mouse := _rec.mouse
	var on_card: Vector2 = Rect2(st.card_rect).get_center()
	_down(0, on_card)
	_down(1, on_card + Vector2(40, 0))
	_up(1, on_card + Vector2(40, 0))
	_up(0, on_card)
	await process_frame
	_check(card.is_open() and _rec.mouse == mouse, "modal: fingers on it reach nothing and it stays open")
	var close: Vector2 = Rect2(card._close.global_position, card._close.size).get_center()
	_down(0, close)
	_up(0, close)
	await process_frame
	_check(not card.is_open(), "✕ closes it")
	_controls.open_help_card("test")
	await process_frame
	_down(0, Vector2(4, 4))
	_up(0, Vector2(4, 4))
	await process_frame
	_check(not card.is_open() and _rec.mouse == mouse, "a tap outside closes it, nothing reaches the game")


## the touch layer's poll of the context (every TOOLBAR_POLL_MS) on or held off
func _poll(on: bool) -> void:
	_controls._toolbar_poll_ms = 0 if on else 1 << 40


## the context the touch layer would give (a game, no menu, plus `extra`)
func _context(extra: Dictionary) -> void:
	var ctx := {"game": true, "menu": false, "mouse": false, "placing": false, "aiming": false, "armed": false}
	for k in extra:
		ctx[k] = extra[k]
	_tips.set_context(ctx, [], 0.0, _controls._safe_rect())


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
