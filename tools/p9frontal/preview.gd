extends SceneTree
func _initialize() -> void:
    call_deferred("capture_views")
func capture_views() -> void:
    var scene = load("res://scenes/frontal_canal.tscn").instantiate()
    root.add_child(scene)
    scene.hud.container.hide()
    scene.dof.enabled = false
    scene.dof.apply()
    scene.clock_frozen = true
    scene.lighting.water.set_shader_parameter("motion",0.0)
    scene.player.set_physics_process(false)
    for id in ["F","W","O"]:
        for side in ["center","left","right"]:
            scene.player.position = scene.to_vector(scene.layout.view_anchors[side])
            scene.select_variant(id)
            for i in range(30): await process_frame
            await scene.capture("res://build/p9-frontal/preview/"+id+"-"+side+".png")
    quit(0)
