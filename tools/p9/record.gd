extends SceneTree
var scene: Node3D
func _initialize() -> void:
    call_deferred("record")
func record() -> void:
    scene=load("res://scenes/reference_scene.tscn").instantiate()
    root.add_child(scene)
    scene.player.scripted_input=true
    scene.hud.container.hide()
    scene.follow=true
    for i in range(60): await physics_frame
    var stops=[Vector3(3,1.2,3.5),Vector3(-20,1.2,3.5),Vector3(22,1.2,3.5),Vector3(2,1.2,.3),Vector3(2,4,-5.8),Vector3(5.4,4,-6.8)]
    for i in range(stops.size()):
        if i==2: scene.lighting.apply_preset("day")
        if i==4: scene.lighting.apply_preset("night")
        var reached=false
        for frame in range(1200):
            var delta: Vector3=stops[i]-scene.player.position
            delta.y=0
            if delta.length()<.18:
                reached=true
                break
            scene.player.scripted_direction=Vector2(delta.x,delta.z).normalized()
            await physics_frame
        if not reached:
            push_error("Recording route blocked")
            quit(1)
            return
    scene.player.scripted_direction=Vector2.ZERO
    for frame in range(90): await physics_frame
    print("P9_RECORDING_ROUTE_COMPLETE")
    quit(0)
