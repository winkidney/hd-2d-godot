extends SceneTree
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var scene = load("res://scenes/waystation.tscn").instantiate()
    root.add_child(scene)
    for i in range(120): await process_frame
    await scene.capture("res://build/p6p7/initial.png")
    scene.player.position = scene.to_vector(scene.layout.walkway.center)+Vector3(0,0.3,0)
    for i in range(180): await process_frame
    await scene.capture("res://build/p6p7/walkway-center.png")
    scene.dof_panel.show()
    await scene.capture("res://build/p6p7/controls.png")
    scene.queue_free()
    for i in range(6): await process_frame
    quit()
