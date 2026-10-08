extends SceneTree
## Actual runtime state; the GPU pass, silhouette and motion are separate captures.
var scene: Node3D
var checks: Array = []
var destination := "res://build/ancient-canal/horizontal-night-20261008/validation/horizontal-sky.json"
func _initialize() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--report="): destination=arg.trim_prefix("--report=")
    call_deferred("run")
func check(value: bool, label: String) -> void:
    checks.append({"id":label,"passed":value})
    if not value: print("HORIZONTAL_SKY_FAIL ",label)
func run() -> void:
    scene=load("res://scenes/ancient_canal.tscn").instantiate()
    root.add_child(scene)
    scene.frozen=true
    scene.player.set_physics_process(false)
    for i in 3: await process_frame
    check(scene.layout.river.axis=="x" and scene.layout.bridge.center_x==1.2,"horizontal_river_and_bridge")
    check(scene.npc_materials.size()==5,"five_stationary_npcs")
    var near_cards: Array=[]
    var far_cards: Array=[]
    for node in scene.world.get_children():
        if node is Sprite3D and node.texture.resource_path.ends_with("scenery/willow.png"): near_cards.append(node)
    for node in scene.farfield.layers.near_town.get_children():
        if node is Sprite3D and node.texture.resource_path.ends_with("scenery/willow.png"): far_cards.append(node)
    for node in scene.farfield.layers.far_town.get_children():
        if node is Sprite3D and node.texture.resource_path.ends_with("scenery/willow.png"): far_cards.append(node)
    check(near_cards.size()==5 and far_cards.size()==10,"five_bank_and_ten_background_flat_willows")
    check(near_cards.filter(func(x): return x.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON).size()==2,"only_two_front_bank_trees_cast_shadows")
    check(far_cards.all(func(x): return x.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),"background_tree_shadows_disabled")
    check((near_cards+far_cards).all(func(x): return x.billboard==BaseMaterial3D.BILLBOARD_FIXED_Y and x.alpha_cut==SpriteBase3D.ALPHA_CUT_DISCARD and x.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS),"upright_cutout_and_mipmap_sampling")
    scene.apply_time_preset("night")
    var sky=scene.night_sky
    var material=sky.stars
    var texture=material.get_shader_parameter("panorama")
    var top=material.get_shader_parameter("sky_top_color")
    var horizon=material.get_shader_parameter("sky_horizon_color")
    check(sky.active and sky.sky_resource.sky_material==material and sky.focus_effect.enabled,"night_enables_cached_panorama_and_sky_focus_protection")
    var anchor: float=sky.anchor_x
    for x in [-100.0,-20.0,0.0,20.0,100.0,0.0]:
        scene.camera.position.x=anchor+x
        sky.update(scene.camera)
        check(is_equal_approx(scene.environment.sky_rotation.y,deg_to_rad(clampf(-x*.005,-.15,.15))),"absolute_parallax_"+str(x))
        check(sky.sky_resource.sky_material==material and material.get_shader_parameter("panorama")==texture and material.get_shader_parameter("sky_top_color")==top and material.get_shader_parameter("sky_horizon_color")==horizon,"motion_keeps_sky_material_uniforms_"+str(x))
    var rotation: Vector3=scene.environment.sky_rotation
    var updates: int=sky.updates
    for i in 120: sky.update(scene.camera)
    check(scene.environment.sky_rotation==rotation and sky.updates==updates,"stationary_sky_does_not_drift")
    scene.set_parameter("main_energy",.7)
    check(scene.values.time_preset=="custom" and sky.active,"custom_night_keeps_stars")
    for lens in ["F","W"]:
        scene.select_variant(lens)
        check(sky.active,"lens_"+lens+"_keeps_night")
    scene.toggle_comparison()
    scene.apply_time_preset("day")
    scene.toggle_comparison()
    check(sky.active,"comparison_restores_actual_night_sky")
    scene.select_lamp("streetlamp_left_back")
    scene.isolate_selected_lamp()
    check(sky.active,"single_lamp_isolation_keeps_night")
    scene.restore_lamp_isolation()
    check(sky.active,"single_lamp_restore_keeps_night")
    for period in ["day","dusk"]:
        scene.apply_time_preset(period)
        check(not sky.active and sky.sky_resource.sky_material==sky.daylight and not sky.focus_effect.enabled and scene.environment.sky_rotation==Vector3.ZERO,"original_"+period+"_sky")
    var passed: bool=checks.all(func(x): return x.passed)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
    var file=FileAccess.open(destination,FileAccess.WRITE)
    file.store_string(JSON.stringify({"passed":passed,"checks":checks,"scope":"Actual headless runtime state and compatibility. GPU rendering/performance are validated separately."},"  ")+"\n")
    print("HORIZONTAL_SKY_DONE passed=",passed," checks=",checks.size())
    scene.queue_free()
    await process_frame
    quit(0 if passed else 1)
