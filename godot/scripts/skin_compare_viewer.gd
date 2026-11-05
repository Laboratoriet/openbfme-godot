## Skin comparison (lane BUG-1): several W3D models playing the same clip at the same frozen times, side by side on a ground line, from a
## low side camera. For telling a model's skinning from its animation: two skins of one skeleton must put the feet in the same place.
##
##   godot --path godot res://scenes/skin_compare_viewer.tscn -- --models=A,B --clip=<HIER.ANIM> --times=0,0.2,... --shots=<dir> [--mod=<folder>]
##   --mod=<folder>   an install-folder mod mounted over retail first (RetailFileSystem.set_install_mod), e.g. to show a mod's own skin
##   --bones=<i,j>    bone indices whose world height is printed at every time (W3DInstancer.get_bone_position)
extends Node3D

var _models: Array = ["MUMntTroll_SKN"]
var _clip := "MUMntTroll_SKL.MUMntTroll_RUNA"
var _times: Array = [0.0, 0.15, 0.3, 0.45, 0.6, 0.75]
var _shots := "user://skin"
var _mod := ""
var _bones: Array = []
var _spacing := 70.0
var _no_shots := false
var _log_path := ""
var _log_lines: PackedStringArray = []
var _clips: Array = [] # --clips=a,b: one instance of the first model per clip instead
var _inst: Node3D
var _camera: Camera3D
var _label: Label


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--models="):
			_models = Array(arg.substr(9).split(","))
		elif arg.begins_with("--clip="):
			_clip = arg.substr(7)
		elif arg.begins_with("--times="):
			_times = Array(arg.substr(8).split(",")).map(func(t): return float(t))
		elif arg.begins_with("--steps="):
			# --steps=<count>:<per second>: count evenly spaced times from 0, no screenshots
			var parts := arg.substr(8).split(":")
			_times = []
			for k in int(parts[0]):
				_times.append(k / float(parts[1]))
			_no_shots = true
		elif arg.begins_with("--log="):
			_log_path = arg.substr(6)
		elif arg.begins_with("--shots="):
			_shots = arg.substr(8)
		elif arg.begins_with("--mod="):
			_mod = arg.substr(6)
		elif arg.begins_with("--bones="):
			_bones = Array(arg.substr(8).split(","))
		elif arg.begins_with("--clips="):
			_clips = Array(arg.substr(8).split(","))
		elif arg.begins_with("--spacing="):
			_spacing = float(arg.substr(10))
	var fs: RefCounted = ClassDB.instantiate("RetailFileSystem")
	if not _mod.is_empty():
		fs.set_install_mod(_mod)
	var mount: Dictionary = fs.mount_retail()
	if not mount.ok:
		_fail("mount failed: %s" % [mount.errors])
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.65, 0.75)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.8)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	# the ground line: a thin dark slab whose top is y = 0 (SAGE z = 0)
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2000, 0.4, 2000)
	ground.mesh = box
	ground.position = Vector3(0, -0.2, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.22, 0.18)
	ground.material_override = gm
	add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 30
	add_child(_camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(8, 4)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_label)
	_inst = ClassDB.instantiate("W3DInstancer")
	add_child(_inst)
	var setup: Dictionary = _inst.setup(fs)
	if not setup.ok:
		_fail("instancer setup failed: %s" % [setup.errors])
		return
	_inst.set_playing(false)
	var ids: Array = []
	if not _clips.is_empty():
		var one = _models[0]
		_models = []
		for c in _clips:
			_models.append(one)
	var x0 := -_spacing * (_models.size() - 1) * 0.5
	for i in _models.size():
		var m: int = _inst.add_model(String(_models[i]))
		if m < 0:
			_fail("model %s: %s" % [_models[i], _inst.get_errors()])
			return
		var rep: Dictionary = _inst.get_model_report(m)
		print("SKINCMP model %s: %s" % [_models[i], rep])
		# a W3D unit faces +X: side view from +Z shows it walking left to right
		var clip: String = _clip if _clips.is_empty() else String(_clips[i])
		var inst: int = _inst.add_instance(m, Transform3D(Basis(), Vector3(x0 + i * _spacing, 0, 0)), clip, 0.0, 1.0)
		ids.append(inst)
	_camera.position = Vector3(0, 1.5, 60 + _spacing * _models.size() * 0.9)
	_camera.look_at(Vector3(0, 18, 0), Vector3.UP)
	_run.call_deferred(ids)


func _run(ids: Array) -> void:
	DirAccess.make_dir_recursive_absolute(_shots)
	for t in _times:
		_inst.set_global_time(float(t))
		_inst.update_now()
		for k in 3:
			await get_tree().process_frame
		var line := "t=%.2f" % t
		for i in ids.size():
			for b in _bones:
				var p = _inst.get_bone_position(ids[i], int(b))
				line += "  %s.%s=(%.2f,%.2f,%.2f)" % [i if _clips.is_empty() else String(_clips[i]).get_slice(".", String(_clips[i]).get_slice_count(".") - 1), b, p.x, p.y, p.z]
		print("SKINCMP ", line)
		_log_lines.append(line)
		if _no_shots:
			continue
		_label.text = "%s   t=%.2f s   %s" % [_clip, t, ", ".join(_models)]
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := "%s/skincmp-%05.2f.png" % [_shots, t]
		print("SKINCMP shot ", path, " ", error_string(img.save_png(path)))
	if not _log_path.is_empty():
		var f := FileAccess.open(_log_path, FileAccess.WRITE)
		f.store_string("\n".join(_log_lines) + "\n")
	print("SKINCMP DONE")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	print("SKINCMP FAIL: ", message)
	get_tree().quit(1)
