extends "res://scripts/parallax_preview.gd"
## Restore the rig's orbit and follow state, not only its visible transform.
var saved_pose: Dictionary = {}

func start(value: Node3D) -> bool:
    if active:
        return true
    scene = value
    start_offset = scene.rig.follow_offset
    var dx := start_offset.dot(scene.rig.initial_right)
    amplitude = minf(3.0, maxf(0.0, float(scene.rig.max_offset.x) - absf(dx)))
    if amplitude < 0.1:
        message = "Camera at its limit: return toward the centre before comparison."
        scene = null
        return false
    saved_pose = scene.rig.pose_snapshot()
    saved = {"camera":scene.camera.global_transform, "frozen":scene.rig.frozen,
        "clock":scene.clock_frozen, "tour":scene.tour, "follow":scene.follow,
        "focus_mode":scene.dof.mode, "manual_depth":scene.dof.manual_depth,
        "focus_depth":scene.dof.focus_depth,
        "water_motion":scene.lighting.water.get_shader_parameter("motion")}
    scene.rig.frozen = true
    scene.clock_frozen = true
    scene.tour = false
    scene.dof.mode = "manual"
    scene.dof.manual_depth = scene.dof.focus_depth
    scene.lighting.water.set_shader_parameter("motion", 0.0)
    elapsed = 0.0
    active = true
    message = "Camera comparison: actor fixed, water and clouds paused."
    return true

func stop() -> void:
    if not active:
        return
    scene.rig.restore_pose(saved_pose)
    super.stop()
    saved_pose.clear()
