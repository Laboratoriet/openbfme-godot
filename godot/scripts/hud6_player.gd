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
##   modbalrog, modcp, modbuild, modlevel, moddarklords, modall  (lane IOS-30, each with its mod of tools/mod/make_ini_mods.py enabled the same way)
##            BalrogUnleashed (--faction=FactionWild): the Balrog recruited from the hero ring for 5,000 and alive after 120 s; DoubleArmy: the command
##            point base / cap / bonus doubled (--expect-retail-cp: the baseline); RapidBuild: the frames a porter and a barracks take (FactionMen,
##            compare a run without it); VeteranHeroes: a recruited hero comes at level 5 (--expect-retail-level: 1); DarkLordsForAll: the ring hero
##            recruited without the One Ring, level 10; modall: every mod on at once (FactionWild)
##   hudsize  (lane IOS-27, OpenBFME presentation; with --faction=FactionDwarves, --touch and an Options file's OpenBFMEHudScale) Rebuild bought in the
##            spell book (store button 1 of the Dwarves' set), a builder selected: the side bar as a block of one or two columns (hud6-hudsize-sidebar),
##            a held finger on the spell book's power and on the first and last button of each side bar column shows its help and presses nothing
##            (hud6-hudsize-hold-*); the tap assist takes a press 6 px off to the same button
##   round    (lane IOS-29, OpenBFME presentation; with --touch or an Options file's OpenBFMEHudScale above 100) the round-HUD audit (InGameHudNode
##            hud_scale_audit): a builder selected (hud6-round-builder), the pause menu (hud6-round-pause), the spell store (hud6-round-store); every
##            line "HUD6 round <where>: <path> sx sy fix", FAIL when the rule is on and any in-game movie unit or HUD draw has |sx / sy - 1| > 1 %
##            (a full-bleed backdrop, edge to edge on its stretched axis, is allowed: AptUniformHud::Entry::fullBleed)
##   menus    (lane IOS-32, with --touch) the full-screen in-game menus with the round-HUD audit: the pause menu, the players screen, the objectives,
##            the save menu over the game, the spell store (hud6-menus-<name>); in portrait they sit in the middle of the safe area
##   portrait (lane IOS-38, a PROTOTYPE comparison; with --touch, a portrait --res and --portrait-layout=default|a|b|c) the same five states for each
##            layout: an army with its builder (hud6-portrait-army), the builder alone with its side bar (-builder), the fortress with its radial
##            bubbles (-building), the spell book with three powers (-spellbook), the pause menu (-menu); prints "HUD6 portrait target <name>: w x h px
##            = w x h pt" (the hit target as the touch layer finds it, walked pixel by pixel from the button's centre), "HUD6 portrait map: ..." (the
##            share of the window that is battlefield, not HUD, and the ground it shows in world units) and the prototype's report; FAIL when a
##            prototype's HUD leaves the window or covers the toolbar strip
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
	var r := await recruit_from_ring(f, "MordorSauron", "Sauron", "modhero")
	return str(r.get("error", ""))


# lane IOS-28 / IOS-30: the hero `template` recruited by the player's hand: the fortress selected, its heroes bubble pressed, the hero's REVIVE bubble
# (its portrait's image names `image_word`) hovered (its help) and clicked with its cost given; the fortress makes him (fast forward) and he is selected.
# Shots <prefix>-ring, -help, -recruiting, -made. {"made": the object, "frames": queue to made} or {"error": why}
func recruit_from_ring(f: Dictionary, template: String, image_word: String, prefix: String) -> Dictionary:
	var heroes: Array = world.get_heroes(game._local_index, int(f.id))
	var record := {}
	for h in heroes:
		if str(h.template) == template:
			record = h
	print("HUD6 %s: the fortress's heroes %s" % [prefix, JSON.stringify(heroes)])
	if record.is_empty():
		return {"error": "%s is not among the fortress's heroes (is the mod enabled and mounted?)" % template}
	world.give_money(game._local_index, int(record.cost))
	if hud.get_selection().has(int(f.id)):
		# a click on the selected fortress opens no ring: a click on open ground drops the selection first
		await click_pixel(Vector2(1250, 120))
		await game._step(10)
	if not await select_object(f):
		return {"error": "the fortress could not be selected"}
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
	print("HUD6 %s ring: %s" % [prefix, JSON.stringify(ring)])
	shot(prefix + "-ring")
	# the hero's REVIVE bubble: a ring hero's is the ring hero slot; another hero's is a generic slot whose portrait names him, the shortest such
	# image when two do (Sauron's HISauron, not the Mouth of Sauron's)
	var bubble: Dictionary = {}
	var ring_hero := template.ends_with("_RingHero")
	for b in ring.get("buttons", []):
		if str(b.command) != "REVIVE" or str(b.get("image", "")).find(image_word) < 0 or (str(b.name) == "Command_RingHeroReviveSlot") != ring_hero:
			continue
		if bubble.is_empty() or str(b.image).length() < str(bubble.image).length():
			bubble = b
	if bubble.is_empty():
		return {"error": "no %s bubble in the hero ring: %s" % [image_word, JSON.stringify(ring.get("buttons", []))]}
	hud.inject_mouse_move(bubble_centre(bubble))
	await wait_help_shown()
	await game._step(20)
	print("HUD6 %s help: %s" % [prefix, JSON.stringify(help())])
	shot(prefix + "-help")
	await click_pixel(bubble_centre(bubble))
	var queued_at: int = world.get_frame()
	hud.inject_mouse_move(Vector2(60, 60))
	await game._step(20)
	var queued := false
	for h in world.get_heroes(game._local_index, int(f.id)):
		if str(h.template) == template:
			queued = queued or bool(h.in_production)
	if not queued:
		return {"error": "the %s bubble was clicked but he is not in production" % image_word}
	shot(prefix + "-recruiting")
	world.set_time_scale(8.0)
	var made := {}
	for i in 400:
		await game._step(30)
		made = find_own(func(o): return str(o.template) == template)
		if not made.is_empty():
			break
	var frames: int = world.get_frame() - queued_at
	world.set_time_scale(1.0)
	if made.is_empty():
		return {"error": "%s was not made" % template}
	await look(made.x, made.y)
	await select_object(made)
	hud.inject_mouse_move(Vector2(60, 60))
	await game._step(40)
	shot(prefix + "-made")
	print("HUD6 %s made: %s after about %d frames" % [prefix, JSON.stringify(made), frames])
	return {"made": made, "frames": frames, "record": record}


# ---- lane IOS-30: the INI mods of tools/mod/make_ini_mods.py (each run with an Options file enabling the mod: OpenBFMEMods) ----------------------------

func my_economy() -> Dictionary:
	for p in world.get_economy().get("players", []):
		if int(p.index) == game._local_index:
			return p
	return {}


func level_of(id: int) -> int:
	return int(world.get_ability_state(id).get("level", 0))


# --faction=FactionWild, BalrogUnleashed: the Balrog (WildBalrog) in the fortress's hero ring for 5,000, recruited, still standing after the
# spell book Balrog's 90 s (BALROG_LIFETIME: the mod removes his LifetimeUpdate), at the summoned Balrog's level 10
func _scenario_modbalrog() -> String:
	var f := fortress()
	if f.is_empty():
		return "no own fortress"
	var r := await recruit_from_ring(f, "WildBalrog", "Balrog", "modbalrog")
	if r.has("error"):
		return str(r.error)
	var id := int(r.made.id)
	var born: int = world.get_frame()
	world.set_time_scale(8.0)
	while world.get_frame() < born + 5 * 120 and world.get_object(id).get("ok", false):
		await game._step(30)
	world.set_time_scale(1.0)
	var alive: bool = world.get_object(id).get("ok", false) and not bool(world.get_object(id).get("destroyed", false))
	print("HUD6 modbalrog: %d frames (%.0f s) after he came, alive %s, level %d" % [world.get_frame() - born, (world.get_frame() - born) / 5.0, str(alive), level_of(id)])
	if not alive:
		return "the Balrog was gone before 120 s (the spell book Balrog's 90 s lifetime?)"
	if int(r.record.cost) != 5000:
		return "the Balrog cost %d, not 5000" % int(r.record.cost)
	# the spell book Balrog's own ExperienceLevel (rank 10), copied for WildBalrog
	return "" if level_of(id) == 10 else "the Balrog is level %d, not the summoned Balrog's 10" % level_of(id)


# DoubleArmy: the command point pool of a two-player skirmish (GameData {Good|Evil}CommandPointsMP2, retail 100 / 1000; the fortress's bonus
# GENERIC_FORTRESS_COMMAND_POINT_BONUS, retail 100) and the HUD's readout. --expect-retail-cp runs it as the baseline (no mod)
func _scenario_modcp() -> String:
	var f := fortress()
	if not f.is_empty():
		await select_object(f)
		hud.inject_mouse_move(Vector2(60, 60))
		await game._step(30)
	var p := my_economy()
	var text := str(hud.get_state().get("control_bar", {}).get("command_points"))
	print("HUD6 modcp: base %d cap %d bonus %d limit %d used %d (the HUD: %s)" % [int(p.cp_base), int(p.cp_cap), int(p.cp_bonus), int(p.cp_limit), int(p.cp_used), text])
	shot("modcp")
	var k := 1 if OS.get_cmdline_user_args().has("--expect-retail-cp") else 2
	if int(p.cp_base) != 100 * k or int(p.cp_cap) != 1000 * k:
		return "base %d cap %d, expected %d / %d" % [int(p.cp_base), int(p.cp_cap), 100 * k, 1000 * k]
	if int(p.cp_bonus) % (100 * k) != 0:
		return "the bonus %d is not a whole number of fortress bonuses (%d)" % [int(p.cp_bonus), 100 * k]
	if int(p.cp_limit) != mini(int(p.cp_cap), int(p.cp_base) + int(p.cp_bonus)):
		return "the limit %d is not min(cap, base + bonus)" % int(p.cp_limit)
	return ""


# RapidBuild: logic frames from the order to the result for a unit (the fortress's porter) and a structure (a barracks on a free castle plot) of
# FactionMen; run once with the mod and once without and compare (retail BuildTime 30 s each: 150 frames)
func _scenario_modbuild() -> String:
	var f := fortress()
	if f.is_empty():
		return "no own fortress"
	world.give_money(game._local_index, 5000)
	var before := {}
	for o in own():
		before[int(o.id)] = true
	world.queue_unit(game._local_index, int(f.id), "MenPorter")
	var t0: int = world.get_frame()
	world.set_time_scale(4.0)
	var unit := {}
	while unit.is_empty() and world.get_frame() < t0 + 1000:
		await game._step(1)
		unit = find_own(func(o): return str(o.template) == "MenPorter" and not before.has(int(o.id)))
	var unit_frames: int = world.get_frame() - t0
	var site: Dictionary = world.build2_construct_on_plot(game._local_name, "GondorBarracks")
	if not bool(site.get("ok", false)):
		world.set_time_scale(1.0)
		return "no barracks site: " + str(site.get("error", ""))
	var t1: int = world.get_frame()
	while bool(world.get_object(int(site.id)).get("under_construction", true)) and world.get_frame() < t1 + 1500:
		await game._step(1)
	var structure_frames: int = world.get_frame() - t1
	world.set_time_scale(1.0)
	var b := find_own(func(o): return int(o.id) == int(site.id))
	if not b.is_empty():
		await select_object(b)
		hud.inject_mouse_move(Vector2(60, 60))
		await game._step(20)
	shot("modbuild")
	print("HUD6 modbuild: MenPorter %d frames, GondorBarracks %d frames (retail BuildTime 30 s = 150 frames each)" % [unit_frames, structure_frames])
	if unit.is_empty():
		return "no porter came within 1000 frames"
	if bool(world.get_object(int(site.id)).get("under_construction", true)):
		return "the barracks was not finished within 1500 frames"
	return ""


# VeteranHeroes: the fortress's cheapest hero (not Create-a-Hero, not the ring hero) recruited by hand: he comes at level 5
func _scenario_modlevel() -> String:
	var f := fortress()
	if f.is_empty():
		return "no own fortress"
	var pick := {}
	for h in world.get_heroes(game._local_index, int(f.id)):
		var tn := str(h.template)
		if tn.find("_RingHero") < 0 and tn.to_lower().find("createahero") < 0 and (pick.is_empty() or int(h.cost) < int(pick.cost)):
			pick = h
	if pick.is_empty():
		return "no hero to recruit"
	var t: String = str(pick.template)
	# the bubble's portrait (the template's ButtonImage, HI<name>) carries the name without its faction prefix
	var word := t.trim_prefix("Rohan").trim_prefix("Gondor").trim_prefix("Elven").trim_prefix("Dwarven").trim_prefix("Isengard").trim_prefix("Mordor").trim_prefix("Wild").trim_prefix("Angmar")
	var r := await recruit_from_ring(f, t, word.substr(0, 4), "modlevel")
	if r.has("error"):
		return str(r.error)
	var level := level_of(int(r.made.id))
	print("HUD6 modlevel: %s level %d" % [t, level])
	var want := 1 if OS.get_cmdline_user_args().has("--expect-retail-level") else 5
	return "" if level == want else "%s came at level %d, not %d" % [t, level, want]


# DarkLordsForAll: the faction's ring hero (Sauron for the evil factions, Galadriel for the good) in the ring hero slot without the One Ring,
# recruited by hand for 10,000; he or she comes at level 10 (the ring hero's own ExperienceLevelCreate)
func _scenario_moddarklords() -> String:
	var f := fortress()
	if f.is_empty():
		return "no own fortress"
	var ring := ""
	for h in world.get_heroes(game._local_index, int(f.id)):
		if str(h.template).ends_with("_RingHero"):
			ring = str(h.template)
	if ring == "":
		return "no ring hero among the fortress's heroes (is the mod enabled?)"
	var r := await recruit_from_ring(f, ring, "Sauron" if ring.begins_with("Mordor") else "Galadriel", "moddarklords")
	if r.has("error"):
		return str(r.error)
	var level := level_of(int(r.made.id))
	print("HUD6 moddarklords: %s level %d" % [ring, level])
	return "" if level == 10 else "%s came at level %d" % [ring, level]


# all six mods at once (Options.ini OpenBFMEMods in the order they were turned on), --faction=FactionWild: the hero ring lists the Balrog and
# the ring hero, the command points are doubled, a hero comes at level 5 (the porter and barracks timing is modbuild's, FactionMen)
func _scenario_modall() -> String:
	var f := fortress()
	if f.is_empty():
		return "no own fortress"
	var names := []
	for h in world.get_heroes(game._local_index, int(f.id)):
		names.append(str(h.template))
	print("HUD6 modall: heroes %s" % str(names))
	if not names.has("WildBalrog") or not names.has("MordorSauron_RingHero"):
		return "the hero list lacks the Balrog or the ring hero: %s" % str(names)
	var lv := await _scenario_modlevel()
	if lv != "":
		return "veteran hero: " + lv
	var cp := await _scenario_modcp()
	if cp != "":
		return "command points: " + cp
	var r := await recruit_from_ring(f, "WildBalrog", "Balrog", "modall")
	return str(r.get("error", ""))


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


## lane IOS-32: the full-screen in-game menus (hud6-menus-<name>): the pause menu, the players screen (the Palantir flag in a skirmish), the
## objectives screen, the save menu over the game and the spell store, each with the round-HUD audit; in portrait with the rule on, the menus sit in
## the middle of the safe area (AptUniformHud's menu levels)
func _scenario_menus() -> String:
	var on := bool(hud.set_view_options({}).get("round_hud", false))
	print("HUD6 menus: the rule is %s, window %s" % ["on" if on else "off (retail)", str(game.get_viewport().get_visible_rect().size)])
	var problems := []
	var check := func(where: String) -> void:
		print("HUD6 menus %s: the shell's screens %s" % [where, str(game._shell.shell_stack())])
		var e := round_audit(where, on)
		if not e.is_empty():
			problems.append(e)
		shot("menus-" + where)
	await game._press_escape()
	await game._step(45)
	check.call("pause")
	await game._press_escape()
	await game._step(30)
	game._palantir_objectives() # a skirmish: the players screen (PlayerTribute.apt)
	await game._step(45)
	check.call("players")
	game._close_tribute()
	await game._step(30)
	game._open_objectives(0)
	await game._step(45)
	check.call("objectives")
	game._close_objectives()
	await game._step(30)
	game._save_flow.open_menu(3, 0xB, true)
	await game._step(45)
	check.call("save")
	game._shell.shell_pop()
	await game._step(30)
	if hud.open_spell_store():
		await game._step(60)
		check.call("store")
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


# ---- lane IOS-38: the portrait layout prototypes, measured -------------------------------------------------------------------------------------------

var _portrait_px_per_pt := 1.5


## the hit target of the HUD button at window pixel `c` as the touch layer finds it: from `c` pixel by pixel left, right, up and down while
## touch_button_at still names the same button; {} when nothing is under `c`
func hit_target(c: Vector2) -> Dictionary:
	var under: Dictionary = hud.touch_button_at(c)
	var target := str(under.get("target", ""))
	if target.is_empty():
		return {}
	var reach := {}
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var n := 0
		while n < 400 and str(hud.touch_button_at(c + dir * float(n + 1)).get("target", "")) == target:
			n += 1
		reach[dir] = n
	var w := float(reach[Vector2.LEFT] + reach[Vector2.RIGHT] + 1)
	var h := float(reach[Vector2.UP] + reach[Vector2.DOWN] + 1)
	return {"target": target, "w": w, "h": h, "x0": c.x - reach[Vector2.LEFT], "y0": c.y - reach[Vector2.UP]}


func report_target(name: String, path: String, sizes: Dictionary) -> void:
	var w: Dictionary = hud.find_button_window(path)
	if not w.get("found", false):
		print("HUD6 portrait target %s: no button at %s" % [name, path])
		return
	var t := hit_target(Vector2(w.x, w.y))
	if t.is_empty():
		print("HUD6 portrait target %s: nothing under its centre %s" % [name, str(Vector2(w.x, w.y))])
		return
	var pt := minf(t.w, t.h) / _portrait_px_per_pt
	sizes[name] = pt
	print("HUD6 portrait target %s: %d x %d px = %.0f x %.0f pt at (%d, %d)%s" % [name, int(t.w), int(t.h), t.w / _portrait_px_per_pt,
		t.h / _portrait_px_per_pt, int(w.x), int(w.y), "" if pt >= 44.0 else " (under 44 pt)"])


## the battlefield's share of the window (a 24 px grid: a point is battlefield when no HUD takes a finger there) and the ground the whole window shows
## (the terrain under the window's corners and edge midpoints: a polygon's area in world units squared)
func report_map(where: String) -> Dictionary:
	var size := get_viewport_size()
	var free := 0
	var total := 0
	var step := 24.0
	var y := step * 0.5
	while y < size.y:
		var x := step * 0.5
		while x < size.x:
			total += 1
			if bool(hud.touch_placement_at(Vector2(x, y)).get("world", false)):
				free += 1
			x += step
		y += step
	var poly := PackedVector2Array()
	for p in [Vector2(0, 0), Vector2(size.x * 0.5, 0), Vector2(size.x - 1, 0), Vector2(size.x - 1, size.y * 0.5), Vector2(size.x - 1, size.y - 1),
			Vector2(size.x * 0.5, size.y - 1), Vector2(0, size.y - 1), Vector2(0, size.y * 0.5)]:
		var g: Vector2 = hud.pixel_to_world(p)
		if g.x > -1e8:
			poly.append(g)
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	area = absf(area) * 0.5
	var top_w: float = (hud.pixel_to_world(Vector2(size.x - 1, size.y * 0.25)) - hud.pixel_to_world(Vector2(0, size.y * 0.25))).length()
	var bottom_w: float = (hud.pixel_to_world(Vector2(size.x - 1, size.y * 0.75)) - hud.pixel_to_world(Vector2(0, size.y * 0.75))).length()
	var depth: float = (hud.pixel_to_world(Vector2(size.x * 0.5, size.y * 0.1)) - hud.pixel_to_world(Vector2(size.x * 0.5, size.y * 0.9))).length()
	var cam: Dictionary = hud.get_camera()
	var r := {"free": float(free) / float(total), "area": area, "corners": poly.size(), "width_top": top_w, "width_bottom": bottom_w, "depth": depth,
		"hfov": rad_to_deg(float(cam.get("horizontal_fov", 0.0))), "vfov": rad_to_deg(float(cam.get("vertical_fov", 0.0))),
		"height": float(cam.get("height_above_ground", 0.0))}
	print("HUD6 portrait map %s: battlefield %.0f %% of the window; ground shown %.0f world units^2 (%d of 8 edge points on the terrain), width %.0f at a quarter of the height, %.0f at three quarters, depth %.0f from 10 %% to 90 %%; camera %.1f x %.1f degrees at %.0f above the ground" % [
		where, r.free * 100.0, r.area, r.corners, r.width_top, r.width_bottom, r.depth, r.hfov, r.vfov, r.height])
	return r


func _scenario_portrait() -> String:
	var view: Dictionary = hud.set_view_options({})
	_portrait_px_per_pt = float(view.get("point_px", 1.5))
	var layout := str(view.get("portrait_layout", "default"))
	var size := get_viewport_size()
	print("HUD6 portrait: layout %s, window %s, %.2f px per point, round HUD %s" % [layout, str(size), _portrait_px_per_pt, str(view.get("round_hud", false))])
	if size.x >= size.y:
		return "portrait needs a portrait window (--res=939x1335)"
	var problems := []
	var me: int = game._local_index
	var f := fortress()
	if f.is_empty():
		return "no own fortress citadel"
	# three powers in the spell book (its vine grows with each)
	world.debug_add_science_points(me, 12)
	print("HUD6 TEST HOOK: player %d given 12 power points" % me)
	if hud.open_spell_store():
		await game._step(60)
		for slot in [1, 2, 3]:
			hud.spell_store_click(slot)
			await game._step(6)
		hud.close_spell_store()
		await game._step(90)
	# an army beside the fortress
	var at := beside_fortress(f, 120.0)
	var army := []
	for i in 3:
		var id: int = world.create_object("GondorFighterHorde", me, at.x + 80.0 * i, at.y, 0.0)
		if id >= 0:
			army.append(id)
	print("HUD6 TEST HOOK: an army of %d GondorFighterHorde made beside the fortress" % army.size())
	await game._step(30)
	var b := find_own(func(o): return str(o.template).find("Worker") >= 0 or str(o.template).find("Porter") >= 0 or str(o.template).find("Builder") >= 0)
	if b.is_empty():
		return "no own builder"
	var sizes := {}
	var maps := {}
	var report := func(where: String) -> void:
		var st: Dictionary = hud.get_hud6_state()
		print("HUD6 portrait report %s: %s" % [where, JSON.stringify(st.get("portrait", {}))])
	# 1. the army with its builder: the arc's commands, the map
	await look(at.x + 80.0, at.y)
	var ids := PackedInt64Array(army)
	ids.append(int(b.id))
	hud.select_objects(ids)
	hud.inject_mouse_move(Vector2(size.x * 0.5, size.y * 0.3))
	await game._step(45)
	report.call("army")
	for i in 6:
		report_target("arc%d" % i, "CommandButtons.%d" % i, sizes)
	report_target("options", "PalantirButtons.Buttons.Options", sizes)
	report_target("powers", "PalantirButtons.Buttons.PlayerMagic", sizes)
	maps["army"] = report_map("army")
	shot("portrait-army")
	# 2. the builder alone: the side bar
	hud.select_objects(PackedInt64Array([int(b.id)]))
	await game._step(60)
	var side: Dictionary = hud.get_hud6_state().get("side_bar", {})
	var n := int(side.get("count", 0))
	print("HUD6 portrait builder: side bar %d buttons, shown %s" % [n, str(side.get("shown", false))])
	for i in [0, n - 1]:
		if i >= 0:
			report_target("side%d" % i, "SideCommandBar.ButtonSet.Button%d.Button" % i, sizes)
	var book: Dictionary = hud.get_spellbook_state()
	var slots: Array = book.get("slots", [])
	for i in slots.size():
		if str(slots[i]) != "_unused":
			report_target("spell%d" % (i + 1), "%s.Spell%d" % [str(book.get("path", "")), i + 1], sizes)
	maps["builder"] = report_map("builder")
	shot("portrait-builder")
	# 3. the fortress: its radial bubbles
	if await select_object(f):
		await game._step(30)
		var bubbles: Array = radial().get("buttons", [])
		if not bubbles.is_empty():
			var bb: Dictionary = bubbles[0]
			var r: Rect2 = bb.rect
			print("HUD6 portrait target bubble: %d x %d px = %.0f x %.0f pt" % [int(r.size.x), int(r.size.y), r.size.x / _portrait_px_per_pt, r.size.y / _portrait_px_per_pt])
			sizes["bubble"] = minf(r.size.x, r.size.y) / _portrait_px_per_pt
	maps["building"] = report_map("building")
	shot("portrait-building")
	# 4. the spell book: a power held (its help box) with nothing selected
	hud.select_objects(PackedInt64Array())
	await game._step(30)
	book = hud.get_spellbook_state()
	var power := ""
	slots = book.get("slots", [])
	for i in slots.size():
		if str(slots[i]) != "_unused":
			power = "%s.Spell%d" % [str(book.get("path", "")), i + 1]
	if not power.is_empty():
		var w: Dictionary = hud.find_button_window(power)
		if w.get("found", false):
			hud.set_touch_help(true)
			for i in 40:
				hud.inject_mouse_move(Vector2(w.x, w.y))
				hud.hold_help(true)
				hud.set_touch_help(true)
				await game._step(2)
	shot("portrait-spellbook")
	hud.hold_help(false)
	hud.set_touch_help(false)
	hud.inject_mouse_move(Vector2(size.x * 0.5, size.y * 0.3))
	await game._step(10)
	# 5. the pause menu
	await game._press_escape()
	await game._step(45)
	shot("portrait-menu")
	await game._press_escape()
	await game._step(30)
	# the prototype's own checks: nothing of the HUD in the toolbar strip
	var st: Dictionary = hud.get_hud6_state().get("portrait", {})
	if layout != "default":
		if st.is_empty():
			problems.append("the prototype %s reported nothing" % layout)
		elif float(st.get("hud_top", 0.0)) < float(st.get("strip_bottom", 0.0)) - 0.5:
			problems.append("the HUD reaches into the toolbar strip (top %.1f, strip ends %.1f)" % [float(st.hud_top), float(st.strip_bottom)])
	var small := []
	for k in sizes:
		if float(sizes[k]) < 44.0:
			small.append("%s %.0f pt" % [k, float(sizes[k])])
	print("HUD6 portrait summary %s: targets under 44 pt: %s; battlefield %.0f %% (army), ground %.0f units^2" % [layout,
		"none" if small.is_empty() else ", ".join(small), float(maps.army.free) * 100.0, float(maps.army.area)])
	return "" if problems.is_empty() else "; ".join(problems)
