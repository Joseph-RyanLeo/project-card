extends SceneTree

## 阶段 7 基础自动战斗闭环集成测试。
## 使用真实 BattleController、Main、BattlefieldRow 与 BoardSlot，不使用 mock。

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const BattleController = preload("res://scripts/battle/battle_controller.gd")
const BattleSquadState = preload("res://scripts/battle/battle_squad_state.gd")
const BattleRules = preload("res://scripts/battle/battle_rules.gd")

var _failure_count: int = 0
var _card_serial: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_test_runtime_sources_isolation_and_rule_config()
	await _test_weighted_targeting_and_five_actions()
	await _test_timeline_batches_and_results()
	await _test_fatigue_buff_and_battle_speed()
	await _test_main_battle_loop_and_restart()
	await _test_departure_entry_and_row_recentering()
	if _failure_count == 0:
		print("Stage 7 integration checks passed.")
	else:
		push_error("Stage 7 integration checks failed: %d" % _failure_count)
	quit(_failure_count)


func _test_runtime_sources_isolation_and_rule_config() -> void:
	var left := _make_card(CardData.ActionType.MAGIC, 4, 11, 1, 2.25)
	var middle := _make_card(CardData.ActionType.HEAL, 8, 15, 2, 7.0)
	var right := _make_card(CardData.ActionType.DEFENSE, 9, 19, 6, 8.0)
	var squad := SquadData.from_cards(_cards([left, middle, right]))
	squad.layer_cards.assign(_cards([middle, left, right]))
	var before_horizontal: Array[CardData] = squad.horizontal_cards.duplicate()
	var before_layers: Array[CardData] = squad.layer_cards.duplicate()
	var before_card_values := [
		left.base_value, left.cooldown_seconds, left.max_health, left.armor,
		middle.base_value, middle.max_health,
		right.base_value, right.max_health, right.armor,
	]
	var state := BattleSquadState.new()
	state.initialize(squad, BattleSquadState.Side.PLAYER, &"player_front", 0)
	_expect(
		state.get_action_source() == left
		and state.get_vitals_source() == right
		and state.get_effect_source() == middle,
		"战斗状态继续读取最左行动、最右生命护甲、最上层效果来源"
	)
	_expect(
		state.current_health == 19
		and state.current_armor == 6
		and is_equal_approx(state.remaining_cooldown, 2.25),
		"战斗临时生命、护甲与冷却由正确来源初始化"
	)
	state.apply_damage(10)
	state.apply_healing(3)
	state.apply_armor(4)
	_expect(
		squad.horizontal_cards == before_horizontal
		and squad.layer_cards == before_layers
		and [
			left.base_value, left.cooldown_seconds, left.max_health, left.armor,
			middle.base_value, middle.max_health,
			right.base_value, right.max_health, right.armor,
		] == before_card_values,
		"修改战斗运行时状态不会写回 CardData、SquadData 或准备阵容"
	)

	var expected_weights := [4, 2, 3, 1, 5]
	for action_type: int in CardData.ActionType.size():
		var card := _make_card(action_type, 1, 10, 0, 1.0)
		_expect(
			card.get_base_target_priority() == expected_weights[action_type],
			"%s 的受击权重只由行动方式统一映射" % card.get_action_type_name()
		)

	var patterns := [
		RunePatternResult.PatternType.CHAOS,
		RunePatternResult.PatternType.PAIR,
		RunePatternResult.PatternType.THREE_OF_A_KIND,
		RunePatternResult.PatternType.TWO_PAIR,
		RunePatternResult.PatternType.SAME_ELEMENT_TWO_PAIR,
		RunePatternResult.PatternType.FULL_HOUSE,
		RunePatternResult.PatternType.FOUR_OF_A_KIND,
		RunePatternResult.PatternType.FIVE_OF_A_KIND,
		RunePatternResult.PatternType.STRAIGHT,
	]
	var expected_amounts := [10, 15, 20, 20, 20, 25, 25, 30, 30]
	for index: int in patterns.size():
		_expect(
			BattleRules.calculate_action_amount(10, patterns[index]) == expected_amounts[index],
			"九种牌型倍率均通过单一配置入口进入最终整数数值"
		)
	_expect(
		BattleRules.calculate_action_amount(3, RunePatternResult.PatternType.PAIR) == 5,
		"最终整数统一使用四舍五入，3×1.5 得到 5"
	)
	_expect(
		is_equal_approx(BattleRules.get_effective_cooldown(0.0), 0.5)
		and is_equal_approx(BattleRules.get_effective_cooldown(-2.0), 0.5)
		and is_equal_approx(BattleRules.get_effective_cooldown(1.25), 1.25)
		and is_equal_approx(BattleRules.get_effective_cooldown(12.0), 9.9),
		"基础值与后续修正后的有效冷却统一限制在 0.5–9.9 秒"
	)
	var capped_card := CardData.new()
	capped_card.base_value = 120
	capped_card.cooldown_seconds = 12.0
	capped_card.max_health = 1200
	capped_card.armor = 1200
	_expect(
		capped_card.base_value == 99
		and is_equal_approx(capped_card.cooldown_seconds, 9.9)
		and capped_card.max_health == 999
		and capped_card.armor == 999
		and BattleRules.calculate_action_amount(
			120,
			RunePatternResult.PatternType.STRAIGHT
		) == 297,
		"基础行动99、冷却9.9、生命护甲999封顶，但牌型后的最终行动结果不封顶99"
	)
	var armor_cap_state := BattleSquadState.new()
	armor_cap_state.initialize(
		SquadData.from_card(capped_card),
		BattleSquadState.Side.PLAYER,
		&"player_front",
		0
	)
	_expect(
		armor_cap_state.apply_armor(20) == 0
		and armor_cap_state.current_armor == 999,
		"战斗临时护甲同样不能突破999且返回实际生效量"
	)


func _test_weighted_targeting_and_five_actions() -> void:
	var controller := BattleController.new()
	root.add_child(controller)
	var weight_states: Array[BattleSquadState] = []
	for action_type: int in [
		CardData.ActionType.MAGIC,
		CardData.ActionType.RANGED,
		CardData.ActionType.DEFENSE,
	]:
		var state := BattleSquadState.new()
		state.initialize(
			SquadData.from_card(_make_card(action_type, 1, 10, 0, 1.0)),
			BattleSquadState.Side.PLAYER,
			&"player_front",
			weight_states.size()
		)
		weight_states.append(state)
	_expect(
		controller.choose_weighted_target(weight_states, 0) == weight_states[0]
		and controller.choose_weighted_target(weight_states, 2) == weight_states[0]
		and controller.choose_weighted_target(weight_states, 3) == weight_states[1]
		and controller.choose_weighted_target(weight_states, 4) == weight_states[1]
		and controller.choose_weighted_target(weight_states, 5) == weight_states[2]
		and controller.choose_weighted_target(weight_states, 9) == weight_states[2],
		"3/2/5 权重边界严格对应 30%/20%/50% 区间"
	)
	controller.queue_free()
	await process_frame

	for attack_type: int in [
		CardData.ActionType.MELEE,
		CardData.ActionType.RANGED,
		CardData.ActionType.MAGIC,
	]:
		var attack_name: String = ["近战", "远程", "法术"][attack_type]
		var attack_controller := await _create_controller(
			[_formation_entry(_single_squad(attack_type, 4, 20, 0, 1.0), &"player_front", 0)],
			[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 20, 3, 100.0), &"enemy_front", 0)],
			701 + attack_type
		)
		attack_controller.resolve_next_batch()
		var target := attack_controller.enemy_states[0]
		_expect(
			target.current_armor == 0 and target.current_health == 19,
			"%s造成基础伤害，并先扣 3 点护甲再扣 1 点生命" % attack_name
		)
		await _dispose_controller(attack_controller)

	var heal_controller := await _create_controller(
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 4, 10, 0, 1.0), &"player_front", 0)],
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 30, 0, 100.0), &"enemy_front", 0)],
		811
	)
	var heal_actor := heal_controller.player_states[0]
	heal_actor.current_health = 9
	heal_controller.resolve_next_batch()
	_expect(
		heal_actor.current_health == 10,
		"治疗使用友方权重池、可以选择自己，且不超过最大生命"
	)
	await _dispose_controller(heal_controller)

	var selective_heal := await _create_controller(
		[
			_formation_entry(_single_squad(CardData.ActionType.HEAL, 4, 10, 0, 1.0), &"player_front", 0),
			_formation_entry(_single_squad(CardData.ActionType.DEFENSE, 1, 10, 0, 100.0), &"player_front", 1),
		],
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 30, 0, 100.0), &"enemy_front", 0)],
		8111
	)
	selective_heal.player_states[1].current_health = 5
	selective_heal.resolve_next_batch()
	_expect(
		selective_heal.player_states[0].current_health == 10
		and selective_heal.player_states[1].current_health == 9,
		"满生命友军不会进入治疗候选池，治疗只落到已经损失生命的友军"
	)
	await _dispose_controller(selective_heal)

	var full_health_heal := await _create_controller(
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 4, 10, 0, 1.0), &"player_front", 0)],
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 30, 0, 100.0), &"enemy_front", 0)],
		8112
	)
	var full_health_events: Array = []
	full_health_heal.action_resolved.connect(func(actor, target, action_type, amount) -> void:
		full_health_events.append([actor, target, action_type, amount])
	)
	full_health_heal.resolve_next_batch()
	_expect(
		full_health_events.size() == 1
		and full_health_events[0][1] == full_health_heal.player_states[0]
		and int(full_health_events[0][3]) == 0
		and full_health_heal.player_states[0].current_health == 10,
		"全员满生命时治疗仍选择目标并触发行动，实际治疗量记录为 0"
	)
	await _dispose_controller(full_health_heal)

	var minimum_cooldown := await _create_controller(
		[_formation_entry(_single_squad(CardData.ActionType.MELEE, 1, 30, 0, 0.0), &"player_front", 0)],
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 30, 0, 100.0), &"enemy_front", 0)],
		8113
	)
	_expect(
		is_equal_approx(minimum_cooldown.player_states[0].remaining_cooldown, 0.5),
		"零或负基础冷却进入战斗状态时按 0.5 秒最低冷却处理"
	)
	minimum_cooldown.resolve_next_batch()
	_expect(
		is_equal_approx(minimum_cooldown.elapsed_seconds, 0.5)
		and is_equal_approx(minimum_cooldown.player_states[0].remaining_cooldown, 0.5),
		"行动后重新冷却同样经过 0.5 秒统一下限"
	)
	await _dispose_controller(minimum_cooldown)

	var defense_controller := await _create_controller(
		[_formation_entry(_single_squad(CardData.ActionType.DEFENSE, 4, 10, 2, 1.0), &"player_front", 0)],
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 30, 0, 100.0), &"enemy_front", 0)],
		812
	)
	defense_controller.resolve_next_batch()
	_expect(
		defense_controller.player_states[0].current_armor == 6,
		"防御使用同一友方权重算法并增加临时护甲"
	)
	await _dispose_controller(defense_controller)


func _test_timeline_batches_and_results() -> void:
	var timeline := await _create_controller(
		[_formation_entry(_single_squad(CardData.ActionType.MELEE, 1, 100, 0, 2.0), &"player_front", 0)],
		[_formation_entry(_single_squad(CardData.ActionType.MELEE, 1, 100, 0, 3.0), &"enemy_front", 0)],
		901
	)
	var events: Array = []
	timeline.action_resolved.connect(func(actor, _target, _type, _amount) -> void:
		events.append(actor)
	)
	timeline.resolve_next_batch()
	_expect(
		is_equal_approx(timeline.elapsed_seconds, 2.0)
		and events.size() == 1
		and events[0] == timeline.player_states[0]
		and is_equal_approx(timeline.enemy_states[0].remaining_cooldown, 1.0),
		"统一时间轴先推进到双方最早的 2 秒冷却点"
	)
	timeline.resolve_next_batch()
	_expect(
		is_equal_approx(timeline.elapsed_seconds, 3.0)
		and events.size() == 2
		and events[1] == timeline.enemy_states[0],
		"第二批继续从同一时间轴推进到敌方 3 秒冷却点"
	)
	await _dispose_controller(timeline)

	var draw := await _create_controller(
		[_formation_entry(_single_squad(CardData.ActionType.MELEE, 5, 5, 0, 1.0), &"player_front", 0)],
		[_formation_entry(_single_squad(CardData.ActionType.MELEE, 5, 5, 0, 1.0), &"enemy_front", 0)],
		902
	)
	var simultaneous_events: Array = []
	draw.action_resolved.connect(func(actor, _target, _type, _amount) -> void:
		simultaneous_events.append(actor)
	)
	draw.resolve_next_batch()
	_expect(
		simultaneous_events.size() == 2
		and draw.batch_count == 1
		and draw.current_result == BattleController.Result.DRAW,
		"同冷却时间点双方都基于批次开始存活状态行动，同时全灭判为平局"
	)
	_expect(
		is_equal_approx(draw.player_states[0].battle_damage_dealt, 5.0)
		and is_equal_approx(draw.player_states[0].battle_damage_taken, 5.0)
		and is_equal_approx(draw.enemy_states[0].battle_damage_dealt, 5.0)
		and is_equal_approx(draw.enemy_states[0].battle_damage_taken, 5.0),
		"每个战斗状态分别累计实际造成伤害与承受伤害"
	)
	await _dispose_controller(draw)

	var heal_after_damage := await _create_controller(
		[_formation_entry(_single_squad(CardData.ActionType.MELEE, 7, 30, 0, 1.0), &"player_front", 0)],
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 4, 5, 0, 1.0), &"enemy_front", 0)],
		903
	)
	heal_after_damage.enemy_states[0].current_health = 4
	heal_after_damage.resolve_next_batch()
	_expect(
		heal_after_damage.enemy_states[0].current_health == 1
		and heal_after_damage.enemy_states[0].alive
		and heal_after_damage.current_result == BattleController.Result.NONE,
		"受伤治疗者同批次先伤害到 -3，再治疗 4 回到 1，最后统一判定仍存活"
	)
	_expect(
		is_equal_approx(heal_after_damage.player_states[0].battle_damage_dealt, 7.0)
		and is_equal_approx(heal_after_damage.enemy_states[0].battle_damage_taken, 7.0)
		and is_equal_approx(heal_after_damage.enemy_states[0].battle_healing_done, 4.0),
		"伤害与实际生效治疗分别归属到正确来源和目标"
	)
	await _dispose_controller(heal_after_damage)

	var armor_after_damage := await _create_controller(
		[_formation_entry(_single_squad(CardData.ActionType.MELEE, 3, 30, 0, 1.0), &"player_front", 0)],
		[_formation_entry(_single_squad(CardData.ActionType.DEFENSE, 5, 2, 0, 1.0), &"enemy_front", 0)],
		904
	)
	armor_after_damage.resolve_next_batch()
	_expect(
		armor_after_damage.enemy_states[0].current_health == -1
		and armor_after_damage.enemy_states[0].current_armor == 5
		and not armor_after_damage.enemy_states[0].alive,
		"同批次护甲在伤害后增加，不能倒流抵挡已经结算的伤害"
	)
	_expect(
		is_equal_approx(armor_after_damage.enemy_states[0].battle_armor_granted, 5.0),
		"实际施加的护甲单独累计到防御来源"
	)
	await _dispose_controller(armor_after_damage)

	var victory := await _create_controller(
		[_formation_entry(_single_squad(CardData.ActionType.MELEE, 10, 10, 0, 1.0), &"player_front", 0)],
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 5, 0, 100.0), &"enemy_front", 0)],
		905
	)
	victory.resolve_next_batch()
	_expect(victory.current_result == BattleController.Result.PLAYER_VICTORY, "敌方全灭得到胜利结果")
	await _dispose_controller(victory)
	var defeat := await _create_controller(
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 5, 0, 100.0), &"player_front", 0)],
		[_formation_entry(_single_squad(CardData.ActionType.MELEE, 10, 10, 0, 1.0), &"enemy_front", 0)],
		906
	)
	defeat.resolve_next_batch()
	_expect(defeat.current_result == BattleController.Result.PLAYER_DEFEAT, "我方全灭得到失败结果")
	await _dispose_controller(defeat)


func _test_fatigue_buff_and_battle_speed() -> void:
	var fatigue := await _create_controller(
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 10, 5, 100.0), &"player_front", 0)],
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 10, 5, 100.0), &"enemy_front", 0)],
		920
	)
	var buff_events: Array = []
	var fatigue_damage_events: Array = []
	fatigue.buff_stacks_changed.connect(func(state, buff_id, stacks) -> void:
		buff_events.append([state, buff_id, stacks])
	)
	fatigue.direct_damage_resolved.connect(func(state, source_id, amount) -> void:
		fatigue_damage_events.append([state, source_id, amount])
	)
	fatigue.advance_time(29.0)
	_expect(
		is_equal_approx(fatigue.elapsed_seconds, 29.0)
		and fatigue.player_states[0].get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 0
		and fatigue.player_states[0].current_health == 10,
		"战斗 30 秒前不会提前获得疲劳或受到疲劳伤害"
	)
	fatigue.advance_time(1.0)
	_expect(
		is_equal_approx(fatigue.elapsed_seconds, 30.0)
		and fatigue.player_states[0].get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 1
		and fatigue.player_states[0].current_health == 9
		and fatigue.player_states[0].current_armor == 5
		and buff_events.size() == 2
		and fatigue_damage_events.size() == 2,
		"30 秒时双方先获得第 1 层疲劳，再立即各受 1 点无视护甲的生命伤害"
	)
	fatigue.advance_time(1.0)
	_expect(
		is_equal_approx(fatigue.elapsed_seconds, 31.0)
		and fatigue.player_states[0].get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 1
		and fatigue.player_states[0].current_health == 8,
		"31 秒不叠层，继续按当前 1 层疲劳造成 1 点直伤"
	)
	fatigue.advance_time(1.0)
	_expect(
		is_equal_approx(fatigue.elapsed_seconds, 32.0)
		and fatigue.player_states[0].get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 2
		and fatigue.player_states[0].current_health == 6
		and buff_events.size() == 4
		and fatigue_damage_events.size() == 6,
		"32 秒先增加到 2 层疲劳，再按新层数造成 2 点直伤"
	)
	await _dispose_controller(fatigue)

	var same_batch_heal := await _create_controller(
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 5, 0, 9.9), &"player_front", 0)],
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 5, 0, 9.9), &"enemy_front", 0)],
		921
	)
	same_batch_heal.advance_time(29.0)
	same_batch_heal.player_states[0].current_health = 1
	same_batch_heal.enemy_states[0].current_health = 1
	same_batch_heal.player_states[0].remaining_cooldown = 1.0
	same_batch_heal.enemy_states[0].remaining_cooldown = 1.0
	same_batch_heal.advance_time(1.0)
	_expect(
		same_batch_heal.player_states[0].current_health == 1
		and same_batch_heal.enemy_states[0].current_health == 1
		and same_batch_heal.player_states[0].alive
		and same_batch_heal.enemy_states[0].alive,
		"30 秒同批次先结算疲劳直伤、再结算已锁定治疗，最后统一判定死亡"
	)
	await _dispose_controller(same_batch_heal)

	var fatigue_draw := await _create_controller(
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 1, 0, 100.0), &"player_front", 0)],
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 1, 0, 100.0), &"enemy_front", 0)],
		922
	)
	fatigue_draw.advance_time(30.0)
	_expect(
		fatigue_draw.current_result == BattleController.Result.DRAW,
		"疲劳在同批次令双方全灭时仍判定为平局"
	)
	await _dispose_controller(fatigue_draw)

	var speed_controller := await _create_controller(
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 10, 0, 100.0), &"player_front", 0)],
		[_formation_entry(_single_squad(CardData.ActionType.HEAL, 1, 10, 0, 100.0), &"enemy_front", 0)],
		923
	)
	speed_controller.set_battle_speed_multiplier(2.0)
	speed_controller._process(0.5)
	_expect(
		is_equal_approx(speed_controller.elapsed_seconds, 1.0)
		and is_equal_approx(speed_controller.player_states[0].remaining_cooldown, 8.9),
		"2×速度只把现实半秒换算为一秒战斗时间，不改变时间轴规则"
	)
	await _dispose_controller(speed_controller)


func _test_main_battle_loop_and_restart() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_expect(
		main.start_battle_button != null
		and main.start_battle_button.text == "开始战斗"
		and main.get_node("%BattleResultPlaceholder") != null
		and main.restart_battle_button.text == "重新开始",
		"正式开始战斗按钮、战后统计提示和重新开始按钮均存在"
	)
	_expect(
		main.battle_speed_button != null
		and not main.battle_speed_button.visible
		and main.battle_speed_button.text == "速度 1×",
		"准备阶段已建立战斗速度按钮，并默认隐藏为 1×"
	)
	_expect(
		main.battle_timer_label != null
		and not main.battle_timer_label.visible
		and main.battle_timer_label.text == "战斗 00:00.0"
		and main.battle_timer_label.position == main.BATTLE_TIMER_POSITION,
		"准备阶段已建立战场中线靠左的逻辑计时，并默认归零隐藏"
	)
	_expect(
		main.battle_log_panel != null
		and main.battle_log_text != null
		and not main.battle_log_panel.visible
		and main.battle_log_panel.position == main.BATTLE_LOG_POSITION
		and main.battle_log_text.text.is_empty(),
		"准备阶段已建立左下角战斗日志，并保持隐藏清空"
	)
	var battle_log_title := main.get_node("%BattleLogTitle") as Label
	_expect(
		battle_log_title.get_theme_font("font") == main.BATTLE_LOG_FONT
		and main.battle_log_text.get_theme_font("normal_font") == main.BATTLE_LOG_FONT
		and main.BATTLE_LOG_FONT.has_char("敌".unicode_at(0))
		and main.BATTLE_LOG_FONT.has_char("疗".unicode_at(0)),
		"战斗日志标题与正文统一使用卡牌中文字体，并覆盖日志所需中文字符"
	)
	_expect(
		main.battle_speed_button.position == main.BATTLE_SPEED_BUTTON_POSITION
		and main.battle_speed_button.size.x >= main.BATTLE_SPEED_BUTTON_SIZE.x
		and main.battle_speed_button.size.y >= main.BATTLE_SPEED_BUTTON_SIZE.y
		and main.battle_speed_button.position.y >= (
			main.enemy_avatar.position.y + main.enemy_avatar.size.y
		),
		"战斗速度按钮位于敌方画像下方，并保留足够点击尺寸"
	)
	_expect(
		main.enemy_back_row.get_card_count() + main.enemy_front_row.get_card_count() == 8,
		"固定敌阵增加到前后排合计 8 张卡，用于测试战斗强度"
	)
	var deployed_card: CardData = main.collection_cards[0]
	_expect(
		main._transfer_card({
			"source_type": &"collection",
			"kind": &"card",
			"card_data": deployed_card,
		}, &"board", main.front_row, 0),
		"为闭环测试建立战斗前玩家阵容"
	)
	var formation_before := _main_formation_signature(main)
	var cards_before := _card_resource_signature(main.collection_cards)
	_expect(main.start_battle(1007, false), "正式入口可使用固定随机种子开始战斗")
	_expect(
		main.current_phase == main.GamePhase.BATTLE
		and main.current_world_view == main.WorldView.BATTLEFIELDS
		and main.battle_speed_button.visible
		and main.battle_timer_label.visible
		and main.battle_log_panel.visible
		and not main.front_row.can_receive_card_drag({
			"source_type": &"collection",
			"kind": &"card",
			"card_data": main.collection_cards[1],
		}),
		"进入战斗后自动切到敌我视图并锁定准备拖拽"
	)
	main.cycle_battle_speed()
	main.battle_controller._process(0.5)
	_expect(
		main.battle_speed_button.text == "速度 2×"
		and is_equal_approx(main.battle_controller.battle_speed_multiplier, 2.0)
		and main.battle_timer_label.text == "战斗 00:01.0",
		"切到 2× 后现实半秒推进一秒逻辑计时，并同步刷新战场计时文字"
	)
	main.cycle_battle_speed()
	main.cycle_battle_speed()
	_expect(
		main.battle_speed_button.text == "速度 1×"
		and is_equal_approx(main.battle_controller.battle_speed_multiplier, 1.0),
		"战斗速度按钮按 1×→2×→3×→1×循环"
	)
	var first_state: BattleSquadState = main.battle_controller.player_states[0]
	var first_slot := main.get("_battle_state_slots").get(first_state) as BoardSlot
	first_state.current_health = maxi(first_state.get_max_health() - 2, 0)
	first_state.current_armor += 3
	main._on_battle_states_changed()
	var vitals_view := first_slot.get_card_view(first_state.get_vitals_source())
	var action_view := first_slot.get_card_view(first_state.get_action_source())
	_expect(
		first_slot != null
		and not first_slot.battle_status_label.visible
		and first_slot.battle_status_label.text.is_empty()
		and vitals_view.has_battle_vitals()
		and vitals_view.health_label.text == str(first_state.current_health)
		and vitals_view.armor_label.text == str(first_state.current_armor)
		and action_view.has_battle_remaining_cooldown()
		and action_view.cooldown_label.text == CardView.format_cooldown_seconds(
			first_state.remaining_cooldown
		),
		"生命护甲覆盖最右卡原数字，剩余冷却覆盖最左卡常驻沙漏数字，旧状态条不再显示冷却"
	)
	first_slot.play_battle_action_lift(1.0)
	await process_frame
	_expect(
		first_slot.squad_lift_layer.position.y < 0.0,
		"小队行动时整组卡牌向上抬起，且不影响 CardView 上的冷却显示"
	)
	await create_timer(SquadView.BATTLE_ACTION_LIFT_SECONDS + 0.03).timeout
	_expect(
		is_zero_approx(first_slot.squad_lift_layer.position.y),
		"行动抬起动画结束后准确回到原位"
	)
	main.battle_controller.resolve_next_batch()
	await process_frame
	_expect(
		not main.battle_log_text.text.is_empty()
		and main.battle_log_text.text.contains("点")
		and (
			main.battle_log_text.text.contains("造成了")
			or main.battle_log_text.text.contains("提供了")
		),
		"真实行动把敌我名称、实际数值和伤害/治疗/护盾类型写入左下角日志"
	)
	var action_beam := main.battle_effect_layer.get_node_or_null("ElementEnergyBeam") as Node2D
	var action_beam_mesh := action_beam.get_node_or_null("BeamMesh") as MeshInstance2D if action_beam != null else null
	var action_beam_material := action_beam_mesh.material as ShaderMaterial if action_beam_mesh != null else null
	_expect(
		action_beam_material != null
		and action_beam_material.shader.resource_path == "res://shaders/battle_energy_beam.gdshader",
		"近战、远程或法术行动会在攻击卡牌与目标之间生成弧线像素能量束"
	)
	_expect(
		_main_formation_signature(main) != {}
		and _card_resource_signature(main.collection_cards) == cards_before,
		"战斗推进只修改运行时状态，不修改 CardData 基础资源"
	)
	var guard := 0
	while (
		main.battle_controller.current_result == BattleController.Result.NONE
		and guard < 200
	):
		main.battle_controller.resolve_next_batch()
		guard += 1
	_expect(
		guard < 200
		and main.battle_controller.current_result != BattleController.Result.NONE
		and main.current_phase == main.GamePhase.BATTLE
		and int(main.get("_active_battle_departures")) > 0,
		"战斗结果已确定时先留在战斗阶段，等待阵亡溶解全部播放完成"
	)
	await create_timer(SquadView.DEATH_DISSOLVE_EDGE_SECONDS + 0.1).timeout
	_expect(
		main.current_phase == main.GamePhase.RESULT
		and main.battle_result_panel.visible
		and main.battle_log_panel.visible
		and not main.battle_log_text.text.is_empty()
		and main.battle_result_label.text in ["胜利", "失败", "平局"],
		"阵亡溶解完成后进入结算页，并保留本场战斗日志供玩家查看"
	)
	var result_states: Array[BattleSquadState] = main.battle_controller.get_all_states()
	var result_state_slots := main.get("_battle_state_slots") as Dictionary
	var defeated_state: BattleSquadState
	var any_result_slot: BoardSlot
	for state: BattleSquadState in result_states:
		var mapped_slot := result_state_slots.get(state) as BoardSlot
		if any_result_slot == null and mapped_slot != null:
			any_result_slot = mapped_slot
		if not state.alive:
			defeated_state = state
	_expect(
		_main_formation_signature(main) == formation_before
		and result_state_slots.size() == result_states.size(),
		"进入结算页时立即恢复战前四排布局，并把全部战斗状态映射回原排位"
	)
	_expect(
		any_result_slot != null
		and any_result_slot.is_showing_battle_result_statistics()
		and any_result_slot.card_visual_layer.modulate.r < 1.0
		and any_result_slot.get_battle_result_stat_row_count() > 0,
		"恢复后的卡面压暗，并以图标加数字覆盖本局非零统计"
	)
	var result_rows := any_result_slot.get("_battle_result_rows") as VBoxContainer
	var first_result_row := result_rows.get_child(0) as HBoxContainer
	var result_icon := first_result_row.get_child(0) as TextureRect
	_expect(
		result_icon.custom_minimum_size == result_icon.texture.get_size(),
		"结算统计图标逐张保持原始素材尺寸，不再强制统一缩放"
	)
	var defeated_slot := result_state_slots.get(defeated_state) as BoardSlot
	_expect(
		defeated_state != null
		and defeated_slot != null
		and defeated_slot.has_battle_result_death_mark(),
		"阵亡卡牌恢复原位后在右上角显示骷髅标识"
	)
	var result_log_entries := main.get("_battle_log_entries") as Array
	if not result_log_entries.is_empty():
		main._on_battle_log_meta_hover_started(
			"formula:%d:0" % int(result_log_entries[0].group_id)
		)
	_expect(
		main.formula_popup.visible,
		"结算页保留日志数值的公式悬停查看能力"
	)
	main._on_battle_log_meta_hover_ended("")
	_expect(main.battle_departure_count > 0, "真实死亡批次调用单一退场入口")
	_expect(main.restart_battle(), "重新开始入口可执行")
	await create_timer(main.VIEW_TWEEN_DURATION + 0.05).timeout
	_expect(
		main.current_phase == main.GamePhase.PREPARE
		and main.current_world_view == main.WorldView.COLLECTION
		and not main.battle_result_panel.visible
		and not main.battle_speed_button.visible
		and not main.battle_timer_label.visible
		and not main.battle_log_panel.visible
		and main.battle_log_text.text.is_empty()
		and main.battle_timer_label.text == "战斗 00:00.0"
		and main.battle_controller.get_all_states().is_empty()
		and _main_formation_signature(main) == formation_before
		and _card_resource_signature(main.collection_cards) == cards_before,
		"重新开始清空临时战斗/随机状态，并精确恢复战前阵容和准备默认视图"
	)
	main.queue_free()
	await process_frame


func _test_departure_entry_and_row_recentering() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]:
		row.clear_squads()
	var first: BoardSlot = main.front_row.add_squad(
		_single_squad(CardData.ActionType.HEAL, 1, 1, 0, 100.0), 0
	)
	var second: BoardSlot = main.front_row.add_squad(
		_single_squad(CardData.ActionType.HEAL, 1, 1, 0, 100.0), 1
	)
	main.enemy_front_row.add_squad(
		_single_squad(CardData.ActionType.MELEE, 10, 30, 0, 1.0), 0
	)
	await process_frame
	await process_frame
	var probe_position_before := (
		first.get_primary_card_view().get_global_transform_with_canvas()
		* Vector2.ZERO
	)
	var probe_slots: Array[BoardSlot] = [second]
	main.front_row.remove_squad_slots(probe_slots)
	var probe_position_after := (
		first.get_primary_card_view().get_global_transform_with_canvas()
		* Vector2.ZERO
	)
	_expect(
		probe_position_after.distance_to(probe_position_before) < 0.1
		and first.is_layout_animating(),
		"批量退场在同一帧先补回旧视觉坐标，不让幸存卡根节点抢先闪到终点"
	)
	main.front_row.clear_squads()
	first = main.front_row.add_squad(
		_single_squad(CardData.ActionType.HEAL, 1, 1, 0, 100.0), 0
	)
	second = main.front_row.add_squad(
		_single_squad(CardData.ActionType.HEAL, 1, 1, 0, 100.0), 1
	)
	await process_frame
	await process_frame
	_expect(main.start_battle(1108, false), "建立真实死亡退场与同行居中测试战斗")
	main.battle_controller.resolve_next_batch()
	await process_frame
	var defeated_state: BattleSquadState
	for state: BattleSquadState in main.battle_controller.player_states:
		if not state.alive:
			defeated_state = state
			break
	var defeated_slot := main.get("_battle_state_slots").get(defeated_state) as BoardSlot
	_expect(
		main.battle_departure_count == 1
		and main.front_row.get_squad_count() == 2
		and is_instance_valid(defeated_slot)
		and defeated_slot.is_death_dissolving()
		and defeated_slot.get_death_dissolve_item_count() > 1,
		"死亡小队经单一入口让多层卡面共用溶解材质，动画期间尚未提前移除"
	)
	await create_timer(SquadView.DEATH_DISSOLVE_BODY_SECONDS * 0.5).timeout
	_expect(
		is_instance_valid(defeated_slot)
		and defeated_slot.get_death_dissolve_progress() > 0.0
		and defeated_slot.get_death_dissolve_progress() < 1.0,
		"溶解主体参数由 Tween 在动画中连续推进"
	)
	await create_timer(
		SquadView.DEATH_DISSOLVE_EDGE_SECONDS
		- SquadView.DEATH_DISSOLVE_BODY_SECONDS * 0.5
		+ 0.05
	).timeout
	var survivor: BoardSlot = first if is_instance_valid(first) and first.get_parent() != null else second
	_expect(
		main.front_row.get_squad_count() == 1
		and is_instance_valid(survivor)
		and survivor.is_layout_animating(),
		"溶解完成后同批次只重排一次，幸存卡当帧保持旧位置再平滑居中"
	)
	_expect(
		SquadView.DEATH_DISSOLVE_EDGE_SECONDS
		- SquadView.DEATH_DISSOLVE_BODY_SECONDS <= 0.1,
		"缩短溶解总时长，并用更小的主体/边缘时间差减少绿色边缘面积"
	)
	main.queue_free()
	await process_frame


func _create_controller(
	player: Array[Dictionary],
	enemy: Array[Dictionary],
	seed_value: int
) -> BattleController:
	var controller := BattleController.new()
	root.add_child(controller)
	await process_frame
	controller.start_battle(player, enemy, seed_value, false)
	return controller


func _dispose_controller(controller: BattleController) -> void:
	controller.queue_free()
	await process_frame


func _single_squad(
	action_type: int,
	base_value: int,
	health: int,
	armor: int,
	cooldown: float
) -> SquadData:
	return SquadData.from_card(_make_card(action_type, base_value, health, armor, cooldown))


func _make_card(
	action_type: int,
	base_value: int,
	health: int,
	armor: int,
	cooldown: float
) -> CardData:
	_card_serial += 1
	var card := CardData.new()
	card.id = StringName("stage7_%d" % _card_serial)
	card.display_name = "测试卡%d" % _card_serial
	card.action_type = action_type
	card.base_value = base_value
	card.max_health = health
	card.armor = armor
	card.cooldown_seconds = cooldown
	card.runes.assign(_runes([
		CardData.ElementType.FIRE,
		CardData.ElementType.WATER,
		CardData.ElementType.WOOD,
	]))
	return card


func _formation_entry(
	squad: SquadData,
	row_key: StringName,
	formation_index: int
) -> Dictionary:
	return {
		"squad_data": squad,
		"row_key": row_key,
		"formation_index": formation_index,
	}


func _main_formation_signature(main: Variant) -> Dictionary:
	return {
		"player_front": _row_signature(main.front_row),
		"player_back": _row_signature(main.back_row),
		"enemy_front": _row_signature(main.enemy_front_row),
		"enemy_back": _row_signature(main.enemy_back_row),
	}


func _row_signature(row: BattlefieldRow) -> Array:
	var result: Array = []
	for slot: BoardSlot in row.get_squads():
		var squad := slot.get_squad_data()
		result.append({
			"horizontal": squad.horizontal_cards.map(func(card: CardData) -> String: return String(card.id)),
			"layers": squad.layer_cards.map(func(card: CardData) -> String: return String(card.id)),
			"layout": squad.two_card_layout,
		})
	return result


func _card_resource_signature(cards: Array[CardData]) -> Array:
	var result: Array = []
	for card: CardData in cards:
		result.append([
			card.id,
			card.action_type,
			card.base_value,
			card.cooldown_seconds,
			card.max_health,
			card.armor,
			card.get_base_target_priority(),
		])
	return result


func _cards(values: Array) -> Array[CardData]:
	var result: Array[CardData] = []
	for value: Variant in values:
		result.append(value as CardData)
	return result


func _runes(values: Array) -> Array[CardData.ElementType]:
	var result: Array[CardData.ElementType] = []
	for value: Variant in values:
		result.append(value as CardData.ElementType)
	return result


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failure_count += 1
	push_error("FAIL: %s" % message)
