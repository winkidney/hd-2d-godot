extends RefCounted
## Cached materials. Camera parallax rotates the sky without changing its uniforms.
var environment: Environment
var daylight := ProceduralSkyMaterial.new()
var stars := ShaderMaterial.new()
var sky_resource := Sky.new()
var anchor_x := 0.0
var active := false
var enabled := true
var updates := 0
var focus_effect: CompositorEffect

func configure(value: Environment, reference_x: float, camera: Camera3D) -> void:
    environment = value
    anchor_x = reference_x
    stars.shader = preload("res://shaders/ancient_canal/night_sky.gdshader")
    stars.set_shader_parameter("panorama",preload("res://assets/ancient-canal/scenery/night-panorama.png"))
    sky_resource.process_mode = Sky.PROCESS_MODE_INCREMENTAL
    sky_resource.radiance_size = Sky.RADIANCE_SIZE_256
    environment.sky = sky_resource
    focus_effect = preload("res://scripts/ancient_canal/sky_focus.gd").new()
    var compositor := Compositor.new()
    compositor.compositor_effects = [focus_effect]
    camera.compositor = compositor
    focus_effect.near_plane = camera.near
    focus_effect.far_plane = camera.far

func apply_preset(period: String, top: Color, horizon: Color) -> void:
    active = period == "night" and enabled
    daylight.sky_top_color = top
    daylight.sky_horizon_color = horizon
    daylight.ground_horizon_color = horizon * .7
    daylight.ground_bottom_color = top * .5
    if stars.get_shader_parameter("sky_top_color") != top:
        stars.set_shader_parameter("sky_top_color",top)
    if stars.get_shader_parameter("sky_horizon_color") != horizon:
        stars.set_shader_parameter("sky_horizon_color",horizon)
    focus_effect.enabled = active
    var desired: Material = stars if active else daylight
    if sky_resource.sky_material != desired: sky_resource.sky_material = desired
    if not active: environment.sky_rotation = Vector3.ZERO

func update(camera: Camera3D) -> void:
    if not active: return
    var angle := deg_to_rad(clampf(-(camera.global_position.x-anchor_x)*.005,-.15,.15))
    if not is_equal_approx(environment.sky_rotation.y,angle):
        environment.sky_rotation = Vector3(0,angle,0)
        updates += 1
