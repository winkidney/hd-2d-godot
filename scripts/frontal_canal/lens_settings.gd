extends RefCounted
## Separate lens files leave the existing F8 preferences schema untouched.
var message := ""

func path_for(id: String) -> String:
    return "user://settings/frontal-lens-"+id+".cfg"

func save_settings(rig: RefCounted, layout_id: String) -> bool:
    var values: Dictionary = rig.lens_snapshot()
    for key in values:
        message = rig.lens_error(key,values[key])
        if not message.is_empty(): return false
    var config := ConfigFile.new()
    config.set_value("meta","schema",1)
    config.set_value("meta","variant",rig.variant_id)
    config.set_value("meta","layout_id",layout_id)
    for key in values: config.set_value("lens",key,values[key])
    var destination := ProjectSettings.globalize_path(path_for(rig.variant_id))
    if DirAccess.make_dir_recursive_absolute(destination.get_base_dir())!=OK:
        message = "Cannot create lens preferences directory."
        return false
    var temporary := destination+".tmp-"+str(Time.get_ticks_usec())
    var file := FileAccess.open(temporary,FileAccess.WRITE)
    if file==null:
        message = "Cannot save lens preferences; previous file kept."
        return false
    file.store_string(config.encode_to_text())
    file.flush()
    var error := file.get_error()
    file.close()
    if error==OK: error = DirAccess.rename_absolute(temporary,destination)
    if error!=OK: DirAccess.remove_absolute(temporary)
    message = "Saved this camera's distance and FOV." if error==OK else "Lens save failed; previous file kept."
    return error==OK

func load_settings(rig: RefCounted, layout_id: String) -> bool:
    var path := path_for(rig.variant_id)
    if not FileAccess.file_exists(path):
        message = "No saved lens settings; current values retained."
        return false
    var file := FileAccess.open(path,FileAccess.READ)
    if file==null:
        message = "Cannot open lens preferences."
        return false
    if file.get_length()>4096:
        message = "Lens preferences exceed size limit; current values retained."
        file.close()
        return false
    var contents := file.get_as_text()
    file.close()
    var config := ConfigFile.new()
    if config.parse(contents)!=OK:
        message = "Malformed lens preferences; current values retained."
        return false
    return apply_config(config,rig,layout_id)

func apply_config(config: ConfigFile, rig: RefCounted, layout_id: String) -> bool:
    message = "Invalid or mismatched lens preferences; current values retained."
    if config.get_sections().size()!=2 or not config.has_section("meta") or not config.has_section("lens"): return false
    if config.get_section_keys("meta").size()!=3 or config.get_section_keys("lens").size()!=2: return false
    for key in ["schema","variant","layout_id"]:
        if not config.has_section_key("meta",key): return false
    for key in ["radius","fov"]:
        if not config.has_section_key("lens",key): return false
    var schema = config.get_value("meta","schema")
    if typeof(schema)!=TYPE_INT or schema!=1: return false
    var saved_variant = config.get_value("meta","variant")
    if typeof(saved_variant)!=TYPE_STRING or saved_variant!=rig.variant_id: return false
    var saved_layout = config.get_value("meta","layout_id")
    if typeof(saved_layout)!=TYPE_STRING or saved_layout!=layout_id: return false
    var candidate: Dictionary = {}
    for key in ["radius","fov"]:
        var value = config.get_value("lens",key)
        if not rig.lens_error(key,value).is_empty(): return false
        candidate[key] = value
    # Validate both fields before applying either one.
    for key in candidate: rig.set_lens(key,candidate[key])
    message = "Loaded this camera's distance and FOV."
    return true
