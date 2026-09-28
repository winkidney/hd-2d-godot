extends "res://scripts/waystation.gd"
@export var gray_mode := false
var recovery_count := 0

func _ready() -> void:
    background.free()
    lighting.free()
    background=preload("res://scripts/reference_scene/background.gd").new()
    lighting=preload("res://scripts/reference_scene/lighting.gd").new()
    layout_path="res://resources/reference-scene/layout.json"
    preferences_path="user://settings/lantern-canal-parallax.cfg"
    super._ready()
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
    if "--p9-test" in OS.get_cmdline_user_args(): call_deferred("run_p9_validation")
    print("P9_SCENE_READY gray=",gray_mode)

func should_load_preferences() -> bool:
    for flag in ["--p9-test","--p9-recording","--p9-preview"]:
        if flag in OS.get_cmdline_user_args(): return false
    return super.should_load_preferences()

func _process(delta: float) -> void:
    super._process(delta)
    if player.position.y < -3.5:
        recovery_count += 1
        player.position=to_vector(layout.player_spawn)
        player.velocity=Vector3.ZERO

func run_p9_validation() -> void:
    var runner=load("res://tests/p9/validation.gd").new()
    add_child(runner)
    await runner.run(self)
