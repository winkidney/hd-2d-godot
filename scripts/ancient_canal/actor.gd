extends "res://scripts/pixel_actor.gd"
## A single frame computation binds unchanged color, vector normals and silver.
const NORMAL_ROOT := "res://assets/ancient-canal/character-normals/v1/"
var normal_definition: Dictionary = {}
var color_definitions: Array[Dictionary] = []
var color_atlases: Array[Texture2D] = []
var color_frames: Array = []
var normal_atlases: Array[Texture2D] = []
var silver_atlases: Array[Texture2D] = []
var surface: ShaderMaterial
var frame_override := -1
var direction_override := -1
var preview_walk := false
var paused := false
var inspection_clock := 0.0
var material_values: Dictionary = {}

func _ready() -> void:
    super._ready()
    surface = ShaderMaterial.new()
    surface.shader = preload("res://shaders/ancient_canal/sprite_native.gdshader")
    sprite.material_override = surface
    sprite.position.y = 0.0
    sprite.offset = Vector2(0,112)
    if FileAccess.file_exists(NORMAL_ROOT+"manifest.json"):
        normal_definition = JSON.parse_string(FileAccess.get_file_as_string(NORMAL_ROOT+"manifest.json"))
    for direction in animation.DIRECTIONS:
        var folder: String = animation.ROOT+direction+"/"
        var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder+"animation.json"))
        color_definitions.append(definition)
        color_atlases.append(load(folder+definition.atlas))
        var originals: Array[Texture2D] = []
        for frame in definition.frames: originals.append(load(folder+frame.path))
        color_frames.append(originals)
        # Exported PNGs are remapped to imported textures in the embedded PCK.
        # ResourceLoader resolves the remap; raw-file existence would silently
        # replace real normals with a flat texture in standalone builds.
        if ResourceLoader.exists(NORMAL_ROOT+direction+"/atlas.png") and ResourceLoader.exists(NORMAL_ROOT+direction+"/mask-atlas.png"):
            normal_atlases.append(load(NORMAL_ROOT+direction+"/atlas.png"))
            silver_atlases.append(load(NORMAL_ROOT+direction+"/mask-atlas.png"))
        else:
            normal_atlases.append(flat_texture(Color(.5,.5,1)))
            silver_atlases.append(flat_texture(Color.BLACK))
    displayed_facing = -1
    update_animation()

static func flat_texture(color: Color) -> ImageTexture:
    var data := Image.create(1,1,false,Image.FORMAT_RGBA8)
    data.fill(color)
    return ImageTexture.create_from_image(data)

func update_animation() -> void:
    if direction_override>=0: facing = direction_override
    var clock := inspection_clock if preview_walk else animation_clock
    var index: int = frame_override if paused and frame_override>=0 else animation.frame_at(facing,clock,walking or preview_walk)
    if index != animation_frame or facing != displayed_facing:
        # An AtlasTexture on Sprite3D would crop its mesh UVs before our uniform
        # atlas mapping. Use the exact original 256px frame to keep mesh UV 0..1.
        sprite.texture = color_frames[facing][index] if color_frames.size()==4 else animation.texture_at(facing,index)
        sprite.offset = animation.clips[facing].pivot-Vector2(128,128)
        sprite.offset.x = -sprite.offset.x
        animation_frame = index
        displayed_facing = facing
    if surface!=null and color_atlases.size()==4:
        bind_frame(facing,index)

func _physics_process(delta: float) -> void:
    var before := animation_clock
    if preview_walk and not paused: inspection_clock += delta
    super._physics_process(delta)
    if paused: animation_clock = before

func bind_frame(direction: int,index: int) -> void:
    var frame: Dictionary = color_definitions[direction].frames[index]
    var size := Vector2(color_atlases[direction].get_size())
    var region: Array = frame.region
    surface.set_shader_parameter("color_atlas",color_atlases[direction])
    surface.set_shader_parameter("normal_atlas",normal_atlases[direction])
    surface.set_shader_parameter("silver_atlas",silver_atlases[direction])
    surface.set_shader_parameter("atlas_region",Vector4(region[0]/size.x,region[1]/size.y,region[2]/size.x,region[3]/size.y))

func apply_material(values: Dictionary) -> void:
    material_values = values
    if surface==null: return
    var wanted: Shader = load("res://shaders/ancient_canal/sprite_"+("native" if values.shading_mode=="native" else "stepped")+".gdshader")
    if surface.shader!=wanted: surface.shader = wanted
    for pair in [["use_normals","normals_enabled"],["normal_strength","normal_strength"],["flip_y","normal_flip_y"],["clay_mode","clay"],["normal_debug","normal_debug"],["silver_specular","silver_specular"],["shade_levels","light_steps"]]:
        surface.set_shader_parameter(pair[0],values[pair[1]])
    update_animation()
