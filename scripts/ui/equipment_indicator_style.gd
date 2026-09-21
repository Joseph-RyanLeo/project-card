class_name EquipmentIndicatorStyle
extends RefCounted

## 装备指示物由“阵营底座 + 装备类型/品级图案”实时合成并缓存。

const CardFactionScript = preload("res://scripts/data/card_faction.gd")
const BASE_ATLAS: Texture2D = preload(
	"res://assets/card_ui/equipment/source/equipment_indicator_bases.png"
)
const TYPE_ATLAS: Texture2D = preload(
	"res://assets/card_ui/equipment/source/equipment_indicator_types.png"
)
const DISPLAY_SIZE := Vector2(30.0, 30.0) # 装备指示物在卡面与鼠标下保持原图30×30的逻辑尺寸
const INDICATOR_Z_INDEX := 450 # 高于最多三张堆叠卡，叠加目标虚影层后仍低于鼠标携带实体
const SOURCE_SIZE := Vector2i(30, 30) # 用户提供的圆形底座原生1×像素尺寸
const TYPE_CELL_SIZE := Vector2i(23, 23) # 六类装备的每个品级图案统一裁切画布
const BASE_X := [0, 37, 74] # 图1依次为辉光蓝、汉萨红、野性绿的30px底座
const TYPE_COLUMN_X := [2, 39, 76, 113, 150, 175, 212, 249, 286, 323] # 图2左右各五列，对应品级I～V
const TYPE_ROW_Y := [0, 25, 50] # 图2每组三行的裁切起点
const SHADOW_OFFSET := Vector2(1.0, 2.0) # 指示物静止贴在卡面时，右下阴影贴近图标的偏移
const LIFTED_SHADOW_OFFSET := Vector2(3.0, 4.0) # 指示物被悬停或拖起时，阴影拉远形成离开卡面的高度感
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.38) # 指示物立体阴影的透明度
const ORANGE_HUE := 0.075 # 寻路者协会底座的橙色色相
const PURPLE_HUE := 0.765 # 迷宫底座的紫色色相

static var _texture_cache: Dictionary = {}


static func get_texture(card_data: CardData) -> Texture2D:
	if card_data == null:
		return null
	var faction := card_data.get_effective_faction()
	var cache_key := "%d:%d:%d" % [faction, card_data.equipment_type, card_data.rarity]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key] as Texture2D
	var composed := _get_faction_base(faction)
	var icon_region := _get_type_region(card_data.equipment_type, card_data.rarity)
	var icon := TYPE_ATLAS.get_image().get_region(icon_region)
	composed.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), _get_centered_icon_offset(icon))
	var texture := ImageTexture.create_from_image(composed)
	_texture_cache[cache_key] = texture
	return texture


static func _get_centered_icon_offset(icon: Image) -> Vector2i:
	# 每类图案在23px格子里的透明边距不同；以实际非透明像素居中，而非居中格子。
	var visible_rect := icon.get_used_rect()
	return Vector2i(
		floori((SOURCE_SIZE.x - visible_rect.size.x) * 0.5) - visible_rect.position.x,
		floori((SOURCE_SIZE.y - visible_rect.size.y) * 0.5) - visible_rect.position.y
	)


static func create_visual(card_data: CardData, include_shadow: bool = true) -> TextureRect:
	var visual := TextureRect.new()
	visual.texture = get_texture(card_data)
	visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	visual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.size = DISPLAY_SIZE
	visual.custom_minimum_size = DISPLAY_SIZE
	visual.z_index = INDICATOR_Z_INDEX
	if include_shadow:
		var shadow := TextureRect.new()
		shadow.name = "IndicatorShadow"
		shadow.texture = visual.texture
		shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shadow.size = DISPLAY_SIZE
		shadow.position = SHADOW_OFFSET
		shadow.modulate = SHADOW_COLOR
		shadow.show_behind_parent = true
		shadow.z_index = -1
		visual.add_child(shadow)
	return visual


static func _get_faction_base(faction: CardFaction.Id) -> Image:
	var base_index := 0
	match faction:
		CardFaction.Id.HANSA_FEDERATION:
			base_index = 1
		CardFaction.Id.WILD_BEAST_NEST:
			base_index = 2
	var base := BASE_ATLAS.get_image().get_region(
		Rect2i(BASE_X[base_index], 0, SOURCE_SIZE.x, SOURCE_SIZE.y)
	)
	if faction == CardFaction.Id.PATHFINDER_ASSOCIATION:
		_recolor_image_hue(base, ORANGE_HUE)
	elif faction == CardFaction.Id.LABYRINTH:
		_recolor_image_hue(base, PURPLE_HUE)
	return base


static func _get_type_region(
	equipment_type: CardData.EquipmentType,
	rarity: CardData.Rarity
) -> Rect2i:
	var group_column := 0
	var group_row := 0
	match equipment_type:
		CardData.EquipmentType.ACCESSORY:
			group_row = 0
		CardData.EquipmentType.FOCUS:
			group_row = 1
		CardData.EquipmentType.CONSUMABLE:
			group_row = 2
		CardData.EquipmentType.RANGED_WEAPON:
			group_column = 5
			group_row = 0
		CardData.EquipmentType.MELEE_WEAPON:
			group_column = 5
			group_row = 1
		CardData.EquipmentType.ARMOR:
			group_column = 5
			group_row = 2
	var column := group_column + int(rarity)
	return Rect2i(
		TYPE_COLUMN_X[column],
		TYPE_ROW_Y[group_row],
		TYPE_CELL_SIZE.x,
		TYPE_CELL_SIZE.y
	)


static func _recolor_image_hue(image: Image, target_hue: float) -> void:
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			image.set_pixel(
				x,
				y,
				Color.from_hsv(target_hue, pixel.s, pixel.v, pixel.a)
			)
