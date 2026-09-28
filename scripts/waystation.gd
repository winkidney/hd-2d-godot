extends Node3D
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
var follow := false
var elapsed := 0.0
var showcase := false
var nearest: Dictionary = {}

func _ready() -> void:
    configure_input()
    layout = JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_layout.json"))
    camera = $Camera3D
    camera_home = to_vector(layout.camera.position)
    camera_target = to_vector(layout.camera.target)
    camera.position = camera_home
    camera.fov = float(layout.camera.fov)
    camera.look_at(camera_target)
    camera.current = true
    add_child(lighting)
    lighting.configure(camera, $World, layout)
    player.position = to_vector(layout.player_spawn)
    player.camera = camera
    add_child(player)
    var keeper := Actor.make_sprite("res://assets/sprites/keeper.png")
    keeper.name = "Waykeeper"
    keeper.position += to_vector(layout.interactions[0].position)
    add_child(keeper)
    add_child(hud)
    showcase = "--showcase" in OS.get_cmdline_user_args()
    if showcase:
        tour = true
        hud.container.hide()
    if "--self-test" in OS.get_cmdline_user_args():
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
    if hud.dialogue.visible:
        hud.close_dialogue()
    else:
        nearest = nearest_interaction()
        if not nearest.is_empty() and not tour:
            hud.show_dialogue(nearest)
    player.controls_enabled = not tour and not hud.dialogue.visible

func _process(delta: float) -> void:
    elapsed += delta
    if showcase and elapsed > 4.0 and lighting.preset_id == "dusk":
        lighting.apply_preset("night")
    nearest = nearest_interaction()
    player.controls_enabled = not tour and not hud.dialogue.visible
    hud.prompt.text = "E   " + str(nearest.title) if not nearest.is_empty() and not hud.dialogue.visible and not tour else ""
    hud.update_status(lighting.preset_id, tour, lighting.effects_enabled, follow)
    var offset := Vector3.ZERO
    if tour:
        offset = Vector3(sin(elapsed * 0.14) * 1.1, sin(elapsed * 0.11) * 0.3, 0)
    elif follow:
        offset = (player.position - to_vector(layout.player_spawn)).limit_length(8.0) * 0.24
        offset.y = 0.0
    camera.position = camera.position.lerp(camera_home + offset, 1.0 - exp(-delta * 3.0))
    camera.look_at(camera_target + offset * 0.65)

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    match event.keycode:
        KEY_E:
            interact()
        KEY_T:
            lighting.apply_preset("night" if lighting.preset_id == "dusk" else "dusk")
        KEY_1:
            lighting.apply_preset("dusk")
        KEY_2:
            lighting.apply_preset("night")
        KEY_F2:
            tour = not tour
            hud.close_dialogue()
        KEY_F3:
            lighting.set_effects(not lighting.effects_enabled)
        KEY_F4:
            follow = not follow
        KEY_TAB, KEY_H:
            hud.container.visible = not hud.container.visible
        KEY_F12:
            capture("user://captures/waystation-%s-%d.png" % [lighting.preset_id, Time.get_ticks_msec()])
        KEY_ESCAPE:
            if hud.dialogue.visible:
                interact()
            else:
                get_tree().quit()

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
