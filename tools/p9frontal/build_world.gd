extends SceneTree
## Optional baked version of the same runtime builder; no old scene is rewritten.
const Builder = preload("res://scripts/frontal_canal/world_builder.gd")
const LAYOUT := "res://resources/frontal-canal/layout.json"
const OUTPUT := "res://scenes/frontal_canal_world.tscn"

func _initialize() -> void:
    call_deferred("build_and_save")

func build_and_save() -> void:
    var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
    var world := Builder.new()
    root.add_child(world)
    world.build(data)
    world.mark_owners(world)
    var packed := PackedScene.new()
    var error := packed.pack(world)
    if error==OK:
        error=ResourceSaver.save(packed,OUTPUT)
    if error!=OK:
        push_error("Frontal canal bake failed: "+str(error))
        quit(1)
        return
    print("P9R2_WORLD_BAKED ",OUTPUT," children=",world.get_child_count())
    quit(0)
