extends RefCounted
## Sample completed render submissions and engine-provided viewport GPU timing.
static func measure(viewport: Viewport) -> Dictionary:
    var rid := viewport.get_viewport_rid()
    RenderingServer.viewport_set_measure_render_time(rid, true)
    for i in range(120):
        await RenderingServer.frame_post_draw
    var wall: Array[float] = []
    var gpu: Array[float] = []
    var previous := Time.get_ticks_usec()
    var first_draw := Engine.get_frames_drawn()
    for i in range(360):
        await RenderingServer.frame_post_draw
        var now := Time.get_ticks_usec()
        wall.append(float(now - previous) / 1000.0)
        gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
        previous = now
    var result := summarize(wall)
    result["scope"] = "wall-clock frame_post_draw interval; GPU timestamps recorded separately"
    result["rendered_frames"] = Engine.get_frames_drawn() - first_draw
    result["gpu"] = summarize(gpu)
    result["raw_frame_ms"] = wall
    result["raw_gpu_ms"] = gpu
    result["warmup_frames"] = 120
    result["vsync_requested"] = "disabled"
    result["target_60fps_p95_met"] = result.p95_ms <= 16.667 and result.gpu.p95_ms <= 16.667
    RenderingServer.viewport_set_measure_render_time(rid, false)
    return result

static func summarize(values: Array[float]) -> Dictionary:
    var ordered: Array[float] = values.duplicate()
    ordered.sort()
    var total := 0.0
    for value in values:
        total += value
    var mean := total / values.size()
    return {"sample_count": values.size(), "mean_ms": mean, "p50_ms": ordered[179], "p95_ms": ordered[341], "p99_ms": ordered[355], "nonzero_samples": values.filter(func(v): return v > 0.0).size()}
