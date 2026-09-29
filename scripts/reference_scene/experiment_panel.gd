extends PanelContainer
## A-D comparison is local to P9. Changes never replace player or physics state.
var scene: Node3D
var selector: OptionButton
var readout: Label
var status: Label
var route_button: Button
var refreshing := false
const IDS := ["A", "B", "C", "D"]
const NAMES := ["A  Perspective / fixed direction", "B  Perspective / gentle orbit",
    "C  Orthographic / gentle orbit", "D  Orthographic / layered + multiview"]

func label(parent: Node, value: String) -> Label:
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

func configure(value: Node3D) -> void:
    scene = value
    name = "ExperimentPanel"
    position = Vector2(1250, 135)
    custom_minimum_size = Vector2(620, 590)
    add_theme_font_size_override("font_size", 20)
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.025, 0.04, 0.055, 0.97)
    style.set_content_margin_all(20)
    add_theme_stylebox_override("panel", style)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 14)
    add_child(box)
    label(box, "CAMERA EXPERIMENTS  /  F9")
    selector = OptionButton.new()
    for title in NAMES: selector.add_item(title)
    selector.item_selected.connect(func(index):
        if refreshing: return
        var ok: bool = scene.select_experiment(IDS[index])
        status.text = "Variant changed. Position, time and focus retained." if ok else scene.experiment_notice
        refresh())
    box.add_child(selector)
    readout = label(box, "")
    label(box, "F8 adjusts each mode's own background settings.\nF6 adjusts focus. T changes the time of day.")
    label(box, "D uses 7 captured views of the main palace. It keeps the same collision, but its picture has one flat depth plane.")
    button(box, "Reset this variant", func(): scene.reset_experiment(); status.text = "Current variant reset."; refresh())
    route_button = button(box, "Run the same walking route", func():
        route_button.disabled = true
        status.text = "Walking route running. Esc cancels and restores your controls."
        var result: Dictionary = await scene.run_experiment_route()
        route_button.disabled = false
        status.text = "Route passed. Controls restored." if bool(result.get("passed", false)) else "Route stopped: " + str(result.get("reason", "see validation report")))
    status = label(box, "Select a mode and walk the same route to compare.")
    button(box, "Close", func(): scene.close_tuning())
    refresh()
    hide()

func refresh() -> void:
    if scene == null: return
    refreshing = true
    selector.select(IDS.find(scene.experiment_id))
    selector.set_item_disabled(3, not scene.impostor.available)
    selector.set_item_tooltip(3, scene.impostor.unavailable_reason if not scene.impostor.available else "Seven GPU views of the main palace")
    refreshing = false
    update_readout()

func update_readout() -> void:
    if scene == null: return
    var projection := "Perspective" if scene.camera.projection == Camera3D.PROJECTION_PERSPECTIVE else "Orthographic"
    var snapshot: Dictionary = scene.parallax.snapshot()
    readout.text = "Active: %s  |  %s\nYaw: %.2f degrees  |  limit: %s\nParallax: %s / strength %.2f\nSettings: %s" % [
        scene.experiment_id, projection, float(scene.rig.yaw_degrees),
        "+/- 6 degrees" if scene.experiment_id in ["B", "C"] else "fixed",
        snapshot.mode, float(snapshot.global_strength), scene.preferences_path.get_file()]
    if scene.experiment_id == "D":
        readout.text += "\nPalazzo: view %.2f / 6, %s" % [scene.impostor.frame_position, scene.lighting.preset_id]

func _process(_delta: float) -> void:
    if visible: update_readout()
