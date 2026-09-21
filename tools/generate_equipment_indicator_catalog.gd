extends SceneTree

## 用游戏运行时的同一合成逻辑生成装备指示物总览，避免预览图与实战图标分叉。

const EquipmentIndicatorStyle = preload("res://scripts/ui/equipment_indicator_style.gd")
const OUTPUT_PATH := "res://assets/card_ui/equipment/equipment_indicator_catalog.png"
const ICON_SIZE: int = 30 # 总览中每个装备图标使用原生30×30像素，不进行放大
const ICON_GAP: int = 2 # 同阵营相邻图标之间的透明间隔
const FACTION_GAP: int = 8 # 不同阵营图标组之间的透明间隔
const FACTIONS := [
	CardFaction.Id.RADIANT_ALLIANCE,
	CardFaction.Id.HANSA_FEDERATION,
	CardFaction.Id.WILD_BEAST_NEST,
	CardFaction.Id.PATHFINDER_ASSOCIATION,
	CardFaction.Id.LABYRINTH,
]
const TYPES := [
	CardData.EquipmentType.RANGED_WEAPON,
	CardData.EquipmentType.MELEE_WEAPON,
	CardData.EquipmentType.ARMOR,
	CardData.EquipmentType.ACCESSORY,
	CardData.EquipmentType.FOCUS,
	CardData.EquipmentType.CONSUMABLE,
]


func _initialize() -> void:
	var width: int = FACTIONS.size() * CardData.Rarity.size() * ICON_SIZE
	width += FACTIONS.size() * (CardData.Rarity.size() - 1) * ICON_GAP
	width += (FACTIONS.size() - 1) * FACTION_GAP
	var height: int = TYPES.size() * ICON_SIZE + (TYPES.size() - 1) * ICON_GAP
	var catalog := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	catalog.fill(Color.TRANSPARENT)
	for faction_index: int in FACTIONS.size():
		for rarity_index: int in CardData.Rarity.size():
			for type_index: int in TYPES.size():
				var card := CardData.new()
				card.card_type = CardData.CardType.EQUIPMENT
				card.faction = FACTIONS[faction_index]
				card.rarity = rarity_index
				card.equipment_type = TYPES[type_index]
				var icon := EquipmentIndicatorStyle.get_texture(card).get_image()
				if icon.get_size() != Vector2i(ICON_SIZE, ICON_SIZE):
					push_error("总览图发现非30×30装备图标")
					quit(1)
					return
				var x: int = faction_index * (
					CardData.Rarity.size() * ICON_SIZE
					+ (CardData.Rarity.size() - 1) * ICON_GAP
					+ FACTION_GAP
				) + rarity_index * (ICON_SIZE + ICON_GAP)
				var y: int = type_index * (ICON_SIZE + ICON_GAP)
				catalog.blit_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), Vector2i(x, y))
	var result := catalog.save_png(OUTPUT_PATH)
	if result != OK:
		push_error("无法保存装备指示物总览图：%s" % error_string(result))
		quit(1)
		return
	print("装备指示物总览已生成：%s，%d×%d" % [OUTPUT_PATH, width, height])
	quit()
