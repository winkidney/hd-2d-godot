extends RefCounted
## Temporary camera comparison; never relocates the player.
var active := false
var scene: Node3D
var saved: Dictionary = {}
var elapsed := 0.0
var amplitude := 0.0
var start_offset := Vector3.ZERO
var message := ""

func start(value: Node3D) -> bool:
    if active: return true
    scene = value
    start_offset = scene.camera.global_position - scene.rig.home
    var dx: float = start_offset.dot(scene.parallax.right)
    amplitude = minf(2.0,maxf(0.0,float(scene.rig.max_offset.x)-absf(dx)))
    if amplitude < 0.1:
        message = "Camera at its limit: walk toward the centre before preview."
        scene = null
        return false
    saved = {"camera": scene.camera.global_transform,"frozen": scene.rig.frozen,
        "clock": scene.clock_frozen,"tour": scene.tour,"follow": scene.follow,
        "focus_mode": scene.dof.mode,"manual_depth": scene.dof.manual_depth,
        "focus_depth": scene.dof.focus_depth,
        "water_motion": scene.lighting.water.get_shader_parameter("motion")}
    scene.rig.frozen = true
    scene.clock_frozen = true
    scene.tour = false
    scene.dof.mode = "manual"
    scene.dof.manual_depth = scene.dof.focus_depth
    scene.lighting.water.set_shader_parameter("motion",0.0)
    elapsed = 0.0
    active = true
    message = "Camera comparison: clouds and water frozen; player stays put."
    return true

func update(delta: float) -> void:
    if not active: return
    elapsed += delta
    scene.rig.set_offset(start_offset + scene.parallax.right * sin(elapsed*0.9) * amplitude)

func stop() -> void:
    if not active: return
    scene.camera.global_transform = saved.camera
    scene.rig.frozen = saved.frozen
    scene.clock_frozen = saved.clock
    scene.tour = saved.tour
    scene.follow = saved.follow
    scene.dof.mode = saved.focus_mode
    scene.dof.manual_depth = saved.manual_depth
    scene.dof.focus_depth = saved.focus_depth
    scene.dof.apply()
    scene.lighting.water.set_shader_parameter("motion",saved.water_motion)
    scene.parallax.update(0.0,true)
    active = false
    scene = null
    saved.clear()
