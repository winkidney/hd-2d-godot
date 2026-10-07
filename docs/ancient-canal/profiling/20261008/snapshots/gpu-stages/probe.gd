extends SceneTree
## Real-time 1080p offscreen workload. No screenshot readback enters sampling.
## Run off screen with --disable-render-loop, never with --fixed-fps.
const ENTRY := "res://scenes/ancient_canal.tscn"
const EVIDENCE_ROOT := "res://build/ancient-canal"
const SIZE := Vector2i(1920,1080)
const WARMUP_SECONDS := 3.0
const SAMPLE_SECONDS := 8.0
const TARGET_MS := 1000.0/60.0
const PERIODS := ["baseline/dusk"]
var viewport: SubViewport
var scene: Node3D
var output := EVIDENCE_ROOT+"/performance"
var runtime_fingerprint := ""
var drawing := false
var loop_route := false
var completed_routes := 0
var failed_routes: Array[Dictionary] = []
var report: Dictionary = {}
var failures: Array[String] = []
var launch_state: Dictionary = {}
var forced_draw_requests := 0
var requesting_forced_draw := false
var pre_draw_events := 0
var post_draw_events := 0
var forced_pre_draw_events := 0
var resource_pre_draw_events := 0
var forced_draw_completions := 0
var resource_draw_completions := 0
var unmatched_post_draw_events := 0
var pending_draws: Array[Dictionary] = []
var last_completed_draw: Dictionary = {}
const COUNTER_SOURCE_COMMIT := "ed1daf0bf001b61586d9930840f2f1394092c079"
const COUNTER_SCOPE := "Every RenderingServer draw has one pre/post pair. Direct force_draw requests do not increment Engine.get_frames_drawn; with the normal render loop disabled, the main loop still draws pending resources and increments that engine counter after requesting the draw. All completed 1080p draws, including those resource-processing draws, enter the wall-clock throughput samples. GPU/CPU timers may describe an earlier draw; post_draw is not a GPU fence or display presentation."

func on_pre_draw() -> void:
    pre_draw_events += 1
    if requesting_forced_draw:
        forced_pre_draw_events += 1
    else:
        resource_pre_draw_events += 1
    pending_draws.append({"pre_id":pre_draw_events,"forced_request_id":forced_draw_requests if requesting_forced_draw else 0,"source":"forced" if requesting_forced_draw else "resource-processing","pre_usec":Time.get_ticks_usec()})

func on_post_draw() -> void:
    post_draw_events += 1
    if pending_draws.is_empty():
        unmatched_post_draw_events += 1
        last_completed_draw = {}
        return
    # RenderingServer submits draws in order. Pair each completion with its pre
    # event, including resource-processing draws outside our force_draw calls.
    last_completed_draw = pending_draws.pop_front()
    last_completed_draw.post_id = post_draw_events
    if last_completed_draw.source=="forced":
        forced_draw_completions += 1
    else:
        resource_draw_completions += 1

func counter_snapshot() -> Dictionary:
    var pending_forced := 0
    for draw in pending_draws:
        if draw.source=="forced":
            pending_forced += 1
    return {"forced_requests":forced_draw_requests,"pre_events":pre_draw_events,"post_events":post_draw_events,"forced_pre_events":forced_pre_draw_events,"resource_pre_events":resource_pre_draw_events,"forced_completions":forced_draw_completions,"resource_completions":resource_draw_completions,"unmatched_post_events":unmatched_post_draw_events,"pending_total":pending_draws.size(),"pending_forced":pending_forced,"pending_resource":pending_draws.size()-pending_forced,"engine_main_loop_draws":Engine.get_frames_drawn(),"last_completed_pre_id":int(last_completed_draw.get("pre_id",0))}

func counter_validation(before: Dictionary, after: Dictionary, post_ids: Array[int], pre_ids: Array[int]) -> Dictionary:
    var deltas := {}
    for key in before:
        deltas[key] = int(after[key])-int(before[key])
    var unique_post := true
    var unique_pre := true
    for index in post_ids.size():
        unique_post = unique_post and post_ids[index]==int(before.post_events)+index+1
        unique_pre = unique_pre and pre_ids[index]==int(before.last_completed_pre_id)+index+1
    # A main-loop draw increments Engine's counter after draw() returns. A
    # post_draw sampling boundary can fall immediately before that increment.
    var resource_engine_boundary_difference: int = deltas.resource_pre_events-deltas.engine_main_loop_draws
    var checks := {"post_ids_unique_consecutive":unique_post,"completed_pre_ids_unique_consecutive":unique_pre,"post_samples_match_events":deltas.post_events==post_ids.size(),"paired_completion_samples":pre_ids.size()==post_ids.size() and deltas.forced_completions+deltas.resource_completions==post_ids.size(),"no_unmatched_post_events":deltas.unmatched_post_events==0,"forced_requests_match_pre_events":deltas.forced_requests==deltas.forced_pre_events,"pre_events_match_all_requests":deltas.pre_events==deltas.forced_requests+deltas.resource_pre_events,"all_draws_reconcile_with_pending":deltas.pre_events-deltas.post_events==deltas.pending_total,"forced_draws_reconcile_with_pending":deltas.forced_requests-deltas.forced_completions==deltas.pending_forced,"resource_draws_reconcile_with_pending":deltas.resource_pre_events-deltas.resource_completions==deltas.pending_resource,"engine_counts_resource_draws_at_boundary":absi(resource_engine_boundary_difference)<=1}
    return {"passed":checks.values().all(func(value): return value),"checks":checks,"deltas":deltas,"resource_engine_boundary_difference":resource_engine_boundary_difference,"engine_resource_offset_before":int(before.engine_main_loop_draws)-int(before.resource_pre_events),"engine_resource_offset_after":int(after.engine_main_loop_draws)-int(after.resource_pre_events),"scope":COUNTER_SCOPE,"official_source_commit":COUNTER_SOURCE_COMMIT}

func actual_launch_state() -> Dictionary:
    # OS.get_cmdline_args omits options already consumed by Godot startup.
    # Read Linux's actual argv without retaining its paths in any report.
    var evidence := {"process_args_read":false,"process_cmdline_complete":false,"process_cmdline_argc":0,"fixed_fps_flag_present":null,"engine_render_loop_query_available":ClassDB.class_has_method("RenderingServer","is_render_loop_enabled"),"engine_render_loop_enabled":null}
    if evidence.engine_render_loop_query_available:
        var enabled = RenderingServer.call("is_render_loop_enabled")
        evidence.engine_render_loop_query_available = enabled is bool
        if enabled is bool: evidence.engine_render_loop_enabled = enabled
    var file := FileAccess.open("/proc/self/cmdline",FileAccess.READ)
    if file==null:
        return evidence
    # proc reports stat size zero; read directly and require a complete NUL list.
    var bytes := file.get_buffer(65536)
    file.close()
    if bytes.is_empty() or bytes.size()>=65536 or bytes[-1]!=0:
        return evidence
    var current := PackedByteArray()
    var fixed := false
    for byte in bytes:
        if byte==0:
            var argument := current.get_string_from_utf8()
            fixed = fixed or argument=="--fixed-fps" or argument.begins_with("--fixed-fps=")
            evidence.process_cmdline_argc += 1
            current.clear()
        else:
            current.append(byte)
    evidence.process_args_read = true
    evidence.process_cmdline_complete = true
    evidence.fixed_fps_flag_present = fixed
    return evidence

func _initialize() -> void:
    # Persistent observers are connected before coroutine awaits. Signal
    # emission snapshots its connections, so reconnecting the await cannot
    # receive the same emission again; these observers independently verify it.
    RenderingServer.frame_pre_draw.connect(on_pre_draw)
    RenderingServer.frame_post_draw.connect(on_post_draw)
    root.transparent_bg = false
    root.gui_embed_subwindows = true
    RenderingServer.set_default_clear_color(Color.BLACK)
    viewport = SubViewport.new()
    viewport.size = SIZE
    viewport.own_world_3d = true
    viewport.gui_embed_subwindows = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--canal-output="):
            output = arg.trim_prefix("--canal-output=")
        elif arg.begins_with("--canal-fingerprint="):
            runtime_fingerprint = arg.trim_prefix("--canal-fingerprint=")
    call_deferred("run")

func _process(_delta: float) -> bool:
    if loop_route and is_instance_valid(scene) and not scene.route_running:
        var result: Dictionary = scene.route_result
        if bool(result.get("passed",false)):
            completed_routes += 1
        else:
            failed_routes.append({"frames":int(result.get("frames",0)),"cancelled":bool(result.get("cancelled",false))})
            loop_route = false
        if loop_route:
            scene.start_route()
    if drawing:
        forced_draw_requests += 1
        requesting_forced_draw = true
        RenderingServer.force_draw()
        requesting_forced_draw = false
    return false

func fail(reason: String) -> void:
    failures.append(reason)
    print("CANAL_BENCHMARK_FAIL ",reason)

func valid_fingerprint(value: String) -> bool:
    if value.length()!=64:
        return false
    for letter in value.to_lower():
        if not "0123456789abcdef".contains(letter):
            return false
    return true

func quantile(ordered: Array[float], fraction: float) -> float:
    if ordered.is_empty():
        return 0.0
    var point: float = float(ordered.size()-1)*fraction
    var lo := int(floor(point))
    var hi := int(ceil(point))
    return lerpf(ordered[lo],ordered[hi],point-lo)

func summarize(samples: Array[float]) -> Dictionary:
    var ordered: Array[float] = samples.duplicate()
    ordered.sort()
    var total := 0.0
    var nonzero := 0
    for number in ordered:
        total += number
        if number>0:
            nonzero += 1
    return {"sample_count":samples.size(),"nonzero_samples":nonzero,"mean_ms":total/maxi(samples.size(),1),"p50_ms":quantile(ordered,.5),"p95_ms":quantile(ordered,.95),"p99_ms":quantile(ordered,.99)}

func portable_path(path: String) -> String:
    return path.trim_prefix(EVIDENCE_ROOT+"/")

func save_json(path: String, value: Dictionary) -> bool:
    var file := FileAccess.open(path,FileAccess.WRITE)
    if file==null:
        fail("Cannot write "+portable_path(path))
        return false
    file.store_string(JSON.stringify(value,"  ")+"\n")
    file.flush()
    var error := file.get_error()
    file.close()
    if error!=OK:
        fail("Write failed: "+portable_path(path))
    return error==OK

func measure(period: String) -> Dictionary:
    loop_route = false
    scene.restore_defaults()
    scene.player.position = scene.vec(scene.layout.player_spawn)
    scene.player.velocity = Vector3.ZERO
    scene.player.set_physics_process(true)
    scene.frozen = false
    scene.overlay.show()
    scene.console.close()
    scene.apply_time_preset(period.split("/")[1])
    scene.camera_update(0,true)
    scene.sync_input()

    var case_id := period.split("/")[0]
    scene.farfield.layers.near_town.show()
    scene.farfield.layers.far_town.show()
    match case_id:
        "no_ssr": scene.environment.ssr_enabled = false
        "no_ssao": scene.environment.ssao_enabled = false
        "no_dof": scene.attributes.dof_blur_near_enabled = false; scene.attributes.dof_blur_far_enabled = false
        "no_glow": scene.environment.glow_enabled = false
        "no_shadows":
            scene.main_light.shadow_enabled = false
            for lamp in scene.lamp_nodes.values(): lamp.shadow_enabled = false
        "no_local_shadows":
            for lamp in scene.lamp_nodes.values(): lamp.shadow_enabled = false
        "no_main_shadow": scene.main_light.shadow_enabled = false
        "no_broad_shadows":
            for lamp in scene.broad_lights: lamp.shadow_enabled = false
        "no_near_town": scene.farfield.layers.near_town.hide()
        "no_far_town": scene.farfield.layers.far_town.hide()
        "no_normals": scene.values.normals_enabled = false; scene.apply_parameters()
        "no_msaa": viewport.msaa_3d = Viewport.MSAA_DISABLED
        "scale_075": viewport.scaling_3d_scale = .75
        "no_post":
            scene.environment.ssr_enabled = false
            scene.environment.ssao_enabled = false
            scene.environment.glow_enabled = false
            scene.attributes.dof_blur_near_enabled = false
            scene.attributes.dof_blur_far_enabled = false
    # The live scene updates DOF every frame; change the owning values as well.
    if case_id in ["no_dof","no_post"]:
        scene.values.dof_near = false
        scene.values.dof_far = false
    viewport.msaa_3d = Viewport.MSAA_DISABLED if case_id=="no_msaa" else Viewport.MSAA_2X
    viewport.scaling_3d_scale = .75 if case_id=="scale_075" else 1.0
    var inventory := {"mesh_instances":0,"surfaces":0,"triangles":0,"unique_meshes":{},"unique_materials":{},"shadow_lights":0}
    for mesh in scene.find_children("*","MeshInstance3D",true,false):
        inventory.mesh_instances += 1
        inventory.unique_meshes[str(mesh.mesh.get_instance_id())] = true
        for surface in mesh.mesh.get_surface_count():
            inventory.surfaces += 1
            var arrays: Array = mesh.mesh.surface_get_arrays(surface)
            inventory.triangles += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size())/3
            var mat: Material = mesh.get_active_material(surface)
            if mat!=null: inventory.unique_materials[str(mat.get_instance_id())] = true
    inventory.unique_meshes = inventory.unique_meshes.size()
    inventory.unique_materials = inventory.unique_materials.size()
    for lamp in scene.lamp_nodes.values():
        if lamp.visible and lamp.shadow_enabled: inventory.shadow_lights += 1
    inventory.main_shadow = scene.main_light.shadow_enabled
    inventory.msaa_3d = viewport.msaa_3d
    inventory.scaling_3d_scale = viewport.scaling_3d_scale
    inventory.ssao = scene.environment.ssao_enabled
    inventory.ssr = scene.environment.ssr_enabled
    inventory.dof = scene.attributes.dof_blur_far_enabled

    completed_routes = 0
    failed_routes.clear()
    scene.start_route()
    loop_route = true
    var rid: RID = viewport.get_viewport_rid()
    RenderingServer.viewport_set_measure_render_time(rid,true)
    var warmup_start := Time.get_ticks_usec()
    while float(Time.get_ticks_usec()-warmup_start)/1000000.0 < WARMUP_SECONDS:
        await RenderingServer.frame_post_draw
    var warmup_elapsed := float(Time.get_ticks_usec()-warmup_start)/1000000.0
    var setup_times: Array[float] = []
    var render_counts: Array = []
    var timestamp_frames: Array = []
    var last_timestamp_frame := -1
    var intervals: Array[float] = []
    var gpu_times: Array[float] = []
    var cpu_times: Array[float] = []
    var frame_ids: Array[int] = []
    var post_ids: Array[int] = []
    var pre_ids: Array[int] = []
    var request_ids: Array[int] = []
    var draw_sources: Array[String] = []
    var pre_times: Array[int] = []
    var counter_before := counter_snapshot()
    var physics_before := Engine.get_physics_frames()
    var draw_before := Engine.get_frames_drawn()
    var sample_start := Time.get_ticks_usec()
    var previous := sample_start
    while float(Time.get_ticks_usec()-sample_start)/1000000.0 < SAMPLE_SECONDS:
        await RenderingServer.frame_post_draw
        var now := Time.get_ticks_usec()
        intervals.append(float(now-previous)/1000.0)
        gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
        cpu_times.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
        frame_ids.append(Engine.get_frames_drawn())
        post_ids.append(post_draw_events)
        pre_ids.append(int(last_completed_draw.get("pre_id",0)))
        request_ids.append(int(last_completed_draw.get("forced_request_id",0)))
        draw_sources.append(str(last_completed_draw.get("source","unmatched")))
        pre_times.append(int(last_completed_draw.get("pre_usec",0)))

        setup_times.append(RenderingServer.get_frame_setup_time_cpu())
        if intervals.size()%10==0:
            render_counts.append({"draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"objects":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_OBJECTS_IN_FRAME),"primitives":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"shadow_draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
            var rd := RenderingServer.get_rendering_device()
            var timestamp_frame := rd.get_captured_timestamps_frame()
            if timestamp_frame!=last_timestamp_frame:
                last_timestamp_frame = timestamp_frame
                var markers: Array = []
                for i in rd.get_captured_timestamps_count():
                    markers.append({"name":rd.get_captured_timestamp_name(i),"gpu_us":rd.get_captured_timestamp_gpu_time(i),"cpu_us":rd.get_captured_timestamp_cpu_time(i)})
                timestamp_frames.append({"frame":timestamp_frame,"markers":markers})

        previous = now
    var counter_after := counter_snapshot()
    var counters := counter_validation(counter_before,counter_after,post_ids,pre_ids)
    var elapsed := float(previous-sample_start)/1000000.0
    var physics_after := Engine.get_physics_frames()
    var rendered := Engine.get_frames_drawn()-draw_before
    loop_route = false
    scene.cancel_route()
    RenderingServer.viewport_set_measure_render_time(rid,false)
    var wall := summarize(intervals)
    var gpu := summarize(gpu_times)
    var cpu := summarize(cpu_times)
    var samples_path := output.path_join(period.replace("/","-")+"-samples.json")
    var raw := {"schema_version":2,"runtime_fingerprint":runtime_fingerprint,"period":period,"mode":"real-time","viewport":[SIZE.x,SIZE.y],"warmup_elapsed_s":warmup_elapsed,"elapsed_s":elapsed,"frame_intervals_ms":intervals,"gpu_timings_ms":gpu_times,"cpu_timings_ms":cpu_times,"render_frame_ids":frame_ids,"server_post_draw_ids":post_ids,"completed_pre_draw_ids":pre_ids,"completed_forced_request_ids":request_ids,"completed_draw_sources":draw_sources,"completed_pre_draw_ticks_usec":pre_times,"counter_snapshot_before":counter_before,"counter_snapshot_after":counter_after,"draw_counters":counters,"forced_draw_requests":counters.deltas.forced_requests,"resource_processing_draw_requests":counters.deltas.resource_pre_events,"server_pre_draw_events":counters.deltas.pre_events,"server_post_draw_events":counters.deltas.post_events,"post_draw_sample_count":intervals.size(),"engine_main_loop_draw_frames":rendered,"rendered_frames_scope":"Engine main-loop draws only; excludes direct force_draw. See draw_counters for all requested/completed draws.","physics_frames":physics_after-physics_before,"rendered_frames":rendered,"time_scale":Engine.time_scale,"physics_ticks_per_second":Engine.physics_ticks_per_second,"readback_count":0,"render_cap_fps":Engine.max_fps,"fixed_fps":launch_state.fixed_fps_flag_present,"workload":"repeating actual CharacterBody3D exploration route, animation, collision, follow, parallax, water and HUD"}
    raw.merge(launch_state,true)
    raw.merge({"inventory":inventory,"frame_setup_cpu_ms":setup_times,"render_counts":render_counts,"timestamp_frames":timestamp_frames})
    var saved := save_json(samples_path,raw)
    var intervals_valid := intervals.all(func(number): return is_finite(number) and number>0.0)
    var timers_valid := gpu_times.all(func(number): return is_finite(number) and number>=0.0) and cpu_times.all(func(number): return is_finite(number) and number>=0.0)
    var valid: bool = saved and elapsed>=SAMPLE_SECONDS and warmup_elapsed>=WARMUP_SECONDS and intervals.size()>=100 and intervals_valid and timers_valid and failed_routes.is_empty() and bool(counters.passed)
    if not valid:
        fail("Incomplete real-time sample "+period)
    if int(gpu.nonzero_samples)==0:
        fail("GPU timing unavailable for "+period)
    var result := {"passed":valid,"duration_s":elapsed,"warmup_s":warmup_elapsed,"size":[SIZE.x,SIZE.y],"viewport":[SIZE.x,SIZE.y],"sample_count":intervals.size(),"samples_path":portable_path(samples_path),"sha256":FileAccess.get_sha256(samples_path) if saved else "","p50_ms":wall.p50_ms,"p95_ms":wall.p95_ms,"p99_ms":wall.p99_ms,"mean_ms":wall.mean_ms,"gpu":gpu,"cpu":cpu,"gpu_timing_available":int(gpu.nonzero_samples)>0,"cpu_timing_available":int(cpu.nonzero_samples)>0,"target_60fps_p95_met":float(wall.p95_ms)<=TARGET_MS,"gpu_p95_within_60fps_budget":int(gpu.nonzero_samples)>0 and float(gpu.p95_ms)<=TARGET_MS,"completed_routes":completed_routes,"failed_routes":failed_routes.duplicate(true),"rendered_frames":rendered,"engine_main_loop_draw_frames":rendered,"forced_draw_requests":counters.deltas.forced_requests,"resource_processing_draw_requests":counters.deltas.resource_pre_events,"server_pre_draw_events":counters.deltas.pre_events,"server_post_draw_events":counters.deltas.post_events,"draw_counters":counters,"physics_frames":physics_after-physics_before,"scope":"30 seconds of all completed-draw wall-clock intervals, including forced and resource-processing draws, for a real-time 1080p moving exploration workload; viewport GPU and CPU render timers separate; no PNG readback, no fixed FPS simulation; measures offscreen rendering throughput, not display presentation or input latency"}
    result["inventory"] = inventory
    result["frame_setup_cpu"] = summarize(setup_times)
    print("CANAL_BENCHMARK_PERIOD ",period," duration=",elapsed," p95_ms=",wall.p95_ms," gpu_p95_ms=",gpu.p95_ms," cpu_p95_ms=",cpu.p95_ms)
    return result

func run() -> void:
    if not output.begins_with(EVIDENCE_ROOT+"/") or output.contains(".."):
        fail("Output must remain within the independent Jiangnan evidence directory.")
        quit(2)
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
    launch_state = actual_launch_state()
    if not launch_state.process_args_read:
        fail("Cannot verify the actual Linux process command line.")
    elif launch_state.fixed_fps_flag_present:
        fail("An actual --fixed-fps process flag cannot measure real-time performance.")
    if not launch_state.engine_render_loop_query_available:
        fail("Cannot verify the engine's actual render-loop state.")
    elif launch_state.engine_render_loop_enabled:
        fail("Disable the normal engine render loop to separate forced requests from resource-processing draws.")
    if DisplayServer.get_name()=="headless":
        fail("A real GPU display driver is required.")
    if not is_equal_approx(Engine.time_scale,1.0) or Engine.physics_ticks_per_second!=60:
        fail("Benchmark requires original time_scale 1 and 60 Hz physics.")
    if "--ignore-user-settings" not in OS.get_cmdline_user_args() and "--canal-test" not in OS.get_cmdline_user_args():
        fail("Refusing to load everyday preferences without an isolation flag.")
    if not runtime_fingerprint.is_empty() and not valid_fingerprint(runtime_fingerprint):
        fail("Invalid runtime fingerprint.")
    if not failures.is_empty():
        report = {"schema_version":1,"passed":false,"failures":failures,"mode":"real-time","presets":{},"runtime_fingerprint":runtime_fingerprint}
        report.merge(launch_state,true)
        save_json(output.path_join("performance-report.json"),report)
        quit(2)
        return
    # Window creation can override flags from _initialize. Apply once after start.
    root.size = Vector2i(64,64)
    root.set_flag(Window.FLAG_NO_FOCUS,true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    OS.low_processor_usage_mode = false
    Engine.max_fps = 0
    drawing = true
    scene = load(ENTRY).instantiate()
    viewport.add_child(scene)
    for index in 20:
        await physics_frame
    var adapter := RenderingServer.get_video_adapter_name()
    var hardware := not adapter.is_empty() and not adapter.to_lower().contains("llvmpipe") and not adapter.to_lower().contains("lavapipe") and not adapter.to_lower().contains("swiftshader")
    if not hardware:
        fail("Hardware GPU unavailable.")
    if RenderingServer.get_current_rendering_method()!="forward_plus":
        fail("Forward+ renderer is required.")
    if viewport.size!=SIZE:
        fail("Viewport size changed.")
    report = {"schema_version":1,"runtime_fingerprint":runtime_fingerprint,"gpu":adapter,"adapter":adapter,"hardware_gpu":hardware,"renderer":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info().string,"viewport":[SIZE.x,SIZE.y],"capture_mode":"minimized no-focus black main window, independent offscreen SubViewport with forced real GPU draws","main_window_minimized":DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED,"no_focus":root.get_flag(Window.FLAG_NO_FOCUS),"vsync_requested":"disabled","disabled_render_loop":true,"low_processor_usage_mode":OS.low_processor_usage_mode,"render_cap_fps":Engine.max_fps,"time_scale":Engine.time_scale,"physics_ticks_per_second":Engine.physics_ticks_per_second,"preferences_ignored":not scene.settings_load_attempted,"fixed_fps":false,"readback_count":0,"scope":"Uncapped real-time 1080p offscreen rendering throughput with moving physical route and HUD. The minimized native window is not presenting the scene; these numbers do not measure visible-window presentation, input latency, or native focus behavior.","presets":{}}
    report.merge(launch_state,true)
    if not report.main_window_minimized or not report.no_focus or not report.preferences_ignored:
        fail("Background window or settings isolation contract failed.")
    if failures.is_empty():
        for period in PERIODS:
            report.presets[period] = await measure(period)
            report.failures = failures.duplicate()
            report.passed = false
            save_json(output.path_join("performance-report.json"),report)
    loop_route = false
    scene.cancel_route()
    report.failures = failures.duplicate()
    report.passed = failures.is_empty() and report.presets.size()==1 and report.presets.values().all(func(value): return value.passed)
    report.all_periods_60fps_p95_met = report.presets.size()==1 and report.presets.values().all(func(value): return value.target_60fps_p95_met)
    save_json(output.path_join("performance-report.json"),report)
    drawing = false
    print("CANAL_BENCHMARK_DONE passed=",report.passed," target60=",report.all_periods_60fps_p95_met)
    quit(0 if report.passed else 1)
