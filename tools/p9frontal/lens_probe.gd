extends SceneTree
## Real-scene lens checks. The caller owns isolated XDG and serial GPU execution.
## --probe-mode=save|load|headless|gpu --probe-output=res://build/...
## Save/load require normal preferences; headless/gpu require --ignore-user-settings.
const IDS := ["F","W","O"]
const RADII := [24.0,29.0,36.0]
const FOVS := [38.0,42.0,48.0]
var scene: Node3D
var mode := "headless"
var output := ""
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var records: Dictionary = {}
var captures: Array[Dictionary] = []
var original_f8: Dictionary = {}
var watching_route := false
var cancel_route := false
var route_seen := false
var route_default_seen := false
var cancel_sent := false
var cancel_after_ms := 0

func _initialize() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--probe-mode="):
            mode = arg.trim_prefix("--probe-mode=")
        elif arg.begins_with("--probe-output="):
            output = arg.trim_prefix("--probe-output=")
    if mode not in ["save","load","headless","gpu"]:
        push_error("Unknown lens probe mode: "+mode)
        quit(2)
        return
    if output.is_empty(): output = "res://build/p9-frontal-zoom/lens/"+mode
    output = ProjectSettings.globalize_path(output)
    call_deferred("run_probe")

func check(ok: bool, label: String) -> void:
    checks.append({"name":label,"passed":ok})
    if not ok: failures.append(label)
    print("FRONTAL_LENS_", "PASS " if ok else "FAIL ",label)

func equal_value(a: Variant, b: Variant) -> bool:
    if typeof(a)!=typeof(b): return false
    if a is float: return (is_nan(a) and is_nan(b)) or is_equal_approx(a,b)
    if a is Vector3 or a is Vector2 or a is Basis or a is Transform3D:
        return a.is_equal_approx(b)
    if a is Dictionary:
        if a.size()!=b.size(): return false
        for key in a:
            if not b.has(key) or not equal_value(a[key],b[key]): return false
        return true
    if a is Array:
        if a.size()!=b.size(): return false
        for index in a.size():
            if not equal_value(a[index],b[index]): return false
        return true
    return a==b

func wait_frames(count: int) -> void:
    for frame in range(count): await process_frame

func key_now(key: Key) -> void:
    var event := InputEventKey.new()
    event.keycode = key
    event.physical_keycode = key
    event.pressed = true
    scene._input(event)

func wheel(up: bool, amount := 1.0) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
    event.position = Vector2(80,360)
    event.global_position = event.position
    event.factor = amount
    event.pressed = true
    Input.parse_input_event(event)
    await wait_frames(2)
    event = event.duplicate()
    event.pressed = false
    Input.parse_input_event(event)
    await wait_frames(2)

func panel_button(title: String) -> bool:
    for item in scene.variant_panel.find_children("*","Button",true,false):
        if item.text == title:
            if item.disabled: return false
            item.pressed.emit()
            return true
    return false

func f8_files() -> Dictionary:
    var result: Dictionary = {}
    for id in IDS:
        var path: String = "user://settings/frontal-canal-"+id+".cfg"
        result[path.get_file()] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
    var old_path := "user://settings/parallax.cfg"
    result[old_path.get_file()] = FileAccess.get_sha256(old_path) if FileAccess.file_exists(old_path) else "absent"
    return result

func check_lens(radius: float, fov: float, label: String) -> void:
    var lens: Dictionary = scene.rig.lens_snapshot()
    check(is_equal_approx(float(lens.radius),radius),label+" radius")
    check(is_equal_approx(float(lens.fov),fov),label+" FOV")
    check(is_equal_approx(scene.camera.fov,fov),label+" actual camera FOV")
    var actual_radius: float = scene.camera.global_position.distance_to(scene.rig.target+scene.rig.follow_offset)
    check(is_equal_approx(actual_radius,radius),label+" actual center distance")

func custom_lens(index: int) -> void:
    check(scene.set_lens("radius",RADII[index]),IDS[index]+" set custom radius")
    check(scene.set_lens("fov",FOVS[index]),IDS[index]+" set custom FOV")

func run_probe() -> void:
    if DirAccess.make_dir_recursive_absolute(output)!=OK:
        push_error("Cannot create lens evidence directory")
        quit(2)
        return
    original_f8 = f8_files()
    var packed := load("res://scenes/frontal_canal.tscn") as PackedScene
    if packed==null:
        check(false,"frontal scene loads")
        await finish()
        return
    scene = packed.instantiate() as Node3D
    root.add_child(scene)
    await wait_frames(30)
    if mode in ["save","load"]:
        check(scene.should_load_preferences(),"normal preference loading enabled")
        check(scene.settings_load_attempted,"normal F8 startup path attempted")
        if scene.should_load_preferences(): await settings_checks()
    else:
        check(not scene.should_load_preferences(),"runtime probe ignores user preferences")
        check(mode!="gpu" or DisplayServer.get_name()!="headless","GPU mode has an actual display")
        if scene.should_load_preferences() or (mode=="gpu" and DisplayServer.get_name()=="headless"):
            await finish()
            return
        # Keep asynchronous input checks stable without changing physical assets.
        scene.clock_frozen = true
        scene.rig.frozen = true
        scene.dof.mode = "manual"
        scene.dof.manual_depth = scene.dof.focus_depth
        scene.dof.apply()
        if mode=="gpu":
            check(scene.get_viewport().get_visible_rect().size==Vector2(1920,1080),"GPU 1920x1080 viewport")
            var start := Time.get_ticks_msec()
            while Time.get_ticks_msec()-start<1200: await process_frame
        await runtime_checks()
        if mode=="headless": await route_checks()
        else: records["route_scope"] = "Full and cancelled physical routes are exercised by the separate headless probe."
    check(equal_value(f8_files(),original_f8),"lens operations leave existing F8 preference files unchanged")
    records["f8_before"] = original_f8
    records["f8_after"] = f8_files()
    await finish()

func settings_checks() -> void:
    if mode=="save":
        # Real F8 files make unchanged-file checks meaningful in an empty test home.
        # This fixture setup happens before the lens-write baseline is captured.
        for id in IDS:
            check(scene.select_variant(id),"F8 fixture select "+id)
            if not FileAccess.file_exists(scene.preferences_path):
                check(scene.parallax_store.save_settings(scene.parallax),"seed absent isolated F8 fixture "+id)
        original_f8 = f8_files()
        scene.select_variant("F")
    else:
        check_lens(RADII[0],FOVS[0],"F automatic startup load")
    var paths: Array[String] = []
    var saved_profiles: Dictionary = {}
    for index in IDS.size():
        var id: String = IDS[index]
        check(scene.select_variant(id),mode+" select "+id)
        if mode=="save":
            custom_lens(index)
            check(panel_button("Save lens"),id+" Save lens button available")
            check(scene.lens_store.message=="Saved this camera's distance and FOV.",id+" Save button succeeded")
        else:
            # No load API call: startup F and first-selection W/O must do the work.
            check(bool(scene.loaded_lenses.get(id,false)),id+" automatic load visited")
            check(scene.lens_store.message=="Loaded this camera's distance and FOV.",id+" automatic load succeeded")
        check_lens(RADII[index],FOVS[index],id+" persisted profile")
        var path: String = scene.lens_store.path_for(id)
        check(path=="user://settings/frontal-lens-"+id+".cfg",id+" independent lens filename")
        check(path not in paths,id+" file is distinct")
        paths.append(path)
        var config := ConfigFile.new()
        var readable := config.load(path)==OK
        check(readable,id+" lens file readable")
        if readable:
            check(config.get_value("meta","schema",-1)==1,id+" disk schema")
            check(config.get_value("meta","variant","")==id,id+" disk variant identity")
            check(config.get_value("meta","layout_id","")==scene.parallax.layout_id,id+" disk layout identity")
            check(is_equal_approx(float(config.get_value("lens","radius",-1)),RADII[index]),id+" disk radius")
            check(is_equal_approx(float(config.get_value("lens","fov",-1)),FOVS[index]),id+" disk FOV")
        if mode=="save":
            scene.set_lens("radius",18.0)
            scene.set_lens("fov",25.0)
            check(panel_button("Load lens"),id+" Load lens button available")
            check_lens(RADII[index],FOVS[index],id+" explicit Load button restores saved values")
        saved_profiles[id] = scene.rig.lens_snapshot()
        records[id] = {"lens":saved_profiles[id],"file":path.get_file(),"sha256":FileAccess.get_sha256(path) if readable else "",
            "normal_automatic_load":mode=="load","store_message":scene.lens_store.message}
    for id in IDS:
        scene.select_variant(id)
        check(equal_value(scene.rig.lens_snapshot(),saved_profiles[id]),id+" revisit keeps independent lens")

func runtime_checks() -> void:
    var expected: Dictionary = {}
    for index in IDS.size():
        var id: String = IDS[index]
        scene.close_tuning()
        var actor: Vector3 = scene.player.global_position
        var period: String = scene.lighting.preset_id
        var focus_mode: String = scene.dof.mode
        var focus_depth: float = scene.dof.focus_depth
        check(scene.select_variant(id),"runtime select "+id)
        check(scene.player.global_position.is_equal_approx(actor),id+" switch preserves actor")
        check(scene.lighting.preset_id==period and scene.dof.mode==focus_mode and is_equal_approx(scene.dof.focus_depth,focus_depth),id+" switch preserves time and focus")
        scene.reset_variant()
        key_now(KEY_F9)
        check(scene.variant_panel.visible,id+" F9 opens")
        var slider: HSlider = scene.variant_panel.lens_sliders.radius
        var spin: SpinBox = scene.variant_panel.lens_spins.fov
        slider.value = RADII[index]
        spin.value = FOVS[index]
        check_lens(RADII[index],FOVS[index],id+" real slider and spin signals")
        check(is_equal_approx(scene.variant_panel.lens_spins.radius.value,RADII[index]) and is_equal_approx(scene.variant_panel.lens_sliders.fov.value,FOVS[index]),id+" paired controls stay synchronized")
        slider.value = -50.0
        check_lens(18.0,FOVS[index],id+" slider clamps minimum")
        spin.value = 500.0
        check_lens(18.0,60.0,id+" spin clamps maximum")
        custom_lens(index)
        var invalid_before: Dictionary = scene.rig.pose_snapshot()
        check(not scene.set_lens("radius",17.0) and not scene.set_lens("fov",61.0) and not scene.set_lens("fov",NAN),id+" API rejects invalid and nonfinite values")
        check(equal_value(invalid_before,scene.rig.pose_snapshot()),id+" invalid API values leave pose unchanged")
        await wheel_guards(id)
        await preview_checks(id)
        projection_range_checks(id)
        scene.parallax.change("mode","artistic")
        scene.parallax.change("global_strength",1.2)
        var p8_before: Dictionary = scene.parallax.snapshot()
        check(panel_button("Reset lens"),id+" Reset lens button")
        check(equal_value(scene.parallax.snapshot(),p8_before),id+" Reset lens preserves all P8 parameters")
        check(equal_value(scene.rig.lens_snapshot(),scene.rig.lens_defaults(id)),id+" Reset lens restores variant defaults")
        custom_lens(index)
        if mode=="gpu": await capture_variant(id,index)
        check(panel_button("Reset this camera"),id+" full reset button")
        check(equal_value(scene.rig.lens_snapshot(),scene.rig.lens_defaults(id)),id+" full reset restores lens")
        check(equal_value(scene.parallax.snapshot(),scene.parallax.defaults),id+" full reset restores P8")
        custom_lens(index)
        expected[id] = scene.rig.lens_snapshot()
        records[id] = {"lens":expected[id],"camera":scene.rig.pose_diagnostics(),"range_samples":records.get(id+"_range",[])}
    scene.close_tuning()
    for id in IDS:
        scene.select_variant(id)
        check(equal_value(scene.rig.lens_snapshot(),expected[id]),id+" in-memory profile survives switching")

func wheel_guards(id: String) -> void:
    var before: Dictionary = scene.rig.lens_snapshot()
    await wheel(true)
    check(equal_value(before,scene.rig.lens_snapshot()),id+" F9 blocks wheel zoom")
    scene.close_tuning()
    await wheel(true)
    check_lens(float(before.radius)-0.5,float(before.fov),id+" gameplay wheel zooms distance only")
    await wheel(false)
    check(equal_value(before,scene.rig.lens_snapshot()),id+" inverse wheel restores lens")
    await wheel(true,0.25)
    check_lens(float(before.radius)-0.5,float(before.fov),id+" fractional wheel factor still uses a half-metre step")
    check(is_equal_approx(scene.variant_panel.lens_sliders.radius.value,float(before.radius)-0.5) and is_equal_approx(scene.variant_panel.lens_spins.radius.value,float(before.radius)-0.5),id+" fractional wheel keeps slider and spin synchronized")
    await wheel(false,0.25)
    check(equal_value(before,scene.rig.lens_snapshot()),id+" inverse fractional wheel restores lens")
    for state in ["F6","F8","dialogue","route","tour","scripted"]:
        match state:
            "F6": key_now(KEY_F6)
            "F8": key_now(KEY_F8)
            "dialogue": scene.hud.show_dialogue({"title":"Lens probe","text":"Wheel zoom must stay locked during dialogue."})
            "route":
                scene.route_running = true
                scene.variant_panel.refresh()
                check(scene.variant_panel.selector.disabled and not scene.variant_panel.lens_sliders.radius.editable and not scene.variant_panel.lens_spins.fov.editable,id+" route locks selector and lens controls")
                for item in scene.variant_panel.adjustment_buttons:
                    check(item.disabled,id+" route locks "+item.text)
                check(not scene.set_lens("radius",25.0),id+" route rejects direct lens edits")
            "tour": scene.tour = true
            "scripted": scene.player.scripted_input = true
        await wheel(true)
        check(equal_value(before,scene.rig.lens_snapshot()),id+" "+state+" blocks wheel zoom")
        scene.route_running = false
        scene.tour = false
        scene.player.scripted_input = false
        scene.hud.close_dialogue()
        scene.close_tuning()
    scene.set_lens("radius",18.0)
    await wheel(true,100.0)
    check_lens(18.0,float(before.fov),id+" wheel clamps near limit")
    scene.set_lens("radius",45.0)
    await wheel(false,100.0)
    check_lens(45.0,float(before.fov),id+" wheel clamps far limit")
    scene.set_lens("radius",float(before.radius))
    scene.variant_panel.refresh()

func preview_checks(id: String) -> void:
    key_now(KEY_F8)
    var before: Dictionary = scene.rig.pose_snapshot()
    var state := {"actor":scene.player.global_position,"frozen":scene.rig.frozen,"clock":scene.clock_frozen,
        "follow":scene.follow,"tour":scene.tour,"mode":scene.dof.mode,"manual":scene.dof.manual_depth,
        "focus":scene.dof.focus_depth,"motion":scene.lighting.water.get_shader_parameter("motion")}
    scene.parallax_panel.preview_button.pressed.emit()
    check(scene.parallax_preview.active,id+" F8 preview button starts")
    scene.parallax_preview.update(0.65)
    check(not scene.camera.global_transform.is_equal_approx(before.transform),id+" preview moves actual camera")
    var lens_before: Dictionary = scene.rig.lens_snapshot()
    await wheel(true)
    check(equal_value(lens_before,scene.rig.lens_snapshot()),id+" F8 preview blocks wheel")
    key_now(KEY_F8)
    check(equal_value(before,scene.rig.pose_snapshot()),id+" F8 close restores complete pose and all lens profiles")
    check(scene.player.global_position.is_equal_approx(state.actor) and scene.rig.frozen==state.frozen and scene.clock_frozen==state.clock,id+" preview restores actor and freeze states")
    check(scene.follow==state.follow and scene.tour==state.tour and scene.dof.mode==state.mode and is_equal_approx(scene.dof.manual_depth,state.manual) and is_equal_approx(scene.dof.focus_depth,state.focus),id+" preview restores follow and focus")
    check(equal_value(scene.lighting.water.get_shader_parameter("motion"),state.motion),id+" preview restores water")
    check(not scene.parallax_preview.active and scene.parallax_preview.saved_pose.is_empty(),id+" preview clears internal state")
    check(scene.parallax_preview.start(scene),id+" independent preview starts with all panels closed")
    await wheel(false)
    check(equal_value(lens_before,scene.rig.lens_snapshot()) and scene.parallax_preview.active,id+" preview alone blocks wheel without a panel")
    scene.parallax_preview.stop()
    check(equal_value(before,scene.rig.pose_snapshot()),id+" independent preview restores complete pose")

func projection_range_checks(id: String) -> void:
    var saved: Dictionary = scene.rig.pose_snapshot()
    var saved_p8: Dictionary = scene.parallax.snapshot()
    var samples: Array[Dictionary] = []
    scene.rig.set_offset(Vector3(4,0,0))
    scene.rig.set_test_yaw(4.0 if id=="O" else 0.0)
    scene.parallax.change("mode","artistic")
    for radius in [18.0,30.0,45.0]:
        for fov in [25.0,35.0,60.0]:
            scene.set_lens("radius",radius)
            scene.set_lens("fov",fov)
            for strength in [0.0,1.0,2.0]:
                scene.parallax.change("global_strength",strength)
                scene.parallax.update(0.0,true)
                var supported: bool = scene.rig.supported_pose() and scene.parallax.compatible
                var max_error := 0.0
                var valid := true
                var diagnostics: Dictionary = scene.parallax.diagnostics()
                for layer in diagnostics:
                    valid = valid and bool(diagnostics[layer].valid)
                    max_error = maxf(max_error,float(diagnostics[layer].representative_error_px))
                var label := "%s radius %.0f FOV %.0f strength %.0f" % [id,radius,fov,strength]
                check(supported and valid and max_error<0.15,label+" keeps P8 supported and representative projection exact")
                samples.append({"radius":radius,"fov":fov,"strength":strength,"supported":supported,"valid":valid,"max_error_px":max_error})
    scene.rig.restore_pose(saved)
    for key in saved_p8: scene.parallax.change(key,saved_p8[key])
    scene.parallax.update(0.0,true)
    scene.variant_panel.refresh()
    records[id+"_range"] = samples

func capture_variant(id: String, index: int) -> void:
    scene.close_tuning()
    var saved_focus := {"mode":scene.dof.mode,"focus":scene.dof.focus_depth,"manual":scene.dof.manual_depth}
    custom_lens(index)
    scene.dof.mode = "protected"
    scene.dof.focus_depth = scene.dof.depth(scene.player.global_position+Vector3.UP)
    scene.dof.apply()
    key_now(KEY_F9)
    await wait_frames(6)
    var rect: Rect2 = scene.variant_panel.get_global_rect()
    var viewport: Rect2 = scene.get_viewport().get_visible_rect()
    check(viewport.encloses(rect),id+" F9 complete panel is inside viewport")
    await capture_image(id+"-F9-custom.png",{"panel_rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
    scene.close_tuning()
    scene.hud.container.hide()
    var saved: Dictionary = scene.rig.pose_snapshot()
    var defaults: Dictionary = scene.rig.lens_defaults(id)
    scene.parallax.change("mode","artistic")
    scene.parallax.change("global_strength",1.2)
    scene.set_lens("fov",float(defaults.fov))
    for sample in [{"name":"near","radius":18.0},{"name":"default","radius":defaults.radius},{"name":"far","radius":45.0}]:
        scene.set_lens("radius",float(sample.radius))
        scene.parallax.update(0.0,true)
        scene.dof.focus_depth = scene.dof.depth(scene.player.global_position+Vector3.UP)
        scene.dof.apply()
        await wait_frames(4)
        check(not scene.hud.container.visible and scene.parallax.profile.mode=="artistic",id+" "+sample.name+" capture has no HUD and uses artistic P8")
        check(scene.dof.mode=="protected",id+" "+sample.name+" capture uses protected focus")
        await capture_image(id+"-"+sample.name+".png",{"comparison":"Same default FOV, independent radius only; near framing may crop.","parallax":scene.parallax.snapshot()})
    scene.rig.restore_pose(saved)
    scene.parallax.update(0.0,true)
    scene.dof.mode = saved_focus.mode
    scene.dof.focus_depth = saved_focus.focus
    scene.dof.manual_depth = saved_focus.manual
    scene.dof.apply()
    scene.hud.container.show()

func capture_image(name: String, extra: Dictionary) -> void:
    var path := output.path_join(name)
    var ok: bool = await scene.capture(path)
    check(ok,"GPU capture "+name)
    var item := {"file":name,"sha256":FileAccess.get_sha256(path) if ok else "","lens":scene.rig.lens_snapshot(),"camera":scene.rig.pose_diagnostics(),
        "focus":{"mode":scene.dof.mode,"depth":scene.dof.focus_depth,"initialization":"Protected focus initialized to player + UP after every lens-distance change; original probe focus restored after capture."}}
    item.merge(extra)
    captures.append(item)

func watch_route_frame() -> void:
    if not watching_route or not scene.route_running: return
    route_seen = true
    route_default_seen = equal_value(scene.rig.lens_snapshot(),scene.rig.lens_defaults(scene.variant_id)) or route_default_seen
    if cancel_route and not cancel_sent and Time.get_ticks_msec()>=cancel_after_ms:
        cancel_sent = true
        var event := InputEventKey.new()
        event.keycode = KEY_ESCAPE
        event.physical_keycode = KEY_ESCAPE
        event.pressed = true
        Input.parse_input_event(event)

func route_checks() -> void:
    scene.close_tuning()
    scene.select_variant("O")
    custom_lens(2)
    scene.parallax.change("mode","artistic")
    scene.parallax.change("global_strength",1.2)
    var route_script: Script = load("res://tests/p9frontal/route.gd")
    var route_records: Array[Dictionary] = []
    for cancel in [false,true]:
        var saved_pose: Dictionary = scene.rig.pose_snapshot()
        var saved_lens: Dictionary = scene.rig.lens_snapshot()
        var saved_p8: Dictionary = scene.parallax.snapshot()
        var saved_actor: Transform3D = scene.player.global_transform
        var saved_period: String = scene.lighting.preset_id
        var saved_focus := {"mode":scene.dof.mode,"depth":scene.dof.focus_depth,"manual":scene.dof.manual_depth}
        watching_route = true
        cancel_route = cancel
        route_seen = false
        route_default_seen = false
        cancel_sent = false
        cancel_after_ms = Time.get_ticks_msec()+200
        process_frame.connect(watch_route_frame)
        var started := Time.get_ticks_msec()
        var result: Dictionary = await route_script.run(scene,"",false)
        var elapsed_ms := Time.get_ticks_msec()-started
        watching_route = false
        process_frame.disconnect(watch_route_frame)
        var label := "cancelled route" if cancel else "complete route"
        check(route_seen and route_default_seen,label+" temporarily uses this variant's default lens")
        if cancel:
            check(cancel_sent and bool(result.cancelled) and not bool(result.passed) and elapsed_ms>=200,label+" receives Escape after real 200ms delay")
        else:
            check(bool(result.passed) and not bool(result.cancelled),label+" completes physical walking checks")
        check(equal_value(saved_pose,scene.rig.pose_snapshot()) and equal_value(saved_lens,scene.rig.lens_snapshot()),label+" restores full pose and personal lens")
        check(equal_value(saved_p8,scene.parallax.snapshot()),label+" preserves P8")
        check(saved_actor.is_equal_approx(scene.player.global_transform) and saved_period==scene.lighting.preset_id,label+" restores actor and time")
        check(scene.dof.mode==saved_focus.mode and is_equal_approx(scene.dof.focus_depth,saved_focus.depth) and is_equal_approx(scene.dof.manual_depth,saved_focus.manual),label+" restores focus")
        check(not scene.route_running and not scene.player.scripted_input,label+" releases route and scripted movement")
        route_records.append({"kind":label,"elapsed_ms":elapsed_ms,"lens_before":saved_lens,"lens_after":scene.rig.lens_snapshot(),"default_seen":route_default_seen,"result":result})
    records["routes"] = route_records

func finish() -> void:
    var report := {"schema":1,"mode":mode,"passed":failures.is_empty(),"checks":checks,"failures":failures,
        "variants":records,"captures":captures,"real_gpu":mode=="gpu" and DisplayServer.get_name()!="headless",
        "engine":Engine.get_version_info().string,"utc":Time.get_datetime_string_from_system(true),
        "scope":"Actual frontal scene and native controls; wheel input uses Input.parse_input_event. Headless runs physical full/cancelled routes. Save/load use normal automatic preferences in separate processes."}
    var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
    if file==null:
        failures.append("report write failed")
        push_error("Could not write lens probe report")
    else:
        file.store_string(JSON.stringify(report,"  ")+"\n")
        file.close()
    print("FRONTAL_LENS_DONE mode=",mode," checks=",checks.size()," failures=",failures.size())
    if is_instance_valid(scene):
        scene.queue_free()
        await wait_frames(4)
    quit(0 if failures.is_empty() else 1)
