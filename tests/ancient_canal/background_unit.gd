extends SceneTree
## Independent camera projections, continuous wind, and actual collider queries.
## Headless only; no editor import, GPU capture, or user setting writes.
const Parallax = preload("res://scripts/ancient_canal/parallax.gd")
const Background = preload("res://scripts/ancient_canal/background.gd")
const World = preload("res://scripts/ancient_canal/world.gd")
const Rig = preload("res://scripts/frontal_canal/camera.gd")
var checks := 0
var failures: Array[String] = []
var projection_samples := 0
var max_projection_error := 0.0

class Backdrop extends Node3D:
    var layers: Dictionary = {}

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures.append(label)
        print("CANAL_BACKGROUND_FAIL ", label)

func profile_checks() -> void:
    var controller := Parallax.new()
    check(controller.snapshot() == controller.defaults_snapshot(), "new profile exposes canonical defaults without configuration")
    check(controller.snapshot().size() == 9, "saved profile has exactly nine flat fields")
    for id in Parallax.IDS: check(is_equal_approx(controller.effective(id),1.0),"natural ignores art gain " + id)
    var copy := controller.snapshot()
    copy.near_town = 2.0
    check(is_equal_approx(controller.snapshot().near_town,.95),"snapshot is detached")
    for key in controller.snapshot():
        var invalid: Array = [null, true, [], {}, NAN, INF, -INF, -0.01, 2.01, "0.5"]
        if key == "mode": invalid = [null,true,1,{},[],"other"]
        if key == "transition_time": invalid.append(1.01)
        for value in invalid:
            var candidate := controller.snapshot()
            candidate[key] = value
            var before := controller.snapshot()
            check(not controller.apply_snapshot(candidate),"invalid complete profile rejects " + key + " " + str(value))
            check(controller.snapshot() == before,"invalid apply is atomic " + key)
    var missing := controller.snapshot()
    missing.erase("near_town")
    check(not controller.apply_snapshot(missing),"missing layer rejects")
    var extra := controller.snapshot()
    extra["unknown"] = .5
    check(not controller.apply_snapshot(extra),"unknown field rejects")
    controller.change("mode","artistic")
    controller.change("global_strength",2.0)
    controller.change("near_town",2.0)
    check(is_equal_approx(controller.profile.requested("near_town"),4.0) and is_equal_approx(controller.effective("near_town"),2.0),"art product caps at two")
    controller.reset_all()
    check(controller.snapshot() == controller.defaults_snapshot(),"reset restores independent canonical profile")

func projection_checks() -> void:
    root.size = Vector2i(1920,1080)
    var camera := Camera3D.new()
    root.add_child(camera)
    camera.current = true
    var virtual_camera := Camera3D.new()
    root.add_child(virtual_camera)
    var rig := Rig.new()
    var spawn := Vector3(-5,.15,5)
    rig.configure(camera,{"target":[.5,1.5,0],"far":320},spawn)
    var backdrop := Backdrop.new()
    root.add_child(backdrop)
    var anchors: Dictionary = {}
    var index := 0
    for id in Parallax.IDS:
        var layer := Node3D.new()
        backdrop.add_child(layer)
        layer.position = Vector3(index*.8,0,-index*2)
        var mesh := MeshInstance3D.new()
        mesh.mesh = BoxMesh.new()
        mesh.position = Vector3(-8+index*4,-2+index*2,-25-index*25)
        layer.add_child(mesh)
        anchors[id] = mesh.global_position
        backdrop.layers[id] = layer
        index += 1
    var controller := Parallax.new()
    controller.configure(camera,rig,backdrop)
    controller.change("mode","artistic")
    for id in Parallax.IDS: controller.change(id,1.0)
    # Exercise the shared projection math at the two fixed Ancient view types.
    # Ancient controller centering and map-edge limits have separate coverage.
    for variant in ["F","W"]:
        rig.select_variant(variant,spawn)
        for radius in [18.0,45.0]:
            for fov in [25.0,60.0]:
                rig.set_lens("radius",radius)
                rig.set_lens("fov",fov)
                for yaw in [0.0]:
                    rig.set_test_yaw(yaw)
                    for ratio in [0.0,1.0,2.0]:
                        controller.change("global_strength",ratio)
                        for dx in [-20.0,20.0]:
                            rig.set_offset(Vector3(dx,0,-1.5))
                            controller.update(0.0,true)
                            virtual_camera.set_perspective(camera.fov,camera.near,camera.far)
                            virtual_camera.global_transform = camera.global_transform
                            virtual_camera.global_position -= Vector3.RIGHT*dx
                            for id in Parallax.IDS:
                                var natural := camera.unproject_position(anchors[id]).x
                                var stationary := virtual_camera.unproject_position(anchors[id]).x
                                var expected: float = stationary+float(ratio)*(natural-stationary)
                                var actual := camera.unproject_position(controller.layer_point(id)).x
                                var error := absf(actual-expected)
                                projection_samples += 1
                                max_projection_error = maxf(max_projection_error,error)
                                check(error<.1,"independent projection " + str([variant,radius,fov,yaw,ratio,dx,id,error]))
                            var transforms: Dictionary = {}
                            for id in Parallax.IDS: transforms[id] = backdrop.layers[id].global_transform
                            controller.update(0.0,true)
                            for id in Parallax.IDS:
                                check(backdrop.layers[id].global_transform.is_equal_approx(transforms[id]),"absolute offset has no drift " + id)
    controller.change("mode","natural")
    controller.update(0.0,true)
    for id in Parallax.IDS:
        check(backdrop.layers[id].global_transform.is_equal_approx(controller.states[id].base),"natural restores authored transform " + id)
    controller.change("mode","artistic")
    camera.fov += 1.0
    controller.update(0.0,true)
    check(not controller.compatible,"external camera mutation triggers fallback")
    for id in Parallax.IDS:
        check(backdrop.layers[id].global_transform.is_equal_approx(controller.states[id].base),"fallback restores natural layer " + id)
    backdrop.free()
    camera.free()
    virtual_camera.free()

func wind_checks() -> void:
    var background := Background.new()
    root.add_child(background)
    for layer in range(2):
        var node := Node3D.new()
        background.add_child(node)
        var position := Vector3(-22,15,-160) if layer==0 else Vector3(90,17,-250)
        node.position = position
        background.clouds.append({"node":node,"origin":position,"layer":layer,"span":240.0 if layer==0 else 400.0})
    background.advance(20.0)
    var positions: Array = [background.clouds[0].node.position,background.clouds[1].node.position]
    background.set_cloud_wind(true,3.0,.0)
    background.advance(0.0)
    for index in range(2): check(background.clouds[index].node.position==positions[index],"speed change keeps continuous phase " + str(index))
    background.set_cloud_wind(false,3.0,.0)
    background.advance(50.0)
    for index in range(2): check(background.clouds[index].node.position==positions[index],"wind disabled freezes position " + str(index))
    background.set_cloud_wind(true,3.0,.0)
    background.advance(1.0)
    check(is_equal_approx(background.clouds[0].node.position.x,positions[0].x+3.0),"resume integrates new velocity from old phase")
    check(background.clouds[1].node.position==positions[1],"zero far wind freezes far cloud without jump")
    background.free()

func collision_and_layout_checks() -> void:
    var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/ancient-canal/layout.json"))
    check(layout.streetlamps.size()==6,"exactly six streetlamp definitions")
    check(is_equal_approx(layout.camera.far,320.0) and World.vec(layout.camera.target).is_equal_approx(Vector3(.5,1.5,0)),"far horizon and composition target")
    var world := World.new()
    root.add_child(world)
    world.configure(layout,true)
    var final_world := World.new()
    root.add_child(final_world)
    final_world.configure(layout,false)
    final_world.position.x = 100.0
    var helper := final_world.get_node("DockFloor")
    check(helper.get_child_count()==1 and helper.get_child(0) is CollisionShape3D,"final dock helper retains collision and has no mesh")
    check(world.get_node("DockFloor").get_child_count()==2,"greybox dock helper remains visible")
    check(world.streetlamp_definitions.size()==6 and world.lantern_positions.size()==6,"six streetlamps and six hanging lanterns are independent")
    var shadows := 0
    for lamp in world.streetlamp_definitions:
        if lamp.cast_shadow: shadows += 1
        check(is_equal_approx(lamp.light_position[1],float(lamp.foot_position[1])+2.2),"lamp light is paper centre " + lamp.id)
        var pole := world.get_node(lamp.id)
        check(pole is StaticBody3D and pole.get_child(0).shape is CylinderShape3D,"real cylinder body " + lamp.id)
        check(is_equal_approx(pole.get_child(0).shape.radius,.12) and is_equal_approx(pole.get_child(0).shape.height,2.6),"pole collider dimensions " + lamp.id)
        for point in layout.route:
            check(Vector2(float(point[0])-pole.position.x,float(point[2])-pole.position.z).length()>.5,"lamp avoids route waypoint " + lamp.id)
    check(shadows==2,"exactly two new lamp shadow casters")
    var collision_count := world.find_children("*","CollisionShape3D",true,false).size()
    var background := Background.new()
    root.add_child(background)
    background.configure(world,layout)
    var expected_counts := {"near_town":11,"far_town":9,"near_hills":1,"far_mountains":1,"near_clouds":4,"far_clouds":4}
    check(background.layers.size()==6,"all six actual layers configured")
    for id in expected_counts:
        check(background.layers[id].get_child_count()==expected_counts[id],"actual model/card count " + id)
    check(world.find_children("*","CollisionShape3D",true,false).size()==collision_count,"background never expands playable collision")
    check(world.water.mesh.size.is_equal_approx(Vector2(340,5.2)) and is_equal_approx(world.water.position.z,2.5),"continuous water spans rear horizon to south background")
    south_foundation_checks(world,layout)
    check(background.layers.near_hills.get_child(0).position.is_equal_approx(Vector3(0,-2,-67)),"near hill recipe placement")
    check(background.layers.far_mountains.get_child(0).scale.is_equal_approx(Vector3(.44,.45,.30)),"far mountains reuse non-snowy middle ridge")
    for id in ["day","dusk","night"]:
        background.apply_preset(id)
        check(background.profile_id==id,"background accepts lighting palette " + id)
    background.free()
    await physics_frame
    await physics_frame
    var space := root.world_3d.direct_space_state
    for lamp in world.streetlamp_definitions:
        var query := PhysicsPointQueryParameters3D.new()
        query.position = World.vec(lamp.foot_position)+Vector3.UP*1.0
        var hits := space.intersect_point(query)
        check(not hits.is_empty(),"physics query hits lamp pillar " + lamp.id)
    world.free()
    final_world.free()

func south_foundation_checks(world: Node3D, layout: Dictionary) -> void:
    var ground: Array[AABB] = []
    for node in world.get_children():
        var found_collision := false
        for child in node.get_children():
            if child is CollisionShape3D and child.shape is BoxShape3D:
                var size: Vector3 = child.shape.size
                var bounds: AABB = child.global_transform * AABB(-size/2,size)
                if is_equal_approx(bounds.end.y,0.0) and is_equal_approx(bounds.size.y,1.0):
                    ground.append(bounds)
                    found_collision = true
        if found_collision: continue
        for child in node.get_children():
            if child is MeshInstance3D and child.mesh is BoxMesh:
                var bounds: AABB = child.global_transform * child.get_aabb()
                if is_equal_approx(bounds.end.y,0.0) and is_equal_approx(bounds.size.y,1.0):
                    ground.append(bounds)
    var water_bounds: AABB = world.water.global_transform * world.water.get_aabb()
    check(is_equal_approx(water_bounds.position.x,-170) and is_equal_approx(water_bounds.end.x,170),"horizontal water spans both side horizons")
    check(is_equal_approx(water_bounds.position.z,-.1) and is_equal_approx(water_bounds.end.z,5.1),"water width matches horizontal river")
    for x in [-160.0,-25.0,25.0,160.0]:
        for z in [-15.0,13.0,40.0]:
            var covered := false
            for bounds in ground: covered = covered or bounds.has_point(Vector3(x,-.1,z))
            check(covered,"horizontal foreground coverage " + str([x,z]))
    for i in ground.size():
        for j in range(i+1,ground.size()):
            var first := ground[i]
            var second := ground[j]
            var overlap_x := minf(first.end.x,second.end.x)-maxf(first.position.x,second.position.x)
            var overlap_z := minf(first.end.z,second.end.z)-maxf(first.position.z,second.position.z)
            check(not (overlap_x>.00001 and overlap_z>.00001),"ground rectangles never overlap coplanar area")

func run() -> void:
    profile_checks()
    projection_checks()
    wind_checks()
    await collision_and_layout_checks()
    print("CANAL_BACKGROUND_UNIT checks=",checks," failures=",failures.size()," projection_samples=",projection_samples," max_error_px=",max_projection_error)
    quit(0 if failures.is_empty() else 1)
