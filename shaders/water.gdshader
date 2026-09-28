shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 deep_color : source_color = vec4(0.075,0.20,0.25,1.0);
uniform vec4 shallow_color : source_color = vec4(0.22,0.39,0.40,1.0);
uniform float motion = 1.0;
varying vec3 world_pos;
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}
void fragment() {
    vec2 cell = floor(world_pos.xz * 24.0) / 24.0;
    float t = TIME * motion;
    float a = sin(cell.y * 13.0 + sin(cell.x * 2.2 - t) * 1.8 - t * 1.6);
    float b = sin(cell.x * 8.0 + cell.y * 2.4 + t * 0.5);
    float streak = smoothstep(0.80,0.98,a) * smoothstep(0.1,0.8,b);
    float broad = sin(cell.x * 0.6 + cell.y * 1.8 - t * 0.4) * 0.5 + 0.5;
    float shore = max(1.0 - smoothstep(0.0,0.38,world_pos.z-2.0),1.0-smoothstep(0.0,0.38,6.8-world_pos.z));
    ALBEDO = mix(deep_color.rgb,shallow_color.rgb,broad*0.55 + streak*0.32);
    ALBEDO += vec3(0.15,0.20,0.19) * streak + shore * 0.06;
    NORMAL = normalize((VIEW_MATRIX * vec4(sin(cell.x*3.0+t)*0.035,1.0,cos(cell.y*4.0-t)*0.035,0.0)).xyz);
    ROUGHNESS = 0.31;
    METALLIC = 0.18;
    SPECULAR = 0.4;
    EMISSION = shallow_color.rgb * streak * 0.12;
}
