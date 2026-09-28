shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D caustics : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 deep_color : source_color = vec4(0.035,0.12,0.14,1.0);
uniform vec4 shallow_color : source_color = vec4(0.14,0.32,0.34,1.0);
uniform float motion = 1.0;
varying vec3 world_pos;
void vertex() {
    world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
    vec2 p=floor(world_pos.xz*28.0)/28.0;
    float t=TIME*motion;
    vec3 pattern=texture(caustics,p*0.22+vec2(t*0.008,t*0.016)).rgb;
    float flow=sin(p.y*6.0+p.x*1.6-t*1.1);
    float glint=smoothstep(0.90,0.999,flow)*smoothstep(0.1,0.9,sin(p.x*9.0+t*.4));
    ALBEDO=mix(deep_color.rgb,shallow_color.rgb,0.25+pattern.g*.35);
    ALBEDO+=vec3(0.17,0.22,0.20)*glint;
    vec3 world_n=normalize(vec3(sin(p.x*2.0+t)*.08,1.0,cos(p.y*3.0-t)*.10));
    NORMAL=normalize((VIEW_MATRIX*vec4(world_n,0.0)).xyz);
    ROUGHNESS=0.23;
    METALLIC=0.12;
    SPECULAR=0.65;
    EMISSION=pattern.rgb*glint*.06;
}
