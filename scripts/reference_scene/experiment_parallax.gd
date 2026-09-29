extends "res://scripts/parallax_controller.gd"
## Representative-point screen-X compensation, recomputed from world bases.
## D uses the same exact projection equation with explicit 2.5D layer gains.
const D_GAINS := {"ridge_near": 0.6, "ridge_mid": 0.3, "ridge_far": 0.12,
    "clouds_near": 0.6, "clouds_far": 0.25}
var variant_id := "A"
var variant_settings: Dictionary = {}
var variant_defaults: Dictionary = {}
var projections: Dictionary = {}

func configure(value: Camera3D, camera_rig: RefCounted, backdrop: Node3D, layout_text: String) -> void:
    super.configure(value, camera_rig, backdrop, layout_text)
    for id in ["A", "B", "C", "D"]:
        var settings: Dictionary = defaults.duplicate(true)
        if id == "D":
            settings.mode = "artistic"
            for layer in D_GAINS:
                settings[layer] = D_GAINS[layer]
        variant_settings[id] = settings.duplicate(true)
        variant_defaults[id] = settings.duplicate(true)

func select_variant(id: String) -> bool:
    if not variant_settings.has(id):
        return false
    variant_settings[variant_id] = snapshot().duplicate(true)
    variant_id = id
    for key in variant_settings[id]:
        change(key, variant_settings[id][key])
    defaults = variant_defaults[id].duplicate(true)
    update(0.0, true)
    return true

func reset_all() -> void:
    super.reset_all()
    variant_settings[variant_id] = snapshot().duplicate(true)

func update(delta: float, immediate := false) -> void:
    compatible = rig.supported_pose()
    notice = "" if compatible else "Unsupported external camera pose; decorative layers restored to natural positions."
    var actual_inverse := camera.get_camera_transform().affine_inverse()
    var virtual_transform := camera.get_camera_transform()
    virtual_transform.origin -= rig.horizontal_follow
    var virtual_inverse := virtual_transform.affine_inverse()
    var viewport_size := camera.get_viewport().get_visible_rect().size
    var projection := camera.get_camera_projection()
    var focal := projection.x.x * viewport_size.x * 0.5
    var perspective := camera.projection == Camera3D.PROJECTION_PERSPECTIVE
    projections.clear()
    for id in Profile.IDS:
        var requested: float = profile.effective(id) if compatible else 1.0
        if immediate or not compatible or profile.transition_time <= 0.0:
            current[id] = requested
        else:
            current[id] = move_toward(float(current[id]), requested, 2.0 * delta / profile.transition_time)
        var base: Transform3D = states[id].base
        var point: Vector3 = base * states[id].point
        var actual: Vector3 = actual_inverse * point
        var virtual: Vector3 = virtual_inverse * point
        var valid := -actual.z > camera.near and -virtual.z > camera.near and absf(focal) > 0.001
        var natural_x := projected_x(actual, focal, perspective)
        var virtual_x := projected_x(virtual, focal, perspective)
        var ratio := float(current[id])
        var desired_x := virtual_x + ratio * (natural_x - virtual_x)
        if valid and compatible:
            var metres_per_pixel := -actual.z / focal if perspective else 1.0 / focal
            base.origin += camera.global_basis.x * (desired_x - natural_x) * metres_per_pixel
        elif not valid:
            notice = "A decorative representative point is behind the camera; that layer stays in world space."
        states[id].node.global_transform = base
        var actual_result: Vector3 = actual_inverse * layer_point(id)
        projections[id] = {"natural_x": natural_x, "virtual_x": virtual_x,
            "expected_x": desired_x, "result_x": projected_x(actual_result, focal, perspective),
            "valid": valid, "depth": -actual.z, "focal": focal,
            "perspective": perspective}

static func projected_x(camera_point: Vector3, focal: float, perspective: bool) -> float:
    return focal * camera_point.x / maxf(-camera_point.z, 0.00001) if perspective else focal * camera_point.x

func diagnostics() -> Dictionary:
    var result: Dictionary = {}
    for id in Profile.IDS:
        var info: Dictionary = projections.get(id, {})
        var depth := float(info.get("depth", 1.0))
        var focal := float(info.get("focal", 0.0))
        var scale := focal / maxf(depth, 0.01) if camera.projection == Camera3D.PROJECTION_PERSPECTIVE else focal
        result[id] = {"requested": profile.requested(id), "target": profile.effective(id),
            "effective": current[id], "depth": depth, "px_per_m": scale * float(current[id]),
            "capped": profile.mode == "artistic" and profile.requested(id) > 2.0,
            "representative_error_px": absf(float(info.get("result_x", 0.0)) - float(info.get("expected_x", 0.0))),
            "valid": info.get("valid", false), "implementation": "layered_2_5d" if variant_id == "D" else "projection_compensation"}
    return result

func layer_sample_errors(id: String) -> Dictionary:
    # The representative is exact; sample several real mesh extents to expose
    # the remaining perspective approximation across a deep background layer.
    var state: Dictionary = states[id]
    var node: Node3D = state.node
    var meshes := node.find_children("*", "MeshInstance3D", true, false)
    var samples: Array[float] = []
    if meshes.is_empty():
        return {"count": 0, "max_error_px": 0.0, "errors_px": samples}
    var inverse := camera.get_camera_transform().affine_inverse()
    var virtual_transform := camera.get_camera_transform()
    virtual_transform.origin -= rig.horizontal_follow
    var virtual_inverse := virtual_transform.affine_inverse()
    var focal := camera.get_camera_projection().x.x * camera.get_viewport().get_visible_rect().size.x * 0.5
    var perspective := camera.projection == Camera3D.PROJECTION_PERSPECTIVE
    var indices: Array[int] = [0]
    if meshes.size() > 2:
        indices.append(meshes.size() / 2)
    if meshes.size() > 1:
        indices.append(meshes.size() - 1)
    var maximum := 0.0
    for index in indices:
        var mesh := meshes[index] as MeshInstance3D
        var bounds := mesh.get_aabb()
        for tx in [0.0, 0.5, 1.0]:
            for tz in [0.0, 0.5, 1.0]:
                var mesh_point := bounds.position + bounds.size * Vector3(tx, 0.5, tz)
                var local_point := node.to_local(mesh.to_global(mesh_point))
                var base_point: Vector3 = state.base * local_point
                var actual: Vector3 = inverse * base_point
                var virtual: Vector3 = virtual_inverse * base_point
                if -actual.z <= camera.near or -virtual.z <= camera.near:
                    continue
                var natural_x := projected_x(actual, focal, perspective)
                var virtual_x := projected_x(virtual, focal, perspective)
                var expected := virtual_x + float(current[id]) * (natural_x - virtual_x)
                var result := projected_x(inverse * node.to_global(local_point), focal, perspective)
                var error := absf(result - expected)
                samples.append(error)
                maximum = maxf(maximum, error)
    return {"count": samples.size(), "max_error_px": maximum, "errors_px": samples}

func warnings() -> String:
    var common := super.warnings()
    var extra := "Representative screen X is exact; other points in a layer retain a depth-dependent approximation."
    if variant_id == "D":
        extra = "D: 2.5D layer ratios; building side views are baked images. " + extra
    if notice != "" and compatible:
        extra = notice + "\n" + extra
    return extra if common == "" else common + "\n" + extra
