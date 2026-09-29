extends "res://scripts/waystation.gd"
@export var gray_mode := false
var recovery_count := 0
var experiment_id := "A"
var experiment_notice := ""
var experiment_panel := preload("res://scripts/reference_scene/experiment_panel.gd").new()
var impostor := preload("res://scripts/reference_scene/impostor.gd").new()
var experiment_loaded_settings: Dictionary = {}
var experiment_route_running := false
var experiment_route_cancelled := false

func _ready() -> void:
    background.free()
    lighting.free()
    background=preload("res://scripts/reference_scene/background.gd").new()
    lighting=preload("res://scripts/reference_scene/lighting.gd").new()
    rig=preload("res://scripts/reference_scene/experiment_camera.gd").new()
    parallax=preload("res://scripts/reference_scene/experiment_parallax.gd").new()
    parallax_preview=preload("res://scripts/reference_scene/experiment_preview.gd").new()
    layout_path="res://resources/reference-scene/layout.json"
    preferences_path="user://settings/lantern-canal-A-parallax.cfg"
    super._ready()
    experiment_loaded_settings["A"] = true
    add_child(impostor)
    impostor.configure(camera, $World)
    lighting.preset_changed.connect(impostor.apply_preset)
    hud.container.add_child(experiment_panel)
    experiment_panel.configure(self)
    player.sprite.texture=load("res://assets/reference-scene/sprites/hero.png")
    player.sprite.pixel_size=.035
    player.sprite.offset=Vector2(0,30)
    if has_node("Waykeeper"): get_node("Waykeeper").queue_free()
    for entry in layout.npcs:
        var npc := Actor.make_sprite("res://assets/reference-scene/sprites/"+entry.sprite+".png")
        npc.pixel_size=.035; npc.offset=Vector2(0,30)
        npc.position=to_vector(entry.position)+Vector3.UP*.04
        npc.name="Citizen_"+str(get_child_count())
        add_child(npc)
    for label in hud.container.find_children("*","Label",true,false):
        if label.text.begins_with("R I V E R"): label.text="L A N T E R N   C A N A L"
        elif label.text.begins_with("HD-2D SCENE"): label.text="REFERENCE STUDY  /  IMAGEGEN-DERIVED ASSETS  /  P9"
    lighting.apply_preset("dusk")
    if gray_mode: background.hide()
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--p9-experiment="):
            select_experiment(arg.trim_prefix("--p9-experiment=").to_upper())
    if "--p9-experiment-test" in OS.get_cmdline_user_args(): call_deferred("run_experiment_validation")
    if "--p9-test" in OS.get_cmdline_user_args(): call_deferred("run_p9_validation")
    print("P9_SCENE_READY gray=",gray_mode)

func should_load_preferences() -> bool:
    for flag in ["--p9-test","--p9-recording","--p9-preview", "--p9-experiment-test", "--p9-experiment-record", "--p9-impostors"]:
        if flag in OS.get_cmdline_user_args(): return false
    return super.should_load_preferences()

func _process(delta: float) -> void:
    super._process(delta)
    impostor.update_view(delta)
    if player.position.y < -3.5:
        recovery_count += 1
        player.position=to_vector(layout.player_spawn)
        player.velocity=Vector3.ZERO

func select_experiment(id: String) -> bool:
    if id not in ["A", "B", "C", "D"]:
        experiment_notice = "Unknown experiment: " + id
        return false
    if experiment_route_running:
        experiment_notice = "Finish the walking route before switching experiments."
        return false
    if id == "D" and not impostor.available:
        experiment_notice = impostor.unavailable_reason
        return false
    parallax_preview.stop()
    parallax.select_variant(id)
    experiment_id = id
    preferences_path = "user://settings/lantern-canal-" + id + "-parallax.cfg"
    parallax_store.path = preferences_path
    if not experiment_loaded_settings.has(id):
        experiment_loaded_settings[id] = true
        if should_load_preferences():
            parallax_store.load_settings(parallax)
            parallax_panel.status.text = parallax_store.message
    rig.select_variant(id, player.global_position)
    parallax.update(0.0, true)
    impostor.set_active(id == "D")
    parallax_panel.refresh()
    experiment_panel.refresh()
    experiment_notice = ""
    return true

func reset_experiment() -> void:
    if experiment_route_running: return
    parallax_preview.stop()
    parallax.reset_all()
    rig.select_variant(experiment_id, player.global_position)
    parallax.update(0.0, true)
    impostor.update_view(0.0, true)
    parallax_panel.refresh()
    experiment_panel.refresh()

func camera_tuning_panel() -> Control:
    return experiment_panel

func toggle_experiments() -> void:
    toggle_camera_panel()

func shortcut_route_running() -> bool:
    return experiment_route_running

func cancel_shortcut_route() -> void:
    experiment_route_cancelled = true

func run_experiment_route() -> Dictionary:
    if experiment_route_running: return {"passed":false, "reason":"Already running."}
    var path := "res://tests/p9/experiment_route.gd"
    if not ResourceLoader.exists(path):
        return {"passed":false, "reason":"The shared route runner is not installed."}
    var restore_panel := experiment_panel.visible
    close_tuning()
    experiment_route_cancelled = false
    experiment_route_running = true
    var runner = load(path)
    var result: Dictionary = await runner.run(self, "", false)
    experiment_route_running = false
    if restore_panel:
        experiment_panel.show()
        experiment_panel.refresh()
    sync_input_lock()
    return result

func run_experiment_validation() -> void:
    var runner = load("res://tests/p9/experiment_validation.gd").new()
    add_child(runner)
    await runner.run(self)

func run_p9_validation() -> void:
    var runner=load("res://tests/p9/validation.gd").new()
    add_child(runner)
    await runner.run(self)
