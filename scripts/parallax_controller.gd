extends RefCounted
## Applies absolute camera-relative offsets to decorative layers only.
const Profile = preload("res://scripts/parallax_profile.gd")
var profile := Profile.new()
var camera: Camera3D
var rig: RefCounted
var background: Node3D
var camera_origin: Vector3
var reference_basis: Basis
var reference_fov: float
var right: Vector3
var states: Dictionary = {}
var current: Dictionary = {}
var defaults: Dictionary = {}
var layout_id := ""
var compatible := true
var notice := ""

func configure(value: Camera3D, camera_rig: RefCounted, backdrop: Node3D, layout_text: String) -> void:
    camera = value
    rig = camera_rig
    background = backdrop
    camera_origin = rig.home
    reference_basis = camera.global_basis
    reference_fov = camera.fov
    right = rig.horizontal_right()
    layout_id = layout_text.sha256_text()
    for id in Profile.IDS:
        var node: Node3D = backdrop.cloud_roots[id] if id.begins_with("clouds_") else backdrop.layers[id]
        var meshes := node.find_children("*", "MeshInstance3D", true, false)
        var point := Vector3.ZERO
        if not meshes.is_empty():
            var mesh := meshes[meshes.size()/2 if id.begins_with("clouds_") else 0] as MeshInstance3D
            point = node.to_local(mesh.to_global(mesh.get_aabb().get_center()))
        states[id] = {"node": node, "base": node.global_transform, "point": point}
        current[id] = 1.0
    defaults = snapshot()

func update(delta: float, immediate := false) -> void:
    compatible = camera.projection == Camera3D.PROJECTION_PERSPECTIVE
    compatible = compatible and reference_basis.is_equal_approx(camera.global_basis)
    compatible = compatible and is_equal_approx(camera.fov, reference_fov)
    notice = "" if compatible else "Camera orientation/projection changed: natural fallback."
    var dx := (camera.global_position-camera_origin).dot(right)
    for id in Profile.IDS:
        var target: float = profile.effective(id) if compatible else 1.0
        if immediate or not compatible or profile.transition_time <= 0.0:
            current[id] = target
        else:
            current[id] = move_toward(float(current[id]), target, 2.0*delta/profile.transition_time)
        var transform: Transform3D = states[id].base
        transform.origin += right * dx * (1.0-float(current[id]))
        states[id].node.global_transform = transform

func snapshot() -> Dictionary:
    var result := {"mode": profile.mode, "global_strength": profile.global_strength,
        "transition_time": profile.transition_time, "wind_enabled": background.wind_enabled,
        "horizontal_follow_gain": rig.horizontal_gain, "horizontal_dead_zone": rig.horizontal_dead_zone,
        "smoothing_rate": rig.smoothing, "horizontal_max_offset": rig.max_offset.x,
        "wind_near": background.wind_speeds[0], "wind_far": background.wind_speeds[1]}
    for id in Profile.IDS: result[id] = profile.layer_gains[id]
    return result

func select_preset(id: String) -> void:
    if id == "natural":
        profile.mode = "natural"
    elif id in ["soft", "enhanced"]:
        profile = load("res://resources/parallax/"+id+".tres").duplicate(true)
    elif id == "custom":
        profile.mode = "artistic"

func preset_name() -> String:
    if profile.mode == "natural": return "natural"
    for id in Profile.IDS:
        if not is_equal_approx(float(profile.layer_gains[id]),1.0): return "custom"
    if is_equal_approx(profile.global_strength,0.6): return "soft"
    if is_equal_approx(profile.global_strength,1.5): return "enhanced"
    return "custom"

func reset_all() -> void:
    for key in defaults: change(key, defaults[key])

func field_error(key: String, value: Variant) -> String:
    var ranges: Dictionary = preload("res://scripts/parallax_settings_store.gd").LIMITS
    if key == "mode":
        if typeof(value) != TYPE_STRING or value not in ["natural","artistic"]: return "Invalid mode."
    elif key == "wind_enabled":
        if typeof(value) != TYPE_BOOL: return "Wind switch must be boolean."
    else:
        if key not in Profile.IDS and not ranges.has(key): return "Unknown parameter."
        if typeof(value) not in [TYPE_FLOAT,TYPE_INT]: return "A number is required."
        var limits: Vector2 = ranges.get(key,Vector2(0,2))
        if not is_finite(float(value)) or float(value) < limits.x or float(value) > limits.y:
            return "Parameter outside supported range."
    return ""

func change(key: String, value: Variant) -> String:
    var error := field_error(key,value)
    if error != "": return error
    match key:
        "mode": profile.mode = value
        "global_strength": profile.global_strength = value
        "transition_time": profile.transition_time = value
        "horizontal_follow_gain": rig.horizontal_gain = value
        "horizontal_dead_zone": rig.horizontal_dead_zone = value
        "smoothing_rate": rig.smoothing = value
        "horizontal_max_offset": rig.max_offset.x = value
        "wind_enabled": background.wind_enabled = value
        "wind_near": background.wind_speeds[0] = value
        "wind_far": background.wind_speeds[1] = value
        _: profile.layer_gains[key] = value
    return ""

func layer_point(id: String) -> Vector3:
    return states[id].node.to_global(states[id].point)

func diagnostics() -> Dictionary:
    var result: Dictionary = {}
    var size := camera.get_viewport().get_visible_rect().size
    var focal := camera.get_camera_projection().x.x * size.x * 0.5
    for id in Profile.IDS:
        var depth := -(camera.get_camera_transform().affine_inverse()*layer_point(id)).z
        result[id] = {"requested": profile.requested(id), "target": profile.effective(id),
            "effective": current[id], "depth": depth,
            "px_per_m": focal*float(current[id])/maxf(depth,0.01),
            "capped": profile.mode == "artistic" and profile.requested(id) > 2.0}
    return result

func warnings() -> String:
    if not compatible: return notice
    var info := diagnostics()
    var messages: Array[String] = []
    for id in Profile.IDS:
        if info[id].capped: messages.append(id+": requested ratio capped at 2.0")
    if info.ridge_mid.px_per_m > info.ridge_near.px_per_m + 0.01 or info.ridge_far.px_per_m > info.ridge_mid.px_per_m + 0.01:
        messages.append("Layer speed order is inverted (custom art effect).")
    if rig.horizontal_gain < 0.2 or rig.max_offset.x < 2.0:
        messages.append("Low camera travel: parallax may be hard to see.")
    return "\n".join(messages)
