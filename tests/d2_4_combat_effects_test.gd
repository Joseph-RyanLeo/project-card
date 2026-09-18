extends SceneTree

## D2-4 第二小步：验证不依赖战后写回/资源系统的真实随从战中事件链。

const BattleControllerScript = preload("res://scripts/battle/battle_controller.gd")
const BattlePermanentGrowthLedger = preload("res://scripts/battle/battle_permanent_growth_ledger.gd")
const BattleRunRewardLedger = preload("res://scripts/battle/battle_run_reward_ledger.gd")
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
	_expect(fireman.get_max_health() == 6 and is_equal_approx(fireman.current_health, 6.0), "伙夫按2枚生效火符文获得本场最大生命+4并同步当前生命")
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
	var armor_before := float(shieldwall.current_armor)
	armor_controller.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.SOURCE_ARMOR_GAINED, {"actor": shieldwall, "amount": 3.0})
	armor_controller.effect_runtime.process_due(armor_controller.elapsed_seconds)
	_expect(is_equal_approx(float(shieldwall.current_armor), armor_before + 1.0), "盾墙列兵收到自身获得护甲事件后额外获得1点且阻止递归")
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
		drummer.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 1.0
		and ally.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 1.0,
		"战鼓乐师回响只由自身行动触发，并强化同排含自身的友军"
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
		and is_equal_approx(float(poet.current_armor), 3.0),
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
		and middle_human.get_max_health() == 22
		and right_human.get_max_health() == 4
		and is_equal_approx(float(commander.current_health), 8.0)
		and is_equal_approx(float(middle_human.current_health), 22.0)
		and is_equal_approx(float(right_human.current_health), 4.0),
		"民兵指挥官按每个目标自己的相邻人类数量实时提供生命，并同步当前生命"
	)
	right_human.current_health = 0.0
	commander_controller._finalize_batch()
	_expect(
		middle_human.get_max_health() == 20
		and is_equal_approx(float(middle_human.current_health), 22.0)
		and middle_human.displayed_health == 22,
		"相邻人类退场后只撤销生命上限，保留当前生命及卡面显示"
	)
	middle_human.current_health = 1.0
	commander.current_health = 0.0
	commander_controller._finalize_batch()
	_expect(
		middle_human.get_max_health() == 18
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
		diplomat_controller.player_states[0].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 0.0
		and diplomat_controller.player_states[1].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 1.0
		and diplomat_controller.player_states[2].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 1.0,
		"外交官只给非精灵友军提供实时基础数值"
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
	_expect(musketeer.get_target_weight() == 0 and controller.get_effective_target_weight(musketeer) == 0, "火枪手乡邻可把受击优先级降至明确下限0")
	controller.player_states[2].current_health = 0.0
	controller.player_states[5].current_health = 0.0
	controller._finalize_batch()
	_expect(
		controller.player_states[0].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 0.0
		and controller.player_states[1].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 0.0
		and musketeer.get_target_weight() == 2,
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
	var controller := BattleControllerScript.new() as BattleController
	root.add_child(controller)
	controller.use_projectile_timing = true
	var launches: Array[Dictionary] = []
	controller.projectile_launched.connect(func(event: BattleEffectEvent) -> void:
		launches.append({
			"event": event,
			"action_type_at_launch": event.source.get_effective_action_type(),
		})
	)
	controller.start_battle(
		[_entry(_card("javelin_skirmisher"), &"player_front", 0)],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24113,
		false
	)
	var skirmisher := controller.player_states[0]
	var source_card := skirmisher.get_action_source()
	var launch_event := launches[0]["event"] as BattleEffectEvent if launches.size() == 1 else null
	var has_plus_two := false
	if launch_event != null:
		for term: Dictionary in launch_event.formula.additive_terms:
			if term.get("name") == "即时行动数值修正" and is_equal_approx(float(term.get("value", 0.0)), 2.0):
				has_plus_two = true
	_expect(
		launches.size() == 1
		and launch_event != null
		and launch_event.action_type == CardData.ActionType.RANGED
		and int(launches[0]["action_type_at_launch"]) == CardData.ActionType.RANGED
		and has_plus_two,
		"标枪散兵突击只发射一次数值+2的远程普通行动"
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
	_expect(float(enemy.current_health) < health_before, "标枪突击弹道随后按正式命中流程造成伤害")
	var next_actions := controller._select_base_actions([skirmisher], controller.get_all_states())
	var next_event := next_actions[0]["base_event"] as BattleEffectEvent if next_actions.size() == 1 else null
	_expect(
		next_event != null
		and next_event.action_type == CardData.ActionType.MELEE
		and next_event.formula.additive_terms.all(func(term: Dictionary) -> bool: return term.get("name") != "即时行动数值修正"),
		"标枪散兵之后的普通行动使用近战且不再获得突击+2"
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
	var controller := _controller_with(
		[
			_entry(_card("field_medic"), &"player_back", 0),
			_entry(_card("ember_squire"), &"player_front", 0),
		],
		[_entry(_plain_enemy(), &"enemy_front", 0)],
		24120
	)
	var medic := controller.player_states[0]
	var healed_target := controller.player_states[1]
	var injury_ids: Array[StringName] = [&"injury_a", &"injury_b"]
	healed_target.set_battle_active_injuries(injury_ids)
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
	controller.effect_runtime.emit_trigger(
		BattleEffectDefinition.Trigger.AFTER_BASIC_HEAL,
		{"actor": medic, "healed_target": healed_target}
	)
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(
		is_equal_approx(heal_event.effective_amount, 1.0)
		and healed_target.get_unmasked_active_injuries().is_empty()
		and healed_target.injury_mask_sources.size() == 2,
		"正式基础治疗钩子触发随军医者，连续治疗只从未遮蔽伤势池选择"
	)
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
		is_equal_approx(smith_state.current_armor, 6.0)
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
