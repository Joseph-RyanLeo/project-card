extends SceneTree

const CardData = preload("res://scripts/data/card_data.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const OwnedCardCollection = preload("res://scripts/data/owned_card_collection.gd")
const SquadData = preload("res://scripts/data/squad_data.gd")
const CelestialIndicator = preload("res://scripts/data/celestial_indicator.gd")
const BattleController = preload("res://scripts/battle/battle_controller.gd")
const EmblemLibraryData = preload("res://scripts/data/emblem_library_data.gd")
const CardSlotLayout = preload("res://scripts/data/card_slot_layout.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const RunSaveService = preload("res://scripts/data/run_save_service.gd")
const MainScript = preload("res://scripts/main.gd")
const InspectionOverlay = preload("res://scripts/ui/card_inspection_overlay.gd")
const BattleSquadState = preload("res://scripts/battle/battle_squad_state.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_static_modifiers_and_instance_ownership()
	_test_slot_removal_and_snapshot()
	_test_squad_sources_and_battle_values()
	_test_numeric_wound_action_values()
	_test_numeric_wound_mask_and_recovery()
	_test_dark_erosion_blocks_healing_and_lowers_priority()
	_test_greed_unifies_preview_and_battle_value()
	await _test_stacked_sources_and_card_preview()
	print("D2-8 emblem static modifier checks: %d failures" % failures)
	quit(failures)


func _new_card(card_id: StringName) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = String(card_id)
	card.base_value = 2
	card.max_health = 20
	card.armor = 3
	card.cooldown_seconds = 6.0
	card.emblem_slot_count = 4
	card.wound_slot_count = 4
	return card


func _new_owned(card: CardData, instance_id: StringName) -> OwnedCard:
	var owned := OwnedCard.new()
	owned.initialize(card, instance_id, 0)
	return owned


func _set_emblem(owned: OwnedCard, slot_index: int, emblem_id: StringName) -> void:
	owned.set_emblem_slot(slot_index, {
		"instance_id": StringName("%s_%d" % [String(emblem_id), slot_index]),
		"emblem_id": emblem_id,
	})


func _set_wound(owned: OwnedCard, slot_index: int, wound_id: StringName) -> void:
	owned.set_wound_slot(slot_index, {"wound_id": wound_id, "level": 1})


func _test_static_modifiers_and_instance_ownership() -> void:
	var shared_definition := _new_card(&"shared")
	var first := _new_owned(shared_definition, &"owned_a")
	var second := _new_owned(shared_definition, &"owned_b")
	_set_emblem(first, 0, &"长剑")
	_set_emblem(first, 1, &"长剑")
	_set_emblem(first, 2, &"改造")
	_set_emblem(first, 3, &"盾牌Ⅲ")
	first.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 3)
	first.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 2)
	_expect(first.get_effective_base_value() == 7, "两枚长剑各+1，并与独立永久数值成长相加")
	_expect(first.get_effective_max_health() == 21, "改造生命-1与独立永久生命成长+2分别结算")
	_expect(first.get_effective_base_armor() == 9, "改造+2与盾牌Ⅲ+4均计入基础护甲")
	_expect(
		second.get_effective_base_value() == 2
		and second.get_effective_max_health() == 20
		and second.get_effective_base_armor() == 3,
		"共用CardData的另一OwnedCard不受纹章或永久成长污染"
	)
	_expect(
		EmblemLibraryData.get_static_modifier(&"盾牌Ⅲ", &"base_armor") == 4
		and EmblemLibraryData.get_static_modifier(&"盾牌Ⅰ", &"base_armor") == 2
		and EmblemLibraryData.get_static_modifier(&"盾牌Ⅱ", &"base_armor") == 4
		and EmblemLibraryData.get_static_modifier(&"火腿面包", &"max_health") == 4
		and EmblemLibraryData.get_static_modifier(&"羽毛Ⅱ", &"zeal") == 3,
		"混合纹章保留明确静态属性部分，强化与其他特效未混入表中"
	)


func _test_slot_removal_and_snapshot() -> void:
	var definition := _new_card(&"scrape")
	var owned := _new_owned(definition, &"scrape_owner")
	_set_emblem(owned, 0, &"长剑")
	owned.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 2)
	owned.wound_battle_counters[&"misfortune:scrape_owner:wound:0"] = 2
	var saved := owned.capture_state()
	var restored := _new_owned(definition, &"scrape_owner")
	_expect(restored.restore_state(saved), "纹章实例可随OwnedCard状态存取")
	_expect(restored.get_effective_base_value() == 5, "读档后由实例重建加成且只累计一次")
	_expect(restored.restore_state(saved) and restored.get_effective_base_value() == 5, "重复恢复同一快照不会重复累加")
	var save_service := RunSaveService.new()
	var encoded := save_service._encode_collection_state({"cards": [saved]})
	var decoded_result := save_service._decode_collection_state(
		JSON.parse_string(JSON.stringify(encoded)),
		{definition.id: definition}
	)
	var decoded_state := decoded_result.get("state", {}) as Dictionary
	var decoded_cards := decoded_state.get("cards", []) as Array
	var disk_restored := OwnedCard.new()
	var disk_restore_ok := (
		bool(decoded_result.get("success", false))
		and decoded_cards.size() == 1
		and disk_restored.restore_state(decoded_cards[0] as Dictionary)
	)
	_expect(
		disk_restore_ok
		and disk_restored.get_effective_base_value() == 5
		and int(disk_restored.wound_battle_counters.get(&"misfortune:scrape_owner:wound:0", -1)) == 2,
		"JSON存档恢复纹章、永久成长和厄运跨战计数，属性仍只计算一次"
	)
	_expect(restored.set_emblem_slot(0, {}), "刮下纹章可安全写入空字典状态")
	_expect(
		restored.get_effective_base_value() == 4
		and restored.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == 2,
		"刮下后移除纹章贡献并保留独立永久成长"
	)


func _test_squad_sources_and_battle_values() -> void:
	var card := _new_card(&"battle_owner")
	var owned := _new_owned(card, &"battle_owner_instance")
	_set_emblem(owned, 0, &"长剑")
	_set_emblem(owned, 1, &"盾牌Ⅲ")
	_set_emblem(owned, 2, &"羽毛Ⅱ")
	var squad := SquadData.from_owned_card(owned)
	var equipment_data := _new_card(&"equipment")
	equipment_data.card_type = CardData.CardType.EQUIPMENT
	equipment_data.equipment_action_delta = 2
	equipment_data.equipment_health_delta = 5
	equipment_data.equipment_armor_delta = 4
	equipment_data.equipment_zeal_delta = 1
	var equipment := _new_owned(equipment_data, &"equipment_instance")
	squad.equip_item(equipment)
	for kind: int in CelestialIndicator.Kind.values():
		var indicator := CelestialIndicator.new()
		indicator.kind = kind as CelestialIndicator.Kind
		indicator.instance_id = StringName("test_indicator_%d" % kind)
		squad.attach_indicator(indicator, Vector2(49.0, 60.0), kind + 1)
	_expect(
		squad.get_effective_action_base_value() == 9
		and squad.get_effective_max_health() == 31
		and squad.get_effective_base_armor() == 19
		and squad.get_emblem_zeal_delta() == 3,
		"小队属性汇总读取单卡有效槽，热诚保持为热诚层"
	)
	var enemy := SquadData.from_card(_new_card(&"enemy"))
	var battle := BattleController.new()
	root.add_child(battle)
	battle.start_battle(
		[{"squad_data": squad, "row_key": &"player_front", "formation_index": 0}],
		[{"squad_data": enemy, "row_key": &"enemy_front", "formation_index": 0}],
		8811,
		false
	)
	var state := battle.player_states[0]
	var action := battle._build_action(state, battle.enemy_states, CardData.ActionType.MELEE)
	var action_value := (action["base_event"] as BattleEffectEvent).formula.base_value
	_expect(
		state.get_display_action_value() == 9
		and is_equal_approx(action_value, 9.0)
		and state.current_armor == 19
		and is_equal_approx(state.current_health, 31.0),
		"战斗攻击公式、卡面数值、初始护甲与生命读取同一属性汇总"
	)
	_expect(
		state.get_display_action_value() == 9
		and is_equal_approx(state.get_action_interval(), 5.0)
		and is_equal_approx(state.battle_armor_granted, 0.0),
		"装备与日月星仍与纹章加算，热诚换算为行动冷却且初始护甲不算战斗获得"
	)
	battle.free()


func _test_numeric_wound_action_values() -> void:
	var cases: Array[Dictionary] = [
		{"wound": &"骨折Ⅰ", "expected": 1},
		{"wound": &"骨折Ⅱ", "expected": 0},
		{"wound": &"内伤Ⅱ", "expected": 1},
		{"wound": &"内伤Ⅲ", "expected": 0},
		{"wound": &"混乱", "expected": 4},
		{"wound": &"尸毒Ⅱ", "expected": 4},
	]
	for index: int in cases.size():
		var wound_id := cases[index]["wound"] as StringName
		var owner := _new_owned(_new_card(StringName("wound_value_%d" % index)), StringName("wound_value_owner_%d" % index))
		_set_wound(owner, 0, wound_id)
		var squad := SquadData.from_owned_card(owner)
		_expect(
			squad.get_effective_action_base_value() == int(cases[index]["expected"]),
			"显现%s伤势的清晰行动值部分直接进入小队基础行动值" % wound_id
		)


func _test_numeric_wound_mask_and_recovery() -> void:
	var owner := _new_owned(_new_card(&"masked_confusion"), &"masked_confusion_owner")
	_set_wound(owner, 0, &"混乱")
	var squad := SquadData.from_owned_card(owner)
	var enemy_card := _new_card(&"masked_confusion_enemy")
	var battle := BattleController.new()
	root.add_child(battle)
	battle.start_battle(
		[{"squad_data": squad, "row_key": &"player_front", "formation_index": 0}],
		[{"squad_data": SquadData.from_card(enemy_card), "row_key": &"enemy_front", "formation_index": 0}],
		8812,
		false
	)
	var state := battle.player_states[0]
	var wound_id := StringName("%s:wound:0" % owner.instance_id)
	var first_mask := state.mask_injury(wound_id, 101)
	var second_mask := state.mask_injury(wound_id, 202)
	var masked_action_value := state.get_display_action_value()
	var removed_first := state.unmask_injury(wound_id, 101)
	var still_masked_action_value := state.get_display_action_value()
	var removed_second := state.unmask_injury(wound_id, 202)
	var restored_action_value := state.get_display_action_value()
	var action := battle._build_action(state, battle.enemy_states, CardData.ActionType.MELEE)
	var formula := action.get("base_event") as BattleEffectEvent if not action.is_empty() else null
	_expect(
		first_mask and second_mask
		and masked_action_value == 2
		and removed_first and still_masked_action_value == 2
		and removed_second and restored_action_value == 4
		and formula != null and is_equal_approx(formula.formula.base_value, 4.0),
		"多重遮蔽只在最后一个来源解除后恢复混乱行动值，公式来源与生效值同步"
	)
	battle.clear_battle()
	battle.free()


func _test_dark_erosion_blocks_healing_and_lowers_priority() -> void:
	var owner := _new_owned(_new_card(&"dark_erosion_owner"), &"dark_erosion_owned")
	_set_wound(owner, 0, &"暗蚀")
	var battle := BattleController.new()
	root.add_child(battle)
	var ordinary_squad := SquadData.from_card(_new_card(&"dark_erosion_ordinary_candidate"))
	battle.start_battle(
		[
			{"squad_data": SquadData.from_owned_card(owner), "row_key": &"player_front", "formation_index": 0},
			{"squad_data": ordinary_squad, "row_key": &"player_front", "formation_index": 1},
		],
		[{"squad_data": SquadData.from_card(_new_card(&"dark_erosion_enemy")), "row_key": &"enemy_front", "formation_index": 0}],
		8813,
		false
	)
	var state := battle.player_states[0]
	var ordinary_state := battle.player_states[1]
	var sun := CelestialIndicator.new()
	sun.instance_id = &"dark_priority_sun"
	sun.kind = CelestialIndicator.Kind.SUN
	ordinary_state.squad_data.attach_indicator(sun, Vector2.ZERO, 0)
	var low_priority := BattleModifier.new()
	low_priority.stat = BattleModifier.Stat.TARGET_PRIORITY
	low_priority.value = -99.0
	ordinary_state.modifiers.add_modifier(low_priority)
	var ordinary_weight_floor := ordinary_state.get_target_weight()
	ordinary_state.modifiers.remove_modifier_ids([low_priority.modifier_id])
	state.current_health = 10.0
	var ordinary_priority := CardData.get_base_target_priority_for_action(state.get_effective_action_type())
	var blocked_healing := state.apply_healing_exact(5.0)
	var dark_priority := state.get_target_weight()
	var dazzling_target := battle.choose_base_target(
		battle.enemy_states[0], battle.player_states, CardData.ActionType.MELEE, 0
	)
	ordinary_state.moon_shadowed = true
	var shadowed_dazzling_target := battle.choose_base_target(
		battle.enemy_states[0], battle.player_states, CardData.ActionType.MELEE, 0
	)
	var priority_card := load("res://scenes/ui/CardView.tscn").instantiate() as CardView
	root.add_child(priority_card)
	priority_card.set_card_data(owner.card_data)
	priority_card.set_battle_action_type(state.get_effective_action_type())
	priority_card.set_battle_target_weight(dark_priority)
	priority_card._mouse_hovered = true
	priority_card._refresh_priority_label()
	var dark_priority_label_text := priority_card.priority_label.text
	var injury_id := StringName("%s:wound:0" % owner.instance_id)
	var masked := state.mask_injury(injury_id, 303)
	var healing_after_mask := state.apply_healing_exact(5.0)
	priority_card.set_battle_target_weight(state.get_target_weight())
	_expect(
		is_zero_approx(blocked_healing)
		and is_equal_approx(state.current_health, 15.0)
		and dark_priority == maxi(ordinary_priority - 4, 1)
		and ordinary_weight_floor == 1
		and priority_card.priority_label.visible
		and dark_priority_label_text == str(dark_priority)
		and dazzling_target == ordinary_state
		and shadowed_dazzling_target == state
		and masked
		and is_equal_approx(healing_after_mask, 5.0)
		and priority_card.priority_label.text == str(ordinary_priority)
		and state.get_target_weight() == ordinary_priority,
		"显现暗蚀禁止治疗并降低受击优先级−4，遮蔽后两项效果都恢复"
	)
	var removed_wound := owner.set_wound_slot(0, {})
	priority_card.set_battle_target_weight(state.get_target_weight())
	_expect(
		removed_wound
		and state.get_target_weight() == ordinary_priority
		and priority_card.priority_label.text == str(ordinary_priority),
		"移除暗蚀后实际与卡面受击权重都恢复基础值"
	)
	priority_card.free()
	battle.clear_battle()
	battle.free()


func _test_greed_unifies_preview_and_battle_value() -> void:
	var owner := _new_owned(_new_card(&"greed_owner"), &"greed_owned")
	_set_wound(owner, 0, &"贪婪")
	var squad := SquadData.from_owned_card(owner)
	var battle := BattleController.new()
	root.add_child(battle)
	battle.start_battle(
		[{"squad_data": squad, "row_key": &"player_front", "formation_index": 0}],
		[{"squad_data": SquadData.from_card(_new_card(&"greed_enemy")), "row_key": &"enemy_front", "formation_index": 0}],
		8814,
		false
	)
	var state := battle.player_states[0]
	var injury_id := StringName("%s:wound:0" % owner.instance_id)
	var battle_action_before_mask := state.get_action_base_value()
	var unreinforced_action_before_mask := state.get_action_value_without_reinforcement()
	var masked := state.mask_injury(injury_id, 404)
	_expect(
		squad.get_effective_action_base_value() == 1
		and battle_action_before_mask == 1
		and unreinforced_action_before_mask == 2
		and masked
		and state.get_action_base_value() == 2,
		"贪婪把备战、战斗基础行动值统一为1，遮蔽后恢复原值"
	)
	battle.clear_battle()
	battle.free()


func _test_stacked_sources_and_card_preview() -> void:
	var left_definition := _new_card(&"left_source")
	var right_definition := _new_card(&"right_source")
	var left := _new_owned(left_definition, &"left_owned")
	var right := _new_owned(right_definition, &"right_owned")
	_set_emblem(right, 0, &"长剑")
	_set_emblem(left, 0, &"羽毛Ⅱ")
	_set_emblem(left, 2, &"名剑")
	_set_emblem(left, 3, &"面包")
	_set_emblem(right, 2, &"盾牌Ⅰ")
	_set_emblem(right, 1, &"改造")
	_set_wound(left, 0, &"内伤Ⅰ")
	_set_wound(left, 2, &"冻僵")
	_set_wound(right, 0, &"撕裂Ⅰ")
	left.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 2)
	right.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 10)
	var squad := SquadData.from_cards([left_definition, right_definition], SquadData.TwoCardLayout.COMPACT)
	squad.layer_cards.assign([right_definition, left_definition])
	squad.bind_owned_card(left_definition, left)
	squad.bind_owned_card(right_definition, right)
	_expect(
		squad.get_visible_emblem_slot_indices(left_definition) == [0, 1]
		and squad.get_effective_action_base_value() == 5,
		"小队行动值只累计左侧行动来源卡未被遮挡的纹章槽"
	)
	squad.layer_cards.assign([left_definition, right_definition])
	var exposed_action_value := squad.get_effective_action_base_value()
	squad.layer_cards.assign([right_definition, left_definition])
	_expect(
		exposed_action_value == 6
		and squad.get_effective_action_base_value() == 5,
		"换层解除名剑遮挡后加成恢复，右卡长剑被遮挡时暂不计入"
	)
	_expect(
		squad.get_effective_action_base_value() == 5
		and squad.get_effective_max_health() == 19
		and squad.get_effective_base_armor() == 7
		and squad.get_visible_status_static_modifier(&"zeal") == 3,
		"小队生命与护甲只取右侧生命来源卡的纹章属性"
	)
	var separated_squad := SquadData.from_owned_card(right)
	_expect(
		separated_squad.get_effective_action_base_value() == 13
		and separated_squad.get_visible_status_static_modifier(&"zeal") == 2
		and right.emblem_slots[0].get("emblem_id") == &"长剑",
		"拆队后长剑与撕裂仍归原OwnedCard，另一张卡的纹章和伤势不随队复制"
	)
	var collection := OwnedCardCollection.new()
	collection.add_existing(left)
	collection.add_existing(right)
	var save_service := RunSaveService.new()
	var encoded := save_service._encode_collection_state(collection.capture_state())
	var decoded := save_service._decode_collection_state(
		JSON.parse_string(JSON.stringify(encoded)),
		{left_definition.id: left_definition, right_definition.id: right_definition}
	)
	var restored_collection := OwnedCardCollection.new()
	var decoded_state := decoded.get("state", {}) as Dictionary
	var loaded_ok := bool(decoded.get("success", false)) and restored_collection.restore_state(decoded_state)
	var restored_left := restored_collection.get_by_instance_id(left.instance_id)
	var restored_right := restored_collection.get_by_instance_id(right.instance_id)
	var restored_squad := SquadData.from_cards([left_definition, right_definition], SquadData.TwoCardLayout.COMPACT)
	restored_squad.layer_cards.assign([right_definition, left_definition])
	loaded_ok = (
		loaded_ok
		and restored_left != null
		and restored_right != null
		and restored_squad.bind_owned_card(left_definition, restored_left)
		and restored_squad.bind_owned_card(right_definition, restored_right)
	)
	_expect(
		loaded_ok
		and restored_squad.get_effective_action_base_value() == 5
		and restored_squad.get_visible_status_static_modifier(&"zeal") == 3,
		"小队跨OwnedCard纹章与伤势经JSON恢复后按实例累计一次"
	)
	var state := BattleSquadState.new()
	state.initialize(squad, BattleSquadState.Side.PLAYER, &"player_front", 0)
	var inner_injury_id := StringName("left_owned:wound:0")
	var tearing_injury_id := StringName("right_owned:wound:0")
	var hidden_injury_id := StringName("left_owned:wound:2")
	_expect(
		state.get_unmasked_active_injuries().has(inner_injury_id)
		and state.get_unmasked_active_injuries().has(tearing_injury_id)
		and not state.get_unmasked_active_injuries().has(hidden_injury_id)
		and state.get_zeal_layers() == 3
		and is_equal_approx(state.get_action_interval(), 6.0 / 1.15),
		"可见伤势的负热诚与正热诚各计一次，物理遮挡的冻僵不生效"
	)
	_expect(
		state.mask_injury(inner_injury_id, 71)
		and state.get_zeal_layers() == 5
		and state.unmask_injury(inner_injury_id, 71)
		and state.get_zeal_layers() == 3,
		"既有效果遮蔽按伤势实例临时移除修正，解除后恢复，不复制或多次触发"
	)
	var enemy := SquadData.from_card(_new_card(&"stack_enemy"))
	var battle := BattleController.new()
	root.add_child(battle)
	battle.start_battle(
		[{"squad_data": squad, "row_key": &"player_front", "formation_index": 0}],
		[{"squad_data": enemy, "row_key": &"enemy_front", "formation_index": 0}],
		9921,
		false
	)
	var battle_state := battle.player_states[0]
	var action := battle._build_action(battle_state, battle.enemy_states, CardData.ActionType.MELEE)
	_expect(
		battle_state.get_display_action_value() == 5
		and is_equal_approx((action["base_event"] as BattleEffectEvent).formula.base_value, 5.0)
		and battle_state.current_health == 19.0
		and battle_state.current_armor == 7.0,
		"正式战斗的行动公式、生命和护甲均读取小队全体有效附加属性"
	)
	battle.free()
	var card_view := load("res://scenes/ui/CardView.tscn").instantiate() as CardView
	root.add_child(card_view)
	card_view.set_card_data(left_definition)
	card_view.set_owned_card(left)
	card_view.set_squad_attribute_preview_from_squad(squad)
	await process_frame
	_expect(
		card_view.value_label.text == "5",
		"桌面卡面预览显示与小队统计相同的纹章后数值"
	)
	left.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 2)
	card_view.set_squad_attribute_preview_from_squad(squad)
	_expect(
		squad.get_effective_action_base_value() == 7 and card_view.value_label.text == "5",
		"贴纸属性已提交后，卡面从当前显示值开始补间"
	)
	await create_timer(0.1).timeout
	_expect(
		int(card_view.value_label.text) >= 5 and int(card_view.value_label.text) <= 7,
		"行动值补间在新旧值之间推进"
	)
	left.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 1)
	card_view.set_squad_attribute_preview_from_squad(squad)
	await create_timer(CardView.BATTLE_NUMBER_TWEEN_DURATION + 0.05).timeout
	_expect(
		card_view.value_label.text == "8",
		"快速连续属性更新最终到达最新目标值"
	)
	left.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, -2)
	card_view.set_squad_attribute_preview_from_squad(squad)
	_expect(
		squad.get_effective_action_base_value() == 6 and card_view.value_label.text == "8",
		"行动值降低时数据立即提交，显示从当前值开始补间"
	)
	await create_timer(CardView.BATTLE_NUMBER_TWEEN_DURATION + 0.05).timeout
	_expect(card_view.value_label.text == "6", "行动值减小补间抵达新目标")
	card_view.free()
	var vitals_card_view := load("res://scenes/ui/CardView.tscn").instantiate() as CardView
	root.add_child(vitals_card_view)
	vitals_card_view.set_card_data(right_definition)
	vitals_card_view.set_owned_card(right)
	vitals_card_view.set_squad_attribute_preview_from_squad(squad)
	await process_frame
	_expect(
		vitals_card_view.health_label.text == "19"
		and vitals_card_view.armor_label.text == "7",
		"右侧生命来源卡面显示小队实际生命上限与基础护甲"
	)
	right.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 2)
	right.apply_permanent_growth(OwnedCard.STAT_BASE_ARMOR, 1)
	vitals_card_view.set_squad_attribute_preview_from_squad(squad)
	_expect(
		squad.get_effective_max_health() == 21
		and squad.get_effective_base_armor() == 8
		and vitals_card_view.health_label.text == "19"
		and vitals_card_view.armor_label.text == "7",
		"生命与护甲基础数据已提交，旧显示值开始补间"
	)
	await create_timer(CardView.BATTLE_NUMBER_TWEEN_DURATION + 0.05).timeout
	_expect(
		vitals_card_view.health_label.text == "21"
		and vitals_card_view.armor_label.text == "8",
		"生命上限与基础护甲同时抵达新值"
	)
	right.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, -4)
	right.apply_permanent_growth(OwnedCard.STAT_BASE_ARMOR, -3)
	vitals_card_view.set_squad_attribute_preview_from_squad(squad)
	await create_timer(CardView.BATTLE_NUMBER_TWEEN_DURATION + 0.05).timeout
	_expect(
		vitals_card_view.health_label.text == "17"
		and vitals_card_view.armor_label.text == "5",
		"生命与护甲减少时也抵达最新数值"
	)
	vitals_card_view.free()
	var overlay := InspectionOverlay.new() as Control
	root.add_child(overlay)
	var paused_card := load("res://scenes/ui/CardView.tscn").instantiate() as CardView
	overlay.add_child(paused_card)
	paused_card.set_card_data(left_definition)
	paused_card.set_owned_card(left)
	paused_card.set_squad_attribute_preview_from_squad(squad)
	await process_frame
	paused = true
	left.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 1)
	paused_card.set_squad_attribute_preview_from_squad(squad)
	await create_timer(CardView.BATTLE_NUMBER_TWEEN_DURATION + 0.05, true).timeout
	_expect(
		paused_card.value_label.text == "7",
		"检视层中的卡面数值补间在场景树暂停时仍播放"
	)
	paused = false
	overlay.free()
	await _test_paste_and_scrape_updates_card_view()


func _test_paste_and_scrape_updates_card_view() -> void:
	root.size = Vector2i(1280, 720)
	var main := load("res://scenes/Main.tscn").instantiate() as MainScript
	root.add_child(main)
	await process_frame
	await process_frame
	var source_slot: Control
	var owned: OwnedCard
	for candidate: Control in main._get_collection_card_slots():
		var candidate_owned := candidate.get_meta("owned_card", null) as OwnedCard
		if candidate_owned != null and candidate_owned.emblem_slots.size() > 0:
			source_slot = candidate
			owned = candidate_owned
			break
	if owned == null:
		_expect(false, "測試場景提供具有纹章槽的真实OwnedCard")
		main.free()
		return
	var source_card := source_slot.get_child(0) as CardView
	var base_value := owned.get_effective_base_value()
	owned.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 2)
	main._open_card_inspection(owned.card_data, owned, source_card)
	await process_frame
	var long_sword: Dictionary = {}
	for definition: Dictionary in main.emblem_library.get_definitions():
		if definition.get("id", &"") == &"长剑":
			long_sword = definition
			break
	var drag_data := {
		"kind": &"emblem_library",
		"source_type": &"emblem_library",
		"emblem_id": &"长剑",
		"definition": long_sword,
	} as Dictionary
	var point := _first_empty_emblem_position(owned)
	if long_sword.is_empty() or not main._can_drop_emblem_on_inspection_card(main._inspection_card_view, point, drag_data):
		_expect(false, "真实纹章库长剑可以放入检视卡合法空槽")
		main.free()
		return
	main._drop_emblem_on_inspection_card(main._inspection_card_view, point, drag_data)
	await process_frame
	_expect(
		owned.get_effective_base_value() == base_value + 3
		and main._inspection_card_view.value_label.text == str(base_value + 3)
		and main._inspection_card_view.get_node("StatusSlotLayer").get_child_count() == 1,
		"检视中粘贴长剑后属性即时生效并显示，且与永久成长相加"
	)
	var scraper := {"kind": &"sticker_scraper"} as Dictionary
	_expect(
		main._drop_emblem_on_inspection_card(main._inspection_card_view, point, scraper)
		and owned.get_effective_base_value() == base_value + 2
		and main._inspection_card_view.get_node("StatusSlotLayer").get_child_count() == 0
		and owned.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == 2,
		"检视中刮下长剑后立即还原其贡献并保留独立永久成长"
	)
	main.free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


func _first_empty_emblem_position(owned: OwnedCard) -> Vector2:
	for slot: Dictionary in CardSlotLayout.get_slot_definitions(owned.card_data, owned):
		if int(slot.get("kind", -1)) != CardSlotLayout.Kind.EMBLEM:
			continue
		var slot_index := int(slot.get("storage_index", -1))
		if slot_index >= 0 and slot_index < owned.emblem_slots.size() and owned.emblem_slots[slot_index].is_empty():
			return (slot.get("position", Vector2.ZERO) as Vector2) + Vector2(7, 7)
	return Vector2.INF
