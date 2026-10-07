extends Node3D
## Independent Jiangnan entry. Existing scenes, art and their evidence remain intact.
const World = preload("res://scripts/ancient_canal/world.gd")
const Actor = preload("res://scripts/ancient_canal/actor.gd")
const Settings = preload("res://scripts/ancient_canal/settings.gd")
const Console = preload("res://scripts/ancient_canal/console.gd")
const CanalRig = preload("res://scripts/ancient_canal/camera.gd")
const Background = preload("res://scripts/ancient_canal/background.gd")
const Parallax = preload("res://build/ancient-canal/profile-20261008/gpu-stages-corrected/parallax.gd")
const FONT_PATH := "res://assets/ancient-canal/fonts/NotoSansSC.ttf"
var parameter_spec: Dictionary
var values: Dictionary
var settings: RefCounted
var layout: Dictionary
var world: Node3D
var player: CharacterBody3D
var camera: Camera3D
var environment: Environment
var attributes := CameraAttributesPractical.new()
var main_light: DirectionalLight3D
var test_light: OmniLight3D
var lanterns: Array[OmniLight3D] = []
var broad_lights: Array[OmniLight3D] = []
var npc_materials: Array[ShaderMaterial] = []
var water_material: ShaderMaterial
var console: PanelContainer
var overlay: CanvasLayer
var dialogue: PanelContainer
var dialogue_text: Label
var prompt: Label
var hud_status: Label
var exit_confirmation: ConfirmationDialog
var status_text := ""
var route_running := false
var route_cancelled := false
var route_points: Array = []
var route_index := 0
var route_frames := 0
var route_trajectory: Array = []
var route_result: Dictionary = {}
var comparison_snapshot: Dictionary = {}
var elapsed := 0.0
var frozen := false
var camera_offset := Vector3.ZERO
var camera_locked := false
var settings_load_attempted := false
var geometry_ready := false
var water_clock := 0.0
var capture_counter := 0
var farfield: Node3D
var rig: RefCounted
var parallax: RefCounted
var streetlamps: Array[OmniLight3D] = []
var lamp_nodes: Dictionary = {}
var lamp_metadata: Dictionary = {}
var lamp_overrides: Dictionary = {}
var selected_lamp_id := "streetlamp_left_front"
var isolated_lamp_id := ""
var lamp_isolation_snapshot: Dictionary = {}
var comparison_rig_pose: Dictionary = {}
var comparison_candidate: Dictionary = {}
var comparison_background_preset := "dusk"
var comparison_player_facing := 0

static func vec(a: Array) -> Vector3:
    return Vector3(a[0],a[1],a[2])

func _ready() -> void:
    parameter_spec = JSON.parse_string(FileAccess.get_file_as_string("res://resources/ancient-canal/parameters.json"))
    settings = Settings.new(parameter_spec)
    values = settings.default_values()
    layout = JSON.parse_string(FileAccess.get_file_as_string("res://resources/ancient-canal/layout.json"))
    configure_input()
    world = World.new()
    world.name = "JiangnanWorld"
    add_child(world)
    world.configure(layout,"--canal-greybox" in OS.get_cmdline_user_args())
    create_farfield()
    camera = Camera3D.new()
    camera.current = true
    camera.near = .08
    camera.far = 240
    camera.attributes = attributes
    add_child(camera)
    rig = CanalRig.new()
    var camera_config: Dictionary = layout.camera.duplicate(true)
    camera_config.follow_bounds = layout.banks
    rig.configure(camera,camera_config,vec(layout.player_spawn))
    parallax = Parallax.new()
    parallax.configure(camera,rig,farfield)
    settings.configure_controllers(rig,parallax)
    settings.configure_background(farfield)
    create_lighting()
    settings.configure_lights(light_catalog())
    player = Actor.new()
    player.position = vec(layout.player_spawn)
    player.camera = camera
    add_child(player)
    create_npcs()
    water_material = ShaderMaterial.new()
    water_material.shader = preload("res://shaders/ancient_canal/water.gdshader")
    world.water.material_override = water_material
    create_hud()
    get_tree().auto_accept_quit = false
    get_tree().root.close_requested.connect(request_quit)
    apply_time_preset("dusk")
    if "--ignore-user-settings" not in OS.get_cmdline_user_args() and "--canal-test" not in OS.get_cmdline_user_args():
        settings_load_attempted = true
        load_settings()
    camera_update(0,true)
    geometry_ready = ResourceLoader.exists("res://assets/ancient-canal/models/tavern.glb")
    print("ANCIENT_CANAL_READY normals=",not player.normal_definition.is_empty()," models=",geometry_ready)
    if "--canal-standalone-test" in OS.get_cmdline_user_args():
        call_deferred("run_standalone_probe")

func run_standalone_probe() -> void:
    await preload("res://scripts/ancient_canal/standalone_probe.gd").run(self)

func configure_input() -> void:
    for pair in [["move_left",KEY_A,KEY_LEFT],["move_right",KEY_D,KEY_RIGHT],["move_up",KEY_W,KEY_UP],["move_down",KEY_S,KEY_DOWN]]:
        if not InputMap.has_action(pair[0]): InputMap.add_action(pair[0])
        for key in [pair[1],pair[2]]:
            var event := InputEventKey.new()
            event.physical_keycode = key
            if not InputMap.action_has_event(pair[0],event): InputMap.action_add_event(pair[0],event)

func create_lighting() -> void:
    environment = Environment.new()
    environment.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color(.12,.19,.34)
    sky_material.sky_horizon_color = Color(.73,.45,.35)
    sky_material.ground_bottom_color = Color(.12,.17,.2)
    sky_material.ground_horizon_color = Color(.5,.36,.3)
    sky.sky_material = sky_material
    environment.sky = sky
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.ssao_radius = 1.1
    environment.ssao_intensity = 1.0
    environment.glow_enabled = true
    environment.fog_light_color = Color(.43,.44,.52)
    environment.fog_sky_affect = .15
    var env_node := WorldEnvironment.new()
    env_node.environment = environment
    add_child(env_node)
    main_light = DirectionalLight3D.new()
    main_light.directional_shadow_max_distance = 70
    main_light.shadow_bias = .03
    add_child(main_light)
    test_light = OmniLight3D.new()
    test_light.name = "NormalSweepLight"
    test_light.shadow_bias = .035
    add_child(test_light)
    for index in world.lantern_positions.size():
        var point: Vector3 = world.lantern_light_positions[index]
        var lantern := OmniLight3D.new()
        var id := "lantern_"+str(index)
        lantern.name = id
        lantern.position = point
        lantern.shadow_bias = .04
        lantern.omni_attenuation = 1.0
        add_child(lantern)
        lanterns.append(lantern)
        lamp_nodes[id] = lantern
        lamp_metadata[id] = {"id":id,"label":world.lantern_labels[index],"group":"lantern","cast_shadow":true}
    for entry in world.streetlamp_definitions:
        var lamp := OmniLight3D.new()
        lamp.name = entry.id
        lamp.position = vec(entry.light_position)
        lamp.shadow_bias = .04
        lamp.omni_attenuation = 1.0
        add_child(lamp)
        streetlamps.append(lamp)
        lamp_nodes[entry.id] = lamp
        lamp_metadata[entry.id] = {"id":entry.id,"label":entry.label,"group":"streetlamp","cast_shadow":entry.cast_shadow}
    for entry in layout.get("broad_lights", []):
        var lamp := OmniLight3D.new()
        lamp.name = entry.id
        lamp.position = vec(entry.position)
        lamp.shadow_bias = .04
        lamp.omni_attenuation = .75
        add_child(lamp)
        broad_lights.append(lamp)
        lamp_nodes[entry.id] = lamp
        var tint := Color(float(entry.tint[0]),float(entry.tint[1]),float(entry.tint[2]),float(entry.tint[3]))
        lamp_metadata[entry.id] = {"id":entry.id,"label":entry.label,"group":"broad","cast_shadow":entry.cast_shadow,"tint":tint}

func light_catalog() -> Array:
    var result: Array = []
    for id in lamp_metadata: result.append(lamp_metadata[id].duplicate(true))
    return result

func lamp_state(id: String) -> Dictionary:
    if not lamp_nodes.has(id): return {}
    var lamp: OmniLight3D = lamp_nodes[id]
    return {"enabled":lamp.visible,"color":lamp.light_color,"energy":lamp.light_energy,"range":lamp.omni_range,"shadow":lamp.shadow_enabled}

func selected_lamp_values() -> Dictionary:
    return lamp_state(selected_lamp_id)

func apply_lamp_properties() -> void:
    for id in lamp_nodes:
        var lamp: OmniLight3D = lamp_nodes[id]
        var entry: Dictionary = lamp_metadata[id]
        var prefix: String = entry.group
        var override: Dictionary = lamp_overrides.get(id,{})
        var enabled: bool = override.get("enabled",values.get(prefix+"_enabled",true))
        lamp.visible = enabled and (isolated_lamp_id.is_empty() or id==isolated_lamp_id)
        lamp.light_color = override.get("color",values[prefix+"_color"]*entry.get("tint",Color.WHITE))
        lamp.light_energy = override.get("energy",values[prefix+"_energy"])
        lamp.omni_range = override.get("range",values[prefix+"_range"])
        lamp.shadow_enabled = bool(values.scene_shadow) and bool(override.get("shadow",bool(values[prefix+"_shadow"]) and bool(entry.cast_shadow)))

func clear_lamp_override_property(group: String,key: String) -> void:
    for id in lamp_overrides.keys():
        if group.is_empty() or lamp_metadata[id].group==group:
            lamp_overrides[id].erase(key)
            if lamp_overrides[id].is_empty(): lamp_overrides.erase(id)

func select_lamp(id: String) -> bool:
    if not lamp_nodes.has(id): return false
    selected_lamp_id = id
    if not isolated_lamp_id.is_empty(): isolated_lamp_id = id; apply_lamp_properties()
    return true

func set_selected_lamp(key: String,value: Variant) -> bool:
    var candidate: Dictionary = lamp_overrides.duplicate(true)
    var override: Dictionary = candidate.get(selected_lamp_id,{}).duplicate(true)
    var error: String = settings.lamp_field_error(key,value)
    if not error.is_empty(): status_text = error; return false
    override[key] = settings.normalize_lamp(key,value)
    candidate[selected_lamp_id] = override
    lamp_overrides = candidate
    values.time_preset = "custom"
    apply_lamp_properties()
    status_text = "当前灯的实际参数已更新。"
    return true

func isolate_selected_lamp() -> void:
    if not comparison_snapshot.is_empty(): status_text = "请先结束法线比较。"; return
    if not lamp_isolation_snapshot.is_empty(): return
    cancel_route()
    lamp_isolation_snapshot = {"values":values.duplicate(true),"overrides":lamp_overrides.duplicate(true),"pose":rig.pose_snapshot(),"parallax":parallax.snapshot(),"candidate":settings.candidate_from_values(values,lamp_overrides),"background_preset":farfield.profile_id,"facing":player.facing,"camera_locked":camera_locked}
    isolated_lamp_id = selected_lamp_id
    values.fixed_animation = true
    values.animation_frame = player.animation_frame
    values.fixed_light = true
    values.main_energy = 0.0
    values.ambient = .12
    values.test_light_enabled = false
    values.time_preset = "custom"
    camera_locked = true
    apply_parameters()
    sync_input()
    status_text = "单灯隔离中：固定人物、镜头和灯位。"

func restore_lamp_isolation() -> void:
    if lamp_isolation_snapshot.is_empty(): return
    var saved: Dictionary = lamp_isolation_snapshot.duplicate(true)
    lamp_isolation_snapshot.clear()
    isolated_lamp_id = ""
    values = saved.values
    lamp_overrides = saved.overrides
    camera_locked = saved.camera_locked
    parallax.apply_snapshot(saved.parallax)
    farfield.apply_preset(saved.background_preset)
    apply_parameters()
    player.facing = saved.facing
    player.update_animation()
    rig.restore_pose(saved.pose)
    camera_offset = rig.follow_offset
    parallax.update(0,true)
    update_focus()
    sync_input()
    status_text = "单灯隔离结束，原照明与镜头已恢复。"

func create_farfield() -> void:
    farfield = Background.new()
    farfield.name = "LayeredJiangnanBackground"
    add_child(farfield)
    farfield.configure(world,layout)

func create_npcs() -> void:
    for entry in layout.npcs:
        var path: String = "res://assets/ancient-canal/npcs/"+entry.id+".png"
        if not ResourceLoader.exists(path): continue
        var npc: Sprite3D = preload("res://scripts/pixel_actor.gd").make_sprite(path)
        npc.name = entry.id
        npc.hframes = 1
        npc.vframes = 1
        npc.pixel_size = .009
        npc.offset = Vector2(0,112)
        npc.position = vec(entry.position)
        var material := ShaderMaterial.new()
        material.shader = preload("res://shaders/ancient_canal/sprite_native.gdshader")
        material.set_shader_parameter("color_atlas",load(path))
        material.set_shader_parameter("normal_atlas",load(path.replace(".png","-normal.png")))
        material.set_shader_parameter("silver_atlas",load(path.replace(".png","-mask.png")))
        npc.material_override = material
        add_child(npc)
        npc_materials.append(material)

func create_hud() -> void:
    overlay = CanvasLayer.new()
    add_child(overlay)
    var bar := VBoxContainer.new()
    bar.position = Vector2(24,22)
    bar.add_theme_constant_override("separation",10)
    overlay.add_child(bar)
    var theme_data := Theme.new()
    theme_data.default_font = load(FONT_PATH)
    theme_data.default_font_size = 20
    bar.theme = theme_data
    var title := Label.new()
    title.text = "江南河街 · 桥头酒肆"
    title.add_theme_font_size_override("font_size",29)
    bar.add_child(title)
    hud_status = Label.new()
    bar.add_child(hud_status)
    var buttons := HBoxContainer.new()
    bar.add_child(buttons)
    add_button(buttons,"光影控制台  M",func(): console.toggle(); sync_input())
    add_button(buttons,"时段  T",cycle_time)
    add_button(buttons,"自动路线  G",start_route)
    add_button(buttons,"截图  K",capture_screenshot)
    add_button(buttons,"退出",request_quit)
    var help := Label.new()
    help.text = "WASD / 方向键移动 · E 交谈 · Esc 取消 / 关闭"
    help.modulate = Color(.8,.83,.85)
    bar.add_child(help)
    prompt = Label.new()
    prompt.position = Vector2(30,1010)
    prompt.theme = theme_data
    overlay.add_child(prompt)
    dialogue = PanelContainer.new()
    dialogue.position = Vector2(400,850)
    dialogue.custom_minimum_size = Vector2(1050,135)
    dialogue.theme = theme_data
    overlay.add_child(dialogue)
    var dialogue_box := VBoxContainer.new()
    dialogue.add_child(dialogue_box)
    dialogue_text = Label.new()
    dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    dialogue_text.custom_minimum_size = Vector2(1000,75)
    dialogue_box.add_child(dialogue_text)
    add_button(dialogue_box,"继续  E / Esc",func(): dialogue.hide(); sync_input())
    dialogue.hide()
    console = Console.new()
    overlay.add_child(console)
    console.configure(self)
    console.closed.connect(sync_input)
    exit_confirmation = ConfirmationDialog.new()
    exit_confirmation.title = "退出江南河街"
    exit_confirmation.dialog_text = "确定退出演示吗？未保存的参数不会写入本机设置。"
    exit_confirmation.ok_button_text = "退出"
    exit_confirmation.cancel_button_text = "继续游览"
    exit_confirmation.theme = theme_data
    exit_confirmation.confirmed.connect(func(): get_tree().quit())
    exit_confirmation.canceled.connect(sync_input)
    exit_confirmation.visibility_changed.connect(sync_input)
    overlay.add_child(exit_confirmation)

func add_button(parent: Node,text: String,action: Callable) -> void:
    var button := Button.new()
    button.text = text
    button.pressed.connect(action)
    parent.add_child(button)

func sync_controller_values() -> void:
    if rig==null or parallax==null: return
    values.camera_variant = rig.variant_id
    values.camera_distance = rig.lens_snapshot().radius
    values.camera_fov = rig.lens_snapshot().fov
    values.camera_follow = rig.enabled
    var profile: Dictionary = parallax.snapshot()
    values.parallax_mode = profile.mode
    values.parallax_strength = profile.global_strength
    values.parallax_transition = profile.transition_time
    for id in parallax.IDS: values[id] = profile[id]

func select_variant(id: String) -> bool:
    if camera_locked: status_text = "请先结束固定机位比较或单灯隔离。"; return false
    if not rig.select_variant(id,player.position): return false
    sync_controller_values()
    parallax.update(0,true)
    update_focus()
    status_text = "已切换正面透视 "+id+"。"
    return true

func set_lens(key: String,value: Variant) -> bool:
    if camera_locked: status_text = "请先结束固定机位比较或单灯隔离。"; return false
    if not rig.set_lens(key,value): status_text = "镜距或视野超出有效范围。"; return false
    sync_controller_values()
    parallax.update(0,true)
    update_focus()
    status_text = "镜头参数已更新。"
    return true

func reset_lens() -> void:
    if camera_locked: status_text = "请先结束固定机位比较或单灯隔离。"; return
    rig.reset_lens()
    sync_controller_values()
    parallax.update(0,true)
    update_focus()

func reset_parallax() -> void:
    parallax.reset_all()
    sync_controller_values()

func set_parameter(key: String,value: Variant) -> bool:
    var error: String = settings.field_error(key,value)
    if not error.is_empty(): status_text = error; return false
    if not isolated_lamp_id.is_empty():
        if parameter_spec.parameters[key].page=="lighting":
            status_text = "单灯隔离中请使用所选灯参数；恢复全部灯光后可调场景照明。"
            return false
        if key in ["fixed_animation","animation_pause","fixed_light"] and not bool(value):
            status_text = "请先恢复全部灯光，再解除固定动画或灯位。"
            return false
    if key=="time_preset" and value!="custom": apply_time_preset(str(value)); return true
    if key=="camera_variant": return select_variant(str(value))
    if key=="camera_distance": return set_lens("radius",value)
    if key=="camera_fov": return set_lens("fov",value)
    if key=="camera_follow":
        if camera_locked: status_text = "请先结束固定机位比较或单灯隔离。"; return false
        rig.enabled = bool(value)
        values[key] = value
        camera_update(0,true)
        sync_controller_values()
        return true
    var profile_key: String = {"parallax_mode":"mode","parallax_strength":"global_strength","parallax_transition":"transition_time"}.get(key,key)
    if profile_key in parallax.DEFAULT_PROFILE:
        var profile: Dictionary = parallax.snapshot()
        profile[profile_key] = value
        if not parallax.apply_snapshot(profile): return false
        sync_controller_values()
        parallax.update(0,true)
        return true
    values[key] = settings.normalize(key,value)
    if parameter_spec.parameters[key].page=="lighting" and key!="time_preset":
        values.time_preset = "custom"
        for prefix in ["lantern","streetlamp","broad"]:
            if key.begins_with(prefix+"_"):
                var property: String = key.trim_prefix(prefix+"_")
                clear_lamp_override_property(prefix,property)
    if key=="animation_pause" or key=="fixed_animation":
        if bool(value): values.animation_frame = player.animation_frame
    apply_parameters()
    status_text = parameter_spec.parameters[key].label+"已更新。"
    return true

func apply_time_preset(id: String) -> void:
    if not isolated_lamp_id.is_empty():
        status_text = "请先恢复全部灯光，再切换时段。"
        return
    var presets := {
        "day":{"main_pitch":-55.0,"main_yaw":-28.0,"main_energy":1.35,"main_color":Color(1,.94,.82),"ambient":.5,"ambient_color":Color(.5,.64,.79),"lantern_energy":.15},
        "dusk":{"main_pitch":-32.0,"main_yaw":-38.0,"main_energy":1.1,"main_color":Color(1,.76,.54),"ambient":.38,"ambient_color":Color(.36,.48,.66),"lantern_energy":1.6},
        "night":{"main_pitch":-48.0,"main_yaw":34.0,"main_energy":.48,"main_color":Color(.46,.62,1),"ambient":.22,"ambient_color":Color(.2,.29,.52),"lantern_energy":2.5}}
    if not presets.has(id): return
    presets[id]["sky_top_color"] = Color(.17,.32,.5) if id=="day" else (Color(.12,.19,.34) if id=="dusk" else Color(.018,.035,.09))
    presets[id]["sky_horizon_color"] = Color(.63,.78,.83) if id=="day" else (Color(.73,.45,.35) if id=="dusk" else Color(.12,.17,.28))
    presets[id]["streetlamp_energy"] = {"day":.05,"dusk":.8,"night":1.4}[id]
    presets[id]["broad_energy"] = {"day":.1,"dusk":1.7,"night":2.6}[id]
    clear_lamp_override_property("","energy")
    values.merge(presets[id],true)
    values.time_preset = id
    if farfield!=null: farfield.apply_preset(id)
    apply_parameters()
    status_text = "已切换时段，镜头与景深保留。"

func cycle_time() -> void:
    var ids := ["day","dusk","night"]
    apply_time_preset(ids[posmod(ids.find(values.time_preset)+1,3)])
    console.refresh()

func apply_parameters() -> void:
    player.apply_material(values)
    player.paused = values.animation_pause or values.fixed_animation
    player.frame_override = values.animation_frame
    player.direction_override = -1 if values.direction=="auto" else player.animation.DIRECTIONS.find(values.direction)
    player.preview_walk = values.direction!="auto"
    player.update_animation()
    for mat in npc_materials:
        mat.shader = player.surface.shader
        for pair in [["use_normals","normals_enabled"],["normal_strength","normal_strength"],["flip_y","normal_flip_y"],["clay_mode","clay"],["normal_debug","normal_debug"],["silver_specular","silver_specular"],["shade_levels","light_steps"]]: mat.set_shader_parameter(pair[0],values[pair[1]])
    main_light.rotation_degrees = Vector3(values.main_pitch,values.main_yaw,0)
    main_light.light_energy = values.main_energy
    main_light.light_color = values.main_color
    main_light.shadow_enabled = values.scene_shadow and values.main_shadow
    environment.ambient_light_color = values.ambient_color
    environment.ambient_light_energy = values.ambient
    environment.sky.sky_material.sky_top_color = values.sky_top_color
    environment.sky.sky_material.sky_horizon_color = values.sky_horizon_color
    environment.sky.sky_material.ground_horizon_color = values.sky_horizon_color*.7
    environment.sky.sky_material.ground_bottom_color = values.sky_top_color*.5
    environment.fog_light_color = values.sky_horizon_color.lerp(values.ambient_color,.5)
    environment.fog_enabled = values.fog>0
    environment.fog_density = values.fog
    environment.glow_enabled = values.bloom>0
    environment.glow_intensity = values.bloom
    environment.ssao_enabled = values.ssao
    environment.ssr_enabled = values.water_reflection>0
    test_light.visible = values.test_light_enabled
    test_light.position = Vector3(values.test_light_x,values.test_light_y,values.test_light_z)
    test_light.light_energy = values.test_light_energy
    test_light.light_color = values.test_light_color
    test_light.omni_range = values.test_light_range
    test_light.shadow_enabled = values.scene_shadow and values.test_light_shadow
    apply_lamp_properties()
    for mat in world.material_overrides:
        mat.normal_scale = values.normal_strength if values.normals_enabled else 0.0
    water_material.set_shader_parameter("flow",values.water_flow)
    water_material.set_shader_parameter("wave_strength",values.water_wave)
    water_material.set_shader_parameter("reflection",values.water_reflection)
    update_focus()
    camera_update(0,true)

func camera_update(delta: float,immediate := false) -> void:
    if rig==null: return
    rig.enabled = values.camera_follow
    if not camera_locked:
        if immediate:
            rig.follow_offset = rig.desired_offset(player.position) if rig.enabled else Vector3.ZERO
            rig.yaw_degrees = rig.desired_yaw(player.position)
            rig.target_yaw_degrees = rig.yaw_degrees
            rig.set_offset(rig.follow_offset)
        else:
            rig.update(delta,player.position,false,elapsed)
    camera_offset = rig.follow_offset
    parallax.update(delta,immediate)
    sync_controller_values()

func update_focus() -> void:
    var depth: float = -(camera.global_transform.affine_inverse()*(player.position+Vector3.UP)).z
    var focus: float = depth if values.focus_protection else values.focus_distance
    attributes.dof_blur_amount = values.dof_amount
    attributes.dof_blur_near_enabled = values.dof_near
    attributes.dof_blur_far_enabled = values.dof_far
    attributes.dof_blur_near_distance = maxf(.1,focus-4.5)
    attributes.dof_blur_far_distance = maxf(1,focus+7.0)
    attributes.dof_blur_near_transition = 4
    attributes.dof_blur_far_transition = 12

func restore_defaults() -> void:
    cancel_route()
    comparison_snapshot.clear()
    comparison_rig_pose.clear()
    comparison_candidate.clear()
    lamp_isolation_snapshot.clear()
    isolated_lamp_id = ""
    lamp_overrides.clear()
    camera_locked = false
    values = settings.default_values()
    rig.enabled = true
    rig.restore_lens_profiles(rig.lens_profiles_defaults(),"F",player.position)
    parallax.reset_all()
    sync_controller_values()
    apply_time_preset("dusk")
    sync_input()
    status_text = "默认参数已恢复。"

func save_settings() -> bool:
    sync_controller_values()
    var ok: bool
    if not lamp_isolation_snapshot.is_empty():
        ok = settings.save_candidate(lamp_isolation_snapshot.candidate)
    elif not comparison_candidate.is_empty():
        ok = settings.save_candidate(comparison_candidate)
    else:
        ok = settings.save_settings(values,lamp_overrides)
    status_text = settings.message
    return ok

func load_settings() -> bool:
    var candidate: Dictionary = settings.load_settings()
    if candidate.is_empty(): status_text = settings.message; return false
    var loaded: Dictionary = settings.candidate_to_values(candidate)
    if loaded.is_empty(): status_text = settings.message; return false
    lamp_isolation_snapshot.clear()
    isolated_lamp_id = ""
    comparison_snapshot.clear()
    comparison_rig_pose.clear()
    comparison_candidate.clear()
    camera_locked = false
    values = loaded
    rig.enabled = candidate.camera.follow
    rig.restore_lens_profiles(candidate.lens_profiles,candidate.camera.variant,player.position)
    parallax.apply_snapshot(candidate.parallax)
    lamp_overrides = candidate.lamp_overrides.duplicate(true)
    sync_controller_values()
    apply_parameters()
    farfield.apply_preset(candidate.background_preset)
    status_text = settings.message
    sync_input()
    return true

func force_direction(id: String) -> void:
    set_parameter("direction",id)

func set_frame(index: int) -> void:
    if index<0 or index>=27: return
    values.animation_pause = true
    set_parameter("animation_frame",index)

func toggle_comparison() -> void:
    if not lamp_isolation_snapshot.is_empty(): status_text = "请先恢复单灯隔离。"; return
    if comparison_snapshot.is_empty():
        cancel_route()
        comparison_snapshot = values.duplicate(true)
        comparison_rig_pose = rig.pose_snapshot()
        comparison_candidate = settings.candidate_from_values(values,lamp_overrides)
        comparison_background_preset = farfield.profile_id
        comparison_player_facing = player.facing
        values.fixed_animation = true
        values.fixed_light = true
        values.animation_frame = player.animation_frame
        values.normals_enabled = not values.normals_enabled
        camera_locked = true
        status_text = "同机位比较：已固定动画和灯位，法线已切换。再次点击恢复。"
    else:
        values = comparison_snapshot.duplicate(true)
        comparison_snapshot.clear()
        lamp_overrides = comparison_candidate.lamp_overrides.duplicate(true)
        parallax.apply_snapshot(comparison_candidate.parallax)
        farfield.apply_preset(comparison_background_preset)
        camera_locked = false
        status_text = "比较结束，原参数已恢复。"
    apply_parameters()
    if comparison_snapshot.is_empty() and not comparison_rig_pose.is_empty():
        player.facing = comparison_player_facing
        player.update_animation()
        rig.restore_pose(comparison_rig_pose)
        comparison_rig_pose.clear()
        comparison_candidate.clear()
        camera_offset = rig.follow_offset
        parallax.update(0,true)
        update_focus()
    sync_input()

func nearest_interaction() -> Dictionary:
    var nearest: Dictionary = {}
    var best := 1.65
    var entries: Array = layout.npcs+layout.interactions
    for entry in entries:
        var distance: float = player.position.distance_to(vec(entry.position))
        if distance<best:
            best = distance
            nearest = entry
    return nearest

func interact() -> void:
    if console.visible or route_running: return
    if dialogue.visible: dialogue.hide()
    else:
        var entry := nearest_interaction()
        if not entry.is_empty():
            dialogue_text.text = entry.name+"\n"+entry.dialogue
            dialogue.show()
    sync_input()

func sync_input() -> void:
    player.controls_enabled = not console.visible and not dialogue.visible and not exit_confirmation.visible and comparison_snapshot.is_empty() and lamp_isolation_snapshot.is_empty()

func request_quit() -> void:
    cancel_route()
    exit_confirmation.popup_centered(Vector2i(680,170))
    exit_confirmation.get_cancel_button().grab_focus()
    sync_input()

func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton or not event.pressed: return
    if event.button_index not in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: return
    if event.ctrl_pressed or event.alt_pressed or event.shift_pressed or event.meta_pressed: return
    if console.visible or dialogue.visible or exit_confirmation.visible or route_running or camera_locked: return
    var focus := get_viewport().gui_get_focus_owner()
    if focus is LineEdit or focus is TextEdit: return
    var step := -.5 if event.button_index==MOUSE_BUTTON_WHEEL_UP else .5
    if set_lens("radius",clampf(float(rig.lens_snapshot().radius)+step,18.0,45.0)):
        get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo: return
    if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed: return
    if event.keycode==KEY_ESCAPE:
        if route_running: cancel_route()
        elif console.dismiss_popup(): pass
        elif console.visible: console.close()
        elif dialogue.visible: dialogue.hide()
        elif exit_confirmation.visible: exit_confirmation.hide()
        else: request_quit()
        sync_input()
        get_viewport().set_input_as_handled()
        return
    if console.is_text_editing() or console.has_open_popup() or exit_confirmation.visible or dialogue.visible: return
    if route_running: return
    if console.visible and event.keycode!=KEY_M: return
    match event.keycode:
        KEY_M: console.toggle(); sync_input()
        KEY_E: interact()
        KEY_T: cycle_time()
        KEY_G: cancel_route() if route_running else start_route()
        KEY_K: capture_screenshot()
        _: return
    get_viewport().set_input_as_handled()

func start_route() -> void:
    if camera_locked: status_text = "请先结束固定机位比较或单灯隔离。"; return
    if route_running: return
    console.close()
    dialogue.hide()
    route_cancelled = false
    route_running = true
    route_frames = 0
    route_trajectory.clear()
    var start := 0
    var distance := INF
    for i in range(layout.route.size()):
        var d: float = player.position.distance_to(vec(layout.route[i]))
        if d<distance: start = i; distance = d
    route_points.clear()
    for i in range(layout.route.size()+1): route_points.append(layout.route[(start+i)%layout.route.size()])
    route_index = 0
    player.scripted_input = true
    status_text = "自动路线进行中，Esc 或移动键取消。"
    sync_input()

func cancel_route() -> void:
    if not route_running: return
    route_cancelled = true
    finish_route(false)

func finish_route(passed: bool) -> void:
    route_running = false
    player.scripted_input = false
    player.scripted_direction = Vector2.ZERO
    route_result = {"passed":passed,"cancelled":route_cancelled,"frames":route_frames,"trajectory":route_trajectory.duplicate(true)}
    status_text = "自动路线完成。" if passed else ("自动路线已取消。" if route_cancelled else "自动路线受阻，请查看验收记录。")

func _physics_process(_delta: float) -> void:
    if not route_running: return
    route_frames += 1
    if route_frames%12==0: route_trajectory.append([player.position.x,player.position.y,player.position.z])
    if route_frames>15000: finish_route(false); return
    var delta := vec(route_points[route_index])-player.position
    delta.y = 0
    if delta.length()<.23:
        route_index += 1
        if route_index>=route_points.size(): finish_route(true); return
        delta = vec(route_points[route_index])-player.position
        delta.y = 0
    player.scripted_direction = Vector2(delta.x,delta.z).normalized()

func _process(delta: float) -> void:
    if frozen: return
    elapsed += delta
    water_clock += delta
    water_material.set_shader_parameter("clock",water_clock)
    if route_running and Input.get_vector("move_left","move_right","move_up","move_down")!=Vector2.ZERO: cancel_route()
    if values.orbit_light and not values.fixed_light:
        var angle: float = elapsed*values.orbit_speed
        test_light.position = Vector3(clampf(player.position.x+cos(angle)*3.0,-20,20),values.test_light_y,clampf(player.position.z+sin(angle)*3.0,-16,16))
        values.test_light_x = test_light.position.x
        values.test_light_z = test_light.position.z
    values.animation_frame = player.animation_frame
    camera_update(delta)
    farfield.advance(delta)
    update_focus()
    var entry := nearest_interaction()
    prompt.text = "E  "+entry.name if not entry.is_empty() and not console.visible and not dialogue.visible else ""
    hud_status.text = ("自定义" if values.time_preset=="custom" else {"day":"晴昼","dusk":"黄昏","night":"夜晚"}[values.time_preset])+" · 法线 "+("开" if values.normals_enabled else "关")+" · "+("原生受光" if values.shading_mode=="native" else str(values.light_steps)+"档受光")
    sync_input()

func capture_screenshot() -> void:
    await RenderingServer.frame_post_draw
    var image: Image = get_viewport().get_texture().get_image()
    var path := "user://screenshots/jiangnan-"+str(Time.get_unix_time_from_system())+"-"+str(capture_counter)+".png"
    capture_counter += 1
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var error := image.save_png(ProjectSettings.globalize_path(path))
    status_text = "画面已保存到本机截图目录。" if error==OK else "截图保存失败。"
