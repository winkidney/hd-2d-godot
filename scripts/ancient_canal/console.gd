extends PanelContainer
## Four pages share the live values dictionary; refreshing never emits changes.
signal closed
const Settings = preload("res://scripts/ancient_canal/settings.gd")
const FONT_PATH := "res://assets/ancient-canal/fonts/NotoSansSC.ttf"
const PAGE_HINTS := {
    "character": "颜色帧沿用原动画。法线、银饰与颜色同时切帧。",
    "lighting": "灯组数值为基准，单灯修改优先。调节同一灯组参数会清除该项单灯修改。时段保留镜头与景深。",
    "environment": "F / W / O 保留各自镜距。六层自然视差与景深独立控制。",
    "comparison": "在同一机位固定姿态与灯位，比较法线开关后的受光。"}
var scene: Node
var validator: RefCounted
var fields: Dictionary = {}
var readouts: Dictionary = {}
var numeric_spins: Dictionary = {}
var tabs: TabContainer
var state_readout: Label
var status: Label
var performance_readout: Label
var compare_button: Button
var route_button: Button
var lamp_selector: OptionButton
var lamp_readout: Label
var camera_readout: Label
var parallax_readout: Label
var lamp_catalog: Array = []
var refreshing := false
var configured := false
var refresh_elapsed := 0.0
var frame_intervals: Array[float] = []

func configure(value: Node) -> void:
    if configured:
        return
    scene = value
    validator = Settings.new(scene.parameter_spec)
    name = "AncientCanalConsole"
    custom_minimum_size = Vector2(620, 850)
    size = custom_minimum_size
    mouse_filter = Control.MOUSE_FILTER_STOP
    _build_theme()
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 12)
    add_child(box)
    var header := HBoxContainer.new()
    box.add_child(header)
    var title := _label(header, "江南河街 · 光影控制台", 25)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _button(header, "关闭  M", close)
    state_readout = _label(box, "", 17)
    tabs = TabContainer.new()
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    tabs.clip_tabs = false
    tabs.tab_changed.connect(func(_index: int): refresh())
    box.add_child(tabs)
    for page in scene.parameter_spec.pages:
        _build_page(str(page.id), str(page.label))
    status = _label(box, "调节立即生效。关闭面板后恢复移动；保存按钮保留本机设置。", 17)
    status.custom_minimum_size.y = 48
    _label(box, "Tab 切换焦点 · Esc 关闭面板 · F8 / F9 保留给编辑器", 15)
    configured = true
    refresh()
    hide()

func _build_theme() -> void:
    var palette := Theme.new()
    palette.default_font_size = 19
    if ResourceLoader.exists(FONT_PATH):
        palette.default_font = load(FONT_PATH)
    theme = palette
    var frame := StyleBoxFlat.new()
    frame.bg_color = Color(0.085, 0.095, 0.115, 0.985)
    frame.border_color = Color(0.48, 0.37, 0.24)
    frame.set_border_width_all(1)
    frame.set_corner_radius_all(8)
    frame.set_content_margin_all(18)
    add_theme_stylebox_override("panel", frame)
    palette.set_color("font_color", "Label", Color(0.92, 0.9, 0.83))
    palette.set_color("font_color", "Button", Color(0.96, 0.9, 0.76))
    palette.set_color("font_color", "CheckBox", Color(0.92, 0.9, 0.83))
    for state in ["normal", "hover", "pressed", "focus"]:
        var style := StyleBoxFlat.new()
        style.bg_color = Color(0.18, 0.2, 0.24) if state == "normal" else Color(0.3, 0.27, 0.2)
        style.border_color = Color(0.71, 0.56, 0.34) if state == "focus" else Color(0.33, 0.32, 0.29)
        style.set_border_width_all(2 if state == "focus" else 1)
        style.set_corner_radius_all(4)
        style.content_margin_left = 12
        style.content_margin_right = 12
        style.content_margin_top = 7
        style.content_margin_bottom = 7
        palette.set_stylebox(state, "Button", style)
        palette.set_stylebox(state, "OptionButton", style)
    var page_style := StyleBoxFlat.new()
    page_style.bg_color = Color(0.105, 0.12, 0.145)
    page_style.set_content_margin_all(12)
    palette.set_stylebox("panel", "TabContainer", page_style)

func _build_page(id: String, title: String) -> void:
    var scroll := ScrollContainer.new()
    scroll.name = title
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.follow_focus = true
    tabs.add_child(scroll)
    var box := VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 11)
    scroll.add_child(box)
    var hint := _label(box, PAGE_HINTS.get(id, ""), 16)
    hint.modulate = Color(0.75, 0.79, 0.83)
    var previous_group := ""
    for key in validator.parameters:
        var definition: Dictionary = validator.parameters[key]
        if definition.page != id:
            continue
        var group := str(definition.group)
        if group != previous_group:
            _heading(box, group)
            previous_group = group
        _build_field(box, str(key), definition)
    if id == "character":
        var controls := HBoxContainer.new()
        controls.add_theme_constant_override("separation", 10)
        box.add_child(controls)
        _button(controls, "上一帧", func(): _step_frame(-1))
        _button(controls, "下一帧", func(): _step_frame(1))
        _label(box, "逐帧按钮自动暂停；序列帧范围 0–26。", 16)
    elif id == "comparison":
        _build_comparison_actions(box)
    elif id == "environment":
        _build_camera_actions(box)
    elif id == "lighting":
        _build_lamp_actions(box)
    _label(box, "", 10).custom_minimum_size.y = 12

func _build_field(parent: Node, key: String, definition: Dictionary) -> void:
    # Lens ranges come from the same controller that validates actual changes.
    if key in ["camera_distance", "camera_fov"]:
        definition = definition.duplicate(true)
        var limits: Vector2 = validator.camera_source.LENS_LIMITS["radius" if key == "camera_distance" else "fov"]
        definition.min = limits.x
        definition.max = limits.y
    var kind: String = definition.type
    if kind == "bool":
        var control := CheckBox.new()
        control.name = key
        control.text = definition.label
        control.focus_mode = Control.FOCUS_ALL
        control.toggled.connect(func(value: bool): _change(key, value))
        parent.add_child(control)
        fields[key] = control
        return
    var group := VBoxContainer.new()
    group.add_theme_constant_override("separation", 4)
    parent.add_child(group)
    var title_row := HBoxContainer.new()
    group.add_child(title_row)
    var label := _label(title_row, str(definition.label), 18)
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    if kind in ["float", "int"]:
        var actual := _label(title_row, "", 16)
        actual.autowrap_mode = TextServer.AUTOWRAP_OFF
        actual.custom_minimum_size.x = 100
        actual.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        actual.modulate = Color(0.94, 0.75, 0.48)
        readouts[key] = actual
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 10)
        group.add_child(row)
        var slider := HSlider.new()
        slider.name = key
        slider.min_value = float(definition.min)
        slider.max_value = float(definition.max)
        slider.step = float(definition.step)
        slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        slider.focus_mode = Control.FOCUS_ALL
        slider.value_changed.connect(func(value: float): _change(key, int(value) if kind == "int" else value))
        row.add_child(slider)
        var spin := SpinBox.new()
        spin.name = key + "Value"
        spin.min_value = slider.min_value
        spin.max_value = slider.max_value
        spin.step = slider.step
        spin.suffix = str(definition.get("suffix", ""))
        spin.custom_minimum_size.x = 130
        spin.value_changed.connect(func(value: float): _change(key, int(value) if kind == "int" else value))
        row.add_child(spin)
        fields[key] = slider
        numeric_spins[key] = spin
    elif kind == "enum":
        var selector := OptionButton.new()
        selector.name = key
        selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        for option in definition.options:
            selector.add_item(str(option.label))
        selector.item_selected.connect(func(index: int): _change(key, str(definition.options[index].value)))
        group.add_child(selector)
        fields[key] = selector
    elif kind == "color":
        var color_picker := ColorPickerButton.new()
        color_picker.name = key
        color_picker.custom_minimum_size = Vector2(0, 32)
        color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        color_picker.edit_alpha = false
        color_picker.color_changed.connect(func(value: Color): _change(key, value))
        group.add_child(color_picker)
        fields[key] = color_picker

func _build_camera_actions(parent: Node) -> void:
    _heading(parent, "实际镜头与远景")
    camera_readout = _label(parent, "", 17)
    parallax_readout = _label(parent, "", 16)
    _label(parent, "水平角与俯角由观察方案决定。艺术倍率在自然模式中保留，实际倍率为 1。", 16)
    var actions := HBoxContainer.new()
    actions.add_theme_constant_override("separation", 10)
    parent.add_child(actions)
    _button(actions, "恢复当前镜头", func():
        if scene.has_method("reset_lens"): scene.reset_lens()
        refresh())
    _button(actions, "恢复六层远景", func():
        if scene.has_method("reset_parallax"): scene.reset_parallax()
        refresh())
    _button(parent, "保存三组镜头与全部设置", func():
        scene.save_settings()
        refresh())

func _build_lamp_actions(parent: Node) -> void:
    _heading(parent, "选择单灯")
    lamp_selector = OptionButton.new()
    lamp_selector.name = "SelectedLamp"
    lamp_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lamp_selector.focus_mode = Control.FOCUS_ALL
    if scene.has_method("light_catalog"):
        lamp_catalog = scene.light_catalog()
    for item in lamp_catalog:
        var group: String = {"lantern":"灯笼","streetlamp":"路灯","broad":"大范围"}.get(item.get("group", ""),"灯具")
        lamp_selector.add_item(group + " · " + str(item.get("label", item.id)))
    lamp_selector.item_selected.connect(func(index: int):
        if refreshing or index < 0 or index >= lamp_catalog.size(): return
        scene.select_lamp(str(lamp_catalog[index].id))
        refresh())
    parent.add_child(lamp_selector)
    lamp_readout = _label(parent, "", 16)
    for key in validator.spec.get("lamp_parameters", {}):
        _build_field(parent, "lamp_" + key, validator.spec.lamp_parameters[key])
    var actions := HBoxContainer.new()
    actions.add_theme_constant_override("separation", 10)
    parent.add_child(actions)
    _button(actions, "仅看所选灯", func():
        scene.isolate_selected_lamp()
        refresh())
    _button(actions, "恢复全部灯光", func():
        scene.restore_lamp_isolation()
        refresh())
    _label(parent, "单灯修改会随设置保存；选择与临时隔离不会保存。隔离结束后恢复原灯组和单灯修改。", 16)

func _build_comparison_actions(parent: Node) -> void:
    _heading(parent, "同机位验证")
    compare_button = _button(parent, "比较法线开 / 关", func():
        scene.toggle_comparison()
        refresh())
    _label(parent, "比较期间使用同机位与同一动画帧。按比较按钮返回原状态。", 16)
    _heading(parent, "复现与记录")
    var preferences := HBoxContainer.new()
    preferences.add_theme_constant_override("separation", 10)
    parent.add_child(preferences)
    _button(preferences, "恢复默认", func():
        scene.restore_defaults()
        refresh())
    _button(preferences, "保存设置", func():
        scene.save_settings()
        refresh())
    _button(preferences, "载入设置", func():
        scene.load_settings()
        refresh())
    _button(parent, "保存当前画面", func():
        scene.capture_screenshot()
        refresh())
    route_button = _button(parent, "开始自动展示路线", func():
        if bool(scene.get("route_running")):
            scene.cancel_route()
        else:
            scene.start_route()
        refresh())
    _label(parent, "自动路线可按 Esc 取消。保存设置只影响江南河街演示。", 16)
    _heading(parent, "性能读数")
    performance_readout = _label(parent, "", 17)
    performance_readout.custom_minimum_size.y = 70

func _heading(parent: Node, title: String) -> void:
    var line := HSeparator.new()
    parent.add_child(line)
    var label := _label(parent, title, 20)
    label.modulate = Color(0.94, 0.75, 0.48)

func _label(parent: Node, text: String, font_size: int) -> Label:
    var label := Label.new()
    label.text = text
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.add_theme_font_size_override("font_size", font_size)
    parent.add_child(label)
    return label

func _button(parent: Node, title: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = title
    button.focus_mode = Control.FOCUS_ALL
    button.pressed.connect(action)
    parent.add_child(button)
    return button

func _change(key: String, value: Variant) -> void:
    if refreshing or scene == null:
        return
    if key.begins_with("lamp_"):
        var property := key.trim_prefix("lamp_")
        var lamp_error: String = validator.lamp_field_error(property, value)
        if not lamp_error.is_empty(): status.text = lamp_error; return
        if scene.has_method("set_selected_lamp"):
            scene.set_selected_lamp(property, validator.normalize_lamp(property, value))
        refresh()
        return
    var error: String = validator.field_error(key, value)
    if not error.is_empty():
        status.text = error
        return
    if key == "camera_variant":
        scene.select_variant(str(value))
    elif key in ["camera_distance", "camera_fov"]:
        scene.set_lens("radius" if key == "camera_distance" else "fov", float(value))
    elif key == "time_preset" and value != "custom":
        scene.apply_time_preset(str(value))
    elif key == "direction":
        scene.force_direction(str(value))
    elif key == "animation_frame":
        scene.set_frame(int(value))
    else:
        scene.set_parameter(key, validator.normalize(key, value))
    refresh()

func _step_frame(offset: int) -> void:
    scene.set_parameter("animation_pause", true)
    scene.set_frame(posmod(int(scene.values.get("animation_frame", 0)) + offset, 27))
    refresh()

func refresh() -> void:
    if scene == null or not configured:
        return
    refreshing = true
    for key in fields:
        if not validator.parameters.has(key):
            continue
        var value = _live_value(key)
        if value == null: continue
        var definition: Dictionary = validator.parameters[key]
        _refresh_field(key, definition, value)
    _refresh_lamps()
    _refresh_camera()
    var time_label := "自定义"
    for option in validator.parameters.time_preset.options:
        if scene.values.get("time_preset", "custom") == option.value:
            time_label = str(option.label)
            break
    var shading_label := "原生" if scene.values.get("shading_mode", "native") == "native" else str(scene.values.get("light_steps", 4)) + " 档"
    state_readout.text = "%s · %s受光 · 法线 %s · 帧 %02d / 26" % [time_label, shading_label, "开" if bool(scene.values.get("normals_enabled", true)) else "关", int(scene.values.get("animation_frame", 0))]
    status.text = str(scene.status_text)
    if status.text.is_empty():
        status.text = "调节立即生效。关闭面板后恢复移动；保存按钮保留本机设置。"
    if route_button != null:
        route_button.text = "取消自动展示路线" if bool(scene.get("route_running")) else "开始自动展示路线"
    refreshing = false
    _update_performance()

func _live_value(key: String) -> Variant:
    var rig = scene.get("rig")
    if rig != null:
        if key == "camera_variant": return rig.variant_id
        if key == "camera_follow": return rig.enabled
        if key in ["camera_distance", "camera_fov"]:
            var lens: Dictionary = rig.lens_snapshot()
            return lens["radius" if key == "camera_distance" else "fov"]
    var parallax = scene.get("parallax")
    if parallax != null and (Settings.PARALLAX_ALIASES.has(key) or key in Settings.LAYER_IDS):
        var values: Dictionary = parallax.snapshot()
        return values.get(Settings.PARALLAX_ALIASES.get(key, key))
    return scene.values.get(key)

func _refresh_field(key: String, definition: Dictionary, value: Variant) -> void:
    var control: Control = fields[key]
    match str(definition.type):
        "bool": control.set_pressed_no_signal(bool(value))
        "float", "int":
            control.set_value_no_signal(float(value))
            var spin: SpinBox = numeric_spins[key]
            if not spin.get_line_edit().has_focus(): spin.set_value_no_signal(float(value))
            readouts[key].text = _number_text(float(value), float(definition.step)) + str(definition.get("suffix", ""))
        "enum":
            for index in definition.options.size():
                if value == definition.options[index].value: control.select(index); break
        "color":
            var normalized = validator.normalize_lamp(key.trim_prefix("lamp_"), value) if key.begins_with("lamp_") else validator.normalize(key, value)
            if normalized is Color: control.color = normalized

func _refresh_camera() -> void:
    if camera_readout == null: return
    var rig = scene.get("rig")
    if rig != null:
        var pose: Dictionary = rig.pose_diagnostics()
        camera_readout.text = "%s · 真实透视 · 观察半径 %.1fm · 视野 %.0f°\n实际俯角 %.1f° · 实际水平角 %.2f°" % [pose.variant, pose.orbit_radius, pose.fov, pose.pitch_degrees, pose.yaw_degrees]
    var controller = scene.get("parallax")
    if controller == null: return
    var diagnostics: Dictionary = controller.diagnostics() if controller.has_method("diagnostics") else {}
    var actual: Array[String] = []
    for id in Settings.LAYER_IDS:
        var effective: float = float(diagnostics.get(id, {}).get("effective", controller.effective(id)))
        actual.append(str(validator.parameters[id].label).trim_suffix("艺术倍率") + " %.2f" % effective)
    parallax_readout.text = "实际倍率：" + " · ".join(actual)

func _refresh_lamps() -> void:
    if lamp_selector == null: return
    var selected := str(scene.get("selected_lamp_id"))
    for index in lamp_catalog.size():
        if lamp_catalog[index].id == selected: lamp_selector.select(index); break
    var actual: Dictionary = scene.selected_lamp_values() if scene.has_method("selected_lamp_values") else {}
    lamp_selector.disabled = lamp_catalog.is_empty()
    lamp_readout.text = "当前灯：" + lamp_selector.get_item_text(lamp_selector.selected) if lamp_selector.selected >= 0 else "当前没有可选灯具。"
    for property in validator.spec.get("lamp_parameters", {}):
        var key: String = "lamp_" + property
        var control: Control = fields[key]
        var available := actual.has(property)
        if control is Range: control.editable = available
        elif control is BaseButton: control.disabled = not available
        if numeric_spins.has(key): numeric_spins[key].editable = available
        if available: _refresh_field(key, validator.spec.lamp_parameters[property], actual[property])

func _number_text(value: float, step: float) -> String:
    var formatted: String
    if step < 0.01:
        formatted = "%.3f" % value
    elif step < 0.1:
        formatted = "%.2f" % value
    elif step < 1.0:
        formatted = "%.1f" % value
    else:
        formatted = "%.0f" % value
    # A saved or programmatic value need not lie on the slider's step grid.
    # Keep the actual readout precise even when the stepping control rounds it.
    return formatted if absf(float(formatted)-value) <= .00001 else String.num(value,4)

func _update_performance() -> void:
    if performance_readout == null:
        return
    var p50 := 0.0
    var p95 := 0.0
    if not frame_intervals.is_empty():
        var samples := frame_intervals.duplicate()
        samples.sort()
        p50 = samples[int(floor((samples.size() - 1) * 0.5))]
        p95 = samples[int(floor((samples.size() - 1) * 0.95))]
    performance_readout.text = "FPS %.0f · 帧间隔中位 %.2f ms · P95 %.2f ms\n绘制调用 %.0f · 可见物体 %.0f" % [Performance.get_monitor(Performance.TIME_FPS), p50, p95, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)]

func open() -> void:
    if not configured:
        return
    refresh()
    show()
    _fit_viewport()
    tabs.get_tab_bar().grab_focus()

func close() -> void:
    dismiss_popup()
    if is_inside_tree():
        var owner := get_viewport().gui_get_focus_owner()
        if owner != null and is_ancestor_of(owner):
            owner.release_focus()
    hide()
    closed.emit()

func toggle() -> void:
    if visible:
        close()
    else:
        open()

func has_open_popup() -> bool:
    if lamp_selector != null and lamp_selector.get_popup().visible: return true
    for control in fields.values():
        if control is OptionButton or control is ColorPickerButton:
            if control.get_popup().visible:
                return true
    return false

func dismiss_popup() -> bool:
    var dismissed := false
    if lamp_selector != null and lamp_selector.get_popup().visible:
        lamp_selector.get_popup().hide()
        dismissed = true
    for control in fields.values():
        if control is OptionButton or control is ColorPickerButton:
            if control.get_popup().visible:
                control.get_popup().hide()
                dismissed = true
    return dismissed

func is_text_editing() -> bool:
    if not is_inside_tree():
        return false
    var focus := get_viewport().gui_get_focus_owner()
    return focus is LineEdit or focus is TextEdit

func _fit_viewport() -> void:
    var viewport_size := get_viewport_rect().size
    var desired := Vector2(minf(620.0, viewport_size.x - 32.0), minf(850.0, viewport_size.y - 64.0))
    custom_minimum_size = desired
    size = desired
    position = Vector2(viewport_size.x - desired.x - 24.0, maxf(24.0, (viewport_size.y - desired.y) * 0.5))

func _process(delta: float) -> void:
    if not configured:
        return
    if delta > 0.0:
        frame_intervals.append(delta * 1000.0)
        if frame_intervals.size() > 300:
            frame_intervals.pop_front()
    if not visible:
        return
    refresh_elapsed += delta
    if refresh_elapsed >= 0.2:
        refresh_elapsed = 0.0
        refresh()
        _fit_viewport()
