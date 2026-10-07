extends SceneTree
## Parameter validation and panel synchronization; no renderer or everyday settings.
const Settings = preload("res://scripts/ancient_canal/settings.gd")
const Console = preload("res://scripts/ancient_canal/console.gd")
const FIXTURE := "res://build/ancient-canal/console-test.cfg"
var checks := 0
var failures: Array[String] = []

class Demo extends Node:
    var parameter_spec: Dictionary = {}
    var values: Dictionary = {}
    var store: RefCounted
    var status_text := ""
    var route_running := false
    var compare_count := 0
    var screenshot_count := 0
    func set_parameter(key: String, value: Variant) -> bool:
        if not store.field_error(key, value).is_empty():
            return false
        values[key] = store.normalize(key, value)
        if key.begins_with("main_") or key.begins_with("ambient"):
            values.time_preset = "custom"
        return true
    func apply_time_preset(id: String) -> void:
        values.time_preset = id
        values.main_energy = 1.0
    func force_direction(id: String) -> void:
        values.direction = id
    func set_frame(index: int) -> void:
        values.animation_pause = true
        values.animation_frame = index
    func restore_defaults() -> void:
        values = store.default_values()
    func save_settings() -> bool:
        return store.save_settings(values)
    func load_settings() -> bool:
        var loaded: Dictionary = store.load_settings()
        if loaded.is_empty():
            return false
        values = loaded
        return true
    func capture_screenshot() -> void:
        screenshot_count += 1
    func start_route() -> void:
        route_running = true
    func cancel_route() -> void:
        route_running = false
    func toggle_comparison() -> void:
        compare_count += 1

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures.append(label)
        print("CANAL_CONSOLE_FAIL ", label)

func config_for(values: Dictionary) -> ConfigFile:
    var config := ConfigFile.new()
    config.set_value("meta", "schema", 1)
    config.set_value("meta", "scene", "ancient-canal")
    for key in values:
        config.set_value("parameters", key, values[key])
    return config

func settings_checks(store: RefCounted) -> void:
    var defaults: Dictionary = store.default_values()
    check(defaults.size() == store.parameters.size(), "all declared defaults present")
    check(defaults.normal_strength == 0.8 and defaults.shading_mode == "native" and defaults.light_steps == 4, "documented default material")
    check(defaults.time_preset == "dusk", "documented dusk default")
    check(store.path == "user://settings/ancient-canal.cfg", "independent preferences path")
    check(store.validate_values(defaults) == defaults, "defaults valid and canonical")
    for key in store.parameters:
        var definition: Dictionary = store.parameters[key]
        check(store.field_error(key, defaults[key]).is_empty(), "default valid " + key)
        check(not store.field_error(key, null).is_empty(), "null rejected " + key)
        if definition.type in ["float", "int"]:
            for boundary in [definition.min, definition.max]:
                check(store.field_error(key, boundary).is_empty(), "inclusive boundary " + key)
            for invalid in [float(definition.min) - 1.0, float(definition.max) + 1.0, NAN, INF, -INF, true, "1", [1], {"value": 1}]:
                check(not store.field_error(key, invalid).is_empty(), "invalid numeric value rejected " + key)
            if definition.type == "int":
                check(not store.field_error(key, float(definition.min) + 0.5).is_empty(), "fraction rejected " + key)
        elif definition.type == "bool":
            for invalid in [0, 1, "true", [], {}]:
                check(not store.field_error(key, invalid).is_empty(), "coerced bool rejected " + key)
        elif definition.type == "enum":
            for invalid in ["unrecognized", 0, true, [], {}]:
                check(not store.field_error(key, invalid).is_empty(), "unknown option rejected " + key)
        elif definition.type == "color":
            for invalid in [Color(-0.1, 0, 0, 1), Color(NAN, 0, 0, 1), [1, 1, 1], [true, 0, 0, 1], [1, 0, 0, 2], "red"]:
                check(not store.field_error(key, invalid).is_empty(), "invalid color rejected " + key)
    var extra := defaults.duplicate(true)
    extra.injected = "res://arbitrary"
    check(store.validate_values(extra).is_empty(), "unknown injection rejected")
    var missing := defaults.duplicate(true)
    missing.erase("camera_fov")
    check(store.validate_values(missing).is_empty(), "partial settings rejected")
    var malformed := defaults.duplicate(true)
    malformed.main_energy = NAN
    check(store.apply_config(config_for(malformed)).is_empty(), "malformed config rejected before application")
    var wrong_scene := config_for(defaults)
    wrong_scene.set_value("meta", "scene", "frontal")
    check(store.apply_config(wrong_scene).is_empty(), "other scene settings rejected")
    var extra_section := config_for(defaults)
    extra_section.set_value("script", "path", "res://injected.gd")
    check(store.apply_config(extra_section).is_empty(), "extra section rejected")
    var extra_meta := config_for(defaults)
    extra_meta.set_value("meta", "unknown", true)
    check(store.apply_config(extra_meta).is_empty(), "extra metadata rejected")
    check(store.apply_config(config_for(defaults)) == defaults, "complete config canonical round trip")

func panel_checks(store: RefCounted) -> void:
    var demo := Demo.new()
    demo.parameter_spec = store.spec
    demo.values = store.default_values()
    demo.store = store
    root.add_child(demo)
    var panel := Console.new()
    root.add_child(panel)
    panel.configure(demo)
    check(panel.tabs.get_tab_count() == 4, "four Chinese console pages")
    check(panel.fields.size() == store.parameters.size(), "every accepted parameter has a control")
    for key in store.parameters:
        check(panel.fields.has(key), "parameter reachable " + key)
    var baseline := demo.values.duplicate(true)
    panel.refresh()
    panel.refresh()
    check(demo.values == baseline, "refresh never changes live state")
    check(panel.validator.normalize("main_color", demo.values.main_color) is Color, "live color handled as Color")
    panel.fields.normals_enabled.toggled.emit(false)
    check(not demo.values.normals_enabled, "real toggle signal changes normals")
    panel.fields.normal_strength.value_changed.emit(1.2)
    check(demo.values.normal_strength == 1.2, "slider signal changes live value")
    check(is_equal_approx(panel.numeric_spins.normal_strength.value, 1.2), "spin reads actual slider result")
    demo.values.normal_strength = 0.4
    panel.refresh()
    check(is_equal_approx(panel.fields.normal_strength.value, 0.4), "external live changes update control")
    panel.fields.direction.item_selected.emit(4)
    check(demo.values.direction == "right", "direction selector uses existing right sequence")
    panel._step_frame(-1)
    check(demo.values.animation_pause and demo.values.animation_frame == 26, "previous frame wraps and pauses")
    panel._step_frame(1)
    check(demo.values.animation_frame == 0, "next frame wraps sequence")
    panel.fields.main_energy.value_changed.emit(2.0)
    check(demo.values.time_preset == "custom" and "自定义" in panel.state_readout.text, "manual lighting displays custom")
    demo.values.camera_fov = 42.0
    demo.values.dof_near = true
    panel.fields.time_preset.item_selected.emit(0)
    check(demo.values.camera_fov == 42.0 and demo.values.dof_near, "preset action retains lens and focus selection")
    panel.compare_button.pressed.emit()
    check(demo.compare_count == 1, "comparison button dispatches comparison")
    panel.route_button.pressed.emit()
    check(demo.route_running, "route button starts demo")
    panel.route_button.pressed.emit()
    check(not demo.route_running, "route button cancels demo")
    var buttons := panel.find_children("*", "Button", true, false)
    var screenshot_found := false
    for button in buttons:
        if button.text == "保存当前画面":
            button.pressed.emit()
            screenshot_found = true
    check(screenshot_found and demo.screenshot_count == 1, "screenshot action reachable")
    panel.open()
    check(panel.visible, "panel opens")
    panel.close()
    check(not panel.visible, "panel closes")
    panel.free()
    demo.free()

func run() -> void:
    root.size = Vector2i(1920, 1080)
    var store := Settings.new()
    var args := OS.get_cmdline_user_args()
    if "--settings-write" in args:
        store.path = FIXTURE
        var candidate: Dictionary = store.default_values()
        candidate.camera_fov = 42.0
        candidate.main_color = Color(0.8, 0.6, 0.4, 1.0)
        check(store.save_settings(candidate), "isolated preferences written")
    elif "--settings-read" in args:
        store.path = FIXTURE
        var loaded: Dictionary = store.load_settings()
        check(loaded.get("camera_fov", 0.0) == 42.0 and loaded.get("main_color", Color.BLACK) == Color(0.8, 0.6, 0.4, 1.0), "separate process restores scalar and Color")
        DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE))
    else:
        settings_checks(store)
        panel_checks(store)
    print("CANAL_CONSOLE_DONE checks=", checks, " failures=", failures.size())
    quit(0 if failures.is_empty() else 1)
