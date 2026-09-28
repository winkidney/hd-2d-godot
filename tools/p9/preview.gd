extends SceneTree
func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    for variant in ["graybox","final"]:
        var path := "res://scenes/reference_scene_graybox.tscn" if variant == "graybox" else "res://scenes/reference_scene.tscn"
        var scene=load(path).instantiate()
        root.add_child(scene)
        scene.follow=false
        scene.hud.container.hide()
        for frame in range(120): await RenderingServer.frame_post_draw
        await scene.capture("res://build/p9/"+variant+"-preview.png")
        if variant == "final":
            scene.lighting.apply_preset("day")
            for frame in range(120): await RenderingServer.frame_post_draw
            await scene.capture("res://build/p9/day-preview.png")
        scene.queue_free()
        for frame in range(4): await process_frame
    quit()
