class_name SpellPreparationIconStyle
extends RefCounted

## 底色表示阵营，中央图案表示启动类别与品级；共用于令牌、拖拽和落位预览。

const FACTION_BASES := {
	CardFaction.Id.RADIANT_ALLIANCE: preload("res://assets/ui/board_revision_20261019/spell_base_prepared.png"),
	CardFaction.Id.HANSA_FEDERATION: preload("res://assets/ui/board_revision_20261019/spell_base_conditional.png"),
	CardFaction.Id.WILD_BEAST_NEST: preload("res://assets/ui/board_revision_20261019/spell_base_instant.png"),
	CardFaction.Id.LABYRINTH: preload("res://assets/ui/board_revision_20261019/spell_base_labyrinth.png"),
}
const PATHFINDER_COLOR := Color("d67a22") # 寻路者协会使用橙色内底，保留原生边框
const UNALIGNED_COLOR := Color("777777") # 未归属法术使用灰色内底
const ICON_ATLAS: Texture2D = preload("res://assets/card_ui/spells/source/preparation_icons.png")
const DISPLAY_SIZE := Vector2(42.0, 42.0) # 法术准备栏图标保持底座原生42×42像素
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


static func get_texture(source_column: int, rarity: CardData.Rarity, faction: CardFaction.Id = CardFaction.Id.UNALIGNED) -> Texture2D:
	if source_column < 0 or source_column >= ICON_X.size():
		return null
	var rarity_index := int(rarity)
	if rarity_index < 0 or rarity_index >= ICON_Y.size():
		return null
	var cache_key := Vector3i(source_column, rarity_index, int(faction))
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key] as Texture2D
	var base_texture: Texture2D = FACTION_BASES.get(faction, FACTION_BASES[CardFaction.Id.RADIANT_ALLIANCE])
	var base := base_texture.get_image().duplicate() as Image
	if not FACTION_BASES.has(faction):
		var original_color := base.get_pixel(10, 10)
		var faction_color := PATHFINDER_COLOR if faction == CardFaction.Id.PATHFINDER_ASSOCIATION else UNALIGNED_COLOR
		for y: int in base.get_height():
			for x: int in base.get_width():
				if base.get_pixel(x, y).is_equal_approx(original_color): base.set_pixel(x, y, faction_color)
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
