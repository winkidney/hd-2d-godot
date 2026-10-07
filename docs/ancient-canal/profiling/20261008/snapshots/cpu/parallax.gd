extends RefCounted
## The profile owns all saved layer values; natural mode keeps authored positions.
const ProjectionMath = preload("res://scripts/projection_parallax.gd")
const IDS := ["near_town", "far_town", "near_hills", "far_mountains", "near_clouds", "far_clouds"]
const DEFAULT_PROFILE := {"mode": "natural", "global_strength": 1.0, "transition_time": 0.2,
    "near_town": 0.95, "far_town": 0.75, "near_hills": 0.6,
    "far_mountains": 0.35, "near_clouds": 0.45, "far_clouds": 0.2}

class LayerProfile extends RefCounted:
    var mode := "natural"
    var global_strength := 1.0
    var transition_time := 0.2
    var layer_gains: Dictionary = {"near_town": 0.95, "far_town": 0.75, "near_hills": 0.6,
        "far_mountains": 0.35, "near_clouds": 0.45, "far_clouds": 0.2}

    func snapshot() -> Dictionary:
        var result := {"mode": mode, "global_strength": global_strength, "transition_time": transition_time}
        result.merge(layer_gains)
        return result

    func field_error(key: String, value: Variant) -> String:
        if key == "mode":
            return "视差模式须为 natural 或 artistic。" if typeof(value) != TYPE_STRING or value not in ["natural", "artistic"] else ""
        if key not in ["global_strength", "transition_time"] and not layer_gains.has(key):
            return "未知视差参数：" + key
        if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
            return "视差参数须为有限数字。"
        var maximum := 1.0 if key == "transition_time" else 2.0
        return "视差参数超出范围。" if float(value) < 0.0 or float(value) > maximum else ""

    func validate_snapshot(data: Dictionary) -> String:
        var keys := snapshot().keys()
        if data.size() != keys.size(): return "视差设置字段不完整。"
        for key in keys:
            if not data.has(key): return "缺少视差参数：" + key
            var error := field_error(key, data[key])
            if error != "": return error
        return ""

    func change(key: String, value: Variant) -> String:
        var error := field_error(key, value)
        if error != "": return error
        match key:
            "mode": mode = value
            "global_strength": global_strength = float(value)
            "transition_time": transition_time = float(value)
            _: layer_gains[key] = float(value)
        return ""

    func apply_snapshot(data: Dictionary) -> bool:
        if validate_snapshot(data) != "": return false
        for key in data: change(key, data[key])
        return true

    func requested(id: String) -> float:
        return global_strength * float(layer_gains[id])

    func effective(id: String) -> float:
        return 1.0 if mode == "natural" else clampf(requested(id), 0.0, 2.0)

var profile := LayerProfile.new()
var camera: Camera3D
var rig: RefCounted
var background: Node3D
var states: Dictionary = {}
var current: Dictionary = {}
var projections: Dictionary = {}
var compatible := true
var notice := ""

func configure(value: Camera3D, camera_rig: RefCounted, backdrop: Node3D) -> void:
    camera = value
    rig = camera_rig
    background = backdrop
    states.clear()
    current.clear()
    for id in IDS:
        var node: Node3D = background.layers[id]
        var meshes := node.find_children("*", "MeshInstance3D", true, false)
        var point := Vector3.ZERO
        if not meshes.is_empty():
            var index: int = meshes.size() / 2 if id.ends_with("clouds") else 0
            var mesh := meshes[index] as MeshInstance3D
            point = node.to_local(mesh.to_global(mesh.get_aabb().get_center()))
        states[id] = {"node": node, "base": node.global_transform, "point": point}
        current[id] = 1.0
    update(0.0, true)

func snapshot() -> Dictionary:
    return profile.snapshot()

func defaults_snapshot() -> Dictionary:
    return DEFAULT_PROFILE.duplicate(true)

func validate_snapshot(data: Dictionary) -> String:
    return profile.validate_snapshot(data)

func apply_snapshot(data: Dictionary) -> bool:
    return profile.apply_snapshot(data)

func field_error(key: String, value: Variant) -> String:
    return profile.field_error(key, value)

func change(key: String, value: Variant) -> String:
    return profile.change(key, value)

func effective(id: String) -> float:
    return profile.effective(id)

func reset_all() -> void:
    profile.apply_snapshot(defaults_snapshot())
    if camera != null: update(0.0, true)

func layer_point(id: String) -> Vector3:
    return states[id].node.to_global(states[id].point)

func profile_original_update(delta: float, immediate := false) -> void:
    if camera == null: return
    if profile_skip_natural and profile.mode=="natural" and not immediate: return
    compatible = rig.supported_pose()
    notice = "" if compatible else "外部镜头姿态不受支持，背景已恢复自然位置。"
    var view := ProjectionMath.context(camera, rig.horizontal_follow)
    projections.clear()
    for id in IDS:
        var requested := profile.effective(id) if compatible else 1.0
        if immediate or not compatible or profile.transition_time <= 0.0:
            current[id] = requested
        else:
            current[id] = move_toward(float(current[id]), requested, 2.0 * maxf(delta, 0.0) / profile.transition_time)
        var base: Transform3D = states[id].base
        var info := ProjectionMath.sample(view, base * states[id].point, float(current[id]))
        if info.valid and compatible:
            base.origin += info.offset_world
        elif not info.valid:
            notice = "有背景参考点位于镜头之后，该层保持世界位置。"
        states[id].node.global_transform = base
        info["result_x"] = ProjectionMath.result_x(view, layer_point(id))
        projections[id] = info

func diagnostics() -> Dictionary:
    var result: Dictionary = {}
    for id in IDS:
        var info: Dictionary = projections.get(id, {})
        var depth := float(info.get("depth", 1.0))
        var focal := float(info.get("focal", 0.0))
        var scale := focal / maxf(depth, 0.01) if bool(info.get("perspective", true)) else focal
        result[id] = {"requested": profile.requested(id), "target": profile.effective(id),
            "effective": current.get(id, 1.0), "depth": depth,
            "px_per_m": scale * float(current.get(id, 1.0)),
            "capped": profile.mode == "artistic" and profile.requested(id) > 2.0,
            "representative_error_px": absf(float(info.get("result_x", 0.0)) - float(info.get("expected_x", 0.0))),
            "valid": info.get("valid", false), "implementation": "projection_compensation"}
    return result

func layer_sample_errors(id: String) -> Dictionary:
    var state: Dictionary = states[id]
    var node: Node3D = state.node
    var meshes := node.find_children("*", "MeshInstance3D", true, false)
    var errors: Array[float] = []
    var view := ProjectionMath.context(camera, rig.horizontal_follow)
    var indices: Array[int] = [0]
    if meshes.is_empty(): return {"count": 0, "max_error_px": 0.0, "errors_px": errors}
    if meshes.size() > 2: indices.append(meshes.size() / 2)
    if meshes.size() > 1: indices.append(meshes.size() - 1)
    var maximum := 0.0
    for index in indices:
        var mesh := meshes[index] as MeshInstance3D
        var bounds := mesh.get_aabb()
        for tx in [0.0, 0.5, 1.0]:
            for tz in [0.0, 0.5, 1.0]:
                var local_point := node.to_local(mesh.to_global(bounds.position + bounds.size * Vector3(tx, 0.5, tz)))
                var info := ProjectionMath.sample(view, state.base * local_point, float(current[id]))
                if not info.valid: continue
                var error := absf(ProjectionMath.result_x(view, node.to_global(local_point)) - float(info.expected_x))
                errors.append(error)
                maximum = maxf(maximum, error)
    return {"count": errors.size(), "max_error_px": maximum, "errors_px": errors}

func warnings() -> String:
    if not compatible: return notice
    return "背景参考点的水平投影准确补偿；同层其他深度仍有透视近似。" if profile.mode == "artistic" else notice

var profile_skip_natural := false

var profile_timings: Dictionary = {}
func profile_record(key: String, started: int) -> void:
    if not profile_timings.has(key): profile_timings[key] = []
    profile_timings[key].append(float(Time.get_ticks_usec()-started)/1000.0)

func update(delta: float,immediate := false) -> void:
    var started := Time.get_ticks_usec()
    profile_original_update(delta,immediate)
    profile_record("update",started)
