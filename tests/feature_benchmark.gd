extends RefCounted
## Wall-clock duration, not a fixed frame count or inferred instantaneous FPS.
static func summarize(values: Array[float]) -> Dictionary:
    var ordered: Array[float] = values.duplicate()
    ordered.sort()
    var n := ordered.size()
    var total := 0.0
    var nonzero := 0
    for value in values:
        total += value
        if value > 0.0: nonzero += 1
    return {"sample_count":n,"mean_ms":total/maxi(n,1),"p50_ms":ordered[mini(n-1,int(n*.5))],"p95_ms":ordered[mini(n-1,int(n*.95))],"p99_ms":ordered[mini(n-1,int(n*.99))],"nonzero_samples":nonzero}

static func measure(viewport: Viewport) -> Dictionary:
    var rid := viewport.get_viewport_rid()
    RenderingServer.viewport_set_measure_render_time(rid,true)
    for i in range(120): await RenderingServer.frame_post_draw
    var wall: Array[float] = []
    var gpu: Array[float] = []
    var start := Time.get_ticks_usec()
    var previous := start
    var start_frame := Engine.get_frames_drawn()
    while Time.get_ticks_usec()-start < 30000000:
        await RenderingServer.frame_post_draw
        var now := Time.get_ticks_usec()
        wall.append(float(now-previous)/1000.0)
        gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
        previous = now
    var result := summarize(wall)
    result["gpu"] = summarize(gpu)
    result["duration_s"] = float(Time.get_ticks_usec()-start)/1000000.0
    result["rendered_frames"] = Engine.get_frames_drawn()-start_frame
    result["raw_frame_ms"] = wall
    result["raw_gpu_ms"] = gpu
    result["target_60fps_p95_met"] = result.p95_ms <= 16.667 and result.gpu.p95_ms <= 16.667
    result["scope"] = "30s wall-clock frame_post_draw intervals and engine viewport GPU timings; vsync disabled; fixed scene; not presentation latency"
    RenderingServer.viewport_set_measure_render_time(rid,false)
    return result

static func run(scene) -> Dictionary:
    var results: Dictionary = {}
    scene.lighting.apply_preset("day")
    var configs := {"background_off":[false,false,"standard","day"],"background_only":[true,false,"standard","day"],"standard":[true,true,"standard","day"],"strong":[true,true,"strong","day"],"night_standard":[true,true,"standard","night"]}
    for id in configs:
        var value: Array = configs[id]
        scene.background.visible = value[0]
        scene.lighting.environment.background_mode = Environment.BG_SKY if value[0] else Environment.BG_COLOR
        scene.lighting.apply_preset(value[3])
        scene.dof.select_profile(value[2])
        scene.dof.enabled = value[1]
        scene.dof.apply()
        results[id] = await measure(scene.get_viewport())
        print("BENCHMARK_COMPLETE ",id," duration=",results[id].duration_s," p95=",results[id].p95_ms)
    scene.dof.select_profile("standard")
    scene.dof.enabled = true
    scene.dof.apply()
    return results
