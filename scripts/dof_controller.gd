extends RefCounted
## Desired switches survive the global FX bypass and time-of-day changes.
const Profile = preload("res://scripts/dof_profile.gd")
var camera: Camera3D
var attributes := CameraAttributesPractical.new()
var profile: Resource
var enabled := true
var near_enabled := true
var far_enabled := true
var master_enabled := true
var mode := "protected"
var focus_depth := 40.0
var manual_depth := 40.0
var anchor := Vector3.ZERO

func configure(value: Camera3D, focus_anchor: Vector3) -> void:
    camera = value
    anchor = focus_anchor
    camera.attributes = attributes
    select_profile("standard")
    focus_depth = depth(anchor)
    manual_depth = focus_depth
    apply()

func depth(point: Vector3) -> float:
    return -(camera.get_camera_transform().affine_inverse() * point).z

func select_profile(id: String) -> void:
    assert(id in ["soft", "standard", "strong"])
    profile = load("res://resources/dof/" + id + ".tres").duplicate()
    assert(profile.valid())
    apply()

func update(delta: float, actor_center: Vector3, tour: bool) -> void:
    var goal := focus_depth
    if tour or mode == "anchor":
        goal = depth(anchor)
    elif mode == "manual":
        goal = manual_depth
    else:
        var actor_depth := depth(actor_center)
        var low := actor_depth - float(profile.far_clear) + 2.0
        var high := actor_depth + float(profile.near_clear) - 2.0
        goal = clampf(focus_depth, low, maxf(low, high))
    focus_depth = lerpf(focus_depth, maxf(goal, 2.0), 1.0 - exp(-float(profile.focus_speed) * delta))
    apply()

func apply() -> void:
    if profile == null:
        return
    attributes.dof_blur_amount = profile.amount
    attributes.dof_blur_near_distance = maxf(0.2, focus_depth - float(profile.near_clear))
    attributes.dof_blur_far_distance = maxf(attributes.dof_blur_near_distance + 0.5, focus_depth + float(profile.far_clear))
    attributes.dof_blur_near_transition = profile.near_transition
    attributes.dof_blur_far_transition = profile.far_transition
    attributes.dof_blur_near_enabled = enabled and near_enabled and master_enabled
    attributes.dof_blur_far_enabled = enabled and far_enabled and master_enabled
