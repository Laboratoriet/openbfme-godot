## Headless test of lane IOS-47's benchmark numbers and results file (scripts/benchmark/benchmark_stats.gd), with frame times of its own: no game.
##  * summarise: the frame count, seconds, fps, mean, p50 / p95 / p99 (GAME PERF's index rule), the worst frame, the 1 % low, the stalls (frames of
##    50 ms or more, worst first, with their times);
##  * the results file: its name (<date>_<time>-<variant>.json), save writes JSON that reads back equal, validate passes a well-formed results
##    dictionary and names what a broken one lacks; the card's lines (benchmark_stats.gd lines) say n/a for the battery and thermal state off iOS.
## The game run is tests/ios47_benchmark_run_test.gd (the game files).
##
##   godot --headless --path godot --script res://tests/ios47_benchmark_test.gd
##
## Exit codes: 0 pass, 1 fail.
extends SceneTree

const Stats := preload("res://scripts/benchmark/benchmark_stats.gd")
const Run := preload("res://scripts/benchmark/benchmark_run.gd")
const Card := preload("res://scripts/benchmark/benchmark_card.gd")

var _failures := 0


func _initialize() -> void:
	_run()
	await _card()
	print("IOS47 BENCHMARK %s" % ["PASS" if _failures == 0 else "FAIL"])
	quit(0 if _failures == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print("  ", "ok   " if ok else "FAIL ", what)
	if not ok:
		_failures += 1


func _run() -> void:
	# 200 frames: 196 of 16 ms, then 20, 60 (at 1.5 s), 80 (at 2.25 s) and 100 ms (at 3.0 s)
	var frames: Array = []
	var times: Array = []
	for i in 196:
		frames.append(16.0)
		times.append(i * 0.016)
	for x in [[20.0, 1.0], [60.0, 1.5], [80.0, 2.25], [100.0, 3.0]]:
		frames.append(x[0])
		times.append(x[1])
	var s := Stats.summarise(frames, times)
	var total := 196 * 16.0 + 20.0 + 60.0 + 80.0 + 100.0
	_check(s.frames == 200 and is_equal_approx(s.seconds, snappedf(total / 1000.0, 0.01)), "200 frames over %.2f s: %s" % [total / 1000.0, s])
	_check(is_equal_approx(s.mean_ms, snappedf(total / 200.0, 0.01)) and is_equal_approx(s.fps, snappedf(200.0 / (total / 1000.0), 0.1)),
		"mean %.2f ms, %.1f fps" % [s.mean_ms, s.fps])
	# sorted: 196 x 16, 20, 60, 80, 100: p50 index 99 -> 16, p95 index 189 -> 16, p99 index 197 -> 60
	_check(s.p50_ms == 16.0 and s.p95_ms == 16.0 and s.p99_ms == 60.0 and s.max_ms == 100.0, "p50 16, p95 16, p99 60, max 100: %s %s %s %s" % [
		s.p50_ms, s.p95_ms, s.p99_ms, s.max_ms])
	_check(is_equal_approx(s.low1_fps, snappedf(1000.0 / 60.0, 0.1)), "1 %% low is 1000 / p99: %s" % s.low1_fps)
	_check(s.stall_count == 3 and s.stalls == [{"at_s": 3.0, "ms": 100.0}, {"at_s": 2.25, "ms": 80.0}, {"at_s": 1.5, "ms": 60.0}],
		"the stalls (>= 50 ms), worst first, with their times: %s" % [s.stalls])
	_check(Stats.summarise([], []).frames == 0, "no frames: zeros, no error")
	_check(Stats.file_name(0.0, "edain").ends_with("-edain.json") and Stats.file_name(0.0, "edain").length() == "YYYY-MM-DD_HH-MM-SS-edain.json".length(),
		"the file's name: %s" % Stats.file_name(0.0, "edain"))
	# a results dictionary as benchmark_run.gd makes it (the device and display parts read from this process)
	var r := {"format": Stats.FORMAT, "version": Stats.VERSION, "variant": "vanilla", "started": "2026-11-07T23:00:00", "seconds": 8.0, "seed": 47047,
		"map": "maps/map mp evendim/map mp evendim.map", "device": Run.device(), "display": Run.display(), "frames": s,
		"video_mem_mb": {"peak": 812.5, "end": 800.0}, "samples": [{"at_s": 5.0, "fps": 60.0, "video_mem_mb": 812.5, "battery": -1.0,
		"battery_state": "n/a", "thermal": "n/a"}], "battle": {"units": 480, "hordes": 48, "templates": ["GondorFighterHorde"], "powers": 2}}
	_check(Stats.validate(r).is_empty(), "a well-formed results dictionary validates: %s" % [Stats.validate(r)])
	var broken := r.duplicate(true)
	broken.erase("display")
	broken.frames.erase("p99_ms")
	broken.samples = []
	broken.variant = "x"
	var why := Stats.validate(broken)
	_check(why.has("variant is x") and why.has("display.render_scale missing") and why.has("frames.p99_ms missing") and why.has("no samples"),
		"a broken one names what it lacks: %s" % [why])
	var path := Stats.save(r, Time.get_unix_time_from_system())
	var back = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null
	_check(back is Dictionary and Stats.validate(back).is_empty() and back.frames.p99_ms == 60.0 and back.variant == "vanilla",
		"saved to %s and read back the same" % path)
	if not path.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var lines := Stats.lines(r)
	_check(lines.size() == 9 and lines[6][1] == "n/a, n/a" and lines[0][1].begins_with("%.1f fps" % s.fps), "the card's lines (battery, thermal n/a off iOS): %s" % [lines])
	_check(not ClassDB.class_exists("IOSDeviceStatus") and Run.ios_status().is_empty(), "off iOS there is no IOSDeviceStatus: the status is {}")
	_results = r


var _results := {}


## the summary card in the Mac stand-in's window (1335 x 939, 1.5 px per point): inside the view, the Close button 44 pt high; Close emits closed
func _card() -> void:
	var stage := SubViewport.new()
	stage.size = Vector2i(1335, 939)
	root.add_child(stage)
	var card: CanvasLayer = Card.new()
	stage.add_child(card)
	await process_frame
	card.show_results(_results, 1.5)
	await process_frame
	var rect: Rect2 = card.panel_rect()
	_check(Rect2(Vector2.ZERO, Vector2(1335, 939)).encloses(rect.grow(-1.0)) and rect.size.y < 939.0 * 0.9, "the card fits the window: %s" % [rect])
	_check(card._button.size.y >= 44.0 * 1.5, "Close is 44 pt high: %s" % [card._button.size])
	var got := [false]
	card.closed.connect(func() -> void: got[0] = true)
	card._close()
	_check(got[0], "Close emits closed")
