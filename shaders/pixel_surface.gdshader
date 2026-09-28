shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform float texture_scale = 0.5;
uniform vec4 tint : source_color = vec4(1.0);
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    vec3 weight = pow(abs(world_normal), vec3(7.0));
    weight /= max(weight.x + weight.y + weight.z, 0.001);
    vec3 px = texture(albedo_tex, world_pos.zy * texture_scale).rgb;
    vec3 py = texture(albedo_tex, world_pos.xz * texture_scale).rgb;
    vec3 pz = texture(albedo_tex, world_pos.xy * texture_scale).rgb;
    ALBEDO = (px * weight.x + py * weight.y + pz * weight.z) * tint.rgb;
    ROUGHNESS = 0.88;
    SPECULAR = 0.16;
}
