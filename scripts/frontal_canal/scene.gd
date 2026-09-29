extends "res://scripts/waystation.gd"
## Independent low-angle reconstruction. Old P9 entrypoints remain unchanged.
var variant_id := "F"
var notice := ""
var recovery_count := 0
var route_running := false
var route_cancelled := false
var loaded_settings: Dictionary = {}
var loaded_lenses: Dictionary = {}
var lens_store := preload("res://scripts/frontal_canal/lens_settings.gd").new()
var variant_panel := preload("res://scripts/frontal_canal/panel.gd").new()

func _ready() -> void:
    background.free()
    lighting.free()
    background = preload("res://scripts/frontal_canal/background.gd").new()
    lighting = preload("res://scripts/frontal_canal/lighting.gd").new()
    rig = preload("res://scripts/frontal_canal/camera.gd").new()
    parallax = preload("res://scripts/frontal_canal/parallax.gd").new()
    parallax_preview = preload("res://scripts/frontal_canal/preview.gd").new()
    layout_path = "res://resources/frontal-canal/layout.json"
    preferences_path = "user://settings/frontal-canal-F.cfg"
    super._ready()
    loaded_settings["F"] = true
    loaded_lenses["F"] = true
    if should_load_preferences(): lens_store.load_settings(rig,parallax.layout_id)
    parallax.update(0.0,true)
    hud.container.add_child(variant_panel)
    variant_panel.configure(self)
    if should_load_preferences(): variant_panel.status.text = lens_store.message
    player.sprite.texture = load("res://assets/reference-scene/sprites/hero.png")
    player.sprite.pixel_size = .035
    player.sprite.offset = Vector2(0,30)
    if has_node("Waykeeper"): get_node("Waykeeper").queue_free()
    for entry in layout.npcs:
        var npc := Actor.make_sprite("res://assets/reference-scene/sprites/"+entry.sprite+".png")
        npc.pixel_size = .035
        npc.offset = Vector2(0,30)
        npc.position = to_vector(entry.position)+Vector3.UP*.04
        add_child(npc)
    for label in hud.container.find_children("*","Label",true,false):
        if label.text.begins_with("R I V E R"): label.text = "C A N A L   F R O N T"
        elif label.text.begins_with("HD-2D SCENE"): label.text = "P9R2  /  FRONTAL PERSPECTIVE  /  F9 COMPARE F · W · O"
    lighting.apply_preset("dusk")
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--frontal-variant="): select_variant(arg.get_slice("=",1))
    if "--frontal-test" in OS.get_cmdline_user_args(): call_deferred("validate_frontal")
    print("FRONTAL_READY ", variant_id)

func should_load_preferences() -> bool:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--frontal-"): return false
    return super.should_load_preferences()

func _process(delta: float) -> void:
    super._process(delta)
    if player.position.y < -3.5:
        recovery_count += 1
        player.position = to_vector(layout.player_spawn)
        player.velocity = Vector3.ZERO

func select_variant(id: String) -> bool:
    if id not in ["F","W","O"] or route_running: return false
    parallax_preview.stop()
    parallax.select_variant(id)
    variant_id = id
    preferences_path = "user://settings/frontal-canal-"+id+".cfg"
    parallax_store.path = preferences_path
    if not loaded_settings.has(id):
        loaded_settings[id] = true
        if should_load_preferences(): parallax_store.load_settings(parallax)
    rig.select_variant(id, player.global_position)
    notice = "Camera changed. Actor, time and focus preserved."
    if not loaded_lenses.has(id):
        loaded_lenses[id] = true
        if should_load_preferences():
            lens_store.load_settings(rig,parallax.layout_id)
            notice += " " + lens_store.message
    parallax.update(0.0,true)
    parallax_panel.refresh()
    variant_panel.refresh()
    return true

func reset_variant() -> void:
    if route_running: return
    parallax_preview.stop()
    parallax.reset_all()
    rig.reset_lens()
    rig.select_variant(variant_id,player.global_position)
    parallax.update(0.0,true)
    parallax_panel.refresh()
    variant_panel.refresh()

func set_lens(key: String, value: float) -> bool:
    if route_running or not rig.lens_error(key,value).is_empty(): return false
    parallax_preview.stop()
    rig.set_lens(key,value)
    parallax.update(0.0,true)
    variant_panel.status.text = "Lens updated. Save to keep this camera's settings."
    variant_panel.refresh()
    return true

func reset_lens() -> void:
    if route_running: return
    parallax_preview.stop()
    rig.reset_lens()
    parallax.update(0.0,true)
    variant_panel.refresh()

func save_lens_settings() -> bool:
    if route_running: return false
    return lens_store.save_settings(rig,parallax.layout_id)

func load_lens_settings() -> bool:
    if route_running: return false
    parallax_preview.stop()
    var ok: bool = lens_store.load_settings(rig,parallax.layout_id)
    parallax.update(0.0,true)
    variant_panel.refresh()
    return ok

func _unhandled_input(event: InputEvent) -> void:
    # GUI gets first refusal; scrolling a slider/menu never zooms the world.
    if not event is InputEventMouseButton or not event.pressed: return
    if event.button_index not in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: return
    if route_running or panels_open() or hud.dialogue.visible or tour or player.scripted_input or parallax_preview.active: return
    var direction := -1.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0
    var amount := absf(event.factor) if is_finite(event.factor) and event.factor!=0.0 else 1.0
    var limits: Vector2 = rig.LENS_LIMITS.radius
    # Wheel input is discrete, matching the UI's half-metre increments.
    var steps := maxf(1.0,roundf(amount))
    var radius := clampf(snappedf(float(rig.lens_snapshot().radius)+direction*0.5*steps,0.5),limits.x,limits.y)
    set_lens("radius",radius)
    get_viewport().set_input_as_handled()

func panels_open() -> bool:
    return super.panels_open() or variant_panel.visible

func close_tuning() -> void:
    variant_panel.hide()
    super.close_tuning()

func _input(event: InputEvent) -> void:
    if event is InputEventKey and route_running:
        if event.pressed and not event.echo and event.keycode == KEY_ESCAPE: route_cancelled = true
        get_viewport().set_input_as_handled()
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
        var was_open := variant_panel.visible
        close_tuning()
        hud.close_dialogue()
        if not was_open:
            hud.container.show()
            variant_panel.refresh()
            variant_panel.show()
        sync_input_lock()
        get_viewport().set_input_as_handled()
        return
    super._input(event)

func run_route() -> Dictionary:
    if route_running: return {"passed":false,"reason":"Route already running"}
    var restore_panel := variant_panel.visible
    close_tuning()
    route_running = true
    route_cancelled = false
    var result: Dictionary = await load("res://tests/p9frontal/route.gd").run(self,"",false)
    route_running = false
    if restore_panel:
        variant_panel.refresh()
        variant_panel.show()
    notice = "Route passed" if result.passed else "Route stopped or failed"
    sync_input_lock()
    return result

func validate_frontal() -> void:
    var runner = load("res://tests/p9frontal/validation.gd").new()
    add_child(runner)
    await runner.run(self)
