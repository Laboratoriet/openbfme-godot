## Headless test of lane IOS-43 in the touch layer (scripts/touch/touch_controls.gd, scripts/touch/touch_targeting.gd, scripts/touch/placement_confirm.gd),
## against a stand-in HUD: no game, no extension needed. While a power or a hero ability waits for its target (the stand-in's touch_targeting_at):
##  * the banner: "Choose where: <power>" / "Choose a target: <power>" with the line saying what to do, inside the view, under the top, a 44 pt ✕;
##    gone once nothing waits;
##  * a ground power, "Aim powers" Confirm first (the default): a finger down on the map puts the pointer (the aim) GHOST_OFFSET_PT above the fingertip
##    and presses nothing; a drag moves it at that offset, pressing nothing; the power's ring shows there when the game draws no decal (gold, red on a
##    spot it cannot land on), none when it does; lifting leaves the aim with ✓ / ✕ beside it (44 pt targets, off the banner), nothing pressed; ✓ is one
##    left click at the aim (the cast); a tap puts the aim under the tap point; ✕ beside it and the banner's ✕ cancel through cancel_targeting (no click);
##    on a red spot ✓ is dimmed and a tap on it clicks nothing (the refusal) and the aim waits; two fingers pan the camera and the aim keeps its ground
##    point (✓ / ✕ hide, then come back beside it); a hold on the map is the right click (the game's cancel);
##  * a target power: a tap on an ally (a target it cannot have) or on the ground refuses (no click, no ✓ / ✕); a tap on an enemy picks it (the sight
##    around it, ✓ / ✕ beside it); ✓ is one left click on the enemy's pick point, after it moved too;
##  * "Above the finger" off: the aim under the finger;
##  * "Aim powers" On tap: the banner says "tap", a tap is the left click at once (the cast, the pre-IOS-43 behaviour), no ✓ / ✕;
##  * with no power waiting, a tap is still the left click and a drag the selection box.
## The game's own check is the touch self-test (touch_selftest.gd: a real spell book power and a hero ability).
##
##   godot --headless --path godot --script res://tests/ios43_touch_test.gd
##
## Exit codes: 0 pass, 1 fail.
extends SceneTree

const TouchControls := preload("res://scripts/touch/touch_controls.gd")
const PlacementConfirm := preload("res://scripts/touch/placement_confirm.gd")
const TouchTargeting := preload("res://scripts/touch/touch_targeting.gd")

const HUD_BAND := 80.0   # the stand-in's HUD: the bottom HUD_BAND pixels of the view
const SCALE := 2.0       # px per point (the Mac stand-in's)
const RADIUS := 50.0     # the stand-in power's RadiusCursorRadius (ground units: a pixel each at this camera)
const PICK_PX := 24.0    # a unit is picked within this many pixels of its point


## InGameHudNode's calls the touch layer makes. The "camera" is a shift: a pixel's ground point is the pixel plus the camera's position. A power waits
## ("location" or "object"); a ground point left of BAD_X (ground units) is no place for it. Like the game, a left press on the map casts where the
## query says it would and ends the wait; a right press cancels
class StubHud:
	extends Node
	const BAD_X := 300.0
	var waiting := ""        # "", "location", "object"
	var decal := false       # the game draws the power's radius decal (the touch ring then stays off)
	var view := Vector2.ZERO
	var cam := Vector2.ZERO
	var units := {}          # id -> [ground point, enemy]
	var casts: Array = []    # ["location", ground point] / ["object", id]
	var cancels := 0         # cancel_targeting calls that cancelled

	func on_hud(p: Vector2) -> bool:
		return p.y >= view.y - HUD_BAND

	func unit_at(p: Vector2) -> int:
		for id in units:
			if (units[id][0] - cam).distance_to(p) <= PICK_PX:
				return id
		return 0

	func touch_targeting_at(p: Vector2) -> Dictionary:
		if waiting == "":
			return {"kind": ""}
		var world := not on_hud(p) and Rect2(Vector2.ZERO, view).has_point(p)
		var id := unit_at(p)
		var valid := world and ((p + cam).x >= BAD_X if waiting == "location" else id != 0 and bool(units[id][1]))
		return {"kind": waiting, "source": "spell_book" if waiting == "location" else "ability", "power": "SpellBookHeal" if waiting == "location" else "SpecialAbilityIstariLight",
			"button": "Command_Stub", "command": "SPELL_BOOK" if waiting == "location" else "SPECIAL_POWER", "label": "Heal" if waiting == "location" else "Istari Light",
			"radius": RADIUS if waiting == "location" else 0.0, "decal": decal, "decal_drawn": decal, "world": world, "ground": true, "valid": valid, "object": id}

	func cancel_targeting() -> bool:
		if waiting == "":
			return false
		waiting = ""
		cancels += 1
		return true

	func pick_box_pixels(id: int) -> PackedVector2Array:
		if not units.has(id):
			return PackedVector2Array()
		var c: Vector2 = units[id][0] - cam
		return PackedVector2Array([c, c + Vector2(-10, -16), c + Vector2(10, 16)])

	func touch_placement_at(p: Vector2) -> Dictionary:
		return {"placing": false, "line_build": false, "world": not on_hud(p), "builds": 0}

	func get_placement() -> Dictionary:
		return {"placing": false, "legal": 0}

	func touch_button_at(p: Vector2) -> Dictionary:
		return {"kind": "movie" if on_hud(p) else "", "target": "", "autocast": false}

	func nearest_button(p: Vector2, _radius: float) -> Dictionary:
		return {"snapped": false, "position": p, "reason": "aiming" if waiting != "" else "far", "target": ""}

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
		if b == null or not b.pressed or waiting == "":
			return
		if b.button_index == MOUSE_BUTTON_RIGHT:
			waiting = ""
			return
		if b.button_index != MOUSE_BUTTON_LEFT:
			return
		var q := touch_targeting_at(b.position)
		if not bool(q.valid):
			return
		casts.append(["location", b.position + cam] if waiting == "location" else ["object", int(q.object)])
		waiting = ""


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
var _offset := Vector2.ZERO


func _initialize() -> void:
	var code: int = await _run()
	print("IOS43 TOUCH %s" % ["PASS" if code == 0 else "FAIL"])
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
	var stage := SubViewport.new()
	stage.size = Vector2i(1335, 939)
	root.add_child(stage)
	_controls = TouchControls.new()
	stage.add_child(_controls)
	await process_frame
	_controls.active = true
	_controls.set_process(true)
	Input.emulate_mouse_from_touch = false
	_controls._scale = SCALE
	_controls._hud = _hud
	var view: Vector2 = _controls.get_viewport().get_visible_rect().size
	_hud.view = view
	_offset = Vector2(0, TouchControls.GHOST_OFFSET_PT * SCALE)
	print("  view %s, aim offset %s px" % [view, _offset])
	await _wait(0.5)
	var f := Vector2(view.x * 0.5, view.y * 0.55)

	# ---- nothing waits: the taps and drags of before -------------------------------------------------------------------------------------------
	_rec.buttons.clear()
	await _tap(f)
	await _wait(0.4)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, f]], "no power waits: a tap is the left click: %s" % [_rec.buttons])
	_check(not _ui().get("banner", false), "no power waits: no banner")
	await _wait(0.4)

	# ---- a ground power, Confirm first ---------------------------------------------------------------------------------------------------------
	_hud.waiting = "location"
	await _wait(0.4)
	var ui := _ui()
	_check(ui.get("banner", false), "a ground power waits: the banner shows")
	_check(str(ui.get("title", "")) == "Choose where: Heal", "its title: %s" % ui.get("title", ""))
	_check(str(ui.get("hint", "")).contains("✓"), "its line says what to do: %s" % ui.get("hint", ""))
	var br: Rect2 = ui.get("banner_rect", Rect2())
	_check(Rect2(Vector2.ZERO, view).encloses(br) and br.position.y < view.y * 0.2, "the banner is inside the view, at the top: %s" % br)
	_check(br.size.y >= 44.0 * SCALE - 0.5, "the banner is at least 44 pt high (its ✕ cell): %s" % br.size)
	_check(br.has_point(ui.cancel), "the banner's ✕ is on it: %s" % ui.cancel)

	_rec.buttons.clear()
	_down(f)
	await _wait(0.05)
	_check(_rec.pointer == f - _offset, "finger down: the aim %s is %s above the finger %s" % [_rec.pointer, _offset, f])
	_check(_rec.buttons.is_empty(), "finger down presses nothing: %s" % [_rec.buttons])
	var g := f + Vector2(140, -60)
	await _drag_to(f, g)
	await process_frame
	_check(_rec.pointer == g - _offset, "drag: the aim follows at the offset: %s" % _rec.pointer)
	_check(_rec.buttons.is_empty(), "the drag presses nothing (no selection box): %s" % [_rec.buttons])
	ui = _ui()
	_check(Vector2(ui.ring) == g - _offset and bool(ui.ring_valid), "mid-drag: the power's ring at the aim, gold: %s %s" % [ui.ring, ui.ring_valid])
	_check(is_equal_approx(float(ui.ring_radius), RADIUS), "the ring is the power's radius on the ground: %.1f" % float(ui.ring_radius))
	_up(g)
	await _wait(0.1)
	var s := _aim()
	_check(s.waiting and Vector2(s.aim) == g - _offset, "lift: the aim waits at the offset point: %s" % s.aim)
	_check(_rec.buttons.is_empty() and _hud.casts.is_empty(), "the lift presses nothing, casts nothing: %s" % [_rec.buttons])
	var c: Dictionary = s.confirm
	_check(c.shown and c.build_enabled, "✓ / ✕ show beside it, ✓ live: %s" % c)
	_check(float(c.hit_radius) * 2.0 >= 44.0 * SCALE, "their targets are at least 44 pt")
	_check(Vector2(c.build).distance_to(g - _offset) >= RADIUS, "✓ sits outside the power's ring: %s" % c.build)
	_check(not br.has_point(c.build) and not br.has_point(c.cancel), "✓ / ✕ are off the banner")

	# two fingers pan: the aim keeps its ground point
	var ground: Vector2 = _hud.pixel_to_world(g - _offset)
	await _pan(Vector2(300, 300), Vector2(-120, 40))
	await _wait(0.8)
	s = _aim()
	var expect: Vector2 = _hud.world_to_pixel(ground)
	_check(s.waiting and Vector2(s.aim).distance_to(expect) < 2.0, "two fingers pan: the aim keeps its ground point: %s (expected %s)" % [s.aim, expect])
	_check(Dictionary(s.confirm).shown and Vector2(s.confirm.build).distance_to(Vector2(s.aim)) < 300.0, "✓ / ✕ came back beside it")
	_check(_presses().is_empty(), "the pan pressed nothing: %s" % [_presses()])

	# ✓: the cast at the aim
	_rec.buttons.clear()
	var aim_px: Vector2 = s.aim
	await _tap(Vector2(s.confirm.build))
	await _wait(0.3)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, aim_px]], "✓ is one left click at the aim: %s" % [_presses()])
	_check(_hud.casts.size() == 1 and Vector2(_hud.casts[0][1]).distance_to(ground) < 2.0, "the power cast at the aim's ground point: %s" % [_hud.casts])
	ui = _ui()
	_check(not ui.banner and not Dictionary(_aim().confirm).shown and not Vector2(ui.ring).is_finite(), "the cast: the banner, ✓ / ✕ and the ring go")
	await _wait(0.4)

	# a tap: the aim under the tap point; ✕ beside it cancels (no click)
	_hud.waiting = "location"
	await _wait(0.3)
	_rec.buttons.clear()
	var h := f + Vector2(-80, 30)
	await _tap(h)
	await _wait(0.1)
	s = _aim()
	_check(s.waiting and Vector2(s.aim) == h, "a tap: the aim under the tap point: %s" % s.aim)
	await _tap(Vector2(s.confirm.cancel))
	await _wait(0.3)
	_check(_hud.cancels == 1 and _hud.waiting == "" and _presses().is_empty(), "✕ beside it: the game's cancel, no click: cancels %d %s" % [_hud.cancels, _presses()])
	_check(not _ui().banner, "the cancel: the banner goes")
	await _wait(0.4)

	# the banner's ✕
	_hud.waiting = "location"
	await _wait(0.3)
	_rec.buttons.clear()
	await _tap(Vector2(_ui().cancel))
	await _wait(0.3)
	_check(_hud.cancels == 2 and _hud.waiting == "" and _presses().is_empty(), "the banner's ✕ cancels, no click: cancels %d" % _hud.cancels)
	await _wait(0.4)

	# a red spot: ✓ dimmed, a tap on it clicks nothing and the aim waits; the ring is red
	_hud.waiting = "location"
	await _wait(0.3)
	var bad := Vector2(150, view.y * 0.5)
	_rec.buttons.clear()
	await _tap(bad)
	await _wait(0.2)
	s = _aim()
	_check(s.waiting and not Dictionary(s.confirm).build_enabled, "on a spot it cannot land on ✓ is dimmed: %s" % s.confirm)
	_check(not bool(Dictionary(s.ui).ring_valid), "and the ring is red")
	var refused: int = _controls.stats.aim_refused
	await _tap(Vector2(s.confirm.build))
	await _wait(0.2)
	_check(_presses().is_empty() and _hud.casts.size() == 1 and _hud.waiting == "location", "a tap on the dimmed ✓ clicks nothing, the power waits: %s" % [_presses()])
	_check(int(_controls.stats.aim_refused) == refused + 1 and bool(Dictionary(_aim().ui).refusing), "the refusal mark shows")
	# the game's decal drawn: no touch ring
	_hud.decal = true
	await _tap(f)
	await _wait(0.3)
	_check(not Vector2(_ui().ring).is_finite(), "a power whose decal the game draws gets no touch ring")
	_hud.decal = false
	# a hold on the map: the right click (the game's cancel)
	_rec.buttons.clear()
	_down(f)
	await _wait(0.7)
	_up(f)
	await _wait(0.3)
	_check(_hud.waiting == "" and _presses() == [[MOUSE_BUTTON_RIGHT, f]], "a hold on the map: the right click cancels: %s" % [_presses()])
	await _wait(0.4)

	# ---- a target power ------------------------------------------------------------------------------------------------------------------------
	var ally_px := f + Vector2(-200, 0)
	var enemy_px := f + Vector2(200, -40)
	_hud.units = {11: [ally_px + _hud.cam, false], 12: [enemy_px + _hud.cam, true]}
	_hud.waiting = "object"
	await _wait(0.4)
	_check(str(_ui().title) == "Choose a target: Istari Light", "a target power's banner: %s" % _ui().title)
	_rec.buttons.clear()
	refused = _controls.stats.aim_refused
	await _tap(ally_px)
	await _wait(0.2)
	_check(not _aim().waiting and _presses().is_empty() and int(_controls.stats.aim_refused) == refused + 1, "a tap on an ally: refused, no click, no ✓ / ✕")
	await _tap(f + Vector2(0, -150))
	await _wait(0.2)
	_check(not _aim().waiting and int(_controls.stats.aim_refused) == refused + 2, "a tap on the ground: refused")
	await _tap(enemy_px + Vector2(6, 4))
	await _wait(0.2)
	s = _aim()
	_check(s.waiting and int(s.object) == 12 and Vector2(s.aim) == enemy_px, "a tap on the enemy picks it: %s" % s)
	_check(Vector2(Dictionary(s.ui).target) == enemy_px and float(Dictionary(s.ui).target_radius) > PICK_PX, "the sight is around it")
	_check(Dictionary(s.confirm).shown and Dictionary(s.confirm).build_enabled, "✓ / ✕ beside it")
	_check(_presses().is_empty(), "picking it pressed nothing")
	# the enemy walks: ✓ clicks where it is now
	var walked := enemy_px + Vector2(30, 10)
	_hud.units[12][0] = walked + _hud.cam
	await _wait(0.3)
	_check(Vector2(_aim().aim) == walked and Vector2(Dictionary(_aim().ui).target) == walked, "the sight follows it: %s" % _aim().aim)
	_rec.buttons.clear()
	await _tap(Vector2(_aim().confirm.build))
	await _wait(0.3)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, walked]], "✓ is one left click on it: %s" % [_presses()])
	_check(_hud.casts.size() == 2 and _hud.casts[1] == ["object", 12], "the power cast at the enemy: %s" % [_hud.casts])
	await _wait(0.4)

	# ---- "Above the finger" off ----------------------------------------------------------------------------------------------------------------
	_controls.apply_options({"OpenBFMETouchGhostAbove": "no"})
	_hud.waiting = "location"
	await _wait(0.3)
	_down(f)
	await _drag_to(f, g)
	_check(_rec.pointer == g, "Above the finger off: the aim under the finger: %s" % _rec.pointer)
	_up(g)
	await _wait(0.1)
	_check(Vector2(_aim().aim) == g, "and it waits there")
	await _tap(Vector2(_ui().cancel))
	await _wait(0.3)
	_controls.apply_options({})

	# ---- "Aim powers" On tap -------------------------------------------------------------------------------------------------------------------
	_controls.apply_options({"OpenBFMETouchTargeting": "tap"})
	_check(str(_controls.switches().get("targeting", "")) == "tap", "the switch reads On tap: %s" % _controls.switches())
	_hud.waiting = "location"
	await _wait(0.4)
	_check(_ui().banner and str(_ui().hint).begins_with("Tap the map"), "On tap: the banner says a tap uses it: %s" % _ui().hint)
	_rec.buttons.clear()
	await _tap(f)
	await _wait(0.6)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, f]] and _hud.casts.size() == 3, "On tap: a tap is the left click at once, the cast: %s" % [_presses()])
	_check(not _aim().waiting and not Dictionary(_aim().confirm).get("shown", false), "On tap: no ✓ / ✕")
	_controls.apply_options({})
	_check(str(_controls.switches().get("targeting", "")) == "confirm", "the default is Confirm first")

	# ---- nothing waits again: a drag is the box ------------------------------------------------------------------------------------------------
	await _wait(0.5)
	_rec.buttons.clear()
	_down(f)
	await _drag_to(f, f + Vector2(80, 40))
	_up(f + Vector2(80, 40))
	await _wait(0.1)
	_check(_presses() == [[MOUSE_BUTTON_LEFT, f]], "with nothing waiting a drag is the box again: %s" % [_presses()])
	return 0 if _failures == 0 else 1


func _ui() -> Dictionary:
	return Dictionary(_controls.aim_state().get("ui", {}))


func _aim() -> Dictionary:
	return _controls.aim_state()


func _presses() -> Array:
	var out: Array = []
	for b in _rec.buttons:
		if b[2]:
			out.append([b[0], b[1]])
	return out


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
