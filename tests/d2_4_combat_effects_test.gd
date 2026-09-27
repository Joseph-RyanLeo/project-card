extends SceneTree

## D2-4 第二小步：验证不依赖战后写回/资源系统的真实随从战中事件链。

const BattleControllerScript = preload("res://scripts/battle/battle_controller.gd")
const BattlePermanentGrowthLedger = preload("res://scripts/battle/battle_permanent_growth_ledger.gd")
const BattleRunRewardLedger = preload("res://scripts/battle/battle_run_reward_ledger.gd")
const BattleFormulaPresenter = preload("res://scripts/battle/battle_formula_presenter.gd")
const BattleDiagnosticRecorder = preload("res://scripts/battle/battle_diagnostic_recorder.gd")
const BattleDiagnosticSerializer = preload("res://scripts/battle/battle_diagnostic_serializer.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const BoardSlotScene: PackedScene = preload("res://scenes/ui/BoardSlot.tscn")

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_action_multiplier_and_continuous_recheck()
	_test_fireman_rush_health_growth()
	_test_armor_gain_and_echo_events()
	_test_other_and_adjacent_ally_death_events()
	_test_dynamic_attribute_auras()
	_test_neighbor_targeting_and_priority()
	_test_other_ally_action_reinforcement()
	_test_armor_multiplier_before_neighbor_addition()
	_test_old_wolf_neighbor_extra_execution()
	_test_javelin_opening_neighbor_aura_barrier()
	_test_javelin_rush_action_switch()
	_test_mudleg_last_wish_masks_active_rune()
	_test_mudleg_reentry_position_conflict()
	_test_recruiter_pending_random_card_request()
	_test_baggage_muleteer_pending_gold()
	_test_field_medic_temporary_injury_mask()
	_test_berserker_pending_base_value_growth()
	_test_armorsmith_pending_armor_growth()
	if failures == 0:
		print("D2-4 combat effect wiring checks passed.")
	else:
		push_error("D2-4 combat effect wiring checks failed: %d" % failures)
	quit(failures)


func _test_action_multiplier_and_continuous_recheck() -> void:
	var controller := _controller_with(
		[
			_entry(_card("rune_engraver"), &"player_front", 0),
			_entry(_card("ember_squire"), &"player_front", 1),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24101
	)
	var militia := controller.player_states[1]
	_expect(
		is_equal_approx(militia.modifiers.get_additive(BattleModifier.Stat.ACTION_MULTIPLIER), 0.1)
		and is_equal_approx(militia.get_exact_action_amount(), 9.9),
		"符文刻匠把+0.1行动倍率接入正式数值公式"
	)
	militia.current_armor = 0.0
	controller.effect_runtime.recheck_continuous_conditions()
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(is_zero_approx(militia.modifiers.get_additive(BattleModifier.Stat.ACTION_MULTIPLIER)), "护甲归零后实时撤销符文刻匠修正")
	militia.current_armor = 1.0
	controller.effect_runtime.recheck_continuous_conditions()
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(is_equal_approx(militia.modifiers.get_additive(BattleModifier.Stat.ACTION_MULTIPLIER), 0.1), "重新获得护甲后恢复符文刻匠修正且不重复累加")
	_dispose(controller)


func _test_fireman_rush_health_growth() -> void:
	var controller := _controller_with(
		[
			_entry(_card("fireman"), &"player_back", 0),
			_entry(_card("ember_squire"), &"player_front", 0),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24102
	)
	var fireman := controller.player_states[0]
	_expect(fireman.get_max_health() == 8 and is_equal_approx(fireman.current_health, 8.0), "伙夫本场生命+4叠加显现水符文基础生命+2")
	_dispose(controller)


func _test_armor_gain_and_echo_events() -> void:
	var armor_controller := _controller_with(
		[
			_entry(_card("ember_squire"), &"player_front", 0),
			_entry(_card("shieldwall_private"), &"player_front", 1),
			_entry(_card("militia"), &"player_front", 2),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24103
	)
	var shieldwall := armor_controller.player_states[1]
	var direct_armor_records: Array[Dictionary] = []
	armor_controller.special_effect_resolved.connect(
		func(record: Dictionary) -> void: direct_armor_records.append(record.duplicate(true))
	)
	var armor_before := float(shieldwall.current_armor)
	armor_controller.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.SOURCE_ARMOR_GAINED, {"actor": shieldwall, "amount": 3.0})
	armor_controller.effect_runtime.process_due(armor_controller.elapsed_seconds)
	_expect(
		is_equal_approx(float(shieldwall.current_armor), armor_before + 1.0)
		and direct_armor_records.size() == 1
		and direct_armor_records[0].get("kind", "") == "armor"
		and direct_armor_records[0].get("source_card_name", "") == "盾墙列兵"
		and direct_armor_records[0].get("target_card_name", "") == "盾墙列兵"
		and is_equal_approx(float(direct_armor_records[0].get("effective_amount", 0.0)), 1.0),
		"盾墙列兵直接护甲效果保留中文卡名、目标与实际+1并阻止递归"
	)
	_dispose(armor_controller)

	var echo_controller := _controller_with(
		[
			_entry(_card("war_drum_musician"), &"player_back", 0),
			_entry(_card("militia"), &"player_back", 1),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24104
	)
	var drummer := echo_controller.player_states[0]
	var ally := echo_controller.player_states[1]
	echo_controller.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": drummer})
	echo_controller.effect_runtime.process_due(echo_controller.elapsed_seconds)
	_expect(
		drummer.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 0.0
		and ally.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 1.0,
		"战鼓乐师回响只由自身行动触发，并强化同排相邻友军而不强化自己"
	)
	echo_controller.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": ally})
	echo_controller.effect_runtime.process_due(echo_controller.elapsed_seconds)
	_expect(ally.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 1.0, "其他单位行动不会误触发战鼓乐师的来源绑定回响")
	_dispose(echo_controller)


func _test_other_and_adjacent_ally_death_events() -> void:
	var controller := _controller_with(
		[
			_entry(_card("elegy_poet"), &"player_front", 0),
			_entry(_card("militia"), &"player_front", 1),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24105
	)
	var poet := controller.player_states[0]
	var victim := controller.player_states[1]
	victim.current_health = 0.0
	controller._finalize_batch()
	_expect(
		poet.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 1.0
		and poet.modifiers.get_additive(BattleModifier.Stat.BASE_ARMOR) == 1.0
		and is_equal_approx(float(poet.current_armor), 4.0),
		"非衍生友军死亡后，悲歌诗人的数值与护甲两步共用一次死亡事件"
	)
	_dispose(controller)


func _test_dynamic_attribute_auras() -> void:
	var commander_controller := _controller_with(
		[
			_entry(_card("militia_commander"), &"player_front", 0),
			_entry(_card("ember_squire"), &"player_front", 1),
			_entry(_card("militia"), &"player_front", 2),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24106
	)
	var commander := commander_controller.player_states[0]
	var middle_human := commander_controller.player_states[1]
	var right_human := commander_controller.player_states[2]
	_expect(
		commander.get_max_health() == 8
		and middle_human.get_max_health() == 24
		and right_human.get_max_health() == 7
		and is_equal_approx(float(commander.current_health), 8.0)
		and is_equal_approx(float(middle_human.current_health), 24.0)
		and is_equal_approx(float(right_human.current_health), 7.0),
		"民兵指挥官按每个目标自己的相邻人类数量实时提供生命，并同步当前生命"
	)
	right_human.current_health = 0.0
	commander_controller._finalize_batch()
	_expect(
		middle_human.get_max_health() == 22
		and is_equal_approx(float(middle_human.current_health), 24.0)
		and middle_human.displayed_health == 24,
		"相邻人类退场后只撤销生命上限，保留当前生命及卡面显示"
	)
	middle_human.current_health = 1.0
	commander.current_health = 0.0
	commander_controller._finalize_batch()
	_expect(
		middle_human.get_max_health() == 20
		and is_equal_approx(float(middle_human.current_health), 1.0)
		and middle_human.displayed_health == 1
		and middle_human.alive,
		"指挥官退场不会把低生命目标随上限加成一起扣到0血"
	)
	_dispose(commander_controller)

	var diplomat_controller := _controller_with(
		[
			_entry(_card("diplomat"), &"player_back", 0),
			_entry(_card("ember_squire"), &"player_front", 0),
			_entry(_card("musketeer"), &"player_front", 1),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24107
	)
	_expect(
		diplomat_controller.player_states[0].modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH) == 0.0
		and diplomat_controller.player_states[1].modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH) == 2.0
		and diplomat_controller.player_states[2].modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH) == 2.0,
		"外交官只给非精灵友军提供实时生命值+2"
	)
	_dispose(diplomat_controller)


func _test_neighbor_targeting_and_priority() -> void:
	var controller := _controller_with(
		[
			_entry(_card("ember_squire"), &"player_front", 0),
			_entry(_card("militia"), &"player_front", 1),
			_entry(_card("ember_squire"), &"player_front", 2),
			_entry(_card("armorsmith"), &"player_back", 0),
			_entry(_card("musketeer"), &"player_back", 1),
			_entry(_card("armorsmith"), &"player_back", 2),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24108
	)
	_expect(
		controller.player_states[0].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 1.0
		and controller.player_states[1].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 1.0
		and controller.player_states[2].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 1.0,
		"民兵左右都有同种族单位时，自己与两侧人类单兵都获得数值+1"
	)
	var musketeer := controller.player_states[4]
	_expect(musketeer.get_target_weight() == 0 and controller.get_effective_target_weight(musketeer) == 0, "火枪手乡邻-3与显现光符文+1相抵后仍可降到专属下限0")
	controller.player_states[2].current_health = 0.0
	controller.player_states[5].current_health = 0.0
	controller._finalize_batch()
	_expect(
		controller.player_states[0].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 0.0
		and controller.player_states[1].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 0.0
		and musketeer.get_target_weight() == 3,
		"任意一侧缺少同种族存活单位后，乡邻实时失效并撤销全部目标修正"
	)
	_dispose(controller)


func _test_other_ally_action_reinforcement() -> void:
	var controller := _controller_with(
		[
			_entry(_card("timid_infantry"), &"player_front", 0),
			_entry(_card("ember_squire"), &"player_front", 1),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24109
	)
	var timid := controller.player_states[0]
	var ally := controller.player_states[1]
	for _index: int in 6:
		controller.effect_runtime.notify_action_after(ally)
		controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(timid.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 5.0, "胆怯的步兵只累计其他友军行动且本效果封顶5强化")
	controller.effect_runtime.notify_action_after(timid)
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(timid.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 0.0, "胆怯的步兵自身行动后消费并清空本效果强化")
	_dispose(controller)


func _test_armor_multiplier_before_neighbor_addition() -> void:
	var controller := _controller_with(
		[
			_entry(_card("anvil_margaret"), &"player_back", 0),
			_entry(_card("anvil_margaret"), &"player_back", 1),
			_entry(_card("ember_squire"), &"player_front", 0),
			_entry(_card("shieldwall_private"), &"player_front", 1),
			_entry(_card("ember_squire"), &"player_front", 2),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24110
	)
	var shieldwall := controller.player_states[3]
	var armor_before := float(shieldwall.current_armor)
	var event := BattleEffectEvent.new()
	event.source = shieldwall
	event.target = shieldwall
	event.action_type = CardData.ActionType.DEFENSE
	event.effect_kind = BattleEffectEvent.EffectKind.ARMOR
	event.exact_amount = 3.0
	event.formula = BattleFormulaData.create("护甲", CardData.ActionType.DEFENSE, 3.0, 1.0, 1.0, shieldwall, shieldwall)
	controller._apply_effect_event(event)
	_expect(
		is_equal_approx(float(shieldwall.current_armor), armor_before + 7.0)
		and is_equal_approx(event.exact_amount, 6.0),
		"玛格丽特同名不叠加，基础3护甲先×2、再结算盾墙+1得到7"
	)
	_dispose(controller)


func _test_old_wolf_neighbor_extra_execution() -> void:
	var militia_controller := _controller_with(
		[
			_entry(_card("ember_squire"), &"player_front", 0),
			_entry(_card("militia"), &"player_front", 1),
			_entry(_card("ember_squire"), &"player_front", 2),
			_entry(_card("old_wolf_kaspar"), &"player_back", 0),
			_entry(_card("old_wolf_kaspar"), &"player_back", 1),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24111
	)
	var left_human := militia_controller.player_states[0]
	var militia := militia_controller.player_states[1]
	var right_human := militia_controller.player_states[2]
	var first_wolf := militia_controller.player_states[3]
	var second_wolf := militia_controller.player_states[4]
	_expect(
		militia.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 3.0
		and left_human.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 3.0
		and right_human.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 3.0,
		"左右人类使民兵乡邻成立，两只老狼各追加一次后三个目标都合计+3"
	)
	first_wolf.current_health = 0.0
	militia_controller._finalize_batch()
	_expect(militia.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 2.0, "一只老狼退场后，民兵乡邻实时回落为两次执行")
	var militia_actions := militia_controller._select_base_actions(
		[militia], militia_controller.get_all_states()
	)
	var militia_event := militia_actions[0].get("base_event") as BattleEffectEvent if not militia_actions.is_empty() else null
	var militia_popup := BattleFormulaPresenter.format_popup(militia_event.formula) if militia_event != null else ""
	var contribution_values: Array[float] = []
	if militia_event != null:
		for modifier_source: Dictionary in militia_event.formula.action_value_modifier_sources:
			for contribution_value: Variant in modifier_source.get("contribution_sources", []) as Array:
				if contribution_value is Dictionary:
					contribution_values.append(float((contribution_value as Dictionary).get("amount", 0.0)))
	_expect(
		militia_event != null
		and is_equal_approx(militia_event.formula.calculate_result(), militia_event.exact_amount)
		and is_equal_approx(militia.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE), 2.0)
		and contribution_values == [1.0, 1.0]
		and militia_popup.contains("民兵")
		and militia_popup.contains("老狼")
		and militia_popup.contains("基础数值  3")
		and militia_popup.contains("+1")
		and not militia_popup.contains("强化  +2"),
		"民兵乡邻的两个+1分别保留来源并合入基础数值，结算仍只加+2"
	)
	second_wolf.current_health = 0.0
	militia_controller._finalize_batch()
	_expect(militia.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 1.0, "全部老狼退场后，民兵保留自身一次乡邻效果")
	_dispose(militia_controller)

	var musketeer_controller := _controller_with(
		[
			_entry(_card("armorsmith"), &"player_front", 0),
			_entry(_card("musketeer"), &"player_front", 1),
			_entry(_card("armorsmith"), &"player_front", 2),
			_entry(_card("old_wolf_kaspar"), &"player_back", 0),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24112
	)
	var musketeer := musketeer_controller.player_states[1]
	var wolf := musketeer_controller.player_states[3]
	_expect(
		musketeer.modifiers.get_additive(BattleModifier.Stat.TARGET_PRIORITY) == -6.0
		and musketeer_controller.get_effective_target_weight(musketeer) == 0,
		"老狼可额外执行火枪手的同名不叠加乡邻效果"
	)
	wolf.current_health = 0.0
	musketeer_controller._finalize_batch()
	_expect(musketeer.modifiers.get_additive(BattleModifier.Stat.TARGET_PRIORITY) == -3.0, "老狼退场后只撤销自己提供的额外执行次数")
	_dispose(musketeer_controller)


func _test_javelin_rush_action_switch() -> void:
	var scaled_javelin := (_card("javelin_skirmisher") as CardData).duplicate(true) as CardData
	var scaled_owner := OwnedCard.new()
	scaled_owner.initialize(scaled_javelin, &"javelin_scaled_value", 1)
	scaled_owner.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 2.0)
	var scaled_squad := SquadData.from_owned_card(scaled_owner)
	var temporary_item := CardData.new()
	temporary_item.id = &"temporary_value_item"
	temporary_item.card_type = CardData.CardType.EQUIPMENT
	temporary_item.equipment_action_delta = 2
	var temporary_owner := OwnedCard.new()
	temporary_owner.initialize(temporary_item, &"temporary_value_item", 1)
	_expect(scaled_squad.equip_item(temporary_owner), "测试装备可挂到标枪散兵身上")
	_expect(
		scaled_squad.get_effective_action_base_value() == 6
		and scaled_squad.get_effective_action_base_value([], false, true, 0.5) == 4,
		"本局永久+2先并入基础值后减半，装备临时+2不减半"
	)
	var controller := BattleControllerScript.new() as BattleController
	root.add_child(controller)
	controller.use_projectile_timing = true
	var javelin_card := (_card("javelin_skirmisher") as CardData).duplicate(true) as CardData
	javelin_card.emblem_slot_count = 1
	javelin_card.runes.assign([CardData.ElementType.FIRE, CardData.ElementType.FIRE, CardData.ElementType.FIRE])
	var javelin_owner := OwnedCard.new()
	javelin_owner.initialize(javelin_card, &"javelin_with_ham_bread", 1)
	javelin_owner.set_emblem_slot(0, {"emblem_id": &"火腿面包", "instance_id": &"javelin_ham_bread"})
	var javelin_squad := SquadData.from_owned_card(javelin_owner)
	var launches: Array[Dictionary] = []
	var resolved_events: Array[BattleEffectEvent] = []
	controller.projectile_launched.connect(func(event: BattleEffectEvent) -> void:
		launches.append({
			"event": event,
			"action_type_at_launch": event.source.get_effective_action_type(),
		})
	)
	controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		resolved_events.append(event)
	)
	controller.start_battle(
		[{"squad_data": javelin_squad, "row_key": &"player_front", "formation_index": 0}],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24113,
		false
	)
	var skirmisher := controller.player_states[0]
	var source_card := skirmisher.get_action_source()
	var launch_event := launches[0]["event"] as BattleEffectEvent if launches.size() == 1 else null
	var has_plus_nine_reinforcement := false
	var launch_popup := BattleFormulaPresenter.format_popup(launch_event.formula) if launch_event != null else ""
	if launch_event != null:
		for term: Dictionary in launch_event.formula.additive_terms:
			if term.get("name") == "强化" and is_equal_approx(float(term.get("value", 0.0)), 9.0):
				has_plus_nine_reinforcement = true
	var contribution_names: Array[String] = []
	if launch_event != null:
		for source: Dictionary in launch_event.formula.reinforcement_modifier_sources:
			for contribution: Dictionary in source.get("contribution_sources", []) as Array:
				contribution_names.append(String(contribution.get("source_name", "")))
	_expect(
		launches.size() == 1
		and launch_event != null
		and launch_event.action_type == CardData.ActionType.RANGED
		and int(launches[0]["action_type_at_launch"]) == CardData.ActionType.RANGED
		and has_plus_nine_reinforcement
		and launch_event.formula.reinforcement_modifier_sources.size() == 4
		and contribution_names.has("火符文")
		and contribution_names.has("火腿面包")
		and launch_popup.contains("标枪散兵 · 火符文")
		and launch_popup.contains("标枪散兵 · 火腿面包")
		and launch_popup.contains("+3")
		and is_zero_approx(controller.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)),
		"标枪散兵突击不额外强化，三枚火符文+6与火腿面包+3合计+9并由本次远程行动消费"
	)
	_expect(
		skirmisher.get_effective_action_type() == CardData.ActionType.MELEE
		and skirmisher.get_target_weight() == 4
		and source_card.action_type == CardData.ActionType.RANGED,
		"远程弹道发射后只把战斗状态锁定为近战，不修改CardData"
	)
	var enemy := controller.enemy_states[0]
	var health_before := float(enemy.current_health)
	if launch_event != null:
		controller.advance_time(maxf(launch_event.impact_time - controller.elapsed_seconds, 0.0) + 0.01)
	var derived_event_count := 0
	var all_derived_events_use_same_reinforcement := true
	if launch_event != null:
		for resolved_event: BattleEffectEvent in resolved_events:
			if resolved_event.group_id != launch_event.group_id or resolved_event.logical_layer <= 0:
				continue
			derived_event_count += 1
			var derived_reinforcement := 0.0
			for term: Dictionary in resolved_event.formula.additive_terms:
				if term.get("name") == "强化":
					derived_reinforcement += float(term.get("value", 0.0))
			all_derived_events_use_same_reinforcement = (
				all_derived_events_use_same_reinforcement
		and is_equal_approx(derived_reinforcement, 9.0)
		and resolved_event.formula.reinforcement_modifier_sources.size() == 4
			)
	_expect(
		float(enemy.current_health) < health_before
		and derived_event_count > 0
		and all_derived_events_use_same_reinforcement
		and is_zero_approx(skirmisher.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)),
		"元素派生沿用同一+9强化快照，而战斗状态不因派生事件再次消费或留下强化"
	)
	var next_actions := controller._select_base_actions([skirmisher], controller.get_all_states())
	var next_event := next_actions[0]["base_event"] as BattleEffectEvent if next_actions.size() == 1 else null
	_expect(
		next_event != null
		and next_event.action_type == CardData.ActionType.MELEE
		and is_equal_approx(next_event.formula.base_value, 1.0)
		and next_event.formula.additive_terms.all(func(term: Dictionary) -> bool: return term.get("name") != "即时行动数值修正"),
		"标枪散兵之后的普通行动使用近战、基础数值减半且不再获得突击强化"
	)
	if next_event != null:
		controller._apply_effect_event(next_event)
	var damage_by_action := (
		skirmisher.get_battle_statistics().get("damage_dealt_by_action", {}) as Dictionary
	)
	_expect(
		float(damage_by_action.get(CardData.ActionType.RANGED, 0.0)) > 0.0
		and float(damage_by_action.get(CardData.ActionType.MELEE, 0.0)) > 0.0,
		"标枪散兵的突击远程伤害与后续近战伤害分别写入结算统计"
	)
	controller.effect_runtime.notify_battle_end()
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(skirmisher.get_effective_action_type() == CardData.ActionType.RANGED, "战斗结束后清除近战覆盖并恢复资源原始远程类型")
	_dispose(controller)


func _test_javelin_opening_neighbor_aura_barrier() -> void:
	var valid_formation: Array[Dictionary] = [
		_entry(_card("ember_squire"), &"player_front", 0),
		_entry(_card("militia"), &"player_front", 1),
		_opening_javelin_entry(&"javelin_with_aura", &"player_front", 2),
		_entry(_card("old_wolf_kaspar"), &"player_back", 0),
	]
	var with_wolf := _opening_javelin_controller(valid_formation, 24114, true)
	var controller := with_wolf.get("controller") as BattleController
	var launches := with_wolf.get("launches") as Array[BattleEffectEvent]
	var event := launches[0] if not launches.is_empty() else null
	var aura_trace_index := -1
	var launch_trace_index := -1
	var trace_order := with_wolf.get("trace_order") as Array[String]
	for index: int in trace_order.size():
		if trace_order[index].begins_with("aura_applied:") and aura_trace_index < 0:
			aura_trace_index = index
		if trace_order[index] == "javelin_launched" and launch_trace_index < 0:
			launch_trace_index = index
	var action_bonus := 0.0
	var reinforcement := 0.0
	var sources: Array[String] = []
	var popup := ""
	if event != null:
		for term: Dictionary in event.formula.additive_terms:
			if term.get("name") == "效果数值修正":
				action_bonus += float(term.get("value", 0.0))
			elif term.get("name") == "强化":
				reinforcement += float(term.get("value", 0.0))
		for modifier_source: Dictionary in event.formula.action_value_modifier_sources:
			for contribution: Dictionary in modifier_source.get("contribution_sources", []) as Array:
				sources.append(String(contribution.get("source_name", "")))
		popup = BattleFormulaPresenter.format_popup(event.formula)
	print("开场 t=0 顺序：", trace_order)
	_expect(
		event != null
		and is_equal_approx(action_bonus, 2.0)
		and is_equal_approx(reinforcement, 3.0)
		and aura_trace_index >= 0
		and launch_trace_index > aura_trace_index
		and sources.has("民兵")
		and sources.has("“老狼”卡斯帕")
		and popup.contains("民兵")
		and popup.contains("“老狼”卡斯帕"),
		"开场持续乡邻先完整应用，再建立标枪公式：民兵与老狼来源合计+2，强化来自火腿面包+3"
	)
	var derived_count := 0
	var derived_consistent := true
	if event != null:
		controller.advance_time(maxf(event.impact_time - controller.elapsed_seconds, 0.0) + 2.0)
		for derived: BattleEffectEvent in with_wolf.get("resolved_events") as Array[BattleEffectEvent]:
			if derived.group_id != event.group_id or derived.element_type != CardData.ElementType.LIGHT:
				continue
			derived_count += 1
			var derived_reinforcement := 0.0
			for term: Dictionary in derived.formula.additive_terms:
				if term.get("name") == "强化":
					derived_reinforcement += float(term.get("value", 0.0))
			derived_consistent = (
				derived_consistent
				and is_equal_approx(_formula_modifier_total(derived), 2.0)
				and is_equal_approx(derived_reinforcement, 3.0)
				and is_equal_approx(derived.formula.element_multiplier, 0.3)
				and is_equal_approx(derived.formula.exact_result, derived.formula.calculate_result())
				and _source_contribution_signature(derived.formula.action_value_modifier_sources)
					== _source_contribution_signature(event.formula.action_value_modifier_sources)
				and _source_contribution_signature(derived.formula.reinforcement_modifier_sources)
					== _source_contribution_signature(event.formula.reinforcement_modifier_sources)
				and not is_equal_approx(derived.attack_type_multiplier, event.attack_type_multiplier)
			)
	_expect(derived_count == 1 and derived_consistent, "光折射沿用同一行动的+2乡邻来源与+3强化快照，并按新目标命中时护甲重算倍率")
	var exported_sources_match := false
	if event != null:
		var recorded_battle := (with_wolf.get("recorder") as BattleDiagnosticRecorder).get_record_copy()
		var document := BattleDiagnosticSerializer.build_document(recorded_battle)
		var parsed: Variant = JSON.parse_string(BattleDiagnosticSerializer.to_json(document))
		if parsed is Dictionary:
			var timeline: Array = (parsed as Dictionary).get("battle", {}).get("timeline", [])
			for item_value: Variant in timeline:
				if not item_value is Dictionary:
					continue
				var item := item_value as Dictionary
				if (
					item.get("record_type") != "effect_event"
					or item.get("event_type") != "primary_action"
					or int(item.get("group_id", -1)) != event.group_id
				):
					continue
				var exported_formula: Dictionary = item.get("formula", {})
				var direct_formula: Dictionary = {}
				for recorded_value: Variant in recorded_battle.get("timeline", []) as Array:
					if not recorded_value is Dictionary:
						continue
					var recorded_item := recorded_value as Dictionary
					if (
						int(recorded_item.get("group_id", -1)) == event.group_id
						and recorded_item.get("record_type") == "effect_event"
						and recorded_item.get("event_type") == "primary_action"
					):
						direct_formula = recorded_item.get("formula", {})
						break
				exported_sources_match = (
					_source_contribution_signature(exported_formula.get("action_value_modifier_sources", []))
						== _source_contribution_signature(event.formula.action_value_modifier_sources)
					and _source_contribution_signature(exported_formula.get("reinforcement_modifier_sources", []))
						== _source_contribution_signature(event.formula.reinforcement_modifier_sources)
					and _source_contribution_signature(exported_formula.get("action_value_modifier_sources", []))
						== _source_contribution_signature(direct_formula.get("action_value_modifier_sources", []))
					and _source_contribution_signature(exported_formula.get("reinforcement_modifier_sources", []))
						== _source_contribution_signature(direct_formula.get("reinforcement_modifier_sources", []))
				)
				break
	_expect(exported_sources_match, "诊断 JSON 往返保留主攻击的乡邻及强化来源，与战斗事件来源一致")
	if event != null:
		var next_action := controller._build_action(
			event.source,
			controller.get_all_states().filter(func(state: BattleSquadState) -> bool: return state.alive),
			CardData.ActionType.MELEE
		)
		var next_event := next_action.get("base_event") as BattleEffectEvent
		var next_bonus := 0.0
		if next_event != null:
			for term: Dictionary in next_event.formula.additive_terms:
				if term.get("name") == "效果数值修正":
					next_bonus += float(term.get("value", 0.0))
		_expect(
			next_event != null
			and is_equal_approx(next_bonus, 2.0)
			and is_zero_approx(event.source.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)),
			"开场行动后普通行动沿用恰好+2实时光环，不重复叠加强化"
		)
	var militia_state := controller.player_states[1]
	var javelin_state := controller.player_states[2]
	militia_state.current_health = 0.0
	controller._finalize_batch()
	_expect(
		is_zero_approx(javelin_state.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE)),
		"乡邻来源退场后实时撤销开场已生效的数值修正"
	)
	javelin_state.current_health = 0.0
	controller._finalize_batch()
	_expect(
		controller.revive_state_at_original_position(javelin_state, 3.0)
		and launches.size() == 1,
		"标枪复活时沿用每场仅一次的突击限制，不重复建立突击行动"
	)
	_dispose(controller)

	var no_wolf := _opening_javelin_controller(
		[
			_entry(_card("ember_squire"), &"player_front", 0),
			_entry(_card("militia"), &"player_front", 1),
			_opening_javelin_entry(&"javelin_no_wolf", &"player_front", 2),
		],
		24115
	)
	var no_wolf_launches := no_wolf.get("launches") as Array[BattleEffectEvent]
	_expect(
		no_wolf_launches.size() == 1
		and is_equal_approx(_formula_modifier_total(no_wolf_launches[0]), 1.0),
		"没有老狼时，合法乡邻只给标枪+1"
	)
	_dispose(no_wolf.get("controller") as BattleController)

	var invalid_neighbor := _opening_javelin_controller(
		[
			_entry(_card("militia"), &"player_front", 0),
			_opening_javelin_entry(&"javelin_invalid_neighbor", &"player_front", 1),
		],
		24116
	)
	var invalid_launches := invalid_neighbor.get("launches") as Array[BattleEffectEvent]
	_expect(
		invalid_launches.size() == 1
		and is_zero_approx(_formula_modifier_total(invalid_launches[0])),
		"民兵左右未都有友方人类时，标枪不获得乡邻加成"
	)
	_dispose(invalid_neighbor.get("controller") as BattleController)


func _opening_javelin_entry(instance_id: StringName, row_key: StringName, position: int) -> Dictionary:
	var card := (_card("javelin_skirmisher") as CardData).duplicate(true) as CardData
	card.emblem_slot_count = 1
	card.runes.assign([CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.LIGHT])
	var owner := OwnedCard.new()
	owner.initialize(card, instance_id, 1)
	owner.set_emblem_slot(0, {"emblem_id": &"火腿面包", "instance_id": StringName("%s:ham" % instance_id)})
	return {"squad_data": SquadData.from_owned_card(owner), "row_key": row_key, "formation_index": position}


func _opening_javelin_controller(players: Array[Dictionary], seed: int, add_refraction_target: bool = false) -> Dictionary:
	var controller := BattleControllerScript.new() as BattleController
	controller.use_projectile_timing = true
	root.add_child(controller)
	var recorder := BattleDiagnosticRecorder.new()
	recorder.attach(controller)
	var launches: Array[BattleEffectEvent] = []
	var resolved_events: Array[BattleEffectEvent] = []
	var trace_order: Array[String] = []
	controller.projectile_launched.connect(func(event: BattleEffectEvent) -> void:
		if (
			event.is_base_action
			and event.source != null
			and event.source.get_action_source() != null
			and event.source.get_action_source().id == &"javelin_skirmisher"
		):
			trace_order.append("javelin_launched")
			launches.append(event)
	)
	controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void: resolved_events.append(event))
	controller.effect_trace_emitted.connect(func(entry: BattleEffectTraceEntry) -> void:
		if entry.effect_id == &"militia.effect.01" and entry.target_runtime_id == 3 and entry.phase == &"apply" and entry.result == &"applied":
			trace_order.append("aura_applied:%s" % entry.to_text())
	)
	var enemies: Array[Dictionary] = [_entry(_plain_enemy(), &"enemy_front", 0)]
	if add_refraction_target:
		var armored_enemy := _plain_enemy()
		armored_enemy.id = &"rush_aura_armored_enemy"
		armored_enemy.display_name = "开场折射护甲目标"
		armored_enemy.armor = 2
		enemies.append(_entry(armored_enemy, &"enemy_front", 1))
	controller.start_battle(players, enemies, seed, false)
	return {
		"controller": controller,
		"launches": launches,
		"resolved_events": resolved_events,
		"trace_order": trace_order,
		"recorder": recorder,
	}


func _formula_modifier_total(event: BattleEffectEvent) -> float:
	if event == null or event.formula == null:
		return 0.0
	for term: Dictionary in event.formula.additive_terms:
		if term.get("name") == "效果数值修正":
			return float(term.get("value", 0.0))
	return 0.0


func _source_contribution_signature(sources: Variant) -> Array[String]:
	var result: Array[String] = []
	if not sources is Array:
		return result
	for source_value: Variant in sources:
		if not source_value is Dictionary:
			continue
		var source := source_value as Dictionary
		var contributions: Variant = source.get("contribution_sources", [])
		if not contributions is Array:
			continue
		for contribution_value: Variant in contributions:
			if not contribution_value is Dictionary:
				continue
			var contribution := contribution_value as Dictionary
			result.append(
				"%s|%s|%.3f" % [
					String(contribution.get("effect_id", "")),
					String(contribution.get("source_name", "")),
					float(contribution.get("amount", 0.0)),
				]
			)
	result.sort()
	return result


func _test_mudleg_last_wish_masks_active_rune() -> void:
	var mudleg := (_card("mudleg_brothers").duplicate(true) as CardData)
	mudleg.armor = 3
	mudleg.runes.assign([
		CardData.ElementType.FIRE,
		CardData.ElementType.FIRE,
		CardData.ElementType.FIRE,
	])
	var controller := _controller_with(
		[_entry(mudleg, &"player_front", 0)],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24114
	)
	var state := controller.player_states[0]
	_expect(
		state.get_active_runes().size() == 3
		and state.get_rune_pattern_result().pattern_type == RunePatternResult.PatternType.THREE_OF_A_KIND
		and is_equal_approx(state.get_exact_action_amount(), 8.0),
		"泥腿三兄弟阵亡前使用三枚生效符文计算三连牌型"
	)
	controller.enemy_states[0].current_health = 0.0
	controller._finalize_batch()
	_expect(state.masked_rune_slots.is_empty(), "其他单位阵亡不会误触发泥腿三兄弟的来源限定遗愿")
	state.current_armor = 0.0
	var first_lethal_hit := BattleEffectEvent.new()
	first_lethal_hit.source = controller.enemy_states[0]
	first_lethal_hit.target = state
	first_lethal_hit.action_type = CardData.ActionType.MELEE
	first_lethal_hit.effect_kind = BattleEffectEvent.EffectKind.DAMAGE
	first_lethal_hit.exact_amount = float(state.current_health)
	controller._apply_effect_event(first_lethal_hit)
	controller._finalize_batch()
	var masked_by_card := state.get_masked_rune_indices_by_card()
	var masked_indices: Array = masked_by_card.get(mudleg, [])
	_expect(
		masked_indices.size() == 1
		and state.get_active_runes().size() == 2
		and state.get_rune_pattern_result().pattern_type == RunePatternResult.PatternType.PAIR
		and is_equal_approx(state.get_exact_action_amount(), 6.0),
		"遗愿随机遮蔽一枚当前生效符文，并立即重算二连牌型与行动值"
	)
	_expect(
		state.alive
		and is_equal_approx(state.current_health, float(state.get_max_health()))
		and is_equal_approx(state.current_armor, 3.0)
		and state.life_generation == 1,
		"同一次遗愿在原位置满生命重新入场，并恢复卡牌基础护甲"
	)
	_expect(
		is_equal_approx(state.battle_damage_taken, first_lethal_hit.effective_amount)
		and state.battle_damage_taken > 0.0
		and is_equal_approx(
			controller.enemy_states[0].battle_damage_dealt,
			first_lethal_hit.effective_amount
		),
		"泥腿三兄弟重新入场只恢复生命护甲，不会清空阵亡前累计承伤与敌方造成伤害"
	)
	var board_slot := BoardSlotScene.instantiate() as BoardSlot
	root.add_child(board_slot)
	board_slot.set_squad_data(SquadData.from_card(mudleg))
	board_slot.set_battle_status(
		state.displayed_health,
		state.displayed_armor,
		state.remaining_cooldown,
		0,
		state.get_display_action_value(),
		state.runtime_action_type_override,
		state.get_rune_pattern_result(),
		state.get_active_rune_slots(),
		masked_by_card
	)
	var masked_slot_index := int(masked_indices[0])
	var masked_icon := (
		board_slot.get_primary_card_view().rune_row
		.get_child(masked_slot_index).get_child(0) as TextureRect
	)
	_expect(
		board_slot.get_displayed_pattern_result().pattern_type == RunePatternResult.PatternType.PAIR
		and not masked_icon.visible,
		"战场卡面隐藏被遮蔽槽位，并显示遮蔽后的牌型"
	)
	board_slot.queue_free()
	var mask_instance_found := false
	for instance: BattleEffectInstance in controller.effect_runtime.active_instances:
		if instance.active and instance.definition.effect_id == &"mudleg_brothers.effect.02":
			mask_instance_found = true
	_expect(mask_instance_found, "符文遮蔽保存为持续到本场结束的可追踪运行实例")
	state.current_armor = 0.0
	state.current_health = 0.0
	controller._finalize_batch()
	_expect(
		state.alive
		and state.life_generation == 2
		and state.masked_rune_slots.size() == 2
		and state.get_active_runes().size() == 1
		and is_equal_approx(state.current_health, float(state.get_max_health()))
		and is_equal_approx(state.current_armor, 3.0),
		"第二次遗愿继续遮蔽另一枚生效符文，并完成第二次重新入场"
	)
	state.current_health = 0.0
	controller._finalize_batch()
	_expect(
		not state.alive
		and state.life_generation == 2
		and state.masked_rune_slots.size() == 2,
		"遗愿组共享每场两次额度，第三次阵亡不再遮蔽或重新入场"
	)
	controller.effect_runtime.notify_battle_end()
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(
		state.get_active_runes().size() == 3
		and state.masked_rune_slots.is_empty(),
		"战斗结束只清除临时遮蔽，不修改泥腿三兄弟的CardData符文"
	)
	_dispose(controller)


func _test_mudleg_reentry_position_conflict() -> void:
	var mudleg := _card("mudleg_brothers")
	var controller := _controller_with(
		[
			_entry(mudleg, &"player_front", 0),
			_entry(_card("militia"), &"player_front", 1),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24115
	)
	var mudleg_state := controller.player_states[0]
	controller.player_states[1].formation_index = mudleg_state.formation_index
	mudleg_state.current_health = 0.0
	controller._finalize_batch()
	var unavailable_trace_found := false
	for entry: BattleEffectTraceEntry in controller.effect_runtime.traces:
		if (
			entry.effect_id == &"mudleg_brothers.effect.03"
			and entry.result == &"original_position_unavailable"
		):
			unavailable_trace_found = true
	_expect(
		not mudleg_state.alive
		and mudleg_state.life_generation == 0
		and unavailable_trace_found,
		"原位置被存活单位占用时结束本次遗愿，并保留可审计失败轨迹"
	)
	_dispose(controller)


func _test_berserker_pending_base_value_growth() -> void:
	var action_provider := CardData.new()
	action_provider.id = &"growth_action_provider"
	action_provider.display_name = "成长行动来源"
	action_provider.base_value = 3
	action_provider.max_health = 10
	var berserker := (_card("berserker_vanguard").duplicate(true) as CardData)
	berserker.max_health = 20
	var squad := SquadData.from_cards([action_provider, berserker])
	squad.layer_cards.assign([berserker, action_provider])
	var controller := _controller_with(
		[{"squad_data": squad, "row_key": &"player_front", "formation_index": 0}],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24116
	)
	var state := controller.player_states[0]
	var damage_source := controller.enemy_states[0]
	state.apply_direct_health_damage_exact(4.0, damage_source)
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(
		controller.permanent_growth_ledger.get_entries().is_empty()
		and is_equal_approx(state.battle_health_lost, 4.0),
		"狂战先锋累计损失未满8点时不提前消耗本场成长次数"
	)
	state.apply_healing_exact(4.0)
	state.apply_direct_health_damage_exact(4.0, damage_source)
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	var entries := controller.permanent_growth_ledger.get_entries()
	var entry: Dictionary = entries[0] if entries.size() == 1 else {}
	_expect(
		entries.size() == 1
		and entry.get("card_data") == action_provider
		and entry.get("stat") == BattlePermanentGrowthLedger.STAT_BASE_VALUE
		and entry.get("owner_kind") == BattleEffectDefinition.OwnerKind.ACTION_PROVIDER_CARD
		and is_equal_approx(float(entry.get("amount", 0.0)), 1.0),
		"狂战先锋达到8点累计损失后，把永久数值成长归给实际行动来源单卡"
	)
	_expect(
		state.get_display_action_value() == 4
		and action_provider.base_value == 3
		and is_equal_approx(state.battle_health_lost, 8.0),
		"待写回成长立即参与本场行动值，但不修改共享CardData且治疗不倒扣累计量"
	)
	state.apply_direct_health_damage_exact(2.0, damage_source)
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(controller.permanent_growth_ledger.get_entries().size() == 1, "狂战先锋每场最多记录一次永久成长")
	controller.effect_runtime.notify_battle_end()
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(
		controller.permanent_growth_ledger.get_entries().size() == 1
		and state.get_display_action_value() == 4,
		"本局永久成长记录在战斗结束后仍等待D2-5消费"
	)
	_dispose(controller)


func _test_recruiter_pending_random_card_request() -> void:
	var controller := _controller_with(
		[_entry(_card("recruiter"), &"player_front", 0)],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24118
	)
	var entries := controller.run_reward_ledger.get_entries()
	var entry: Dictionary = entries[0] if entries.size() == 1 else {}
	var parameters := entry.get("parameters", {}) as Dictionary
	_expect(
		entries.size() == 1
		and entry.get("kind") == BattleRunRewardLedger.KIND_RANDOM_CARD_REQUEST
		and int(entry.get("amount", 0)) == 1
		and entry.get("owner_kind") == BattleEffectDefinition.OwnerKind.OWNING_PLAYER
		and entry.get("status") == BattleRunRewardLedger.STATUS_PENDING_RUN_RESOLUTION
		and parameters.get("pool") == "available_run_minions"
		and bool(parameters.get("owned_unique_exclusion", false)),
		"征召官只记录带完整筛选参数的随机随从请求，等待D2-5按收藏与卡池结算"
	)
	controller.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.RUSH)
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(controller.run_reward_ledger.get_entries().size() == 1, "征召官重新触发突击也不会突破每场一次")
	controller.effect_runtime.notify_battle_end()
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(controller.run_reward_ledger.get_entries().size() == 1, "随机卡请求保留到正常战后，等待本局系统消费")
	_dispose(controller)


func _test_baggage_muleteer_pending_gold() -> void:
	var controller := _controller_with(
		[
			_entry(_card("old_wolf_kaspar"), &"player_front", 0),
			_entry(_card("baggage_muleteer"), &"player_front", 1),
			_entry(_card("ember_squire"), &"player_front", 2),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24119
	)
	var entries := controller.run_reward_ledger.get_entries()
	var base_amount := 0
	var neighbor_amount := 0
	for entry: Dictionary in entries:
		if entry.get("effect_id") == &"baggage_muleteer.effect.01":
			base_amount += int(entry.get("amount", 0))
		elif entry.get("effect_id") == &"baggage_muleteer.effect.02":
			neighbor_amount += int(entry.get("amount", 0))
	_expect(
		entries.size() == 2
		and base_amount == 1
		and neighbor_amount == 4
		and controller.run_reward_ledger.get_total(
			BattleRunRewardLedger.KIND_GOLD,
			BattleSquadState.Side.PLAYER
		) == 5,
		"辎重驮夫记录基础1金币，乡邻2金币可被一只老狼额外执行为4，合计待结算5金币"
	)
	_dispose(controller)


func _test_field_medic_temporary_injury_mask() -> void:
	var wounded_card := _card("ember_squire").duplicate(true) as CardData
	wounded_card.wound_slot_count = 2
	var wounded_owner := OwnedCard.new()
	wounded_owner.initialize(wounded_card, &"field_medic_wounded_owner", 0)
	wounded_owner.set_wound_slot(0, {"wound_id": &"中毒Ⅰ", "level": 1})
	wounded_owner.set_wound_slot(1, {"wound_id": &"中毒Ⅱ", "level": 2})
	var wounded_squad := SquadData.from_owned_card(wounded_owner)
	var controller := _controller_with(
		[
			_entry(_card("field_medic"), &"player_back", 0),
			{"squad_data": wounded_squad, "row_key": &"player_front", "formation_index": 0},
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24120
	)
	var medic := controller.player_states[0]
	var healed_target := controller.player_states[1]
	var injury_ids: Array[StringName] = [
		StringName("%s:wound:0" % wounded_owner.instance_id),
		StringName("%s:wound:1" % wounded_owner.instance_id),
	]
	_expect(
		wounded_squad.get_visible_wound_slots().size() == 2
		and healed_target.battle_active_injury_ids == injury_ids,
		"随军医者测试使用真实 OwnedCard 显现伤势槽"
	)
	healed_target.apply_direct_health_damage_exact(2.0)
	var heal_event := BattleEffectEvent.new()
	heal_event.source = medic
	heal_event.target = healed_target
	heal_event.action_type = CardData.ActionType.HEAL
	heal_event.effect_kind = BattleEffectEvent.EffectKind.HEALING
	heal_event.exact_amount = 1.0
	heal_event.is_base_action = true
	heal_event.formula = BattleFormulaData.create(
		"治疗",
		CardData.ActionType.HEAL,
		1.0,
		1.0,
		1.0,
		medic,
		healed_target
	)
	controller._apply_effect_event(heal_event)
	_expect(
		is_equal_approx(heal_event.effective_amount, 1.0)
		and healed_target.get_unmasked_active_injuries().size() == 1
		and healed_target.injury_mask_sources.size() == 1,
		"一次正式基础治疗只触发一次随军医者，遮蔽目标一处生效伤势"
	)
	controller.effect_runtime.emit_trigger(
		BattleEffectDefinition.Trigger.AFTER_BASIC_HEAL,
		{"actor": medic, "healed_target": healed_target}
	)
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(healed_target.get_unmasked_active_injuries().is_empty(), "下一次治疗可遮蔽另一处生效伤势")
	controller.effect_runtime.emit_trigger(
		BattleEffectDefinition.Trigger.AFTER_BASIC_HEAL,
		{"actor": medic, "healed_target": healed_target}
	)
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	var no_target_traced := controller.effect_runtime.traces.any(
		func(trace: BattleEffectTraceEntry) -> bool:
			return (
				trace.effect_id == &"field_medic.effect.01"
				and trace.result == &"no_legal_target"
			)
	)
	_expect(no_target_traced, "随军医者面对全部已遮蔽伤势时明确记录无合法目标，不重复命中")
	controller.effect_runtime.process_due(4.999)
	_expect(healed_target.get_unmasked_active_injuries().is_empty(), "伤势遮蔽在5秒到期前保持生效")
	controller.effect_runtime.process_due(5.0)
	_expect(
		healed_target.get_unmasked_active_injuries().size() == 2
		and healed_target.injury_mask_sources.is_empty(),
		"5秒到期后各运行实例只移除自身遮蔽来源并恢复两处伤势"
	)
	_dispose(controller)

	# 不手动构造治疗事件，走正式冷却、目标选择和命中链，覆盖实际游玩入口。
	var live_controller := _controller_with(
		[
			_entry(_card("field_medic"), &"player_back", 0),
			{"squad_data": wounded_squad, "row_key": &"player_front", "formation_index": 0},
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24121
	)
	var live_target := live_controller.player_states[1]
	live_target.apply_direct_health_damage_exact(2.0)
	live_controller.advance_time(6.0)
	var medic_applied := live_controller.effect_runtime.traces.any(
		func(trace: BattleEffectTraceEntry) -> bool:
			return trace.effect_id == &"field_medic.effect.01" and trace.result == &"applied"
	)
	_expect(medic_applied and live_target.injury_mask_sources.size() == 1, "真实冷却行动治疗有伤势目标时触发随军医者")
	_dispose(live_controller)


func _test_armorsmith_pending_armor_growth() -> void:
	var armorsmith := _card("armorsmith")
	var armor_provider := CardData.new()
	armor_provider.id = &"growth_armor_provider"
	armor_provider.display_name = "成长护甲来源"
	armor_provider.max_health = 20
	armor_provider.armor = 5
	var source_squad := SquadData.from_cards([armorsmith, armor_provider])
	source_squad.layer_cards.assign([armorsmith, armor_provider])
	var controller := _controller_with(
		[
			{"squad_data": source_squad, "row_key": &"player_front", "formation_index": 0},
			_entry(_card("militia"), &"player_front", 1),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24117
	)
	var smith_state := controller.player_states[0]
	var adjacent := controller.player_states[1]
	adjacent.current_health = 0.0
	controller._finalize_batch()
	var entries := controller.permanent_growth_ledger.get_entries()
	var entry: Dictionary = entries[0] if entries.size() == 1 else {}
	_expect(
		entries.size() == 1
		and entry.get("card_data") == armor_provider
		and entry.get("stat") == BattlePermanentGrowthLedger.STAT_BASE_ARMOR
		and entry.get("owner_kind") == BattleEffectDefinition.OwnerKind.ARMOR_PROVIDER_CARD
		and is_equal_approx(float(entry.get("amount", 0.0)), 1.0),
		"铸甲师把永久护甲成长归给触发当时实际提供护甲的单卡"
	)
	_expect(
		is_equal_approx(smith_state.current_armor, 9.0)
		and armor_provider.armor == 5,
		"铸甲师同步增加本场当前护甲，但不直接写回CardData"
	)
	controller.effect_runtime.emit_trigger(
		BattleEffectDefinition.Trigger.ADJACENT_ALLY_DESTROYED,
		{"actor": adjacent}
	)
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(controller.permanent_growth_ledger.get_entries().size() == 1, "铸甲师复活或后续相邻阵亡不会重置每场一次限制")
	_dispose(controller)


func _controller_with(players: Array[Dictionary], enemies: Array[Dictionary], seed: int) -> BattleController:
	var controller := BattleControllerScript.new() as BattleController
	root.add_child(controller)
	controller.start_battle(players, enemies, seed, false)
	return controller


func _entry(card: CardData, row_key: StringName, position: int) -> Dictionary:
	return {
		"squad_data": SquadData.from_card(card),
		"row_key": row_key,
		"formation_index": position,
	}


func _squad_entry(cards: Array[CardData], row_key: StringName, position: int) -> Dictionary:
	return {
		"squad_data": SquadData.from_cards(cards),
		"row_key": row_key,
		"formation_index": position,
	}


func _card(card_id: String) -> CardData:
	return load("res://resources/cards/%s.tres" % card_id) as CardData


func _plain_enemy() -> CardData:
	var card := CardData.new()
	card.id = &"d2_4_plain_enemy"
	card.display_name = "D2-4测试敌人"
	card.base_value = 0
	card.cooldown_seconds = 9.0
	card.max_health = 100
	return card


func _dispose(controller: BattleController) -> void:
	controller.clear_battle()
	controller.free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
