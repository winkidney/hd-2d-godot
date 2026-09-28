extends SceneTree

func _initialize() -> void:
    call_deferred("capture_preview")

func capture_preview() -> void:
    var scene = load("res://scenes/waystation.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    for i in range(150):
        await process_frame
    var ok: bool = await scene.capture("res://build/visual/first-look.png")
    print("PREVIEW_GPU ", RenderingServer.get_video_adapter_name())
    scene.queue_free()
    for i in range(4):
        await process_frame
    quit(0 if ok else 1)
