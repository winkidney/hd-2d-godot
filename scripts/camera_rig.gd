extends RefCounted
## A single final pose. Translation never silently changes orientation or FOV.
var camera: Camera3D
var home: Vector3
var target: Vector3
var anchor: Vector3
var gain := 0.45
var dead_zone := 0.8
var smoothing := 4.0
var max_offset := Vector2(7.5, 4.5)
var horizontal_gain := 0.45
var horizontal_dead_zone := 0.8
var enabled := true
var frozen := false

func configure(value: Camera3D, config: Dictionary, player_spawn: Vector3) -> void:
    camera = value
    home = vec(config.position)
    target = vec(config.target)
    anchor = player_spawn
    gain = float(config.follow_gain)
    dead_zone = float(config.dead_zone)
    smoothing = float(config.smoothing)
    max_offset = Vector2(config.follow_max[0], config.follow_max[1])
    camera.fov = float(config.fov)
    camera.far = float(config.far)
    horizontal_gain = gain
    horizontal_dead_zone = dead_zone
    set_offset(Vector3.ZERO)

static func vec(data: Array) -> Vector3:
    return Vector3(data[0], data[1], data[2])

func horizontal_right() -> Vector3:
    var right := camera.global_basis.x
    right.y = 0.0
    return right.normalized()

func desired_offset(player_position: Vector3) -> Vector3:
    var delta := player_position - anchor
    var right := horizontal_right()
    var back := Vector3(-right.z, 0, right.x)
    var x := signf(delta.dot(right)) * maxf(absf(delta.dot(right)) - horizontal_dead_zone, 0.0) * horizontal_gain
    var z := signf(delta.dot(back)) * maxf(absf(delta.dot(back)) - dead_zone, 0.0) * gain
    return right * clampf(x, -max_offset.x, max_offset.x) + back * clampf(z, -max_offset.y, max_offset.y)

func set_offset(offset: Vector3) -> void:
    camera.global_position = home + offset
    camera.look_at(target + offset)

func update(delta: float, player_position: Vector3, tour: bool, elapsed: float) -> void:
    if frozen:
        return
    var offset := desired_offset(player_position) if enabled else Vector3.ZERO
    if tour:
        offset = horizontal_right() * sin(elapsed * 0.18) * 4.5
    var current := camera.global_position - home
    set_offset(current.lerp(offset, 1.0 - exp(-smoothing * delta)))
