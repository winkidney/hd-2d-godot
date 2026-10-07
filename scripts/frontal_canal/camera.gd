extends "res://scripts/camera_rig.gd"
## Frontal cameras share a -Z central view and a genuine lateral crossing.
const VARIANTS := {
    "F": {"fov":35.0, "pitch":14.0, "radius":30.0, "yaw_limit":0.0},
    "W": {"fov":45.0, "pitch":12.0, "radius":23.0, "yaw_limit":0.0},
    "O": {"fov":35.0, "pitch":14.0, "radius":30.0, "yaw_limit":4.0}}
const ORBIT_DEAD_ZONE := 1.0
const ORBIT_RAMP_DISTANCE := 12.0
const ORBIT_SMOOTHING := 2.5
const LENS_LIMITS := {"radius":Vector2(18.0,45.0), "fov":Vector2(25.0,60.0)}
var lens_profiles: Dictionary = {}
var variant_id := "F"
var yaw_degrees := 0.0
var target_yaw_degrees := 0.0
var horizontal_follow := Vector3.ZERO
var follow_offset := Vector3.ZERO
var initial_right := Vector3.RIGHT
var reference_basis := Basis.IDENTITY
var orbit_vector := Vector3.ZERO
var _test_yaw := NAN

func configure(value: Camera3D, config: Dictionary, player_spawn: Vector3) -> void:
    camera = value
    target = vec(config.get("target", [4.0,4.0,1.0]))
    anchor = player_spawn
    gain = 0.25
    dead_zone = 1.5
    smoothing = 4.0
    max_offset = Vector2(22.0, 3.0)
    horizontal_gain = 0.7
    horizontal_dead_zone = 1.0
    camera.far = float(config.get("far", 1400.0))
    camera.near = 0.1
    for id in VARIANTS:
        lens_profiles[id] = lens_defaults(id)
    select_variant("F", anchor)

func horizontal_right() -> Vector3:
    return initial_right

func select_variant(id: String, player_position := Vector3.INF) -> bool:
    if not VARIANTS.has(id):
        return false
    variant_id = id
    apply_lens()
    _test_yaw = NAN
    if player_position.is_finite():
        follow_offset = desired_offset(player_position) if enabled else Vector3.ZERO
        target_yaw_degrees = desired_yaw(player_position)
    else:
        target_yaw_degrees = 0.0
    yaw_degrees = target_yaw_degrees
    set_offset(follow_offset)
    return true

func lens_defaults(id: String) -> Dictionary:
    return {"radius":float(VARIANTS[id].radius), "fov":float(VARIANTS[id].fov)}

func lens_snapshot() -> Dictionary:
    return lens_profiles[variant_id].duplicate()

func lens_profiles_defaults() -> Dictionary:
    var result: Dictionary = {}
    for id in VARIANTS:
        result[id] = lens_defaults(id)
    return result

func lens_profiles_snapshot() -> Dictionary:
    return lens_profiles.duplicate(true)

func lens_profiles_error(value: Variant) -> String:
    if not value is Dictionary or value.size() != VARIANTS.size():
        return "All three camera lens profiles are required."
    for id in VARIANTS:
        if not value.has(id) or not value[id] is Dictionary:
            return "Missing camera lens profile."
        var profile: Dictionary = value[id]
        if profile.size() != LENS_LIMITS.size():
            return "Unknown or missing lens setting."
        for key in LENS_LIMITS:
            if not profile.has(key):
                return "Missing lens setting."
            var error := lens_error(key, profile[key])
            if not error.is_empty():
                return error
    return ""

func validate_lens_profiles(value: Variant) -> Dictionary:
    if not lens_profiles_error(value).is_empty():
        return {}
    var result: Dictionary = {}
    for id in VARIANTS:
        result[id] = {"radius":float(value[id].radius), "fov":float(value[id].fov)}
    return result

func restore_lens_profiles(value: Dictionary, active_id: String, player_position := Vector3.INF) -> bool:
    if not VARIANTS.has(active_id) or camera == null:
        return false
    var candidate := validate_lens_profiles(value)
    if candidate.is_empty():
        return false
    # Validate inactive profiles as well, then update the actual pose only once.
    lens_profiles = candidate
    return select_variant(active_id, player_position)

func lens_error(key: String, value: Variant) -> String:
    if not LENS_LIMITS.has(key): return "Unknown lens setting."
    if typeof(value) not in [TYPE_INT,TYPE_FLOAT]: return "A number is required."
    var limits: Vector2 = LENS_LIMITS[key]
    if not is_finite(float(value)) or float(value)<limits.x or float(value)>limits.y:
        return "Lens setting outside supported range."
    return ""

func set_lens(key: String, value: Variant) -> bool:
    if not lens_error(key,value).is_empty(): return false
    lens_profiles[variant_id][key] = float(value)
    apply_lens()
    return true

func reset_lens() -> void:
    lens_profiles[variant_id] = lens_defaults(variant_id)
    apply_lens()

func apply_lens() -> void:
    # Lens changes preserve follow, yaw and their smoothing state.
    var lens: Dictionary = lens_profiles[variant_id]
    var pitch := deg_to_rad(float(VARIANTS[variant_id].pitch))
    orbit_vector = Vector3(0.0,sin(pitch),cos(pitch)) * float(lens.radius)
    home = target + orbit_vector
    reference_basis = Basis.looking_at(-orbit_vector,Vector3.UP)
    camera.set_perspective(float(lens.fov),camera.near,camera.far)
    set_offset(follow_offset)

func desired_yaw(player_position: Vector3) -> float:
    if not enabled:
        return 0.0
    var travel := (player_position - anchor).dot(initial_right)
    var limit := float(VARIANTS[variant_id].yaw_limit)
    return signf(travel) * clampf((absf(travel) - ORBIT_DEAD_ZONE) / ORBIT_RAMP_DISTANCE, 0.0, 1.0) * limit

func set_offset(offset: Vector3) -> void:
    follow_offset = offset
    horizontal_follow = initial_right * offset.dot(initial_right)
    var pivot := target + offset
    camera.global_position = pivot + orbit_vector.rotated(Vector3.UP, deg_to_rad(yaw_degrees))
    camera.look_at(pivot)

func set_test_yaw(value: float) -> void:
    var limit := float(VARIANTS[variant_id].yaw_limit)
    _test_yaw = clampf(value, -limit, limit)
    yaw_degrees = _test_yaw
    target_yaw_degrees = _test_yaw
    set_offset(follow_offset)

func clear_test_yaw() -> void:
    _test_yaw = NAN

func update(delta: float, player_position: Vector3, tour: bool, elapsed: float) -> void:
    if frozen:
        return
    var desired := desired_offset(player_position) if enabled else Vector3.ZERO
    if tour:
        desired = initial_right * sin(elapsed * 0.18) * 10.0
    target_yaw_degrees = desired_yaw(player_position) if is_nan(_test_yaw) else _test_yaw
    yaw_degrees = lerpf(yaw_degrees, target_yaw_degrees, 1.0 - exp(-ORBIT_SMOOTHING * delta))
    set_offset(follow_offset.lerp(desired, 1.0 - exp(-smoothing * delta)))

func supported_pose() -> bool:
    var expected_basis := Basis(Vector3.UP, deg_to_rad(yaw_degrees)) * reference_basis
    var expected_position := target + follow_offset + orbit_vector.rotated(Vector3.UP,deg_to_rad(yaw_degrees))
    return camera.projection == Camera3D.PROJECTION_PERSPECTIVE and camera.global_basis.is_equal_approx(expected_basis) and camera.global_position.is_equal_approx(expected_position) and is_equal_approx(camera.fov,float(lens_profiles[variant_id].fov))

func pose_snapshot() -> Dictionary:
    return {"variant_id":variant_id, "transform":camera.global_transform,
        "projection":camera.projection, "fov":camera.fov, "lens_profiles":lens_profiles.duplicate(true),
        "home":home, "orbit_vector":orbit_vector, "reference_basis":reference_basis,
        "follow_offset":follow_offset, "horizontal_follow":horizontal_follow,
        "yaw_degrees":yaw_degrees, "target_yaw_degrees":target_yaw_degrees, "test_yaw":_test_yaw}

func restore_pose(value: Dictionary) -> void:
    variant_id = value.variant_id
    lens_profiles = value.lens_profiles.duplicate(true)
    home = value.home
    orbit_vector = value.orbit_vector
    reference_basis = value.reference_basis
    follow_offset = value.follow_offset
    horizontal_follow = value.horizontal_follow
    yaw_degrees = value.yaw_degrees
    target_yaw_degrees = value.target_yaw_degrees
    _test_yaw = value.test_yaw
    camera.projection = value.projection
    camera.fov = value.fov
    camera.global_transform = value.transform

func actor_screen_height(feet: Vector3, pixel_size := 0.035, frame_height := 64.0, offset_pixels := 30.0) -> float:
    var center := feet + Vector3.UP * 0.04 + camera.global_basis.y * offset_pixels * pixel_size
    var half_height := camera.global_basis.y * frame_height * pixel_size * 0.5
    return camera.unproject_position(center + half_height).distance_to(camera.unproject_position(center - half_height))

func pose_diagnostics() -> Dictionary:
    return {"variant":variant_id, "projection":"perspective", "fov":camera.fov,
        "pitch_degrees":rad_to_deg(asin(camera.global_basis.z.y)),
        "yaw_degrees":yaw_degrees, "target_yaw_degrees":target_yaw_degrees,
        "orbit_radius":camera.global_position.distance_to(target + follow_offset),
        "horizontal_follow":[horizontal_follow.x,horizontal_follow.y,horizontal_follow.z],
        "camera_position":[camera.global_position.x,camera.global_position.y,camera.global_position.z],
        "supported":supported_pose()}
