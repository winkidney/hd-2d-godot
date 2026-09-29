extends SceneTree
## Actual viewport UI evidence; no runtime source edits or test-node dependency.
## --script res://tools/p9frontal/ui_probe.gd -- --ignore-user-settings
var scene: Node3D
var output := "res://build/p9-frontal/ui"
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var records: Dictionary = {}

func _initialize() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--probe-output="):
            output = arg.trim_prefix("--probe-output=")
    call_deferred("run_probe")

func check(ok: bool, label: String) -> void:
    checks.append({"name":label,"passed":ok})
    if not ok:
        failures.append(label)
    print("FRONTAL_UI_", "PASS " if ok else "FAIL ",label)

func press_key(key: Key) -> void:
    var event := InputEventKey.new()
    event.keycode = key
    event.physical_keycode = key
    event.pressed = true
    # Use the real scene input handler; do not call panel toggle helpers.
    scene._input(event)

func equal_value(a: Variant, b: Variant) -> bool:
    if typeof(a)!=typeof(b):
        return false
    if a is float:
        return (is_nan(a) and is_nan(b)) or is_equal_approx(a,b)
    if a is Vector3:
        return a.is_equal_approx(b)
    if a is Basis:
        return a.is_equal_approx(b)
    if a is Transform3D:
        return a.is_equal_approx(b)
    return a==b

func run_probe() -> void:
    output = ProjectSettings.globalize_path(output)
    if DirAccess.make_dir_recursive_absolute(output)!=OK:
        push_error("Cannot create the UI probe evidence directory.")
        quit(2)
        return
    check(DisplayServer.get_name()!="headless","actual GPU display required")
    if DisplayServer.get_name()=="headless":
        await finish()
        return
    var packed := load("res://scenes/frontal_canal.tscn") as PackedScene
    if packed==null:
        check(false,"frontal scene loads")
        await finish()
        return
    scene = packed.instantiate() as Node3D
    root.add_child(scene)
    for frame in range(30):
        await process_frame
    # Let the HUD's real-time FPS window replace its startup sample.
    # Wall-clock time matters here, including when fixed-fps advances game time.
    var warmup_started := Time.get_ticks_msec()
    while Time.get_ticks_msec()-warmup_started < 1200:
        await process_frame
    check(scene.get_viewport().get_visible_rect().size==Vector2(1920,1080),"1920x1080 viewport")
    for id in ["F","W","O"]:
        check(scene.select_variant(id),"select "+id)
        scene.reset_variant()
        scene.close_tuning()
        press_key(KEY_F9)
        check(scene.variant_panel.visible and not scene.player.controls_enabled,id+" F9 opens and locks movement")
        check(not scene.parallax_panel.visible and not scene.dof_panel.visible,id+" F9 exclusive panel")
        for frame in range(4):
            await process_frame
        var path := output.path_join(id+"-F9.png")
        check(await scene.capture(path),id+" F9 GPU capture")
        press_key(KEY_F8)
        check(scene.parallax_panel.visible and not scene.variant_panel.visible,id+" F8 switches from F9")
        var before: Dictionary = scene.rig.pose_snapshot()
        var state := {"frozen":scene.rig.frozen,"clock":scene.clock_frozen,
            "follow":scene.follow,"tour":scene.tour,"focus_mode":scene.dof.mode,
            "manual_depth":scene.dof.manual_depth,"focus_depth":scene.dof.focus_depth,
            "water_motion":scene.lighting.water.get_shader_parameter("motion"),
            "actor":scene.player.global_position}
        scene.parallax_panel.preview_button.pressed.emit()
        check(scene.parallax_preview.active,id+" preview button starts")
        scene.parallax_preview.update(0.65)
        scene.parallax.update(0.0,true)
        check(not scene.camera.global_transform.is_equal_approx(before.transform),id+" preview actually moves camera")
        check(scene.rig.frozen and scene.clock_frozen and scene.dof.mode=="manual",id+" preview owns camera clock focus")
        press_key(KEY_F8)
        # Compare synchronously, before a normal frame legitimately advances focus.
        var after: Dictionary = scene.rig.pose_snapshot()
        check(before.size()==after.size(),id+" pose field set retained")
        for key in before:
            check(after.has(key) and equal_value(before[key],after[key]),id+" preview restores pose "+key)
        check(scene.rig.frozen==state.frozen and scene.clock_frozen==state.clock,id+" freeze state restored")
        check(scene.follow==state.follow and scene.tour==state.tour,id+" follow and tour restored")
        check(scene.dof.mode==state.focus_mode and is_equal_approx(scene.dof.manual_depth,state.manual_depth) and is_equal_approx(scene.dof.focus_depth,state.focus_depth),id+" focus state restored")
        check(equal_value(scene.lighting.water.get_shader_parameter("motion"),state.water_motion),id+" water motion restored")
        check(scene.player.global_position.is_equal_approx(state.actor),id+" actor not moved by preview")
        check(not scene.parallax_preview.active and scene.parallax_preview.saved.is_empty() and scene.parallax_preview.saved_pose.is_empty(),id+" preview state cleared")
        check(not scene.panels_open() and scene.player.controls_enabled,id+" F8 close releases input")
        check(scene.parallax.compatible,id+" restored camera compatible with parallax")
        records[id] = {"capture":id+"-F9.png","capture_sha256":FileAccess.get_sha256(path),
            "pose_fields_checked":before.keys(),"camera":scene.rig.pose_diagnostics(),
            "input_path":"Synthesized InputEventKey passed to scene._input; preview uses the F8 button signal."}
    await finish()

func finish() -> void:
    var report := {"schema":1,"passed":failures.is_empty(),"checks":checks,
        "failures":failures,"variants":records,"real_gpu":DisplayServer.get_name()!="headless",
        "engine":Engine.get_version_info().string,"utc":Time.get_datetime_string_from_system(true)}
    var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
    if file==null:
        failures.append("report write failed")
        push_error("Could not write UI probe report.")
    else:
        file.store_string(JSON.stringify(report,"  ")+"\n")
        file.close()
    print("FRONTAL_UI_DONE checks=",checks.size()," failures=",failures.size())
    if is_instance_valid(scene):
        scene.queue_free()
        for frame in range(4):
            await process_frame
    quit(0 if failures.is_empty() else 1)
