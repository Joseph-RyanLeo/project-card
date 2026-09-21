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
const BASE_X := [0, 45, 92, 137, 182] # 底座从左到右按I～V品级排列
const ICON_X := [0, 45, 92, 137, 182] # 资源图案从左到右按I～V品级排列
const ICON_Y := [0, 40, 77, 115] # 资源图案四行的裁切起点，具体种类顺序待确认
const ICON_HEIGHT := [19, 15, 22, 19] # 资源图案四行各自的原生高度
const BADGE_Y_BY_RARITY := [0, 121, 91, 62, 31] # 角标原图自上而下为I、V、IV、III、II
const CARD_TYPE_Y := [0, 17, 31, 44] # 卡面中央小图自上而下为矿物、植物、遗物、食物
const CARD_TYPE_HEIGHT := [11, 9, 9, 10] # 四类卡面小图的原生高度

static var _texture_cache: Dictionary = {}


static func get_texture(rarity: CardData.Rarity, source_row: int) -> Texture2D:
	var rarity_index := int(rarity)
	if rarity_index < 0 or rarity_index >= BASE_X.size() or source_row < 0 or source_row >= ICON_Y.size():
		return null
	var cache_key := Vector2i(rarity_index, source_row)
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key] as Texture2D
	var base := BASE_ATLAS.get_image().get_region(
		Rect2i(BASE_X[rarity_index], 0, 35, 33)
	)
	var icon := ICON_ATLAS.get_image().get_region(
		Rect2i(ICON_X[rarity_index], ICON_Y[source_row], 21, ICON_HEIGHT[source_row])
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
