shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform float clock = 0.0;
uniform float flow = 0.35;
uniform float wave_strength = 0.6;
uniform float reflection = 0.55;
uniform vec4 deep_color : source_color = vec4(0.06,0.18,0.22,1.0);
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec2 p = floor(world_pos.xz * 40.0) / 40.0;
    float time = clock * flow;
    float a = sin(p.y*15.4 - time*2.0 + sin(p.x*5.1+time)*0.7);
    float b = cos(p.x*17.0 + p.y*3.3 + time*1.2);
    float line = step(0.87,a) * step(0.15,b);
    ALBEDO = deep_color.rgb + vec3(0.06,0.10,0.09) * (a*0.5+0.5) + vec3(0.08,0.13,0.13)*line;
    vec3 n = normalize(vec3(cos(p.x*22.0+time)*0.045*wave_strength,1.0,sin(p.y*18.4-time)*0.07*wave_strength));
    NORMAL = normalize((VIEW_MATRIX * vec4(n,0.0)).xyz);
    ROUGHNESS = mix(0.82,0.18,reflection);
    SPECULAR = reflection;
    METALLIC = reflection*0.22;
}
