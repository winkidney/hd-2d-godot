extends SceneTree
## Extract notices from the exact installed engine, not a drifting web copy.
func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute("res://licenses")
    var file := FileAccess.open("res://licenses/GODOT_LICENSE.txt", FileAccess.WRITE)
    if file == null:
        quit(1)
        return
    file.store_string(Engine.get_license_text())
    file.close()
    file = FileAccess.open("res://licenses/GODOT_THIRD_PARTY.txt", FileAccess.WRITE)
    file.store_string("Engine: " + Engine.get_version_info().string + "\n\n")
    for component in Engine.get_copyright_info():
        file.store_string(JSON.stringify(component, "  ") + "\n\n")
    var licenses := Engine.get_license_info()
    for key in licenses:
        file.store_string("\n===== " + str(key) + " =====\n" + str(licenses[key]) + "\n")
    file.close()
    print("ENGINE_NOTICES_EXPORTED")
    quit(0)
