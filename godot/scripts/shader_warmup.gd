extends Node
## Lane IOS-11 (OpenBFME, not retail): the W3D shaders compiled ahead of play, so a unit type's first appearance does not stall the game while its
## shader compiles (0.1 .. 0.8 s per new variant on an M2 Max the first time, longer on a phone; Godot's shader cache only helps from the second run).
##
## The variants (id -> generated code, GameWorld.w3d_shader_variants) come from two lists: the one shipped with the game (SHIPPED, recorded on the
## same rendering driver: the code differs by driver, W3DMaterialFactory's sampler policy) and the ones this device has generated before (LEARNED,
## saved while playing). In the menus they are created a few per frame (GameWorld.warm_w3d_shaders); Godot compiles them on its worker threads, and
## the game's own surfaces then take the warm shader of the same id. A variant whose code changed (a newer build) is simply generated again.
##
## `-- --record-shaders=<path>` writes every variant of the run to <path> when the game ends (how SHIPPED is made: play the factions' games once).

const SHIPPED := "res://data/w3d-shader-variants.json"
const LEARNED := "user://w3d-shader-variants.json"
const PER_FRAME := 6           # shaders created per frame while warming (the menus stay responsive)
const SAVE_EVERY_S := 30.0     # how often new variants are saved while playing (a phone ends apps without notice)

var _learned := {}
var _saved_count := 0
var _record_path := ""
var _t := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--record-shaders="):
			_record_path = a.trim_prefix("--record-shaders=")
	_learned = _read(LEARNED)
	_saved_count = _learned.size()
	_warm()


func _warm() -> void:
	var driver := RenderingServer.get_current_rendering_driver_name()
	var shipped := _read(SHIPPED)
	var all := shipped.duplicate()
	all.merge(_learned, true)
	# a variant's id names the sampler policy it was generated for (W3DMaterialFactory::Get_Shader: "_metal16" on Metal): only this driver's are warm-able
	var metal := driver == "metal"
	var ids := all.keys().filter(func(id: String) -> bool: return id.ends_with("_metal16") == metal)
	var t0 := Time.get_ticks_msec()
	var created := 0
	for i in range(0, ids.size(), PER_FRAME):
		var batch := {}
		for id in ids.slice(i, i + PER_FRAME):
			batch[id] = all[id]
		created += int(ClassDB.class_call_static("GameWorld", "warm_w3d_shaders", batch))
		await get_tree().process_frame
	var learned_only := ids.filter(func(id: String) -> bool: return not shipped.has(id)).size()
	print("SHADERS warmed %d of %d W3D variants (%d shipped, %d more learned on this device; driver %s) in %.1f s" % [created, ids.size(),
		ids.size() - learned_only, learned_only, driver, (Time.get_ticks_msec() - t0) / 1000.0])


func _process(delta: float) -> void:
	_t += delta
	if _t >= SAVE_EVERY_S:
		_t = 0.0
		_save_new()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_save_new()


func _exit_tree() -> void:
	_save_new()
	if not _record_path.is_empty():
		var all: Dictionary = ClassDB.class_call_static("GameWorld", "w3d_shader_variants")
		all.merge(_learned, false)
		print("SHADERS recorded %d variants -> %s: %s" % [all.size(), _record_path, error_string(_write(_record_path, all))])


## the variants generated since the last save join the device's list
func _save_new() -> void:
	var now: Dictionary = ClassDB.class_call_static("GameWorld", "w3d_shader_variants")
	_learned.merge(now, true)
	if _learned.size() == _saved_count:
		return
	var err := _write(LEARNED, _learned)
	if err != OK:
		printerr("SHADERS cannot save the learned variants to %s: %s" % [LEARNED, error_string(err)])
		return
	_saved_count = _learned.size()


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		printerr("SHADERS %s is not a JSON object: ignored" % path)
		return {}
	return parsed


static func _write(path: String, variants: Dictionary) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(variants))
	f.close()
	return OK
