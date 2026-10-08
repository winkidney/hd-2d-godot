shader_type sky;
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 sky_top_color : source_color;
uniform vec4 sky_horizon_color : source_color;
void sky() {
    float h = clamp(EYEDIR.y, 0.0, 1.0);
    vec3 base = mix(sky_horizon_color.rgb, sky_top_color.rgb, pow(clamp(h * 7.0, 0.0, 1.0), 0.55));
    vec2 uv = vec2(atan(EYEDIR.x, -EYEDIR.z) / TAU + 0.5, acos(clamp(EYEDIR.y, -1.0, 1.0)) / PI);
    COLOR = base + texture(panorama, uv).rgb;
}
