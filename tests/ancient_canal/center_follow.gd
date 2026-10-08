extends SceneTree
## Actual physics and independent projection checks; no rendered acceptance.
const ENTRY := "res://scenes/ancient_canal.tscn"
const CENTER_HEIGHT := 1.0125
const SIZES := [Vector2i(1920,1080),Vector2i(1280,1024),Vector2i(2560,1080)]
const EDGES := [Vector3(-25.64,0,-15.64),Vector3(-25.64,0,13.64),Vector3(25.64,0,-15.64),Vector3(25.64,0,13.64),Vector3(-25.64,0,9),Vector3(25.64,0,9),Vector3(-6,0,-15.64),Vector3(-6,0,13.64)]
var scene: Node3D
var destination := "res://build/ancient-canal/center-follow-20261007/center.json"
var fingerprint := ""
var baseline_only := false
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var matrix: Array[Dictionary] = []
var movement: Array[Dictionary] = []
var total_projected_frames := 0
var maximum_center_error := 0.0

func _initialize() -> void:
    root.size = SIZES[0]
    root.content_scale_size = SIZES[0]
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--report="): destination = argument.trim_prefix("--report=")
        if argument.begins_with("--canal-fingerprint="): fingerprint = argument.trim_prefix("--canal-fingerprint=")
        if argument=="--baseline-only": baseline_only = true
    call_deferred("run")

func check(passed: bool,label: String,detail: Dictionary = {}) -> void:
    checks.append({"id":label,"passed":passed,"detail":detail})
    if not passed:
        failures.append(label)
        print("CENTER_FOLLOW_FAIL ",label," ",detail)

func array3(value: Vector3) -> Array:
    return [value.x,value.y,value.z]

func array2(value: Vector2) -> Array:
    return [value.x,value.y]

func settle(count := 12) -> void:
    for index in count: await physics_frame

func place(value: Vector3) -> void:
    scene.player.scripted_direction = Vector2.ZERO
    scene.player.position = value+Vector3.UP*.08
    scene.player.velocity = Vector3.ZERO
    await settle()
    scene.camera_update(0,true)

func pivot() -> Vector3:
    return scene.camera.global_position-scene.rig.orbit_vector

func center_error() -> float:
    var actual: Vector2 = scene.camera.unproject_position(scene.player.position+Vector3.UP*CENTER_HEIGHT)
    return actual.distance_to(scene.camera.get_viewport().get_visible_rect().size/2.0)

func frame_bounds() -> Dictionary:
    var actor: Node3D = scene.player
    var bounds: Array = actor.color_definitions[actor.facing].frames[actor.animation_frame].visible_bounds
    var right: Vector3 = scene.camera.global_basis.x
    right.y = 0
    right = right.normalized()
    var minimum := Vector2(INF,INF)
    var maximum := Vector2(-INF,-INF)
    var forward := true
    for pixel in [Vector2(bounds[0],bounds[1]),Vector2(bounds[2],bounds[1]),Vector2(bounds[2],bounds[3]),Vector2(bounds[0],bounds[3])]:
        var location: Vector3 = actor.global_position+right*(pixel.x-128.0+actor.sprite.offset.x)*actor.sprite.pixel_size+Vector3.UP*(128.0-pixel.y+actor.sprite.offset.y)*actor.sprite.pixel_size
        var projected: Vector2 = scene.camera.unproject_position(location)
        minimum = minimum.min(projected)
        maximum = maximum.max(projected)
        forward = forward and not scene.camera.is_position_behind(location)
    var size: Vector2 = scene.camera.get_viewport().get_visible_rect().size
    var inset := minf(minf(minimum.x,minimum.y),minf(size.x-maximum.x,size.y-maximum.y))
    return {"forward":forward,"inset":inset,"bounds":[minimum.x,minimum.y,maximum.x,maximum.y]}

func core_invariants() -> void:
    await place(Vector3(-5,0,9))
    check(center_error()<=1.0,"startup_centered",{"pixel_error":center_error(),"pivot":array3(pivot()),"player":array3(scene.player.position)})
    var before: Transform3D = scene.camera.global_transform
    var profiles: Dictionary = scene.rig.lens_profiles_snapshot()
    var before_id: String = scene.rig.variant_id
    check(not scene.select_variant("O"),"O_selection_rejected")
    check(scene.rig.variant_id==before_id and scene.camera.global_transform.is_equal_approx(before) and scene.rig.lens_profiles_snapshot()==profiles,"O_selection_no_state_change")
    check(not scene.rig.restore_lens_profiles(profiles,"O",scene.player.position),"O_profile_restore_rejected")
    check(scene.rig.variant_id==before_id and scene.camera.global_transform.is_equal_approx(before) and scene.rig.lens_profiles_snapshot()==profiles,"O_profile_restore_no_state_change")
    var orbit_pose: Dictionary = scene.rig.pose_snapshot()
    orbit_pose.variant_id = "O"
    scene.rig.restore_pose(orbit_pose)
    check(scene.rig.variant_id==before_id and scene.camera.global_transform.is_equal_approx(before) and scene.rig.lens_profiles_snapshot()==profiles,"O_pose_restore_no_state_change")
    check(profiles.size()==2 and profiles.has("F") and profiles.has("W"),"runtime_only_F_W_profiles")
    check(absf(scene.rig.yaw_degrees)<.0001 and absf(scene.camera.rotation.y)<.0001,"fixed_horizontal_orientation")

func drive(label: String,direction: Vector2,frames: int,require_center := true) -> Dictionary:
    scene.player.scripted_direction = direction
    var start: Vector3 = scene.player.position
    var error := 0.0
    var height_error := 0.0
    var yaw_error := 0.0
    var low: float = scene.player.position.y
    var high: float = low
    var covered: Dictionary = {}
    var grounded := 0
    for index in frames:
        await physics_frame
        scene.camera_update(1.0/60.0)
        error = maxf(error,center_error())
        maximum_center_error = maxf(maximum_center_error,error) if require_center else maximum_center_error
        height_error = maxf(height_error,absf(pivot().y-scene.player.position.y-CENTER_HEIGHT))
        yaw_error = maxf(yaw_error,absf(scene.camera.rotation.y))
        low = minf(low,scene.player.position.y)
        high = maxf(high,scene.player.position.y)
        covered[scene.player.facing] = true
        if scene.player.is_on_floor(): grounded += 1
    var detail := {"id":label,"frames":frames,"start":array3(start),"end":array3(scene.player.position),"center_error_px":error,"pivot_height_error_m":height_error,"yaw_error_radians":yaw_error,"min_foot_y":low,"max_foot_y":high,"grounded_frames":grounded,"directions":covered.keys()}
    movement.append(detail)
    if require_center: check(error<=1.0,label+"_immediate_center",detail)
    if require_center: check(height_error<.0001,label+"_follows_actual_foot_height",detail)
    check(yaw_error<.0001,label+"_horizontal_yaw_fixed",detail)
    return detail

func actual_walks() -> void:
    for variant in ["F","W"]:
        check(scene.select_variant(variant),"walk_select_"+variant)
        scene.reset_lens()
        for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
            await place(Vector3(-6,0,9))
            var name: String = variant+"_direction_"+str(direction)
            var outbound := await drive(name,direction,30)
            check(Vector3(outbound.end[0],outbound.end[1],outbound.end[2]).distance_to(Vector3(outbound.start[0],outbound.start[1],outbound.start[2]))>1.4,name+"_actual_physics_moved")
            await drive(name+"_reverse",-direction,30)
            var stopped := await drive(name+"_stop",Vector2.ZERO,14)
            check(Vector3(stopped.end[0],stopped.end[1],stopped.end[2]).distance_to(Vector3(stopped.start[0],stopped.start[1],stopped.start[2]))<.01,name+"_stop_has_no_camera_lag")
        await place(Vector3(1.2,0,7.3))
        var bridge := await drive(variant+"_bridge",Vector2.UP,200)
        check(bridge.max_foot_y>.5 and bridge.grounded_frames>=195 and float(bridge.end[2])<-1.7,variant+"_actual_bridge_height_and_crossing",bridge)
        await drive(variant+"_bridge_reverse",Vector2.DOWN,200)
        await place(Vector3(scene.layout.dock.center_x,0,scene.layout.dock.approach_z+.2))
        var dock := await drive(variant+"_dock_downhill",Vector2.UP,42)
        check(dock.min_foot_y<-.25 and dock.grounded_frames>=38,variant+"_actual_dock_downhill",dock)
        var bank := await drive(variant+"_dock_uphill",Vector2.DOWN,42)
        check(bank.max_foot_y>-.03 and bank.grounded_frames>=38,variant+"_actual_dock_returns_to_bank",bank)
    scene.player.scripted_direction = Vector2.ZERO

func all_frames_visible(label: String) -> Dictionary:
    var least_inset := INF
    var failed: Array[Dictionary] = []
    var initial_pose: Transform3D = scene.camera.global_transform
    var initial_feet: Vector3 = scene.player.position
    var maximum_pose_motion := 0.0
    for direction in range(4):
        scene.player.direction_override = direction
        for frame in range(27):
            scene.player.frame_override = frame
            scene.player.update_animation()
            scene.camera_update(1.0/60.0)
            var projected := frame_bounds()
            least_inset = minf(least_inset,float(projected.inset))
            maximum_pose_motion = maxf(maximum_pose_motion,scene.camera.global_position.distance_to(initial_pose.origin))
            if not projected.forward or float(projected.inset)<1.999:
                if failed.size()<8: failed.append({"direction":direction,"frame":frame,"projected":projected})
            total_projected_frames += 1
    check(failed.is_empty(),label+"_108_frames_have_2px_inset",{"minimum_inset_px":least_inset,"failures":failed})
    check(maximum_pose_motion<.00001 and scene.player.position==initial_feet,label+"_animation_does_not_move_camera_or_feet")
    return {"minimum_inset_px":least_inset,"frames":108,"failed_examples":failed}

func projection_matrix() -> void:
    scene.player.paused = true
    for size in SIZES:
        root.size = size
        root.content_scale_size = size
        await process_frame
        for variant in ["F","W"]:
            check(scene.select_variant(variant),"matrix_select_"+variant+"_"+str(size))
            var lenses: Array = [scene.rig.lens_defaults(variant)]
            for distance in [18.0,45.0]:
                for field in [25.0,60.0]: lenses.append({"radius":distance,"fov":field})
            for lens in lenses:
                check(scene.set_lens("radius",lens.radius) and scene.set_lens("fov",lens.fov),"matrix_supported_lens_"+variant+"_"+str(size)+"_"+str(lens))
                for location in EDGES:
                    await place(location)
                    var label: String = variant+"_"+str(size)+"_"+str(lens)+"_"+str(location)
                    var result := all_frames_visible(label)
                    result.merge({"id":label,"feet":array3(scene.player.position),"camera":scene.rig.pose_diagnostics()},true)
                    if scene.rig.has_method("follow_diagnostics"): result["follow"] = scene.rig.follow_diagnostics()
                    matrix.append(result)
                    check(absf(scene.camera.rotation.y)<.0001,label+"_yaw_zero")
    scene.player.direction_override = -1
    scene.player.frame_override = -1
    scene.player.paused = false
    root.size = SIZES[0]
    root.content_scale_size = SIZES[0]
    await process_frame

func edge_axis_and_restore() -> void:
    for variant in ["F","W"]:
        scene.select_variant(variant)
        scene.reset_lens()
        for side in [-1.0,1.0]:
            await place(Vector3(side*25,0,9))
            var edge_start := pivot()
            await place(Vector3(side*25.64,0,10))
            var edge_end := pivot()
            check(absf(edge_end.x-edge_start.x)<.001 and absf(edge_end.z-edge_start.z-1)<.001,variant+"_x_edge_limits_only_x_"+str(side),{"start":array3(edge_start),"end":array3(edge_end)})
        for z in [-15.64,13.64]:
            await place(Vector3(-6,0,z))
            var edge_start := pivot()
            await place(Vector3(-5,0,z))
            var edge_end := pivot()
            check(absf(edge_end.z-edge_start.z)<.001 and absf(edge_end.x-edge_start.x-1)<.001,variant+"_z_edge_limits_only_z_"+str(z),{"start":array3(edge_start),"end":array3(edge_end)})
        await place(Vector3(24,0,9))
        var previous := pivot()
        var maximum_jump := 0.0
        for step in range(141):
            scene.player.position = Vector3(24.0-float(step)*.1,0,9)
            scene.camera_update(1.0/60.0)
            maximum_jump = maxf(maximum_jump,pivot().distance_to(previous))
            previous = pivot()
        check(maximum_jump<.101 and center_error()<=1.0,variant+"_edge_to_interior_continuous",{"max_pivot_step_m":maximum_jump,"center_error_px":center_error()})

func controls_remain_available() -> void:
    scene.select_variant("F")
    scene.reset_lens()
    await place(Vector3(-6,0,9))
    check(scene.set_parameter("camera_follow",false),"follow_can_be_disabled")
    var off_pose: Transform3D = scene.camera.global_transform
    await drive("follow_disabled",Vector2.RIGHT,24,false)
    check(scene.camera.global_transform.is_equal_approx(off_pose),"disabled_camera_remains_fixed")
    check(scene.set_parameter("camera_follow",true),"follow_can_be_reenabled")
    check(center_error()<=1.0,"reenabled_follow_centers_immediately")
    var before: Dictionary = scene.rig.pose_snapshot()
    scene.toggle_comparison()
    check(scene.camera_locked and not scene.comparison_snapshot.is_empty(),"fixed_comparison_available")
    var locked: Transform3D = scene.camera.global_transform
    check(not scene.select_variant("W") and not scene.set_lens("radius",32.0),"comparison_rejects_camera_changes")
    scene.camera_update(1.0/60.0)
    check(scene.camera.global_transform.is_equal_approx(locked),"comparison_pose_fixed")
    scene.toggle_comparison()
    check(not scene.camera_locked and scene.camera.global_transform.is_equal_approx(before.transform),"comparison_restores_original_pose")
    var lamp_id: String = scene.selected_lamp_id
    check(scene.select_lamp(lamp_id),"single_lamp_selection_available")
    scene.isolate_selected_lamp()
    check(not scene.lamp_isolation_snapshot.is_empty(),"single_lamp_isolation_available")
    check(scene.camera_locked and scene.isolated_lamp_id==lamp_id,"single_lamp_locks_camera")
    scene.restore_lamp_isolation()
    check(not scene.camera_locked and scene.isolated_lamp_id.is_empty(),"single_lamp_restore_available")
    check(scene.set_parameter("dof_near",true) and scene.set_parameter("dof_far",true),"both_dof_controls_available")
    check(scene.set_parameter("parallax_mode","artistic"),"artistic_parallax_available")
    scene.camera_update(0,true)
    check(center_error()<=1.0,"effects_do_not_change_centering")
    scene.set_parameter("parallax_mode","natural")

func write_report() -> void:
    var report := {"passed":failures.is_empty(),"entry":ENTRY,"runtime_fingerprint":fingerprint,"checks":checks,"failures":failures,"matrix":matrix,"movement":movement,"total_projected_frames":total_projected_frames,"maximum_interior_center_error_px":maximum_center_error,"scope":"Headless real CharacterBody3D motion and Camera3D projection only. No native window, GPU rendering, appearance or user visual acceptance claimed.","physics_hz":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,"display_backend":DisplayServer.get_name(),"baseline_only":baseline_only}
    if scene.rig.has_method("follow_diagnostics"): report["follow_diagnostics"] = scene.rig.follow_diagnostics()
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
    var file := FileAccess.open(destination,FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  ")+"\n")
    print("CENTER_FOLLOW_DONE passed=",report.passed," checks=",checks.size()," projected_frames=",total_projected_frames," failures=",failures.size())

func run() -> void:
    if not destination.begins_with("res://build/ancient-canal/") or not destination.ends_with(".json"):
        print("CENTER_FOLLOW_FAIL invalid report destination")
        quit(1)
        return
    scene = load(ENTRY).instantiate()
    root.add_child(scene)
    scene.frozen = true
    scene.player.controls_enabled = true
    scene.player.scripted_input = true
    await settle()
    check(DisplayServer.get_name()=="headless","headless_scope_only")
    check(not scene.settings_load_attempted,"user_settings_not_loaded")
    await core_invariants()
    if not baseline_only:
        await actual_walks()
        await projection_matrix()
        await edge_axis_and_restore()
        await controls_remain_available()
    write_report()
    scene.queue_free()
    await process_frame
    quit(0 if failures.is_empty() else 1)
