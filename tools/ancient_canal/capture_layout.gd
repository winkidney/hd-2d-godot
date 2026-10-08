extends "res://tools/ancient_canal/capture.gd"
## Current revision only. Readback captures are separate from performance samples.
var video_frames: Array = []
var writes: Array = []
var micro_groups: Array = []
var write_failures: Array = []

func record_frame(scene: Node3D, started: int, folder: String) -> void:
    await RenderingServer.frame_post_draw
    var path := folder.path_join("%05d.png" % video_frames.size())
    for index in range(writes.size()-1,-1,-1):
        if WorkerThreadPool.is_task_completed(writes[index].task):
            WorkerThreadPool.wait_for_task_completion(writes[index].task)
            writes.remove_at(index)
    var frame_image := viewport.get_texture().get_image()
    # Callable does not retain a RefCounted Image. Keep it until the task ends.
    writes.append({"task":WorkerThreadPool.add_task(frame_image.save_png.bind(path)),"image":frame_image})
    video_frames.append({"path":path.get_file(),"time_s":float(Time.get_ticks_usec()-started)/1000000.0,
        "sha256":"","foot":[scene.player.position.x,scene.player.position.y,scene.player.position.z],
        "sky_yaw":scene.environment.sky_rotation.y})

func finish_writes(folder: String) -> void:
    for task in writes: WorkerThreadPool.wait_for_task_completion(task.task)
    writes.clear()
    for frame in video_frames:
        frame.sha256=FileAccess.get_sha256(folder.path_join(frame.path))
        if frame.sha256.is_empty(): write_failures.append(folder.path_join(frame.path).get_file())

func dock_micro(scene: Node3D) -> void:
    scene.apply_time_preset("dusk")
    scene.player.position=Vector3(scene.layout.dock.center_x,scene.layout.dock.surface_y,scene.layout.dock.center_z)
    var polygons: Array=[]
    for lens in ["F","W"]:
        scene.select_variant(lens)
        scene.camera_update(0,true)
        scene.update_focus()
        var home: Vector3=scene.camera.position
        var entries: Array=[]
        for index in 24:
            scene.camera.position=home+Vector3(.0005 if index%2 else -.0005,0,0)
            await snapshot("dock-micro-"+lens+"-%02d"%index)
            var points: Array=[]
            for point in [Vector3(-12.65,-.32,3.0),Vector3(-12.25,-.32,3.0),Vector3(-12.25,-.32,3.75),Vector3(-12.65,-.32,3.75)]:
                var pixel: Vector2=scene.camera.unproject_position(point)
                points.append([pixel.x,pixel.y])
            entries.append({"path":"dock-micro-"+lens+"-%02d.png"%index,"camera_dx_m":.0005 if index%2 else -.0005,"plank_polygon":points})
        micro_groups.append({"lens":lens,"frames":entries,"fixed_world":true,"offset_m":.0005,"msaa":viewport.msaa_3d})
        scene.camera.position=home
    scene.select_variant("F")

func overhead_and_side(scene: Node3D) -> void:
    scene.restore_defaults()
    scene.overlay.hide()
    scene.apply_time_preset("day")
    scene.frozen = true
    scene.values.dof_near = false
    scene.values.dof_far = false
    scene.values.fog = 0
    scene.apply_parameters()
    scene.camera_locked = true
    var background_mode: int = scene.environment.background_mode
    var background_color: Color = scene.environment.background_color
    scene.environment.background_mode = Environment.BG_COLOR
    scene.environment.background_color = Color(.16,.19,.21)
    scene.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    scene.camera.size = 76
    scene.camera.position = Vector3(0,90,-18)
    scene.camera.look_at(Vector3(0,0,-18),Vector3.FORWARD)
    await snapshot("actual-top-layout")
    scene.camera.size = 40
    scene.camera.position = Vector3(90,3,-18)
    scene.camera.look_at(Vector3(0,3,-18),Vector3.UP)
    await snapshot("actual-side-layout")
    scene.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
    scene.environment.background_mode = background_mode
    scene.environment.background_color = background_color
    scene.restore_defaults()
    scene.overlay.hide()

func run() -> void:
    OS.low_processor_usage_mode = false
    OS.low_processor_usage_mode_sleep_usec = 0
    viewport.msaa_3d = Viewport.MSAA_2X
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
    for i in 5: await process_frame
    var scene = load("res://scenes/ancient_canal.tscn").instantiate()
    viewport.add_child(scene)
    for i in 30: await physics_frame
    scene.frozen = true
    scene.player.set_physics_process(false)
    scene.overlay.hide()
    if "--layout-only" in OS.get_cmdline_user_args():
        await overhead_and_side(scene)
        FileAccess.open(output.path_join("construction-capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"runtime_fingerprint":runtime_fingerprint,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"viewport":[1920,1080],"screenshots":screenshots,"scope":"Actual orthographic construction views, neutral background; no performance claim."},"  ")+"\n")
        print("CONSTRUCTION_VIEWS_DONE")
        quit()
        return
    for period in (["night"] if "--sky-probe" in OS.get_cmdline_user_args() else ["day","dusk","night"]):
        scene.apply_time_preset(period)
        for lens in (["F"] if "--sky-probe" in OS.get_cmdline_user_args() else ["F","W"]):
            scene.select_variant(lens)
            for i in 30: await process_frame
            await snapshot(period+"-"+lens)
    scene.select_variant("F")
    scene.apply_time_preset("night")
    for i in 30: await process_frame
    await snapshot("night-still-a")
    for i in 30: await process_frame
    await snapshot("night-still-b")
    scene.values.dof_far = false
    scene.values.dof_near = false
    scene.apply_parameters()
    await snapshot("night-no-dof")
    if "--sky-probe" in OS.get_cmdline_user_args():
        quit()
        return
    scene.restore_defaults()
    scene.overlay.hide()
    scene.apply_time_preset("night")
    for label in ["left","right"]:
        scene.player.position = Vector3(-23.5 if label=="left" else 23.5,0,8.5)
        scene.camera_update(0,true)
        scene.update_focus()
        for i in 15: await process_frame
        await snapshot("night-route-"+label)
    for entry in scene.layout.npcs:
        scene.player.position = Vector3(scene.layout.dock.center_x,scene.layout.dock.surface_y,scene.layout.dock.center_z) if entry.id=="boatman" else Vector3(entry.position[0],0,entry.position[2]+.7)
        scene.camera_update(0,true)
        scene.update_focus()
        await snapshot("npc-"+entry.id)
    if "--sky-quick" in OS.get_cmdline_user_args():
        print("LAYOUT_QUICK_DONE sky=",scene.night_sky.active)
        quit()
        return
    await overhead_and_side(scene)
    await dock_micro(scene)
    scene.player.set_physics_process(true)
    scene.frozen = false
    scene.player.position = scene.vec(scene.layout.player_spawn)
    scene.player.velocity = Vector3.ZERO
    scene.apply_time_preset("dusk")
    scene.camera_update(0,true)
    scene.update_focus()
    var folder := output.path_join("route-frames")
    DirAccess.make_dir_recursive_absolute(folder)
    var started := Time.get_ticks_usec()
    var next_sample := 0.0
    scene.start_route()
    while scene.route_running and Time.get_ticks_usec()-started<180000000:
        await process_frame
        if float(Time.get_ticks_usec()-started)/1000000.0>=next_sample:
            await record_frame(scene,started,folder)
            next_sample = float(Time.get_ticks_usec()-started)/1000000.0+.1
    var completed_route: Dictionary = scene.route_result.duplicate(true)
    var route_passed: bool = completed_route.get("passed",false)
    await finish_writes(folder)
    scene.cancel_route()
    var route_elapsed := float(Time.get_ticks_usec()-started)/1000000.0
    var route_frames := video_frames.duplicate(true)
    var night_folder := output.path_join("night-frames")
    DirAccess.make_dir_recursive_absolute(night_folder)
    video_frames.clear()
    scene.apply_time_preset("night")
    scene.player.position = Vector3(-7,0,8.5)
    scene.player.velocity = Vector3.ZERO
    scene.player.scripted_input = true
    started = Time.get_ticks_usec()
    next_sample = 0
    var target := 7.0
    var returning := false
    while Time.get_ticks_usec()-started<20000000:
        scene.player.scripted_direction = Vector2(signf(target-scene.player.position.x),0)
        await process_frame
        if float(Time.get_ticks_usec()-started)/1000000.0>=next_sample:
            await record_frame(scene,started,night_folder)
            next_sample = float(Time.get_ticks_usec()-started)/1000000.0+.1
        if absf(scene.player.position.x-target)<.2:
            if returning: break
            returning = true
            target = -7
    scene.player.scripted_direction = Vector2.ZERO
    scene.player.scripted_input = false
    await finish_writes(night_folder)
    var report := {"passed":route_passed and returning and write_failures.is_empty(),"write_failures":write_failures,"runtime_fingerprint":runtime_fingerprint,
        "gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
        "viewport":[1920,1080],"msaa_3d":viewport.msaa_3d,
        "no_focus":root.get_flag(Window.FLAG_NO_FOCUS),"main_window_minimized":DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED,
        "screenshots":screenshots,"dock_micro_groups":micro_groups,"route_passed":route_passed,"route_elapsed_s":route_elapsed,
        "route_result":completed_route,"route_frames":route_frames,"night_frames":video_frames,
        "capture_scope":"Actual GPU readback with wall-clock frame timestamps; not a performance/FPS measurement"}
    var file := FileAccess.open(output.path_join("horizontal-capture.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  ")+"\n")
    print("HORIZONTAL_CAPTURE_DONE passed=",report.passed," route_frames=",route_frames.size()," night_frames=",video_frames.size())
    quit(0 if report.passed else 1)
