extends Node
## Deterministic comparison recording; never enabled during normal exploration.
var scene: Node3D
var elapsed := 0.0
var segment := -1
var title: Label
const PRESETS = ["soft","natural","enhanced"]
func _ready() -> void:
    scene = get_parent()
    scene.tour = false
    scene.follow = true
    scene.clock_frozen = true
    scene.hud.container.hide()
    scene.player.scripted_input = true
    scene.lighting.apply_preset("day")
    scene.lighting.water.set_shader_parameter("motion",0.0)
    var overlay := CanvasLayer.new()
    add_child(overlay)
    title = Label.new()
    title.position = Vector2(40,35)
    title.add_theme_font_size_override("font_size",28)
    title.add_theme_color_override("font_shadow_color",Color.BLACK)
    title.add_theme_constant_override("shadow_offset_x",2)
    title.add_theme_constant_override("shadow_offset_y",2)
    overlay.add_child(title)
    begin_segment(0)

func begin_segment(index: int) -> void:
    segment = index
    scene.parallax.reset_all()
    scene.parallax.select_preset(PRESETS[index])
    scene.background.wind_enabled = false
    scene.background.wind_phases.assign([0.0,0.0])
    scene.background.advance(0)
    var direction: Vector3 = scene.to_vector(scene.layout.walkway.direction)
    scene.player.position = scene.to_vector(scene.layout.walkway.center)-direction*14.5+Vector3.UP*0.2
    scene.player.velocity = Vector3.ZERO
    scene.player.scripted_direction = Vector2.ZERO
    scene.rig.set_offset(scene.rig.desired_offset(scene.player.position))
    scene.parallax.update(0,true)
    scene.dof.mode = "protected"
    scene.dof.focus_depth = scene.dof.depth(scene.player.position+Vector3.UP)
    title.text = "PARALLAX / %s / %.2fx natural motion\nSame 30m walkway and camera settings; wind frozen" % [PRESETS[index].to_upper(),scene.parallax.profile.effective("ridge_near")]

func _process(delta: float) -> void:
    elapsed += delta
    var index := mini(int(elapsed/12.0),2)
    if index != segment: begin_segment(index)
    var phase := fmod(elapsed,12.0)
    var direction: Vector3 = scene.to_vector(scene.layout.walkway.direction)
    var coordinate: float = (scene.player.position-scene.to_vector(scene.layout.walkway.center)).dot(direction)
    var moving := phase > 1.0 and phase < 11.0 and coordinate < 14.5
    scene.player.scripted_direction = Vector2(direction.x,direction.z) if moving else Vector2.ZERO
