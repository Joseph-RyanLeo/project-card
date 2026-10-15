class_name SentryIndicatorStyle
extends RefCounted

const SOURCE: Texture2D = preload("res://assets/card_ui/sentry/source/sentry_variants.png")
const CELLS: Array[Rect2] = [Rect2(0, 0, 44, 49), Rect2(49, 0, 44, 49), Rect2(0, 59, 44, 49), Rect2(49, 59, 44, 49)] # 去除透明留白，四款保持原生44×49像素
static var _textures: Dictionary = {}


static func get_texture(variant: int) -> Texture2D:
	if variant < 0 or variant >= CELLS.size():
		return null
	if not _textures.has(variant):
		var texture := AtlasTexture.new()
		texture.atlas = SOURCE
		texture.region = CELLS[variant]
		_textures[variant] = texture
	return _textures[variant]


static func create_visual(indicator: SentryIndicator) -> TextureRect:
	if indicator == null:
		return null
	var view := TextureRect.new()
	view.texture = get_texture(indicator.visual_variant)
	if view.texture == null:
		view.free()
		return null
	view.size = view.texture.get_size()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return view
