extends SceneTree
## Background GPU capture: no user input, no focus, no visible game window.
var viewport: SubViewport
var output := "res://build/ancient-canal/render"
var runtime_fingerprint := ""
var screenshots: Array = []

func _initialize() -> void:
    root.set_flag(Window.FLAG_NO_FOCUS,true)
    root.gui_embed_subwindows = true
    viewport = SubViewport.new()
    viewport.size = Vector2i(1920,1080)
    viewport.own_world_3d = true
    viewport.gui_embed_subwindows = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--canal-output="): output = arg.trim_prefix("--canal-output=")
        if arg.begins_with("--canal-fingerprint="): runtime_fingerprint = arg.trim_prefix("--canal-fingerprint=")
    output = ProjectSettings.globalize_path(output)
    DirAccess.make_dir_recursive_absolute(output)
    call_deferred("run")

func _process(_delta: float) -> bool:
    RenderingServer.force_draw()
    return false

func snapshot(name: String) -> void:
    for i in range(3): await process_frame
    await RenderingServer.frame_post_draw
    var image: Image = viewport.get_texture().get_image()
    image.save_png(output.path_join(name+".png"))
    screenshots.append({"path":"render/"+name+".png","sha256":FileAccess.get_sha256(output.path_join(name+".png")),"scope":"Actual hardware GPU 1080p scene snapshot: "+name})

func run() -> void:
    root.set_flag(Window.FLAG_NO_FOCUS,true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
    for i in 5: await process_frame
    var scene = load("res://scenes/ancient_canal.tscn").instantiate()
    viewport.add_child(scene)
    for i in range(20): await physics_frame
    scene.frozen = true
    scene.player.set_physics_process(false)
    # Keep the position settled on the bank by the actual physics warmup.
    scene.player.velocity = Vector3.ZERO
    scene.camera_update(0,true)
    scene.overlay.hide()
    await snapshot("dusk-default")
    for id in ["day","night"]:
        scene.apply_time_preset(id)
        await snapshot(id+"-default")
    scene.apply_time_preset("dusk")
    # Current forward-camera variants, real background depth and lamp layouts.
    for id in ["W","O"]:
        scene.select_variant(id)
        await snapshot("lens-"+id)
    scene.select_variant("F")
    scene.set_parameter("fog",0.0)
    await snapshot("no-fog-background")
    var spawn: Vector3 = scene.player.position
    for label in ["left-bank","right-bank"]:
        scene.player.position = Vector3(-8 if label=="left-bank" else 8,0,-7)
        scene.camera_update(0,true)
        await snapshot("route-"+label)
    scene.player.position = spawn
    scene.camera_update(0,true)
    scene.restore_defaults()
    scene.overlay.show()
    scene.console.open()
    for page in range(4):
        scene.console.tabs.current_tab = page
        await snapshot("console-"+str(page))
    for page in [1,2]:
        scene.console.tabs.current_tab = page
        var scroll: ScrollContainer = scene.console.tabs.get_tab_control(page)
        scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
        await snapshot("console-"+str(page)+"-details")
    scene.console.close()
    scene.overlay.hide()
    scene.camera_locked = true
    scene.camera.position = scene.player.position+Vector3(0,1.1,4.8)
    scene.camera.look_at(scene.player.position+Vector3.UP*1.02)
    scene.values.dof_far = false
    scene.values.dof_near = false
    scene.values.fog = 0.0
    scene.values.animation_pause = true
    scene.values.animation_frame = 11
    scene.values.direction = "right"
    scene.apply_parameters()
    await snapshot("role-native")
    scene.values.normals_enabled = false
    scene.apply_parameters()
    await snapshot("role-no-normal")
    scene.values.normals_enabled = true
    scene.values.clay = true
    scene.apply_parameters()
    await snapshot("role-clay")
    scene.values.clay = false
    scene.values.normal_debug = true
    scene.apply_parameters()
    await snapshot("role-normal-data")
    scene.values.normal_debug = false
    scene.values.shading_mode = "stepped"
    scene.apply_parameters()
    await snapshot("role-stepped-4")
    scene.values.shading_mode = "native"
    scene.values.silver_specular = 0.0
    scene.apply_parameters()
    await snapshot("role-no-silver")
    var report := {"runtime_fingerprint":runtime_fingerprint,"passed":DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED and root.get_flag(Window.FLAG_NO_FOCUS),"gpu":true,"viewport":[1920,1080],"screenshots":screenshots,"hardware_gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"size":[1920,1080],"main_window_minimized":DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED,"no_focus":root.get_flag(Window.FLAG_NO_FOCUS),"normals_loaded":not scene.player.normal_definition.is_empty(),"model_loaded":scene.geometry_ready,"npc_materials":scene.npc_materials.size()}
    var file := FileAccess.open(output.path_join("quick-report.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  ")+"\n")
    print("CANAL_CAPTURE_DONE ",JSON.stringify(report))
    quit(0 if report.passed else 1)
