## Character animation survey (lane BUG-1): one unit at a time in a live game, filmed from a low side view through idle, move, attack and death,
## each phase saved as a strip of frames so hovering (feet above the ground), sliding, T-poses and frozen poses show side by side. Every capture
## also logs the drawable's height above the terrain under it (drawable z - ground height) and the logic z, so a float that is the object's own
## height is told apart from one inside the model. It changes nothing in the game.
##
##   godot --path godot res://scenes/anim_survey_viewer.tscn -- [options]
##
## Options (after `--`):
##   --map=<name>          the map (default "map mp fall back 4p")
##   --units=<a,b,...>     object templates (a horde template films its first member's view: the whole horde is in shot); each may be written
##                         <label>:<template>@<zoom>: the strips are then named <prefix><label>-<template>-<phase>.png and filmed at that zoom
##   --phases=<a,b,...>    any of idle, move, attack, die (default all four, in that order)
##   --shots=<dir>         where the strips go (default user://anim); one PNG per unit and phase: <prefix><unit>-<phase>.png
##   --prefix=<text>       file name prefix (e.g. "mordor-")
##   --cells=<n>           frames per strip (default 6); --every=<n> logic frames between them (default 1: 0.2 s of game time)
##   --size=<px>           the side of one strip cell (default 300)
##   --speed=<f>           the logic speed (default 0.5: slow motion)
##   --target=<template>   what the attack phase attacks (default MordorBarracks, owned by the other player)
##   --zoom=<f>            camera distance factor (default 1)
##   --producer=<template> the unit is not created in place but trained in this building (the computer player's): the strips film it
##                         from the moment it leaves, with its height above the terrain (a unit made at its building's door height)
##   --hill                start on a slope: the point of the map's playable middle whose ground falls the most over the next 600 along +X
##                         (the move phase walks down it), to show a unit's height on uneven ground
##   --fixed               the camera stays where each strip starts instead of following the unit (shows feet slipping against the ground)
##   --view=<side|game>    side: a low side view (default); game: the player's view (from the south, about 50 degrees down)
extends Node3D

var _map_name := "map mp fall back 4p"
var _units: Array = ["MordorMountainTroll"]
var _phases: Array = ["idle", "move", "attack", "die"]
var _shots := "user://anim"
var _prefix := ""
var _cells := 6
var _every := 1
var _size := 300
var _speed := 0.5
var _target_template := "MordorBarracks"
var _zoom := 1.0
var _view := "side"
var _producer := ""
var _hill := false
var _fixed := false
var _fixed_at := Vector3.INF
var _fs: RefCounted
var _world: Node3D
var _camera: Camera3D
var _label: Label
var _local := -1
var _enemy := -1
var _centre := Vector2.INF


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			_map_name = arg.substr(6)
		elif arg.begins_with("--units="):
			_units = Array(arg.substr(8).split(","))
		elif arg.begins_with("--phases="):
			_phases = Array(arg.substr(9).split(","))
		elif arg.begins_with("--shots="):
			_shots = arg.substr(8)
		elif arg.begins_with("--prefix="):
			_prefix = arg.substr(9)
		elif arg.begins_with("--cells="):
			_cells = int(arg.substr(8))
		elif arg.begins_with("--every="):
			_every = int(arg.substr(8))
		elif arg.begins_with("--size="):
			_size = int(arg.substr(7))
		elif arg.begins_with("--speed="):
			_speed = float(arg.substr(8))
		elif arg.begins_with("--target="):
			_target_template = arg.substr(9)
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.substr(7))
		elif arg == "--fixed":
			_fixed = true
		elif arg == "--hill":
			_hill = true
		elif arg.begins_with("--producer="):
			_producer = arg.substr(11)
		elif arg.begins_with("--view="):
			_view = arg.substr(7)
	_fs = ClassDB.instantiate("RetailFileSystem")
	var mount: Dictionary = _fs.mount_retail()
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
	_camera.fov = 30
	_camera.near = 2.0
	_camera.far = 60000.0
	add_child(_camera)
	var builder: RefCounted = ClassDB.instantiate("MapTerrainBuilder")
	var root: Node3D = builder.build_map(_fs, _map_name, {"markers": false, "fog": false})
	if root == null:
		_fail("build_map failed: %s" % [builder.get_report().errors])
		return
	add_child(root)
	_world = ClassDB.instantiate("GameWorld")
	var setup: Dictionary = _world.setup(_fs)
	if not setup.ok:
		_fail("object world failed: %s" % [setup.errors])
		return
	# the filmed unit is the computer player's: a human player's units do not attack what its shroud fogs (anim1_viewer)
	var slots := [
		{"player": "Player_1", "faction": "FactionMen", "human": true, "team": 0, "start_index": 0},
		{"player": "Player_2", "faction": "FactionMordor", "human": false, "team": 1, "start_index": 1},
	]
	var rep: Dictionary = _world.load_map(_map_name, {"slots": slots, "seed": 4711})
	if not rep.ok:
		_fail("load_map failed: %s" % [rep.errors.slice(0, 5)])
		return
	root.add_child(_world)
	var idx := 0
	for pl in rep.players:
		if "Player_1" in str(pl) and _local < 0:
			_local = idx
		if "Player_2" in str(pl) and _enemy < 0:
			_enemy = idx
		idx += 1
	_hide_static_scenery()
	_world.set_auto_advance(true)
	_world.set_time_scale(_speed)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(8, 4)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_font_size_override("font_size", 16)
	layer.add_child(_label)
	_run()


# the map's trees and props (the largest instancer, as anim1_viewer hides them): nothing stands between the camera and the unit
func _hide_static_scenery() -> void:
	var best: Node = null
	var most := -1
	for c in _world.get_children():
		if c.get_class() == "W3DInstancer":
			var n: int = c.get_instance_count()
			if n > most:
				most = n
				best = c
	if best != null:
		best.visible = false


func _fail(message: String) -> void:
	push_error(message)
	print("ANIMSURVEY FAIL: ", message)
	get_tree().quit(1)


func _sage_to_godot(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y)


func _base() -> Vector2:
	if _centre == Vector2.INF:
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for id in _world.get_object_ids():
			var o: Dictionary = _world.get_object(id)
			if o.get("ok", false):
				lo = Vector2(minf(lo.x, o.x), minf(lo.y, o.y))
				hi = Vector2(maxf(hi.x, o.x), maxf(hi.y, o.y))
		_centre = (lo + hi) * 0.5
		if _hill:
			var best := -1.0
			var pick := _centre
			for i in 31:
				for j in 31:
					var p := Vector2(lerpf(lo.x, hi.x, 0.15 + 0.6 * i / 30.0), lerpf(lo.y, hi.y, 0.15 + 0.7 * j / 30.0))
					var h0: float = _world.get_ground_height(p.x, p.y)
					var drop: float = h0 - _world.get_ground_height(p.x + 600.0, p.y + 80.0)
					if drop > best:
						best = drop
						pick = p
			print("ANIMSURVEY hill at (%.0f, %.0f): the ground falls %.1f over the move" % [pick.x, pick.y, best])
			_centre = pick
	return _centre


func _run() -> void:
	await get_tree().process_frame
	for unit in _units:
		await _survey(String(unit))
	print("ANIMSURVEY DONE")
	get_tree().quit(0)


# the unit's position for the camera: the horde's first member when it has members (a horde's own position is its formation centre)
func _focus_id(id: int) -> int:
	var o: Dictionary = _world.get_object(id)
	var members = o.get("members", [])
	if members is Array and members.size() > 0:
		return int(members[0])
	return id


func _all_ids(id: int) -> Array:
	var o: Dictionary = _world.get_object(id)
	var out: Array = []
	var members = o.get("members", [])
	if members is Array:
		for m in members:
			out.append(int(m))
	out.append(id)
	return out


func _survey(spec: String) -> void:
	var label := ""
	var unit := spec
	var zoom := _zoom
	if unit.contains("@"):
		zoom = float(unit.get_slice("@", 1))
		unit = unit.get_slice("@", 0)
	if unit.contains(":"):
		label = unit.get_slice(":", 0) + "-"
		unit = unit.get_slice(":", 1)
	var keep_zoom := _zoom
	var keep_prefix := _prefix
	_zoom = zoom
	_prefix = keep_prefix + label
	await _survey_unit(unit)
	_zoom = keep_zoom
	_prefix = keep_prefix


func _survey_unit(unit: String) -> void:
	var base := _base()
	var id := -1
	if _producer.is_empty():
		id = _world.create_object(unit, _enemy, base.x, base.y, 0.0)
	else:
		id = await _produce(unit, base)
	print("ANIMSURVEY %s object %d" % [unit, id])
	if id <= 0:
		print("ANIMSURVEY %s could not be created" % unit)
		return
	await _logic(3, id)
	var target := -1
	for phase in _phases:
		if not _world.get_object(id).get("ok", false):
			print("ANIMSURVEY %s gone before %s" % [unit, phase])
			break
		match String(phase):
			"idle":
				_world.order_stop([id])
				await _logic(5, id)
				await _strip(unit, "idle", id)
			"move":
				var o: Dictionary = _world.get_object(id)
				print("ANIMSURVEY %s move from (%.0f, %.0f): %s" % [unit, o.x, o.y, _world.order_move([id], o.x + 600.0, o.y + 80.0, {})])
				await _logic(5, id)
				await _strip(unit, "move", id)
				_world.order_stop([id])
				await _logic(5, id)
			"attack":
				var o: Dictionary = _world.get_object(id)
				target = _world.create_object(_target_template, _local, o.x + 200.0, o.y, PI)
				await _logic(2, id)
				print("ANIMSURVEY %s attack %s object %d: %s" % [unit, _target_template, target, _world.order_attack([id], target)])
				# close in first: the strip starts once the unit has stood still for 3 logic frames near the target, or after 60
				var still := 0
				var last := Vector2.INF
				for k in 60:
					await _logic(1, id)
					var f: Dictionary = _world.get_object(_focus_id(id))
					if not f.get("ok", false):
						break
					var p := Vector2(f.x, f.y)
					still = still + 1 if last != Vector2.INF and p.distance_to(last) < 0.05 else 0
					last = p
					if still >= 3:
						break
				await _strip(unit, "attack", id)
				_world.order_stop([id])
			"die":
				for d in _all_ids(id):
					_world.damage_object(d, 1.0e7)
				await _strip(unit, "die", id, true)
	for d in _all_ids(id):
		if _world.get_object(d).get("ok", false):
			_world.destroy_object(d)
	if target > 0 and _world.get_object(target).get("ok", false):
		_world.destroy_object(target)
	await _logic(3, -1)


# trains the unit in a new _producer of the computer player's and returns the trained object once it exists (-1 after 300 logic frames)
func _produce(unit: String, base: Vector2) -> int:
	var b: int = _world.create_object(_producer, _enemy, base.x, base.y, 0.0)
	await _logic(2, -1)
	_world.debug_build_complete(b)
	_world.give_money(_enemy, 100000)
	var before := {}
	for oid in _world.get_object_ids():
		before[oid] = true
	_world.queue_unit(_enemy, b, unit)
	print("ANIMSURVEY %s queued in %s %d" % [unit, _producer, b])
	for k in 300:
		await _logic(1, -1)
		for oid in _world.get_object_ids():
			if before.has(oid):
				continue
			var o: Dictionary = _world.get_object(oid)
			if o.get("ok", false) and String(o.get("template", "")) == unit:
				var pose: Dictionary = _world.get_render_pose(oid)
				print("ANIMSURVEY %s trained: object %d at (%.0f, %.0f, z %.2f), ground %.2f" % [unit, oid, o.x, o.y, o.z, _world.get_ground_height(o.x, o.y)])
				return oid
	return -1


# waits n logic frames, keeping the camera on the unit
func _logic(n: int, id: int) -> void:
	var until: int = _world.get_frame() + n
	var fid := _focus_id(id) if id > 0 else -1
	while _world.get_frame() < until:
		await get_tree().process_frame
		if fid > 0:
			_aim(fid)


func _aim(fid: int, ground_only := false) -> Dictionary:
	var pose: Dictionary = _world.get_render_pose(fid)
	if not pose.get("ok", false):
		return {}
	var x: float = pose.x
	var y: float = pose.y
	var z: float = pose.z
	if _fixed:
		if _fixed_at == Vector3.INF:
			_fixed_at = Vector3(x, y, z)
		var g: float = _world.get_ground_height(_fixed_at.x, _fixed_at.y)
		var d := 150.0 * _zoom
		_camera.position = _sage_to_godot(Vector3(_fixed_at.x + d * 0.5, _fixed_at.y - d, g + d * 0.18))
		_camera.look_at(_sage_to_godot(Vector3(_fixed_at.x + d * 0.5, _fixed_at.y, g + 18.0 * _zoom)), Vector3.UP)
		return {"z": z, "ground": _world.get_ground_height(x, y), "logic_z": pose.logic_z, "x": x, "y": y}
	var ground: float = _world.get_ground_height(x, y)
	var dist := 150.0 * _zoom
	# a side view from the south, low: the feet and the ground line are in profile
	var cam := Vector3(x, y - dist, ground + dist * 0.18) if _view == "side" else Vector3(x, y - dist * 0.8, ground + dist)
	_camera.position = _sage_to_godot(cam)
	_camera.look_at(_sage_to_godot(Vector3(x, y, ground + 18.0 * _zoom)), Vector3.UP)
	return {"z": z, "ground": ground, "logic_z": pose.logic_z, "x": x, "y": y}


func _strip(unit: String, phase: String, id: int, allow_gone := false) -> void:
	_fixed_at = Vector3.INF
	var cells: Array = []
	var heights: Array = []
	var fid := _focus_id(id)
	for c in _cells:
		await _logic(_every, fid)
		var a := _aim(fid)
		if a.is_empty():
			if allow_gone:
				break
			print("ANIMSURVEY %s %s: the drawable is gone" % [unit, phase])
			break
		_label.text = "%s  %s  frame %d  drawable z - ground %.2f  logic z - ground %.2f" % [unit, phase, _world.get_frame(), a.z - a.ground, a.logic_z - a.ground]
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var side := mini(img.get_width(), img.get_height())
		var cell := img.get_region(Rect2i((img.get_width() - side) / 2, img.get_height() - side, side, side))
		cell.resize(_size, _size, Image.INTERPOLATE_BILINEAR)
		cells.append(cell)
		heights.append("%.2f @ (%.0f, %.0f) f%d" % [a.z - a.ground, a.x, a.y, _world.get_frame()])
	if cells.is_empty():
		return
	var strip := Image.create(_size * cells.size(), _size, false, cells[0].get_format())
	for i in cells.size():
		strip.blit_rect(cells[i], Rect2i(0, 0, _size, _size), Vector2i(i * _size, 0))
	var path := "%s/%s%s-%s.png" % [_shots, _prefix, unit, phase]
	DirAccess.make_dir_recursive_absolute(_shots)
	var err := strip.save_png(path)
	print("ANIMSURVEY %s %s -> %s (%s) drawable z - ground per cell: %s" % [unit, phase, path, error_string(err), ", ".join(heights)])
