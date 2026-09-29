extends "res://tests/runtime_validation.gd"
## Assertions, analytic projection measurements and real rendered evidence are separate.
## Shortcut calls below are synchronous logic checks, not native-window key evidence.
var output := "res://build/p6p7/validation"
var route_samples: Array[Dictionary] = []
var scene_ref: Node3D
var real_gpu := false
var capture_names: Array[String] = []

func run(scene) -> void:
    scene_ref = scene
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--capture-dir="):
            output = arg.trim_prefix("--capture-dir=")
    output = ProjectSettings.globalize_path(output)
    DirAccess.make_dir_recursive_absolute(output)
    real_gpu = DisplayServer.get_name() != "headless"
    check(scene.follow,"default_exploration_follows")
    if real_gpu: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    await run_core(scene)
    test_controls(scene)
    test_dof(scene)
    await test_route(scene)
    test_parallax(scene)
    if real_gpu:
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
        await capture_matrix(scene)
        await capture_dof_fixture(scene)
        if not "--quick" in OS.get_cmdline_user_args():
            await benchmark(scene)
    await finish_features(scene)

func test_dof(scene) -> void:
    var d = scene.dof
    for id in ["soft","standard","strong"]:
        d.select_profile(id)
        check(d.profile.valid(), "dof_profile_valid_"+id)
    d.select_profile("standard")
    d.enabled = true
    d.near_enabled = true
    d.far_enabled = false
    d.apply()
    check(d.attributes.dof_blur_near_enabled and not d.attributes.dof_blur_far_enabled,"near_only_switch")
    scene.lighting.set_effects(false)
    check(not d.attributes.dof_blur_near_enabled and d.near_enabled,"master_bypass_preserves_near_choice")
    scene.lighting.set_effects(true)
    check(d.attributes.dof_blur_near_enabled and not d.attributes.dof_blur_far_enabled,"master_restores_exact_choices")
    d.enabled = false
    var identity: int = scene.background.layers.ridge_far.get_instance_id()
    for id in ["day","dusk","night"]:
        scene.lighting.apply_preset(id)
        check(not d.enabled and scene.background.profile_id == id,"time_does_not_reset_dof_"+id)
    check(identity == scene.background.layers.ridge_far.get_instance_id(),"background_identity_preserved")
    d.enabled = true
    d.near_enabled = false
    d.far_enabled = true
    d.apply()
    check(not d.attributes.dof_blur_near_enabled and d.attributes.dof_blur_far_enabled,"far_only_switch")
    d.near_enabled = true
    d.focus_depth = 40.0
    var focus_point: Vector3 = scene.camera.get_camera_transform() * Vector3(0,0,-40)
    d.update(0.1,focus_point,false)
    check(absf(d.focus_depth-40.0) < 0.001,"focus_dead_zone_stable")
    var close_point: Vector3 = scene.camera.get_camera_transform() * Vector3(0,0,-20)
    d.update(1.0/60.0,close_point,false)
    check(d.focus_depth < 40 and d.focus_depth > 25,"focus_changes_smoothly")
    d.mode = "protected"
    d.far_enabled = true
    scene.lighting.apply_preset("day")

func walk_to(scene, point: Vector3, limit := 1800) -> bool:
    var frames := 0
    while frames < limit:
        var delta: Vector3 = point-scene.player.position
        delta.y = 0
        if delta.length() < 0.14:
            break
        delta = delta.normalized()
        scene.player.scripted_direction = Vector2(delta.x,delta.z)
        await get_tree().physics_frame
        frames += 1
        if scene.player.position.y < -0.5:
            break
    scene.player.scripted_direction = Vector2.ZERO
    await settle(90)
    var remaining: Vector3 = scene.player.position-point
    remaining.y = 0
    return remaining.length() < 0.22 and scene.player.is_on_floor()

func test_route(scene) -> void:
    scene.follow = true
    scene.rig.frozen = false
    await place(scene,scene.to_vector(scene.layout.player_spawn))
    for point in [Vector3(1.2,0,0.8),Vector3(1.2,0,8.3),scene.to_vector(scene.layout.walkway.center)]:
        check(await walk_to(scene,point),"spawn_connected_to_walkway_"+str(point.z))
    var center: Vector3 = scene.to_vector(scene.layout.walkway.center)
    var direction: Vector3 = scene.to_vector(scene.layout.walkway.direction).normalized()
    var rotations: Array[Vector3] = []
    for coordinate in [-14.5,-10.0,-5.0,0.0,5.0,10.0,14.5]:
        check(await walk_to(scene,center+direction*coordinate),"walkway_eastbound_"+str(coordinate))
        var screen: Vector2 = scene.camera.unproject_position(scene.player.position+Vector3.UP)
        var viewport_size: Vector2 = get_viewport().get_visible_rect().size
        var depth: float = scene.dof.depth(scene.player.position+Vector3.UP)
        check(screen.x > 60 and screen.x < viewport_size.x-60 and screen.y > 80 and screen.y < viewport_size.y-100,"actor_on_screen_"+str(coordinate))
        check(depth > scene.dof.attributes.dof_blur_near_distance and depth < scene.dof.attributes.dof_blur_far_distance,"actor_in_focus_"+str(coordinate))
        var ray := PhysicsRayQueryParameters3D.create(scene.camera.global_position,scene.player.position+Vector3.UP)
        var excluded: Array[RID] = [scene.player.get_rid()]
        for body in get_tree().get_nodes_in_group("movement_only_barrier"): excluded.append(body.get_rid())
        ray.exclude = excluded
        var hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(ray)
        if not hit.is_empty(): print("VISIBILITY_OCCLUDER ",hit.collider.name," at ",hit.position)
        check(hit.is_empty(),"route_camera_collision_visibility_"+str(coordinate))
        route_samples.append({"coordinate":coordinate,"player":array3(scene.player.position),"camera":array3(scene.camera.position),"screen":[screen.x,screen.y],"depth":depth})
        rotations.append(scene.camera.rotation)
    var a: Array = route_samples.front().camera
    var b: Array = route_samples.back().camera
    var travel := Vector3(b[0]-a[0],b[1]-a[1],b[2]-a[2]).length()
    report["camera_travel_m"] = travel
    check(travel >= 6.0 and travel <= 14.0,"sustained_lateral_camera_travel")
    check(rotations.front().distance_to(rotations.back()) < 0.0001,"follow_does_not_rotate_camera")
    check(await walk_to(scene,center-direction*14.5),"walkway_full_return_westbound")
    report["route_samples"] = route_samples

static func array3(p: Vector3) -> Array:
    return [p.x,p.y,p.z]

func test_parallax(scene) -> void:
    scene.clock_frozen = true
    scene.background.wind_enabled = false
    scene.lighting.water.set_shader_parameter("motion",0.0)
    scene.rig.frozen = true
    scene.rig.set_offset(Vector3.ZERO)
    var records: Array[Dictionary] = []
    var last_shift := INF
    var viewport_size: Vector2 = get_viewport().get_visible_rect().size
    var focal := viewport_size.y * 0.5 / tan(deg_to_rad(scene.camera.fov)*0.5)
    for id in ["ridge_near","ridge_mid","ridge_far"]:
        var layer: Node3D = scene.background.layers[id]
        var mesh: MeshInstance3D = layer.find_children("*","MeshInstance3D",true,false)[0]
        var point: Vector3 = mesh.global_transform * mesh.get_aabb().get_center()
        var original: Transform3D = layer.global_transform
        scene.rig.set_offset(Vector3.ZERO)
        var before: Vector2 = scene.camera.unproject_position(point)
        var depth: float = scene.dof.depth(point)
        var rotation: Basis = scene.camera.global_basis
        scene.rig.set_offset(scene.rig.horizontal_right()*2.0)
        var after: Vector2 = scene.camera.unproject_position(point)
        var shift := after.x-before.x
        var predicted := -focal*2.0/depth
        check(absf(shift-predicted) < 0.05 and absf(after.y-before.y) < 0.05,"projection_matches_depth_"+id)
        check(absf(shift) < last_shift,"parallax_order_"+id)
        check(original.is_equal_approx(layer.global_transform) and rotation.is_equal_approx(scene.camera.global_basis),"world_fixed_no_rotation_"+id)
        records.append({"layer":id,"depth_m":depth,"observed_projected_dx":shift,"predicted_dx":predicted,"point":array3(point)})
        last_shift = absf(shift)
        scene.rig.set_offset(Vector3.ZERO)
        check(scene.camera.unproject_position(point).distance_to(before) < 0.01,"parallax_returns_without_drift_"+id)
    report["parallax"] = {"scope":"Engine projection of fixed mesh AABB centres; analytic check, not image feature tracking","translation_m":2.0,"layers":records}
    var cloud: Node3D = scene.background.clouds[0].node
    var cloud_before: Vector3 = cloud.position
    scene.background.advance(10)
    check(cloud.position.is_equal_approx(cloud_before),"frozen_clouds_do_not_move")
    scene.background.wind_enabled = true
    scene.background.advance(10)
    check(cloud.position.distance_to(cloud_before) > 1.0,"wind_moves_clouds_without_camera")
    scene.background.wind_enabled = false
    var sky_code: String = scene.background.sky_material.shader.code
    check(sky_code.contains("EYEDIR") and not sky_code.contains("POSITION") and not sky_code.contains("TIME"),"sky_direction_only_no_translation_time_dependency")

func snap(scene, name: String) -> void:
    for i in range(12): await RenderingServer.frame_post_draw
    check(await scene.capture(output.path_join(name+".png")),"capture_"+name)
    capture_names.append(name+".png")

func capture_matrix(scene) -> void:
    scene.hud.container.hide()
    scene.rig.frozen = true
    for coordinate in [-14.5,0.0,14.5]:
        var point: Vector3 = scene.to_vector(scene.layout.walkway.center)+scene.to_vector(scene.layout.walkway.direction)*coordinate
        await place(scene,point+Vector3(0,0.25,0))
        scene.rig.set_offset(scene.rig.desired_offset(scene.player.position))
        scene.dof.focus_depth = scene.dof.depth(scene.player.position+Vector3.UP)
        scene.dof.mode = "manual"
        scene.dof.manual_depth = scene.dof.focus_depth
        scene.player.facing = 0
        var side := "left" if coordinate < 0 else ("right" if coordinate > 0 else "center")
        for id in ["day","dusk","night"]:
            scene.lighting.apply_preset(id)
            for on in [false,true]:
                scene.dof.enabled = on
                scene.dof.apply()
                await snap(scene,id+"-"+side+"-dof-"+("on" if on else "off"))
            if coordinate == 0.0:
                scene.dof.far_enabled = false
                scene.dof.apply()
                await snap(scene,id+"-center-near-only")
                scene.dof.far_enabled = true
                scene.dof.near_enabled = false
                scene.dof.apply()
                await snap(scene,id+"-center-far-only")
                scene.dof.near_enabled = true
    scene.dof.enabled = true
    scene.dof.mode = "protected"
    scene.dof.apply()

func capture_dof_fixture(scene) -> void:
    report["dof_fixture"] = await preload("res://tests/dof_fixture.gd").run(scene,output)
    check(report.dof_fixture.capture_success,"dof_fixture_rendered")

func benchmark(scene) -> void:
    report["performance"] = await preload("res://tests/feature_benchmark.gd").run(scene)
    for id in report.performance:
        check(report.performance[id].duration_s >= 30.0 and report.performance[id].gpu.nonzero_samples > 0,"benchmark_duration_and_gpu_"+id)
        check(report.performance[id].target_60fps_p95_met,"frame_budget_"+id)

func finish_features(scene) -> void:
    report["input_scope"] = "Synchronous shortcut-handler logic regression. This does not verify native-window delivery or editor-reserved shortcuts."
    report["engine"] = Engine.get_version_info().string
    report["renderer"] = RenderingServer.get_current_rendering_method()
    report["real_gpu"] = real_gpu
    if real_gpu: report["gpu"] = RenderingServer.get_video_adapter_name()
    report["utc"] = Time.get_datetime_string_from_system(true)
    report["viewport"] = [get_viewport().size.x,get_viewport().size.y]
    report["checks"] = checks
    report["failures"] = failures
    report["passed"] = failures.is_empty()
    report["capture_files"] = capture_names
    var file := FileAccess.open(output.path_join("features-report.json"),FileAccess.WRITE)
    if file == null:
        push_error("Feature report write failed.")
        failures.append("write_feature_report")
    else:
        file.store_string(JSON.stringify(report)+"\n")
        file.close()
    print("FEATURE_VALIDATION_DONE assertions=",checks.size()," failures=",failures.size())
    scene.queue_free()
    scene_ref = null
    for i in range(6): await get_tree().process_frame
    get_tree().quit(0 if failures.is_empty() else 1)

func press(scene, code: Key) -> void:
    # Keep state restoration assertions in one frame. Native input has a separate runner.
    var event := InputEventKey.new()
    event.pressed = true
    event.keycode = code
    scene._unhandled_key_input(event)

func test_controls(scene) -> void:
    press(scene,KEY_B)
    check(not scene.dof.enabled,"B_toggles_dof")
    press(scene,KEY_B)
    press(scene,KEY_O)
    scene._process(0.016)
    check(scene.dof_panel.visible and not scene.player.controls_enabled,"O_opens_panel_and_locks_walk")
    scene.dof_panel.fields.amount.value = 0.12
    check(absf(scene.dof.attributes.dof_blur_amount-0.12) < 0.001,"slider_updates_native_dof")
    scene.dof_panel.box.get_node("DofPreset").item_selected.emit(2)
    check(scene.dof.profile.profile_id == "strong","preset_widget_changes_resource")
    scene.dof_panel.box.get_node("near_enabled").button_pressed = false
    check(not scene.dof.near_enabled,"near_checkbox_updates_controller")
    scene.dof_panel.box.get_node("near_enabled").button_pressed = true
    press(scene,KEY_ESCAPE)
    scene._process(0.016)
    check(not scene.dof_panel.visible and scene.player.controls_enabled,"escape_closes_tuning_without_quitting")
    scene.dof.select_profile("standard")
    scene.dof_panel.refresh()
