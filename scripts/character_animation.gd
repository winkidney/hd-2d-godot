extends RefCounted
## Explicit four-direction clips, retaining each source frame's millisecond timing.
const ROOT := "res://assets/characters/crescent-traveler/v1/"
const DIRECTIONS := ["down", "up", "left", "right"]
var clips: Array[Dictionary] = []

func _init() -> void:
    var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "character.json"))
    for direction in DIRECTIONS:
        var folder: String = ROOT + direction + "/"
        var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "animation.json"))
        var atlas: Texture2D = load(folder + manifest.atlas)
        var textures: Array[Texture2D] = []
        var ends: Array[float] = []
        var duration := 0.0
        for frame in manifest.frames:
            var texture := AtlasTexture.new()
            texture.atlas = atlas
            texture.region = Rect2(frame.region[0], frame.region[1], frame.region[2], frame.region[3])
            textures.append(texture)
            duration += float(frame.duration_ms) / 1000.0
            ends.append(duration)
        clips.append({"textures": textures, "ends": ends, "duration": duration,
            "idle_frame": int(definition.directions[direction].idle_frame),
            "pivot": Vector2(manifest.pivot[0], manifest.pivot[1])})

func frame_at(direction: int, clock: float, moving: bool) -> int:
    var clip := clips[direction]
    if not moving:
        return clip.idle_frame
    var phase := fposmod(clock, float(clip.duration))
    for index in range(clip.ends.size()):
        if phase < clip.ends[index]:
            return index
    return clip.ends.size() - 1

func texture_at(direction: int, index: int) -> Texture2D:
    return clips[direction].textures[index]
