extends RefCounted
## Local user preferences; this class never modifies project resources.
const Profile = preload("res://scripts/parallax_profile.gd")
const LIMITS = {
    "global_strength": Vector2(0,2),
    "transition_time": Vector2(0,1),
    "horizontal_follow_gain": Vector2(0,0.7),
    "horizontal_dead_zone": Vector2(0,3),
    "smoothing_rate": Vector2(1,10),
    "horizontal_max_offset": Vector2(0,7.5),
    "wind_near": Vector2(-2,2),
    "wind_far": Vector2(-2,2)}
const CAMERA_KEYS = ["horizontal_follow_gain","horizontal_dead_zone","smoothing_rate","horizontal_max_offset"]
var path := "user://settings/parallax.cfg"
var message := ""

func save_settings(controller: RefCounted) -> bool:
    var data: Dictionary = controller.snapshot()
    for key in data:
        message = controller.field_error(key,data[key])
        if message != "": return false
    var config := ConfigFile.new()
    config.set_value("meta","schema",1)
    config.set_value("meta","layout_id",controller.layout_id)
    for key in data: config.set_value("parallax",key,data[key])
    var absolute := ProjectSettings.globalize_path(path)
    var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if error != OK:
        message = "Cannot create preferences directory: " + str(error)
        return false
    var temporary := absolute + ".tmp-" + str(Time.get_ticks_usec())
    var file := FileAccess.open(temporary,FileAccess.WRITE)
    if file == null:
        message = "Cannot create preferences file; previous file kept."
        return false
    file.store_string(config.encode_to_text())
    file.flush()
    var write_error := file.get_error()
    file.close()
    error = DirAccess.rename_absolute(temporary,absolute) if write_error == OK else write_error
    if error != OK: DirAccess.remove_absolute(temporary)
    message = "Saved to " + path if error == OK else "Save failed; previous file kept: " + str(error)
    return error == OK

func load_settings(controller: RefCounted) -> bool:
    if not FileAccess.file_exists(path):
        message = "No saved preferences; project defaults remain active."
        return false
    var file := FileAccess.open(path,FileAccess.READ)
    if file == null:
        message = "Preferences could not be opened."
        return false
    if file.get_length() > 32768:
        file.close()
        message = "Preferences exceed size limit; no changes applied."
        return false
    var text := file.get_as_text()
    file.close()
    var config := ConfigFile.new()
    if config.parse(text) != OK:
        message = "Malformed preferences; file preserved, no changes applied."
        return false
    return apply_config(config,controller)

func apply_config(config: ConfigFile, controller: RefCounted) -> bool:
    if config.get_sections().size() != 2 or not config.has_section("meta") or not config.has_section("parallax"):
        message = "Unexpected preferences sections."
        return false
    var schema = config.get_value("meta","schema",0)
    if config.get_section_keys("meta").size() != 2 or typeof(schema) != TYPE_INT or schema != 1:
        message = "Unsupported preferences schema."
        return false
    var saved_layout = config.get_value("meta","layout_id","")
    if typeof(saved_layout) != TYPE_STRING or saved_layout.length() != 64:
        message = "Invalid layout identity."
        return false
    var keys := config.get_section_keys("parallax")
    if keys.size() != controller.defaults.size():
        message = "Incomplete or unknown preferences fields."
        return false
    var candidate: Dictionary = {}
    for key in keys:
        if not controller.defaults.has(key):
            message = "Unknown preferences field."
            return false
        var value = config.get_value("parallax",key)
        message = controller.field_error(key,value)
        if message != "": return false
        candidate[key] = value
    var layout_changed: bool = saved_layout != controller.layout_id
    if layout_changed:
        for key in CAMERA_KEYS: candidate[key] = controller.defaults[key]
    for key in candidate: controller.change(key,candidate[key])
    message = "Loaded preferences." if not layout_changed else "Layout changed: camera overrides reset; background settings loaded."
    return true
