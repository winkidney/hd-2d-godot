extends SceneTree
func _initialize() -> void:
    call_deferred("probe")
func probe() -> void:
    var scene = load("res://scenes/frontal_canal.tscn").instantiate()
    root.add_child(scene)
    var result := {}
    var passed := true
    for id in ["F","W","O"]:
        scene.select_variant(id)
        result[id] = await load("res://tests/p9frontal/route.gd").run(scene,"res://build/p9-frontal/route-probe",false)
        passed = passed and result[id].passed
    var file := FileAccess.open("res://build/p9-frontal/route-probe/report.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"passed":passed,"routes":result},"  "))
    file.close()
    print("ROUTE_PROBE ",passed)
    quit(0 if passed else 1)
