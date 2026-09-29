extends "res://scripts/reference_scene/lighting.gd"
func apply_preset(id: String) -> void:
    super.apply_preset(id)
    # Slightly higher ambient fill keeps both real side walls readable at night.
    sun.rotation_degrees = Vector3(-32,-28,0)
    environment.ambient_light_energy = {"day":.68,"dusk":.32,"night":.30}[id]
    environment.ssao_intensity = 1.15
    environment.volumetric_fog_density = {"day":.0018,"dusk":.0065,"night":.0075}[id]
    for lamp in lamps:
        lamp.light_energy = {"day":.6,"dusk":2.4,"night":3.4}[id]
