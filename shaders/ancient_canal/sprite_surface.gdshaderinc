// Adapted from sprite-lamp-godot surface.gdshaderinc to spatial tangent normals.
uniform sampler2D color_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D normal_atlas : filter_nearest, repeat_disable;
uniform sampler2D silver_atlas : filter_nearest, repeat_disable;
uniform vec4 atlas_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool use_normals = true;
uniform bool flip_y = false;
uniform bool clay_mode = false;
uniform bool normal_debug = false;
uniform float normal_strength = 0.8;
uniform float silver_specular = 0.75;
varying float material_specular;

mat3 upright_billboard_basis(vec3 camera_back, vec3 camera_right) {
    vec3 world_up = vec3(0.0, 1.0, 0.0);
    vec3 front = vec3(camera_back.x, 0.0, camera_back.z);
    // A camera directly above the character has no horizontal back vector.
    // Retain its horizontal right vector in that singular view instead.
    if (dot(front, front) < 0.000001) {
        vec3 right_hint = vec3(camera_right.x, 0.0, camera_right.z);
        if (dot(right_hint, right_hint) < 0.000001) {
            right_hint = vec3(1.0, 0.0, 0.0);
        }
        front = cross(normalize(right_hint), world_up);
    }
    front = normalize(front);
    vec3 right = normalize(cross(world_up, front));
    return mat3(right, world_up, front);
}

void vertex() {
    // The main view determines the same upright silhouette in visible and
    // shadow passes. Its pitch never tilts the character away from world UP.
    mat3 standing = upright_billboard_basis(MAIN_CAM_INV_VIEW_MATRIX[2].xyz, MAIN_CAM_INV_VIEW_MATRIX[0].xyz);
    mat4 facing = mat4(vec4(standing[0], 0.0), vec4(standing[1], 0.0), vec4(standing[2], 0.0), MODEL_MATRIX[3]);
    MODELVIEW_MATRIX = VIEW_MATRIX * facing;
    MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
    vec2 coord = atlas_region.xy + UV * atlas_region.zw;
    vec4 color = texture(color_atlas, coord);
    if (color.a < 0.5) { discard; }
    ALBEDO = clay_mode ? vec3(0.64) : color.rgb;
    float silver = texture(silver_atlas, coord).r;
    vec3 n = texture(normal_atlas, coord).rgb * 2.0 - 1.0;
    n.z = max(n.z, 0.001);
    n.xy *= normal_strength;
    if (flip_y) { n.y = -n.y; }
    n = normalize(n);
    NORMAL_MAP = use_normals ? n * 0.5 + 0.5 : vec3(0.5, 0.5, 1.0);
    NORMAL_MAP_DEPTH = 1.0;
    ROUGHNESS = mix(0.91, 0.23, silver * silver_specular);
    METALLIC = silver * 0.78 * silver_specular;
    SPECULAR = mix(0.12, 0.72, silver * silver_specular);
    if (normal_debug) { EMISSION = n * 0.5 + 0.5; ALBEDO = vec3(0.0); SPECULAR = 0.0; METALLIC = 0.0; }
    material_specular = SPECULAR;
}
