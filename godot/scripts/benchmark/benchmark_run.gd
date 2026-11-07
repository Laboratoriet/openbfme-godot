extends RefCounted
## Lane IOS-47: the benchmark, a scripted large battle in a skirmish game.gd started for it (--benchmark, or start_benchmark from Options >
## Performance: DEFAULT_MAP (Evendim), seed BENCHMARK_SEED, FactionMen against one AI; the start option test_hooks on, for the GameWorld hooks below).
##
##   the battle .. HORDES_PER_SIDE hordes for the local player (Gondor, Rohan, Elves) and as many for the opponent (Mordor, Isengard, Goblins) in two
##                 facing blocks across the map's middle, each ordered to attack the one facing it (GameWorld.create_object / order_attack, as
##                 uber1_player.gd). The templates are tried in order and the first that exists is used (EDAIN_WEST / EDAIN_EAST for Edain: its own
##                 units first; the results list the ones made). Deterministic: the same seed, places, orders and casts (by logic frame) every run
##   powers ...... at CAST_AT of the run (by the logic's frames) each side buys its spell book powers (debug_add_science_points, purchase_science) and casts the first usable
##                 ones that take a place at the battle's middle (spell_bar_press / spell_bar_click_world, as weatherfx1_player.gd)
##   the camera .. a fixed path through PATH's keys, by the run's time: low over the west block, along the front, a slow turn, up to the camera's
##                 highest zoom-out over the whole battle, back down (camera_look_at, camera_set_height, camera_set_angle_pitch)
##   measured .... every frame's time (Time.get_ticks_usec between frames) for `seconds` (default SECONDS) after SETTLE_S; every SAMPLE_S the fps of
##                 the last interval, the video memory (Performance RENDER_VIDEO_MEM_USED) and, on iOS, the battery and thermal state (the extension's
##                 IOSDeviceStatus; "n/a" elsewhere); the display settings in effect (the 3D scale and upscaler, MSAA / AA, HUD size, vsync, cap)
## The results (benchmark_stats.gd) are printed as BENCHMARK lines and saved to user://benchmarks/<date>-<variant>.json.

const Stats := preload("res://scripts/benchmark/benchmark_stats.gd")

const SECONDS := 120.0
const SETTLE_S := 3.0
const SAMPLE_S := 5.0
const HORDES_PER_SIDE := 24
const SPACING := 90.0
const GAP := 220.0
const CAST_AT := [0.3, 0.65]
const WEST := [["GondorFighterHorde"], ["GondorArcherHorde"], ["GondorTowerShieldGuardHorde", "GondorFighterHorde"], ["RohanRohirrimHorde", "RohanPeasantHorde", "GondorFighterHorde"],
	["ElvenLorienArcherHorde", "ElvenLorienWarriorHorde", "GondorArcherHorde"]]
const EAST := [["MordorFighterHorde"], ["MordorArcherHorde"], ["IsengardFighterHorde", "IsengardUrukHorde", "MordorFighterHorde"], ["IsengardPikemanHorde", "MordorFighterHorde"],
	["GoblinFighterHorde", "MordorArcherHorde"]]
## Edain's own units first (its data keeps retail's names too, so the retail lists would measure retail's battle with Edain loaded), retail's after
const EDAIN_WEST := [["DwarvenGuardianHorde", "GondorFighterHorde"], ["ArnorArcherHorde", "GondorArcherHorde"], ["GondorKnightHorde", "RohanRohirrimHorde"],
	["BruchtalSchwertkampferHorde", "GondorTowerShieldGuardHorde"], ["DwarvenAxeThrowerHorde", "ElvenLorienArcherHorde"]]
const EDAIN_EAST := [["DolguldurOrkHorde", "MordorFighterHorde"], ["DolguldurArcherHorde", "MordorArcherHorde"], ["AngmarHillTrollHorde", "IsengardFighterHorde"],
	["AngmarWolfReiterHorde", "IsengardPikemanHorde"], ["AngmarDarkDunedainHorde", "GoblinFighterHorde"]]
const LOGIC_FPS := 5.0  # the logic's frames per second (casts go by its frames: the same moment of the battle every run)
const SCIENCES := ["SCIENCE_Heal", "SCIENCE_ElvenAllies", "SCIENCE_Rebuild", "SCIENCE_EyeofSauron", "SCIENCE_Barricade", "SCIENCE_Darkness",
	"SCIENCE_WarChant", "SCIENCE_Fortify"]
## the camera path: [time (0 .. 1 of the run), offset from the battle's middle (world units), height (fraction of the camera's highest), turn (radians)]
const PATH := [[0.0, Vector2(-700, 0), 0.32, 0.0], [0.2, Vector2(-200, 150), 0.3, 0.35], [0.4, Vector2(250, -100), 0.38, 0.9],
	[0.6, Vector2(0, 0), 1.0, 1.4], [0.8, Vector2(0, 0), 1.0, 2.2], [1.0, Vector2(500, 0), 0.35, 2.6]]

var game: Node
var hud: Node
var world: Node
var log_prefix := "BENCHMARK"


func run(p_game: Node, variant: String, seconds := SECONDS) -> Dictionary:
	game = p_game
	hud = game._hud
	world = game._world
	var me := int(game._local_index)
	var foe := _opponent(me)
	if me < 0 or foe < 0:
		return {"error": "no local player or opponent"}
	var census: Dictionary = world.get_census()
	if not census.has("extent_x"):
		return {"error": "no census (no game)"}
	var centre := Vector2(float(census.extent_x) * 0.5, float(census.extent_y) * 0.5)
	var base_troops := int(census.troops)
	var unix := Time.get_unix_time_from_system()
	var started := Time.get_datetime_string_from_system(false, true)
	# the battle
	var west_t := _templates(EDAIN_WEST if variant == "edain" else WEST, me, centre)
	var east_t := _templates(EDAIN_EAST if variant == "edain" else EAST, foe, centre)
	if west_t.is_empty() or east_t.is_empty():
		return {"error": "no horde template of %s exists (west %s, east %s)" % [variant, west_t, east_t]}
	var west: Array = []
	var east: Array = []
	var rows := 6
	for i in HORDES_PER_SIDE:
		var col := i / rows
		var row := i % rows
		var y := centre.y + (row - (rows - 1) * 0.5) * SPACING
		var dx := GAP + col * SPACING
		var a: int = world.create_object(west_t[i % west_t.size()], me, centre.x - dx, y, 0.0)
		var b: int = world.create_object(east_t[i % east_t.size()], foe, centre.x + dx, y, PI)
		if a > 0:
			west.append(a)
		if b > 0:
			east.append(b)
	await game._step(4)
	for i in mini(west.size(), east.size()):
		world.order_attack([west[i]], east[i])
		world.order_attack([east[i]], west[i])
	var units := int(world.get_census().troops) - base_troops
	print("%s battle: %d + %d hordes (%d units) of %s / %s at %s" % [log_prefix, west.size(), east.size(), units, west_t, east_t, centre])
	world.debug_add_science_points(me, 1000)
	world.debug_add_science_points(foe, 1000)
	for s in SCIENCES:
		world.purchase_science(me, s)
		world.purchase_science(foe, s)
	# the camera's start, then SETTLE_S for the first orders and the effects to come in
	var cam: Dictionary = hud.get_camera()
	var top := float(cam.get("max_height", 400.0))
	var angle0 := float(cam.get("angle", 0.0))
	var pitch := float(cam.get("pitch", 0.6))
	_camera(centre, top, angle0, pitch, 0.0)
	var settle := Time.get_ticks_msec()
	while Time.get_ticks_msec() - settle < int(SETTLE_S * 1000.0):
		await game.get_tree().process_frame
	# the measured window
	var frames: Array = []
	var times: Array = []
	var samples: Array = []
	var casts := 0
	var cast_i := 0
	var vmem_peak := 0.0
	var f0: int = world.get_presented_frame()
	var w0 := Time.get_ticks_usec()
	var last := w0
	var sample_at := 0.0
	var sample_frames := 0
	var sample_us := w0
	while true:
		await game.get_tree().process_frame
		var now := Time.get_ticks_usec()
		var t := (now - w0) / 1000000.0
		if t >= seconds:
			break
		frames.append((now - last) / 1000.0)
		times.append(t)
		last = now
		sample_frames += 1
		_camera(centre, top, angle0, pitch, t / seconds)
		if cast_i < CAST_AT.size() and world.get_presented_frame() - f0 >= int(CAST_AT[cast_i] * seconds * LOGIC_FPS):
			casts += _cast(me, centre) + _cast(foe, centre)
			cast_i += 1
		if t - sample_at >= SAMPLE_S:
			var s := _sample(t, sample_frames / maxf(0.001, (now - sample_us) / 1000000.0))
			vmem_peak = maxf(vmem_peak, float(s.video_mem_mb))
			samples.append(s)
			print("%s %3.0f s of %.0f: %.1f fps, %.0f MB video memory, %d living units, battery %s, thermal %s" % [log_prefix, t, seconds, s.fps,
				s.video_mem_mb, int(world.get_census().troops) - base_troops, s.battery, s.thermal])
			sample_at = t
			sample_frames = 0
			sample_us = now
	var end_sample := _sample(seconds, sample_frames / maxf(0.001, (Time.get_ticks_usec() - sample_us) / 1000000.0))
	samples.append(end_sample)
	vmem_peak = maxf(vmem_peak, float(end_sample.video_mem_mb))
	var logic_frames: int = world.get_presented_frame() - f0
	var results := {
		"format": Stats.FORMAT,
		"version": Stats.VERSION,
		"variant": variant,
		"started": started,
		"seconds": seconds,
		"seed": int(game.get("_seed")),
		"map": str(game.get("_map_key")),
		"device": device(),
		"display": display(),
		"frames": Stats.summarise(frames, times),
		"video_mem_mb": {"peak": snappedf(vmem_peak, 0.1), "end": end_sample.video_mem_mb},
		"samples": samples,
		"battle": {"units": units, "hordes": west.size() + east.size(), "templates": west_t + east_t, "powers": casts,
			"living_at_end": int(world.get_census().troops) - base_troops},
		"logic": {"frames": logic_frames, "per_s": snappedf(logic_frames / seconds, 0.01)},
		"camera": PATH.map(func(k): return [k[0], [k[1].x, k[1].y], k[2], k[3]]),
	}
	var path := Stats.save(results, unix)
	results["file"] = path
	for l in Stats.lines(results):
		print("%s %s: %s" % [log_prefix, l[0], l[1]])
	print("%s results: %s" % [log_prefix, ProjectSettings.globalize_path(path) if not path.is_empty() else "NOT SAVED"])
	return results


func _opponent(me: int) -> int:
	for p in world.get_economy().get("players", []):
		if p.playable and int(p.index) != me:
			return int(p.index)
	return -1


## the first template of each candidate list that the game makes (tried once, away from the battle, and removed again)
func _templates(lists: Array, player: int, centre: Vector2) -> Array:
	var out: Array = []
	for candidates in lists:
		for t in candidates:
			if out.has(t):
				break
			var id: int = world.create_object(t, player, centre.x, centre.y - 2000.0, 0.0)
			if id > 0:
				world.destroy_object(id)
				out.append(t)
				break
	return out


## the camera at `u` (0 .. 1) of the path: its keys eased between (smoothstep), by the run's time
func _camera(centre: Vector2, top: float, angle0: float, pitch: float, u: float) -> void:
	var k := 0
	while k < PATH.size() - 2 and u > float(PATH[k + 1][0]):
		k += 1
	var a: Array = PATH[k]
	var b: Array = PATH[k + 1]
	var f := clampf((u - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0])), 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	hud.camera_look_at(centre + Vector2(a[1]).lerp(Vector2(b[1]), f))
	hud.camera_set_height(top * lerpf(float(a[2]), float(b[2]), f))
	hud.camera_set_angle_pitch(angle0 + lerpf(float(a[3]), float(b[3]), f), pitch)


## the first usable spell book powers of `player` that take a place, cast at the battle's middle; how many
func _cast(player: int, at: Vector2) -> int:
	var n := 0
	for b in world.get_spell_bar(player).get("buttons", []):
		if n >= 2:
			break
		if bool(b.get("usable", false)) and bool(b.get("needs_position", false)):
			if world.spell_bar_press(player, int(b.index)) and world.spell_bar_click_world(player, at.x, at.y):
				print("%s cast %s for player %d" % [log_prefix, b.power, player])
				n += 1
	return n


func _sample(t: float, fps: float) -> Dictionary:
	var s := {"at_s": snappedf(t, 0.1), "fps": snappedf(fps, 0.1),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1), "battery": -1.0, "battery_state": "n/a",
		"thermal": "n/a"}
	var ios := ios_status()
	if not ios.is_empty():
		s.battery = snappedf(float(ios.get("battery_level", -1.0)), 0.01)
		s.battery_state = str(ios.get("battery_state", "unknown"))
		s.thermal = str(ios.get("thermal_state", "unknown"))
	return s


## the extension's IOSDeviceStatus (iOS builds only): { battery_level, battery_state, thermal_state, low_power_mode, model }; {} elsewhere
static func ios_status() -> Dictionary:
	if not ClassDB.class_exists("IOSDeviceStatus"):
		return {}
	return ClassDB.class_call_static("IOSDeviceStatus", "status")


static func device() -> Dictionary:
	var model := OS.get_model_name()
	var ios := ios_status()
	if not ios.is_empty() and not str(ios.get("model", "")).is_empty():
		model = str(ios.model)
	var tree := Engine.get_main_loop() as SceneTree
	var size: Vector2i = tree.root.size if tree != null else Vector2i.ZERO
	return {"model": model, "os": "%s %s" % [OS.get_name(), OS.get_version()], "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "window": "%dx%d" % [size.x, size.y],
		"low_power_mode": bool(ios.get("low_power_mode", false)) if not ios.is_empty() else "n/a"}


## the display settings in effect (the window's, not the file's)
static func display() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var root: Window = tree.root if tree != null else null
	var scalers := {Viewport.SCALING_3D_MODE_BILINEAR: "bilinear", Viewport.SCALING_3D_MODE_FSR: "fsr", Viewport.SCALING_3D_MODE_FSR2: "fsr2",
		Viewport.SCALING_3D_MODE_METALFX_SPATIAL: "metalfx", Viewport.SCALING_3D_MODE_METALFX_TEMPORAL: "metalfx temporal"}
	var msaa := {Viewport.MSAA_DISABLED: "off", Viewport.MSAA_2X: "2x", Viewport.MSAA_4X: "4x", Viewport.MSAA_8X: "8x"}
	var opts := {}
	var touch := tree.root.get_node_or_null("TouchControls") if tree != null else null
	var scene := tree.current_scene if tree != null else null
	var go = scene.get("_game_options") if scene != null else null
	if go != null and go.has_method("current"):
		opts = go.current()
	var vsync := {DisplayServer.VSYNC_DISABLED: "off", DisplayServer.VSYNC_ENABLED: "on", DisplayServer.VSYNC_ADAPTIVE: "adaptive", DisplayServer.VSYNC_MAILBOX: "mailbox"}
	return {
		"render_scale": snappedf(root.scaling_3d_scale, 0.01) if root != null else 1.0,
		"scaler": scalers.get(root.scaling_3d_mode, str(root.scaling_3d_mode)) if root != null else "?",
		"msaa": msaa.get(root.msaa_3d, str(root.msaa_3d)) if root != null else "?",
		"aa": str(opts.get("OpenBFMEAntiAliasing", "?")),
		"hud_scale": str(opts.get("OpenBFMEHudScale", "?")),
		"vsync": vsync.get(DisplayServer.window_get_vsync_mode(), "?"),
		"max_fps": Engine.max_fps,
		"touch": touch != null and touch.has_method("is_active") and touch.is_active(),
	}
