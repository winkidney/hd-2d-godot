extends SceneTree
var failures: Array[String] = []
var checks: Array[Dictionary] = []

func check(condition: bool, label: String) -> void:
    checks.append({"name": label, "passed": condition})
    if not condition: failures.append(label)
    print("CHARACTER_", "PASS " if condition else "FAIL ", label)

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var animation := preload("res://scripts/character_animation.gd").new()
    for direction in range(4):
        var clip: Dictionary = animation.clips[direction]
        check(clip.textures.size() >= 16, "full_stride_" + str(direction))
        var start := 0.0
        for index in range(clip.ends.size()):
            var end: float = clip.ends[index]
            check(animation.frame_at(direction, (start + end) * 0.5, true) == index, "timing_%d_%d" % [direction, index])
            check(animation.frame_at(direction, (start + end) * 0.5 + clip.duration * 3.0, true) == index, "three_loops_%d_%d" % [direction, index])
            check(clip.textures[index].get_size() == Vector2(256, 256), "native_size_%d_%d" % [direction, index])
            start = end
        check(animation.frame_at(direction, clip.duration + 0.001, true) == 0, "loop_wrap_" + str(direction))
        check(animation.frame_at(direction, 9.0, false) == clip.idle_frame, "stationary_hold_" + str(direction))
        check(clip.pivot == Vector2(128, 240), "fixed_foot_pivot_" + str(direction))
    check(animation.clips[3].textures.size() == 27 and absf(animation.clips[3].duration - 1.125) < 0.00001, "approved_A_original_timeline")
    await movement_fixture()
    for path in ["waystation", "reference_scene", "reference_scene_graybox", "frontal_canal"]:
        var scene = load("res://scenes/" + path + ".tscn").instantiate()
        root.add_child(scene)
        await process_frame
        check(not scene.settings_load_attempted, path + "_preferences_ignored")
        var actor = scene.player
        actor.set_physics_process(false)
        check(actor.displayed_facing == 3 and actor.sprite.texture.resource_path != "res://assets/reference-scene/sprites/hero.png", path + "_default_A")
        check(is_equal_approx(actor.sprite.pixel_size, 0.009) and actor.sprite.offset.is_equal_approx(Vector2(0, 112)), path + "_world_scale_and_anchor")
        check(actor.sprite.shaded and actor.sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD and actor.sprite.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, path + "_HD2D_material")
        var collider = actor.get_child(0)
        var initial_transform: Transform3D = collider.transform
        for direction in range(4):
            actor.facing = direction
            actor.walking = true
            actor.animation_clock = 0.4
            actor.update_animation()
            check(actor.displayed_facing == direction and actor.sprite.texture == actor.animation.texture_at(direction, actor.animation_frame), path + "_direction_" + str(direction))
            check(collider.transform == initial_transform, path + "_collider_fixed_" + str(direction))
        scene.queue_free()
        for i in range(4): await process_frame
    var output := "res://build/character-directions/character-test.json"
    var file := FileAccess.open(output, FileAccess.WRITE)
    file.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}, "  ") + "\n")
    print("CHARACTER_TEST_DONE ", checks.size(), " failures=", failures.size())
    quit(0 if failures.is_empty() else 1)

func movement_fixture() -> void:
    var fixture := Node3D.new()
    root.add_child(fixture)
    var floor_body := StaticBody3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(50, 0.2, 50)
    var collision := CollisionShape3D.new()
    collision.shape = shape
    floor_body.add_child(collision)
    floor_body.position.y = -0.1
    fixture.add_child(floor_body)
    var camera := Camera3D.new()
    fixture.add_child(camera)
    camera.position = Vector3(5, 6, 8)
    camera.look_at(Vector3.ZERO)
    var actor := preload("res://scripts/pixel_actor.gd").new()
    actor.position.y = 0.2
    actor.camera = camera
    actor.scripted_input = true
    fixture.add_child(actor)
    for i in range(30): await physics_frame
    var right := camera.global_basis.x
    var back := camera.global_basis.z
    right.y = 0
    back.y = 0
    var directions: Array[Vector3] = [back.normalized(), -back.normalized(), -right.normalized(), right.normalized()]
    for direction in range(4):
        var move := directions[direction]
        var before: Vector3 = actor.position
        actor.scripted_direction = Vector2(move.x, move.z)
        for i in range(12): await physics_frame
        check(actor.walking and actor.facing == direction and actor.displayed_facing == direction, "camera_relative_movement_" + str(direction))
        check(actor.position.distance_to(before) > 0.3, "physical_displacement_" + str(direction))
        actor.scripted_direction = Vector2.ZERO
        for i in range(3): await physics_frame
        check(not actor.walking and actor.facing == direction and actor.animation_clock == 0.0 and actor.animation_frame == actor.animation.clips[direction].idle_frame, "stop_preserves_facing_" + str(direction))
    fixture.queue_free()
    for i in range(4): await process_frame
