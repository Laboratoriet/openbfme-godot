extends Node
## Lane IOS-7: `-- --gpu-probe` prints the root viewport's measured render time every 5 s, so a frame-capped run (the game paces to the
## display) still tells what a frame costs: GPU and CPU (render thread) ms per frame (RenderingServer.viewport_get_measured_render_time_*),
## the frame rate, and the video and texture memory in use. Lines start "GPU PROBE"; nothing else changes.

const WINDOW_S := 5.0

var _rid: RID
var _gpu := PackedFloat32Array()
var _cpu := PackedFloat32Array()
var _t := 0.0


func _ready() -> void:
	_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	print("GPU PROBE on: %s, %s, window %s, 3D scale %.2f mode %d" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(),
		str(get_window().size), get_window().scaling_3d_scale, get_window().scaling_3d_mode])


func _process(delta: float) -> void:
	_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_rid))
	_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(_rid))
	_t += delta
	if _t < WINDOW_S:
		return
	print("GPU PROBE gpu_ms mean %.2f p95 %.2f | cpu_ms mean %.2f p95 %.2f | fps %.0f | video_mem %.0f MB texture_mem %.0f MB | 3D scale %.2f mode %d" % [
		_mean(_gpu), _p95(_gpu), _mean(_cpu), _p95(_cpu), Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		get_window().scaling_3d_scale, get_window().scaling_3d_mode])
	_gpu.clear()
	_cpu.clear()
	_t = 0.0


static func _mean(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(1.0, a.size())


static func _p95(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[mini(b.size() - 1, int(b.size() * 0.95))]
