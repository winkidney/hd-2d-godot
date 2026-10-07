extends SceneTree
## Storage and Chinese controls exercise the real camera/profile and local lights.
const Settings = preload("res://scripts/ancient_canal/settings.gd")
const Console = preload("res://scripts/ancient_canal/console.gd")
const Camera = preload("res://scripts/frontal_canal/camera.gd")
const Parallax = preload("res://scripts/ancient_canal/parallax.gd")
const FIXTURE := "user://settings/ancient-canal-contract.cfg"
const REPORT := "res://build/ancient-canal-camera/settings-contract.json"
var checks: Array[Dictionary] = []
var failures: Array[String] = []

class BackgroundState extends RefCounted:
    var profile_id := "dusk"

class Demo extends Node:
    var parameter_spec: Dictionary
    var values: Dictionary
    var store: RefCounted
    var rig: RefCounted
    var parallax: RefCounted
    var camera: Camera3D
    var farfield: RefCounted
    var selected_lamp_id := "streetlamp_left_front"
    var lamp_overrides: Dictionary = {}
    var lamps: Dictionary = {}
    var isolation: Dictionary = {}
    var status_text := ""
    var route_running := false
    var comparison_count := 0
    func light_catalog() -> Array:
        return [{"id":"lantern_0", "label":"酒肆灯笼", "group":"lantern"}, {"id":"streetlamp_left_front", "label":"桥头路灯", "group":"streetlamp"}]
    func set_parameter(key: String, value: Variant) -> bool:
        if not store.field_error(key, value).is_empty(): return false
        values[key] = store.normalize(key, value)
        if key == "camera_follow": rig.enabled = value
        elif Settings.PARALLAX_ALIASES.has(key) or key in Settings.LAYER_IDS:
            parallax.change(Settings.PARALLAX_ALIASES.get(key, key), value)
        return true
    func select_variant(id: String) -> bool:
        return rig.select_variant(id, Vector3.ZERO)
    func set_lens(key: String, value: Variant) -> bool:
        return rig.set_lens(key, value)
    func reset_lens() -> void: rig.reset_lens()
    func reset_parallax() -> void: parallax.reset_all()
    func selected_lamp_values() -> Dictionary:
        var lamp: OmniLight3D = lamps[selected_lamp_id]
        return {"enabled":lamp.visible, "color":lamp.light_color, "energy":lamp.light_energy, "range":lamp.omni_range, "shadow":lamp.shadow_enabled}
    func select_lamp(id: String) -> bool:
        if not lamps.has(id): return false
        selected_lamp_id = id
        return true
    func set_selected_lamp(key: String, value: Variant) -> bool:
        if not store.lamp_field_error(key, value).is_empty(): return false
        if not lamp_overrides.has(selected_lamp_id): lamp_overrides[selected_lamp_id] = {}
        lamp_overrides[selected_lamp_id][key] = store.normalize_lamp(key, value)
        var lamp: OmniLight3D = lamps[selected_lamp_id]
        match key:
            "enabled": lamp.visible = value
            "color": lamp.light_color = value
            "energy": lamp.light_energy = value
            "range": lamp.omni_range = value
            "shadow": lamp.shadow_enabled = value
        return true
    func isolate_selected_lamp() -> void:
        if not isolation.is_empty(): return
        for id in lamps:
            isolation[id] = lamps[id].visible
            lamps[id].visible = id == selected_lamp_id
    func restore_lamp_isolation() -> void:
        for id in isolation: lamps[id].visible = isolation[id]
        isolation.clear()
    func apply_time_preset(id: String) -> void: values.time_preset = id
    func force_direction(id: String) -> void: values.direction = id
    func set_frame(index: int) -> void: values.animation_frame = index; values.animation_pause = true
    func toggle_comparison() -> void: comparison_count += 1
    func restore_defaults() -> void: values = store.default_values()
    func save_settings() -> bool: return store.save_settings(values, lamp_overrides)
    func load_settings() -> bool: return not store.load_settings().is_empty()
    func capture_screenshot() -> void: pass
    func start_route() -> void: route_running = true
    func cancel_route() -> void: route_running = false

func _initialize() -> void:
    call_deferred("run")

func check(passed: bool, scope: String) -> void:
    checks.append({"passed":passed, "scope":scope})
    if not passed:
        failures.append(scope)
        print("SETTINGS_CONTRACT_FAIL ", scope)

func make_demo() -> Node:
    var demo := Demo.new()
    root.add_child(demo)
    demo.camera = Camera3D.new()
    demo.add_child(demo.camera)
    demo.rig = Camera.new()
    demo.rig.configure(demo.camera, {"target":[0,1,0]}, Vector3.ZERO)
    demo.parallax = Parallax.new()
    demo.store = Settings.new()
    demo.store.configure_controllers(demo.rig, demo.parallax)
    demo.farfield = BackgroundState.new()
    demo.store.configure_background(demo.farfield)
    demo.store.configure_lights(demo.light_catalog())
    demo.store.path = FIXTURE
    demo.parameter_spec = demo.store.spec
    demo.values = demo.store.default_values()
    for item in demo.light_catalog():
        var lamp := OmniLight3D.new()
        lamp.light_energy = 0.8
        lamp.omni_range = 4.0
        lamp.light_color = Color(1,0.68,0.38,1)
        demo.add_child(lamp)
        demo.lamps[item.id] = lamp
    return demo

func legacy_config(values: Dictionary) -> ConfigFile:
    var config := ConfigFile.new()
    config.set_value("meta", "schema", 1)
    config.set_value("meta", "scene", "ancient-canal")
    for key in Settings.LEGACY_KEYS:
        var value = values.get(key, 1.0)
        if key == "camera_yaw": value = 10.0
        elif key == "camera_pitch": value = 20.0
        config.set_value("parameters", key, value)
    return config

func write_fixture(config: ConfigFile) -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE.get_base_dir()))
    var file := FileAccess.open(FIXTURE, FileAccess.WRITE)
    file.store_string(config.encode_to_text())
    file.flush()
    file.close()

func storage_checks(demo: Node) -> void:
    var store: RefCounted = demo.store
    var defaults: Dictionary = store.default_values()
    check(defaults.size() == 73 and defaults.size() == store.parameters.size(), "all 73 UI defaults present")
    check(defaults.camera_distance == demo.rig.lens_defaults("F").radius and defaults.camera_fov == demo.rig.lens_defaults("F").fov, "default lens derives from shared F controller")
    check(defaults.parallax_mode == "natural" and defaults.far_clouds == demo.parallax.defaults_snapshot().far_clouds, "profile defaults derive from actual six-layer controller")
    check(not defaults.test_light_enabled and defaults.streetlamp_energy == 0.8 and defaults.streetlamp_range == 4.0, "normal scene keeps test lamp off and new lamp defaults")
    check(not defaults.has("camera_yaw") and not defaults.has("camera_pitch") and not defaults.has("parallax"), "obsolete free-angle and one-layer controls removed")
    for key in store.parameters:
        check(store.field_error(key, defaults[key]).is_empty() and not store.field_error(key, null).is_empty(), "strict type validation " + key)
    var previous_lenses: Dictionary = demo.rig.lens_profiles_snapshot()
    var bad_lenses: Dictionary = previous_lenses.duplicate(true)
    bad_lenses.W.fov = NAN
    check(not demo.rig.restore_lens_profiles(bad_lenses, "O", Vector3.ZERO) and demo.rig.lens_profiles_snapshot() == previous_lenses and demo.rig.variant_id == "F", "invalid inactive lens rejects entire restore without pose mutation")
    var old := legacy_config(defaults)
    old.set_value("parameters", "camera_distance", 38.0)
    old.set_value("parameters", "camera_fov", 55.0)
    old.set_value("parameters", "camera_follow", false)
    old.set_value("parameters", "camera_yaw", 31.0)
    old.set_value("parameters", "parallax", 0.25)
    old.set_value("parameters", "normal_strength", 1.15)
    old.set_value("parameters", "main_color", Color(0.8,0.6,0.4,1))
    old.set_value("parameters", "main_energy", NAN)
    old.set_value("parameters", "dof_near", true)
    old.set_value("parameters", "time_preset", "night")
    write_fixture(old)
    var before := FileAccess.get_sha256(FIXTURE)
    var migrated: Dictionary = store.load_settings()
    var mapped: Dictionary = store.candidate_to_values(migrated)
    var migration_message: String = store.message
    demo.values = mapped.duplicate(true)
    check(mapped.keys().all(func(key): return typeof(key)==TYPE_STRING), "migrated candidate exposes canonical String UI keys and can be saved again")
    var named_keys: Dictionary = mapped.duplicate(true)
    named_keys.erase("camera_variant")
    named_keys[&"camera_variant"] = "F"
    check(not store.validate_values(named_keys).is_empty(), "engine StringName keys normalize to known canonical String keys")
    check(store.migrated_v1 and mapped.camera_variant == "F" and mapped.camera_follow and mapped.camera_distance == 30.0 and mapped.camera_fov == 35.0, "v1 always resets every camera setting to canonical F")
    check(migrated.parallax == demo.parallax.defaults_snapshot(), "old scalar parallax discarded for natural six-layer default")
    check(migrated.background_preset == "night", "valid v1 lighting preset explicitly migrates matching background metadata")
    check(mapped.normal_strength == 1.15 and mapped.main_color == Color(0.8,0.6,0.4,1) and mapped.dof_near, "migration preserves valid material Color and independent DOF")
    check(mapped.main_energy == defaults.main_energy and "main_energy" in store.discarded_fields, "invalid noncamera migration field defaults with visible explanation")
    check("原文件" in migration_message and "内存" in migration_message, "migration explains no automatic file replacement")
    demo.rig.select_variant("W", Vector3.ZERO)
    demo.rig.set_lens("radius", 24.5)
    demo.rig.set_lens("fov", 47.0)
    demo.parallax.change("far_clouds", 0.4)
    check(FileAccess.get_sha256(FIXTURE) == before, "load variant switch and edits preserve v1 exact file bytes")
    var rig_before: Dictionary = demo.rig.pose_snapshot()
    var profile_before: Dictionary = demo.parallax.snapshot()
    var candidate: Dictionary = store.default_candidate()
    var malformed: Dictionary = candidate.duplicate(true)
    malformed.background_preset = "custom"
    check(store.validate_candidate(malformed).is_empty(), "custom lighting label cannot substitute for background time metadata")
    malformed = candidate.duplicate(true)
    malformed.erase("background_preset")
    check(store.validate_candidate(malformed).is_empty(), "missing background metadata rejects the complete candidate")
    malformed = candidate.duplicate(true)
    malformed.lens_profiles.O.radius = INF
    check(store.validate_candidate(malformed).is_empty(), "malformed inactive O profile rejects candidate")
    malformed = candidate.duplicate(true)
    malformed.parallax.far_clouds = 3.0
    check(store.validate_candidate(malformed).is_empty(), "out-of-range sixth layer rejects entire candidate")
    malformed = candidate.duplicate(true)
    malformed.parallax.erase("near_hills")
    check(store.validate_candidate(malformed).is_empty(), "missing layer rejects whole candidate")
    malformed = candidate.duplicate(true)
    malformed.camera.follow = 1
    check(store.validate_candidate(malformed).is_empty(), "coerced follow bool rejected")
    malformed = candidate.duplicate(true)
    malformed.lamp_overrides = {"unknown_lamp":{"energy":1.0}}
    check(store.validate_candidate(malformed).is_empty(), "unknown lamp ID rejected")
    malformed = candidate.duplicate(true)
    malformed.lamp_overrides = {"lantern_0":{"script":"res://injected.gd"}}
    check(store.validate_candidate(malformed).is_empty(), "unknown lamp property rejected")
    for invalid in [NAN, INF, -1.0, 9.0, true, "2"]:
        malformed = candidate.duplicate(true)
        malformed.lamp_overrides = {"lantern_0":{"energy":invalid}}
        check(store.validate_candidate(malformed).is_empty(), "invalid single lamp energy rejected " + str(invalid))
    check(demo.camera.global_transform == rig_before.transform and demo.rig.variant_id == rig_before.variant_id and demo.rig.lens_profiles_snapshot() == rig_before.lens_profiles and demo.rig.follow_offset == rig_before.follow_offset and demo.rig.yaw_degrees == rig_before.yaw_degrees and demo.parallax.snapshot() == profile_before and FileAccess.get_sha256(FIXTURE) == before, "candidate rejection never mutates controllers or original file")
    demo.rig.select_variant("O", Vector3.ZERO)
    demo.rig.set_lens("radius", 32.5)
    demo.rig.set_lens("fov", 39.0)
    demo.values.main_color = Color(0.7,0.5,0.3,1)
    demo.values.time_preset = "custom"
    demo.farfield.profile_id = "night"
    demo.lamp_overrides = {"streetlamp_left_front":{"color":Color(1,0.7,0.4,1), "energy":1.25, "shadow":true}}
    demo.parallax.change("mode", "natural")
    check(demo.save_settings(), "explicit save writes complete v2 transaction")
    check(FileAccess.get_sha256(FIXTURE) != before and not store.migrated_v1, "only explicit save replaces old CFG with v2")
    var loaded: Dictionary = store.load_settings()
    check(loaded.camera.variant == "O" and loaded.lens_profiles.W.radius == 24.5 and loaded.lens_profiles.W.fov == 47.0 and loaded.lens_profiles.O.radius == 32.5 and loaded.lens_profiles.O.fov == 39.0, "all independent inactive and active profiles survive file roundtrip")
    check(loaded.parallax.mode == "natural" and loaded.parallax.far_clouds == 0.4 and demo.parallax.effective("far_clouds") == 1.0, "natural mode persists artistic requested gain and retains effective 1")
    check(loaded.lamp_overrides == demo.lamp_overrides and not loaded.has("selected_lamp_id") and not loaded.has("isolation"), "single-lamp overrides persist without transient selection or isolation")
    check(loaded.background_preset == "night" and loaded.parameters.time_preset == "custom", "actual night background persists independently from custom lighting label")
    var older_v2: ConfigFile = store.config_for(loaded)
    for key in Settings.BROAD_LIGHT_KEYS: older_v2.erase_section_key("parameters",key)
    write_fixture(older_v2)
    var older_v2_sha := FileAccess.get_sha256(FIXTURE)
    var upgraded_v2: Dictionary = store.load_settings()
    check(not upgraded_v2.is_empty() and upgraded_v2.camera==loaded.camera and upgraded_v2.lens_profiles==loaded.lens_profiles and upgraded_v2.parallax==loaded.parallax and upgraded_v2.lamp_overrides==loaded.lamp_overrides,"previous_complete_v2_preserves_controllers_and_single_lights")
    var previous_parameters: Dictionary = upgraded_v2.parameters.duplicate(true)
    for key in Settings.BROAD_LIGHT_KEYS: previous_parameters.erase(key)
    var original_parameters: Dictionary = loaded.parameters.duplicate(true)
    for key in Settings.BROAD_LIGHT_KEYS: original_parameters.erase(key)
    check(previous_parameters==original_parameters and upgraded_v2.parameters.broad_range==7.0 and upgraded_v2.parameters.broad_enabled,"previous_v2_preserves_all_old_fields_and_defaults_new_lights")
    check(FileAccess.get_sha256(FIXTURE)==older_v2_sha,"previous_v2_load_never_rewrites_local_settings")
    var incomplete_new: ConfigFile = store.config_for(loaded)
    incomplete_new.erase_section_key("parameters","broad_shadow")
    check(store.apply_config(incomplete_new).is_empty(),"partial_new_lighting_settings_still_rejected")
    older_v2.set_value("parameters","time_preset","night")
    check(store.apply_config(older_v2).parameters.broad_energy==2.6,"previous_v2_night_defaults_new_light_intensity")
    check(store.save_candidate(loaded),"explicit_save_writes_complete_current_lighting_settings")
    var exported: Dictionary = store.candidate_from_values(demo.values, demo.lamp_overrides)
    check(exported.lens_profiles == demo.rig.lens_profiles_snapshot() and exported.camera.variant == "O", "save reads rig authority despite stale UI aliases")
    var stale_aliases: Dictionary = demo.values.duplicate(true)
    stale_aliases.camera_distance = -99.0
    stale_aliases.camera_fov = NAN
    stale_aliases.parallax_strength = NAN
    check(store.candidate_from_values(stale_aliases, demo.lamp_overrides) == exported, "invalid display aliases cannot override or block valid controller-authoritative save")
    demo.rig.select_variant("F", Vector3.ZERO)
    demo.rig.set_lens("radius", 19.0)
    demo.parallax.change("mode", "artistic")
    demo.parallax.change("far_clouds", 1.4)
    demo.farfield.profile_id = "day"
    check(store.save_candidate(exported) and store.load_settings() == exported, "explicit captured candidate save ignores temporary preview controller changes")
    check(demo.rig.variant_id == "F" and demo.rig.lens_snapshot().radius == 19.0 and demo.parallax.snapshot().far_clouds == 1.4 and demo.farfield.profile_id == "day", "saving captured settings never applies them to preview nodes")
    demo.rig.restore_lens_profiles(exported.lens_profiles, exported.camera.variant, Vector3.ZERO)
    demo.parallax.apply_snapshot(exported.parallax)
    demo.farfield.profile_id = exported.background_preset
    var invalid_config: ConfigFile = store.config_for(exported)
    invalid_config.set_value("camera", "arbitrary", true)
    check(store.apply_config(invalid_config).is_empty(), "CFG section unknown property rejected")
    invalid_config = store.config_for(exported)
    invalid_config.set_value("injected", "path", "res://injected.gd")
    check(store.apply_config(invalid_config).is_empty(), "CFG extra section rejected")
    invalid_config = store.config_for(exported)
    invalid_config.set_value("meta", "background_preset", "custom")
    check(store.apply_config(invalid_config).is_empty(), "invalid CFG background metadata rejects before application")
    var saved_hash := FileAccess.get_sha256(FIXTURE)
    var invalid_values: Dictionary = demo.values.duplicate(true)
    invalid_values.normal_strength = NAN
    check(not store.save_settings(invalid_values, demo.lamp_overrides) and FileAccess.get_sha256(FIXTURE) == saved_hash, "invalid save preserves complete existing file")

func panel_checks(demo: Node) -> void:
    var panel := Console.new()
    root.add_child(panel)
    panel.configure(demo)
    check(panel.tabs.get_tab_count() == 4 and panel.fields.size() == 78, "four Chinese pages expose 73 global and five selected-lamp controls")
    check(not panel.fields.has("camera_yaw") and not panel.fields.has("camera_pitch"), "free yaw and pitch cannot be changed through UI")
    var lens_before: Dictionary = demo.rig.lens_profiles_snapshot()
    var profile_before: Dictionary = demo.parallax.snapshot()
    var lamp_before: Dictionary = demo.selected_lamp_values()
    panel.refresh()
    panel.refresh()
    check(demo.rig.lens_profiles_snapshot() == lens_before and demo.parallax.snapshot() == profile_before and demo.selected_lamp_values() == lamp_before, "panel refresh emits no parameter mutation")
    panel.fields.camera_variant.item_selected.emit(1)
    check(demo.rig.variant_id == "W" and panel.fields.camera_distance.value == 24.5 and panel.fields.camera_fov.value == 47.0, "F W O selector reads actual stored W lens")
    panel.fields.camera_distance.value_changed.emit(26.0)
    check(demo.rig.lens_snapshot().radius == 26.0 and demo.rig.lens_profiles.O.radius == 32.5, "radius control updates only actual active profile")
    demo.values.camera_distance = 18.0
    panel.refresh()
    check(panel.fields.camera_distance.value == 26.0 and "12.0" in panel.camera_readout.text, "actual rig readout overrides stale UI alias and reports W pitch")
    panel.fields.parallax_mode.item_selected.emit(1)
    panel.fields.near_town.value_changed.emit(0.5)
    check(demo.parallax.snapshot().mode == "artistic" and demo.parallax.snapshot().near_town == 0.5, "artistic mode and layer slider update authority")
    panel.fields.parallax_mode.item_selected.emit(0)
    check(demo.parallax.effective("near_town") == 1.0 and demo.parallax.snapshot().near_town == 0.5, "natural selection preserves requested artistic layer gain")
    panel.lamp_selector.item_selected.emit(0)
    check(demo.selected_lamp_id == "lantern_0", "single-lamp selector uses catalog stable IDs")
    panel.fields.lamp_energy.value_changed.emit(1.6)
    check(is_equal_approx(demo.lamps.lantern_0.light_energy, 1.6) and demo.lamp_overrides.lantern_0.energy == 1.6, "single lamp control reaches real Light3D and stored override")
    demo.set_selected_lamp("energy",1.25)
    panel.refresh()
    check(is_equal_approx(float(panel.readouts.lamp_energy.text),1.25) and is_equal_approx(demo.lamps.lantern_0.light_energy,1.25), "off-grid actual light energy retains precise numeric readout")
    demo.set_selected_lamp("energy",1.6)
    demo.lamps.lantern_0.omni_range = 5.5
    panel.refresh()
    check(panel.fields.lamp_range.value == 5.5, "single lamp refresh reads actual light node range")
    for button in panel.find_children("*", "Button", true, false):
        if button.text == "仅看所选灯": button.pressed.emit()
    check(not demo.lamps.streetlamp_left_front.visible and demo.lamps.lantern_0.visible, "isolation action dispatches selected-light-only state")
    for button in panel.find_children("*", "Button", true, false):
        if button.text == "恢复全部灯光": button.pressed.emit()
    check(demo.lamps.streetlamp_left_front.visible and is_equal_approx(demo.lamps.lantern_0.light_energy, 1.6), "isolation recovery retains real individual modifications")
    panel.open()
    var editing: LineEdit = panel.numeric_spins.camera_distance.get_line_edit()
    editing.grab_focus()
    editing.text = "31.5"
    demo.rig.set_lens("radius", 27.0)
    panel.refresh()
    check(panel.is_text_editing() and editing.text == "31.5" and panel.readouts.camera_distance.text == "27.0m", "refresh protects focused text while actual label keeps updating")
    panel.lamp_selector.get_popup().popup()
    check(panel.has_open_popup() and panel.dismiss_popup() and not panel.has_open_popup(), "new lamp menu participates in Escape popup-first handling")
    panel.close()
    check(not panel.visible and not panel.is_text_editing(), "closing panel releases input focus")
    panel.free()

func process_probe(demo: Node, read: bool) -> void:
    if not read:
        demo.rig.select_variant("W", Vector3.ZERO)
        demo.rig.set_lens("radius", 24.5)
        demo.rig.set_lens("fov", 47.0)
        demo.rig.select_variant("O", Vector3.ZERO)
        demo.rig.set_lens("radius", 32.5)
        demo.values.main_color = Color(0.7,0.5,0.3,1)
        demo.values.time_preset = "custom"
        demo.farfield.profile_id = "night"
        demo.parallax.change("far_clouds", 0.4)
        demo.lamp_overrides = {"streetlamp_left_front":{"energy":1.25, "color":Color(1,0.7,0.4,1)}}
        check(demo.save_settings(), "writer process stores canonical multi-lens profile and overrides")
    else:
        var loaded: Dictionary = demo.store.load_settings()
        check(not loaded.is_empty(), "reader process loads v2")
        if loaded.is_empty(): return
        check(loaded.camera.variant == "O" and loaded.lens_profiles.W.radius == 24.5 and loaded.lens_profiles.W.fov == 47.0 and loaded.lens_profiles.O.radius == 32.5, "different process restores active variant and inactive profile")
        check(loaded.parameters.main_color == Color(0.7,0.5,0.3,1), "different process restores native Color")
        check(loaded.background_preset == "night" and loaded.parameters.time_preset == "custom", "different process retains explicit night background despite custom lighting")
        check(loaded.parallax.mode == "natural" and loaded.parallax.far_clouds == 0.4, "different process restores six-layer requested profile")
        check(loaded.lamp_overrides.streetlamp_left_front.energy == 1.25 and loaded.lamp_overrides.streetlamp_left_front.color == Color(1,0.7,0.4,1), "different process restores single-lamp scalar and native Color")
        check(demo.rig.variant_id == "F", "load candidate leaves scene pose untouched until explicit application")
        check(demo.rig.restore_lens_profiles(loaded.lens_profiles, loaded.camera.variant, Vector3.ZERO) and demo.parallax.apply_snapshot(loaded.parallax), "fully validated candidate applies controller states once")
        check(demo.rig.variant_id == "O" and demo.rig.lens_snapshot().radius == 32.5 and demo.parallax.effective("far_clouds") == 1.0, "applied controller values match independent process snapshot")

func run() -> void:
    root.size = Vector2i(1920,1080)
    var demo := make_demo()
    var args := OS.get_cmdline_user_args()
    var mode := "suite"
    if "--settings-contract-write" in args: mode = "writer"; process_probe(demo, false)
    elif "--settings-contract-read" in args: mode = "reader"; process_probe(demo, true)
    else: storage_checks(demo); panel_checks(demo)
    var report_path := REPORT
    for arg in args:
        if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path.get_base_dir()))
    var file := FileAccess.open(report_path, FileAccess.WRITE)
    file.store_string(JSON.stringify({"passed":failures.is_empty(), "mode":mode, "checks":checks, "failures":failures, "scope":"Headless settings, real camera/profile and Light3D controls; no visual or performance claim."}, "  ") + "\n")
    file.close()
    demo.free()
    print("SETTINGS_CONTRACT_DONE mode=", mode, " checks=", checks.size(), " failures=", failures.size())
    quit(0 if failures.is_empty() else 1)
