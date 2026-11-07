extends "res://scripts/touch/touch_selftest.gd"
## Lane IOS-46: `-- --touch --touch-help-shots=<folder>` in a game (with --auto): pictures of the three touch help prototypes for the owner's choice,
## in the window's orientation (<folder>/<option>-<state>-<landscape|portrait>.png), driven by the touch self-test's synthetic fingers:
##   (b) tips ...... the hold tip after a selection, the preview tip on an armed build button, the place and twist tips at a waiting ghost, the aim tip
##                   under a power's banner, the camera tip
##   (a) guide ..... its first step, its third, its placing line at a waiting ghost, its last line
##   (c) card ...... the card over the game, the pause menu's "Touch controls" button, the card over the pause menu
## The tips use a file of their own (user://touch-tips-shots.cfg, emptied first), never the player's. Prints TOUCH HELP SHOTS DONE (or FAIL <why>).

var _fails := PackedStringArray()


func start(controls: Node, out_dir: String) -> void:
	_controls = controls
	_out = out_dir
	DirAccess.make_dir_recursive_absolute(_out)
	_shots()


func _shots() -> void:
	var hud: Node = null
	for i in 600:
		hud = _controls._game_hud()
		if hud != null and Vector2(hud.get_camera().get("position", Vector2.INF)).is_finite():
			break
		await get_tree().create_timer(0.1).timeout
	if hud == null:
		print("TOUCH HELP SHOTS FAIL: no game on screen")
		return
	await _wait(3.0)
	var tips: CanvasLayer = _controls.tips
	tips.store_path = "user://touch-tips-shots.cfg"
	tips.reset()
	tips.apply("tips", true)
	await _tips_shots(hud, tips)
	tips.reset()
	tips.apply("guide", true)
	await _guide_shots(hud, tips)
	tips.apply("tips", true)
	tips.reset()
	await _card_shots(hud)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://touch-tips-shots.cfg"))
	print("TOUCH HELP SHOTS %s" % ("DONE" if _fails.is_empty() else "FAIL " + "; ".join(_fails)))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _pic(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return
	var path := _out.path_join("%s-%s.png" % [label, _orient()])
	print("TOUCH HELP SHOTS picture %s: %s %s" % [path, error_string(image.save_png(path)), JSON.stringify(_controls.help_state().tips.get("current", ""))])


func _expect(tips: CanvasLayer, want: String, what: String) -> void:
	if tips.current() != want:
		_fails.append("%s: the panel shows '%s', not '%s'" % [what, tips.current(), want])


## a builder selected (the touch layer's world tap is the tested path; here the selection is made directly and its news given)
func _select(hud: Node, tips: CanvasLayer) -> bool:
	if await _select_builder(hud) < 0:
		_fails.append("no builder of the local player")
		return false
	tips.event("selected")
	await _wait(0.6)
	return true


## the builder's build button tapped once (armed: the preview), then again (the placement), then a tap on open ground (✓ / ✕)
func _to_ghost(hud: Node) -> bool:
	var button := _build_button(hud)
	if button.is_empty():
		_fails.append("no build button on screen")
		return false
	await _tap(button.position)
	await _wait(0.45)
	await _tap(button.position)
	await _wait(0.8)
	if not bool(hud.get_placement().get("placing", false)):
		_fails.append("the build button started no placement")
		return false
	var size := get_viewport().get_visible_rect().size
	await _tap(_open_ground(hud, size * Vector2(0.5, 0.42)))
	await _wait(0.8)
	return _controls._confirming


func _cancel_ghost() -> void:
	if _controls._confirming:
		await _tap(_controls._confirm.centre("cancel"))
		await _wait(0.5)


func _tips_shots(hud: Node, tips: CanvasLayer) -> void:
	if not await _select(hud, tips):
		return
	_expect(tips, "hold", "tips: the selection")
	await _pic("b-tips-1-hold")
	tips.dismiss()
	await _wait(0.4)
	var button := _build_button(hud)
	if not button.is_empty():
		await _tap(button.position)
		await _wait(0.6)
		_expect(tips, "preview", "tips: the first tap on a build button")
		await _pic("b-tips-2-preview")
		await _wait(0.45)
		await _tap(button.position)  # the use: the placement starts (the preview tip ends as learned)
		await _wait(0.8)
		var size := get_viewport().get_visible_rect().size
		await _tap(_open_ground(hud, size * Vector2(0.5, 0.42)))
		await _wait(0.8)
		_expect(tips, "place", "tips: the ghost waits for ✓ / ✕")
		await _pic("b-tips-3-place")
		tips.dismiss()
		await _wait(0.5)
		_expect(tips, "twist", "tips: after the place tip, while the ghost waits")
		await _pic("b-tips-4-twist")
		tips.dismiss()
		await _cancel_ghost()
	await _aim(hud)
	_expect(tips, "aim", "tips: a power waits for its aim")
	await _pic("b-tips-5-aim")
	tips.dismiss()
	hud.cancel_targeting()
	await _wait(0.6)
	tips.event("drag_box")
	await _wait(0.5)
	_expect(tips, "camera", "tips: a box drag")
	await _pic("b-tips-6-camera")
	tips.dismiss()
	await _wait(0.4)


## Heal from the spell book (points from the test hook), left waiting for its aim (the self-test's IOS-43 step, without its checks)
func _aim(hud: Node) -> void:
	var game: Node = get_tree().current_scene
	var world = game.get("_world")
	var me := int(game.get("_local_index"))
	world.debug_add_science_points(me, 10)
	world.purchase_science(me, "SCIENCE_Heal")
	await _wait(1.5)
	var index := -1
	for b in world.get_spell_bar(me).get("buttons", []):
		if str(b.power) == "SpellBookHeal":
			index = int(b.index)
	var sb: Dictionary = hud.get_spellbook_state()
	var slots: Array = sb.get("slot_buttons", [])
	for i in slots.size():
		if int(slots[i]) == index:
			hud.press_spell_slot(i)
	await _wait(1.0)


func _guide_shots(hud: Node, tips: CanvasLayer) -> void:
	hud.deselect_all()
	await _wait(0.8)
	_expect(tips, "guide:select", "guide: its first step")
	await _pic("a-guide-1-select")
	if not await _select(hud, tips):
		return
	tips.event("ordered")
	await _wait(0.6)
	_expect(tips, "guide:buttons", "guide: after a selection and an order")
	await _pic("a-guide-2-buttons")
	if await _to_ghost(hud):
		_expect(tips, "guide:placing", "guide: a ghost waits")
		await _pic("a-guide-3-placing")
		await _cancel_ghost()
	for e in [["armed_use", {}], ["info", {}], ["camera", {"kind": "pan"}], ["camera", {"kind": "zoom"}]]:
		tips.event(e[0], e[1])
	await _wait(0.6)
	_expect(tips, "guide:finished", "guide: every step done")
	await _pic("a-guide-4-finished")
	tips.dismiss()
	hud.deselect_all()
	await _wait(0.4)


func _card_shots(hud: Node) -> void:
	_controls.open_help_card("shots")
	await _wait(0.6)
	await _pic("c-card-1-game")
	await _tap(Rect2(_controls.help_card._close.global_position, _controls.help_card._close.size).get_center())
	await _wait(0.5)
	var game: Node = get_tree().current_scene
	game._toggle_quit_menu()
	await _wait(1.2)
	_controls._update_help()
	await _wait(0.4)
	if not _controls.help_card.entry_shown():
		var menus: Node = _controls._menu_player()
		_fails.append("card: no Touch controls button on the pause menu (quit open %s, stack %s)" % [game.get("_quit_open"),
			menus.shell_stack() if menus != null else "no shell"])
	await _pic("c-card-2-pause-button")
	await _tap(_controls.help_card.entry_rect().get_center())
	await _wait(0.6)
	if not _controls.help_card.is_open():
		_fails.append("card: the pause menu's button did not open the card")
	await _pic("c-card-3-pause-card")
	await _tap(Vector2(4, 4))  # outside the card: it closes
	await _wait(0.5)
	await _options_shots(game)
	game._toggle_quit_menu()
	await _wait(0.8)


## the pause menu's SETTINGS: Options > Touch (its Help row), Touch > Help, and the card over it
func _options_shots(game: Node) -> void:
	var r: Dictionary = game._shell.quit_menu({"kind": "state"})
	var path := ""
	for b in game._shell.list_buttons(int(r.get("level", -1))):
		if b.hittable and String(b.path).contains(".Options."):
			path = String(b.path)
			break
	if path.is_empty():
		_fails.append("options: no SETTINGS button on the pause menu")
		return
	await game._click_button(int(r.level), path)
	await _wait(1.5)
	var screen: CanvasLayer = game._display_screen
	if screen == null or not screen.is_open():
		_fails.append("options: the page did not open")
		return
	screen._show_tab("Touch")
	await _wait(0.6)
	await _pic("c-options-1-touch")
	screen.touch_press("Touch.help")
	await _wait(0.6)
	if not screen.touch_help_page():
		_fails.append("options: HELP did not open the Help page")
	await _pic("c-options-2-help")
	screen.touch_press("Touch.card")
	await _wait(0.6)
	await _pic("c-options-3-card")
	_controls.help_card.close()
	await _wait(0.4)
	screen.touch_press("Touch.back")
	screen.close(false)
	await _wait(1.0)
