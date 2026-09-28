extends SceneTree
const Builder = preload("res://scripts/reference_scene/world_builder.gd")
func _initialize() -> void:
    call_deferred("bake")

func bake() -> void:
    var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/reference-scene/layout.json"))
    for gray in [true,false]:
        var world := Builder.new()
        world.graybox=gray
        root.add_child(world)
        world.build(layout)
        world.mark_owners(world)
        var packed := PackedScene.new()
        var error := packed.pack(world)
        var path := "res://scenes/reference_scene_gray_world.tscn" if gray else "res://scenes/reference_scene_world.tscn"
        if error == OK: error=ResourceSaver.save(packed,path)
        if error != OK:
            push_error("P9 bake failed: "+str(error))
            quit(1)
            return
        print("P9_BAKED ",path," nodes=",world.get_child_count())
        world.queue_free()
        for frame in range(3): await process_frame
    quit(0)
