## Wall crossing check (lane BUG-1): a Men wall span is built from the castle's wall hub, then each horde is ordered from one side of the
## wall to the other. Every logic frame the members' signed distance to the wall line and their height above the ground are logged, so a
## member that passes the wall's line inside its length shows as "crossed" with the height it had while doing so (a climb rises on the wall's
## face, RW 0x86E214; a walk-through stays on the ground). It changes nothing in the game.
##
##   godot --path godot res://scenes/wall_cross_viewer.tscn -- [options]
##
## Options (after `--`):
##   --map=<path>          the map (default "maps/map mp evendim/map mp evendim.map", build_viewer's)
##   --units=<a,b,...>     horde templates (default GoblinFighterHorde,GoblinSpiderRiderHorde,WildSpiderlingHorde,MordorFighterHorde)
##   --shots=<dir>         screenshots <unit>-wall-<n>.png while members are at the wall
##   --length=<d>          the span's length (default 700); --at=<f> where along it the hordes cross (default 0.6)
##   --frames=<n>          logic frames each horde gets (default 200)
extends Node3D

var _map_name := "maps/map mp evendim/map mp evendim.map"
var _local_name := ""
var _units: Array = ["GoblinFighterHorde", "GoblinSpiderRiderHorde", "WildSpiderlingHorde", "MordorFighterHorde"]
var _shots := ""
var _frames := 200
var _length := 700.0
var _at := 0.6
var _world: Node3D
var _camera: Camera3D
var _label: Label
var _local := -1
var _enemy := -1


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			_map_name = arg.substr(6)
		elif arg.begins_with("--units="):
			_units = Array(arg.substr(8).split(","))
		elif arg.begins_with("--shots="):
			_shots = arg.substr(8)
		elif arg.begins_with("--length="):
			_length = float(arg.substr(9))
		elif arg.begins_with("--at="):
			_at = float(arg.substr(5))
		elif arg.begins_with("--frames="):
			_frames = int(arg.substr(9))
	var fs: RefCounted = ClassDB.instantiate("RetailFileSystem")
	var mount: Dictionary = fs.mount_retail()
	if not mount.ok:
		_fail("mount failed: %s" % [mount.errors])
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.3, 0.4)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_camera = Camera3D.new()
	_camera.fov = 40
	_camera.near = 2.0
	_camera.far = 60000.0
	add_child(_camera)
	_world = ClassDB.instantiate("GameWorld")
	add_child(_world)
	var setup: Dictionary = _world.setup(fs)
	if not setup.ok:
		_fail("object world failed: %s" % [setup.errors])
		return
	# a skirmish start as build_viewer's (the castle and its wall hub pads exist): the local Men player and an idle Easy AI Mordor
	var slots: Array = []
	for i in 8:
		slots.append({"state": 1, "name": "Closed", "accepted": true, "color": -1, "start_pos": -1, "player_template": -1, "team": -1})
	slots[0] = {"state": 6, "name": "Gimli", "accepted": true, "color": 0, "start_pos": 0, "player_template": 3, "team": -1}
	slots[1] = {"state": 2, "name": "Easy AI", "accepted": true, "color": 1, "start_pos": 4, "player_template": 8, "team": -1}
	var message := {"mode": "skirmish", "difficulty": 1, "rank_points": 0, "map": _map_name, "map_crc": 0, "map_size": 0, "map_mask": 0, "seed": 4711, "starting_cash": 5000, "slots": slots}
	var prep: Dictionary = _world.prepare_new_game(message)
	if not prep.ok:
		_fail("prepare_new_game: %s" % [prep.errors])
		return
	var rep: Dictionary = _world.start_new_game({})
	if not rep.ok:
		_fail("start_new_game: %s" % [rep.errors.slice(0, 5)])
		return
	_local_name = str(rep.start.get("local_player", ""))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
	_world.set_auto_advance(true)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(8, 4)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_label)
	_run()


func _fail(message: String) -> void:
	push_error(message)
	print("WALLCROSS FAIL: ", message)
	get_tree().quit(1)


func _sage_to_godot(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y)


func _logic(n: int) -> void:
	var until: int = _world.get_frame() + n
	while _world.get_frame() < until:
		await get_tree().process_frame


func _look(at: Vector2, from_dir: Vector2, dist: float) -> void:
	var g: float = _world.get_ground_height(at.x, at.y)
	var p := at - from_dir * dist
	_camera.position = _sage_to_godot(Vector3(p.x, p.y, g + dist * 0.55))
	_camera.look_at(_sage_to_godot(Vector3(at.x, at.y, g + 10.0)), Vector3.UP)


func _run() -> void:
	await _logic(3)
	var hub: Dictionary = _world.build2_wall_hub(_local_name, "MenWallHubSmallExpansion")
	if not hub.get("ok", false):
		_fail("wall hub: %s" % hub.get("error", ""))
		return
	var h := Vector2(float(hub.x), float(hub.y))
	var dir := Vector2(h.x - float(hub.cx), h.y - float(hub.cy)).normalized()
	# the wall runs out from the castle (build_viewer's span), so both its sides are open ground
	var a := h
	var b := h + dir * _length
	var before := {}
	for id in _world.get_object_ids():
		before[id] = true
	print("WALLCROSS span sent: ", _world.build2_wall_span(int(hub.hub), "MenWallHubSmall", a.x, a.y, b.x, b.y, 1 << 13))
	await _logic(20)
	var pieces: Array = []
	for id in _world.get_object_ids():
		if before.has(id):
			continue
		var o: Dictionary = _world.get_object(id)
		if str(o.get("template", "")).begins_with("MenWall"):
			pieces.append(id)
	# the span's builders put the pieces up one after another: fast-forward until none is under construction (at most 2000 logic frames)
	_world.set_time_scale(8.0)
	for round in 200:
		var building := 0
		for id in pieces:
			if _world.get_object(id).get("under_construction", false):
				building += 1
		if building == 0:
			break
		await _logic(10)
	_world.set_time_scale(1.0)
	await _logic(10)
	var names := {}
	for id in pieces:
		var o: Dictionary = _world.get_object(id)
		names[str(o.template)] = names.get(str(o.template), 0) + 1
	print("WALLCROSS wall pieces: %d %s from (%.0f, %.0f) to (%.0f, %.0f)" % [pieces.size(), names, a.x, a.y, b.x, b.y])
	var ts: Array = []
	for id in pieces:
		var o: Dictionary = _world.get_object(id)
		ts.append("%s %.0f (%s)" % [str(o.template).replace("MenWall", ""), (Vector2(o.x, o.y) - a).dot(dir), "building" if o.get("under_construction", false) else "built"])
	print("WALLCROSS pieces along the span: ", ", ".join(ts))
	var mid := (a + b) * 0.5
	var normal := Vector2(-dir.y, dir.x)
	# create_object takes an index of the player list: the hordes go to the first player that is neither the local one nor neutral
	for i in 16:
		var probe: int = _world.create_object("MordorFighterHorde", i, mid.x - normal.x * 400.0, mid.y - normal.y * 400.0, 0.0)
		if probe < 0:
			continue
		var owner := str(_world.get_object(probe).get("owner", ""))
		_world.destroy_object(probe)
		if owner != _local_name and owner != "" and not owner.to_lower().contains("neutral") and not owner.to_lower().contains("civilian") and not owner.to_lower().contains("creep"):
			_enemy = i
			print("WALLCROSS the hordes belong to %s (index %d)" % [owner, i])
			break
	_look(mid, -normal.rotated(0.6), 420.0)
	await _logic(3)
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)
		get_viewport().get_texture().get_image().save_png(_shots.path_join("wall.png"))
	for unit in _units:
		await _cross(String(unit), a, b, normal, mid)
	print("WALLCROSS DONE")
	get_tree().quit(0)


func _cross(unit: String, a: Vector2, b: Vector2, normal: Vector2, mid: Vector2) -> void:
	var cross := a.lerp(b, _at)
	var start := cross - normal * 220.0
	var goal := cross + normal * 220.0
	var horde: int = _world.create_object(unit, _enemy, start.x, start.y, normal.angle())
	if horde <= 0:
		print("WALLCROSS %s could not be created" % unit)
		return
	await _logic(3)
	print("WALLCROSS %s order %s" % [unit, _world.order_move([horde], goal.x, goal.y, {})])
	var length := a.distance_to(b)
	var along := (b - a) / length
	var crossed := {}
	var max_h := 0.0
	var max_h_at_wall := 0.0
	var at_wall_frames := 0
	var shots := 0
	var first_side := {}
	var start_frame: int = _world.get_frame()
	var last := -1
	while _world.get_frame() < start_frame + _frames:
		await get_tree().process_frame
		var f: int = _world.get_frame()
		if f == last:
			continue
		last = f
		var o: Dictionary = _world.get_object(horde)
		if not o.get("ok", false):
			break
		var members = o.get("members", [])
		var near := false
		for m in members:
			var mo: Dictionary = _world.get_object(int(m))
			if not mo.get("ok", false):
				continue
			var p := Vector2(mo.x, mo.y)
			var s := (p - a).dot(normal)
			var t := (p - a).dot(along)
			var hgt: float = float(mo.z) - _world.get_ground_height(p.x, p.y)
			max_h = maxf(max_h, hgt)
			if not first_side.has(m):
				first_side[m] = signf(s)
			if t > 10.0 and t < length - 10.0:
				if absf(s) < 12.0:
					near = true
					max_h_at_wall = maxf(max_h_at_wall, hgt)
				if signf(s) != first_side[m] and signf(s) != 0.0 and not crossed.has(m):
					crossed[m] = [f, hgt, t]
		if near:
			at_wall_frames += 1
			if not _shots.is_empty() and shots < 3 and at_wall_frames % 4 == 1:
				_look(mid, -normal.rotated(0.6), 300.0)
				_label.text = "%s at the wall, logic frame %d" % [unit, f]
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(_shots.path_join("%s-wall-%d.png" % [unit, shots]))
				shots += 1
	var o2: Dictionary = _world.get_object(horde)
	var members2 = o2.get("members", [])
	var beyond := 0
	for m in members2:
		var mo: Dictionary = _world.get_object(int(m))
		if mo.get("ok", false) and (Vector2(mo.x, mo.y) - a).dot(normal) > 0.0:
			beyond += 1
	print("WALLCROSS %s: %d members, %d crossed the wall line inside its length %s, %d now beyond; max height above ground %.1f (at the wall %.1f); frames with a member at the wall %d" % [
		unit, members2.size(), crossed.size(), crossed.values().slice(0, 4), beyond, max_h, max_h_at_wall, at_wall_frames])
	for m in members2:
		if _world.get_object(int(m)).get("ok", false):
			_world.destroy_object(int(m))
	if _world.get_object(horde).get("ok", false):
		_world.destroy_object(horde)
	await _logic(3)
