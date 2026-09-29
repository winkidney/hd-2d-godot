extends Node3D
@export_file("*.json") var layout_path := "res://resources/world_layout.json"
@export var preferences_path := "user://settings/parallax.cfg"
const Actor = preload("res://scripts/pixel_actor.gd")
const Lighting = preload("res://scripts/lighting_controller.gd")
const Hud = preload("res://scripts/hud.gd")
var player := Actor.new()
var lighting := Lighting.new()
var hud := Hud.new()
var layout: Dictionary
var camera: Camera3D
var camera_home := Vector3.ZERO
var camera_target := Vector3.ZERO
var tour := false
var follow := true
var elapsed := 0.0
var showcase := false
var nearest: Dictionary = {}
var rig := preload("res://scripts/camera_rig.gd").new()
var dof := preload("res://scripts/dof_controller.gd").new()
var background := preload("res://scripts/background_rig.gd").new()
var dof_panel := preload("res://scripts/dof_panel.gd").new()
var record_walk := false
var clock_frozen := false
var parallax := preload("res://scripts/parallax_controller.gd").new()
var parallax_store := preload("res://scripts/parallax_settings_store.gd").new()
var parallax_panel := preload("res://scripts/parallax_panel.gd").new()
var parallax_preview := preload("res://scripts/parallax_preview.gd").new()
var settings_load_attempted := false

func _ready() -> void:
    configure_input()
    layout = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
    camera = $Camera3D
    camera_home = to_vector(layout.camera.position)
    camera_target = to_vector(layout.camera.target)
    camera.position = camera_home
    camera.fov = float(layout.camera.fov)
    camera.look_at(camera_target)
    camera.current = true
    add_child(lighting)
    lighting.configure(camera, $World, layout)
    rig.configure(camera, layout.camera, to_vector(layout.player_spawn))
    dof.configure(camera, camera_target)
    add_child(background)
    background.configure(lighting.environment)
    parallax.configure(camera,rig,background,FileAccess.get_file_as_string(layout_path))
    lighting.preset_changed.connect(background.apply_preset)
    lighting.effects_changed.connect(func(value): dof.master_enabled = value; dof.apply())
    player.position = to_vector(layout.player_spawn)
    player.camera = camera
    add_child(player)
    var keeper := Actor.make_sprite("res://assets/sprites/keeper.png")
    keeper.name = "Waykeeper"
    keeper.position += to_vector(layout.interactions[0].position)
    add_child(keeper)
    add_child(hud)
    hud.container.add_child(dof_panel)
    dof_panel.configure(dof)
    hud.container.add_child(parallax_panel)
    parallax_panel.configure(self)
    hud.configure_toolbar(self)
    get_tree().auto_accept_quit = false
    get_tree().root.close_requested.connect(request_quit)
    parallax_store.path = preferences_path
    if should_load_preferences():
        settings_load_attempted = true
        parallax_store.load_settings(parallax)
        parallax_panel.status.text = parallax_store.message
        parallax_panel.refresh()
    parallax.update(0.0,true)
    showcase = "--showcase" in OS.get_cmdline_user_args()
    if showcase:
        tour = true
        hud.container.hide()
    record_walk = "--walk-recording" in OS.get_cmdline_user_args()
    if record_walk:
        setup_walk_recording()
    if "--p8-recording" in OS.get_cmdline_user_args():
        add_child(preload("res://scripts/parallax_recording.gd").new())
    if "--p8-test" in OS.get_cmdline_user_args():
        call_deferred("run_parallax_validation")
    elif "--settings-probe" in OS.get_cmdline_user_args():
        call_deferred("run_settings_probe")
    elif "--p6p7-test" in OS.get_cmdline_user_args():
        call_deferred("run_feature_validation")
    elif "--self-test" in OS.get_cmdline_user_args():
        call_deferred("run_validation")
    print("WAYSTATION_READY renderer=", RenderingServer.get_current_rendering_method())

static func to_vector(value: Array) -> Vector3:
    return Vector3(float(value[0]), float(value[1]), float(value[2]))

func configure_input() -> void:
    var bindings := {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN]}
    for action in bindings:
        if not InputMap.has_action(action):
            InputMap.add_action(action)
        for key in bindings[action]:
            var event := InputEventKey.new()
            event.physical_keycode = key
            InputMap.action_add_event(action, event)

func nearest_interaction() -> Dictionary:
    var point: Dictionary = {}
    var best_distance := INF
    for entry in layout.interactions:
        var distance := player.position.distance_to(to_vector(entry.position))
        if distance <= float(entry.radius) and distance < best_distance:
            best_distance = distance
            point = entry
    return point

func interact() -> void:
    if panels_open(): return
    if hud.dialogue.visible:
        hud.close_dialogue()
    else:
        nearest = nearest_interaction()
        if not nearest.is_empty() and not tour:
            hud.show_dialogue(nearest)
    sync_input_lock()

func _process(delta: float) -> void:
    if not clock_frozen: elapsed += delta
    if showcase and elapsed > 4.0 and lighting.preset_id == "dusk":
        lighting.apply_preset("night")
    nearest = nearest_interaction()
    sync_input_lock()
    hud.prompt.text = "E   " + str(nearest.title) if not nearest.is_empty() and not hud.dialogue.visible and not tour else ""
    hud.update_status(lighting.preset_id, tour, lighting.effects_enabled, follow)
    rig.enabled = follow
    if parallax_preview.active: parallax_preview.update(delta)
    else: rig.update(delta, player.global_position, tour, elapsed)
    parallax.update(delta)
    background.advance(0.0 if clock_frozen else delta)
    dof.update(delta, player.global_position + Vector3.UP, tour)
    if record_walk:
        update_walk_recording()

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed:
        return
    if shortcut_route_running():
        if event.keycode == KEY_ESCAPE:
            cancel_shortcut_route()
            get_viewport().set_input_as_handled()
        return
    # GUI sees the event before this method. Never turn typing into scene actions.
    if text_edit_has_focus() and event.keycode != KEY_ESCAPE:
        return
    if popup_open() and event.keycode != KEY_ESCAPE:
        return
    var handled := true
    match event.keycode:
        KEY_E:
            interact()
        KEY_T:
            lighting.apply_preset({"day":"dusk", "dusk":"night", "night":"day"}[lighting.preset_id])
        KEY_1:
            lighting.apply_preset("dusk")
        KEY_2:
            lighting.apply_preset("night")
        KEY_3:
            lighting.apply_preset("day")
        KEY_G:
            close_tuning()
            tour = not tour
            hud.close_dialogue()
        KEY_V:
            lighting.set_effects(not lighting.effects_enabled)
        KEY_F:
            parallax_preview.stop()
            follow = not follow
        KEY_B:
            dof.enabled = not dof.enabled
            dof.apply()
        KEY_O:
            toggle_tuning("dof")
        KEY_P:
            toggle_tuning("parallax")
        KEY_K:
            background.visible = not background.visible
        KEY_C:
            if camera_tuning_panel() != null: toggle_camera_panel()
            else: handled = false
        KEY_H:
            close_tuning()
            hud.close_dialogue()
            hud.container.visible = not hud.container.visible
            sync_input_lock()
        KEY_J:
            capture("user://captures/waystation-%s-%d.png" % [lighting.preset_id, Time.get_ticks_msec()])
        KEY_ESCAPE:
            if close_visible_popup():
                pass
            elif parallax_preview.active:
                parallax_preview.stop()
            elif panels_open():
                close_tuning()
            elif hud.dialogue.visible:
                hud.close_dialogue()
                sync_input_lock()
            else:
                request_quit()
        _:
            handled = false
    if handled:
        sync_input_lock()
        get_viewport().set_input_as_handled()

func capture(path: String) -> bool:
    if DisplayServer.get_name() == "headless":
        push_error("Image capture requires a real rendering device.")
        return false
    var absolute := ProjectSettings.globalize_path(path)
    var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if error != OK:
        push_error("Cannot create capture directory: " + str(error))
        return false
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        push_error("Viewport returned no image.")
        return false
    error = image.save_png(absolute)
    if error != OK:
        push_error("Cannot save capture: " + str(error))
        return false
    print("CAPTURE_SAVED ", absolute)
    return true

func run_validation() -> void:
    var runner = load("res://tests/runtime_validation.gd").new()
    add_child(runner)
    await runner.run(self)

func run_feature_validation() -> void:
    var runner = load("res://tests/p6p7_validation.gd").new()
    add_child(runner)
    await runner.run(self)

func setup_walk_recording() -> void:
    tour = false
    follow = true
    hud.container.hide()
    player.scripted_input = true
    player.position = to_vector(layout.walkway.center) - to_vector(layout.walkway.direction) * 14.5 + Vector3(0,0.2,0)
    rig.set_offset(rig.desired_offset(player.position))
    dof.focus_depth = dof.depth(player.position + Vector3.UP)

func update_walk_recording() -> void:
    var direction := to_vector(layout.walkway.direction)
    var coordinate := (player.position-to_vector(layout.walkway.center)).dot(direction)
    var move := 0.0
    if elapsed > 1.0 and elapsed < 11.0 and coordinate < 14.5:
        move = 1.0
    elif elapsed >= 12.0 and coordinate > -14.5:
        move = -1.0
    player.scripted_direction = Vector2(direction.x,direction.z)*move
    var id := "day" if elapsed < 8 else ("dusk" if elapsed < 16 else "night")
    if lighting.preset_id != id:
        lighting.apply_preset(id)

func panels_open() -> bool:
    var camera_panel := camera_tuning_panel()
    return dof_panel.visible or parallax_panel.visible or (camera_panel != null and camera_panel.visible)

func sync_input_lock() -> void:
    player.controls_enabled = not tour and not hud.dialogue.visible and not panels_open() and not popup_open() and not text_edit_has_focus()
    hud.refresh_toolbar(shortcut_route_running())

func close_tuning() -> void:
    parallax_preview.stop()
    dof_panel.hide()
    parallax_panel.hide()
    var camera_panel := camera_tuning_panel()
    if camera_panel != null: camera_panel.hide()
    sync_input_lock()

func toggle_tuning(kind: String) -> void:
    if shortcut_route_running() or popup_open(): return
    var target: Control = dof_panel if kind == "dof" else parallax_panel
    var was_open := target.visible
    close_tuning()
    hud.close_dialogue()
    if not was_open:
        hud.container.show()
        target.refresh()
        target.show()
    sync_input_lock()

func camera_tuning_panel() -> Control:
    return null

func toggle_camera_panel() -> void:
    var panel := camera_tuning_panel()
    if panel == null or shortcut_route_running() or popup_open(): return
    var was_open := panel.visible
    close_tuning()
    hud.close_dialogue()
    if not was_open:
        hud.container.show()
        panel.refresh()
        panel.show()
    sync_input_lock()

func shortcut_route_running() -> bool:
    return false

func cancel_shortcut_route() -> void:
    pass

func text_edit_has_focus() -> bool:
    var focus := get_viewport().gui_get_focus_owner()
    return focus is LineEdit or focus is TextEdit

func visible_popups() -> Array[Window]:
    var result: Array[Window] = []
    # Include internal OptionButton menus, scoped to this scene, not the editor.
    collect_visible_popups(hud,result)
    return result

func collect_visible_popups(node: Node, result: Array[Window]) -> void:
    for child in node.get_children(true):
        if child is Window and child.visible:
            result.append(child)
        collect_visible_popups(child,result)

func popup_open() -> bool:
    return not visible_popups().is_empty()

func close_visible_popup() -> bool:
    var popups := visible_popups()
    if popups.is_empty(): return false
    popups.back().hide()
    sync_input_lock()
    return true

func request_quit() -> void:
    if shortcut_route_running() or hud.quit_dialog.visible: return
    parallax_preview.stop()
    hud.quit_dialog.popup_centered(Vector2i(580,180))
    hud.quit_dialog.get_cancel_button().grab_focus()
    sync_input_lock()

func should_load_preferences() -> bool:
    var flags := ["--ignore-user-settings","--self-test","--p6p7-test","--p8-test","--walk-recording","--showcase","--p8-recording"]
    for flag in flags:
        if flag in OS.get_cmdline_user_args(): return false
    return true

func run_parallax_validation() -> void:
    var runner = load("res://tests/parallax_validation.gd").new()
    add_child(runner)
    await runner.run(self)

func run_settings_probe() -> void:
    var folder := "user://p8-probe"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--capture-dir="): folder = arg.trim_prefix("--capture-dir=")
    var success := true
    if "--probe-save" in OS.get_cmdline_user_args():
        parallax.change("mode","artistic")
        parallax.change("global_strength",1.25)
        parallax.change("ridge_far",0.5)
        success = parallax_store.save_settings(parallax)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
    var file := FileAccess.open(folder.path_join("probe-report.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify({"passed":success,"load_attempted":settings_load_attempted,"snapshot":parallax.snapshot(),"message":parallax_store.message}))
    file.close()
    get_tree().quit(0 if success else 1)
