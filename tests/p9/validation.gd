extends Node
## Routes use real physics. Teleports are only for named image fixtures.
var scene: Node3D
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var report: Dictionary = {}
var output := "res://build/p9/validation"
var capture_names: Array[String] = []
var real_gpu := false

func check(ok: bool, label: String) -> void:
    checks.append({"name":label,"passed":ok})
    if not ok: failures.append(label)
    print("P9_", "PASS " if ok else "FAIL ",label)

func settle(count: int) -> void:
    for frame in range(count): await get_tree().physics_frame

func go(target: Vector3, label: String) -> void:
    var reached := false
    for frame in range(1600):
        var delta: Vector3=target-scene.player.position
        delta.y=0
        if delta.length()<.16:
            reached=true
            break
        scene.player.scripted_direction=Vector2(delta.x,delta.z).normalized()
        await get_tree().physics_frame
    scene.player.scripted_direction=Vector2.ZERO
    await settle(12)
    check(reached and absf(scene.player.position.y-target.y)<.36,label)
    report.get_or_add("route",[]).append({"step":label,"target":[target.x,target.y,target.z],"actual":[scene.player.position.x,scene.player.position.y,scene.player.position.z],"reached":reached})
    if not reached: print("P9_ROUTE_STOP ",label," actual=",scene.player.position," target=",target)

func run(value: Node3D) -> void:
    scene=value
    reparent(get_tree().root)
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--capture-dir="): output=arg.trim_prefix("--capture-dir=")
    output=ProjectSettings.globalize_path(output)
    DirAccess.make_dir_recursive_absolute(output)
    real_gpu=DisplayServer.get_name()!="headless"
    Engine.max_fps=0
    if real_gpu: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    scene.player.scripted_input=true
    scene.tour=false;scene.follow=true
    await settle(30)
    check(scene.layout.scene_id=="lantern-canal-v1","independent_layout")
    check(scene.preferences_path=="user://settings/lantern-canal-parallax.cfg","isolated_preferences")
    check(not scene.settings_load_attempted,"tests_ignore_preferences")
    check(scene.player.sprite.texture.resource_path.ends_with("reference-scene/sprites/hero.png"),"imagegen_hero_connected")
    check(scene.player.sprite.texture.get_size()==Vector2(192,256),"hero_atlas_contract")
    check(scene.get_node("World").has_node("CentralStairRamp"),"central_stair_collider")
    check(scene.get_node("World").has_node("MarketStairRamp"),"market_stair_collider")
    check(scene.get_node("World").has_node("DockStairRamp"),"dock_stair_collider")
    await routes()
    experiments()
    if real_gpu: await images()
    await finish()

func routes() -> void:
    await go(Vector3(3,1.2,3.5),"spawn_to_bridge_approach")
    await go(Vector3(-7,1.2,3.5),"enter_bridge")
    await go(Vector3(-20,1.2,3.5),"west_extension")
    await go(Vector3(3,1.2,3.5),"bridge_return")
    await go(Vector3(22,1.2,3.5),"east_extension")
    await go(Vector3(2,1.2,.3),"central_stair_bottom")
    await go(Vector3(2,4,-5.8),"central_stair_up")
    await go(Vector3(5.4,4,-6.8),"upper_square")
    scene.interact()
    check(scene.hud.dialogue.visible and not scene.player.controls_enabled,"upper_npc_dialogue")
    if scene.hud.dialogue.visible: scene.interact()
    await go(Vector3(2,4,-5.8),"central_stair_return")
    await go(Vector3(2,1.2,.3),"central_stair_down")
    await go(Vector3(17.5,1.2,3.2),"market_stair_bottom")
    await go(Vector3(17.5,4,-3),"market_stair_up")
    await go(Vector3(17.5,1.2,3.2),"market_stair_down")
    await go(Vector3(8,1.2,.8),"merchant_approach")
    scene.interact()
    check(scene.hud.dialogue.visible,"merchant_dialogue")
    if scene.hud.dialogue.visible: scene.interact()
    await go(Vector3(0,1.2,9.5),"dock_approach")
    await go(Vector3(0,1.2,12),"dock_stair_approach")
    await go(Vector3(-5.3,-.3,12),"dock_down")
    await go(Vector3(0,1.2,12),"dock_up")
    await go(Vector3(3,1.2,6.7),"return_spawn_area")
    check(scene.recovery_count==0,"no_fall_recovery_used_for_routes")
    check(scene.player.is_on_floor(),"player_finishes_grounded")

func experiments() -> void:
    var actor_id: int=scene.player.get_instance_id()
    for id in ["day","dusk","night"]:
        scene.lighting.apply_preset(id)
        check(scene.lighting.preset_id==id and scene.background.profile_id==id,"time_"+id)
    check(actor_id==scene.player.get_instance_id(),"presets_preserve_actor")
    scene.dof.near_enabled=false;scene.dof.far_enabled=true;scene.dof.apply()
    scene.lighting.set_effects(false)
    check(not scene.dof.attributes.dof_blur_far_enabled,"global_bypass")
    scene.lighting.set_effects(true)
    check(not scene.dof.attributes.dof_blur_near_enabled and scene.dof.attributes.dof_blur_far_enabled,"global_restore_preserves_dof_choice")
    scene.dof.near_enabled=true;scene.dof.apply()
    for id in ["soft","standard","strong"]:
        scene.dof.select_profile(id)
        check(scene.dof.profile.valid(),"shared_dof_"+id)
    scene.dof.select_profile("standard")
    scene.rig.frozen=true
    scene.rig.set_offset(Vector3.ZERO)
    scene.parallax.reset_all();scene.parallax.update(0,true)
    var c=scene.parallax
    var viewport_size: Vector2=scene.get_viewport().get_visible_rect().size
    var focal: float=scene.camera.get_camera_projection().x.x*viewport_size.x*.5
    for k in [0.0,.5,1.0,1.5,2.0]:
        scene.rig.set_offset(Vector3.ZERO);c.change("mode","artistic");c.change("global_strength",k);c.update(0,true)
        var original: Dictionary={}
        for id in c.Profile.IDS:
            var point: Vector3=c.layer_point(id)
            original[id]={"screen":scene.camera.unproject_position(point),"depth":scene.dof.depth(point)}
        for dx in [-2.0,2.0]:
            scene.rig.set_offset(c.right*dx);c.update(0,true)
            for id in c.Profile.IDS:
                var point: Vector3=c.layer_point(id)
                var actual: float=scene.camera.unproject_position(point).x-original[id].screen.x
                var expected: float=-focal*k*dx/original[id].depth
                check(absf(actual-expected)<.08,"layer_ratio_%s_%s_%s"%[id,k,dx])
                check(absf(scene.dof.depth(point)-original[id].depth)<.002,"layer_depth_%s_%s_%s"%[id,k,dx])
    c.reset_all();scene.rig.set_offset(Vector3.ZERO);c.update(0,true)
    for id in c.Profile.IDS:
        check(c.states[id].node.global_transform.is_equal_approx(c.states[id].base),"natural_restores_"+id)
    scene.toggle_tuning("parallax")
    check(scene.parallax_panel.visible and not scene.player.controls_enabled,"parallax_panel_input_lock")
    scene.toggle_tuning("dof")
    check(scene.dof_panel.visible and not scene.parallax_panel.visible,"exclusive_panels")
    scene.close_tuning()
    check(scene.player.controls_enabled,"panel_close_releases_input")
    var old_path := "user://settings/parallax.cfg"
    var old_text := FileAccess.get_file_as_string(old_path) if FileAccess.file_exists(old_path) else "NO_FILE"
    c.change("mode","artistic");c.change("global_strength",.7)
    check(scene.parallax_store.save_settings(c),"new_scene_save")
    c.change("global_strength",1.5)
    check(scene.parallax_store.load_settings(c) and is_equal_approx(c.profile.global_strength,.7),"new_scene_reload")
    var after := FileAccess.get_file_as_string(old_path) if FileAccess.file_exists(old_path) else "NO_FILE"
    check(old_text==after,"old_scene_preferences_untouched")
    c.reset_all();c.update(0,true)
    scene.rig.frozen=false

func snap(name: String) -> void:
    for frame in range(120): await RenderingServer.frame_post_draw
    check(await scene.capture(output.path_join(name+".png")),"capture_"+name)
    capture_names.append(name+".png")

func images() -> void:
    scene.rig.frozen=true;scene.clock_frozen=true
    scene.background.wind_enabled=false
    scene.lighting.water.set_shader_parameter("motion",0.0)
    scene.hud.container.hide()
    var positions := {"reference":Vector3(3,1.2,6.7),"west":Vector3(-17,1.2,3.5),"east":Vector3(20,1.2,3.5)}
    for location in positions:
        scene.player.position=positions[location]+Vector3.UP*.2
        scene.player.velocity=Vector3.ZERO
        await settle(20)
        scene.rig.set_offset(Vector3.ZERO if location=="reference" else scene.rig.desired_offset(scene.player.position))
        scene.parallax.update(0,true)
        scene.dof.focus_depth=scene.dof.depth(scene.player.position+Vector3.UP)
        for id in ["day","dusk","night"]:
            scene.lighting.apply_preset(id)
            for enabled in [false,true]:
                scene.dof.enabled=enabled;scene.dof.apply()
                await snap(id+"-"+location+"-dof-"+("on" if enabled else "off"))
    scene.player.position=Vector3(3,1.4,6.7)
    scene.player.velocity=Vector3.ZERO;await settle(20)
    scene.rig.set_offset(Vector3.ZERO);scene.parallax.update(0,true)
    scene.lighting.apply_preset("dusk")
    scene.dof.focus_depth=scene.dof.depth(scene.player.position+Vector3.UP)
    scene.dof.enabled=true
    for pair in [["near",true,false],["far",false,true]]:
        scene.dof.near_enabled=pair[1];scene.dof.far_enabled=pair[2];scene.dof.apply()
        await snap("dusk-reference-"+pair[0]+"-only")
    scene.dof.near_enabled=true;scene.dof.far_enabled=true;scene.dof.apply()
    scene.hud.container.show()
    scene.toggle_tuning("dof");await snap("panel-dof");scene.close_tuning()
    scene.toggle_tuning("parallax");await snap("panel-parallax");scene.close_tuning()
    scene.hud.container.hide()
    # Compatibility adapter for the existing shared calibration fixtures only.
    for period in ["day","dusk","night"]:
        scene.lighting.apply_preset(period)
        for preset in ["natural","soft","enhanced"]:
            scene.parallax.select_preset(preset)
            for dx in [0.0,2.0]:
                scene.rig.set_offset(scene.parallax.right*dx)
                scene.parallax.update(0,true)
                await snap("%s-%s-x%d"%[period,preset,int(dx)])
    scene.parallax.reset_all()
    scene.rig.set_offset(Vector3.ZERO)
    scene.parallax.update(0,true)
    var proxy := Node3D.new();proxy.name="Waykeeper";scene.add_child(proxy)
    var citizens: Array[Node3D]=[]
    for node in scene.get_children():
        if node is Sprite3D and str(node.name).begins_with("Citizen"):
            citizens.append(node);node.hide()
    report["dof_fixture"]=await preload("res://tests/dof_fixture.gd").run(scene,output)
    check(report.dof_fixture.capture_success,"shared_native_dof_fixture")
    report["pixel_fixture"]=await preload("res://tests/parallax_pixel_fixture.gd").run(scene,output)
    check(report.pixel_fixture.passed,"urban_layer_pixel_fixture")
    proxy.queue_free()
    for node in citizens: node.show()
    if "--quick" not in OS.get_cmdline_user_args():
        await performance()

func performance() -> void:
    var cases := {"background_off":[false,false,"standard","natural","day"],"background_only":[true,false,"standard","natural","day"],"standard":[true,true,"standard","natural","day"],"strong":[true,true,"strong","natural","day"],"soft_dusk":[true,true,"standard","soft","dusk"],"enhanced_dusk":[true,true,"standard","enhanced","dusk"],"night":[true,true,"standard","natural","night"]}
    var results: Dictionary={}
    for id in cases:
        var values: Array=cases[id]
        scene.background.visible=values[0]
        scene.lighting.apply_preset(values[4])
        scene.lighting.environment.background_mode=Environment.BG_SKY if values[0] else Environment.BG_COLOR
        scene.dof.select_profile(values[2]);scene.dof.enabled=values[1];scene.dof.apply()
        scene.parallax.select_preset(values[3])
        scene.rig.set_offset(scene.parallax.right*4.0);scene.parallax.update(0,true)
        results[id]=await preload("res://tests/feature_benchmark.gd").measure(scene.get_viewport())
        check(results[id].duration_s>=30.0 and results[id].gpu.nonzero_samples>0,"measured_"+id)
        check(results[id].target_60fps_p95_met,"budget_"+id)
        print("P9_BENCH ",id," P95=",results[id].p95_ms," GPU=",results[id].gpu.p95_ms)
    report["performance"]=results

func finish() -> void:
    report["schema"]=1
    report["scene"]="lantern-canal-v1"
    report["engine"]=Engine.get_version_info().string
    report["real_gpu"]=real_gpu
    report["renderer"]=RenderingServer.get_current_rendering_method()
    report["utc"]=Time.get_datetime_string_from_system(true)
    report["viewport"]=[get_viewport().size.x,get_viewport().size.y]
    if real_gpu: report["gpu"]=RenderingServer.get_video_adapter_name()
    report["checks"]=checks;report["failures"]=failures;report["passed"]=failures.is_empty()
    report["captures"]=capture_names
    var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(report,"  ")+"\n");file.close()
    else:
        push_error("Cannot write P9 report");failures.append("write_report")
    print("P9_VALIDATION_DONE checks=",checks.size()," failures=",failures)
    scene.queue_free()
    for frame in range(5): await get_tree().process_frame
    get_tree().quit(0 if failures.is_empty() else 1)
