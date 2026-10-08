extends RefCounted
## One shared texture and a two-triangle card, with a separate narrow trunk collider.
static func make_tree(parent: Node3D, point: Vector3, scale_value := 1.0, shadow := true) -> Sprite3D:
    var card := Sprite3D.new()
    card.name = "PixelWillow"
    card.texture = preload("res://assets/ancient-canal/scenery/willow.png")
    card.pixel_size = .025 * scale_value
    card.offset = Vector2(0,120)
    card.position = point
    card.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
    card.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
    card.shaded = true
    card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(card)
    return card
