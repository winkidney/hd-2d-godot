extends RefCounted
## One independent transaction: live controllers own camera/profile calculations.
const Camera = preload("res://scripts/frontal_canal/camera.gd")
const Parallax = preload("res://scripts/ancient_canal/parallax.gd")
const SPEC_PATH := "res://resources/ancient-canal/parameters.json"
const SETTINGS_PATH := "user://settings/ancient-canal.cfg"
const SCENE_ID := "ancient-canal"
const MAX_FILE_BYTES := 32768
const BACKGROUND_PRESETS := ["day", "dusk", "night"]
const BROAD_LIGHT_KEYS := ["broad_enabled", "broad_energy", "broad_color", "broad_range", "broad_shadow"]
const CAMERA_KEYS := ["camera_variant", "camera_follow", "camera_distance", "camera_fov"]
const PARALLAX_ALIASES := {"parallax_mode":"mode", "parallax_strength":"global_strength", "parallax_transition":"transition_time"}
const LAYER_IDS = Parallax.IDS
const LEGACY_KEYS := ["normals_enabled", "normal_strength", "normal_flip_y", "shading_mode", "light_steps", "clay", "normal_debug", "silver_specular", "direction", "animation_pause", "animation_frame", "time_preset", "main_yaw", "main_pitch", "main_energy", "main_color", "main_shadow", "scene_shadow", "ambient", "ambient_color", "lantern_energy", "lantern_color", "lantern_range", "lantern_shadow", "test_light_enabled", "test_light_color", "test_light_energy", "test_light_x", "test_light_y", "test_light_z", "test_light_range", "test_light_shadow", "orbit_light", "orbit_speed", "water_flow", "water_wave", "water_reflection", "fog", "bloom", "ssao", "dof_near", "dof_far", "dof_amount", "focus_protection", "focus_distance", "parallax", "camera_follow", "camera_distance", "camera_fov", "camera_yaw", "camera_pitch", "fixed_animation", "fixed_light", "sky_top_color", "sky_horizon_color"]
var spec: Dictionary = {}
var parameters: Dictionary = {}
var path := SETTINGS_PATH
var message := ""
var migrated_v1 := false
var discarded_fields: Array[String] = []
var camera_source: RefCounted = Camera.new()
var parallax_source: RefCounted = Parallax.new()
var controllers_configured := false
var lamp_ids: Dictionary = {}
var background_source: Object

func _init(specification: Dictionary = {}) -> void:
    if specification.is_empty():
        var parsed = JSON.parse_string(FileAccess.get_file_as_string(SPEC_PATH))
        if parsed is Dictionary: spec = parsed
    else:
        spec = specification.duplicate(true)
    parameters = spec.get("parameters", {})

func configure_controllers(rig: RefCounted, profile: RefCounted) -> void:
    camera_source = rig
    parallax_source = profile
    controllers_configured = true

func configure_background(background: Object) -> void:
    background_source = background

func configure_lights(catalog: Array) -> bool:
    var candidate: Dictionary = {}
    for entry in catalog:
        if not entry is Dictionary or not entry.get("id") is String or str(entry.id).is_empty() or candidate.has(entry.id):
            message = "灯具目录包含无效或重复编号。"
            return false
        candidate[entry.id] = true
    lamp_ids = candidate
    return true

func _is_managed(key: String) -> bool:
    return key in CAMERA_KEYS or PARALLAX_ALIASES.has(key) or key in LAYER_IDS

func default_values() -> Dictionary:
    var result: Dictionary = {}
    var lens: Dictionary = camera_source.lens_defaults("F")
    var profile: Dictionary = parallax_source.defaults_snapshot()
    for key in parameters:
        var value = parameters[key].default
        if key == "camera_variant": value = "F"
        elif key == "camera_follow": value = true
        elif key == "camera_distance": value = lens.radius
        elif key == "camera_fov": value = lens.fov
        elif PARALLAX_ALIASES.has(key): value = profile[PARALLAX_ALIASES[key]]
        elif key in LAYER_IDS: value = profile[key]
        result[key] = normalize(key, value)
    return result

func field_error(key: String, value: Variant) -> String:
    if not parameters.has(key): return "未知设置项：" + key
    if key in ["camera_distance", "camera_fov"]:
        var error: String = camera_source.lens_error("radius" if key == "camera_distance" else "fov", value)
        return "镜头参数超出共享控制器允许的范围。" if not error.is_empty() else ""
    if key == "camera_variant":
        return "镜头方案无效。" if not value is String or not Camera.VARIANTS.has(value) else ""
    if PARALLAX_ALIASES.has(key) or key in LAYER_IDS:
        return parallax_source.field_error(PARALLAX_ALIASES.get(key, key), value)
    return _definition_error(parameters[key], value)

func _definition_error(definition: Dictionary, value: Variant) -> String:
    var label: String = definition.label
    match str(definition.type):
        "bool":
            if typeof(value) != TYPE_BOOL: return label + "必须是开关值。"
        "float", "int":
            if typeof(value) not in [TYPE_FLOAT, TYPE_INT]: return label + "必须是数值。"
            var number := float(value)
            if not is_finite(number) or number < float(definition.min) or number > float(definition.max): return label + "超出范围。"
            if definition.type == "int" and number != floor(number): return label + "必须是整数。"
        "enum":
            if typeof(value) != TYPE_STRING: return label + "选项无效。"
            var found := false
            for option in definition.options:
                if value == option.value: found = true; break
            if not found: return label + "选项无效。"
        "color":
            if value is Color:
                if not _valid_color_channels([value.r, value.g, value.b, value.a]): return label + "颜色通道无效。"
            elif value is Array:
                if not _valid_color_channels(value): return label + "颜色通道无效。"
            else: return label + "必须是颜色。"
        _: return "不支持的设置类型。"
    return ""

func _valid_color_channels(channels: Array) -> bool:
    if channels.size() != 4: return false
    for value in channels:
        if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0: return false
    return true

func _normalized(definition: Dictionary, value: Variant) -> Variant:
    match str(definition.type):
        "float": return float(value)
        "int": return int(value)
        "color":
            if value is Color: return value
            return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
    return value

func normalize(key: String, value: Variant) -> Variant:
    if not field_error(key, value).is_empty(): return null
    return _normalized(parameters[key], value)

func lamp_field_error(key: String, value: Variant) -> String:
    var definitions: Dictionary = spec.get("lamp_parameters", {})
    if not definitions.has(key): return "未知单灯参数。"
    return _definition_error(definitions[key], value)

func normalize_lamp(key: String, value: Variant) -> Variant:
    if not lamp_field_error(key, value).is_empty(): return null
    return _normalized(spec.lamp_parameters[key], value)

func validate_values(values: Dictionary) -> Dictionary:
    if values.size() != parameters.size():
        message = "设置项不完整或包含未知设置。"
        return {}
    var candidate: Dictionary = {}
    for key in values:
        if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME]: message = "设置项名称无效。"; return {}
        var name := str(key)
        message = field_error(name, values[key])
        if not message.is_empty(): return {}
        candidate[name] = normalize(name, values[key])
    message = ""
    return candidate

func _parameters_only(values: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    for key in values:
        if not _is_managed(key): result[key] = values[key]
    return result

func _profile_from_values(values: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    for key in PARALLAX_ALIASES: result[PARALLAX_ALIASES[key]] = values[key]
    for key in LAYER_IDS: result[key] = values[key]
    return result

func default_candidate() -> Dictionary:
    var values := default_values()
    return {"schema":2, "parameters":_parameters_only(values), "camera":{"variant":"F", "follow":true},
        "lens_profiles":camera_source.lens_profiles_defaults(), "parallax":parallax_source.defaults_snapshot(), "lamp_overrides":{}, "background_preset":"dusk"}

func candidate_from_values(values: Dictionary, overrides: Dictionary = {}) -> Dictionary:
    var input := values.duplicate(true)
    if controllers_configured:
        var actual_lenses: Dictionary = camera_source.validate_lens_profiles(camera_source.lens_profiles_snapshot())
        var actual_variant: String = camera_source.variant_id
        var actual_profile: Dictionary = parallax_source.snapshot()
        if actual_lenses.is_empty() or not actual_lenses.has(actual_variant):
            message = "共享控制器的镜头状态无效。"; return {}
        var profile_error: String = parallax_source.validate_snapshot(actual_profile)
        if not profile_error.is_empty(): message = profile_error; return {}
        input.camera_variant = actual_variant
        input.camera_follow = bool(camera_source.enabled)
        input.camera_distance = actual_lenses[actual_variant].radius
        input.camera_fov = actual_lenses[actual_variant].fov
        for key in PARALLAX_ALIASES: input[key] = actual_profile[PARALLAX_ALIASES[key]]
        for key in LAYER_IDS: input[key] = actual_profile[key]
    var normalized := validate_values(input)
    if normalized.is_empty(): return {}
    var lenses: Dictionary = camera_source.lens_profiles_snapshot() if controllers_configured else camera_source.lens_profiles_defaults()
    var active: String = camera_source.variant_id if controllers_configured else normalized.camera_variant
    if not controllers_configured:
        lenses[active] = {"radius":normalized.camera_distance, "fov":normalized.camera_fov}
    var profile: Dictionary = parallax_source.snapshot() if controllers_configured else _profile_from_values(normalized)
    var background = background_source.get("profile_id") if is_instance_valid(background_source) else normalized.time_preset
    if not is_instance_valid(background_source) and background not in BACKGROUND_PRESETS: background = "dusk"
    return validate_candidate({"schema":2, "parameters":_parameters_only(normalized),
        "camera":{"variant":active, "follow":bool(camera_source.enabled) if controllers_configured else normalized.camera_follow},
        "lens_profiles":lenses, "parallax":profile, "lamp_overrides":overrides, "background_preset":background})

func validate_candidate(value: Dictionary) -> Dictionary:
    if not _exact_keys(value, ["schema", "parameters", "camera", "lens_profiles", "parallax", "lamp_overrides", "background_preset"]):
        message = "新设置包含未知或缺失部分。"; return {}
    if typeof(value.schema) != TYPE_INT or value.schema != 2:
        message = "设置版本无效。"; return {}
    if not value.background_preset is String or value.background_preset not in BACKGROUND_PRESETS:
        message = "背景时段无效，当前场景保留。"; return {}
    if not value.parameters is Dictionary or not value.camera is Dictionary or not value.lens_profiles is Dictionary or not value.parallax is Dictionary or not value.lamp_overrides is Dictionary:
        message = "设置部分必须是字段集合。"; return {}
    var expected := _parameters_only(default_values())
    if not _exact_keys(value.parameters, expected.keys()):
        message = "非镜头设置不完整或含未知字段。"; return {}
    var normalized: Dictionary = {}
    for key in value.parameters:
        var error := field_error(key, value.parameters[key])
        if not error.is_empty(): message = error; return {}
        normalized[key] = normalize(key, value.parameters[key])
    if not _exact_keys(value.camera, ["variant", "follow"]) or not value.camera.variant is String or not Camera.VARIANTS.has(value.camera.variant) or typeof(value.camera.follow) != TYPE_BOOL:
        message = "镜头方案或跟随设置无效。"; return {}
    var lenses: Dictionary = camera_source.validate_lens_profiles(value.lens_profiles)
    if lenses.is_empty(): message = "三组镜头设置无效，当前镜头保留。"; return {}
    var profile_error: String = parallax_source.validate_snapshot(value.parallax)
    if not profile_error.is_empty(): message = profile_error; return {}
    var overrides: Dictionary = {}
    for id in value.lamp_overrides:
        if not id is String or not lamp_ids.has(id) or not value.lamp_overrides[id] is Dictionary:
            message = "单灯设置含未知灯具或无效内容。"; return {}
        var fields: Dictionary = value.lamp_overrides[id]
        if fields.is_empty(): message = "空单灯设置无效。"; return {}
        var item: Dictionary = {}
        for key in fields:
            if not key is String: message = "单灯参数名称无效。"; return {}
            var error := lamp_field_error(key, fields[key])
            if not error.is_empty(): message = error; return {}
            item[key] = normalize_lamp(key, fields[key])
        overrides[id] = item
    # This function stages values only; controller and scene state are untouched.
    return {"schema":2, "parameters":normalized, "camera":value.camera.duplicate(), "lens_profiles":lenses,
        "parallax":value.parallax.duplicate(true), "lamp_overrides":overrides, "background_preset":value.background_preset}

func candidate_to_values(candidate: Dictionary) -> Dictionary:
    var previous_message := message
    var value := validate_candidate(candidate)
    if value.is_empty(): return {}
    message = previous_message
    var result: Dictionary = value.parameters.duplicate(true)
    result["camera_variant"] = value.camera.variant
    result["camera_follow"] = value.camera.follow
    result["camera_distance"] = value.lens_profiles[value.camera.variant].radius
    result["camera_fov"] = value.lens_profiles[value.camera.variant].fov
    for key in PARALLAX_ALIASES: result[key] = value.parallax[PARALLAX_ALIASES[key]]
    for key in LAYER_IDS: result[key] = value.parallax[key]
    return result

func _exact_keys(value: Dictionary, expected: Array) -> bool:
    if value.size() != expected.size(): return false
    for key in expected:
        if not value.has(key): return false
    return true

func config_for(candidate: Dictionary) -> ConfigFile:
    var config := ConfigFile.new()
    config.set_value("meta", "schema", 2)
    config.set_value("meta", "scene", SCENE_ID)
    config.set_value("meta", "background_preset", candidate.background_preset)
    for key in candidate.parameters: config.set_value("parameters", key, candidate.parameters[key])
    for key in candidate.camera: config.set_value("camera", key, candidate.camera[key])
    for id in Camera.VARIANTS:
        for key in candidate.lens_profiles[id]: config.set_value("lens_" + id, key, candidate.lens_profiles[id][key])
    for key in candidate.parallax: config.set_value("parallax", key, candidate.parallax[key])
    config.set_value("lamps", "overrides", candidate.lamp_overrides)
    return config

func save_settings(values: Dictionary, lamp_overrides: Dictionary = {}) -> bool:
    var candidate := candidate_from_values(values, lamp_overrides)
    if candidate.is_empty(): return false
    return save_candidate(candidate)

func save_candidate(value: Dictionary) -> bool:
    var candidate := validate_candidate(value)
    if candidate.is_empty(): return false
    var config := config_for(candidate)
    var destination := ProjectSettings.globalize_path(path)
    if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK:
        message = "无法创建设置目录。"; return false
    var temporary := destination + ".tmp-" + str(Time.get_ticks_usec())
    var file := FileAccess.open(temporary, FileAccess.WRITE)
    if file == null: message = "无法写入设置，原文件保留。"; return false
    file.store_string(config.encode_to_text())
    file.flush()
    var error := file.get_error()
    file.close()
    if error == OK: error = DirAccess.rename_absolute(temporary, destination)
    if error != OK: DirAccess.remove_absolute(temporary)
    message = "江南河街设置已保存，三组镜头与单灯修改一同保留。" if error == OK else "设置保存失败，原文件保留。"
    if error == OK: migrated_v1 = false
    return error == OK

func load_settings() -> Dictionary:
    migrated_v1 = false
    discarded_fields.clear()
    if not FileAccess.file_exists(path): message = "尚未保存设置，继续使用当前参数。"; return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null: message = "无法打开设置文件。"; return {}
    if file.get_length() > MAX_FILE_BYTES:
        file.close(); message = "设置文件过大，当前参数保留。"; return {}
    var contents := file.get_as_text()
    file.close()
    var config := ConfigFile.new()
    if config.parse(contents) != OK: message = "设置文件格式错误，当前参数保留。"; return {}
    return apply_config(config)

func _section(config: ConfigFile, name: String) -> Dictionary:
    var result: Dictionary = {}
    for key in config.get_section_keys(name): result[key] = config.get_value(name, key)
    return result

func apply_config(config: ConfigFile) -> Dictionary:
    message = "设置文件不属于当前演示，当前参数保留。"
    if not config.has_section("meta"): return {}
    var schema = config.get_value("meta", "schema")
    var scene_id = config.get_value("meta", "scene")
    if typeof(schema) != TYPE_INT or not scene_id is String or scene_id != SCENE_ID: return {}
    if schema == 1:
        if not _exact_keys(_section(config, "meta"), ["schema", "scene"]): return {}
        return _migrate_v1(config)
    if schema != 2: return {}
    if not _exact_keys(_section(config, "meta"), ["schema", "scene", "background_preset"]): return {}
    var sections := config.get_sections()
    var required := ["meta", "parameters", "camera", "lens_F", "lens_W", "lens_O", "parallax", "lamps"]
    if sections.size() != required.size(): return {}
    for section in required:
        if section not in sections: return {}
    if not _exact_keys(_section(config, "lamps"), ["overrides"]): return {}
    var lenses: Dictionary = {}
    for id in Camera.VARIANTS: lenses[id] = _section(config, "lens_" + id)
    var saved_parameters := _section(config, "parameters")
    var previous_keys: Array = _parameters_only(default_values()).keys().filter(func(key): return key not in BROAD_LIGHT_KEYS)
    var old_lighting_config := _exact_keys(saved_parameters, previous_keys)
    if old_lighting_config:
        # Only the complete previous schema-2 set qualifies for this additive
        # upgrade. Partial current files still fail strict validation below.
        var defaults := default_values()
        for key in BROAD_LIGHT_KEYS: saved_parameters[key] = defaults[key]
        saved_parameters.broad_energy = {"day":.1,"dusk":1.7,"night":2.6}.get(saved_parameters.get("time_preset","dusk"),defaults.broad_energy)
    var candidate := validate_candidate({"schema":2, "parameters":saved_parameters, "camera":_section(config, "camera"),
        "lens_profiles":lenses, "parallax":_section(config, "parallax"), "lamp_overrides":config.get_value("lamps", "overrides"),
        "background_preset":config.get_value("meta", "background_preset")})
    if not candidate.is_empty(): message = "江南河街设置已载入，等待场景统一应用。"
    if not candidate.is_empty() and old_lighting_config:
        message = "原设置已在内存载入，新大范围灯使用默认值；手动保存前保留原文件。"
    return candidate

func _migrate_v1(config: ConfigFile) -> Dictionary:
    if config.get_sections().size() != 2 or not config.has_section("parameters"): return {}
    var old := _section(config, "parameters")
    for key in old:
        if key not in LEGACY_KEYS: message = "旧设置含未知字段，当前参数保留。"; return {}
    var candidate := default_candidate()
    var kept := 0
    discarded_fields.clear()
    for key in old:
        if key.begins_with("camera_") or key == "parallax": continue
        if not parameters.has(key) or not field_error(key, old[key]).is_empty():
            discarded_fields.append(key)
            continue
        candidate.parameters[key] = normalize(key, old[key])
        kept += 1
    if candidate.parameters.time_preset in BACKGROUND_PRESETS: candidate.background_preset = candidate.parameters.time_preset
    var validated := validate_candidate(candidate)
    if validated.is_empty(): return {}
    migrated_v1 = true
    message = "旧设置仅在内存迁移：保留 %d 项有效非镜头设置；镜头恢复 F（30m / 35°），远景恢复自然模式。原文件将在手动保存前保留。" % kept
    if not discarded_fields.is_empty(): message += " 无效字段已使用默认值：" + "、".join(discarded_fields) + "。"
    return validated
