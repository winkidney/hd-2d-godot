extends SceneTree
## No editor plugin or network access is required to build the static scene.
const Builder = preload("res://scripts/world_builder.gd")

func _initialize() -> void:
    call_deferred("bake")

func bake() -> void:
    var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_layout.json"))
    var world := Builder.new()
    root.add_child(world)
    world.build(data)
    world.mark_owners(world)
    var packed := PackedScene.new()
    var error := packed.pack(world)
    if error == OK:
        error = ResourceSaver.save(packed, "res://scenes/world.tscn")
    if error != OK:
        push_error("Scene bake failed: " + str(error))
        quit(1)
        return
    print("BAKE_PASS children=", world.get_child_count())
    world.queue_free()
    quit(0)
