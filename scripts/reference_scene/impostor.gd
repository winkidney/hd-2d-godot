extends Node3D
## Seven GPU-rendered views of the same palace. Physics belongs to the world.
const FOLDER := "res://assets/reference-scene/impostors/"
const PERIODS := ["day", "dusk", "night"]
const ANGLES := [-24.0, -16.0, -8.0, 0.0, 8.0, 16.0, 24.0]
const WORLD_SPAN := 13.5
const ANCHOR_V := 0.80
var camera: Camera3D
var source_visual: Node3D
var card := MeshInstance3D.new()
var material := ShaderMaterial.new()
var textures: Dictionary = {}
var available := false
var unavailable_reason := "Palazzo multiview atlases have not been generated."
var active := false
var angle_degrees := 0.0
var target_angle_degrees := 0.0
var frame_position := 3.0
var preset_id := "dusk"

func _exit_tree() -> void:
    # A missing atlas returns before this visual becomes an owned child.
    if is_instance_valid(card) and card.get_parent() == null:
        card.free()

func configure(value: Camera3D, world: Node3D) -> void:
    camera = value
    for node in world.get_children():
        if node is Node3D and str(node.name).begins_with("Palazzo_"):
            source_visual = node
            break
    if source_visual == null:
        unavailable_reason = "The main Palazzo visual is unavailable."
        return
    for id in PERIODS:
        var path: String = FOLDER + "palazzo-" + id + ".png"
        if not ResourceLoader.exists(path): return
        var texture := load(path) as Texture2D
        if texture == null or texture.get_width() != 3584 or texture.get_height() != 512:
            unavailable_reason = "Palazzo atlas dimensions must be 3584 x 512."
            return
        textures[id] = texture
    var mesh := QuadMesh.new()
    mesh.size = Vector2.ONE * WORLD_SPAN
    card.mesh = mesh
    card.name = "PalazzoMultiviewCard"
    card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    material.shader = preload("res://scripts/reference_scene/impostor.gdshader")
    card.material_override = material
    add_child(card)
    available = true
    unavailable_reason = ""
    apply_preset(preset_id)
    card.hide()

func set_active(value: bool) -> bool:
    if value and not available: return false
    active = value
    if is_instance_valid(source_visual): source_visual.visible = not value
    card.visible = value
    if value: update_view(0.0, true)
    return true

func apply_preset(id: String) -> void:
    preset_id = id
    if available: material.set_shader_parameter("atlas", textures[id])

func update_view(delta: float, immediate := false) -> void:
    if not active or not available: return
    # This is the simulated view selection in D's fixed orthographic camera.
    # A real orthographic camera does not change viewing direction on translation.
    var relative := camera.global_position - source_visual.global_position
    target_angle_degrees = clampf(rad_to_deg(atan2(relative.x, relative.z)), -24.0, 24.0)
    angle_degrees = target_angle_degrees if immediate else lerpf(angle_degrees, target_angle_degrees, 1.0 - exp(-8.0 * delta))
    frame_position = (angle_degrees + 24.0) / 8.0
    material.set_shader_parameter("frame_position", frame_position)
    card.global_basis = camera.global_basis
    card.global_position = source_visual.global_position + camera.global_basis.y * ((ANCHOR_V - 0.5) * WORLD_SPAN)

func diagnostics() -> Dictionary:
    return {"available":available, "active":active, "angle_degrees":angle_degrees,
        "target_angle_degrees":target_angle_degrees, "frame_position":frame_position,
        "period":preset_id, "feet_anchor":Vector2(0.5, ANCHOR_V),
        "limitation":"One flat depth plane; no volumetric occlusion or cast shadow."}

func pose_snapshot() -> Dictionary:
    return {"angle_degrees":angle_degrees, "target_angle_degrees":target_angle_degrees,
        "frame_position":frame_position, "card_transform":card.global_transform}

func restore_pose(value: Dictionary) -> void:
    angle_degrees = value.angle_degrees
    target_angle_degrees = value.target_angle_degrees
    frame_position = value.frame_position
    if available:
        material.set_shader_parameter("frame_position", frame_position)
        card.global_transform = value.card_transform
