extends "res://tests/p6p7_validation.gd"
## P8 reuses the shipped route tests, then checks adjustable parallax separately.
const IDS = ["ridge_near","ridge_mid","ridge_far","clouds_near","clouds_far"]

func run(scene) -> void:
    scene_ref = scene
    output = "res://build/p8/validation"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--capture-dir="): output = arg.trim_prefix("--capture-dir=")
    output = ProjectSettings.globalize_path(output)
    DirAccess.make_dir_recursive_absolute(output)
    real_gpu = DisplayServer.get_name() != "headless"
    if real_gpu: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    check(not scene.settings_load_attempted,"personal_settings_ignored_in_tests")
    await run_core(scene)
    test_controls(scene)
    test_dof(scene)
    await test_route(scene)
    test_parallax(scene)
    test_ratios(scene)
    test_wind(scene)
    test_settings(scene)
    test_panel(scene)
    test_extended(scene)
    await test_custom_routes(scene)
    report["coverage"] = await preload("res://tests/parallax_coverage.gd").run(scene,self)
    if real_gpu: await gpu_checks(scene)
    scene.parallax_preview.stop()
    report["p8_settings"] = scene.parallax.snapshot()
    await finish_features(scene)

func test_ratios(scene) -> void:
    var control = scene.parallax
    scene.rig.frozen = true
    scene.clock_frozen = true
    scene.background.wind_enabled = false
    var ground: Transform3D = scene.background.layers.valley.global_transform
    var records: Array[Dictionary] = []
    var focal: float = scene.camera.get_camera_projection().x.x*get_viewport().get_visible_rect().size.x*0.5
    control.profile.mode = "artistic"
    control.profile.transition_time = 0.0
    for k in [0.0,0.5,1.0,1.5,2.0]:
        control.profile.global_strength = k
        for id in IDS:
            scene.rig.set_offset(Vector3.ZERO)
            control.update(0.0,true)
            var initial: Vector2 = scene.camera.unproject_position(control.layer_point(id))
            var depth: float = scene.dof.depth(control.layer_point(id))
            for dx in [-7.5,-2.0,2.0,7.5]:
                scene.rig.set_offset(control.right*dx)
                control.update(0.0,true)
                var point: Vector2 = scene.camera.unproject_position(control.layer_point(id))
                var expected: float = -focal*k*dx/depth
                check(absf(point.x-initial.x-expected)<0.08 and absf(point.y-initial.y)<0.05,"ratio_%s_%.1f_%.1f"%[id,k,dx])
                check(absf(scene.dof.depth(control.layer_point(id))-depth)<0.001,"depth_preserved_%s_%.1f_%.1f"%[id,k,dx])
                records.append({"layer":id,"k":k,"camera_dx":dx,"depth":depth,"expected_dx":expected,"projected_dx":point.x-initial.x})
    report["ratio_projection"] = records
    for i in range(100):
        scene.rig.set_offset(control.right*(7.5 if i%2==0 else -7.5))
        control.update(0.0,true)
    scene.rig.set_offset(Vector3.ZERO)
    control.update(0.0,true)
    for id in IDS: check(control.states[id].node.global_transform.is_equal_approx(control.states[id].base),"no_drift_"+id)
    check(scene.background.layers.valley.global_transform.is_equal_approx(ground),"terrain_not_compensated")
    scene.rig.set_offset(control.right*2.0)
    control.profile.global_strength = 2.0
    control.profile.layer_gains.ridge_far = 2.0
    control.update(0.0,true)
    check(control.current.ridge_far == 2.0 and control.diagnostics().ridge_far.capped,"requested_vs_capped_ratio")
    control.profile.global_strength = 0.0
    control.profile.transition_time = 0.2
    control.update(0.01)
    check(control.current.ridge_far > 0 and control.current.ridge_far < 2,"ratio_transition_not_instant")
    control.update(0.25)
    check(control.current.ridge_far == 0,"ratio_transition_finishes")
    scene.camera.fov += 1.0
    control.update(0.0)
    check(not control.compatible and control.current.ridge_far == 1.0,"incompatible_camera_falls_back")
    scene.camera.fov = control.reference_fov
    control.reset_all()
    scene.rig.set_offset(Vector3.ZERO)
    control.update(0.0,true)
    check(control.compatible,"camera_recovery")
    for id in IDS: check(control.current[id] == 1.0,"natural_default_"+id)

func test_wind(scene) -> void:
    var cloud: Node3D = scene.background.clouds[0].node
    scene.background.wind_enabled = true
    scene.background.advance(5.0)
    var before := cloud.position
    scene.parallax.change("wind_near",-2.0)
    scene.background.advance(0.0)
    check(cloud.position.is_equal_approx(before),"wind_change_preserves_position")
    scene.background.advance(0.1)
    check(absf(cloud.position.x-before.x+0.2)<0.001,"reverse_wind_continuous")
    scene.parallax.change("wind_near",0.0)
    before = cloud.position
    scene.background.advance(20.0)
    check(cloud.position.is_equal_approx(before),"zero_wind_pauses_phase")
    scene.background.wind_enabled = false
    var phases: Array = scene.background.wind_phases.duplicate()
    scene.background.advance(30.0)
    check(scene.background.wind_phases == phases,"wind_disabled_freezes_both_phases")
    scene.parallax.change("horizontal_follow_gain",0.0)
    var displacement: Vector3 = scene.rig.desired_offset(scene.player.position)
    check(absf(displacement.dot(scene.parallax.right))<0.001,"zero_horizontal_follow_gain")
    check(scene.rig.gain == 0.45 and scene.rig.dead_zone == 0.8,"depth_follow_defaults_not_overridden")
    scene.parallax.reset_all()
    scene.parallax.update(0.0,true)

func config_for(scene) -> ConfigFile:
    var config := ConfigFile.new()
    config.set_value("meta","schema",1)
    config.set_value("meta","layout_id",scene.parallax.layout_id)
    for key in scene.parallax.snapshot(): config.set_value("parallax",key,scene.parallax.snapshot()[key])
    return config

func test_settings(scene) -> void:
    var store = preload("res://scripts/parallax_settings_store.gd").new()
    store.path = "user://p8-tests/parallax.cfg"
    scene.parallax.select_preset("enhanced")
    scene.parallax.change("ridge_far",0.5)
    var expected: Dictionary = scene.parallax.snapshot()
    check(store.save_settings(scene.parallax),"save_preferences")
    scene.parallax.reset_all()
    check(store.load_settings(scene.parallax) and scene.parallax.snapshot()==expected,"preferences_roundtrip")
    for value in [NAN,INF,-1.0,3.0,"resource://not-allowed",true,null]:
        var config := config_for(scene)
        config.set_value("parallax","global_strength",value)
        check(not store.apply_config(config,scene.parallax),"reject_invalid_scalar_"+str(value))
        check(scene.parallax.snapshot()==expected,"invalid_load_is_atomic_"+str(value))
    for version in [2,true,"1"]:
        var config := config_for(scene)
        config.set_value("meta","schema",version)
        check(not store.apply_config(config,scene.parallax),"reject_schema_"+str(version))
    var missing := config_for(scene)
    missing.erase_section_key("parallax","ridge_far")
    check(not store.apply_config(missing,scene.parallax),"reject_missing_field")
    var unknown := config_for(scene)
    unknown.set_value("parallax","node_path","anything")
    check(not store.apply_config(unknown,scene.parallax),"reject_unknown_field")
    var changed := config_for(scene)
    changed.set_value("meta","layout_id","0".repeat(64))
    changed.set_value("parallax","horizontal_max_offset",0.5)
    check(store.apply_config(changed,scene.parallax) and scene.rig.max_offset.x==7.5,"layout_change_resets_camera_only")
    check(scene.parallax.profile.global_strength==1.5,"layout_change_preserves_background_choice")
    var original := FileAccess.get_file_as_string(store.path)
    store.path = "user://p8-tests/malformed.cfg"
    var file := FileAccess.open(store.path,FileAccess.WRITE)
    file.store_string("[unclosed")
    file.close()
    print("EXPECTED_PREF_PARSE_BEGIN")
    var malformed_rejected: bool = not store.load_settings(scene.parallax)
    print("EXPECTED_PREF_PARSE_END")
    check(malformed_rejected,"malformed_config_rejected")
    file = FileAccess.open(store.path,FileAccess.WRITE)
    file.store_string("x".repeat(33000))
    file.close()
    check(not store.load_settings(scene.parallax),"oversized_config_rejected")
    store.path = "user://p8-tests/directory-target"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(store.path))
    print("EXPECTED_PREF_IO_BEGIN")
    var failed_save: bool = not store.save_settings(scene.parallax)
    print("EXPECTED_PREF_IO_END")
    check(failed_save,"failed_save_reports_error")
    check(FileAccess.get_file_as_string("user://p8-tests/parallax.cfg")==original,"failed_save_keeps_old_config")
    scene.parallax.reset_all()

func test_panel(scene) -> void:
    scene.rig.set_offset(Vector3.ZERO)
    press(scene,KEY_F8)
    check(scene.parallax_panel.visible and not scene.player.controls_enabled,"F8_opens_and_locks_walk")
    scene.parallax_panel.fields.global_strength.value = 1.5
    check(scene.parallax.profile.mode=="artistic" and scene.parallax.profile.global_strength==1.5,"slider_selects_artistic_mode")
    scene.parallax_panel.fields.ridge_far.value = 2.0
    scene.parallax.update(0,true)
    check(scene.parallax.diagnostics().ridge_far.capped,"panel_displays_effective_cap")
    var parameters: Dictionary = scene.parallax.snapshot()
    for key in [KEY_T,KEY_F3,KEY_F3,KEY_F7,KEY_F7,KEY_F4,KEY_F4]: press(scene,key)
    check(scene.parallax.snapshot()==parameters,"unrelated_shortcuts_preserve_parameters")
    var pose: Transform3D = scene.camera.global_transform
    var player_position: Vector3 = scene.player.position
    var phases: Array = scene.background.wind_phases.duplicate()
    check(scene.parallax_preview.start(scene),"camera_preview_starts")
    scene._process(0.5)
    check(not scene.camera.global_transform.is_equal_approx(pose),"comparison_moves_camera")
    check(scene.player.position.is_equal_approx(player_position),"comparison_does_not_teleport_player")
    check(scene.background.wind_phases==phases,"comparison_freezes_clouds")
    press(scene,KEY_ESCAPE)
    check(not scene.parallax_preview.active and scene.parallax_panel.visible,"escape_stops_preview_first")
    check(scene.camera.global_transform.is_equal_approx(pose),"preview_restores_camera")
    press(scene,KEY_ESCAPE)
    check(not scene.panels_open() and scene.player.controls_enabled,"second_escape_releases_panel_lock")
    press(scene,KEY_F8)
    press(scene,KEY_F6)
    check(scene.dof_panel.visible and not scene.parallax_panel.visible,"tuning_panels_are_exclusive")
    press(scene,KEY_F8)
    check(scene.parallax_panel.visible and not scene.dof_panel.visible,"F8_replaces_dof_panel")
    press(scene,KEY_TAB)
    check(not scene.hud.container.visible and not scene.panels_open() and scene.player.controls_enabled,"hide_HUD_releases_invisible_lock")
    scene.hud.container.show()
    scene.parallax.reset_all()
    scene.parallax.update(0,true)

func test_custom_routes(scene) -> void:
    var center: Vector3 = scene.to_vector(scene.layout.walkway.center)
    var direction: Vector3 = scene.to_vector(scene.layout.walkway.direction)
    scene.follow = true
    scene.rig.frozen = false
    for id in ["natural","soft","enhanced","maximum"]:
        scene.parallax.reset_all()
        scene.parallax.select_preset(id if id != "maximum" else "custom")
        if id == "maximum": scene.parallax.change("global_strength",2.0)
        for side in [-1,1,-1]:
            check(await walk_to(scene,center+direction*(14.5*side)),"custom_route_%s_%d"%[id,side])
        check(scene.player.is_on_floor(),"custom_route_floor_"+id)
    scene.parallax.reset_all()
    scene.parallax.update(0,true)

func gpu_checks(scene) -> void:
    await capture_parallax_matrix(scene)
    report["pixel_markers"] = await preload("res://tests/parallax_pixel_fixture.gd").run(scene,output)
    check(report.pixel_markers.passed,"rendered_layer_markers_saved")
    scene.hud.container.show()
    scene.toggle_tuning("parallax")
    await snap(scene,"panel-basic")
    scene.parallax_panel.tabs.current_tab = 1
    await snap(scene,"panel-advanced")
    scene.close_tuning()
    scene.hud.container.hide()
    if not "--quick" in OS.get_cmdline_user_args():
        report["performance"] = await preload("res://tests/parallax_benchmark.gd").run(scene)
        for id in report.performance:
            var data: Dictionary = report.performance[id]
            check(data.duration_s >= 30.0 and data.gpu.nonzero_samples > 0,"gpu_sampling_"+id)
            check(data.target_60fps_p95_met,"p8_frame_budget_"+id)

func capture_parallax_matrix(scene) -> void:
    scene.close_tuning()
    scene.hud.container.hide()
    scene.clock_frozen = true
    scene.background.wind_enabled = false
    scene.background.wind_phases.assign([0.0,0.0])
    scene.background.advance(0.0)
    scene.lighting.water.set_shader_parameter("motion",0.0)
    scene.rig.frozen = true
    await place(scene,scene.to_vector(scene.layout.walkway.center)+Vector3.UP*0.2)
    scene.player.facing = 0
    scene.dof.mode = "manual"
    scene.rig.set_offset(Vector3.ZERO)
    scene.dof.manual_depth = scene.dof.depth(scene.player.position+Vector3.UP)
    scene.dof.focus_depth = scene.dof.manual_depth
    scene.dof.apply()
    for time_id in ["day","dusk","night"]:
        scene.lighting.apply_preset(time_id)
        for preset_id in ["natural","soft","enhanced"]:
            scene.parallax.select_preset(preset_id)
            for dx in [0.0,2.0]:
                scene.rig.set_offset(scene.parallax.right*dx)
                scene.parallax.update(0,true)
                await snap(scene,"%s-%s-x%d"%[time_id,preset_id,int(dx)])
    scene.parallax.reset_all()
    scene.rig.set_offset(Vector3.ZERO)
    scene.parallax.update(0,true)
    scene.lighting.apply_preset("day")

func snap(scene, name: String) -> void:
    # Settle temporal fog after time-of-day and camera changes before A/B captures.
    for i in range(120): await RenderingServer.frame_post_draw
    check(await scene.capture(output.path_join(name+".png")),"capture_"+name)
    capture_names.append(name+".png")

func test_extended(scene) -> void:
    var c = scene.parallax
    c.change("ridge_far",0.35)
    c.change("horizontal_follow_gain",0.6)
    c.change("wind_near",-0.4)
    c.select_preset("natural")
    c.select_preset("custom")
    check(c.profile.layer_gains.ridge_far == 0.35,"natural_preserves_custom_layer_edit")
    c.select_preset("soft")
    check(scene.rig.horizontal_gain==0.6 and scene.background.wind_speeds[0]==-0.4,"preset_does_not_reset_camera_or_wind")
    c.reset_all()
    c.change("mode","artistic")
    c.change("ridge_near",0.0)
    c.change("ridge_far",2.0)
    c.update(0,true)
    check(c.warnings().contains("inverted"),"layer_speed_inversion_warning")
    c.reset_all()
    scene.rig.set_offset(Vector3.ZERO)
    press(scene,KEY_F8)
    var event := InputEventKey.new()
    event.keycode = KEY_F8
    event.pressed = true
    scene._input(event)
    check(not scene.panels_open() and scene.player.controls_enabled,"global_shortcut_closes_focused_panel")
    press(scene,KEY_F8)
    scene.parallax_preview.start(scene)
    press(scene,KEY_F6)
    check(not scene.parallax_preview.active and scene.dof_panel.visible,"panel_switch_stops_preview")
    scene.close_tuning()
    var store = preload("res://scripts/parallax_settings_store.gd").new()
    store.path = "user://p8-tests/safe-save.cfg"
    check(store.save_settings(c),"atomic_save_baseline")
    var original := FileAccess.get_file_as_string(store.path)
    c.profile.global_strength = INF
    check(not store.save_settings(c),"invalid_snapshot_not_saved")
    check(FileAccess.get_file_as_string(store.path)==original,"invalid_save_preserves_same_target")
    c.reset_all()
    scene.rig.set_offset(c.right*2.0)
    c.update(0,true)
    var old_parent: Transform3D = scene.background.global_transform
    scene.background.position += Vector3(3,0,1)
    c.update(0,true)
    for id in IDS:
        check(c.states[id].node.global_transform.is_equal_approx(c.states[id].base),"global_baseline_with_transformed_parent_"+id)
    scene.background.global_transform = old_parent
    c.update(0,true)
    scene.rig.set_offset(Vector3.ZERO)
    c.reset_all()
    c.update(0,true)
    check(c.snapshot()==c.defaults,"reset_restores_project_defaults")
