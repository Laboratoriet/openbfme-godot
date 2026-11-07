## Smoke test of lane IOS-47's benchmark in the game: the game run headless with `--benchmark --benchmark-seconds=8` (the short variant) starts the
## benchmark's skirmish, makes the battle, runs the camera path and writes a results file that validates (benchmark_stats.gd), with frames,
## samples, the battle's hordes and units. Needs the game files (ROTWK_INSTALL, BFME2_INSTALL; SKIP without).
##
##   godot --headless --path godot --script res://tests/ios47_benchmark_run_test.gd
##
## Exit codes: 0 pass (or SKIP), 1 fail.
extends SceneTree

const Stats := preload("res://scripts/benchmark/benchmark_stats.gd")

var _failures := 0


func _initialize() -> void:
	_run()
	print("IOS47 BENCHMARK RUN %s" % ["PASS" if _failures == 0 else "FAIL"])
	quit(0 if _failures == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print("  ", "ok   " if ok else "FAIL ", what)
	if not ok:
		_failures += 1


func _run() -> void:
	if OS.get_environment("ROTWK_INSTALL").is_empty() or OS.get_environment("BFME2_INSTALL").is_empty():
		print("SKIP: the game run (set ROTWK_INSTALL and BFME2_INSTALL)")
		return
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--benchmark",
		"--benchmark-seconds=8", "--no-intro"], out, true)
	var text := "\n".join(out)
	var path := ""
	for line in text.split("\n"):
		if line.begins_with("BENCHMARK"):
			print("  | ", line)
		if line.begins_with("BENCHMARK results: "):
			path = Stats.DIR.path_join(line.trim_prefix("BENCHMARK results: ").strip_edges().get_file())  # the log hides the user's folder
	_check(code == 0 and text.contains("BENCHMARK DONE"), "the run ends with BENCHMARK DONE (exit %d)" % code)
	var r = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	_check(r is Dictionary, "the results file was written: %s" % path)
	if not r is Dictionary:
		return
	_check(Stats.validate(r).is_empty(), "it validates: %s" % [Stats.validate(r)])
	_check(float(r.seconds) == 8.0 and int(r.frames.frames) > 0 and r.samples.size() >= 2, "8 s, %d frames, %d samples" % [int(r.frames.frames), r.samples.size()])
	_check(int(r.battle.hordes) == 48 and int(r.battle.units) > 48 and int(r.seed) == 47047, "48 hordes, %d units, seed %d" % [int(r.battle.units), int(r.seed)])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
