extends "res://scripts/frontal_canal/camera.gd"
## Fixed frontal lenses, a stable actor centre and per-axis outer-map limits.
const SUPPORTED_VARIANTS := {"F":true, "W":true}
const CENTER_HEIGHT := 1.0125
const SILHOUETTE := Rect2(66,14,123,227)
const PIXEL_SIZE := 0.009
const FOOT_PIXEL := Vector2(128,240)
const SCREEN_INSET := 2.0
var follow_bounds := Rect2(-26,-16,52,30)
var raw_margin := Vector2.ZERO
var edge_margin := Vector2.ZERO
var margin_scale := 1.0
var _limit_key: Array = []
var _last_player_position := Vector3.ZERO

func configure(value: Camera3D, config: Dictionary, player_spawn: Vector3) -> void:
    camera = value
    anchor = player_spawn
    target = player_spawn + Vector3.UP * CENTER_HEIGHT
    _last_player_position = player_spawn
    gain = 1.0
    horizontal_gain = 1.0
    dead_zone = 0.0
    horizontal_dead_zone = 0.0
    smoothing = 0.0
    initial_right = Vector3.RIGHT
    var bank: Dictionary = config.get("follow_bounds", {})
    if not bank.is_empty():
        follow_bounds = Rect2(-float(bank.outer_x),float(bank.min_z),2.0*float(bank.outer_x),float(bank.max_z)-float(bank.min_z))
    max_offset = follow_bounds.size
    camera.near = .1
    camera.far = float(config.get("far",320.0))
    lens_profiles = lens_profiles_defaults()
    _limit_key.clear()
    select_variant("F",player_spawn)

func lens_defaults(id: String) -> Dictionary:
    return super.lens_defaults(id) if SUPPORTED_VARIANTS.has(id) else {}

func lens_profiles_defaults() -> Dictionary:
    var result: Dictionary = {}
    for id in SUPPORTED_VARIANTS: result[id] = lens_defaults(id)
    return result

func lens_profiles_error(value: Variant) -> String:
    if not value is Dictionary or value.size()!=SUPPORTED_VARIANTS.size():
        return "需要完整的 F、W 两组镜头设置。"
    for id in SUPPORTED_VARIANTS:
        if not value.has(id) or not value[id] is Dictionary:
            return "缺少镜头设置。"
        var profile: Dictionary = value[id]
        if profile.size()!=LENS_LIMITS.size(): return "镜头设置包含未知或缺失字段。"
        for key in LENS_LIMITS:
            if not profile.has(key): return "缺少镜头参数。"
            var error := lens_error(key,profile[key])
            if not error.is_empty(): return error
    return ""

func validate_lens_profiles(value: Variant) -> Dictionary:
    if not lens_profiles_error(value).is_empty(): return {}
    var result: Dictionary = {}
    for id in SUPPORTED_VARIANTS:
        result[id] = {"radius":float(value[id].radius),"fov":float(value[id].fov)}
    return result

func restore_lens_profiles(value: Dictionary, active_id: String, player_position := Vector3.INF) -> bool:
    # Reject removed variants before the inherited restore can mutate profiles.
    if not SUPPORTED_VARIANTS.has(active_id): return false
    return super.restore_lens_profiles(value,active_id,player_position)

func select_variant(id: String, player_position := Vector3.INF) -> bool:
    if not SUPPORTED_VARIANTS.has(id): return false
    var feet: Vector3 = player_position if player_position.is_finite() else _last_player_position
    return super.select_variant(id,feet)

func apply_lens() -> void:
    super.apply_lens()
    if enabled: set_offset(desired_offset(_last_player_position))

func refresh_follow_limits() -> void:
    var size := camera.get_viewport().get_visible_rect().size
    var projection := camera.get_camera_projection()
    var radius := float(lens_snapshot().radius)
    var key: Array = [size,projection.x.x,projection.y.y,radius,reference_basis,follow_bounds]
    if key==_limit_key: return
    _limit_key = key
    # Projection coefficients already account for keep_aspect and viewport size.
    var half_width := radius/absf(projection.x.x)
    var half_height := radius/absf(projection.y.y)
    var right := reference_basis.x
    var up := reference_basis.y
    raw_margin = Vector2(absf(right.x)*half_width+absf(up.x)*half_height,absf(right.z)*half_width+absf(up.z)*half_height)
    raw_margin = raw_margin.min(follow_bounds.size*.25)
    margin_scale = silhouette_safe_scale(radius,raw_margin,projection,size)
    edge_margin = raw_margin*margin_scale

func silhouette_safe_scale(radius: float, margin: Vector2, projection: Projection, size: Vector2) -> float:
    # Each frustum half-plane is linear in the common edge-band scale. The
    # fixed union covers all 108 frames, so walking cannot shake the limits.
    var horizontal_tangent := (1.0-2.0*SCREEN_INSET/maxf(size.x,8.0))/absf(projection.x.x)
    var vertical_tangent := (1.0-2.0*SCREEN_INSET/maxf(size.y,8.0))/absf(projection.y.y)
    var right := reference_basis.x
    var up := reference_basis.y
    var back := reference_basis.z
    var scale := 1.0
    var corners := [SILHOUETTE.position,Vector2(SILHOUETTE.end.x,SILHOUETTE.position.y),SILHOUETTE.end,Vector2(SILHOUETTE.position.x,SILHOUETTE.end.y)]
    for sx in [-1.0,1.0]:
        for sz in [-1.0,1.0]:
            var edge := Vector3(sx*margin.x,0,sz*margin.y)
            for pixel: Vector2 in corners:
                var point := right*(pixel.x-FOOT_PIXEL.x)*PIXEL_SIZE+Vector3.UP*((FOOT_PIXEL.y-pixel.y)*PIXEL_SIZE-CENTER_HEIGHT)
                var depth := radius-point.dot(back)
                var depth_delta := -edge.dot(back)
                for plane in [[right,horizontal_tangent],[-right,horizontal_tangent],[up,vertical_tangent],[-up,vertical_tangent]]:
                    var axis: Vector3 = plane[0]
                    var tangent: float = plane[1]
                    var base := point.dot(axis)-tangent*depth
                    var rate := edge.dot(axis)-tangent*depth_delta
                    if rate>0.0: scale = minf(scale,-base/rate)
                if -depth_delta>0.0:
                    scale = minf(scale,(depth-camera.near)/(-depth_delta))
    return clampf(scale,0.0,1.0)

func desired_offset(player_position: Vector3) -> Vector3:
    _last_player_position = player_position
    refresh_follow_limits()
    var center := player_position+Vector3.UP*CENTER_HEIGHT
    center.x = clampf(center.x,follow_bounds.position.x+edge_margin.x,follow_bounds.end.x-edge_margin.x)
    center.z = clampf(center.z,follow_bounds.position.y+edge_margin.y,follow_bounds.end.y-edge_margin.y)
    return center-target

func desired_yaw(_player_position: Vector3) -> float:
    return 0.0

func set_offset(offset: Vector3) -> void:
    yaw_degrees = 0.0
    target_yaw_degrees = 0.0
    _test_yaw = NAN
    super.set_offset(offset)

func set_test_yaw(value: float) -> void:
    if not is_zero_approx(value): return
    set_offset(follow_offset)

func profile_original_update(_delta: float, player_position: Vector3, _tour: bool, _elapsed: float) -> void:
    if frozen: return
    _last_player_position = player_position
    set_offset(desired_offset(player_position) if enabled else Vector3.ZERO)

func supported_pose() -> bool:
    return SUPPORTED_VARIANTS.has(variant_id) and is_zero_approx(yaw_degrees) and is_zero_approx(target_yaw_degrees) and super.supported_pose()

func restore_pose(value: Dictionary) -> void:
    if not SUPPORTED_VARIANTS.has(value.get("variant_id","")): return
    if validate_lens_profiles(value.get("lens_profiles",{})).is_empty(): return
    if not is_zero_approx(value.get("yaw_degrees",INF)) or not is_zero_approx(value.get("target_yaw_degrees",INF)): return
    super.restore_pose(value)
    _test_yaw = NAN
    refresh_follow_limits()

func follow_diagnostics() -> Dictionary:
    refresh_follow_limits()
    return {"bounds":[follow_bounds.position.x,follow_bounds.position.y,follow_bounds.size.x,follow_bounds.size.y],
        "raw_margin":[raw_margin.x,raw_margin.y],"safe_margin":[edge_margin.x,edge_margin.y],"margin_scale":margin_scale,
        "center_height":CENTER_HEIGHT,"pivot":target+follow_offset,"viewport":camera.get_viewport().get_visible_rect().size}

var profile_timings: Dictionary = {}
func profile_record(key: String, started: int) -> void:
    if not profile_timings.has(key): profile_timings[key] = []
    profile_timings[key].append(float(Time.get_ticks_usec()-started)/1000.0)

func update(delta: float,player_position: Vector3,tour: bool,elapsed: float) -> void:
    var started := Time.get_ticks_usec()
    profile_original_update(delta,player_position,tour,elapsed)
    profile_record("update",started)
