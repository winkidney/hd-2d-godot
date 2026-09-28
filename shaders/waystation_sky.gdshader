shader_type sky;
render_mode disable_fog;
uniform vec4 zenith : source_color = vec4(0.21,0.46,0.70,1.0);
uniform vec4 horizon : source_color = vec4(0.74,0.83,0.84,1.0);
uniform float night = 0.0;
void sky() {
    float h = clamp(EYEDIR.y,0.0,1.0);
    COLOR = mix(horizon.rgb, zenith.rgb, pow(clamp(h*7.0,0.0,1.0),0.55));
    vec3 sun_dir = normalize(vec3(-0.43,0.11,-1.0));
    float disc = smoothstep(0.99975,0.9999,dot(EYEDIR,sun_dir));
    float halo = pow(max(dot(EYEDIR,sun_dir),0.0),220.0);
    COLOR += vec3(1.0,0.73,0.37) * (disc*1.4+halo*0.10)*(1.0-night);
    vec3 q = floor(EYEDIR*800.0);
    float star = step(0.9993,fract(sin(dot(q,vec3(12.9898,78.233,31.27)))*43758.5453));
    COLOR += star*night*0.75*smoothstep(0.025,0.18,EYEDIR.y);
}
