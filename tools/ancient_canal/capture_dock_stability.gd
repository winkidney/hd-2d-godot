extends SceneTree
## Actual GPU dock regression. Motion uses the actor's normal move_and_slide.
## Fixed +/-0.5 mm probes isolate surface instability from ordinary pixel edges.
const SIZE := Vector2i(1920,1080)
const MICRO_FRAMES := 24
const MICRO_OFFSET := 0.0005
const PHYSICS_HZ := 60
const FLOOR_POINTS := [Vector3(2.85,-.32,7.85),Vector3(4.45,-.32,7.85),
    Vector3(4.45,-.32,8.36),Vector3(2.85,-.32,8.36)]
const DOCK_POINTS := [Vector3(2.65,-.32,5.5125),Vector3(4.65,-.32,5.5125),
    Vector3(4.65,-.32,8.4875),Vector3(2.65,-.32,8.4875)]
const CONTROL_POINTS := [Vector3(6.2,0,7.8),Vector3(7.4,0,7.8),
    Vector3(7.4,0,8.3),Vector3(6.2,0,8.3)]
const LEGACY_ROIS := {"dock_floor":[1160,1030,1380,1070],
    "dock_posts":[1200,925,1310,1010],"right_wall":[1260,330,1430,455]}
var output := "res://build/ancient-canal/dock-stability"
var evidence_prefix := "dock-stability"
var fingerprint := ""
var viewport: SubViewport
var scene
var frames: Array[Dictionary] = []
var motion_cases: Array[Dictionary] = []
var micro_groups: Array[Dictionary] = []
var failures: Array[String] = []
var trajectory: Array[Dictionary] = []
var recording := false
var movement_variant := ""
var phase := "warming"
var start_usec := 0
var next_sample_tick := 0
var previous_tick := -1
var attempted_slots := 0
var skipped_slots := 0
var draw_requests := 0
var post_draw_sequence := 0
var launch_state: Dictionary = {}
var check_only := false

func command_state() -> Dictionary:
    var result := {"process_command_complete":false,"fixed_fps_flag_present":true,
        "disabled_render_loop":false,"preferences_ignored_requested":false}
    if ClassDB.class_has_method("RenderingServer","is_render_loop_enabled"):
        result.disabled_render_loop = RenderingServer.call("is_render_loop_enabled") == false
    var source := FileAccess.open("/proc/self/cmdline",FileAccess.READ)
    if source != null:
        var bytes := source.get_buffer(65536)
        source.close()
        if not bytes.is_empty() and bytes.size()<65536 and bytes[-1]==0:
            result.process_command_complete = true
            result.fixed_fps_flag_present = false
            var argument_bytes := PackedByteArray()
            for byte in bytes:
                if byte==0:
                    var argument := argument_bytes.get_string_from_utf8()
                    if argument=="--fixed-fps" or argument.begins_with("--fixed-fps="):
                        result.fixed_fps_flag_present = true
                    argument_bytes.clear()
                else:
                    argument_bytes.append(byte)
    result.preferences_ignored_requested = "--ignore-user-settings" in OS.get_cmdline_user_args()
    return result

func require(ok: bool, label: String) -> void:
    if not ok and label not in failures:
        failures.append(label)
        push_error(label)

func _initialize() -> void:
    check_only = "--canal-dock-check-only" in OS.get_cmdline_user_args()
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--canal-dock-dir="): output = argument.trim_prefix("--canal-dock-dir=")
        elif argument.begins_with("--canal-fingerprint="): fingerprint = argument.trim_prefix("--canal-fingerprint=")
    if check_only:
        print("DOCK_CAPTURE_SCHEMA_OK ",JSON.stringify({"size":[SIZE.x,SIZE.y],"micro_frames_per_group":MICRO_FRAMES,
            "groups":["legacy_projection","F","W"],"offset_metres":MICRO_OFFSET,
            "motion_phases":["bank_stop","down_slope","dock_stop","up_slope","return_stop"],
            "gpu_performed":false}))
        quit(0)
        return
    launch_state = command_state()
    output = ProjectSettings.globalize_path(output).simplify_path()
    var evidence_root := ProjectSettings.globalize_path("res://build/ancient-canal").simplify_path()
    if not output.begins_with(evidence_root+"/"):
        print("DOCK_CAPTURE_REFUSED output outside evidence tree")
        quit(1)
        return
    evidence_prefix = output.trim_prefix(evidence_root+"/")
    var pattern := RegEx.new()
    pattern.compile("^[0-9a-f]{64}$")
    require(pattern.search(fingerprint)!=null,"current runtime fingerprint is required")
    require(launch_state.process_command_complete and not launch_state.fixed_fps_flag_present,"actual dock capture command must not use fixed FPS")
    require(launch_state.disabled_render_loop,"dock capture requires the actual render loop disabled")
    require(launch_state.preferences_ignored_requested,"dock capture must ignore everyday user preferences")
    root.set_flag(Window.FLAG_NO_FOCUS,true)
    root.transparent_bg = false
    root.gui_embed_subwindows = true
    RenderingServer.set_default_clear_color(Color.BLACK)
    Engine.time_scale = 1.0
    Engine.physics_ticks_per_second = PHYSICS_HZ
    Engine.max_fps = 60
    OS.low_processor_usage_mode = false
    viewport = SubViewport.new()
    viewport.size = SIZE
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    RenderingServer.frame_post_draw.connect(on_post_draw)
    call_deferred("run")

func on_post_draw() -> void:
    post_draw_sequence += 1

func _process(_delta: float) -> bool:
    if check_only or viewport==null or DisplayServer.get_name()=="headless": return false
    draw_requests += 1
    RenderingServer.force_draw()
    if recording and is_instance_valid(scene):
        var tick := Engine.get_physics_frames()
        if tick >= next_sample_tick and tick != previous_tick:
            var slots := 1 + int((tick-next_sample_tick)/2)
            attempted_slots += slots
            skipped_slots += slots-1
            next_sample_tick += slots*2
            previous_tick = tick
            capture("motion",movement_variant,phase)
    return false

func vector_array(value: Vector3) -> Array:
    return [value.x,value.y,value.z]

func polygon(points: Array) -> Array:
    var result: Array = []
    for point in points:
        var projected: Vector2 = scene.camera.unproject_position(point)
        result.append([projected.x,projected.y])
    return result

func capture(kind: String, variant: String, state: String, extra := {}) -> void:
    var read_start := Time.get_ticks_usec()
    var image := viewport.get_texture().get_image()
    if image.is_empty() or image.get_size()!=SIZE:
        require(false,"actual GPU image must be complete 1080p")
        return
    var name := "frame-%05d.png" % frames.size()
    var destination := output.path_join("frames").path_join(name)
    var entry := {"index":frames.size(),"file":evidence_prefix+"/frames/"+name,
        "kind":kind,"variant":variant,"phase":state,"physics_index":Engine.get_physics_frames(),
        "wall_elapsed_ms":float(read_start-start_usec)/1000.0,"post_draw_sequence":post_draw_sequence,
        "camera_position":vector_array(scene.camera.global_position),"camera_fov":scene.camera.fov,
        "world_foot":vector_array(scene.player.global_position),"velocity":vector_array(scene.player.get_real_velocity()),
        "on_floor":scene.player.is_on_floor(),"animation_frame":scene.player.animation_frame,
        "direction":scene.player.animation.DIRECTIONS[scene.player.facing],
        "floor_polygon":polygon(FLOOR_POINTS),"dock_polygon":polygon(DOCK_POINTS),"bank_polygon":polygon(CONTROL_POINTS),
        "water_clock":scene.water_clock,"time_preset":scene.values.time_preset,
        "world_frozen":scene.frozen,"camera_locked":scene.camera_locked,
        "dof_near":scene.values.dof_near,"dof_far":scene.values.dof_far,
        "dof_amount":scene.values.dof_amount,"focus_protection":scene.values.focus_protection,
        "scene_shadow":scene.values.scene_shadow,"ssao":scene.values.ssao,"water_reflection":scene.values.water_reflection}
    entry.merge(extra,true)
    var error := image.save_png(destination)
    require(error==OK,"cannot save dock PNG")
    entry["sha256"] = FileAccess.get_sha256(destination) if error==OK else ""
    entry["readback_and_png_ms"] = float(Time.get_ticks_usec()-read_start)/1000.0
    frames.append(entry)
    if kind=="motion": trajectory.append(entry.duplicate(true))

func wait_physics(count: int) -> void:
    var end := Engine.get_physics_frames()+count
    while Engine.get_physics_frames()<end: await process_frame

func hide_ui() -> void:
    scene.console.close()
    scene.dialogue.hide()
    scene.exit_confirmation.hide()
    scene.overlay.hide()

func new_scene() -> void:
    if is_instance_valid(scene):
        scene.queue_free()
        await process_frame
        await physics_frame
    scene = load("res://scenes/ancient_canal.tscn").instantiate()
    viewport.add_child(scene)
    await wait_physics(30)
    require(not scene.settings_load_attempted,"dock scene must ignore user settings")
    hide_ui()
    scene.apply_time_preset("dusk")

func micro_probe(id: String) -> void:
    scene.camera_locked = false
    if id!="legacy_projection":
        require(scene.select_variant(id),"cannot select current dock camera " + id)
        scene.reset_lens()
        scene.camera_update(0,true)
    scene.player.set_physics_process(false)
    scene.player.velocity = Vector3.ZERO
    scene.values.animation_pause = true
    scene.apply_parameters()
    scene.camera_locked = true
    scene.frozen = true
    var pivot: Vector3 = scene.rig.target+scene.rig.follow_offset
    if id=="legacy_projection":
        # Match the documented historic camera recipe, using today's scene.
        pivot = Vector3(.5,1.5,0)
        scene.camera.fov = 38.0
        scene.camera.position = pivot+Vector3(0,sin(deg_to_rad(20.0)),cos(deg_to_rad(20.0))).rotated(Vector3.UP,deg_to_rad(10.0))*20.0
        scene.camera.look_at(pivot)
    scene.update_focus()
    for warm in range(8): await process_frame
    var home: Vector3 = scene.camera.position
    var first := frames.size()
    for index in range(MICRO_FRAMES):
        var perturbation := MICRO_OFFSET if index%2 else -MICRO_OFFSET
        scene.camera.position = home+Vector3(perturbation,0,0)
        scene.camera.look_at(pivot)
        scene.update_focus()
        await create_timer(1.0/30.0).timeout
        await RenderingServer.frame_post_draw
        capture("micro",id,"fixed_world",{"micro_index":index,"camera_dx_metres":perturbation})
    micro_groups.append({"id":id,"first_index":first,"frame_count":frames.size()-first,
        "base_camera_position":vector_array(home),"pivot":vector_array(pivot),"fov":scene.camera.fov,
        "roi_policy":"historic fixed rectangle" if id=="legacy_projection" else "projected interior dock front planks, eroded one pixel",
        "fixed_roi":LEGACY_ROIS.dock_floor if id=="legacy_projection" else []})

func drive_until(direction: Vector2, target_x: float, downhill: bool) -> bool:
    scene.player.scripted_direction = direction
    var start := Time.get_ticks_msec()
    while (scene.player.position.x>target_x if downhill else scene.player.position.x<target_x):
        if Time.get_ticks_msec()-start>10000:
            require(false,"actual dock movement timed out " + movement_variant + " " + phase)
            return false
        await process_frame
    scene.player.scripted_direction = Vector2.ZERO
    return true

func motion_probe(id: String) -> void:
    await new_scene()
    scene.player.position = Vector3(5.95,.12,7)
    scene.player.velocity = Vector3.ZERO
    scene.values.direction = "auto"
    scene.values.animation_pause = false
    scene.values.camera_follow = true
    scene.apply_parameters()
    require(scene.select_variant(id),"cannot select moving dock camera " + id)
    await wait_physics(30)
    scene.player.scripted_input = true
    scene.player.controls_enabled = true
    scene.player.scripted_direction = Vector2.ZERO
    movement_variant = id
    next_sample_tick = Engine.get_physics_frames()+2
    previous_tick = -1
    var first := frames.size()
    recording = true
    phase = "bank_stop"
    var bank_start: Vector3 = scene.player.position
    await wait_physics(60)
    phase = "down_slope"
    var down_ok := await drive_until(Vector2.LEFT,4.03,true)
    phase = "dock_stop"
    await wait_physics(60)
    var dock_foot: Vector3 = scene.player.position
    phase = "up_slope"
    var up_ok := await drive_until(Vector2.RIGHT,5.85,false)
    phase = "return_stop"
    await wait_physics(60)
    var returned: Vector3 = scene.player.position
    recording = false
    scene.player.scripted_input = false
    var return_error := Vector2(returned.x-bank_start.x,returned.z-bank_start.z).length()
    var passed: bool = down_ok and up_ok and dock_foot.y<-.27 and dock_foot.y>-.34 and absf(returned.y)<.04 and absf(returned.z-7)<.08 and return_error<.2 and scene.player.is_on_floor()
    require(passed,"physical dock down/stop/up sequence failed " + id)
    motion_cases.append({"id":id,"first_index":first,"frame_count":frames.size()-first,"passed":passed,
        "initial_placement_only":true,"movement_api":"normal CharacterBody3D scripted_direction + move_and_slide, no per-frame teleport",
        "bank_start":vector_array(bank_start),"dock_foot":vector_array(dock_foot),"returned_foot":vector_array(returned),
        "return_horizontal_error_metres":return_error,
        "downhill_completed":down_ok,"uphill_completed":up_ok,"camera_follow":scene.values.camera_follow,
        "physics_ticks_per_second":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale})

func surface_audit() -> Dictionary:
    var floor: Node3D = scene.world.get_node("DockFloor")
    var mesh_count: int = floor.find_children("*","MeshInstance3D",true,false).size()
    var collisions: Array[Node] = floor.find_children("*","CollisionShape3D",true,false)
    require(mesh_count==0 and collisions.size()==1,"final DockFloor must have collision only")
    return {"DockFloor":{"visible_mesh_count":mesh_count,"collision_count":collisions.size(),
        "position":vector_array(floor.position),"collision_top_y":-.32},
        "dock_plank_world_top_y":-.32,"dock_model_sha256":FileAccess.get_sha256("res://assets/ancient-canal/models/dock.glb"),
        "DockApproach":"separate sloped visible and collision surface; retained",
        "banks":"right-bank opening retained around dock and approach; decorative strips meet only at z=-16/-126",
        "bridge_helpers":"walk/rail visual meshes restricted to greybox; collisions retained",
        "water_y":scene.layout.river.water_y}

func run() -> void:
    var adapter := RenderingServer.get_video_adapter_name()
    var hardware := not adapter.is_empty() and not adapter.to_lower().contains("llvmpipe") and not adapter.to_lower().contains("lavapipe") and not adapter.to_lower().contains("swiftshader")
    require(DisplayServer.get_name()!="headless" and hardware,"dock visual evidence requires a real hardware GPU display backend")
    require(RenderingServer.get_current_rendering_method()=="forward_plus","dock capture requires Forward+")
    if DisplayServer.get_name()!="headless":
        root.set_flag(Window.FLAG_NO_FOCUS,true)
        DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
    for startup in range(5): await process_frame
    var minimized := DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED if DisplayServer.get_name()!="headless" else false
    require(minimized and root.get_flag(Window.FLAG_NO_FOCUS) and root.visible,"dock capture window must remain minimized and no focus")
    if DirAccess.dir_exists_absolute(output):
        print("DOCK_CAPTURE_REFUSED output already exists")
        quit(1)
        return
    require(DirAccess.make_dir_recursive_absolute(output.path_join("frames"))==OK,"cannot create new dock evidence directory")
    var report := {"schema_version":1,"runtime_fingerprint":fingerprint,"adapter":adapter,"hardware_gpu":hardware,
        "producer_script":"tools/ancient_canal/capture_dock_stability.gd",
        "producer_script_sha256":FileAccess.get_sha256("res://tools/ancient_canal/capture_dock_stability.gd"),
        "renderer":RenderingServer.get_current_rendering_method(),"display_driver":DisplayServer.get_name(),"size":[SIZE.x,SIZE.y],
        "main_window_minimized":minimized,"no_focus_flag":root.get_flag(Window.FLAG_NO_FOCUS),"root_hidden":not root.visible,
        "viewport_own_world_3d":viewport.own_world_3d,"time_scale":Engine.time_scale,"physics_ticks_per_second":Engine.physics_ticks_per_second,
        "capture_scope":"Actual independent 1080p GPU SubViewport; fixed micro camera probes and real dock motion; not a throughput benchmark",
        "timing_policy":"Actual wall/physics timestamps; synchronous PNG cost and sampling gaps retained; no assumed 30fps clock",
        "criterion":{"fraction_above_16_max":.01,"delta_255":16,"micro_camera_metres":MICRO_OFFSET,"frames_per_group":MICRO_FRAMES},
        "floor_world_points":FLOOR_POINTS.map(vector_array),"legacy_rois":LEGACY_ROIS,"passed":false}
    report.merge(launch_state,true)
    if failures.is_empty():
        start_usec = Time.get_ticks_usec()
        await new_scene()
        report["surface_audit"] = surface_audit()
        for id in ["legacy_projection","F","W"]: await micro_probe(id)
        for id in ["F","W"]: await motion_probe(id)
    report["micro_groups"] = micro_groups
    report["motion_cases"] = motion_cases
    report["frames"] = frames
    report["trajectory"] = trajectory
    report["sampling"] = {"attempted_slots":attempted_slots,"skipped_slots":skipped_slots,"capture_every_physics_frames":2,
        "recorded_motion_frames":trajectory.size(),"sampling_complete":skipped_slots==0}
    report["wall_duration_ms"] = float(Time.get_ticks_usec()-start_usec)/1000.0 if start_usec>0 else 0.0
    report["draw_requests"] = draw_requests
    report["post_draw_sequence"] = post_draw_sequence
    report["main_window_minimized"] = DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED if DisplayServer.get_name()!="headless" else false
    report["no_focus_flag"] = root.get_flag(Window.FLAG_NO_FOCUS)
    require(report.main_window_minimized and report.no_focus_flag,"window contract changed during dock capture")
    require(Engine.time_scale==1.0 and Engine.physics_ticks_per_second==PHYSICS_HZ,"actual dock simulation timing changed")
    report["failures"] = failures
    report["passed"] = failures.is_empty() and micro_groups.size()==4 and motion_cases.size()==3
    var file := FileAccess.open(output.path_join("dock-capture-report.json"),FileAccess.WRITE)
    if file==null:
        print("DOCK_CAPTURE_FAILED cannot write report")
        quit(1)
        return
    file.store_string(JSON.stringify(report,"  ")+"\n")
    file.close()
    print("DOCK_CAPTURE_DONE passed=",report.passed," frames=",frames.size()," failures=",failures.size())
    quit(0 if report.passed else 1)
