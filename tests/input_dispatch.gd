extends SceneTree
## Input regression for all interactive scenes. Keys use the real dispatch chain.
## --script res://tests/input_dispatch.gd -- --ignore-user-settings
## --input-scene=res://scenes/frontal_canal.tscn optionally narrows the matrix.
## Button checks emit the public pressed signal and are labelled separately.
const SCENES := ["res://scenes/waystation.tscn", "res://scenes/reference_scene.tscn",
    "res://scenes/reference_scene_graybox.tscn", "res://scenes/frontal_canal.tscn"]
const ACTION_KEYS := [KEY_E,KEY_T,KEY_1,KEY_2,KEY_3,KEY_G,KEY_V,KEY_F,KEY_B,KEY_O,KEY_P,KEY_K,KEY_H,KEY_J,KEY_C]
var scene: Node3D
var audit_scene_path := ""
var output := "res://build/input-dispatch/report.json"
var paths: Array = SCENES.duplicate()
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var complete := false

func _initialize() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--input-output="): output = arg.trim_prefix("--input-output=")
        if arg.begins_with("--input-scene="): paths = [arg.trim_prefix("--input-scene=")]
    root.size = Vector2i(1920,1080)
    root.content_scale_size = Vector2i(1920,1080)
    root.gui_embed_subwindows = true
    Input.use_accumulated_input = false
    call_deferred("run")

func wait_frames(count: int = 2) -> void:
    for index in count: await process_frame

func key_event(code: Key, pressed: bool, echo: bool = false, modifier := "", unicode_value := 0, window_id := 0) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.physical_keycode = code
    event.pressed = pressed
    event.echo = echo
    event.unicode = unicode_value
    event.ctrl_pressed = modifier == "ctrl"
    event.alt_pressed = modifier == "alt"
    event.meta_pressed = modifier == "meta"
    event.shift_pressed = modifier == "shift"
    event.window_id = window_id
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    await wait_frames()

func tap(code: Key, modifier := "", unicode_value := 0, window_id := 0) -> void:
    await key_event(code,true,false,modifier,unicode_value,window_id)
    await key_event(code,false,false,modifier,unicode_value,window_id)

func check(ok: bool, label: String, details: Dictionary = {}) -> void:
    var name := audit_scene_path.get_file()+": "+label
    checks.append({"name":name,"passed":ok,"details":details})
    if not ok: failures.append(name)
    print("INPUT_DISPATCH_", "PASS " if ok else "FAIL ",name," ",JSON.stringify(details))
    save_report()

func save_report() -> void:
    var absolute := ProjectSettings.globalize_path(output)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var file := FileAccess.open(absolute,FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify({"schema":1,"passed":complete and failures.is_empty(),
            "complete":complete,"checks":checks,"failures":failures,"scenes":paths,
            "engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),
            "input_boundary":"Input.parse_input_event with press/release/echo, native GUI focus and embedded PopupMenu.",
            "button_boundary":"Button.pressed signal; not a physical mouse click. Separate real-window mouse tests are required.",
            "scope":"Runtime dispatch only. Headless cannot reproduce the editor host's F8 stop shortcut or prove physical desktop key delivery."},"  ")+"\n")

func snapshot() -> Dictionary:
    var camera_panel: Control = scene.camera_tuning_panel()
    return {"period":scene.lighting.preset_id,"tour":scene.tour,"fx":scene.lighting.effects_enabled,
        "follow":scene.follow,"dof":scene.dof.enabled,"background":scene.background.visible,
        "hud":scene.hud.container.visible,"dialogue":scene.hud.dialogue.visible,
        "dof_panel":scene.dof_panel.visible,"parallax_panel":scene.parallax_panel.visible,
        "camera_panel":camera_panel!=null and camera_panel.visible,"quit_dialog":scene.hud.quit_dialog.visible}

func reset_ui() -> void:
    scene.close_tuning()
    scene.hud.close_dialogue()
    scene.hud.quit_dialog.hide()
    scene.hud.container.show()
    root.gui_release_focus()
    scene.tour = false
    scene.sync_input_lock()
    await wait_frames()

func panel_keys() -> void:
    await tap(KEY_P)
    check(scene.parallax_panel.visible and not scene.player.controls_enabled,"P opens parallax and locks movement")
    await key_event(KEY_P,true,true)
    await key_event(KEY_P,false)
    check(scene.parallax_panel.visible,"echo and release do not toggle again")
    await tap(KEY_P)
    check(not scene.panels_open() and scene.player.controls_enabled,"second P closes once")
    await tap(KEY_P)
    await tap(KEY_O)
    check(scene.dof_panel.visible and not scene.parallax_panel.visible,"O replaces P exclusively")
    await tap(KEY_P)
    check(scene.parallax_panel.visible and not scene.dof_panel.visible,"P replaces O exclusively")
    await reset_ui()
    await tap(KEY_C)
    var panel: Control = scene.camera_tuning_panel()
    if panel==null:
        check(not scene.panels_open(),"C is a no-op without camera variants")
    else:
        check(panel.visible and not scene.player.controls_enabled,"C opens camera panel and locks movement")
        await tap(KEY_P)
        check(scene.parallax_panel.visible and not panel.visible,"P replaces C exclusively")
        await tap(KEY_C)
        check(panel.visible and not scene.parallax_panel.visible,"C replaces P exclusively")
    await reset_ui()

func modifiers_and_legacy() -> void:
    var before := snapshot()
    for modifier in ["ctrl","alt","meta","shift"]:
        for code in ACTION_KEYS+[KEY_ESCAPE]:
            await tap(code,modifier)
            check(snapshot()==before,modifier+"+"+OS.get_keycode_string(code)+" does not trigger plain action")
    for code in [KEY_F2,KEY_F3,KEY_F4,KEY_F5,KEY_F6,KEY_F7,KEY_F8,KEY_F9,KEY_F12]:
        await tap(code)
        check(snapshot()==before,OS.get_keycode_string(code)+" is not a game action")
    await tap(KEY_TAB)
    check(snapshot()==before,"Tab does not hide gameplay UI")

func plain_actions() -> void:
    var properties := {KEY_G:"tour",KEY_V:"fx",KEY_F:"follow",KEY_B:"dof",KEY_K:"background",KEY_H:"hud"}
    for code in properties:
        var before := snapshot()
        var property: String = properties[code]
        await tap(code)
        check(bool(snapshot()[property])!=bool(before[property]),OS.get_keycode_string(code)+" activates its documented toggle")
        var activated := snapshot()
        await key_event(code,true,true)
        await key_event(code,false)
        check(snapshot()==activated,OS.get_keycode_string(code)+" echo does not repeat toggle")
        await tap(code)
        check(snapshot()==before,OS.get_keycode_string(code)+" second press restores prior state")
    for pair in [[KEY_1,"dusk"],[KEY_2,"night"],[KEY_3,"day"]]:
        await tap(pair[0])
        check(scene.lighting.preset_id==pair[1],"plain "+OS.get_keycode_string(pair[0])+" selects "+pair[1])
    for period in ["dusk","night","day"]:
        await tap(KEY_T)
        check(scene.lighting.preset_id==period,"plain T cycles to "+period)
    await reset_ui()

func text_editing() -> void:
    await tap(KEY_P)
    var spins: Array = scene.parallax_panel.find_children("*","SpinBox",true,false)
    check(not spins.is_empty(),"parallax exposes a real SpinBox")
    if spins.is_empty(): return
    var edit: LineEdit = spins[0].get_line_edit()
    edit.grab_focus()
    edit.select_all()
    await wait_frames()
    check(root.gui_get_focus_owner()==edit,"SpinBox LineEdit owns real GUI focus")
    var before := snapshot()
    for code in ACTION_KEYS:
        await tap(code,"",int(code))
        check(snapshot()==before,"editing "+OS.get_keycode_string(code)+" does not dispatch scene action")
    await tap(KEY_A,"ctrl",97)
    await tap(KEY_2,"",50)
    check(edit.text=="2" and snapshot()==before,"Ctrl+A and numeric entry stay in LineEdit",{"text":edit.text})
    await tap(KEY_LEFT)
    await tap(KEY_RIGHT)
    check(snapshot()==before and not scene.player.controls_enabled,"editing arrows do not enable walking")
    await tap(KEY_TAB)
    check(scene.parallax_panel.visible and scene.hud.container.visible,"Tab stays within active panel")
    # Deliberately release GUI focus: the documented T action remains available.
    root.gui_release_focus()
    var period: String = scene.lighting.preset_id
    await tap(KEY_T)
    check(scene.lighting.preset_id!=period and scene.parallax_panel.visible,"T remains usable with panel open outside text editing")
    await reset_ui()
    if audit_scene_path!=SCENES[3]: return
    await tap(KEY_C)
    for lens_key in ["radius","fov"]:
        var spin: SpinBox = scene.variant_panel.lens_spins[lens_key]
        edit = spin.get_line_edit()
        edit.grab_focus()
        edit.select_all()
        await wait_frames()
        before = snapshot()
        check(root.gui_get_focus_owner()==edit,lens_key+" lens LineEdit owns real GUI focus")
        for code in ACTION_KEYS:
            await tap(code,"",int(code))
            check(snapshot()==before,lens_key+" editing "+OS.get_keycode_string(code)+" does not dispatch scene action")
        await tap(KEY_A,"ctrl",97)
        var typed := "28" if lens_key=="radius" else "42"
        for character in typed:
            var code := character.unicode_at(0)
            await tap(code,"",code)
        await tap(KEY_ENTER)
        check(is_equal_approx(float(scene.rig.lens_snapshot()[lens_key]),float(typed)),lens_key+" Enter commits typed number to real lens")
        await tap(KEY_TAB)
        check(scene.variant_panel.visible and scene.hud.container.visible,lens_key+" Tab retains camera panel")
    await reset_ui()

func escape_stack() -> void:
    await tap(KEY_P)
    scene.parallax_panel.preview_button.pressed.emit()
    await wait_frames()
    check(scene.parallax_preview.active,"preview button signal starts comparison")
    var popup: PopupMenu = scene.parallax_panel.preset.get_popup()
    scene.parallax_panel.preset.show_popup()
    await wait_frames()
    check(popup.visible,"real embedded preset popup is open")
    await tap(KEY_ESCAPE,"",0,popup.get_window_id())
    check(not popup.visible and scene.parallax_preview.active and scene.parallax_panel.visible,"Esc dismisses popup before preview or panel")
    await tap(KEY_ESCAPE)
    check(not scene.parallax_preview.active and scene.parallax_panel.visible and not scene.hud.quit_dialog.visible,"next Esc stops preview only")
    await tap(KEY_ESCAPE)
    check(not scene.panels_open() and not scene.hud.quit_dialog.visible and scene.player.controls_enabled,"next Esc closes panel only")
    scene.hud.show_dialogue({"title":"Input regression","text":"Runtime-only fixture."})
    scene.sync_input_lock()
    await tap(KEY_ESCAPE)
    check(not scene.hud.dialogue.visible and not scene.hud.quit_dialog.visible,"Esc closes dialogue without exit request")
    await tap(KEY_ESCAPE)
    check(scene.hud.quit_dialog.visible and not scene.player.controls_enabled,"bare Esc asks for confirmation and locks movement")
    check(scene.hud.quit_dialog.gui_get_focus_owner()==scene.hud.quit_dialog.get_cancel_button(),"quit confirmation defaults to Keep playing")
    await tap(KEY_ENTER,"",0,scene.hud.quit_dialog.get_window_id())
    check(not scene.hud.quit_dialog.visible and scene.player.controls_enabled,"default Enter cancels confirmation without quitting")
    await tap(KEY_ESCAPE)
    check(scene.hud.quit_dialog.visible and scene.hud.quit_dialog.gui_get_focus_owner()==scene.hud.quit_dialog.get_cancel_button(),"reopened confirmation still defaults to Keep playing")
    await key_event(KEY_ESCAPE,true,true,"",0,scene.hud.quit_dialog.get_window_id())
    await key_event(KEY_ESCAPE,false,false,"",0,scene.hud.quit_dialog.get_window_id())
    check(scene.hud.quit_dialog.visible,"echo cannot dismiss or accept exit confirmation")
    await tap(KEY_ESCAPE,"",0,scene.hud.quit_dialog.get_window_id())
    check(not scene.hud.quit_dialog.visible and scene.player.controls_enabled,"Esc cancels confirmation without quitting")
    await reset_ui()

func button_signals() -> void:
    for id in ["dof","parallax","camera"]:
        if not scene.hud.toolbar_buttons.has(id):
            check(id=="camera" and scene.camera_tuning_panel()==null,"optional toolbar "+id+" matches scene")
            continue
        var item: Button = scene.hud.toolbar_buttons[id]
        if id=="camera" and scene.camera_tuning_panel()==null:
            check(not item.visible or item.disabled,"camera toolbar hidden or disabled without variants")
            continue
        await reset_ui()
        item.pressed.emit()
        await wait_frames()
        var panel: Control = scene.dof_panel if id=="dof" else (scene.parallax_panel if id=="parallax" else scene.camera_tuning_panel())
        check(panel.visible and not scene.player.controls_enabled,"toolbar "+id+" pressed signal opens panel")
        item.pressed.emit()
        await wait_frames()
        check(not panel.visible,"toolbar "+id+" pressed signal closes panel")
    await reset_ui()
    var quit_button: Button = scene.hud.toolbar_buttons.quit
    quit_button.pressed.emit()
    await wait_frames()
    check(scene.hud.quit_dialog.visible,"quit toolbar pressed signal requires confirmation")
    check(scene.hud.quit_dialog.gui_get_focus_owner()==scene.hud.quit_dialog.get_cancel_button(),"toolbar quit confirmation also defaults to Keep playing")
    scene.hud.quit_dialog.get_cancel_button().pressed.emit()
    await wait_frames()
    check(not scene.hud.quit_dialog.visible,"cancel button signal preserves running scene")
    await reset_ui()

func route_lock() -> void:
    if audit_scene_path==SCENES[0]: return
    var running_key := "route_running" if audit_scene_path==SCENES[3] else "experiment_route_running"
    var cancel_key := "route_cancelled" if audit_scene_path==SCENES[3] else "experiment_route_cancelled"
    scene.set(running_key,true)
    scene.set(cancel_key,false)
    var before := snapshot()
    for code in ACTION_KEYS:
        await tap(code)
        check(snapshot()==before,"route prevents "+OS.get_keycode_string(code)+" shortcut")
    for modifier in ["ctrl","alt","meta","shift"]:
        await tap(KEY_ESCAPE,modifier)
        check(not bool(scene.get(cancel_key)) and not scene.hud.quit_dialog.visible,modifier+"+Esc does not cancel route or request exit")
    await key_event(KEY_ESCAPE,true,true)
    await key_event(KEY_ESCAPE,false)
    check(not bool(scene.get(cancel_key)),"Esc echo and release do not cancel route")
    root.close_requested.emit()
    await wait_frames()
    check(not scene.hud.quit_dialog.visible and not bool(scene.get(cancel_key)),"window close signal cannot interrupt route")
    await tap(KEY_ESCAPE)
    check(bool(scene.get(cancel_key)) and not scene.hud.quit_dialog.visible,"plain Esc cancels route without quit dialog")
    scene.set(running_key,false)
    scene.set(cancel_key,false)
    await reset_ui()

func run() -> void:
    save_report()
    if "--ignore-user-settings" not in OS.get_cmdline_user_args():
        check(false,"--ignore-user-settings is required; refusing to read everyday preferences")
        complete = true
        save_report()
        quit(2)
        return
    for path in paths:
        audit_scene_path = path
        var close_connections := root.close_requested.get_connections().size()
        scene = load(path).instantiate()
        root.add_child(scene)
        check(not scene.panels_open() and scene.player.controls_enabled,"scene starts with panels closed and movement enabled")
        await wait_frames(5)
        check(not scene.panels_open() and scene.player.controls_enabled,"initial process frames preserve usable controls")
        check(root.close_requested.get_connections().size()==close_connections+1,"scene installs one close-request handler")
        scene.clock_frozen = true
        if not scene.has_method("camera_tuning_panel"):
            check(false,"safe input contract installed")
        else:
            await panel_keys()
            await modifiers_and_legacy()
            await plain_actions()
            await text_editing()
            await escape_stack()
            await button_signals()
            await route_lock()
        scene.queue_free()
        scene = null
        await wait_frames(5)
        check(root.close_requested.get_connections().size()==close_connections,"freeing scene removes its close-request handler")
    complete = true
    save_report()
    print("INPUT_DISPATCH_DONE checks=",checks.size()," failures=",failures.size())
    quit(0 if failures.is_empty() else 1)
