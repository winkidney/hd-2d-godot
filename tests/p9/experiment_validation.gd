extends Node
var scene: Node3D
var output := "res://build/p9-experiments/gpu"
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var report: Dictionary = {}
var real_gpu := false

func check(ok: bool, label: String) -> void:
    checks.append({"name":label,"passed":ok})
    if not ok: failures.append(label)
    print("P9X_", "PASS " if ok else "FAIL ",label)

func wait_frames(count: int) -> void:
    for i in range(count): await get_tree().physics_frame

func run(value: Node3D) -> void:
    scene = value
    reparent(get_tree().root)
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--capture-dir="): output=arg.trim_prefix("--capture-dir=")
    output=ProjectSettings.globalize_path(output)
    DirAccess.make_dir_recursive_absolute(output)
    real_gpu=DisplayServer.get_name()!="headless"
    if real_gpu: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps=0
    await wait_frames(30)
    scene.player.scripted_input=true
    scene.tour=false
    scene.clock_frozen=true
    if "--p9-experiment-record" in OS.get_cmdline_user_args():
        scene.hud.container.hide()
        report.route=await preload("res://tests/p9/experiment_route.gd").run(scene,output,true)
        check(report.route.passed,"recorded_physical_route")
        await finish()
        return
    check(not scene.settings_load_attempted,"tests_ignore_preferences")
    check(scene.impostor.available,"three_period_multiview_atlases_available")
    state_tests()
    report.variants={}
    var initial: Vector3 = scene.to_vector(scene.layout.player_spawn)
    var actor_heights: Dictionary={}
    for id in ["A","B","C","D"]:
        check(scene.select_experiment(id),"select_"+id)
        scene.player.position=initial
        scene.player.velocity=Vector3.ZERO
        scene.rig.select_variant(id,initial)
        scene.rig.set_offset(Vector3.ZERO)
        actor_heights[id]=scene.rig.actor_screen_height(initial)
        var entry: Dictionary={"camera":scene.rig.pose_diagnostics()}
        if "--no-route" not in OS.get_cmdline_user_args():
            entry.route=await preload("res://tests/p9/experiment_route.gd").run(scene,output,false)
            check(entry.route.passed,"physics_route_"+id)
        check(scene.impostor.active==(id=="D"),"impostor_only_D_"+id)
        check(scene.impostor.source_visual.visible==(id!="D"),"geometry_visible_ABC_"+id)
        if real_gpu:
            entry.images=await images(id)
            if "--no-fixtures" not in OS.get_cmdline_user_args():
                var fixture_dir: String=output.path_join(id)
                DirAccess.make_dir_recursive_absolute(fixture_dir)
                entry.fixtures=await preload("res://tests/p9/experiment_fixtures.gd").run(scene,fixture_dir)
                check(entry.fixtures.passed,"fixtures_"+id)
            if "--quick" not in OS.get_cmdline_user_args(): entry.performance=await performance(id)
        report.variants[id]=entry
    report.actor_heights_px=actor_heights
    for id in ["C","D"]: check(absf(actor_heights[id]/actor_heights.A-1.0)<=.02,"center_actor_height_match_"+id)
    await finish()

func state_tests() -> void:
    var pos: Vector3=scene.player.position
    var collisions: Array = scene.get_node("World").find_children("*","CollisionShape3D",true,false)
    var transforms: Dictionary={}
    for shape in collisions: transforms[shape.get_instance_id()]=shape.global_transform
    scene.lighting.apply_preset("night")
    scene.dof.near_enabled=false;scene.dof.far_enabled=true;scene.dof.apply()
    for id in ["A","B","C","D"]:
        check(scene.select_experiment(id),"switch_"+id)
        check(scene.player.position==pos and scene.lighting.preset_id=="night" and not scene.dof.near_enabled and scene.dof.far_enabled,"switch_preserves_player_time_dof_"+id)
        check(scene.preferences_path.ends_with("-"+id+"-parallax.cfg"),"settings_path_"+id)
        for shape in collisions: check(shape.global_transform==transforms[shape.get_instance_id()],"collision_unchanged_"+id+"_"+str(shape.get_instance_id()))
        scene.parallax.change("global_strength",.4+.2*["A","B","C","D"].find(id))
    for id in ["A","B","C","D"]:
        scene.select_experiment(id)
        check(is_equal_approx(scene.parallax.profile.global_strength,.4+.2*["A","B","C","D"].find(id)),"independent_settings_"+id)
        scene.reset_experiment()
        check(scene.rig.supported_pose(),"reset_supported_pose_"+id)
        scene.player.scripted_input=false
        for yaw in [-6.0,0.0,6.0]:
            scene.rig.set_test_yaw(yaw)
            for action in ["move_left","move_right","move_up","move_down"]:
                Input.action_press(action)
                var direction: Vector3=scene.player.motion_direction()
                Input.action_release(action)
                var screen_delta: Vector2=scene.camera.unproject_position(pos+direction)-scene.camera.unproject_position(pos)
                var ok: bool = screen_delta.x<0 if action=="move_left" else (screen_delta.x>0 if action=="move_right" else (screen_delta.y<0 if action=="move_up" else screen_delta.y>0))
                check(ok,"screen_controls_"+id+"_"+action+"_"+str(yaw))
        scene.player.scripted_input=true
        scene.rig.clear_test_yaw()
        for i in range(300): scene.rig.update(1.0/60.0,pos,false,0)
        check(scene.rig.follow_offset.distance_to(scene.rig.desired_offset(pos))<.001 and absf(scene.rig.yaw_degrees-scene.rig.desired_yaw(pos))<.001,"stop_converges_"+id)
        scene.reset_experiment()
    scene.toggle_experiments()
    check(scene.experiment_panel.visible and not scene.player.controls_enabled,"F9_input_lock")
    scene.toggle_tuning("dof")
    check(not scene.experiment_panel.visible and scene.dof_panel.visible,"exclusive_F6_F9")
    scene.close_tuning()
    check(not scene.panels_open() and scene.player.controls_enabled,"close_releases_controls")
    scene.dof.near_enabled=true;scene.dof.apply()
    scene.lighting.apply_preset("dusk")

func images(id: String) -> Array:
    var entries: Array=[]
    scene.rig.frozen=true
    scene.hud.container.hide()
    scene.background.wind_enabled=false
    scene.lighting.water.set_shader_parameter("motion",0.0)
    var positions := {"left":Vector3(-17,1.2,3.5),"center":Vector3(3,1.2,6.7),"right":Vector3(20,1.2,3.5)}
    for place in positions:
        scene.player.position=positions[place]+Vector3.UP*.2
        scene.player.velocity=Vector3.ZERO
        await wait_frames(20)
        scene.rig.select_variant(id,scene.player.position)
        scene.parallax.update(0,true)
        scene.impostor.update_view(0,true)
        for period in ["day","dusk","night"]:
            scene.lighting.apply_preset(period)
            scene.dof.focus_depth=scene.dof.depth(scene.player.position+Vector3.UP)
            for enabled in [false,true]:
                scene.dof.enabled=enabled;scene.dof.apply()
                for frame in range(8): await RenderingServer.frame_post_draw
                var name: String="%s-%s-%s-dof-%s.png"%[id,period,place,"on" if enabled else "off"]
                check(await scene.capture(output.path_join(name)),"capture_"+name)
                var model_pos: Vector3=scene.impostor.source_visual.global_position
                var viewing: Vector3=scene.camera.global_position-model_pos if scene.camera.projection==Camera3D.PROJECTION_PERSPECTIVE else scene.camera.global_basis.z
                entries.append({"file":name,"camera":scene.rig.pose_diagnostics(),"player_screen":scene.camera.unproject_position(scene.player.position),"geometric_view_angle":rad_to_deg(atan2(viewing.x,viewing.z)),"impostor":scene.impostor.diagnostics()})
    scene.hud.container.show()
    scene.toggle_experiments()
    check(await scene.capture(output.path_join(id+"-panel.png")),"panel_capture_"+id)
    scene.close_tuning()
    scene.hud.container.hide()
    scene.rig.frozen=false
    scene.lighting.water.set_shader_parameter("motion",1.0)
    scene.background.wind_enabled=true
    return entries

func performance(id: String) -> Dictionary:
    var results: Dictionary={}
    scene.player.position=scene.to_vector(scene.layout.player_spawn)
    scene.player.velocity=Vector3.ZERO
    scene.rig.select_variant(id,scene.player.position)
    scene.dof.enabled=true;scene.dof.near_enabled=true;scene.dof.far_enabled=true;scene.dof.apply()
    scene.clock_frozen=false
    for period in ["day","dusk","night"]:
        scene.lighting.apply_preset(period)
        var result: Dictionary=await preload("res://tests/feature_benchmark.gd").measure(scene.get_viewport())
        result["rendering_video_memory_bytes"]=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
        results[period]=result
        check(result.duration_s>=30 and result.gpu.nonzero_samples>0,"measured_"+id+"_"+period)
        check(result.target_60fps_p95_met,"budget_"+id+"_"+period)
        print("P9X_BENCH ",id," ",period," P95 ",result.p95_ms," GPU ",result.gpu.p95_ms)
    scene.clock_frozen=true
    return results

func finish() -> void:
    report.merge({"schema":1,"real_gpu":real_gpu,"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name() if real_gpu else "none","viewport":[get_viewport().size.x,get_viewport().size.y],"checks":checks,"failures":failures,"passed":failures.is_empty(),"utc":Time.get_datetime_string_from_system(true)})
    var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
    if file: file.store_string(JSON.stringify(report,"  ")+"\n");file.close()
    print("P9X_DONE checks=",checks.size()," failures=",failures)
    scene.queue_free()
    for i in range(5): await get_tree().process_frame
    get_tree().quit(0 if failures.is_empty() else 1)
