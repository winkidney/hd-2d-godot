extends SceneTree
## Render the real scene into a SubViewport with the native window minimized.
## Run with --disable-render-loop --position 10000,10000; no keyboard injection.
var viewport: SubViewport
var output := "res://build/character-directions/render"
var record := false
var report: Dictionary = {}
var failures: Array[String] = []

func _initialize() -> void:
    root.set_flag(Window.FLAG_NO_FOCUS, true)
    root.hide()
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--character-capture-dir="): output = arg.trim_prefix("--character-capture-dir=")
        if arg == "--character-record": record = true
    output = ProjectSettings.globalize_path(output)
    DirAccess.make_dir_recursive_absolute(output)
    viewport = SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    call_deferred("run")

func _process(_delta: float) -> bool:
    RenderingServer.force_draw()
    return false

func image_after_draw() -> Image:
    await process_frame
    await RenderingServer.frame_post_draw
    return viewport.get_texture().get_image()

func save_image(image: Image, path: String) -> void:
    if image.is_empty() or image.get_size() != Vector2i(1280, 720) or image.save_png(path) != OK:
        failures.append("image_save:" + path.get_file())

func visible_pixels(scene, visible: Image) -> Dictionary:
    var sprite: Sprite3D = scene.player.sprite
    var camera: Camera3D = scene.camera
    var half: Vector2 = sprite.texture.get_size() * sprite.pixel_size * 0.5
    var center: Vector3 = sprite.global_position + camera.global_basis.y * sprite.offset.y * sprite.pixel_size
    var first: Vector2 = camera.unproject_position(center - camera.global_basis.x * half.x + camera.global_basis.y * half.y)
    var last: Vector2 = camera.unproject_position(center + camera.global_basis.x * half.x - camera.global_basis.y * half.y)
    var area := Rect2(first, last - first).abs().intersection(Rect2(Vector2.ZERO, Vector2(viewport.size)))
    sprite.hide()
    var hidden := await image_after_draw()
    sprite.show()
    await image_after_draw()
    var changed := 0
    for y in range(ceili(area.position.y), floori(area.end.y)):
        for x in range(ceili(area.position.x), floori(area.end.x)):
            var a := visible.get_pixel(x, y)
            var b := hidden.get_pixel(x, y)
            if absf(a.r-b.r) + absf(a.g-b.g) + absf(a.b-b.b) > 0.12:
                changed += 1
    var passed := changed >= maxi(40, int(area.get_area() * 0.012))
    if not passed: failures.append("character_not_visible")
    return {"passed": passed, "changed_pixels": changed, "projected_area": area.get_area()}

func freeze_scene(scene) -> void:
    scene.set_process(false)
    scene.player.set_physics_process(false)
    scene.clock_frozen = true
    scene.background.wind_enabled = false
    scene.lighting.water.set_shader_parameter("motion", 0.0)
    scene.hud.container.hide()

func run() -> void:
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
    # The main Window cannot be hidden after engine startup. Keep it minimized and unfocused.
    var adapter := RenderingServer.get_video_adapter_name()
    report = {"renderer": RenderingServer.get_current_rendering_method(), "adapter": adapter,
        "capture_mode": "Minimized no-focus native window; independent offscreen SubViewport", "main_window_scene_visible": root.visible,
        "hardware_gpu": not adapter.is_empty() and not adapter.to_lower().contains("llvmpipe") and not adapter.to_lower().contains("lavapipe"), "main_window_minimized": DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED,
        "size": [1280, 720], "preferences_ignored": true, "scene_entries": [], "clips": [],
        "scope": "Real Sprite3D in project scenes; close-up camera is evidence framing only. Clip playback in place is separate from physical movement tests."}
    for name in ["waystation", "reference_scene", "reference_scene_graybox", "frontal_canal"]:
        var scene = load("res://scenes/" + name + ".tscn").instantiate()
        viewport.add_child(scene)
        for i in range(30): await physics_frame
        freeze_scene(scene)
        report.preferences_ignored = report.preferences_ignored and not scene.settings_load_attempted
        var image := await image_after_draw()
        save_image(image, output.path_join(name + "-default.png"))
        var visibility: Dictionary = await visible_pixels(scene, image)
        report.scene_entries.append({"scene": name, "default_direction": scene.player.animation.DIRECTIONS[scene.player.displayed_facing],
            "frame": scene.player.animation_frame, "foot_anchor_screen": [scene.camera.unproject_position(scene.player.global_position).x, scene.camera.unproject_position(scene.player.global_position).y], "pixel_size": scene.player.sprite.pixel_size, "visibility": visibility,
            "shaded": scene.player.sprite.shaded, "player_in_frustum": scene.camera.is_position_in_frustum(scene.player.global_position + Vector3.UP), "preferences_loaded": scene.settings_load_attempted, "screenshot": name + "-default.png"})
        scene.queue_free()
        for i in range(4): await process_frame
    var scene = load("res://scenes/waystation.tscn").instantiate()
    viewport.add_child(scene)
    for i in range(30): await physics_frame
    freeze_scene(scene)
    # Keep the actual scene, materials and lights; inspect the native detail closer.
    scene.camera.global_position = scene.player.global_position + Vector3(0.0, 2.0, 4.5)
    scene.camera.look_at(scene.player.global_position + Vector3.UP * 1.0)
    scene.camera.fov = 35
    scene.dof.enabled = false
    scene.dof.apply()
    var counter := 0
    if record: DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
    for direction in range(4):
        var actor = scene.player
        actor.facing = direction
        actor.walking = true
        var clip: Dictionary = actor.animation.clips[direction]
        var seen: Array[int] = []
        for cycle in range(3):
            var start := 0.0
            for index in range(clip.ends.size()):
                var end: float = clip.ends[index]
                actor.animation_clock = cycle * float(clip.duration) + (start + end) * 0.5
                actor.update_animation()
                var image := await image_after_draw()
                if actor.animation_frame != index:
                    push_error("Playback timing mismatch")
                    quit(1)
                    return
                if cycle == 0: seen.append(index)
                if cycle == 0 and index == 0:
                    save_image(image, output.path_join(actor.animation.DIRECTIONS[direction] + "-close.png"))
                    report.get_or_add("clip_visibility", []).append(await visible_pixels(scene, image))
                if record:
                    save_image(image, output.path_join("frames/%05d.png" % counter))
                    counter += 1
                start = end
        report.clips.append({"direction": actor.animation.DIRECTIONS[direction], "frames": clip.textures.size(),
            "duration_ms": roundi(float(clip.duration) * 1000), "cycles_rendered": 3, "seen": seen})
    report["recorded_frames"] = counter
    report["main_window_minimized"] = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
    report["failures"] = failures
    report["passed"] = failures.is_empty() and report.preferences_ignored and report.hardware_gpu and report.renderer == "forward_plus" and report.main_window_minimized and report.clips.size() == 4 and report.scene_entries.size() == 4
    var file := FileAccess.open(output.path_join("render-report.json"), FileAccess.WRITE)
    file.store_string(JSON.stringify(report, "  ") + "\n")
    scene.queue_free()
    for i in range(4): await process_frame
    print("CHARACTER_RENDER_DONE ", adapter, " hardware=", report.hardware_gpu, " passed=",report.passed)
    quit(0 if report.passed else 1)
