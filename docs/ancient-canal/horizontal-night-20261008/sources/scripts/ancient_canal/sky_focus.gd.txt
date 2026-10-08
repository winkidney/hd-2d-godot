extends CompositorEffect
## Protect only untouched sky pixels in Forward+'s resolved R32 depth buffer.
## Runs after transparent/MSAA resolve and before the engine's existing DOF.
## No color pass, extra texture, geometry or change to object focus distances.
const COMPUTE := """#version 450
layout(local_size_x=8, local_size_y=8, local_size_z=1) in;
layout(r32f, set=0, binding=0) uniform image2D depth_image;
layout(push_constant, std430) uniform Parameters { vec4 values; } params;
void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(p,imageSize(depth_image)))) return;
    if (imageLoad(depth_image,p).r == 0.0) {
        float n=params.values.x, f=params.values.y, d=params.values.z;
        imageStore(depth_image,p,vec4(n*(f-d)/(d*(f-n))));
    }
}
"""
var focus_distance := 30.0
var near_plane := .05
var far_plane := 320.0
var rd: RenderingDevice
var shader := RID()
var pipeline := RID()

func _init() -> void:
    enabled = false
    effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
    access_resolved_depth = true
    RenderingServer.call_on_render_thread(initialize_gpu)

func initialize_gpu() -> void:
    rd = RenderingServer.get_rendering_device()
    if rd == null: return
    var source := RDShaderSource.new()
    source.source_compute = COMPUTE
    var spirv := rd.shader_compile_spirv_from_source(source)
    if not spirv.compile_error_compute.is_empty():
        push_error(spirv.compile_error_compute)
        return
    shader = rd.shader_create_from_spirv(spirv)
    pipeline = rd.compute_pipeline_create(shader)

func _render_callback(_type: int, data: RenderData) -> void:
    if rd == null or not pipeline.is_valid(): return
    var buffers: RenderSceneBuffersRD = data.get_render_scene_buffers()
    # Forward+ exposes a writable resolved R32 buffer with MSAA, while the
    # no-MSAA depth attachment and other renderers cannot be bound as an image.
    if buffers.get_msaa_3d()==RenderingServer.VIEWPORT_MSAA_DISABLED: return
    var size := buffers.get_internal_size()
    var uniform := RDUniform.new()
    uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    uniform.binding = 0
    for view in buffers.get_view_count():
        uniform.clear_ids()
        uniform.add_id(buffers.get_depth_layer(view))
        var bindings := UniformSetCacheRD.get_cache(shader,0,[uniform])
        var parameters := PackedFloat32Array([near_plane,far_plane,focus_distance,0]).to_byte_array()
        var list := rd.compute_list_begin()
        rd.compute_list_bind_compute_pipeline(list,pipeline)
        rd.compute_list_bind_uniform_set(list,bindings,0)
        rd.compute_list_set_push_constant(list,parameters,16)
        rd.compute_list_dispatch(list,ceili(size.x/8.0),ceili(size.y/8.0),1)
        rd.compute_list_end()

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE and shader.is_valid():
        # Freeing a shader releases dependent pipelines and uniform sets too.
        RenderingServer.call_on_render_thread(rd.free_rid.bind(shader))
