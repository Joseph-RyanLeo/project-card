class_name SpellPreparationIconStyle
extends RefCounted

## 将法术启动类别的底座与对应品级图案裁切、居中，合成为准备栏图标。

const BASE_ATLAS: Texture2D = preload("res://assets/card_ui/spells/source/preparation_bases.png")
const ICON_ATLAS: Texture2D = preload("res://assets/card_ui/spells/source/preparation_icons.png")
const DISPLAY_SIZE := Vector2(42.0, 42.0) # 法术准备栏图标保持底座原生42×42像素
const BASE_X := [0, 64, 127] # 原图从左到右：条件、准备、即时
const ICON_X := [0, 64, 126] # 图案原图从左到右：条件、准备、即时
const ICON_WIDTH := [24, 24, 26] # 三列图案的原生宽度
const ICON_Y := [0, 41, 86, 125, 170] # 图案从上到下对应I～V品级
const ICON_HEIGHT: int = 32 # 每个法术启动图案的原生高度

static var _texture_cache: Dictionary = {}


static func source_column_for_trigger(kind: CardData.SpellTriggerKind) -> int:
	match kind:
		CardData.SpellTriggerKind.CONDITIONAL:
			return 0
		CardData.SpellTriggerKind.PREPARED:
			return 1
		CardData.SpellTriggerKind.INSTANT:
			return 2
		_:
			return -1


static func get_texture(source_column: int, rarity: CardData.Rarity) -> Texture2D:
	if source_column < 0 or source_column >= BASE_X.size():
		return null
	var rarity_index := int(rarity)
	if rarity_index < 0 or rarity_index >= ICON_Y.size():
		return null
	var cache_key := Vector2i(source_column, rarity_index)
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key] as Texture2D
	var base := BASE_ATLAS.get_image().get_region(
		Rect2i(BASE_X[source_column], 0, 42, 42)
	)
	var icon := ICON_ATLAS.get_image().get_region(
		Rect2i(ICON_X[source_column], ICON_Y[rarity_index], ICON_WIDTH[source_column], ICON_HEIGHT)
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


static func get_icon_region(source_column: int, rarity: CardData.Rarity) -> Rect2:
	if source_column < 0 or source_column >= ICON_X.size():
		return Rect2()
	var rarity_index := int(rarity)
	if rarity_index < 0 or rarity_index >= ICON_Y.size():
		return Rect2()
	return Rect2(
		ICON_X[source_column],
		ICON_Y[rarity_index],
		ICON_WIDTH[source_column],
		ICON_HEIGHT
	)
