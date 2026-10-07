shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/ancient_canal/sprite_surface.gdshaderinc"
uniform int shade_levels = 4;
void light() {
    float amount = max(dot(normalize(NORMAL), normalize(LIGHT)), 0.0);
    float steps = float(max(shade_levels - 1, 1));
    amount = floor(amount * steps + 0.5) / steps;
    // Attenuation includes light distance and shadow visibility. Add every light.
    DIFFUSE_LIGHT += amount * ATTENUATION * LIGHT_COLOR / PI;
    vec3 half_dir = normalize(LIGHT + VIEW);
    float exponent = mix(12.0, 128.0, 1.0 - ROUGHNESS);
    SPECULAR_LIGHT += pow(max(dot(NORMAL, half_dir), 0.0), exponent) * ATTENUATION * LIGHT_COLOR * material_specular;
}
