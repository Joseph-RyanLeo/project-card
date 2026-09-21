class_name CelestialIndicatorStyle
extends RefCounted

const SOURCE: Texture2D = preload("res://assets/card_ui/celestial/source/celestial_indicators.png")
const CELLS := [Rect2i(0, 0, 31, 47), Rect2i(31, 0, 42, 47), Rect2i(73, 0, 44, 47)]
static var _textures: Dictionary = {}

static func get_texture(kind: int) -> Texture2D:
	if _textures.has(kind):
		return _textures[kind] as Texture2D
	if kind < 0 or kind >= CELLS.size():
		return null
	var source := SOURCE.get_image()
	var crop := source.get_region(CELLS[kind])
	# 按透明边界裁切，保留每枚指示物自己的原生像素尺寸。
	var texture := ImageTexture.create_from_image(crop.get_region(crop.get_used_rect()))
	_textures[kind] = texture
	return texture

static func create_visual(indicator: CelestialIndicator) -> TextureRect:
	var view := TextureRect.new()
	view.texture = get_texture(indicator.kind)
	view.size = view.texture.get_size()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.z_index = EquipmentIndicatorStyle.INDICATOR_Z_INDEX
	var shadow := TextureRect.new()
	shadow.texture = view.texture
	shadow.position = EquipmentIndicatorStyle.SHADOW_OFFSET
	shadow.modulate = EquipmentIndicatorStyle.SHADOW_COLOR
	shadow.show_behind_parent = true
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(shadow)
	return view
