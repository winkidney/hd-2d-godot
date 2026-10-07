shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/ancient_canal/sprite_surface.gdshaderinc"
// No custom light(): Godot's native spatial light/shadow implementation.
