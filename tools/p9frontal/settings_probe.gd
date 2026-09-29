extends SceneTree
## Run separate processes with the same isolated XDG_DATA_HOME.
## --script res://tools/p9frontal/settings_probe.gd -- --save|--load|--restore-defaults
## Do not pass --frontal-* or --ignore-user-settings: this probes normal loading.
const IDS := ["F", "W", "O"]
const STRENGTHS := [0.4, 0.8, 1.2]
const FOLLOW_GAINS := [0.6, 0.7, 0.8]
var scene: Node3D
var mode := ""
var output := "res://build/p9-frontal/settings"
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var records: Dictionary = {}

func _initialize() -> void:
    var modes: Array[String] = []
    for arg in OS.get_cmdline_user_args():
        if arg in ["--save", "--load", "--restore-defaults"]:
            modes.append(arg.trim_prefix("--"))
        elif arg.begins_with("--probe-output="):
            output = arg.trim_prefix("--probe-output=")
    if modes.size()!=1:
        push_error("Choose exactly one mode: --save, --load, or --restore-defaults.")
        quit(2)
        return
    mode = modes[0]
    call_deferred("run_probe")

func check(ok: bool, label: String) -> void:
    checks.append({"name":label,"passed":ok})
    if not ok:
        failures.append(label)
    print("FRONTAL_SETTINGS_", "PASS " if ok else "FAIL ", label)

func run_probe() -> void:
    output = ProjectSettings.globalize_path(output)
    if DirAccess.make_dir_recursive_absolute(output)!=OK:
        push_error("Cannot create the settings probe evidence directory.")
        quit(2)
        return
    var packed := load("res://scenes/frontal_canal.tscn") as PackedScene
    if packed==null:
        check(false,"frontal scene loads")
        await finish()
        return
    scene = packed.instantiate() as Node3D
    root.add_child(scene)
    for frame in range(30):
        await process_frame
    check(scene.should_load_preferences(),"normal preference loading enabled")
    check(scene.settings_load_attempted,"startup attempted F preference loading")
    if not scene.should_load_preferences():
        await finish()
        return
    for index in IDS.size():
        var id: String = IDS[index]
        check(scene.select_variant(id),"select "+id)
        var expected_strength: float = STRENGTHS[index]
        var expected_gain: float = FOLLOW_GAINS[index]
        if mode=="save":
            scene.reset_variant()
            check(scene.parallax.change("mode","artistic").is_empty(),id+" artistic mode")
            check(scene.parallax.change("global_strength",expected_strength).is_empty(),id+" set strength")
            check(scene.parallax.change("horizontal_follow_gain",expected_gain).is_empty(),id+" set follow gain")
            check(scene.parallax_store.save_settings(scene.parallax),id+" settings saved")
        elif mode=="restore-defaults":
            scene.reset_variant()
            check(scene.parallax_store.save_settings(scene.parallax),id+" defaults saved")
            expected_strength = float(scene.parallax.defaults.global_strength)
            expected_gain = float(scene.parallax.defaults.horizontal_follow_gain)
        else:
            # No explicit load call here: scene startup / first selection must load.
            check(bool(scene.loaded_settings.get(id,false)),id+" normal load path visited")
            check(scene.parallax_store.message=="Loaded preferences.",id+" normal load succeeded")
        var snapshot: Dictionary = scene.parallax.snapshot()
        var expected_mode := "natural" if mode=="restore-defaults" else "artistic"
        check(snapshot.mode==expected_mode,id+" loaded mode matches")
        check(is_equal_approx(float(snapshot.global_strength),expected_strength),id+" strength matches")
        check(is_equal_approx(float(snapshot.horizontal_follow_gain),expected_gain),id+" follow gain matches")
        check(scene.preferences_path=="user://settings/frontal-canal-"+id+".cfg",id+" independent settings path")
        var config := ConfigFile.new()
        var disk_ok := config.load(scene.preferences_path)==OK
        check(disk_ok,id+" settings file readable")
        if disk_ok:
            check(is_equal_approx(float(config.get_value("parallax","global_strength",-1)),expected_strength),id+" disk strength matches")
            check(is_equal_approx(float(config.get_value("parallax","horizontal_follow_gain",-1)),expected_gain),id+" disk follow matches")
            check(config.get_value("meta","layout_id","")==scene.parallax.layout_id,id+" disk layout identity matches")
        records[id] = {"snapshot":snapshot,"file":scene.preferences_path.get_file(),
            "file_sha256":FileAccess.get_sha256(scene.preferences_path) if disk_ok else "",
            "automatic_load":mode=="load","message":scene.parallax_store.message}
    for id in IDS:
        check(scene.select_variant(id),"revisit "+id)
        var snapshot: Dictionary = scene.parallax.snapshot()
        check(snapshot==records[id].snapshot,id+" revisiting preserves its own values")
    await finish()

func finish() -> void:
    var report := {"schema":1,"mode":mode,"passed":failures.is_empty(),
        "checks":checks,"failures":failures,"variants":records,
        "engine":Engine.get_version_info().string,"utc":Time.get_datetime_string_from_system(true),
        "isolation":"Run save/load/restore-defaults with the same isolated XDG_DATA_HOME; files are only user://settings/frontal-canal-{F,W,O}.cfg."}
    var path := output.path_join(mode+"-report.json")
    var file := FileAccess.open(path,FileAccess.WRITE)
    if file==null:
        failures.append("report write failed")
        push_error("Could not write settings probe report.")
    else:
        file.store_string(JSON.stringify(report,"  ")+"\n")
        file.close()
    print("FRONTAL_SETTINGS_DONE mode=",mode," checks=",checks.size()," failures=",failures.size())
    if is_instance_valid(scene):
        scene.queue_free()
        for frame in range(4):
            await process_frame
    quit(0 if failures.is_empty() else 1)
