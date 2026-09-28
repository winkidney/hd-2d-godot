extends Node3D
## Lighting is a presentation boundary; preset changes never rebuild physics.
var environment: Environment
var camera_attributes: CameraAttributesPractical
var sun: DirectionalLight3D
var lamps: Array[OmniLight3D] = []
var water: ShaderMaterial
var preset_id := "dusk"
var effects_enabled := true

func configure(camera: Camera3D, world: Node3D, layout: Dictionary) -> void:
    environment = Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.ssao_enabled = true
    environment.ssao_radius = 1.4
    environment.ssao_intensity = 1.4
    environment.glow_enabled = true
    environment.glow_intensity = 0.75
    environment.glow_bloom = 0.035
    environment.glow_hdr_threshold = 1.1
    var world_environment := WorldEnvironment.new()
    world_environment.environment = environment
    add_child(world_environment)
    sun = DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-38, -42, 0)
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 85.0
    sun.shadow_bias = 0.035
    add_child(sun)
    for entry in layout.lamps:
        add_lamp(Vector3(entry[0] + 0.52, 2.0, entry[2]), lamps.size() < 2)
    for entry in layout.buildings:
        var pos: Array = entry.position
        add_lamp(Vector3(pos[0], 2.1, pos[2] + 2.4 * float(entry.scale)), false)
    camera_attributes = CameraAttributesPractical.new()
    camera_attributes.dof_blur_near_distance = 30.0
    camera_attributes.dof_blur_near_transition = 5.0
    camera_attributes.dof_blur_far_distance = 46.0
    camera_attributes.dof_blur_far_transition = 10.0
    camera_attributes.dof_blur_amount = 0.085
    camera.attributes = camera_attributes
    water = world.get_node("WaterSurface").material_override as ShaderMaterial
    apply_preset("dusk")

func add_lamp(pos: Vector3, shadows: bool) -> void:
    var light := OmniLight3D.new()
    light.position = pos
    light.light_color = Color("ffb562")
    light.omni_range = 6.0
    light.omni_attenuation = 1.6
    light.shadow_enabled = shadows
    light.light_size = 0.12
    add_child(light)
    lamps.append(light)

func apply_preset(id: String) -> void:
    assert(id in ["dusk", "night"])
    var preset := load("res://resources/" + id + ".tres")
    preset_id = id
    sun.light_color = preset.sun_color
    sun.light_energy = preset.sun_energy
    environment.background_color = preset.fog_color
    environment.ambient_light_color = preset.ambient_color
    environment.ambient_light_energy = preset.ambient_energy
    environment.volumetric_fog_albedo = preset.fog_color
    environment.volumetric_fog_density = preset.fog_density
    environment.volumetric_fog_length = 100.0
    for lamp in lamps:
        lamp.light_energy = preset.lamp_energy
    water.set_shader_parameter("deep_color", preset.water_deep)
    water.set_shader_parameter("shallow_color", preset.water_shallow)
    set_effects(effects_enabled)

func set_effects(enabled: bool) -> void:
    effects_enabled = enabled
    environment.glow_enabled = enabled
    environment.ssao_enabled = enabled
    environment.volumetric_fog_enabled = enabled
    camera_attributes.dof_blur_near_enabled = enabled
    camera_attributes.dof_blur_far_enabled = enabled
