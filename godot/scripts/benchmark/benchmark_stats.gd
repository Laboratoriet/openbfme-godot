extends RefCounted
## Lane IOS-47: the benchmark's numbers from its frame times, and its results file (scripts/benchmark/benchmark_run.gd records, this summarises).
## No game needed (tests/ios47_benchmark_test.gd checks it with frame times of its own).
##
## summarise(frames_ms, times_s): { frames, seconds, fps (frames / seconds), mean_ms, p50_ms, p95_ms, p99_ms, max_ms, low1_fps (1000 / p99),
## stalls: the STALLS worst frames over STALL_MS as [{ at_s, ms }] (worst first) }. Percentiles: the sorted frame times' value at index
## int(q * (n - 1)), GAME PERF's and fps_overlay.gd's rule.
##
## The results file (FORMAT, version VERSION): user://benchmarks/<YYYY-MM-DD_HH-MM-SS>-<variant>.json with
##   { format, version, variant, started (ISO), seconds, device: { model, os, renderer, adapter, window }, display: { render_scale, scaler, msaa,
##     aa, hud_scale, vsync, max_fps }, frames: summarise(), video_mem_mb: { peak, end }, samples: [{ at_s, fps, video_mem_mb, battery, battery_state,
##     thermal }], battle: { units, hordes, templates, powers }, logic: { frames, per_s }, camera: [the path's keys] }
## validate(results) lists what a results dictionary lacks (empty: a well-formed file).

const FORMAT := "openbfme-benchmark"
const VERSION := 1
const STALL_MS := 50.0   # a frame this long is a stall (GAME HITCH's bar, game.gd)
const STALLS := 5
const DIR := "user://benchmarks"


static func percentile(sorted: Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return float(sorted[int(q * (sorted.size() - 1))])


static func summarise(frames_ms: Array, times_s: Array) -> Dictionary:
	var n := frames_ms.size()
	if n == 0:
		return {"frames": 0, "seconds": 0.0, "fps": 0.0, "mean_ms": 0.0, "p50_ms": 0.0, "p95_ms": 0.0, "p99_ms": 0.0, "max_ms": 0.0, "low1_fps": 0.0,
			"stalls": []}
	var sorted := frames_ms.duplicate()
	sorted.sort()
	var sum := 0.0
	for t in frames_ms:
		sum += float(t)
	var stalls: Array = []
	for i in n:
		if float(frames_ms[i]) >= STALL_MS:
			stalls.append({"at_s": snappedf(float(times_s[i]) if i < times_s.size() else 0.0, 0.01), "ms": snappedf(float(frames_ms[i]), 0.1)})
	stalls.sort_custom(func(a, b): return a.ms > b.ms or (a.ms == b.ms and a.at_s < b.at_s))
	var p99 := percentile(sorted, 0.99)
	return {
		"frames": n,
		"seconds": snappedf(sum / 1000.0, 0.01),
		"fps": snappedf(n / maxf(sum / 1000.0, 0.001), 0.1),
		"mean_ms": snappedf(sum / n, 0.01),
		"p50_ms": snappedf(percentile(sorted, 0.5), 0.01),
		"p95_ms": snappedf(percentile(sorted, 0.95), 0.01),
		"p99_ms": snappedf(p99, 0.01),
		"max_ms": snappedf(float(sorted[n - 1]), 0.01),
		"low1_fps": snappedf(1000.0 / maxf(p99, 0.001), 0.1),
		"stall_count": stalls.size(),
		"stalls": stalls.slice(0, STALLS),
	}


## the file's name for a run that started at `unix` (local time) of `variant`
static func file_name(unix: float, variant: String) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(unix) + Time.get_time_zone_from_system().get("bias", 0) * 60)
	return "%04d-%02d-%02d_%02d-%02d-%02d-%s.json" % [d.year, d.month, d.day, d.hour, d.minute, d.second, variant]


## writes `results` into DIR (made when missing); the file's path, or "" (printerr says why)
static func save(results: Dictionary, unix: float) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join(file_name(unix, str(results.get("variant", "vanilla"))))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("BENCHMARK the results file %s could not be written: %s" % [path, error_string(FileAccess.get_open_error())])
		return ""
	f.store_string(JSON.stringify(results, "  ", false))
	f.close()
	return path


## what a results dictionary lacks or has wrong ([] when it is well formed)
static func validate(r: Dictionary) -> PackedStringArray:
	var bad := PackedStringArray()
	if r.get("format") != FORMAT:
		bad.append("format is %s" % r.get("format"))
	if int(r.get("version", 0)) != VERSION:
		bad.append("version is %s" % r.get("version"))
	if not str(r.get("variant", "")) in ["vanilla", "edain"]:
		bad.append("variant is %s" % r.get("variant"))
	for k in ["model", "os", "renderer", "adapter", "window"]:
		if not r.get("device", {}).has(k):
			bad.append("device.%s missing" % k)
	for k in ["render_scale", "scaler", "msaa", "aa", "hud_scale", "vsync", "max_fps"]:
		if not r.get("display", {}).has(k):
			bad.append("display.%s missing" % k)
	for k in ["frames", "fps", "mean_ms", "p95_ms", "p99_ms", "max_ms", "stalls"]:
		if not r.get("frames", {}).has(k):
			bad.append("frames.%s missing" % k)
	if int(r.get("frames", {}).get("frames", 0)) <= 0:
		bad.append("no frames")
	if not r.get("video_mem_mb", {}).has("peak"):
		bad.append("video_mem_mb.peak missing")
	var samples: Array = r.get("samples", [])
	if samples.is_empty():
		bad.append("no samples")
	for s in samples:
		for k in ["at_s", "fps", "video_mem_mb", "battery", "thermal"]:
			if not s.has(k):
				bad.append("a sample lacks %s" % k)
				return bad
	for k in ["units", "hordes", "templates", "powers"]:
		if not r.get("battle", {}).has(k):
			bad.append("battle.%s missing" % k)
	return bad


## the summary's lines (the card's and the log's): [[label, value], ...]
static func lines(r: Dictionary) -> Array:
	var f: Dictionary = r.get("frames", {})
	var d: Dictionary = r.get("display", {})
	var dev: Dictionary = r.get("device", {})
	var stalls: Array = f.get("stalls", [])
	var worst := "none over %d ms" % int(STALL_MS) if stalls.is_empty() else ", ".join(stalls.slice(0, 3).map(func(s): return "%.0f ms at %.1f s" % [s.ms, s.at_s]))
	var therm: Array = r.get("samples", []).map(func(s): return str(s.get("thermal", "n/a")))
	var batt: Array = r.get("samples", []).map(func(s): return float(s.get("battery", -1.0)))
	var battery := "n/a"
	if not batt.is_empty() and batt[0] >= 0.0:
		battery = "%d %% → %d %%" % [roundi(batt[0] * 100.0), roundi(batt[-1] * 100.0)]
	var thermal := "n/a" if therm.is_empty() or therm[0] == "n/a" else "%s → %s" % [therm[0], therm[-1]]
	return [
		["Average", "%.1f fps (%.1f ms)" % [f.get("fps", 0.0), f.get("mean_ms", 0.0)]],
		["Frame time p95 / p99", "%.1f / %.1f ms (1 %% low %.0f fps)" % [f.get("p95_ms", 0.0), f.get("p99_ms", 0.0), f.get("low1_fps", 0.0)]],
		["Worst stalls", worst],
		["Video memory", "%.0f MB peak" % float(r.get("video_mem_mb", {}).get("peak", 0.0))],
		["3D scale, upscaler", "%d %%, %s" % [roundi(float(d.get("render_scale", 1.0)) * 100.0), d.get("scaler", "?")]],
		["Anti-aliasing, HUD", "%s, HUD %s %%" % [d.get("aa", "?"), d.get("hud_scale", "?")]],
		["Battery, thermal", "%s, %s" % [battery, thermal]],
		["Device", "%s · %s · %s" % [dev.get("model", "?"), dev.get("renderer", "?"), dev.get("window", "?")]],
		["Battle", "%d units in %d hordes, %d powers cast" % [int(r.get("battle", {}).get("units", 0)), int(r.get("battle", {}).get("hordes", 0)),
			int(r.get("battle", {}).get("powers", 0))]],
	]
