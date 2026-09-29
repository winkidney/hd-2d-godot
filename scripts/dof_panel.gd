extends PanelContainer
## Runtime inspection only: resources are duplicated, never overwritten.
var dof: RefCounted
var readout: Label
var box: VBoxContainer
var refreshing := false
var fields: Dictionary = {}

func configure(controller: RefCounted) -> void:
    dof = controller
    position = Vector2(1420,150)
    custom_minimum_size = Vector2(450,610)
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.035,0.05,0.07,0.97)
    style.content_margin_left = 18
    style.content_margin_right = 18
    style.content_margin_top = 16
    style.content_margin_bottom = 16
    add_theme_stylebox_override("panel",style)
    box = VBoxContainer.new()
    box.add_theme_constant_override("separation",8)
    add_child(box)
    var title := Label.new()
    title.text = "DEPTH OF FIELD   /   O CLOSE"
    box.add_child(title)
    var presets := OptionButton.new()
    presets.name = "DofPreset"
    for text in ["soft","standard","strong"]:
        presets.add_item(text)
    presets.select(1)
    presets.item_selected.connect(func(i): dof.select_profile(["soft","standard","strong"][i]); refresh())
    box.add_child(presets)
    for pair in [["near_enabled","Near blur"],["far_enabled","Far blur"]]:
        var button := CheckBox.new()
        button.name = pair[0]
        button.text = pair[1]
        button.button_pressed = true
        var key: String = pair[0]
        button.toggled.connect(func(value): dof.set(key,value); dof.apply())
        box.add_child(button)
    var mode := OptionButton.new()
    mode.name = "FocusMode"
    for text in ["Protected player focus","Fixed scene anchor","Manual focus"]:
        mode.add_item(text)
    mode.item_selected.connect(func(i): dof.mode = ["protected","anchor","manual"][i])
    box.add_child(mode)
    slider("amount","Blur amount",0.0,0.25,0.005)
    slider("near_clear","Near clear range (m)",2,18,0.5)
    slider("far_clear","Far clear range (m)",3,25,0.5)
    slider("near_transition","Near transition (m)",0.5,18,0.5)
    slider("far_transition","Far transition (m)",0.5,60,0.5)
    slider("manual_depth","Manual focal depth (m)",10,80,0.5)
    readout = Label.new()
    readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(readout)
    refresh()
    hide()

func slider(key: String, title: String, low: float, high: float, step_value: float) -> void:
    var label := Label.new()
    label.text = title
    box.add_child(label)
    var control := HSlider.new()
    control.min_value = low
    control.max_value = high
    control.step = step_value
    control.value_changed.connect(func(value):
        if refreshing: return
        if key == "manual_depth": dof.manual_depth = value
        else: dof.profile.set(key,value)
        dof.apply())
    box.add_child(control)
    fields[key] = control

func refresh() -> void:
    refreshing = true
    for key in fields:
        fields[key].value = dof.manual_depth if key == "manual_depth" else dof.profile.get(key)
    refreshing = false

func _process(_delta: float) -> void:
    if visible and dof != null:
        readout.text = "Focus %.1fm | Clear %.1f - %.1fm\nDOF %s | Global FX %s | %s" % [dof.focus_depth,dof.attributes.dof_blur_near_distance,dof.attributes.dof_blur_far_distance,str(dof.enabled),str(dof.master_enabled),dof.mode]
