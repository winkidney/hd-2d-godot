shader_type canvas_item;
#include "res://shaders/surface.gdshaderinc"
uniform int shade_levels : hint_range(2, 8) = 4;
void light() {
    float amount = max(dot(normalize(NORMAL), normalize(LIGHT_DIRECTION)), 0.0);
    float steps = float(shade_levels - 1);
    amount = floor(amount * steps + 0.5) / steps;
    LIGHT = vec4(COLOR.rgb * LIGHT_COLOR.rgb * LIGHT_ENERGY * amount, LIGHT_COLOR.a);
}
