extends PanelContainer
## F9 is dispatched by the frontal scene. F8 keeps independent live parameters.
const IDS := ["F", "W", "O"]
const TITLES := ["F  Frontal / stable perspective", "W  Wider lens / stronger depth", "O  Frontal / gentle orbit"]
var scene: Node3D
var selector: OptionButton
var readout: Label
var status: Label
var route_button: Button
var lens_sliders: Dictionary = {}
var lens_spins: Dictionary = {}
var adjustment_buttons: Array[Button] = []
var refreshing := false

func text_line(parent: Node, value: String) -> Label:
    var item := Label.new()
    item.text = value
    item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    parent.add_child(item)
    return item

func button(parent: Node, title: String, action: Callable) -> Button:
    var item := Button.new()
    item.text = title
    item.pressed.connect(action)
    parent.add_child(item)
    return item

func lens_control(parent: Node, key: String, title: String, increment: float, suffix: String) -> void:
    var group := VBoxContainer.new()
    group.add_theme_constant_override("separation", 3)
    parent.add_child(group)
    text_line(group, title)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    group.add_child(row)
    var limits: Vector2 = scene.rig.LENS_LIMITS[key]
    var slider := HSlider.new()
    slider.name = key.capitalize()+"Slider"
    slider.min_value = limits.x
    slider.max_value = limits.y
    slider.step = increment
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.custom_minimum_size.x = 360
    row.add_child(slider)
    var spin := SpinBox.new()
    spin.name = key.capitalize()+"SpinBox"
    spin.min_value = limits.x
    spin.max_value = limits.y
    spin.step = increment
    spin.suffix = suffix
    spin.custom_minimum_size.x = 150
    row.add_child(spin)
    lens_sliders[key] = slider
    lens_spins[key] = spin
    slider.value_changed.connect(func(next_value: float): change_lens(key,next_value))
    spin.value_changed.connect(func(next_value: float): change_lens(key,next_value))

func change_lens(key: String, value: float) -> void:
    if refreshing or scene == null or scene.route_running:
        return
    var ok: bool = scene.set_lens(key,value)
    status.text = "Lens updated. Save to keep this camera's settings." if ok else scene.notice
    refresh()

func configure(value: Node3D) -> void:
    scene = value
    name = "FrontalCameraPanel"
    position = Vector2(1230, 100)
    custom_minimum_size = Vector2(650, 820)
    add_theme_font_size_override("font_size", 18)
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.025,0.04,0.055,0.97)
    style.set_content_margin_all(18)
    add_theme_stylebox_override("panel", style)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 8)
    add_child(box)
    text_line(box, "FRONTAL CANAL  /  CAMERA STUDIES  /  F9")
    selector = OptionButton.new()
    for title in TITLES:
        selector.add_item(title)
    selector.item_selected.connect(func(index):
        if refreshing or scene.route_running: return
        scene.select_variant(IDS[index])
        status.text = scene.notice
        refresh())
    box.add_child(selector)
    readout = text_line(box, "")
    text_line(box, "Shared 3D buildings; only O adds a +/- 4 degree orbit.")
    lens_control(box,"radius","Distance to observation center",0.5,"m")
    lens_control(box,"fov","Vertical field of view",1.0,"deg")
    text_line(box, "Distance is to the observation center, not the actor.\nClose / narrow may crop; far / wide may expose scene edges.\nLive controls; wheel zoom only with all panels closed.")
    var lens_actions := HBoxContainer.new()
    lens_actions.add_theme_constant_override("separation", 10)
    box.add_child(lens_actions)
    adjustment_buttons.append(button(lens_actions, "Save lens", func():
        if scene.route_running: return
        scene.save_lens_settings()
        status.text = scene.lens_store.message
        refresh()))
    adjustment_buttons.append(button(lens_actions, "Load lens", func():
        if scene.route_running: return
        scene.load_lens_settings()
        status.text = scene.lens_store.message
        refresh()))
    adjustment_buttons.append(button(lens_actions, "Reset lens", func():
        if scene.route_running: return
        scene.reset_lens()
        status.text = "Lens defaults restored. Save to keep them."
        refresh()))
    text_line(box, "Save / Load: this camera only. F8: follow. F6: focus. T: time.\nThe route temporarily uses this camera's default lens.\nYour lens returns on completion or cancellation.")
    adjustment_buttons.append(button(box, "Reset this camera", func():
        if scene.route_running: return
        scene.reset_variant()
        status.text = "Camera, lens and background reset for this session only.\nUse Save lens separately to keep the lens defaults."
        refresh()))
    route_button = button(box, "Run the same walking route", func():
        if scene.route_running: return
        route_button.disabled = true
        status.text = "Walking the shared route."
        var result: Dictionary = await scene.run_route()
        status.text = "Route passed." if bool(result.get("passed",false)) else "Route stopped: " + str(result.get("reason","see the route report"))
        refresh())
    status = text_line(box, "Select a camera, then compare the same route and time of day.")
    button(box, "Close", func(): scene.close_tuning())
    # Resize the existing F8 Range objects locally; the shared script is intact.
    for key in scene.parallax.CAMERA_RANGES:
        if scene.parallax_panel.fields.has(key):
            var control: Range = scene.parallax_panel.fields[key]
            var limits: Vector2 = scene.parallax.CAMERA_RANGES[key]
            control.min_value = limits.x
            control.max_value = limits.y
    scene.parallax_panel.refresh()
    refresh()
    hide()

func refresh() -> void:
    if scene == null:
        return
    refreshing = true
    selector.select(IDS.find(scene.variant_id))
    var lens: Dictionary = scene.rig.lens_snapshot()
    for key in lens_sliders:
        var slider: HSlider = lens_sliders[key]
        var spin: SpinBox = lens_spins[key]
        slider.set_value_no_signal(float(lens[key]))
        spin.set_value_no_signal(float(lens[key]))
    refreshing = false
    refresh_locks()
    update_readout()

func refresh_locks() -> void:
    selector.disabled = scene.route_running
    route_button.disabled = scene.route_running
    for key in lens_sliders:
        var slider: HSlider = lens_sliders[key]
        var spin: SpinBox = lens_spins[key]
        slider.editable = not scene.route_running
        spin.editable = not scene.route_running
    for item in adjustment_buttons:
        item.disabled = scene.route_running

func update_readout() -> void:
    if scene == null:
        return
    var state: Dictionary = scene.rig.pose_diagnostics()
    var parameters: Dictionary = scene.parallax.snapshot()
    readout.text = "Camera %s  |  Perspective %.0f degrees\nPitch %.1f degrees  |  orbit %.2f degrees\nRadius %.1fm  |  horizontal follow %.2f\nBackground %s / strength %.2f\nTranslation compensation; orbit remains natural." % [scene.variant_id,state.fov,state.pitch_degrees,state.yaw_degrees,state.orbit_radius,scene.rig.horizontal_gain,parameters.mode,parameters.global_strength]

func _process(_delta: float) -> void:
    if visible:
        refresh_locks()
        update_readout()
