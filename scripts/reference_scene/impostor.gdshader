shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform float frame_position : hint_range(0.0, 6.0) = 3.0;

void fragment() {
    // Screen-stable ordered dithering avoids double silhouettes between views.
    int bayer[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
    int cell = int(FRAGCOORD.x) % 4 + (int(FRAGCOORD.y) % 4) * 4;
    float threshold = (float(bayer[cell]) + 0.5) / 16.0;
    float lower = floor(frame_position);
    float selected = min(6.0, lower + (fract(frame_position) > threshold ? 1.0 : 0.0));
    vec2 tile_uv = clamp(UV, vec2(0.5 / 512.0), vec2(1.0 - 0.5 / 512.0));
    vec4 color = texture(atlas, vec2((selected + tile_uv.x) / 7.0, tile_uv.y));
    if (color.a < 0.5) { discard; }
    ALBEDO = color.rgb;
}
