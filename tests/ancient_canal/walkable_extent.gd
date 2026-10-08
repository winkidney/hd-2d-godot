extends SceneTree
## Headless physical traversal and camera projection; no visual acceptance.
const ENTRY := "res://scenes/ancient_canal.tscn"
const SIZE := Vector2i(1920,1080)
var scene: Node3D
var destination := "res://build/ancient-canal/walkable-width-20261007/extent.json"
var fingerprint := ""
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var traversals: Array[Dictionary] = []
var camera_cases: Array[Dictionary] = []

func _initialize() -> void:
    root.size = SIZE
    root.content_scale_size = SIZE
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--report="): destination = argument.trim_prefix("--report=")
        if argument.begins_with("--canal-fingerprint="): fingerprint = argument.trim_prefix("--canal-fingerprint=")
    call_deferred("run")

func check(passed: bool, label: String, detail: Dictionary = {}) -> void:
    checks.append({"id":label,"passed":passed,"detail":detail})
    if not passed:
        failures.append(label)
        print("WALKABLE_EXTENT_FAIL ",label," ",detail)

func point(value: Vector3) -> Array:
    return [value.x,value.y,value.z]

func settle(count := 12) -> void:
    for index in count: await physics_frame

func place(value: Vector3) -> void:
    scene.player.scripted_direction = Vector2.ZERO
    scene.player.position = value + Vector3.UP*.1
    scene.player.velocity = Vector3.ZERO
    await settle()
    # Teleport is test setup, not gameplay movement. Start every actual walk
    # from its supported camera pose instead of the previous distant fixture.
    scene.camera_update(0,true)

func projected_character() -> Dictionary:
    var actor: Node3D = scene.player
    var bounds: Array = actor.color_definitions[actor.facing].frames[actor.animation_frame].visible_bounds
    var right: Vector3 = scene.camera.global_basis.x
    right.y = 0.0
    right = right.normalized()
    var minimum := Vector2(INF,INF)
    var maximum := Vector2(-INF,-INF)
    var forward := true
    for pixel in [Vector2(bounds[0],bounds[1]),Vector2(bounds[2],bounds[1]),Vector2(bounds[2],bounds[3]),Vector2(bounds[0],bounds[3])]:
        var location: Vector3 = actor.global_position + right*(pixel.x-128.0+actor.sprite.offset.x)*actor.sprite.pixel_size + Vector3.UP*(128.0-pixel.y+actor.sprite.offset.y)*actor.sprite.pixel_size
        var projected: Vector2 = scene.camera.unproject_position(location)
        forward = forward and not scene.camera.is_position_behind(location)
        minimum = minimum.min(projected)
        maximum = maximum.max(projected)
    return {"in_frame":forward and minimum.x>=0 and minimum.y>=0 and maximum.x<=SIZE.x and maximum.y<=SIZE.y,"bounds":[minimum.x,minimum.y,maximum.x,maximum.y]}

func push_against_wall(label: String, start: Vector3, direction: Vector2, axis: int, wall: float, frames: int) -> void:
    await place(start)
    var initial: Vector3 = scene.player.position
    scene.player.scripted_direction = direction
    var maximum_floor_error := 0.0
    var grounded_frames := 0
    var beyond_old_edge := 0
    var camera_outside := 0
    var terminal_start := Vector3.ZERO
    for index in frames:
        await physics_frame
        scene.camera_update(1.0/60.0)
        var position: Vector3 = scene.player.position
        maximum_floor_error = maxf(maximum_floor_error,absf(position.y))
        if scene.player.is_on_floor(): grounded_frames += 1
        if absf(position.x)>13.0: beyond_old_edge += 1
        if index==frames-90: terminal_start = position
        if index%15==0 and not projected_character().in_frame: camera_outside += 1
    scene.player.scripted_direction = Vector2.ZERO
    await settle(3)
    var final: Vector3 = scene.player.position
    var wall_clearance: float = absf(final[axis]-wall)
    var stopped_distance := Vector2(final.x-terminal_start.x,final.z-terminal_start.z).length()
    var detail := {"start":point(initial),"end":point(final),"wall":wall,"wall_clearance_metres":wall_clearance,"last_90_frames_motion_metres":stopped_distance,"floor_error_metres":maximum_floor_error,"grounded_frames":grounded_frames,"frames":frames,"samples_beyond_old_edge":beyond_old_edge,"camera_outside_samples":camera_outside}
    traversals.append(detail.merged({"id":label}))
    check(wall_clearance>.30 and wall_clearance<.42,label+"_physical_boundary_stops_capsule",detail)
    check(stopped_distance<.005,label+"_continual_input_cannot_escape")
    check(maximum_floor_error<.015 and grounded_frames>=frames-2,label+"_feet_remain_on_bank")
    check(beyond_old_edge>90,label+"_uses_expanded_ground")
    check(camera_outside==0,label+"_default_follow_keeps_projected_character_inside")

func ground_seams() -> void:
    var banks: Array[AABB] = []
    var streets: Array[AABB] = []
    var surface_y: float = scene.layout.banks.surface_y
    var minimum_z: float = scene.layout.banks.min_z
    var maximum_z: float = scene.layout.banks.max_z
    for child in scene.world.get_children():
        # Repeated World.box() nodes receive Godot-generated names. Identify
        # actual ground shapes rather than relying on only the first name.
        for part in child.get_children():
            if child is StaticBody3D and part is CollisionShape3D and part.shape is BoxShape3D:
                var collision_bounds: AABB = part.global_transform*AABB(-part.shape.size/2,part.shape.size)
                if absf(collision_bounds.end.y-surface_y)<.001 and collision_bounds.position.y<surface_y-.1:
                    banks.append(collision_bounds)
            elif not child is StaticBody3D and part is MeshInstance3D:
                var visual_bounds: AABB = part.global_transform*part.get_aabb()
                if absf(visual_bounds.end.y-surface_y)<.001 and (visual_bounds.end.x<=-float(scene.layout.banks.outer_x)+.001 or visual_bounds.position.x>=float(scene.layout.banks.outer_x)-.001) and visual_bounds.position.z>=minimum_z-.001 and visual_bounds.end.z<=maximum_z+.001:
                    streets.append(visual_bounds)
    check(streets.size()==4 and banks.size()>=2,"real_bank_and_decorative_street_bounds_exist")
    for index in streets.size():
        var adjacent := false
        for bank in banks:
            var overlap: AABB = streets[index].intersection(bank)
            check(overlap.size.x*overlap.size.y*overlap.size.z<.0001,"street_"+str(index)+"_no_ground_volume_overlap_"+str(banks.find(bank)))
            if absf(streets[index].position.x-bank.end.x)<.001 or absf(streets[index].end.x-bank.position.x)<.001: adjacent = true
        check(adjacent,"street_"+str(index)+"_touches_actual_bank_edge")
    var background_items := 0
    for child in scene.farfield.layers.near_town.get_children():
        background_items += 1
        check(child.position.z<float(scene.layout.banks.min_z),"background_item_behind_playable_bank_"+str(background_items),{"position":point(child.position)})
    check(background_items==11,"six_background_houses_and_five_flat_willows_present")

func camera_edges() -> void:
    scene.player.paused = true
    for variant in ["F","W"]:
        check(scene.select_variant(variant),"select_default_camera_"+variant)
        for side in [-1.0,1.0]:
            for z in [9.0,float(scene.layout.banks.max_z)-.6]:
                await place(Vector3(side*25.0,0,z))
                scene.camera_update(0,true)
                check(scene.rig.supported_pose(),"supported_camera_at_outer_edge_"+variant+"_"+str(side)+"_"+str(z))
                for facing in range(4):
                    scene.player.direction_override = facing
                    for frame in [0,13,26]:
                        scene.player.frame_override = frame
                        scene.player.update_animation()
                        var projection := projected_character()
                        var label: String = variant+"_"+str(side)+"_z_"+str(z)+"_direction_"+str(facing)+"_frame_"+str(frame)
                        check(projection.in_frame,"projected_visible_character_"+label,projection)
                        camera_cases.append({"case":label,"foot":point(scene.player.position),"projected_alpha_bounds":projection.bounds,"camera":scene.rig.pose_diagnostics()})
    scene.player.direction_override = -1
    scene.player.frame_override = -1
    scene.player.paused = false

func run() -> void:
    if not destination.begins_with("res://build/ancient-canal/") or not destination.ends_with(".json"):
        print("WALKABLE_EXTENT_FAIL invalid report destination")
        quit(1)
        return
    scene = load(ENTRY).instantiate()
    root.add_child(scene)
    scene.frozen = true
    scene.player.controls_enabled = true
    scene.player.scripted_input = true
    await settle()
    check(not scene.settings_load_attempted,"user_settings_not_loaded")
    check(float(scene.layout.banks.outer_x)>=26.0,"expanded_lateral_playable_extent")
    check(DisplayServer.get_name()=="headless","headless_scope_only")
    ground_seams()
    for side in [-1.0,1.0]:
        await push_against_wall("lateral_"+str(side),Vector3(side*11.0,0,12.0),Vector2(side,0),0,side*float(scene.layout.banks.outer_x),460)
        for z in [float(scene.layout.banks.min_z),float(scene.layout.banks.max_z)]:
            await push_against_wall("end_"+str(side)+"_"+str(z),Vector3(side*24.0,0,-3 if z<0 else 7),Vector2(0,signf(z)),2,z,460)
    await camera_edges()
    var report := {"passed":failures.is_empty(),"entry":ENTRY,"runtime_fingerprint":fingerprint,"checks":checks,"failures":failures,"traversals":traversals,"camera_cases":camera_cases,"scope":"Headless actual CharacterBody3D collisions/grounding and Camera3D alpha-bounds projection. User performs visual validation; no rendered appearance or GPU acceptance claimed. Launch timing is recorded by the wrapper: OS.get_cmdline_args() may omit processed engine flags, so CLI token visibility does not determine whether fixed-fps was enabled.","display_backend":DisplayServer.get_name(),"fixed_fps_cli_token_visible":OS.get_cmdline_args().has("--fixed-fps"),"physics_hz":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale}
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
    var file := FileAccess.open(destination,FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  ")+"\n")
    print("WALKABLE_EXTENT_DONE passed=",report.passed," checks=",checks.size()," traversals=",traversals.size()," camera_cases=",camera_cases.size())
    scene.queue_free()
    await process_frame
    quit(0 if report.passed else 1)
