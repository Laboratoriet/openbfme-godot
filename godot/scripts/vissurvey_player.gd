## Lane VIS-1: the visual survey of every buildable unit, hero and building, in the real client (game.gd --auto --vissurvey=<faction>[,...]).
## Each object of the catalog (tools/visual/survey_catalog.py: the factions' builders, structures, trained units and heroes, read from the
## player's own game files) is made by a logged test hook for the local player on a flat spot near the map's middle, selected (its ring and
## health bar), and filmed from the player's camera, the camera fixed per phase:
##   units / heroes  idle, move, attack (an enemy farm is the target), a hero's first powers, die; one copy on the steepest slope nearby;
##   buildings       finished, damaged, badly damaged, destroyed (made finished: the construction stage is not filmed).
## Every phase is a row of cells in one contact sheet per object and configuration: <vis-out>/<faction>/<object>-<config>.jpg. The probe (one
## JSON per object in <vis-data>/<config>/<faction>/) holds, for every cell: the drawable's height above the terrain, each draw entry's model,
## clip and frame, the lowest posed pivot and the feet pivots (GameWorld.get_render_debug), the selection decal and health bar the HUD lists, the
## icon images (veterancy), the declared shadow bits and whether the entry casts a shadow map; for the move phase the feet every render frame
## (the slide measure); and raw PNG crops for the pixel checks (tools/visual/survey_flags.py): three frames of the paused game (flicker), the
## same frame without shadows (the shadow's pixels), and an enemy-owned twin beside the object (house colour).
## Options (after `--`):
##   --vis-catalog=<json>   the catalog (required); --vis-out=<dir> the contact sheets; --vis-data=<dir> the probes and raw crops
##   --vis-config=<label>   the file label of this run (default: the renderer and the shadow detail, e.g. "fwd-def")
##   --vis-shadow=low       ShadowLOD Low for the run (blob shadows, no maps); default: the detail level's own
##   --vis-mode=lite        fewer cells (idle and move, finished and damaged) for the second renderer / detail
##   --vis-only=<a,b>       only these templates; --vis-limit=<n> at most n objects per faction and kind; --vis-zoom-out=<f> a wider frame
## Prints "VISSURVEY BEGIN <faction> <template>" / "VISSURVEY END ..." around each object (tools/visual/survey_flags.py splits the log by them).
## Changes nothing in the game's code paths: everything goes through the GameWorld / InGameHud test hooks that other players use.
extends "res://scripts/scenario_player.gd"

const FACTIONS := {"men": "FactionMen", "elves": "FactionElves", "dwarves": "FactionDwarves", "isengard": "FactionIsengard",
	"mordor": "FactionMordor", "wild": "FactionWild", "angmar": "FactionAngmar"}
const TARGET := "GondorFarm"

var game: Node
var hud: Node
var world: Node
var _catalog := {}
var _out := ""
var _data := ""
var _config := ""
var _mode := "full"
var _shadow := "default"
var _only: PackedStringArray = []
var _limit := 0
var _zoom_out := 1.0         # --vis-zoom-out=<f>: the object fills 1/f of the usual share of the window (more room around it)
var _me := -1
var _enemy := -1
var _enemy_name := ""
var _enemy_keep := ""
var _flat := Vector2()
var _flat0 := Vector2()
var _slope := Vector2()
var _created: Array = []
var _cell := 200
var _rows: Array = []        # the contact sheet: rows of cell Images
var _probe := {}             # the object's probe record
var _focus := -1
var _subject := -1
var _bg: Image = null        # the frame before the object was made (same camera)
var _crop := Rect2i()
var _shadow_lod := 0
var _samples: Array = []     # move phase: render frame samples
var _sampling := false
var _done := 0


func _run(p_game: Node, scenarios: PackedStringArray) -> void:
	game = p_game
	hud = game._hud
	world = game._world
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--vis-catalog="):
			var f := FileAccess.open(arg.substr(14), FileAccess.READ)
			if f != null:
				_catalog = JSON.parse_string(f.get_as_text())
		elif arg.begins_with("--vis-out="):
			_out = arg.substr(10)
		elif arg.begins_with("--vis-data="):
			_data = arg.substr(11)
		elif arg.begins_with("--vis-config="):
			_config = arg.substr(13)
		elif arg.begins_with("--vis-mode="):
			_mode = arg.substr(11)
		elif arg.begins_with("--vis-shadow="):
			_shadow = arg.substr(13)
		elif arg.begins_with("--vis-only="):
			_only = arg.substr(11).split(",", false)
		elif arg.begins_with("--vis-zoom-out="):
			_zoom_out = maxf(float(arg.substr(15)), 0.25)
		elif arg.begins_with("--vis-limit="):
			_limit = int(arg.substr(12))
	if _config.is_empty():
		var method := RenderingServer.get_current_rendering_method()
		_config = ("mob" if method == "mobile" else "fwd" if method == "forward_plus" else method) + "-" + ("low" if _shadow == "low" else "def")
	if _mode == "lite":
		_cell = 160
	await _run_scenarios(scenarios)


# one scenario per faction (the scene is set up by the first)
func _scenario_men() -> String:
	return await _survey_faction("men")


func _scenario_elves() -> String:
	return await _survey_faction("elves")


func _scenario_dwarves() -> String:
	return await _survey_faction("dwarves")


func _scenario_isengard() -> String:
	return await _survey_faction("isengard")


func _scenario_mordor() -> String:
	return await _survey_faction("mordor")


func _scenario_wild() -> String:
	return await _survey_faction("wild")


func _scenario_angmar() -> String:
	return await _survey_faction("angmar")


# ---- setup --------------------------------------------------------------------------------------------------------------------------------------

var _ready_scene := false


func _setup() -> void:
	if _ready_scene:
		return
	_ready_scene = true
	for p in world.get_economy().get("players", []):
		if p.name == game._local_name:
			_me = int(p.index)
		elif p.playable and _enemy < 0:
			_enemy = int(p.index)
			_enemy_name = String(p.name)
	world.debug_set_auto_acquire(false)
	for o in world.get_player_objects(_enemy_name):
		if o.get("commandcenter", false):
			_enemy_keep = String(o.get("template", ""))
	_quiet_enemy()
	# the map's trees and props (the largest instancer): nothing stands between the camera and the object (anim_survey_viewer does the same)
	var best: Node = null
	var most := -1
	for c in world.get_children():
		if c.get_class() == "W3DInstancer" and int(c.get_instance_count()) > most:
			most = int(c.get_instance_count())
			best = c
	if best != null and most > 400:
		best.visible = false
	world.set_shroud_drawn(false)
	var detail: Dictionary = game._shell.get_detail_state() if game._shell != null else {}
	_shadow_lod = int(detail.get("shadow_lod", 0)) if detail.get("ok", false) else 0
	if _shadow == "low":
		_shadow_lod = 1
		game.set_shadow_lod(1)
		hud.set_shadow_decals(true, false)
	hud.set_view_options({"health_bar_mode": "retail"})
	game.get_tree().process_frame.connect(_process_sample)
	var before := _new_asset_errors() # the map's own lines are not an object's
	print("VISSURVEY instancer lines before the survey: %d" % before.size())
	_find_spots()
	_flat0 = _flat
	print("VISSURVEY SETUP config %s mode %s renderer %s shadow_lod %d flat (%.0f, %.0f) slope (%.0f, %.0f) detail %s window %s" % [_config, _mode,
		RenderingServer.get_current_rendering_method(), _shadow_lod, _flat.x, _flat.y, _slope.x, _slope.y, JSON.stringify(detail),
		str(game.get_viewport().get_visible_rect().size)])
	await game._step(10)


# the enemy keeps only its fortress (no army walks into the survey); it is checked again before every object
func _quiet_enemy() -> void:
	if _enemy_name.is_empty():
		return
	world.debug_kill_player_objects(_enemy_name, _enemy_keep)


func _base_of(player: String) -> Vector2:
	for o in world.get_player_objects(player):
		if o.get("commandcenter", false):
			return Vector2(o.x, o.y)
	return Vector2()


# the flattest open patch near the middle of the two bases, and the steepest one near it (the slope copy)
func _find_spots() -> void:
	var a := _base_of(game._local_name)
	var b := _base_of(_enemy_name)
	var mid := (a + b) * 0.5 if b != Vector2() else a + Vector2(900, 0)
	var objs: Array = []
	for id in world.get_object_ids():
		var o: Dictionary = world.get_object(id)
		if o.get("ok", false) and o.get("structure", false):
			objs.append(Vector2(o.x, o.y))
	var best := INF
	var steep := -1.0
	for i in range(-12, 13):
		for j in range(-12, 13):
			var p := mid + Vector2(i, j) * 110.0
			var near := false
			for q in objs:
				if p.distance_to(q) < 450.0:
					near = true
					break
			if near:
				continue
			var lo := INF
			var hi := -INF
			for dx in [-200.0, 0.0, 200.0]:
				for dy in [-200.0, 0.0, 200.0]:
					var h: float = world.get_ground_height(p.x + dx, p.y + dy)
					lo = minf(lo, h)
					hi = maxf(hi, h)
			var spread := hi - lo + p.distance_to(mid) * 0.002
			if spread < best:
				best = spread
				_flat = p
			var grad := absf(world.get_ground_height(p.x + 60.0, p.y) - world.get_ground_height(p.x - 60.0, p.y)) \
				+ absf(world.get_ground_height(p.x, p.y + 60.0) - world.get_ground_height(p.x, p.y - 60.0))
			# a walkable slope (about 5 to 10 degrees), not a cliff in its own shadow nor a river bank (the water is not known here: the ground
			# stays within 30 of the flat spot's)
			var h0: float = world.get_ground_height(p.x, p.y)
			if grad > steep and grad < 22.0 and p.distance_to(mid) < 900.0 and absf(h0 - world.get_ground_height(mid.x, mid.y)) < 30.0:
				steep = grad
				_slope = p
	if steep < 0.0:
		_slope = _flat + Vector2(400.0, 0.0)
	print("VISSURVEY spots: flat spread %.1f, slope gradient %.1f per 120" % [best, steep])


# ---- the camera and the frame -----------------------------------------------------------------------------------------------------------------

func _look(p: Vector2, height: float) -> void:
	for i in 4:
		hud.camera_look_at(p)
		hud.camera_set_height(height)
		await game._step(8)
	hud.camera_look_at(p)
	await game._step(4)


func _frame() -> Image:
	var img: Image = game.get_viewport().get_texture().get_image()
	if img != null and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	return img


func _logic(n: int) -> void:
	var until: int = world.get_frame() + n
	var guard := 0
	while world.get_frame() < until and guard < 600:
		await game.get_tree().process_frame
		guard += 1


func _vp_size() -> Vector2:
	return game.get_viewport().get_visible_rect().size


func _sage_to_godot(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y)


# the screen rectangle of the objects' posed pivots (every entry, every horde member) with a margin; empty when none is posed
func _screen_box(ids: Array) -> Rect2:
	var cam: Camera3D = game.get_viewport().get_camera_3d()
	if cam == null:
		return Rect2()
	var have := false
	var box := Rect2()
	for id in ids:
		var dbg: Dictionary = world.get_render_debug(int(id))
		if not dbg.get("ok", false):
			continue
		var pts: Array = [Vector3(dbg.x, dbg.y, dbg.ground)]
		for e in dbg.get("entries", []):
			if e.has("lo"):
				var lo: Vector3 = e.lo
				var hi: Vector3 = e.hi
				for cx in [lo.x, hi.x]:
					for cy in [lo.y, hi.y]:
						for cz in [lo.z, hi.z]:
							pts.append(Vector3(cx, cy, cz))
		for p in pts:
			var g := _sage_to_godot(p)
			if cam.is_position_behind(g):
				continue
			var s := cam.unproject_position(g)
			if not have:
				box = Rect2(s, Vector2.ZERO)
				have = true
			else:
				box = box.expand(s)
	return box if have else Rect2()


# the box of what changed against the frame before the object was made (a quarter resolution diff); the fallback crop of an unposed model
func _diff_box(img: Image) -> Rect2:
	if _bg == null or img == null or img.get_size() != _bg.get_size():
		return Rect2()
	var w := img.get_width() / 4
	var h := img.get_height() / 4
	var a: Image = img.duplicate()
	var b: Image = _bg.duplicate()
	a.resize(w, h, Image.INTERPOLATE_BILINEAR)
	b.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var have := false
	var box := Rect2i()
	for y in range(0, int(h * 0.82)): # above the Palantir
		for x in w:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.12:
				if not have:
					box = Rect2i(x, y, 1, 1)
					have = true
				else:
					box = box.expand(Vector2i(x, y))
	if not have:
		return Rect2()
	return Rect2(box.position * 4, (box.size + Vector2i(1, 1)) * 4)


# the box's width in world units on the ground (the twin's spacing)
func _world_width(box: Rect2) -> float:
	var a: Vector2 = hud.pixel_to_world(Vector2(box.position.x, box.get_center().y))
	var b: Vector2 = hud.pixel_to_world(Vector2(box.end.x, box.get_center().y))
	if a.x < -1.0e8 or b.x < -1.0e8:
		return 120.0
	return maxf(a.distance_to(b), 20.0)


# a square crop around the box: the health bar above it and some ground below
func _crop_of(box: Rect2) -> Rect2i:
	var size := _vp_size()
	var side := maxf(maxf(box.size.x, box.size.y) * 1.7, 96.0)
	side = minf(side, minf(size.x, size.y * 0.8))
	var c := box.get_center() - Vector2(0, box.size.y * 0.18)
	var r := Rect2i(int(c.x - side * 0.5), int(c.y - side * 0.5), int(side), int(side))
	r.position.x = clampi(r.position.x, 0, int(size.x) - r.size.x)
	r.position.y = clampi(r.position.y, 0, int(size.y * 0.82) - r.size.y)
	return r


func _cell_of(img: Image, crop: Rect2i) -> Image:
	var c := img.get_region(crop)
	c.resize(_cell, _cell, Image.INTERPOLATE_BILINEAR)
	return c


# ---- probes -------------------------------------------------------------------------------------------------------------------------------------

func _ids_of(id: int) -> Array:
	var o: Dictionary = world.get_object(id)
	var out: Array = []
	for m in o.get("members", []):
		out.append(int(m))
	if out.is_empty():
		out.append(id)
	return out


func _compact(dbg: Dictionary) -> Dictionary:
	if not dbg.get("ok", false):
		return {"ok": false}
	var g: float = dbg.ground
	var out := {"ok": true, "x": snappedf(dbg.x, 0.01), "y": snappedf(dbg.y, 0.01), "z_g": snappedf(float(dbg.z) - g, 0.01),
		"house": int(dbg.house_color), "entries": []}
	for e in dbg.get("entries", []):
		if int(e.get("instance", -1)) < 0 and not e.get("missing_model", false):
			continue
		var ce := {"model": e.get("raw_model", e.get("model", "")), "clip": e.get("clip", ""), "frame": snappedf(float(e.get("frame", 0.0)), 0.01),
			"posed": e.get("posed", false), "shadow_bits": int(e.get("shadow_bits", 0)), "casts_map": e.get("casts_map", false),
			"house_kind": int(e.get("house_kind", 0)), "missing": e.get("missing_model", false), "bones": int(e.get("bones", 0))}
		if e.has("lo"):
			ce["min_bone_g"] = snappedf(float(e.min_bone_z) - g, 0.01)
			ce["min_bone"] = e.get("min_bone", "")
			ce["height"] = snappedf(float(e.hi.z) - float(e.lo.z), 0.1)
			var feet: Array = []
			for f in e.get("feet", []):
				feet.append([f.name, snappedf(f.x, 0.01), snappedf(f.y, 0.01), snappedf(float(f.z) - g, 0.01)])
			ce["feet"] = feet
		out.entries.append(ce)
	return out


func _probe_cell(phase: String, ids: Array) -> Dictionary:
	var st: Dictionary = hud.get_state()
	var sel := false
	for dcl in st.get("selection_decals", []):
		if ids.has(int(dcl.get("object", -1))) or int(dcl.get("object", -1)) == _subject:
			sel = true
	var icons: Dictionary = hud.get_icon_ui()
	var bar := false
	for b in icons.get("bar_objects", []):
		if ids.has(int(b)) or int(b) == _subject:
			bar = true
	var shadows: Dictionary = st.get("drawable_shadow_decals", {})
	var members: Array = []
	for i in mini(ids.size(), 4):
		members.append(_compact(world.get_render_debug(int(ids[i]))))
	var o: Dictionary = world.get_object(int(ids[0]))
	return {"phase": phase, "frame": world.get_frame(), "sel": sel, "sel_decals": st.get("selection_decals", []).size(), "bar": bar,
		"images": icons.get("images", []), "shadow_decals_drawn": int(shadows.get("drawn", 0)), "members": members,
		"conditions": o.get("conditions", []), "moving": o.get("moving", false), "speed": o.get("speed", 0.0), "health": o.get("health", 0.0),
		"damage_state": o.get("damage_state", ""), "construction": o.get("construction_percent", -1.0)}


func _process_sample() -> void:
	if not _sampling or _focus <= 0:
		return
	var dbg: Dictionary = world.get_render_debug(_focus)
	if not dbg.get("ok", false):
		return
	var g: float = dbg.ground
	var row := [Time.get_ticks_usec() / 1000.0, world.get_frame(), snappedf(dbg.x, 0.01), snappedf(dbg.y, 0.01), snappedf(float(dbg.z) - g, 0.01)]
	for e in dbg.get("entries", []):
		if e.get("feet", []).size() > 0:
			var feet: Array = []
			for f in e.feet:
				feet.append([snappedf(f.x, 0.01), snappedf(f.y, 0.01), snappedf(float(f.z) - world.get_ground_height(f.x, f.y), 0.01)])
			row.append(e.get("clip", ""))
			row.append(snappedf(float(e.get("frame", 0.0)), 0.01))
			row.append(feet)
			break
	_samples.append(row)


# n cells of the phase, `every` logic frames apart; the crop follows the subject when `follow`
func _strip(phase: String, n: int, every: int, follow := false) -> void:
	var row: Array = []
	var cells: Array = []
	for i in n:
		await _logic(every)
		await game.get_tree().process_frame
		var ids := _ids_of(_subject) if world.get_object(_subject).get("ok", false) else [_focus]
		var img := _frame()
		if img == null:
			break
		if follow:
			var b := _screen_box(ids)
			if b.size != Vector2.ZERO:
				var c := _crop_of(b)
				c.size = _crop.size
				var size := _vp_size()
				c.position = Vector2i(clampi(int(b.get_center().x) - c.size.x / 2, 0, int(size.x) - c.size.x),
					clampi(int(b.get_center().y - b.size.y * 0.1) - c.size.y / 2, 0, int(size.y * 0.82) - c.size.y))
				row.append(_cell_of(img, c))
			else:
				row.append(_cell_of(img, _crop))
		else:
			row.append(_cell_of(img, _crop))
		cells.append(_probe_cell(phase, ids))
	_rows.append({"phase": phase, "cells": row})
	_probe.phases.append({"phase": phase, "every": every, "cells": cells})


func _save_png(img: Image, tag: String, crop: Rect2i) -> void:
	if img == null:
		return
	var dir := "%s/%s/%s" % [_data, _config, _probe.faction]
	DirAccess.make_dir_recursive_absolute(dir)
	# at most 320 px a side, nearest neighbour: the pixel checks compare exact values, and the scratch disk stays small
	var r := img.get_region(crop)
	var k := maxf(1.0, maxf(r.get_width(), r.get_height()) / 320.0)
	if k > 1.0:
		r.resize(int(r.get_width() / k), int(r.get_height() / k), Image.INTERPOLATE_NEAREST)
	r.save_png("%s/%s-%s.png" % [dir, _probe.template, tag])


# the pixel checks' raw crops, the game paused: three frames (flicker), the same without shadows, the enemy-owned twin's crop (house colour)
func _pixel_crops(twin: int) -> void:
	var selected: Array = hud.get_selection()
	hud.deselect_all() # the ring is drawn in the player's colour: it would pass for house colour
	world.set_paused(true)
	await game._step(4)
	for k in 3:
		await game.get_tree().process_frame
		_save_png(_frame(), "still%d" % k, _crop)
	if twin > 0:
		var tb := _screen_box(_ids_of(twin))
		if tb.size != Vector2.ZERO:
			var tc := _crop_of(tb)
			tc.size = _crop.size
			var size := _vp_size()
			tc.position = Vector2i(clampi(int(tb.get_center().x) - tc.size.x / 2, 0, int(size.x) - tc.size.x),
				clampi(int(tb.get_center().y - tb.size.y * 0.1) - tc.size.y / 2, 0, int(size.y * 0.82) - tc.size.y))
			_save_png(_frame(), "twin", tc)
			_probe["twin_house"] = int(world.get_render_debug(_ids_of(twin)[0]).get("house_color", 0))
	game.set_shadow_lod(0)
	hud.set_shadow_decals(false, false)
	await game._step(6)
	_save_png(_frame(), "noshadow", _crop)
	game.set_shadow_lod(_shadow_lod)
	if _shadow == "low":
		hud.set_shadow_decals(true, false)
	else:
		game._push_shadow_decals()
	await game._step(6)
	_save_png(_frame(), "shadow", _crop)
	world.set_paused(false)
	if not selected.is_empty():
		hud.select_objects(PackedInt64Array(selected))
	await game._step(2)


# ---- objects ------------------------------------------------------------------------------------------------------------------------------------

func _make(template: String, player: int, p: Vector2, angle: float) -> int:
	var id: int = world.create_object(template, player, p.x, p.y, angle)
	print("VISSURVEY TEST HOOK: create_object %s for player %d at (%.0f, %.0f) -> %d" % [template, player, p.x, p.y, id])
	if id > 0:
		_created.append(id)
	return id


func _clear() -> void:
	hud.deselect_all()
	for id in _created:
		for m in _ids_of(int(id)) + [int(id)]:
			if world.get_object(int(m)).get("ok", false):
				world.destroy_object(int(m))
	_created.clear()
	await _logic(3)


func _kill(id: int) -> void:
	for m in _ids_of(id) + [id]:
		if world.get_object(int(m)).get("ok", false):
			world.damage_object(int(m), 1.0e7)


# the camera height that frames the object: a first copy measured on the flat spot, then removed
func _frame_height(template: String, kind: String) -> float:
	var c: Dictionary = hud.get_camera()
	var maxh: float = float(c.get("max_height", 400.0))
	var h := maxh * (0.9 if kind == "building" else 0.45)
	await _look(_flat, h)
	var id := _make(template, _me, _flat, 0.0)
	if id <= 0:
		return -1.0
	await _logic(4)
	if kind == "building":
		world.debug_build_complete(id)
		await _logic(3)
	var b := _screen_box(_ids_of(id))
	if b.size == Vector2.ZERO:
		b = _diff_box(_frame())
	await _clear()
	var target := _vp_size().y * (0.42 if kind == "building" else 0.30) / _zoom_out
	if b.size.y > 4.0:
		h = clampf(h * maxf(b.size.y, b.size.x * 0.6) / target, maxh * 0.12, maxh * 2.2)
	return h


# the instancers' error and warning lines added since the last object (a model, texture or animation the archives do not have)
var _errors_seen := {}


func _new_asset_errors() -> Array:
	var out: Array = []
	for c in world.get_children():
		if c.get_class() != "W3DInstancer":
			continue
		var lines: Array = Array(c.get_errors()) + Array(c.get_warnings())
		var key := str(c.get_instance_id())
		var seen: int = _errors_seen.get(key, 0)
		for i in range(seen, lines.size()):
			out.append(String(lines[i]).substr(0, 240))
		_errors_seen[key] = lines.size()
	return out


func _begin(faction: String, template: String, kind: String) -> void:
	print("VISSURVEY BEGIN %s %s" % [faction, template])
	_rows.clear()
	_samples.clear()
	_probe = {"faction": faction, "template": template, "kind": kind, "config": _config, "mode": _mode, "shadow_lod": _shadow_lod,
		"renderer": RenderingServer.get_current_rendering_method(), "phases": [], "notes": []}


func _end(ok: bool) -> void:
	var faction: String = _probe.faction
	var template: String = _probe.template
	_probe["samples"] = _samples
	_probe["ok"] = ok
	_probe["asset_errors"] = _new_asset_errors()
	var dir := "%s/%s/%s" % [_data, _config, faction]
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open("%s/%s.json" % [dir, template], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_probe))
	# the contact sheet: one row per phase, the longest row sets the width
	var cols := 1
	for r in _rows:
		cols = maxi(cols, r.cells.size())
	if not _rows.is_empty():
		var sheet := Image.create(cols * _cell, _rows.size() * _cell, false, Image.FORMAT_RGB8)
		sheet.fill(Color(0.08, 0.08, 0.08))
		for ri in _rows.size():
			var cells: Array = _rows[ri].cells
			for ci in cells.size():
				sheet.blit_rect(cells[ci], Rect2i(0, 0, _cell, _cell), Vector2i(ci * _cell, ri * _cell))
		var sdir := "%s/%s" % [_out, faction]
		DirAccess.make_dir_recursive_absolute(sdir)
		sheet.save_jpg("%s/%s-%s.jpg" % [sdir, template, _config], 0.8)
	_done += 1
	print("VISSURVEY END %s %s %s (%d rows, %d objects so far)" % [faction, template, "ok" if ok else "FAILED", _rows.size(), _done])


func _survey_faction(key: String) -> String:
	var faction: String = FACTIONS.get(key, "")
	if faction.is_empty() or not _catalog.has(faction):
		return "no faction %s in the catalog" % key
	await _setup()
	var entry: Dictionary = _catalog[faction]
	var failed: Array = []
	for kind in ["units", "heroes", "buildings"]:
		var n := 0
		for template in entry[kind]:
			if not _only.is_empty() and not _only.has(String(template)):
				continue
			if _limit > 0 and n >= _limit:
				break
			n += 1
			_quiet_enemy()
			# each object on its own patch of the flat spot (a cell an earlier object used keeps nothing for the next)
			_flat = _flat0 + Vector2((_done % 3 - 1) * 90.0, (_done / 3 % 3 - 1) * 90.0)
			var why := ""
			if kind == "buildings":
				why = await _survey_building(key, String(template), String(entry.builder))
			else:
				why = await _survey_unit(key, String(template), kind == "heroes")
			if not why.is_empty():
				failed.append("%s: %s" % [template, why])
				print("VISSURVEY %s %s: %s" % [key, template, why])
			await _clear()
	# a failed object is a finding, not a failed run: the run fails only when nothing at all was filmed
	print("VISSURVEY faction %s: %d objects not filmed: %s" % [key, failed.size(), "; ".join(failed)])
	return ""


func _survey_unit(faction: String, template: String, hero: bool) -> String:
	_begin(faction, template, "hero" if hero else "unit")
	var h := await _frame_height(template, "unit")
	if h < 0.0:
		_probe.notes.append("create_object failed")
		_end(false)
		return "could not be created"
	_probe["camera_height"] = h
	await _look(_flat, h)
	_bg = _frame()
	_subject = _make(template, _me, _flat, 0.0)
	if _subject <= 0:
		_end(false)
		return "could not be created"
	await _logic(4)
	var ids := _ids_of(_subject)
	_focus = int(ids[0])
	var box := _screen_box(ids)
	if box.size == Vector2.ZERO:
		box = _diff_box(_frame())
		_probe.notes.append("no posed pivots: crop from the frame difference")
	if box.size == Vector2.ZERO:
		box = Rect2(_vp_size() * Vector2(0.4, 0.3), _vp_size() * Vector2(0.2, 0.3))
		_probe.notes.append("nothing drawn: crop at the middle")
	_crop = _crop_of(box)
	_probe["box"] = [box.position.x, box.position.y, box.size.x, box.size.y]
	_probe["bg_diff_box"] = _diff_box(_frame()).size.length() > 0.0
	hud.select_objects(PackedInt64Array([_subject]))
	# the enemy-owned twin, left of the object, outside its crop
	# (full mode only: each owner colour is a model variant of its own, and the renderer's instance-uniform buffer is finite)
	var twin := _make(template, _enemy, Vector2(_flat.x - _world_width(box) * 1.6 - 30.0, _flat.y), 0.0) if _mode == "full" else -1
	await _logic(3)
	await _strip("idle", 6 if _mode == "full" else 3, 1)
	await _pixel_crops(twin)
	if twin > 0:
		for m in _ids_of(twin) + [twin]:
			if world.get_object(int(m)).get("ok", false):
				world.destroy_object(int(m))
	# the veterancy badge from here on (its level-up flash would spoil the still frames above)
	var rank: Variant = world.debug_set_object_rank(_subject, 2)
	_probe["rank_set"] = str(rank)
	# move: across the fixed camera, the feet sampled every render frame
	var o: Dictionary = world.get_object(_focus)
	var dest := Vector2(o.x + 260.0, o.y + 20.0)
	world.order_move(PackedInt64Array([_subject]), dest.x, dest.y, {})
	_samples.clear()
	_sampling = true
	await _logic(2)
	await _strip("move", 6 if _mode == "full" else 3, 1, true)
	_sampling = false
	_probe["move_samples_from"] = 0
	world.order_stop(PackedInt64Array([_subject]))
	if _mode != "full":
		_end(true)
		return ""
	await _logic(4)
	# attack an enemy farm in front of it, the camera over both
	o = world.get_object(_focus)
	var tpos := Vector2(o.x + 170.0, o.y)
	var target := _make(TARGET, _enemy, tpos, PI)
	world.debug_build_complete(target)
	var mid := (Vector2(o.x, o.y) + tpos) * 0.5
	await _look(mid, h * 1.25)
	_crop = _crop_of(Rect2(hud.world_to_pixel(Vector2(o.x - 60.0, o.y)), Vector2.ZERO).expand(hud.world_to_pixel(tpos + Vector2(60.0, 0.0))).grow(box.size.y * 0.5))
	world.order_attack(PackedInt64Array([_subject]), target)
	world.set_time_scale(2.0)
	var still := 0
	var last := Vector2.INF
	for k in 50:
		await _logic(1)
		var f: Dictionary = world.get_object(_focus)
		if not f.get("ok", false):
			break
		var p := Vector2(f.x, f.y)
		still = still + 1 if last != Vector2.INF and p.distance_to(last) < 0.05 else 0
		last = p
		if still >= 3:
			break
	world.set_time_scale(1.0)
	await _strip("attack", 6, 1)
	world.order_stop(PackedInt64Array([_subject]))
	# a hero's first two powers at the farm (or at its own spot)
	if hero and world.get_object(_subject).get("ok", false):
		world.ready_object_powers(_subject)
		var powers: Array = world.get_object_powers(_subject)
		var cast := 0
		for pw in powers:
			if cast >= 2:
				break
			var name := String(pw.get("name", ""))
			if name.is_empty():
				continue
			var okc: bool = world.cast_object_power(_me, _subject, name, target) if world.get_object(target).get("ok", false) else false
			if not okc:
				okc = world.cast_object_power_at(_me, _subject, name, tpos.x, tpos.y)
			_probe.notes.append("power %s cast %s" % [name, str(okc)])
			if okc:
				cast += 1
				await _strip("power-%s" % name, 6, 2)
	if target > 0 and world.get_object(target).get("ok", false):
		world.destroy_object(target)
	# the steepest slope nearby: one copy, two cells (its height above the ground there)
	if world.get_object(_subject).get("ok", false):
		var keep_crop := _crop
		var keep_subject := _subject
		var keep_focus := _focus
		await _look(_slope, h)
		var s := _make(template, _me, _slope, 0.0)
		await _logic(4)
		if s > 0:
			_subject = s
			_focus = int(_ids_of(s)[0])
			var sb := _screen_box(_ids_of(s))
			_crop = _crop_of(sb) if sb.size != Vector2.ZERO else keep_crop
			await _strip("slope", 2, 2)
			for m in _ids_of(s) + [s]:
				if world.get_object(int(m)).get("ok", false):
					world.destroy_object(int(m))
		_subject = keep_subject
		_focus = keep_focus
		var f2: Dictionary = world.get_object(_focus)
		if f2.get("ok", false):
			await _look(Vector2(f2.x, f2.y), h)
			var db := _screen_box(_ids_of(_subject))
			_crop = _crop_of(db) if db.size != Vector2.ZERO else keep_crop
	# die
	if world.get_object(_subject).get("ok", false):
		_kill(_subject)
		await _logic(1)
		if hero and world.get_object(_subject).get("ok", false) and float(world.get_object(_subject).get("health", 0.0)) > 0.0:
			world.kill_hero(_subject)
			_probe.notes.append("damage did not kill the hero: kill_hero")
		await _strip("die", 6, 2)
	_end(true)
	return ""


func _survey_building(faction: String, template: String, builder: String) -> String:
	_begin(faction, template, "building")
	var h := await _frame_height(template, "building")
	if h < 0.0:
		_end(false)
		return "could not be created"
	_probe["camera_height"] = h
	await _look(_flat, h)
	_bg = _frame()
	# made finished (create_object): the construction stage is not filmed (a scripted builder's placement through injected clicks did not take in
	# this harness: the placement ghost does not follow injected pointer moves; see VISUAL-SURVEY.md)
	_subject = _make(template, _me, _flat, 0.0)
	if _subject <= 0:
		_end(false)
		return "could not be created"
	_focus = _subject
	world.debug_build_complete(_subject)
	await _logic(4)
	var at: Dictionary = world.get_object(_subject)
	if Vector2(at.x, at.y).distance_to(_flat) > 30.0:
		await _look(Vector2(at.x, at.y), h)
		_bg = null
	var box := _screen_box([_subject])
	if box.size == Vector2.ZERO:
		box = _diff_box(_frame())
		_probe.notes.append("no posed pivots: crop from the frame difference")
	if box.size == Vector2.ZERO:
		box = Rect2(_vp_size() * Vector2(0.3, 0.2), _vp_size() * Vector2(0.4, 0.45))
		_probe.notes.append("nothing drawn: crop at the middle")
	_crop = _crop_of(box)
	_probe["box"] = [box.position.x, box.position.y, box.size.x, box.size.y]
	var twin := _make(template, _enemy, Vector2(float(at.x) - _world_width(box) * 1.6 - 40.0, float(at.y)), 0.0) if _mode == "full" else -1
	if twin > 0:
		world.debug_build_complete(twin)
	hud.select_objects(PackedInt64Array([_subject]))
	await _logic(3)
	await _strip("finished", 2 if _mode == "full" else 1, 2)
	hud.deselect_all() # the radial's bubbles would cover the damage
	await _pixel_crops(twin)
	if twin > 0 and world.get_object(twin).get("ok", false):
		world.destroy_object(twin)
	var maxhp := float(world.get_object(_subject).get("max_health", 1000.0))
	print("VISSURVEY TEST HOOK: debug_damage_object %s" % str(world.debug_damage_object(_subject, maxhp * 0.55, 0)))
	await _logic(6)
	await _strip("damaged", 2 if _mode == "full" else 1, 3)
	if _mode != "full":
		_end(true)
		return ""
	print("VISSURVEY TEST HOOK: debug_damage_object %s" % str(world.debug_damage_object(_subject, maxhp * 0.3, 0)))
	await _logic(6)
	await _strip("badly-damaged", 3, 3)
	_kill(_subject)
	await _strip("destroyed", 6, 3)
	_end(true)
	return ""
