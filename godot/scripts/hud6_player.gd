## Lane HUD-6: RotWK's in-game UI pieces the owner's retail shots show (owner-shots/hud6), scripted for proof screenshots: every scenario prints
## "HUD6 <name>: ok" or "HUD6 <name>: FAIL <why>", saves hud6-<name>*.png in --screens and "HUD6 RESULT: <n> ok, <m> failed" ends the run. game.gd runs it with
## --auto --faction=FactionMordor --hud6=radial,help,heroes,sidebar
##   radial   the player's fortress selected by a click: its Radial command buttons ring over it as gold-rimmed bubbles (retail-1.png)
##   help     the pointer on a bubble, then on a Palantir arc button: the help box shows the button's name, shortcut, cost and description (retail-5.png)
##   heroes   the fortress's hero bubble pressed (PUSH_VISIBLE_COMMAND_RANGE): the ring of hero portraits (retail-2.png)
##   sidebar  a builder selected: the build list in the side bar's carved frame (retail-3.png)
##   queue    (lane OWNERFIX-3) a Men barracks of the player's: three presses of its soldiers' bubble, the bubble and the Palantir show "3" (RW 0x4A4CD3 / 0x9D7054)
##   enemy    (lane OWNERFIX-3) the enemy's barracks and hero, selected by a click: the Palantir shows their command set, every button disabled (RW 0x94397F)
##   modhero  (lane IOS-28, with the Sauron test mod enabled: tools/mod/make_sauron_mod.py, Options.ini OpenBFMEMods) the fortress's hero ring offers
##            MordorSauron without the ring: his bubble is clicked with 10,000 given, the fortress builds him (fast forward), he is selected
##            (hud6-modhero-ring, hud6-modhero-recruiting, hud6-modhero-made)
##   hudsize  (lane IOS-27, OpenBFME presentation; with --faction=FactionDwarves, --touch and an Options file's OpenBFMEHudScale) Rebuild bought in the
##            spell book (store button 1 of the Dwarves' set), a builder selected: the side bar as a block of one or two columns (hud6-hudsize-sidebar),
##            a held finger on the spell book's power and on the first and last button of each side bar column shows its help and presses nothing
##            (hud6-hudsize-hold-*); the tap assist takes a press 6 px off to the same button
##   round    (lane IOS-29, OpenBFME presentation; with --touch or an Options file's OpenBFMEHudScale above 100) the round-HUD audit (InGameHudNode
##            hud_scale_audit): a builder selected (hud6-round-builder), the pause menu (hud6-round-pause), the spell store (hud6-round-store); every
##            line "HUD6 round <where>: <path> sx sy fix", FAIL when the rule is on and any in-game movie unit or HUD draw has |sx / sy - 1| > 1 %
##            (a full-bleed backdrop, edge to edge on its stretched axis, is allowed: AptUniformHud::Entry::fullBleed)
extends "res://scripts/scenario_player.gd"

var game: Node
var hud: Node
var world: Node


func _run(p_game: Node, scenarios: PackedStringArray) -> void:
	game = p_game
	hud = game._hud
	world = game._world
	await _run_scenarios(scenarios)


# ---- helpers ----------------------------------------------------------------------------------------------------------------------------------------------

func shot(name: String) -> void:
	game._save_named("hud6-" + name)


func own() -> Array:
	return world.get_player_objects(game._local_name)


func look(x: float, y: float) -> void:
	hud.camera_look_at(Vector2(x, y))
	await game._step(20)


func click_pixel(p: Vector2, right: bool = false) -> void:
	hud.inject_mouse_move(p)
	await game._step(2)
	hud.inject_mouse_button(2 if right else 1, true, p)
	await game._step(1)
	hud.inject_mouse_button(2 if right else 1, false, p)
	await game._step(4)


func find_own(pred: Callable) -> Dictionary:
	for o in own():
		if pred.call(o):
			return o
	return {}


# a click where the object shows (the real pick); the id hook only as a logged fallback
func select_object(o: Dictionary) -> bool:
	await look(o.x, o.y)
	var centre: Vector2 = hud.world_to_pixel(Vector2(o.x, o.y))
	for dy in range(-120, 41, 10):
		for dx in [0, -20, 20, -40, 40]:
			var px := centre + Vector2(dx, dy)
			var probe: Dictionary = hud.pick_probe(px, int(o.id))
			if int(probe.get("picked", 0)) == int(o.id):
				await click_pixel(px)
				await game._step(6)
				if hud.get_selection().has(int(o.id)):
					print("HUD6 select: %s %d selected by a click at (%d, %d)" % [o.template, int(o.id), int(px.x), int(px.y)])
					return true
	print("HUD6 select: no click selected %s %d; selecting it by id (GAME TEST HOOK)" % [o.template, int(o.id)])
	return hud.select_object(int(o.id))


func radial() -> Dictionary:
	return hud.get_hud6_state().get("radial", {})


func help() -> Dictionary:
	return hud.get_hud6_state().get("help", {})


func bubble_centre(b: Dictionary) -> Vector2:
	var r: Rect2 = b.rect
	return r.position + r.size * 0.5


func fortress() -> Dictionary:
	return find_own(func(o): return str(o.template).find("Fortress") >= 0 and str(o.template).find("Citadel") >= 0)


# lane RELFIX-2: the open ground 450 units beside the fortress, on the side towards the map's middle. Evendim's Men start sits at the east edge (fortress
# x 4602 of a 5000-unit map), where fortress.x + 450 is off the map: an object there covers no shroud cell, so its owner sees it SHROUDED (RW 0xB4E890) and
# InGameUI::update deselects it on the next 30th client frame (RW 0x6A2449, no owner test: VISUAL-2 r2), which left the barracks scenario without bubbles
func beside_fortress(f: Dictionary, dy: float = 0.0) -> Vector2:
	var census: Dictionary = world.get_census()
	var side := 1.0
	if census.has("extent_x") and float(f.x) > float(census.extent_x) * 0.5:
		side = -1.0
	return Vector2(float(f.x) + side * 450.0, float(f.y) + dy)


# lane RELFIX-2: an object a scenario created is on the map and seen clear by the local player (its own sight or the player's), else why not
func check_seen(id: int, what: String) -> String:
	var census: Dictionary = world.get_census()
	if not census.has("extent_x"):
		return "no playable extent in the census"
	var st: int = world.get_object_shroud_status(id)
	if st != 1 and st != 2:
		return "%s %d is not seen clear by the local player (shroud status %d, playable extent %s x %s)" % [what, id, st, str(census.extent_x), str(census.extent_y)]
	return ""


func wait_help_shown() -> bool:
	for i in 60:
		if bool(help().get("shown", false)) and int(help().get("draws", 0)) > 0:
			return true
		await game._step(2)
	return false


# ---- scenarios ------------------------------------------------------------------------------------------------------------------------------------------

func _scenario_radial() -> String:
	var f := fortress()
	if f.is_empty():
		var names := []
		for o in own():
			names.append(o.template)
		return "no own fortress citadel among " + str(names)
	if not await select_object(f):
		return "the fortress could not be selected"
	hud.camera_set_height(330.0)
	await look(f.x, f.y)
	hud.inject_mouse_move(Vector2(60, 60))
	await game._step(30)
	var r := radial()
	print("HUD6 radial: %s" % JSON.stringify(r))
	shot("radial")
	if int(r.get("count", 0)) < 1:
		return "no bubbles over the fortress"
	if (r.get("errors", []) as Array).size() > 0:
		return "radial errors: " + str(r.errors)
	return ""


func _scenario_help() -> String:
	var r := radial()
	var buttons: Array = r.get("buttons", [])
	if buttons.is_empty():
		return "no bubbles (run radial first)"
	# the bubble the owner's shot hovers: a unit's build button if there is one
	var target: Dictionary = buttons[0]
	for b in buttons:
		if str(b.command) == "UNIT_BUILD":
			target = b
			break
	hud.inject_mouse_move(bubble_centre(target))
	await game._step(4)
	var ok := await wait_help_shown()
	await game._step(20)
	print("HUD6 help (bubble %s): %s" % [str(target.name), JSON.stringify(help())])
	if OS.get_environment("HUD6_DUMP") != "":
		var tree: String = hud.dump_tree(40)
		var keep := false
		for line in tree.split("\n"):
			if line.find("helpBox") >= 0:
				keep = true
			if keep:
				print("HUD6 TREE ", line)
	shot("help-bubble")
	if not ok:
		return "the help box did not show over bubble " + str(target.name)
	# the pointer off the buttons: the box hides
	hud.inject_mouse_move(Vector2(60, 60))
	await game._step(40)
	if bool(help().get("shown", false)):
		return "the help box stayed after the pointer left"
	# an arc button of the Palantir
	for b in hud.get_command_buttons():
		if str(b.frame).begins_with("CommandButtons."):
			var w: Dictionary = hud.find_button_window(b.frame)
			if w.get("found", false):
				hud.inject_mouse_move(Vector2(w.x, w.y))
				await game._step(4)
				var arc_ok := await wait_help_shown()
				await game._step(20)
				print("HUD6 help (arc %s): %s" % [str(b.name), JSON.stringify(help())])
				shot("help-arc")
				hud.inject_mouse_move(Vector2(60, 60))
				await game._step(20)
				if not arc_ok:
					return "the help box did not show over arc button " + str(b.name)
				return ""
	return "no arc button found"


func _scenario_heroes() -> String:
	var r := radial()
	for b in r.get("buttons", []):
		if str(b.command) == "PUSH_VISIBLE_COMMAND_RANGE":
			await click_pixel(bubble_centre(b))
			hud.inject_mouse_move(Vector2(60, 60))
			await game._step(30)
			var after := radial()
			print("HUD6 heroes: pressed %s -> %s" % [str(b.name), JSON.stringify(after)])
			shot("heroes")
			if int(after.get("count", 0)) < 2:
				return "the hero ring did not open"
			# back to the first ring (POP_VISIBLE_COMMAND_RANGE)
			for c in after.get("buttons", []):
				if str(c.command) == "POP_VISIBLE_COMMAND_RANGE":
					await click_pixel(bubble_centre(c))
					await game._step(10)
					break
			return ""
	return "the fortress has no PUSH_VISIBLE_COMMAND_RANGE bubble: " + JSON.stringify(r.get("buttons", []))


func _scenario_modhero() -> String:
	var f := fortress()
	if f.is_empty():
		return "no own fortress"
	var heroes: Array = world.get_heroes(game._local_index, int(f.id))
	var sauron := -1
	for h in heroes:
		if str(h.template) == "MordorSauron":
			sauron = int(h.index)
	print("HUD6 modhero: the fortress's heroes %s" % JSON.stringify(heroes))
	if sauron < 0:
		return "MordorSauron is not among the fortress's heroes (is the mod enabled and mounted?)"
	world.give_money(game._local_index, 10000)
	if not await select_object(f):
		return "the fortress could not be selected"
	hud.camera_set_height(330.0)
	await look(f.x, f.y)
	hud.inject_mouse_move(Vector2(60, 60))
	await game._step(30)
	var ring: Dictionary = {}
	for b in radial().get("buttons", []):
		if str(b.command) == "PUSH_VISIBLE_COMMAND_RANGE":
			await click_pixel(bubble_centre(b))
			hud.inject_mouse_move(Vector2(60, 60))
			await game._step(30)
			ring = radial()
			break
	print("HUD6 modhero ring: %s" % JSON.stringify(ring))
	shot("modhero-ring")
	# Sauron's bubble: the REVIVE button whose portrait is his (HISauron, sauron.ini ButtonImage)
	var bubble: Dictionary = {}
	for b in ring.get("buttons", []):
		if JSON.stringify(b).find("Sauron") >= 0 and str(b.command) == "REVIVE":
			bubble = b
	if bubble.is_empty():
		return "no Sauron bubble in the hero ring: " + JSON.stringify(ring.get("buttons", []))
	hud.inject_mouse_move(bubble_centre(bubble))
	await game._step(40)
	shot("modhero-help")
	await click_pixel(bubble_centre(bubble))
	hud.inject_mouse_move(Vector2(60, 60))
	await game._step(20)
	var queued := false
	for h in world.get_heroes(game._local_index, int(f.id)):
		if str(h.template) == "MordorSauron":
			queued = bool(h.in_production)
	if not queued:
		return "the Sauron bubble was clicked but he is not in production"
	shot("modhero-recruiting")
	world.set_time_scale(8.0)
	var made := {}
	for i in 200:
		await game._step(30)
		made = find_own(func(o): return str(o.template) == "MordorSauron")
		if not made.is_empty():
			break
	world.set_time_scale(1.0)
	if made.is_empty():
		return "Sauron was not made"
	await look(made.x, made.y)
	await select_object(made)
	hud.inject_mouse_move(Vector2(60, 60))
	await game._step(40)
	shot("modhero-made")
	print("HUD6 modhero made: %s" % JSON.stringify(made))
	return ""


func _scenario_sidebar() -> String:
	var b := find_own(func(o): return str(o.template).find("Worker") >= 0 or str(o.template).find("Porter") >= 0 or str(o.template).find("Builder") >= 0)
	if b.is_empty():
		return "no own builder"
	if not await select_object(b):
		return "the builder could not be selected"
	hud.inject_mouse_move(Vector2(60, 60))
	await game._step(60)
	var side: Dictionary = hud.get_hud6_state().get("side_bar", {})
	print("HUD6 sidebar: %s" % JSON.stringify(side))
	shot("sidebar")
	if not bool(side.get("shown", false)) or int(side.get("count", 0)) < 1:
		return "the side bar shows no framed buttons"
	return ""


# lane BUGS-1: the devlog's case (Devlog #4 take 4: the help box over a GondorBarracks bubble drew its frame with no text): a Men barracks of the
# player's (made with the world's create_object test hook), selected by a click, the pointer held on its first unit bubble for 120 frames
func _scenario_barracks() -> String:
	var f := fortress()
	if f.is_empty():
		return "no own fortress citadel"
	var at := beside_fortress(f)
	var id: int = world.create_object("GondorBarracks", game._local_index, at.x, at.y, 0.0)
	if id < 0:
		return "create_object GondorBarracks failed"
	await game._step(10)
	var unseen := check_seen(id, "the barracks")
	if unseen != "":
		return unseen
	var o := find_own(func(x): return int(x.id) == id)
	if o.is_empty() or not await select_object(o):
		return "the barracks could not be selected"
	hud.camera_set_height(330.0)
	await look(o.x, o.y)
	hud.inject_mouse_move(Vector2(60, 60))
	await game._step(30)
	var target := {}
	for b in radial().get("buttons", []):
		if str(b.command) == "UNIT_BUILD":
			target = b
			break
	if target.is_empty():
		return "no unit bubble over the barracks: " + JSON.stringify(radial())
	hud.inject_mouse_move(bubble_centre(target))
	await game._step(4)
	var ok := await wait_help_shown()
	await game._step(6)
	shot("barracks-help-early")
	await game._step(120)
	var h := help()
	print("HUD6 barracks (bubble %s): %s" % [str(target.name), JSON.stringify(h)])
	if OS.get_environment("HUD6_DUMP") != "":
		var keep := false
		for line in hud.dump_tree(40).split("\n"):
			if line.find("helpBox") >= 0:
				keep = true
			if keep:
				print("HUD6 TREE ", line)
	shot("barracks-help")
	if not ok:
		return "the help box did not show over bubble " + str(target.name)
	# the box keeps its text: drawn again in the last frames (draws grows) with at least the name line
	if int(h.get("text_ops", 0)) < 1 or int(h.get("draws", 0)) < 30:
		return "the help box drew no text (draws %d, text_ops %d)" % [int(h.get("draws", 0)), int(h.get("text_ops", 0))]
	return ""


# ---- lane OWNERFIX-3 -------------------------------------------------------------------------------------------------------------------------------------

func _enemy() -> Dictionary:
	for p in world.get_economy().players:
		if p.playable and p.name != game._local_name:
			return p
	return {}


# a barracks of the player's beside the fortress, its soldiers' bubble (ShowProductionCount = Yes) pressed three times: the bubble's count and the
# Palantir's say 3 (entries, not soldiers: a horde is one entry)
func _scenario_queue() -> String:
	var f := fortress()
	if f.is_empty():
		return "no own fortress citadel"
	var at := beside_fortress(f)
	var id: int = world.create_object("GondorBarracks", game._local_index, at.x, at.y, 0.0)
	if id < 0:
		return "create_object GondorBarracks failed"
	await game._step(10)
	var unseen := check_seen(id, "the barracks")
	if unseen != "":
		return unseen
	var o := find_own(func(x): return int(x.id) == id)
	if o.is_empty() or not await select_object(o):
		return "the barracks could not be selected"
	hud.camera_set_height(330.0)
	await look(o.x, o.y)
	hud.inject_mouse_move(Vector2(60, 60))
	await game._step(30)
	var target := {}
	for b in radial().get("buttons", []):
		if str(b.name) == "Command_ConstructGondorFighterHorde":
			target = b
	if target.is_empty():
		return "no soldiers' bubble over the barracks: " + JSON.stringify(radial())
	for i in 3:
		await click_pixel(bubble_centre(target))
		hud.inject_mouse_move(Vector2(60, 60))
		await game._step(6)
	await game._step(20)
	var r := radial()
	var texts: Array = r.get("texts", [])
	print("HUD6 queue: bubble texts %s, errors %s" % [JSON.stringify(texts), JSON.stringify(r.get("errors", []))])
	var palantir := -1
	for b in hud.get_command_buttons():
		if str(b.name) == "Command_ConstructGondorFighterHorde" and bool(b.in_palantir):
			palantir = int(b.production_count)
	print("HUD6 queue: Palantir production_count %d" % palantir)
	shot("queue")
	if texts.size() != 1 or str(texts[0].text) != "3" or int(texts[0].slot) != int(target.slot):
		return "the soldiers' bubble does not show 3: " + JSON.stringify(texts)
	if (r.get("errors", []) as Array).size() > 0:
		return "radial errors: " + str(r.errors)
	if palantir != -1 and palantir != 3:
		return "the Palantir's soldiers button counts %d" % palantir
	return ""


# the enemy's barracks and a hero of theirs beside the player's fortress, each selected by a click: the bar shows their command set (foreign_view), every
# button disabled (state 2, Restricted), no bubbles; a press sends nothing
func _scenario_enemy() -> String:
	var f := fortress()
	var e := _enemy()
	if f.is_empty() or e.is_empty():
		return "no own fortress or no enemy player"
	for t in ["GondorBarracks", "MordorGothmog"]:
		var at := beside_fortress(f, 0.0 if t == "GondorBarracks" else 160.0) # the open ground beside the fortress (the queue scenario's spot)
		var id: int = world.create_object(t, int(e.index), at.x, at.y, 0.0)
		if id < 0:
			return "create_object %s for the enemy failed" % t
		await game._step(10)
		var o := {}
		for x in world.get_player_objects(str(e.name)):
			if int(x.id) == id:
				o = x
		if o.is_empty():
			o = {"id": id, "x": at.x, "y": at.y, "template": t}
		if not await select_object(o):
			return "the enemy %s could not be selected" % t
		hud.camera_set_height(330.0)
		await look(o.x, o.y)
		hud.inject_mouse_move(Vector2(60, 60))
		await game._step(30)
		var bar: Dictionary = hud.get_state().get("control_bar", {})
		var buttons: Array = hud.get_command_buttons()
		var states := []
		for b in buttons:
			states.append("%s=%d" % [str(b.name), int(b.state)])
		print("HUD6 enemy %s: command_set %s foreign_view %s buttons %s bubbles %d" % [t, str(bar.get("command_set", "")), str(bar.get("foreign_view", false)), str(states), int(radial().get("count", 0))])
		shot("enemy-" + t.to_lower())
		if not bool(bar.get("foreign_view", false)) or str(bar.get("command_set", "")) == "":
			return "the enemy %s shows no command set" % t
		if buttons.is_empty():
			return "the enemy %s's set shows no buttons" % t
		for b in buttons:
			if int(b.state) != 2:
				return "the enemy %s's button %s is not disabled (state %d)" % [t, str(b.name), int(b.state)]
		if int(radial().get("count", 0)) != 0:
			return "bubbles over the enemy %s" % t
		world.destroy_object(id)
		await game._step(5)
	return ""


# lane IOS-27: the side bar's columns and the spell book under the HUD size; a held finger (IOS-21's hold_help with the pointer under it) shows the help
# lane IOS-29: the audit's lines; the rule's failures when it is on
func round_audit(where: String, on: bool) -> String:
	var bad := []
	for row in hud.hud_scale_audit():
		print("HUD6 round %s: L%d %s sx %.4f sy %.4f fix %.4f %.4f%s%s%s" % [where, int(row.level), str(row.path), float(row.sx), float(row.sy),
			float(row.fix_x), float(row.fix_y), " unit" if bool(row.unit) else "", " DISTORTED" if bool(row.distorted) else "",
			" (full-bleed backdrop)" if bool(row.full_bleed) else ""])
		if on and bool(row.squashes):
			bad.append(str(row.path))
	return "" if bad.is_empty() else "%s: drawn non-uniformly: %s" % [where, str(bad)]


func _scenario_round() -> String:
	var on := bool(hud.set_view_options({}).get("round_hud", false))
	print("HUD6 round: the rule is %s, window %s" % ["on" if on else "off (retail)", str(game.get_viewport().get_visible_rect().size)])
	var problems := []
	var b := find_own(func(o): return str(o.template).find("Worker") >= 0 or str(o.template).find("Porter") >= 0 or str(o.template).find("Builder") >= 0)
	if not b.is_empty() and await select_object(b):
		hud.inject_mouse_move(Vector2(60, 60))
		await game._step(60)
	var e := round_audit("builder", on)
	if not e.is_empty():
		problems.append(e)
	shot("round-builder")
	await game._press_escape()
	await game._step(45)
	e = round_audit("pause", on)
	if not e.is_empty():
		problems.append(e)
	shot("round-pause")
	await game._press_escape()
	await game._step(30)
	if hud.open_spell_store():
		await game._step(60)
		e = round_audit("store", on)
		if not e.is_empty():
			problems.append(e)
		shot("round-store")
		hud.close_spell_store()
		await game._step(60)
	return "" if problems.is_empty() else "; ".join(problems)


func _scenario_hudsize() -> String:
	if str(game._faction) != "FactionDwarves":
		return "hudsize needs --faction=FactionDwarves (its store button 1 is Rebuild)"
	var me: int = game._local_index
	world.debug_add_science_points(me, 5)
	print("HUD6 TEST HOOK: player %d given 5 power points" % me)
	if not hud.open_spell_store():
		return "the spell store did not open"
	await game._step(60)
	hud.spell_store_click(1)
	await game._step(4)
	hud.close_spell_store()
	await game._step(90)
	var book: Dictionary = hud.get_spellbook_state()
	var book_path := str(book.get("path", ""))
	var spell_slot := -1
	var slots: Array = book.get("slots", [])
	for i in slots.size():
		if str(slots[i]) != "_unused":
			spell_slot = i + 1
			break
	if spell_slot < 0:
		return "no power in the spell book: " + JSON.stringify(slots)
	var b := find_own(func(o): return str(o.template).find("Worker") >= 0 or str(o.template).find("Porter") >= 0 or str(o.template).find("Builder") >= 0)
	if b.is_empty():
		return "no own builder"
	if not await select_object(b):
		return "the builder could not be selected"
	hud.inject_mouse_move(Vector2(get_viewport_size().x * 0.5, 60))
	await game._step(60)
	var side: Dictionary = hud.get_hud6_state().get("side_bar", {})
	var n := int(side.get("count", 0))
	print("HUD6 hudsize: side bar %s, spell book slot %d" % [JSON.stringify(side), spell_slot])
	shot("hudsize-sidebar")
	if not bool(side.get("shown", false)) or n < 1:
		return "the side bar shows no framed buttons"
	# name -> the button's path: the power, then the first and last button of each column (column-major, at most six rows: AptPalantir::kSideBarMaxRows)
	var targets := {"spell": "%s.Spell%d" % [book_path, spell_slot]}
	var rows := n if n <= 6 else (n + 1) / 2
	for i in [0, rows - 1, rows, n - 1]:
		if i >= 0 and i < n:
			targets["side%d" % i] = "SideCommandBar.ButtonSet.Button%d.Button" % i
	hud.set_touch_help(true) # a phone's help: only while a finger is held (IOS-21; the touch layer turns it on at its first touch)
	for name in targets:
		var t: String = targets[name]
		var w: Dictionary = hud.find_button_window(t)
		if not w.get("found", false):
			return "no button at " + t
		var p := Vector2(w.x, w.y)
		var under: Dictionary = hud.touch_button_at(p)
		var snap: Dictionary = hud.nearest_button(p + Vector2(6, 6), 30.0)
		# the finger stays on the button: the pointer and the hold are set again each step (a desktop's own mouse over the window, and the touch layer
		# turning its help off for a mouse, would otherwise move or end them)
		var h := {}
		var since := 0
		for i in 70:
			hud.inject_mouse_move(p)
			hud.hold_help(true)
			hud.set_touch_help(true)
			await game._step(2)
			if h.is_empty() and bool(help().get("shown", false)) and int(help().get("draws", 0)) > 0:
				h = help()
			elif not h.is_empty():
				since += 1
				if since >= 5:
					break # the box's text draws a few frames after its frame
		var shown := not h.is_empty()
		print("HUD6 hudsize hold %s (%s) at %s: under %s, tap assist %s, help %s" % [name, t, str(p), JSON.stringify(under), JSON.stringify(snap), JSON.stringify(h)])
		shot("hudsize-hold-" + name)
		hud.hold_help(false)
		hud.inject_mouse_move(Vector2(get_viewport_size().x * 0.5, 60))
		await game._step(10)
		if str(under.get("kind", "")) != "movie":
			return "the finger at %s is on no HUD button (%s)" % [t, JSON.stringify(under)]
		if str(snap.get("target", "")) != str(under.get("target", "")):
			return "the tap assist 6 px off %s went to %s" % [t, JSON.stringify(snap)]
		if not shown or str(h.get("name", "")) == "":
			return "a held finger on %s showed no help: %s" % [t, JSON.stringify(h)]
		if bool(hud.get_spellbook_state().get("targeting", false)) or bool(hud.get_placement().get("placing", false)):
			return "holding %s pressed it" % t
	hud.set_touch_help(false)
	return ""


func get_viewport_size() -> Vector2:
	return Vector2(game.get_viewport().get_visible_rect().size)
