extends SceneTree

## 法术/装备占位卡面与收藏事务集成检查。
## 这些卡只验证静态 CardData 和共享 CardView 的显示，不接入战斗状态。

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/ui/CardView.tscn")
const TUNER_SCENE: PackedScene = preload("res://scenes/tools/CardArtTuner.tscn")
const PLACEHOLDER_PATHS := [
	"res://resources/cards/frostfang_blade.tres",
	"res://resources/cards/azure_hunt_bow.tres",
	"res://resources/cards/mana_tonic.tres",
	"res://resources/cards/glacial_crossbow.tres",
	"res://resources/cards/emberbrand_sword.tres",
	"res://resources/cards/sapphire_plate.tres",
	"res://resources/cards/seastone_ring.tres",
	"res://resources/cards/tidecaller_scepter.tres",
	"res://resources/cards/restoration_flask.tres",
	"res://resources/cards/stormstring_bow.tres",
	"res://resources/cards/inferno_edge.tres",
	"res://resources/cards/royal_aegis.tres",
	"res://resources/cards/starsea_ring.tres",
	"res://resources/cards/void_orb_scepter.tres",
	"res://resources/cards/bloodrage_elixir.tres",
	"res://resources/cards/blessing_sacred_shield.tres",
	"res://resources/cards/blessing_strength.tres",
	"res://resources/cards/blessing_vitality.tres",
	"res://resources/cards/summon_undead_army.tres",
	"res://resources/cards/summon_resurrection.tres",
	"res://resources/cards/summon_scarab_swarm.tres",
	"res://resources/cards/damage_fireball.tres",
	"res://resources/cards/damage_sandstorm.tres",
	"res://resources/cards/damage_ice_cone.tres",
	"res://resources/cards/support_healing_aura.tres",
	"res://resources/cards/support_repulsion_aura.tres",
	"res://resources/cards/disruption_counterspell.tres",
	"res://resources/cards/disruption_rust_blade.tres",
	"res://resources/cards/disruption_discordant_wave.tres",
]

var _failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var cards: Array[CardData] = []
	var unique_ids := {}
	for path: String in PLACEHOLDER_PATHS:
		var card := load(path) as CardData
		_expect(card != null, "占位资源可载入：%s" % path.get_file())
		if card == null:
			continue
		cards.append(card)
		unique_ids[card.id] = true
	_expect(cards.size() == 29 and unique_ids.size() == 29, "manifest 对应 29 张资源且 id 唯一")
	_test_data_mappings(cards)
	await _test_card_views(cards)
	await _test_collection_and_illegal_drops(cards)
	await _test_tuner()
	if _failure_count == 0:
		print("Placeholder card checks passed.")
	else:
		push_error("Placeholder card checks failed: %d" % _failure_count)
	quit(_failure_count)


func _test_data_mappings(cards: Array[CardData]) -> void:
	var equipment_cards: Array[CardData] = []
	var spell_cards: Array[CardData] = []
	for card: CardData in cards:
		if card.card_type == CardData.CardType.EQUIPMENT:
			equipment_cards.append(card)
		else:
			spell_cards.append(card)
	_expect(equipment_cards.size() == 15 and spell_cards.size() == 14, "占位资源包含 15 张装备与 14 张法术")
	for index: int in equipment_cards.size():
		_expect(equipment_cards[index].rarity == index % 5, "装备第 %d 张按 I～V 循环稀有度" % (index + 1))
	for index: int in spell_cards.size():
		_expect(spell_cards[index].rarity == index % 5, "法术第 %d 张按 I～V 循环稀有度" % (index + 1))
	_expect(
		spell_cards[0].spell_type == CardData.SpellType.ENHANCE
		and spell_cards[3].spell_type == CardData.SpellType.SUMMON
		and spell_cards[6].spell_type == CardData.SpellType.DAMAGE
		and spell_cards[9].spell_type == CardData.SpellType.SUPPORT
		and spell_cards[11].spell_type == CardData.SpellType.DISRUPTION,
		"法术中文类型映射到单一 SpellType 字段"
	)
	_expect(
		equipment_cards[0].equipment_type == CardData.EquipmentType.MELEE_WEAPON
		and equipment_cards[1].equipment_type == CardData.EquipmentType.RANGED_WEAPON
		and equipment_cards[5].equipment_type == CardData.EquipmentType.ARMOR
		and equipment_cards[6].equipment_type == CardData.EquipmentType.ACCESSORY
		and equipment_cards[7].equipment_type == CardData.EquipmentType.FOCUS
		and equipment_cards[2].equipment_type == CardData.EquipmentType.CONSUMABLE,
		"装备中文类型映射到单一 EquipmentType 字段"
	)
	_expect(
		equipment_cards[0].equipment_action_delta > 0
		and equipment_cards[1].equipment_action_delta < 0
		and absf(equipment_cards[0].equipment_cooldown_delta) == 0.5,
		"装备占位数据覆盖正负行动与冷却变化量"
	)


func _test_card_views(cards: Array[CardData]) -> void:
	var spell := cards[15]
	var equipment_positive := cards[0]
	var equipment_negative := cards[1]
	var spell_view := CARD_VIEW_SCENE.instantiate() as CardView
	root.add_child(spell_view)
	spell_view.set_card_data(spell)
	await process_frame
	var spell_badge := spell_view.action_icon.texture as AtlasTexture
	var spell_type_icon := spell_view.race_icon.texture as AtlasTexture
	_expect(
		spell_badge != null
		and spell_badge.atlas == CardView.SPELL_RARITY_BADGE_TEXTURE
		and spell_badge.region == CardView.SPELL_RARITY_BADGE_REGIONS[spell.rarity]
		and spell_view.action_icon.position == CardView.SPELL_RARITY_BADGE_POSITION,
		"法术左上稀有度使用 I、V、IV、III、II 的显式图集映射"
	)
	_expect(
		spell_type_icon != null
		and spell_type_icon.atlas == CardView.SPELL_TYPE_ATLAS
		and spell_view.rune_row.visible == false
		and spell_view.effect_text_label.visible
		and not spell_view.cooldown_icon.visible
		and not spell_view.health_icon.visible
		and not spell_view.armor_icon.visible,
		"法术使用中央类型图标，隐藏符文/状态并显示效果文字"
	)
	var positive_view := CARD_VIEW_SCENE.instantiate() as CardView
	root.add_child(positive_view)
	positive_view.set_card_data(equipment_positive)
	await process_frame
	_expect(
		positive_view.action_icon.texture == CardView.EQUIPMENT_ACTION_INCREASE_TEXTURE
		and positive_view.action_icon.position == CardView.EQUIPMENT_ACTION_POSITION
		and CardView.EQUIPMENT_ACTION_INCREASE_TEXTURE.get_image().get_used_rect()
		== Rect2i(2, 3, 24, 24)
		and positive_view.value_label.text == "1"
		and positive_view.cooldown_icon.texture == CardView.COOLDOWN_HOURGLASS_TEXTURE
		and positive_view.health_icon.texture == CardView.HEALTH_TEXTURE
		and positive_view.armor_icon.texture == CardView.ARMOR_TEXTURE
		and positive_view.value_label is RuneNumberDisplay
		and positive_view.cooldown_label is RuneNumberDisplay
		and positive_view.rune_row.visible == false
		and positive_view.effect_text_label.visible,
		"装备正值使用完整绿色箭头且不夹带沙漏残片，并复用卢恩数字与状态图标"
	)
	var negative_view := CARD_VIEW_SCENE.instantiate() as CardView
	root.add_child(negative_view)
	negative_view.set_card_data(equipment_negative)
	await process_frame
	_expect(
		negative_view.action_icon.texture == CardView.EQUIPMENT_ACTION_DECREASE_TEXTURE
		and CardView.EQUIPMENT_ACTION_DECREASE_TEXTURE.get_image().get_used_rect()
		== Rect2i(2, 3, 24, 24)
		and negative_view.value_label.text == "1"
		and negative_view.rune_row.visible == false,
		"装备负值显示红色下箭头且数字取绝对值"
	)
	for view: CardView in [spell_view, positive_view, negative_view]:
		view.queue_free()
	await process_frame


func _test_collection_and_illegal_drops(cards: Array[CardData]) -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_expect(main.collection_cards.size() == 53, "Main 收藏包含原有 24 张与新增 29 张")
	main.active_card_type_filters.assign([CardData.CardType.SPELL])
	var spells: Array[CardData] = main.get_filtered_collection_cards()
	_expect(spells.size() == 14 and spells.all(func(card: CardData) -> bool: return card.card_type == CardData.CardType.SPELL), "收藏法术种类筛选只显示 14 张法术")
	main.active_card_type_filters.assign([CardData.CardType.EQUIPMENT])
	var equipment: Array[CardData] = main.get_filtered_collection_cards()
	_expect(equipment.size() == 15 and equipment.all(func(card: CardData) -> bool: return card.card_type == CardData.CardType.EQUIPMENT), "收藏装备种类筛选只显示 15 张装备")
	main.active_card_type_filters.clear()
	main.active_action_filters.assign([CardData.ActionType.MELEE])
	var action_filtered: Array[CardData] = main.get_filtered_collection_cards()
	_expect(action_filtered.all(func(card: CardData) -> bool: return card.card_type == CardData.CardType.MINION), "行动筛选不把法术/装备当作随从行动实体")
	main.active_action_filters.clear()
	main.search_query = "强化"
	var searched: Array[CardData] = main.get_filtered_collection_cards()
	_expect(searched.size() == 3 and searched.all(func(card: CardData) -> bool: return card.card_type == CardData.CardType.SPELL), "搜索可匹配法术类型中文")
	main.search_query = ""
	var spell_drag := {
		"kind": &"card",
		"card_data": cards[15],
		"source_type": &"collection",
	}
	var before_count: int = main.collection_cards.size()
	var spell_drop_intent: Dictionary = spell_drag.duplicate()
	spell_drop_intent["drop_intent"] = {}
	_expect(
		not main._transfer_card(spell_drag, &"board", main.front_row, 0)
		and not main._transfer_drop_intent(spell_drop_intent, main.front_row)
		and not main.front_row.can_receive_card_drag(spell_drag)
		and not main.collection_drop_zone.preview_card_drop(Vector2.ZERO, spell_drag)
		and main.collection_cards.size() == before_count,
		"法术非法落点统一拒绝且收藏不丢失、不复制"
	)
	main.queue_free()
	await process_frame


func _test_tuner() -> void:
	var tuner := TUNER_SCENE.instantiate()
	root.add_child(tuner)
	await process_frame
	var group_counts: Array[int] = []
	for item_index: int in tuner.card_type_selector.item_count:
		tuner.card_type_selector.select(item_index)
		tuner.card_type_selector.emit_signal("item_selected", item_index)
		await process_frame
		group_counts.append(tuner.card_selector.item_count)
	_expect(
		group_counts == [24, 14, 15]
		and group_counts.reduce(func(sum: int, count: int) -> int: return sum + count, 0) == 53,
		"CardArtTuner 以随从/法术/装备滚动分组覆盖全部 53 张卡"
	)
	tuner.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failure_count += 1
		push_error("FAIL: %s" % message)
