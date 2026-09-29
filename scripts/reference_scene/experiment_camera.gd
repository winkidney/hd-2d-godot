extends "res://scripts/camera_rig.gd"
## P9 camera experiments. Existing scenes keep the original fixed-pose rig.
const VARIANTS := ["A", "B", "C", "D"]
const ORBIT_LIMIT_DEGREES := 6.0
const ORBIT_DEAD_ZONE := 1.0
const ORBIT_RAMP_DISTANCE := 10.0
const ORBIT_SMOOTHING := 2.5
const ACTOR_ORIGIN_HEIGHT := 0.04
const ACTOR_PIXEL_SIZE := 0.035
const ACTOR_FRAME_HEIGHT := 64.0
const ACTOR_OFFSET_PIXELS := 30.0

var variant_id := "A"
var yaw_degrees := 0.0
var target_yaw_degrees := 0.0
var horizontal_follow := Vector3.ZERO
var orthographic_size := 20.0
var reference_basis := Basis.IDENTITY
var initial_right := Vector3.RIGHT
var follow_offset := Vector3.ZERO
var orbit_vector := Vector3.ZERO
var _configured := false
var _test_yaw := NAN

func configure(value: Camera3D, config: Dictionary, player_spawn: Vector3) -> void:
    _configured = false
    camera = value
    camera.projection = Camera3D.PROJECTION_PERSPECTIVE
    super.configure(value, config, player_spawn)
    camera.fov = 35.0
    reference_basis = camera.global_basis
    initial_right = Vector3(reference_basis.x.x, 0.0, reference_basis.x.z).normalized()
    orbit_vector = home - target
    # Sprite3D's pixel offset is along billboard up, not world up. Both
    # billboard ends share the depth of feet + the sprite's 0.04m origin.
    var reference_height := actor_screen_height(anchor)
    camera.set_orthogonal(1.0, camera.near, camera.far)
    orthographic_size = actor_screen_height(anchor) / reference_height
    _configured = true
    select_variant("A")

func horizontal_right() -> Vector3:
    return initial_right if _configured else super.horizontal_right()

func actor_screen_height(feet: Vector3) -> float:
    var center := feet + Vector3.UP * ACTOR_ORIGIN_HEIGHT + camera.global_basis.y * ACTOR_OFFSET_PIXELS * ACTOR_PIXEL_SIZE
    var half_height := camera.global_basis.y * ACTOR_FRAME_HEIGHT * ACTOR_PIXEL_SIZE * 0.5
    return camera.unproject_position(center + half_height).distance_to(camera.unproject_position(center - half_height))

func select_variant(id: String, player_position := Vector3.INF) -> bool:
    if id not in VARIANTS:
        return false
    variant_id = id
    _test_yaw = NAN
    if player_position.is_finite():
        follow_offset = desired_offset(player_position) if enabled else Vector3.ZERO
        target_yaw_degrees = desired_yaw(player_position)
    else:
        target_yaw_degrees = 0.0
    yaw_degrees = target_yaw_degrees
    if variant_id in ["C", "D"]:
        camera.set_orthogonal(orthographic_size, camera.near, camera.far)
    else:
        camera.set_perspective(35.0, camera.near, camera.far)
    set_offset(follow_offset)
    return true

func desired_yaw(player_position: Vector3) -> float:
    if variant_id not in ["B", "C"] or not enabled:
        return 0.0
    var travel := (player_position - anchor).dot(initial_right)
    return signf(travel) * clampf((absf(travel) - ORBIT_DEAD_ZONE) / ORBIT_RAMP_DISTANCE, 0.0, 1.0) * ORBIT_LIMIT_DEGREES

func set_offset(offset: Vector3) -> void:
    if not _configured:
        super.set_offset(offset)
        return
    follow_offset = offset
    horizontal_follow = initial_right * offset.dot(initial_right)
    var pivot := target + follow_offset
    camera.global_position = pivot + orbit_vector.rotated(Vector3.UP, deg_to_rad(yaw_degrees))
    camera.look_at(pivot)

func set_test_yaw(value: float) -> void:
    _test_yaw = clampf(value, -ORBIT_LIMIT_DEGREES, ORBIT_LIMIT_DEGREES)
    yaw_degrees = _test_yaw if variant_id in ["B", "C"] else 0.0
    target_yaw_degrees = yaw_degrees
    set_offset(follow_offset)

func clear_test_yaw() -> void:
    _test_yaw = NAN

func update(delta: float, player_position: Vector3, tour: bool, elapsed: float) -> void:
    if frozen:
        return
    var offset := desired_offset(player_position) if enabled else Vector3.ZERO
    if tour:
        offset = initial_right * sin(elapsed * 0.18) * 4.5
    target_yaw_degrees = desired_yaw(player_position) if is_nan(_test_yaw) else _test_yaw
    if variant_id not in ["B", "C"]:
        target_yaw_degrees = 0.0
    yaw_degrees = lerpf(yaw_degrees, target_yaw_degrees, 1.0 - exp(-ORBIT_SMOOTHING * delta))
    set_offset(follow_offset.lerp(offset, 1.0 - exp(-smoothing * delta)))

func supported_pose() -> bool:
    var expected_projection := Camera3D.PROJECTION_ORTHOGONAL if variant_id in ["C", "D"] else Camera3D.PROJECTION_PERSPECTIVE
    var expected_basis := Basis(Vector3.UP, deg_to_rad(yaw_degrees)) * reference_basis
    return camera.projection == expected_projection and camera.global_basis.is_equal_approx(expected_basis) and is_equal_approx(camera.fov, 35.0) and (expected_projection != Camera3D.PROJECTION_ORTHOGONAL or is_equal_approx(camera.size, orthographic_size))

func pose_snapshot() -> Dictionary:
    return {"variant_id": variant_id, "transform": camera.global_transform,
        "projection": camera.projection, "fov": camera.fov, "size": camera.size,
        "follow_offset": follow_offset, "horizontal_follow": horizontal_follow,
        "yaw_degrees": yaw_degrees, "target_yaw_degrees": target_yaw_degrees,
        "test_yaw": _test_yaw}

func restore_pose(value: Dictionary) -> void:
    variant_id = value.variant_id
    follow_offset = value.follow_offset
    horizontal_follow = value.horizontal_follow
    yaw_degrees = value.yaw_degrees
    target_yaw_degrees = value.target_yaw_degrees
    _test_yaw = value.test_yaw
    camera.projection = value.projection
    camera.fov = value.fov
    camera.size = value.size
    camera.global_transform = value.transform

func pose_diagnostics() -> Dictionary:
    var pivot := target + follow_offset
    return {"variant": variant_id, "projection": "orthographic" if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else "perspective",
        "yaw_degrees": yaw_degrees, "target_yaw_degrees": target_yaw_degrees,
        "fov": camera.fov, "orthographic_size": camera.size,
        "orbit_radius": camera.global_position.distance_to(pivot),
        "pitch_degrees": rad_to_deg(asin(camera.global_basis.z.y)),
        "horizontal_follow": [horizontal_follow.x, horizontal_follow.y, horizontal_follow.z],
        "supported": supported_pose()}
