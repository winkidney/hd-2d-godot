extends RefCounted
## Screen-X compensation shared by the Frontal and Jiangnan controllers.
## Each update starts from the authored world transform, never yesterday's offset.

static func context(camera: Camera3D, horizontal_follow: Vector3) -> Dictionary:
    var actual := camera.get_camera_transform()
    var virtual := actual
    virtual.origin -= horizontal_follow
    return {"actual_inverse": actual.affine_inverse(),
        "virtual_inverse": virtual.affine_inverse(),
        "focal": camera.get_camera_projection().x.x * camera.get_viewport().get_visible_rect().size.x * 0.5,
        "perspective": camera.projection == Camera3D.PROJECTION_PERSPECTIVE,
        "near": camera.near, "right": camera.global_basis.x}

static func projected_x(point: Vector3, focal: float, perspective: bool) -> float:
    return focal * point.x / maxf(-point.z, 0.00001) if perspective else focal * point.x

static func sample(view: Dictionary, world_point: Vector3, ratio: float) -> Dictionary:
    var actual: Vector3 = view.actual_inverse * world_point
    var virtual: Vector3 = view.virtual_inverse * world_point
    var focal := float(view.focal)
    var perspective := bool(view.perspective)
    var valid := -actual.z > float(view.near) and -virtual.z > float(view.near) and absf(focal) > 0.001
    var natural_x := projected_x(actual, focal, perspective)
    var virtual_x := projected_x(virtual, focal, perspective)
    var expected_x := virtual_x + ratio * (natural_x - virtual_x)
    var offset := Vector3.ZERO
    if valid:
        var metres_per_pixel := -actual.z / focal if perspective else 1.0 / focal
        offset = view.right * (expected_x - natural_x) * metres_per_pixel
    return {"natural_x": natural_x, "virtual_x": virtual_x, "expected_x": expected_x,
        "offset_world": offset, "valid": valid, "depth": -actual.z,
        "focal": focal, "perspective": perspective}

static func result_x(view: Dictionary, world_point: Vector3) -> float:
    return projected_x(view.actual_inverse * world_point, float(view.focal), bool(view.perspective))
