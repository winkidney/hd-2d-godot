extends CharacterBody3D
## The actor origin is its feet; sprite animation never moves the collider.
const SPEED := 3.2
const GRAVITY := 18.0
var controls_enabled := true
var camera: Camera3D
var sprite: Sprite3D
var animation_clock := 0.0
var facing := 3
var walking := false
var scripted_input := false
var scripted_direction := Vector2.ZERO
var animation := preload("res://scripts/character_animation.gd").new()
var animation_frame := -1
var displayed_facing := -1

func _ready() -> void:
    name = "Traveler"
    floor_snap_length = 0.35
    var shape := CapsuleShape3D.new()
    shape.radius = 0.26
    shape.height = 1.35
    var collider := CollisionShape3D.new()
    collider.shape = shape
    collider.position.y = 0.675
    add_child(collider)
    sprite = make_sprite("res://assets/characters/crescent-traveler/v1/right/atlas.png")
    sprite.hframes = 1
    sprite.vframes = 1
    sprite.pixel_size = 0.009
    sprite.offset = animation.clips[facing].pivot - Vector2(128, 128)
    sprite.offset.x = -sprite.offset.x
    add_child(sprite)
    update_animation()
    var shadow := Sprite3D.new()
    shadow.texture = load("res://assets/sprites/contact_shadow.png")
    shadow.pixel_size = 0.017
    shadow.rotation_degrees.x = -90.0
    shadow.position.y = 0.018
    shadow.shaded = false
    shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(shadow)

static func make_sprite(path: String) -> Sprite3D:
    var visual := Sprite3D.new()
    visual.texture = load(path)
    visual.hframes = 4
    visual.vframes = 4
    visual.pixel_size = 0.045
    visual.offset = Vector2(0.0, 22.0)
    visual.position.y = 0.04
    visual.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    visual.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    visual.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    visual.alpha_scissor_threshold = 0.5
    visual.shaded = true
    visual.double_sided = true
    visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    return visual

func motion_direction() -> Vector3:
    if not controls_enabled:
        return Vector3.ZERO
    if scripted_input:
        var d := scripted_direction.limit_length(1.0)
        return Vector3(d.x, 0.0, d.y)
    var axis := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    if not is_instance_valid(camera):
        return Vector3(axis.x, 0.0, axis.y)
    var right := camera.global_basis.x
    right.y = 0.0
    var back := camera.global_basis.z
    back.y = 0.0
    return (right.normalized() * axis.x + back.normalized() * axis.y).limit_length(1.0)

func _physics_process(delta: float) -> void:
    var move := motion_direction()
    velocity.x = move.x * SPEED
    velocity.z = move.z * SPEED
    if not is_on_floor():
        velocity.y -= GRAVITY * delta
    else:
        velocity.y = 0.0
    move_and_slide()
    if position.y < -5.0:
        position = Vector3(1.2, 0.25, 0.0)
        velocity = Vector3.ZERO
    walking = Vector2(get_real_velocity().x, get_real_velocity().z).length() > 0.08
    if walking:
        var screen_move := Vector2(move.x, move.z)
        if is_instance_valid(camera):
            screen_move = Vector2(move.dot(camera.global_basis.x), move.dot(camera.global_basis.z))
        if absf(screen_move.x) > absf(screen_move.y):
            facing = 3 if screen_move.x > 0.0 else 2
        else:
            facing = 0 if screen_move.y > 0.0 else 1
        animation_clock += delta
    else:
        animation_clock = 0.0
    update_animation()

func update_animation() -> void:
    var index := animation.frame_at(facing, animation_clock, walking)
    if index != animation_frame or facing != displayed_facing:
        sprite.texture = animation.texture_at(facing, index)
        sprite.offset = animation.clips[facing].pivot - Vector2(128, 128)
        sprite.offset.x = -sprite.offset.x
        animation_frame = index
        displayed_facing = facing
