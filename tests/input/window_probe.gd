extends Node
## Test-only autoload installed into an isolated project by input_window_test.py.
## Targeted native X11 key/button events enter through Window.window_input.
var output := OS.get_environment("HD2D_INPUT_PROBE_OUT")
var ticks := 0
var interval := 0.0
var command_id := 0
var capture_pending := false

func _process(delta: float) -> void:
    ticks += 1
    interval += delta
    if interval < .05 or output.is_empty(): return
    interval = 0.0
    var scene := get_tree().current_scene
    if scene == null or not "parallax_panel" in scene: return
    var command_path := output.path_join("command.json")
    if FileAccess.file_exists(command_path):
        var command = JSON.parse_string(FileAccess.get_file_as_string(command_path))
        if command is Dictionary and int(command.get("id",0)) > command_id:
            command_id = int(command.id)
            match command.get("action", ""):
                "release_focus":
                    var focus := scene.get_viewport().gui_get_focus_owner()
                    if focus != null: focus.release_focus()
                "focus_spin":
                    var spins: Array[Node] = scene.parallax_panel.find_children("*", "SpinBox", true, false)
                    for spin in spins:
                        if spin.is_visible_in_tree():
                            spin.get_line_edit().grab_focus()
                            spin.get_line_edit().select_all()
                            break
                "capture":
                    capture_pending = true
                    await scene.capture(output.path_join(str(command.get("name", "window.png"))))
                    capture_pending = false
    var focus := scene.get_viewport().gui_get_focus_owner()
    var state := {
        "ticks": ticks, "command_id":command_id, "capture_pending":capture_pending,
        "parallax":scene.parallax_panel.visible, "dof_panel":scene.dof_panel.visible,
        "hud":scene.hud.container.visible, "tour":scene.tour,
        "effects":scene.lighting.effects_enabled, "follow":scene.follow,
        "dof":scene.dof.enabled, "background":scene.background.visible,
        "time":scene.lighting.preset_id, "controls":scene.player.controls_enabled,
        "focus":str(focus.get_path()) if focus != null else "",
        "focus_type":focus.get_class() if focus != null else "",
        "dialogue":scene.hud.dialogue.visible, "preview":scene.parallax_preview.active,
        "camera":false,"camera_supported":false,"quit_dialog":false,"buttons":{},
        "viewport":[scene.get_viewport().size.x,scene.get_viewport().size.y],
        "mouse":[scene.get_viewport().get_mouse_position().x,scene.get_viewport().get_mouse_position().y]
    }
    if "experiment_panel" in scene:
        state.camera = scene.experiment_panel.visible
        state.camera_supported = true
    elif "variant_panel" in scene:
        state.camera = scene.variant_panel.visible
        state.camera_supported = true
    if "quit_dialog" in scene.hud: state.quit_dialog = scene.hud.quit_dialog.visible
    if "toolbar_buttons" in scene.hud:
        for id in scene.hud.toolbar_buttons:
            var button: Button = scene.hud.toolbar_buttons[id]
            if button.is_visible_in_tree():
                var center := scene.get_viewport().get_final_transform() * button.get_global_rect().get_center()
                state.buttons[id] = [center.x,center.y]
    var target := output.path_join("state.json")
    var file := FileAccess.open(target+".tmp",FileAccess.WRITE)
    file.store_string(JSON.stringify(state))
    file.close()
    DirAccess.rename_absolute(target+".tmp",target)
