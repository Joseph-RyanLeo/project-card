extends SceneTree

## D2-6B素材与正式装备卡的轻量回归：仅验证真实资源、图集和卡面，不替占位法术编造效果。

const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/ui/CardView.tscn")
const SpellPreparationIconStyle = preload("res://scripts/ui/spell_preparation_icon_style.gd")
const ResourceIndicatorStyle = preload("res://scripts/ui/resource_indicator_style.gd")
const EFFECT_DATA_PATH := "res://data/demo2/ash_ledger_effect_samples.json"

const SPELL_TRIGGER_COUNTS := {
	CardData.SpellTriggerKind.INSTANT: 5,
	CardData.SpellTriggerKind.CONDITIONAL: 5,
	CardData.SpellTriggerKind.PREPARED: 4,
}
const FORMAL_EQUIPMENT := {
	&"ash_war_banner": {"rarity": CardData.Rarity.III, "type": CardData.EquipmentType.MELEE_WEAPON, "action": 1, "zeal": 0, "armor": 0},
	&"ash_war_shield": {"rarity": CardData.Rarity.II, "type": CardData.EquipmentType.ARMOR, "action": 0, "zeal": -1, "armor": 4},
	&"rally_horn": {"rarity": CardData.Rarity.II, "type": CardData.EquipmentType.ACCESSORY, "action": 0, "zeal": 0, "armor": 0},
	&"coarse_bandage": {"rarity": CardData.Rarity.I, "type": CardData.EquipmentType.ACCESSORY, "action": 0, "zeal": 0, "armor": 1},
	&"recruitment_ledger": {"rarity": CardData.Rarity.I, "type": CardData.EquipmentType.CONSUMABLE, "action": 0, "zeal": 1, "armor": 0},
}

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_asset_regions()
	_test_spell_assignments_and_badges()
	_test_resource_card_face()
	_test_formal_equipment()
	if failures == 0:
		print("D2-6B asset and card checks passed.")
	else:
		push_error("D2-6B asset and card checks failed: %d" % failures)
	quit(failures)


func _test_asset_regions() -> void:
	for rarity_index: int in CardData.Rarity.size():
		var rarity := rarity_index as CardData.Rarity
		for column: int in 3:
			var spell_icon := SpellPreparationIconStyle.get_texture(column, rarity)
			_expect(spell_icon != null and spell_icon.get_size() == Vector2(42, 42), "法术准备图标按原生42×42组合：%d/%d" % [column, rarity_index])
		for row: int in 4:
			var resource_icon := ResourceIndicatorStyle.get_texture(rarity, row)
			var card_type_icon := ResourceIndicatorStyle.get_card_type_texture(rarity, row)
			_expect(resource_icon != null and resource_icon.get_size() == Vector2(35, 33), "资源指示物按原生35×33组合：%d/%d" % [rarity_index, row])
			_expect(card_type_icon != null and card_type_icon.get_size().x == 11.0, "资源卡种类小图按品级和类别裁切：%d/%d" % [rarity_index, row])
		_expect(ResourceIndicatorStyle.get_badge_region(rarity).size == Vector2(21, 26), "资源袋角标保留21×26原生尺寸：%d" % rarity_index)


func _test_spell_assignments_and_badges() -> void:
	var counts := {CardData.SpellTriggerKind.INSTANT: 0, CardData.SpellTriggerKind.CONDITIONAL: 0, CardData.SpellTriggerKind.PREPARED: 0}
	var directory := DirAccess.open("res://resources/cards")
	for filename: String in directory.get_files():
		if not filename.ends_with(".tres"):
			continue
		var card := load("res://resources/cards/%s" % filename) as CardData
		if card == null or card.card_type != CardData.CardType.SPELL:
			continue
		counts[card.spell_trigger_kind] = int(counts.get(card.spell_trigger_kind, 0)) + 1
		_expect(card.get_spell_preparation_column() in [0, 1, 2] and SpellPreparationIconStyle.source_column_for_trigger(card.spell_trigger_kind) in [0, 1, 2], "占位法术有固定准备栏列与素材列：%s" % card.id)
		var view := CARD_VIEW_SCENE.instantiate() as CardView
		root.add_child(view)
		view.set_card_data(card)
		var icon := view.action_icon.texture as AtlasTexture
		var old_center := CardView.SPELL_RARITY_BADGE_POSITION + CardView.SPELL_RARITY_BADGE_SIZE * 0.5
		_expect(icon != null and icon.atlas == SpellPreparationIconStyle.ICON_ATLAS and (view.action_icon.position + view.action_icon.size * 0.5).is_equal_approx(old_center), "法术牌左上触发图案与旧角标同心：%s" % card.id)
		view.free()
	_expect(counts == SPELL_TRIGGER_COUNTS, "14张占位法术触发类别固定为即时5、条件5、准备4")
	var instant := CardData.new()
	instant.spell_trigger_kind = CardData.SpellTriggerKind.INSTANT
	var conditional := CardData.new()
	conditional.spell_trigger_kind = CardData.SpellTriggerKind.CONDITIONAL
	var prepared := CardData.new()
	prepared.spell_trigger_kind = CardData.SpellTriggerKind.PREPARED
	_expect(instant.get_spell_preparation_column() == 0 and conditional.get_spell_preparation_column() == 1 and prepared.get_spell_preparation_column() == 2, "准备栏从左到右固定为即时、条件、准备，不受素材原列序影响")


func _test_resource_card_face() -> void:
	var card := CardData.new()
	card.id = &"d2_6b_resource_face"
	card.display_name = "测试资源"
	card.card_type = CardData.CardType.RESOURCE
	card.rarity = CardData.Rarity.IV
	card.resource_type = CardData.ResourceType.RELIC
	card.max_health = 3
	var view := CARD_VIEW_SCENE.instantiate() as CardView
	root.add_child(view)
	view.set_card_data(card)
	var badge := view.action_icon.texture as AtlasTexture
	var center_icon := view.race_icon.texture as AtlasTexture
	_expect(badge != null and badge.atlas == ResourceIndicatorStyle.BADGE_ATLAS and badge.region == ResourceIndicatorStyle.get_badge_region(card.rarity), "资源卡左上角使用相应品级的资源袋")
	_expect(center_icon != null and center_icon.get_size() == Vector2(11, 9) and view.race_icon.visible, "资源卡立绘下部使用对应品级与种类的小图")
	_expect(view.health_label.text == "3" and view.health_icon.visible and not view.armor_icon.visible and not view.cooldown_icon.visible and not view.value_label.visible, "资源卡保留右下生命，隐藏随从专属行动、护甲和冷却")
	view.free()


func _test_formal_equipment() -> void:
	var catalog := BattleEffectCatalog.load_from_file(EFFECT_DATA_PATH)
	_expect(catalog.is_valid(), "灰烬征册正式效果目录仍可严格解析")
	for card_id: StringName in FORMAL_EQUIPMENT:
		var card := load("res://resources/cards/%s.tres" % card_id) as CardData
		var expected := FORMAL_EQUIPMENT[card_id] as Dictionary
		_expect(card != null and card.pack_id == &"ash_ledger" and card.card_type == CardData.CardType.EQUIPMENT and card.rarity == expected["rarity"] and card.equipment_type == expected["type"] and card.equipment_action_delta == expected["action"] and card.equipment_zeal_delta == expected["zeal"] and card.equipment_armor_delta == expected["armor"], "正式装备遵守已确认品级、类型和当前热诚方向：%s" % card_id)
		_expect(card != null and card.effect_ids == catalog.card_effect_ids.get(card_id, []), "正式装备绑定已确认的全部效果ID：%s" % card_id)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
