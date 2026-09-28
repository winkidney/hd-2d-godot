extends "res://scripts/lighting_controller.gd"
## New art direction, same preset controls and FX signals.
func configure(camera: Camera3D, world: Node3D, data: Dictionary) -> void:
    super.configure(camera,world,data)
    for i in range(data.lamps.size()):
        var p: Array=data.lamps[i]
        lamps[i].position=Vector3(p[0],p[1]+3.05,p[2])
        lamps[i].omni_range=7.5
    for i in range(data.buildings.size()):
        var building: Dictionary=data.buildings[i]
        var index: int = data.lamps.size()+i
        lamps[index].position=Vector3(building.position[0],building.position[1]+2.5,building.position[2]+3.3)
        lamps[index].omni_range=8
    environment.ssao_radius=1.15
    environment.ssao_intensity=1.65
    apply_preset("dusk")

func apply_preset(id: String) -> void:
    super.apply_preset(id)
    sun.light_energy={"day":1.05,"dusk":.42,"night":.28}[id]
    environment.ambient_light_energy={"day":.58,"dusk":.29,"night":.27}[id]
    environment.glow_intensity=.75
    environment.volumetric_fog_density={"day":.0012,"dusk":.0045,"night":.006}[id]
    environment.volumetric_fog_length=100
    for lamp in lamps:
        lamp.light_energy={"day":.6,"dusk":3.4,"night":5.0}[id]
    for mat in window_materials:
        mat.emission_energy_multiplier=.10 if id=="day" else 2.6
