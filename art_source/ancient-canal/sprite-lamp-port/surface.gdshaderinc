uniform bool use_normals = true;
uniform bool flip_y = false;
uniform bool clay_mode = false;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.8;

void fragment() {
    vec4 albedo = texture(TEXTURE, UV);
    if (clay_mode) { albedo.rgb = vec3(0.72); }
    COLOR = albedo;
    vec3 n = texture(NORMAL_TEXTURE, UV).rgb * 2.0 - 1.0;
    n.z = max(n.z, 0.001);
    n.xy *= normal_strength;
    if (flip_y) { n.y = -n.y; }
    n = normalize(n);
    // NORMAL_MAP performs Godot's 3D-map -> 2D-normal coordinate conversion.
    NORMAL_MAP = use_normals ? n * 0.5 + 0.5 : vec3(0.5, 0.5, 1.0);
}
