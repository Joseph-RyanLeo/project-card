class_name ResourceIndicatorStyle
extends RefCounted

## 从用户素材裁切资源品级底座、种类图案、卡面角标和中央小图标。

const BASE_ATLAS: Texture2D = preload("res://assets/card_ui/resources/source/indicator_bases.png")
const ICON_ATLAS: Texture2D = preload("res://assets/card_ui/resources/source/indicator_icons.png")
const BADGE_ATLAS: Texture2D = preload("res://assets/card_ui/resources/source/rarity_badges.png")
const CARD_TYPE_ATLASES: Array[Texture2D] = [
	preload("res://assets/card_ui/resources/source/type_grade_i.png"),
	preload("res://assets/card_ui/resources/source/type_grade_ii.png"),
	preload("res://assets/card_ui/resources/source/type_grade_iii.png"),
	preload("res://assets/card_ui/resources/source/type_grade_iv.png"),
	preload("res://assets/card_ui/resources/source/type_grade_v.png"),
] # 卡面中央小图按I～V品级索引，原素材文件由图12～图8反向排列
const DISPLAY_SIZE := Vector2(35.0, 33.0) # 资源指示物保持底座原生35×33像素
const SOURCE_COLUMN_BY_RARITY := [1, 0, 2, 3, 4] # I/II素材列颜色与逻辑品级相反，III～V保持原列
const SOURCE_X_BY_COLUMN := [0, 45, 92, 137, 182] # 五列素材在图集中的像素起点
const ICON_Y_BY_SOURCE_ROW := [0, 40, 77, 115] # 大图集视觉顺序：食物、遗物、矿物、植物
const ICON_HEIGHT_BY_SOURCE_ROW := [19, 15, 22, 19] # 四行各自的原生高度
const SOURCE_ROW_BY_RESOURCE_TYPE := [2, 3, 1, 0] # CardData顺序矿物、植物、遗物、食物→大图集行
const BADGE_Y_BY_RARITY := [0, 121, 91, 62, 31] # 角标原图自上而下为I、V、IV、III、II
const CARD_TYPE_Y := [0, 17, 31, 44] # 卡面中央小图自上而下为矿物、植物、遗物、食物
const CARD_TYPE_HEIGHT := [11, 9, 9, 10] # 四类卡面小图的原生高度

static var _texture_cache: Dictionary = {}


static func get_texture(rarity: CardData.Rarity, resource_type: int) -> Texture2D:
	var rarity_index := int(rarity)
	if rarity_index < 0 or rarity_index >= SOURCE_COLUMN_BY_RARITY.size() or resource_type < 0 or resource_type >= SOURCE_ROW_BY_RESOURCE_TYPE.size():
		return null
	var source_row: int = SOURCE_ROW_BY_RESOURCE_TYPE[resource_type]
	var cache_key := Vector2i(rarity_index, source_row)
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key] as Texture2D
	var source_x := get_source_x(rarity_index)
	var base := BASE_ATLAS.get_image().get_region(
		Rect2i(source_x, 0, 35, 33)
	)
	var icon := ICON_ATLAS.get_image().get_region(
		Rect2i(source_x, ICON_Y_BY_SOURCE_ROW[source_row], 21, ICON_HEIGHT_BY_SOURCE_ROW[source_row])
	)
	var visible := icon.get_used_rect()
	var centered_position := Vector2i(
		floori((int(DISPLAY_SIZE.x) - visible.size.x) * 0.5) - visible.position.x,
		floori((int(DISPLAY_SIZE.y) - visible.size.y) * 0.5) - visible.position.y
	)
	base.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), centered_position)
	var texture := ImageTexture.create_from_image(base)
	_texture_cache[cache_key] = texture
	return texture


static func get_icon_atlas_texture(rarity: CardData.Rarity, resource_type: int) -> AtlasTexture:
	var rarity_index := int(rarity)
	if rarity_index < 0 or rarity_index >= SOURCE_COLUMN_BY_RARITY.size() or resource_type < 0 or resource_type >= SOURCE_ROW_BY_RESOURCE_TYPE.size():
		return null
	var source_row: int = SOURCE_ROW_BY_RESOURCE_TYPE[resource_type]
	var icon := AtlasTexture.new()
	icon.atlas = ICON_ATLAS
	icon.region = Rect2(get_source_x(rarity_index), ICON_Y_BY_SOURCE_ROW[source_row], 21, ICON_HEIGHT_BY_SOURCE_ROW[source_row])
	return icon


static func get_source_x(rarity_index: int) -> int:
	if rarity_index < 0 or rarity_index >= SOURCE_COLUMN_BY_RARITY.size():
		return -1
	return SOURCE_X_BY_COLUMN[SOURCE_COLUMN_BY_RARITY[rarity_index]]


static func get_icon_visible_rect(rarity: CardData.Rarity, resource_type: int) -> Rect2i:
	var texture := get_icon_atlas_texture(rarity, resource_type)
	if texture == null:
		return Rect2i()
	var source_row: int = SOURCE_ROW_BY_RESOURCE_TYPE[resource_type]
	var image := ICON_ATLAS.get_image().get_region(Rect2i(
		get_source_x(int(rarity)),
		ICON_Y_BY_SOURCE_ROW[source_row],
		21,
		ICON_HEIGHT_BY_SOURCE_ROW[source_row]
	))
	return image.get_used_rect()


static func get_badge_region(rarity: CardData.Rarity) -> Rect2:
	var rarity_index := int(rarity)
	if rarity_index < 0 or rarity_index >= BADGE_Y_BY_RARITY.size():
		return Rect2()
	return Rect2(0, BADGE_Y_BY_RARITY[rarity_index], 21, 26)


static func get_card_type_texture(rarity: CardData.Rarity, resource_type: int) -> AtlasTexture:
	var rarity_index := int(rarity)
	if rarity_index < 0 or rarity_index >= CARD_TYPE_ATLASES.size():
		return null
	if resource_type < 0 or resource_type >= CARD_TYPE_Y.size():
		return null
	var texture := AtlasTexture.new()
	texture.atlas = CARD_TYPE_ATLASES[rarity_index]
	texture.region = Rect2(0, CARD_TYPE_Y[resource_type], 11, CARD_TYPE_HEIGHT[resource_type])
	return texture
