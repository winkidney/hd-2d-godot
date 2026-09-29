extends CanvasLayer
var container: Control
var status: Label
var prompt: Label
var dialogue: PanelContainer
var dialogue_title: Label
var dialogue_text: Label
var toolbar: HBoxContainer
var toolbar_buttons: Dictionary = {}
var quit_dialog: ConfirmationDialog

func label_at(text: String, position: Vector2, size: Vector2, font_size: int) -> Label:
    var label := Label.new()
    label.text = text
    label.position = position
    label.size = size
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", Color("eadfc8"))
    label.add_theme_color_override("font_shadow_color", Color(0.02, 0.025, 0.03, 0.9))
    label.add_theme_constant_override("shadow_offset_x", 2)
    label.add_theme_constant_override("shadow_offset_y", 2)
    container.add_child(label)
    return label

func _ready() -> void:
    container = Control.new()
    container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(container)
    label_at("R I V E R S I D E   W A Y S T A T I O N", Vector2(46, 36), Vector2(1000, 44), 29)
    label_at("HD-2D SCENE STUDY   /   ORIGINAL PROCEDURAL ART", Vector2(48, 82), Vector2(1000, 32), 16)
    status = label_at("", Vector2(1320, 40), Vector2(550, 70), 20)
    status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var footer := label_at("WASD / ARROWS Walk  |  E Interact  T Time  G Tour  V Effects  F Follow  B DOF  O Focus  P Parallax  K Background  H Hide UI  J Capture  Esc Back / Exit", Vector2(46, 1016), Vector2(1830, 40), 16)
    footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    prompt = label_at("", Vector2(450, 948), Vector2(1020, 48), 25)
    prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    dialogue = PanelContainer.new()
    dialogue.position = Vector2(460, 740)
    dialogue.size = Vector2(1000, 190)
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.045, 0.062, 0.075, 0.96)
    style.border_color = Color("a98d61")
    style.set_border_width_all(2)
    style.content_margin_left = 28
    style.content_margin_right = 28
    style.content_margin_top = 20
    style.content_margin_bottom = 20
    dialogue.add_theme_stylebox_override("panel", style)
    container.add_child(dialogue)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 12)
    dialogue.add_child(box)
    dialogue_title = Label.new()
    dialogue_title.add_theme_font_size_override("font_size", 25)
    dialogue_title.add_theme_color_override("font_color", Color("e9c88f"))
    box.add_child(dialogue_title)
    dialogue_text = Label.new()
    dialogue_text.add_theme_font_size_override("font_size", 22)
    dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    dialogue_text.custom_minimum_size = Vector2(930, 92)
    box.add_child(dialogue_text)
    dialogue.hide()

func configure_toolbar(scene: Node3D) -> void:
    toolbar = HBoxContainer.new()
    toolbar.name = "SceneToolbar"
    toolbar.position = Vector2(48,126)
    toolbar.add_theme_constant_override("separation",8)
    container.add_child(toolbar)
    for entry in [["dof","O  Focus"],["parallax","P  Parallax"],["camera","C  Camera"],["quit","Exit"]]:
        var button := Button.new()
        button.name = str(entry[0]).capitalize()+"ToolbarButton"
        button.text = entry[1]
        button.add_theme_font_size_override("font_size",18)
        button.custom_minimum_size = Vector2(126,36)
        toolbar.add_child(button)
        toolbar_buttons[entry[0]] = button
    toolbar_buttons.dof.pressed.connect(func(): scene.toggle_tuning("dof"))
    toolbar_buttons.parallax.pressed.connect(func(): scene.toggle_tuning("parallax"))
    toolbar_buttons.camera.pressed.connect(scene.toggle_camera_panel)
    toolbar_buttons.camera.visible = scene.camera_tuning_panel() != null
    toolbar_buttons.quit.pressed.connect(scene.request_quit)
    label_at("F8 / F9 are reserved by the Godot editor. Use the buttons above.\nTab navigates controls; H hides the interface.",Vector2(48,168),Vector2(760,52),16)
    quit_dialog = ConfirmationDialog.new()
    quit_dialog.name = "QuitConfirmation"
    quit_dialog.title = "Exit scene?"
    quit_dialog.dialog_text = "Exit this running scene? Unsaved settings will not be saved."
    quit_dialog.ok_button_text = "Exit"
    quit_dialog.cancel_button_text = "Keep playing"
    quit_dialog.transient = true
    quit_dialog.exclusive = true
    add_child(quit_dialog)
    quit_dialog.confirmed.connect(func(): get_tree().quit())
    quit_dialog.canceled.connect(func(): scene.call_deferred("sync_input_lock"))
    quit_dialog.close_requested.connect(func(): scene.call_deferred("sync_input_lock"))

func refresh_toolbar(route_running: bool) -> void:
    for key in toolbar_buttons:
        toolbar_buttons[key].disabled = route_running

func show_dialogue(point: Dictionary) -> void:
    dialogue_title.text = str(point.title) + "    /    E or ESC to close"
    dialogue_text.text = str(point.text)
    dialogue.show()

func close_dialogue() -> void:
    dialogue.hide()

func update_status(preset: String, tour: bool, effects: bool, follow: bool) -> void:
    status.text = "%s  /  %s\nFX %s  ·  Follow %s  ·  %d FPS" % [preset.to_upper(), "TOUR" if tour else "EXPLORE", "ON" if effects else "OFF", "ON" if follow else "OFF", Engine.get_frames_per_second()]
