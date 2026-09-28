extends RefCounted
## Same bounded camera sweep and frozen animation in every 30-second sample.
static func run(scene) -> Dictionary:
    var result: Dictionary = {}
    var viewport: Viewport = scene.get_viewport()
    var rid := viewport.get_viewport_rid()
    scene.rig.frozen = true
    scene.clock_frozen = true
    scene.background.wind_enabled = false
    scene.hud.container.hide()
    scene.lighting.apply_preset("day")
    scene.dof.select_profile("standard")
    scene.dof.enabled = true
    scene.dof.apply()
    for id in ["natural","soft","enhanced","maximum"]:
        scene.parallax.reset_all()
        scene.background.wind_enabled = false
        scene.parallax.select_preset(id if id != "maximum" else "custom")
        if id == "maximum": scene.parallax.change("global_strength",2.0)
        scene.rig.set_offset(Vector3.ZERO)
        scene.parallax.update(0,true)
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
            var seconds := float(now-start)/1000000.0
            scene.rig.set_offset(scene.parallax.right*sin(seconds*0.4)*7.5)
            scene.parallax.update(0,true)
        var stats: Dictionary = preload("res://tests/feature_benchmark.gd").summarize(wall)
        stats.gpu = preload("res://tests/feature_benchmark.gd").summarize(gpu)
        stats.duration_s = float(Time.get_ticks_usec()-start)/1000000.0
        stats.rendered_frames = Engine.get_frames_drawn()-start_frame
        stats.raw_frame_ms = wall
        stats.raw_gpu_ms = gpu
        stats.parameters = scene.parallax.snapshot()
        stats.target_60fps_p95_met = stats.p95_ms <= 16.667 and stats.gpu.p95_ms <= 16.667
        stats.scope = "30s wall-clock frame_post_draw; engine viewport GPU time; same +/-7.5m camera sweep; wind/water frozen; not display latency."
        result[id] = stats
        RenderingServer.viewport_set_measure_render_time(rid,false)
        print("P8_BENCHMARK ",id," p95=",stats.p95_ms," gpu=",stats.gpu.p95_ms)
    scene.parallax.reset_all()
    return result
