extends "res://scripts/parallax_preview.gd"
## The saved rig pose includes orbit and follow smoothing, not only the camera.
var saved_pose: Dictionary = {}
var saved_multiview: Dictionary = {}

func start(value: Node3D) -> bool:
    if active:
        return true
    scene = value
    start_offset = value.rig.follow_offset
    var dx := start_offset.dot(scene.rig.horizontal_right())
    amplitude = minf(2.0, maxf(0.0, float(scene.rig.max_offset.x) - absf(dx)))
    if amplitude < 0.1:
        message = "Camera at its limit: walk toward the centre before preview."
        scene = null
        return false
    saved_pose = scene.rig.pose_snapshot()
    saved_multiview = scene.impostor.pose_snapshot() if scene.impostor.available else {}
    saved = {"camera": scene.camera.global_transform, "frozen": scene.rig.frozen,
        "clock": scene.clock_frozen, "tour": scene.tour, "follow": scene.follow,
        "focus_mode": scene.dof.mode, "manual_depth": scene.dof.manual_depth,
        "focus_depth": scene.dof.focus_depth,
        "water_motion": scene.lighting.water.get_shader_parameter("motion")}
    scene.rig.frozen = true
    scene.clock_frozen = true
    scene.tour = false
    scene.dof.mode = "manual"
    scene.dof.manual_depth = scene.dof.focus_depth
    scene.lighting.water.set_shader_parameter("motion", 0.0)
    elapsed = 0.0
    active = true
    message = "Camera comparison: clouds and water frozen; player stays put."
    return true

func stop() -> void:
    if not active:
        return
    # Parent stop restores the displayed camera, clock, focus and input mode.
    # Restore internals first so its final parallax update uses the saved pose.
    scene.rig.restore_pose(saved_pose)
    if not saved_multiview.is_empty():
        scene.impostor.restore_pose(saved_multiview)
    super.stop()
    saved_pose.clear()
    saved_multiview.clear()
