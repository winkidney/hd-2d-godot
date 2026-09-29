extends "res://scripts/reference_scene/experiment_parallax.gd"
## Same projection equation, separate frontal profiles and longer follow range.
const FRONTAL_IDS := ["F", "W", "O"]
const CAMERA_RANGES := {"horizontal_follow_gain":Vector2(0.0,1.2),
    "horizontal_max_offset":Vector2(0.0,26.0)}

func configure(value: Camera3D, camera_rig: RefCounted, backdrop: Node3D, layout_text: String) -> void:
    super.configure(value, camera_rig, backdrop, layout_text)
    variant_id = "F"
    variant_settings.clear()
    variant_defaults.clear()
    defaults = snapshot().duplicate(true)
    for id in FRONTAL_IDS:
        variant_settings[id] = defaults.duplicate(true)
        variant_defaults[id] = defaults.duplicate(true)

func field_error(key: String, value: Variant) -> String:
    if not CAMERA_RANGES.has(key):
        return super.field_error(key, value)
    if typeof(value) not in [TYPE_FLOAT, TYPE_INT]:
        return "A number is required."
    var limits: Vector2 = CAMERA_RANGES[key]
    if not is_finite(float(value)) or float(value) < limits.x or float(value) > limits.y:
        return "Parameter outside the frontal scene range."
    return ""

func warnings() -> String:
    var message := super.warnings()
    var explanation := "Translation multiplier only; orbit remains natural. Near-field buildings and all collisions stay fixed."
    return explanation if message.is_empty() else message + "\n" + explanation
