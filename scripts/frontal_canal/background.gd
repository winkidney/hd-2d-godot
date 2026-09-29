extends "res://scripts/reference_scene/background.gd"
## Three actual city rows, with a continuous canal gap rather than a skyline wall.
func configure(env: Environment) -> void:
    super.configure(env)
    # Frontal framing keeps real cloud cards above the distant skyline.
    for i in range(clouds.size()):
        var cloud: Dictionary = clouds[i]
        var origin: Vector3 = cloud.origin
        origin.y = (21.0 if int(cloud.layer) == 0 else 35.0) + float(i%3)*(3.0 if int(cloud.layer) == 0 else 5.0)
        cloud.origin = origin
        cloud.node.position = origin
    for key in ["ridge_near","ridge_mid","ridge_far"]:
        var old: Node3D = layers[key]
        remove_child(old)
        old.free()
    city_materials.clear()
    var rows := [["ridge_near",-30.0,1.0,1.0],["ridge_mid",-65.0,0.0,1.5],["ridge_far",-125.0,-1.0,2.2]]
    for row_index in range(rows.size()):
        var row: Array = rows[row_index]
        var group := Node3D.new()
        group.name = row[0]
        add_child(group)
        layers[row[0]] = group
        city_materials[row[0]] = []
        for i in range(18):
            var x := -80.0 + i*9.4
            if absf(x+5)<8: continue
            var kind := "tower" if (i+row_index)%7 == 0 else "townhouse"
            var item := (load("res://assets/reference-scene/models/"+kind+".glb") as PackedScene).instantiate() as Node3D
            group.add_child(item)
            item.position = Vector3(x*float(row[3]),row[2],float(row[1])-float(i%3)*2.8)
            item.scale = Vector3(1.0,1.0+float((i+row_index)%3)*.15,1.0)*float(row[3])
            adapt_city_materials(item,row[0],CITY_TONES[(i+row_index)%5])
        # River continues between foundations all the way to the vanishing point.
        for side in [-1,1]:
            var x := -5.0 + float(side)*70.0
            city_box(group,"QuayFoundation",Vector3(x,float(row[2])-4.0,float(row[1])-12.0),Vector3(134,8,44*float(row[3])),"brick",Color("a5aaa4"),Vector3(60,4,1))
            city_box(group,"QuayCap",Vector3(x,float(row[2])+.025,float(row[1])-12.0),Vector3(134,.05,44*float(row[3])),"paving",Color("c5c4b2"),Vector3(60,20,1))
    var base := Node3D.new()
    base.name = "FarQuayUnderlay"
    add_child(base)
    city_materials[base.name] = []
    for side in [-1,1]:
        var x := -5.0 + float(side)*453.0
        city_box(base,"ContinuousFarQuay",Vector3(x,-3.8,-520),Vector3(900,4,1000),"paving",Color("66716d"),Vector3(350,4,350))
    apply_preset("dusk")

func apply_preset(id: String) -> void:
    super.apply_preset(id)
    var cloud_tint := Color({"day":"c5d3d9","dusk":"677a85","night":"344455"}[id])
    for cloud in clouds:
        cloud.node.material_override.albedo_color = cloud_tint
