extends PanelContainer
## Runtime editor for parallax only; saves are explicit user actions.
var scene: Node3D
var controller: RefCounted
var fields: Dictionary = {}
var refreshing := false
var preset: OptionButton
var mode_select: OptionButton
var wind: CheckBox
var readout: Label
var status: Label
var applied_summary: Label
var preview_button: Button
var tabs: TabContainer
var preset_ids := ["natural","soft","enhanced","custom"]

func text(parent: Node, value: String) -> Label:
    var label := Label.new()
    label.text = value
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    parent.add_child(label)
    return label

func button(parent: Node, title: String, action: Callable) -> Button:
    var item := Button.new()
    item.text = title
    item.pressed.connect(action)
    parent.add_child(item)
    return item

func configure(value: Node3D) -> void:
    scene = value
    controller = scene.parallax
    name = "ParallaxPanel"
    position = Vector2(1320,120)
    custom_minimum_size = Vector2(560,820)
    add_theme_font_size_override("font_size",18)
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.025,0.04,0.055,0.97)
    style.set_content_margin_all(16)
    add_theme_stylebox_override("panel",style)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation",10)
    add_child(box)
    var header := HBoxContainer.new()
    box.add_child(header)
    var title := text(header,"PARALLAX  /  P")
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button(header,"Close",func(): scene.close_tuning())
    tabs = TabContainer.new()
    tabs.custom_minimum_size = Vector2(520,520)
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    box.add_child(tabs)
    var basic := page("Basic")
    var advanced := page("Advanced")
    text(basic,"1.0 = each layer's natural motion.\n0.0 cancels horizontal parallax, not wind.")
    preset = OptionButton.new()
    for id in preset_ids: preset.add_item(id.capitalize())
    preset.item_selected.connect(func(i): controller.select_preset(preset_ids[i]); refresh())
    basic.add_child(preset)
    mode_select = OptionButton.new()
    mode_select.add_item("Natural: preserve custom values")
    mode_select.add_item("Artistic: use the multipliers below")
    mode_select.item_selected.connect(func(i): controller.change("mode","natural" if i == 0 else "artistic"); refresh())
    basic.add_child(mode_select)
    field(basic,"global_strength","Overall strength",0,2,0.05)
    field(basic,"transition_time","Parameter transition (seconds)",0,1,0.05)
    var reset_row := HBoxContainer.new()
    basic.add_child(reset_row)
    button(reset_row,"Natural only",func(): controller.select_preset("natural"); refresh())
    button(reset_row,"Reset all",func(): scene.parallax_preview.stop(); controller.reset_all(); refresh())
    for id in preload("res://scripts/parallax_profile.gd").IDS: field(advanced,id,id.replace("_"," ").capitalize()+" ratio",0,2,0.05)
    text(advanced,"Camera motion (vertical/depth follow unchanged)")
    field(advanced,"horizontal_follow_gain","Horizontal follow gain",0,0.7,0.05)
    field(advanced,"horizontal_dead_zone","Horizontal dead zone (m)",0,3,0.1)
    field(advanced,"smoothing_rate","Follow response (1/s)",1,10,0.5)
    field(advanced,"horizontal_max_offset","Maximum horizontal offset per side (m)",0,7.5,0.5)
    text(advanced,"Wind is independent from camera motion")
    field(advanced,"wind_near","Near cloud wind (m/s)",-2,2,0.05)
    field(advanced,"wind_far","Far cloud wind (m/s)",-2,2,0.05)
    wind = CheckBox.new()
    wind.text = "Wind enabled"
    wind.toggled.connect(func(v): if not refreshing: controller.change("wind_enabled",v))
    advanced.add_child(wind)
    readout = text(basic,"")
    readout.add_theme_font_size_override("font_size",16)
    applied_summary = text(box,"")
    applied_summary.add_theme_font_size_override("font_size",16)
    status = text(box,"Changes are live. Save explicitly to restore them next time.")
    status.custom_minimum_size.y = 65
    preview_button = button(box,"Start camera comparison",func():
        if scene.parallax_preview.active: scene.parallax_preview.stop()
        else: scene.parallax_preview.start(scene)
        status.text = scene.parallax_preview.message)
    var save_row := HBoxContainer.new()
    box.add_child(save_row)
    button(save_row,"Save on this computer",func():
        scene.parallax_store.save_settings(controller)
        status.text = scene.parallax_store.message)
    button(save_row,"Load saved settings",func():
        scene.parallax_preview.stop()
        scene.parallax_store.load_settings(controller)
        status.text = scene.parallax_store.message
        refresh())
    refresh()
    hide()

func page(title: String) -> VBoxContainer:
    var scroll := ScrollContainer.new()
    scroll.name = title
    tabs.add_child(scroll)
    var content := VBoxContainer.new()
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_theme_constant_override("separation",10)
    scroll.add_child(content)
    return content

func field(parent: Node, key: String, title: String, low: float, high: float, step_value: float) -> void:
    text(parent,title)
    var row := HBoxContainer.new()
    parent.add_child(row)
    var slider := HSlider.new()
    slider.min_value = low
    slider.max_value = high
    slider.step = step_value
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(slider)
    var number := SpinBox.new()
    number.custom_minimum_size.x = 100
    row.add_child(number)
    slider.share(number)
    slider.value_changed.connect(func(v):
        if refreshing: return
        if key in preload("res://scripts/parallax_settings_store.gd").CAMERA_KEYS: scene.parallax_preview.stop()
        var error: String = controller.change(key,v)
        if error != "": status.text = error
        if key == "global_strength" or key in preload("res://scripts/parallax_profile.gd").IDS:
            controller.change("mode","artistic")
        refresh())
    button(row,"Reset",func():
        scene.parallax_preview.stop()
        controller.change(key,controller.defaults[key])
        refresh())
    fields[key] = slider

func refresh() -> void:
    refreshing = true
    var values: Dictionary = controller.snapshot()
    for key in fields: fields[key].set_value_no_signal(float(values[key]))
    mode_select.select(0 if values.mode == "natural" else 1)
    preset.select(preset_ids.find(controller.preset_name()))
    wind.set_pressed_no_signal(bool(values.wind_enabled))
    refreshing = false

func _process(_delta: float) -> void:
    if not visible or controller == null: return
    var info: Dictionary = controller.diagnostics()
    var rows: Array[String] = ["Layer: requested > applied | depth | px / 1m camera"]
    for id in preload("res://scripts/parallax_profile.gd").IDS:
        var entry: Dictionary = info[id]
        rows.append("%s: %.2f > %.2f | %.0fm | %.1fpx%s" % [id,
            entry.requested,entry.effective,entry.depth,entry.px_per_m," [CAP]" if entry.capped else ""])
    rows.append("Sky: direction only, no horizontal multiplier.")
    var warning: String = controller.warnings()
    if warning != "": rows.append(warning)
    readout.text = "\n".join(rows)
    applied_summary.text = "Applied: near %.2f / mid %.2f / far %.2f" % [info.ridge_near.effective,info.ridge_mid.effective,info.ridge_far.effective]
    if warning != "": applied_summary.text += "\n" + warning
    preview_button.text = "Stop comparison (Esc)" if scene.parallax_preview.active else "Start camera comparison"
