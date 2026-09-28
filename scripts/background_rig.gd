extends Node3D
## Mountains stay in world space. Only clouds have independent wind motion.
var sky_material: ShaderMaterial
var layer_materials: Dictionary = {}
var layers: Dictionary = {}
var clouds: Array[Dictionary] = []
var wind_enabled := true
var cloud_time := 0.0
var visible_background := true
var environment: Environment
var profile_id := "day"
var palette_config: Dictionary
var config: Dictionary

func configure(env: Environment) -> void:
    config = JSON.parse_string(FileAccess.get_file_as_string("res://resources/background.json"))
    assert(config.schema == 1 and int(config.cloud_count_per_layer) >= 1 and int(config.cloud_count_per_layer) <= 12)
    palette_config = config.palettes
    for id in ["day","dusk","night"]: assert(palette_config.has(id) and palette_config[id].size() == 7)
    environment = env
    name = "BackgroundRig"
    var sky := Sky.new()
    sky_material = ShaderMaterial.new()
    sky_material.shader = load("res://shaders/waystation_sky.gdshader")
    sky.sky_material = sky_material
    sky.radiance_size = Sky.RADIANCE_SIZE_128
    environment.sky = sky
    environment.background_mode = Environment.BG_SKY
    for id in ["valley", "ridge_near", "ridge_mid", "ridge_far"]:
        var item := (load("res://assets/background/" + id + ".glb") as PackedScene).instantiate()
        item.name = id
        add_child(item)
        layers[id] = item
        var material: Material = terrain_material() if id == "valley" else ridge_material()
        layer_materials[id] = material
        dress(item, material)
    build_tree_line()
    for layer in range(2):
        for index in range(int(config.cloud_count_per_layer)):
            var card := MeshInstance3D.new()
            card.name = "Cloud_%d_%d" % [layer, index]
            var mesh := QuadMesh.new()
            mesh.size = Vector2(48,18) if layer == 0 else Vector2(125,47)
            card.mesh = mesh
            var material := StandardMaterial3D.new()
            material.albedo_texture = load("res://assets/background/cloud-%d.png" % (index % 3))
            material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
            material.alpha_scissor_threshold = 0.5
            material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
            material.disable_fog = true
            card.material_override = material
            card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            var pos := Vector3((index-4)*65, 29+(index%3)*5, -240-(index%2)*25) if layer == 0 else Vector3((index-4)*180, 87+(index%3)*10, -760)
            card.position = pos
            add_child(card)
            clouds.append({"node":card,"origin":pos,"speed":float(config.cloud_wind_speeds[layer]),"span":585.0 if layer == 0 else 1620.0})
    apply_preset("day")

func dress(node: Node, material: Material) -> void:
    if node is MeshInstance3D:
        node.material_override = material
        node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    for child in node.get_children():
        dress(child, material)

func apply_preset(id: String) -> void:
    assert(palette_config.has(id))
    profile_id = id
    var palette: Array = palette_config[id]
    sky_material.set_shader_parameter("zenith", Color(palette[0]))
    sky_material.set_shader_parameter("horizon", Color(palette[1]))
    sky_material.set_shader_parameter("night", 1.0 if id == "night" else 0.0)
    var index := 2
    for key in ["valley", "ridge_near", "ridge_mid", "ridge_far"]:
        if layer_materials[key] is StandardMaterial3D:
            layer_materials[key].albedo_color = Color(palette[index])
        index += 1
    for cloud in clouds:
        cloud.node.material_override.albedo_color = Color(palette[6])

func advance(delta: float) -> void:
    if wind_enabled:
        cloud_time += delta
    for cloud in clouds:
        var p: Vector3 = cloud.origin
        p.x = wrapf(p.x + cloud_time * float(cloud.speed), -float(cloud.span)*0.5, float(cloud.span)*0.5)
        cloud.node.position = p

func terrain_material() -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = load("res://shaders/pixel_surface.gdshader")
    material.set_shader_parameter("albedo_tex",load("res://assets/textures/grass.png"))
    material.set_shader_parameter("texture_scale",0.55)
    return material

func ridge_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.disable_fog = true
    material.roughness = 1.0
    return material

func build_tree_line() -> void:
    var row := MultiMeshInstance3D.new()
    row.name = "DistantTreeLine"
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    var mesh := QuadMesh.new()
    mesh.size = Vector2(4.2,4.2)
    multi.mesh = mesh
    multi.instance_count = 150
    var rng := RandomNumberGenerator.new()
    rng.seed = 290928
    for i in range(150):
        var scale_value := rng.randf_range(0.7,1.35)
        var pos := Vector3(-300+i*4.0,2.1*scale_value,-32+rng.randf_range(-5,3))
        multi.set_instance_transform(i,Transform3D(Basis(Vector3.UP,deg_to_rad(10)).scaled(Vector3.ONE*scale_value),pos))
    row.multimesh = multi
    var material := StandardMaterial3D.new()
    material.albedo_texture = load("res://assets/sprites/oak.png")
    material.albedo_color = Color("879b89")
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
    material.alpha_scissor_threshold = 0.5
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
    material.roughness = 1.0
    row.material_override = material
    row.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(row)
