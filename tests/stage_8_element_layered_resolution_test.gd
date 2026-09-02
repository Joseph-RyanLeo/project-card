extends SceneTree

## 阶段 8 真实规则测试：直接使用 BattleController/BattleSquadState，不使用 mock。

const BattleController = preload("res://scripts/battle/battle_controller.gd")
const BattleSquadState = preload("res://scripts/battle/battle_squad_state.gd")
const BattleEffectEvent = preload("res://scripts/battle/battle_effect_event.gd")
const BattleFormulaData = preload("res://scripts/battle/battle_formula_data.gd")
const BattleLogEntry = preload("res://scripts/battle/battle_log_entry.gd")
const BattleAttackEffectProfiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
const BattleAttackTrailRenderer = preload("res://scripts/battle/battle_attack_trail_renderer.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")

var failures: int = 0
var test_root: Node


func _initialize() -> void:
	test_root = Node.new()
	get_root().add_child(test_root)
	_run.call_deferred()


func _run() -> void:
	BattleAttackEffectProfiles.reload(false)
	_test_config_and_element_groups()
	_test_precise_channels_and_attribution()
	await _test_all_element_tiers()
	await _test_all_action_modes()
	await _test_straight_and_same_element_two_pair()
	await _test_fire_independent_statuses()
	await _test_water_dark_light_wood_targets()
	await _test_combinations_and_layering()
	_test_water_target_boundaries()
	_test_cover_union_and_boundary()
	_test_structured_log_and_formula()
	await _test_formula_popup_ui()
	if failures == 0:
		print("Stage 8 element/layered resolution checks passed.")
	else:
		push_error("Stage 8 element/layered resolution checks failed: %d" % failures)
	quit(failures)


func _test_config_and_element_groups() -> void:
	for element: int in CardData.ElementType.values():
		_expect(not bool(BattleRules.BASE_ELEMENT_EFFECTS[element]["enabled"]), "五元素基础效果本阶段统一关闭")
	for count: int in range(2, 6):
		_expect(not BattleRules.get_element_config(CardData.ElementType.FIRE, count).is_empty(), "火%d档集中配置" % count)
		_expect(not BattleRules.get_element_config(CardData.ElementType.WATER, count).is_empty(), "水%d档集中配置" % count)
		_expect(not BattleRules.get_element_config(CardData.ElementType.DARK, count).is_empty(), "暗%d档集中配置" % count)
		_expect(not BattleRules.get_element_config(CardData.ElementType.LIGHT, count).is_empty(), "光%d档集中配置" % count)
		_expect(not BattleRules.get_element_config(CardData.ElementType.WOOD, count).is_empty(), "木%d档集中配置" % count)
	var full_house := _squad_with_runes([CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.WATER, CardData.ElementType.WATER]).get_rune_pattern_result()
	var full_groups := BattleElementResolver.get_element_groups(full_house)
	_expect(full_groups.size() == 2 and int(full_groups[0]["count"]) == 3 and int(full_groups[1]["count"]) == 2, "葫芦严格按三条元素→对子元素")
	var two_pair := _squad_with_runes([CardData.ElementType.WOOD, CardData.ElementType.WOOD, CardData.ElementType.FIRE, CardData.ElementType.FIRE, CardData.ElementType.LIGHT]).get_rune_pattern_result()
	var pair_groups := BattleElementResolver.get_element_groups(two_pair)
	_expect(pair_groups.size() == 2 and int(pair_groups[0]["element"]) == CardData.ElementType.WOOD and int(pair_groups[1]["element"]) == CardData.ElementType.FIRE, "两对严格按可见序列第一组→第二组")
	var same_pair := _squad_with_runes([CardData.ElementType.FIRE, CardData.ElementType.FIRE, CardData.ElementType.WATER, CardData.ElementType.FIRE, CardData.ElementType.FIRE]).get_rune_pattern_result()
	var same_pair_groups := BattleElementResolver.get_element_groups(same_pair)
	_expect(
		same_pair_groups.size() == 1
		and int(same_pair_groups[0]["element"]) == CardData.ElementType.FIRE
		and int(same_pair_groups[0]["count"]) == 3
		and is_equal_approx(BattleRules.get_pattern_multiplier(same_pair.pattern_type), 2.0),
		"同花两对按同元素三条档效果与 2.0 牌型倍率结算"
	)


func _test_precise_channels_and_attribution() -> void:
	var target := _state(_single_squad(CardData.ActionType.HEAL, 1, 10, 0, 9.0), BattleSquadState.Side.PLAYER, &"player_front", 0)
	var source_a := _state(_single_squad(CardData.ActionType.MELEE, 1, 10, 0, 9.0), BattleSquadState.Side.ENEMY, &"enemy_front", 0)
	var source_b := _state(_single_squad(CardData.ActionType.MELEE, 1, 10, 0, 9.0), BattleSquadState.Side.ENEMY, &"enemy_front", 1)
	var commits: Array[Dictionary] = []
	target.integer_settlement_committed.connect(func(event: Dictionary) -> void: commits.append(event))
	var first_event := _raw_event(source_a, target, 0.4)
	target.apply_damage_exact(0.4, source_a, first_event)
	_expect(is_equal_approx(float(target.current_health), 9.6) and target.displayed_health == 10 and commits.is_empty(), "0.4伤害立即进入精确生命但卡面暂不跨整数")
	var boundary_event := _raw_event(source_b, target, 0.6)
	target.apply_damage_exact(0.6, source_b, boundary_event)
	_expect(target.displayed_health == 9 and commits.size() == 1 and commits[0]["source"] == source_b and int(commits[0]["amount"]) == 1, "跨整数边界由最后施加来源取得触发归属")
	var single_event := _raw_event(source_a, target, 2.7)
	target.apply_damage_exact(2.7, source_a, single_event)
	_expect(int(commits[-1]["amount"]) == 2 and is_equal_approx(float(target.fractional_accumulators[BattleSquadState.CHANNEL_HEALTH_DAMAGE]), 0.7), "单次2.7只发一个amount=2事件并保留0.7")
	var full := _state(_single_squad(CardData.ActionType.HEAL, 1, 10, 0, 9.0), BattleSquadState.Side.PLAYER, &"player_front", 0)
	full.apply_healing_exact(3.5, source_a, _raw_event(source_a, full, 3.5))
	_expect(is_equal_approx(float(full.fractional_accumulators[BattleSquadState.CHANNEL_HEALING]), 0.0), "过量治疗不进入小数累计")
	full.current_armor = 998.8
	full.apply_armor_exact(1.0, source_a, _raw_event(source_a, full, 1.0))
	_expect(is_equal_approx(float(full.current_armor), 999.0) and is_equal_approx(float(full.fractional_accumulators[BattleSquadState.CHANNEL_ARMOR_GAIN]), 0.2), "超过999的护甲部分不进入累计")
	var doomed := _state(_single_squad(CardData.ActionType.HEAL, 1, 2, 0, 9.0), BattleSquadState.Side.PLAYER, &"player_front", 0)
	var kill_event := _raw_event(source_a, doomed, 3.0)
	doomed.apply_damage_exact(3.0, source_a, kill_event)
	_expect(doomed.pending_kill_source == source_a, "精确生命首次跨过0时记录最后伤害来源")
	doomed.apply_healing_exact(2.0, source_b, _raw_event(source_b, doomed, 2.0))
	doomed.finalize_batch_survival()
	_expect(doomed.current_health > 0.0 and doomed.pending_kill_source == null, "同批治疗救回后取消击杀候选")
	doomed.apply_damage_exact(2.0, source_b, _raw_event(source_b, doomed, 2.0))
	_expect(doomed.pending_kill_source == source_b, "治疗救回后在下一逻辑层再次跨0时记录新的最后伤害来源")


func _test_all_element_tiers() -> void:
	for count: int in range(2, 6):
		for element: int in CardData.ElementType.values():
			var controller := await _controller_for_element(element, count, CardData.ActionType.MELEE, 1000 + element * 10 + count)
			var events: Array[BattleEffectEvent] = []
			controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void: events.append(event))
			controller.resolve_next_batch()
			var found := false
			for event: BattleEffectEvent in events:
				if event.element_type == element:
					found = true
			_expect(found, "%s%d档生成对应元素事件或状态标记" % [CardData.new().get_element_type_name(element), count])
			if element == CardData.ElementType.FIRE:
				_expect(controller.active_continuous_effects.size() == 1 and int(controller.active_continuous_effects[0]["ticks_remaining"]) == int(BattleRules.FIRE_CONFIG[count]["ticks"]), "火%d档保存独立持续次数" % count)
			await _dispose(controller)


func _test_all_action_modes() -> void:
	for element: int in CardData.ElementType.values():
		for action_type: int in CardData.ActionType.values():
			var controller := await _controller_for_element(element, 2, action_type, 2000 + element * 10 + action_type)
			var element_events: Array[BattleEffectEvent] = []
			controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
				if event.element_type == element: element_events.append(event)
			)
			if action_type == CardData.ActionType.HEAL:
				for state: BattleSquadState in controller.player_states:
					state.current_health = 50
					state.displayed_health = 50
			controller.resolve_next_batch()
			var supported := not element_events.is_empty()
			if element == CardData.ElementType.FIRE:
				supported = controller.active_continuous_effects.size() == 1 and int(controller.active_continuous_effects[0]["action_type"]) == action_type
			else:
				supported = supported and element_events[0].effect_kind == _kind_for_action(action_type)
			_expect(supported, "%s元素支持%s行动模式" % [CardData.new().get_element_type_name(element), _action_name(action_type)])
			await _dispose(controller)


func _test_straight_and_same_element_two_pair() -> void:
	var same_pair := await _same_element_two_pair_controller(3201)
	var same_pair_base: Array[BattleEffectEvent] = []
	same_pair.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.is_base_action: same_pair_base.append(event)
	)
	same_pair.resolve_next_batch()
	_expect(
		same_pair_base.size() == 1
		and is_equal_approx(same_pair_base[0].exact_amount, 20.0)
		and same_pair.active_continuous_effects.size() == 1
		and int(same_pair.active_continuous_effects[0]["ticks_remaining"]) == 3
		and is_equal_approx(float(same_pair.active_continuous_effects[0]["element_multiplier"]), 0.20),
		"同花两对完整复用三条火的倍率、三跳持续效果和 2.0B 基础行动"
	)
	await _dispose(same_pair)

	var straight := await _straight_controller(3202)
	var straight_events: Array[BattleEffectEvent] = []
	var straight_ticks: Array[BattleEffectEvent] = []
	straight.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.logical_layer == 1 and event.element_type >= 0:
			straight_events.append(event)
		if event.is_continuous and event.element_type == CardData.ElementType.FIRE:
			straight_ticks.append(event)
	)
	straight.resolve_next_batch()
	var expected_kinds: Array[StringName] = [&"dark_repeat", &"water_spread", &"wood_pierce", &"light_reflect", &"fire_burn"]
	var found_kinds: Array[StringName] = []
	var all_unlinked := true
	var all_secondary_values_correct := true
	for event: BattleEffectEvent in straight_events:
		found_kinds.append(event.visual_kind)
		all_unlinked = all_unlinked and not event.can_trigger_element_chain
		if event.effect_kind != BattleEffectEvent.EffectKind.PLACEHOLDER:
			all_secondary_values_correct = all_secondary_values_correct and is_equal_approx(event.exact_amount, 30.0)
	_expect(
		straight_events.size() == 5
		and expected_kinds.all(func(kind: StringName) -> bool: return found_kinds.has(kind))
		and all_unlinked
		and all_secondary_values_correct
		and straight.active_continuous_effects.size() == 1
		and is_equal_approx(float(straight.active_continuous_effects[0]["element_multiplier"]), 0.5)
		and not bool(straight.active_continuous_effects[0]["can_trigger_element_chain"]),
		"顺子在 3.0B 主行动后各生成一次 1.0B 连击、扩散、穿刺、折射，并建立不连锁灼烧"
	)
	straight.advance_time(3.01)
	var tick_total := 0.0
	for event: BattleEffectEvent in straight_ticks:
		tick_total += event.exact_amount
	_expect(
		straight_ticks.size() == 3
		and is_equal_approx(tick_total, 45.0)
		and straight_ticks.all(func(event: BattleEffectEvent) -> bool: return not event.can_trigger_element_chain),
		"顺子灼烧持续 3 秒、每秒 0.5B、合计 1.5B，持续结算同样禁止连锁"
	)
	await _dispose(straight)


func _test_fire_independent_statuses() -> void:
	var controller := await _controller_for_element(CardData.ElementType.FIRE, 5, CardData.ActionType.MELEE, 3001)
	controller.resolve_next_batch()
	controller.player_states[0].remaining_cooldown = 0.0
	controller.resolve_next_batch()
	_expect(controller.active_continuous_effects.size() == 2, "每次灼烧独立创建，不刷新、不合并、不覆盖")
	var source := controller.player_states[0]
	controller.player_states.append(_state(_single_squad(CardData.ActionType.HEAL, 1, 100, 0, 9.9), BattleSquadState.Side.PLAYER, &"player_back", 0))
	source.alive = false
	var fire_events: Array[BattleEffectEvent] = []
	var kill_events: Array = []
	controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.is_continuous: fire_events.append(event)
	)
	controller.kill_resolved.connect(func(killer, target, event) -> void: kill_events.append([killer, target, event]))
	controller.advance_time(1.0)
	_expect(fire_events.size() == 2 and fire_events[0].source == source, "来源死亡后两份灼烧继续独立结算并保留原来源")
	var kill_target := controller.active_continuous_effects[0]["target"] as BattleSquadState
	kill_target.current_health = 0.1
	kill_target.displayed_health = 1
	controller.advance_time(1.0)
	_expect(not kill_events.is_empty() and kill_events[0][0] == source, "DOT来源死亡后仍由原施加卡取得击杀归属")
	for status: Dictionary in controller.active_continuous_effects:
		var target := status["target"] as BattleSquadState
		target.current_health = 0
		target.alive = false
	controller.advance_time(1.0)
	_expect(controller.active_continuous_effects.is_empty(), "五火目标提前死亡时剩余DOT与终结全部取消")
	await _dispose(controller)


func _test_water_dark_light_wood_targets() -> void:
	var spread := await _multi_target_controller(CardData.ElementType.WATER, 5, 4101)
	var water_targets: Array[BattleSquadState] = []
	spread.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.element_type == CardData.ElementType.WATER: water_targets.append(event.target)
	)
	spread.resolve_next_batch()
	_expect(water_targets.size() <= 4 and water_targets.duplicate().all(func(value): return water_targets.count(value) == 1), "五水左右各最多两个且同层不重复")
	await _dispose(spread)

	var dark := await _controller_for_element(CardData.ElementType.DARK, 5, CardData.ActionType.MELEE, 4102, 7, 25)
	var dark_events: Array[BattleEffectEvent] = []
	dark.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.element_type == CardData.ElementType.DARK: dark_events.append(event)
	)
	dark.resolve_next_batch()
	_expect(dark_events.size() == 1, "暗原目标被首个追加击杀后取消剩余追加且不转移")
	await _dispose(dark)

	var light_a := await _multi_target_controller(CardData.ElementType.LIGHT, 5, 4103)
	var light_b := await _multi_target_controller(CardData.ElementType.LIGHT, 5, 4103)
	var ids_a: Array[int] = []
	var ids_b: Array[int] = []
	light_a.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.element_type == CardData.ElementType.LIGHT: ids_a.append(event.target.formation_index)
	)
	light_b.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.element_type == CardData.ElementType.LIGHT: ids_b.append(event.target.formation_index)
	)
	light_a.resolve_next_batch()
	light_b.resolve_next_batch()
	_expect(ids_a == ids_b and ids_a.duplicate().all(func(value): return ids_a.count(value) == 1), "光折射固定种子确定且一轮内不重复")
	await _dispose(light_a)
	await _dispose(light_b)

	var wood := await _wood_controller(5, CardData.ActionType.MELEE, 4104)
	var wood_events: Array[BattleEffectEvent] = []
	wood.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.element_type == CardData.ElementType.WOOD: wood_events.append(event)
	)
	wood.resolve_next_batch()
	_expect(wood_events.size() == 1 and wood_events[0].target.row_key != wood_events[0].anchor.row_key and wood_events[0].pierces_armor, "五木按横向投影命中另一排并穿透护甲")
	await _dispose(wood)
	var wood_empty := BattleController.new()
	test_root.add_child(wood_empty)
	var empty_actor := _squad_with_runes([CardData.ElementType.WOOD, CardData.ElementType.WOOD, CardData.ElementType.WOOD, CardData.ElementType.WOOD], CardData.ActionType.MELEE, 10, 100, 0, 9.0)
	var empty_players: Array[Dictionary] = [_entry(empty_actor, &"player_front", 0)]
	var empty_enemies: Array[Dictionary] = [_entry(_single_squad(CardData.ActionType.HEAL, 1, 200, 0, 9.9), &"enemy_front", 0)]
	wood_empty.start_battle(empty_players, empty_enemies, 4105, false)
	var empty_events := 0
	wood_empty.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.element_type == CardData.ElementType.WOOD: empty_events += 1
	)
	wood_empty.resolve_next_batch()
	_expect(empty_events == 0, "木对应另一排为空时失效")
	await _dispose(wood_empty)
	for mode: int in [CardData.ActionType.HEAL, CardData.ActionType.DEFENSE]:
		var conversion := await _wood_controller(3, mode, 4110 + mode)
		var kinds: Array[int] = []
		conversion.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
			if event.element_type == CardData.ElementType.WOOD: kinds.append(event.effect_kind)
		)
		conversion.resolve_next_batch()
		_expect(kinds.has(BattleEffectEvent.EffectKind.HEALING) and kinds.has(BattleEffectEvent.EffectKind.ARMOR), "三木以上%s在副目标额外获得治疗/护甲转换" % _action_name(mode))
		await _dispose(conversion)


func _test_combinations_and_layering() -> void:
	var controller := await _full_house_controller(5101)
	var layers: Array[int] = []
	var secondary_amounts: Array[float] = []
	controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.element_type >= 0:
			layers.append(event.logical_layer)
		if event.logical_layer == 2:
			secondary_amounts.append(event.exact_amount)
	)
	controller.resolve_next_batch()
	var expected := 10.0 * BattleRules.get_pattern_multiplier(RunePatternResult.PatternType.FULL_HOUSE) * 0.30 * 0.40
	_expect(layers.has(1) and layers.has(2) and not secondary_amounts.is_empty() and is_equal_approx(secondary_amounts[0], expected), "3光+2水按三层流程继续乘当前浮点值")
	await _dispose(controller)

	var two_pair := await _wood_fire_two_pair_controller(5102)
	two_pair.resolve_next_batch()
	_expect(two_pair.active_continuous_effects.size() == 1 and is_equal_approx(float(two_pair.active_continuous_effects[0]["element_multiplier"]), 0.40 * 0.133), "2木+2火在另一排建立B×木倍率×火倍率的DOT")
	await _dispose(two_pair)

	var fire_water := await _fire_water_full_house_controller(51021)
	var chained_water: Array[BattleEffectEvent] = []
	fire_water.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.element_type == CardData.ElementType.WATER: chained_water.append(event)
	)
	fire_water.resolve_next_batch()
	fire_water.advance_time(1.0)
	var fire_water_expected := 10.0 * BattleRules.get_pattern_multiplier(RunePatternResult.PatternType.FULL_HOUSE) * 0.20 * 0.40
	_expect(not chained_water.is_empty() and is_equal_approx(chained_water[0].exact_amount, fire_water_expected), "3火+2水让副元素跟随每次真实DOT并继续乘火、水倍率")
	await _dispose(fire_water)

	var simultaneous := await _simultaneous_controller(5103)
	var base_actors: Array[BattleSquadState] = []
	simultaneous.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.is_base_action: base_actors.append(event.source)
	)
	simultaneous.resolve_next_batch()
	_expect(base_actors.size() == 2, "同时间行动者先完成本层选目标，再统一结算，互相击杀仍各自行動")
	await _dispose(simultaneous)


func _test_cover_union_and_boundary() -> void:
	var controller := BattleController.new()
	test_root.add_child(controller)
	var back := _state(_single_squad(CardData.ActionType.MELEE, 1, 10, 0, 9.0), BattleSquadState.Side.PLAYER, &"player_back", 0)
	var front_a := _state(_single_squad(CardData.ActionType.MELEE, 1, 10, 0, 9.0), BattleSquadState.Side.PLAYER, &"player_front", 0)
	var front_b := _state(_single_squad(CardData.ActionType.MELEE, 1, 10, 0, 9.0), BattleSquadState.Side.PLAYER, &"player_front", 1)
	controller.player_states.assign([back, front_a, front_b])
	back.logical_left = 0.0; back.logical_right = 100.0
	front_a.logical_left = 0.0; front_a.logical_right = 30.0
	front_b.logical_left = 20.0; front_b.logical_right = 50.0
	_expect(is_equal_approx(controller.get_front_cover_ratio(back), 0.5) and controller.get_effective_target_weight(back) == back.get_target_weight(), "遮挡恰好50%不降低受击权重，重叠区间按并集只算一次")
	front_b.logical_right = 50.01
	_expect(controller.get_front_cover_ratio(back) > 0.5 and controller.get_effective_target_weight(back) == maxi(back.get_target_weight() - 1, 1), "遮挡超过50%才降低1且最终最低为1")
	controller.queue_free()


func _test_water_target_boundaries() -> void:
	var controller := BattleController.new()
	test_root.add_child(controller)
	var anchor := _state(_single_squad(CardData.ActionType.HEAL, 1, 10, 0, 9.0), BattleSquadState.Side.ENEMY, &"enemy_front", 1)
	var left := _state(_single_squad(CardData.ActionType.HEAL, 1, 10, 0, 9.0), BattleSquadState.Side.ENEMY, &"enemy_front", 0)
	var right_a := _state(_single_squad(CardData.ActionType.HEAL, 1, 10, 0, 9.0), BattleSquadState.Side.ENEMY, &"enemy_front", 2)
	var right_b := _state(_single_squad(CardData.ActionType.HEAL, 1, 10, 0, 9.0), BattleSquadState.Side.ENEMY, &"enemy_front", 3)
	var right_c := _state(_single_squad(CardData.ActionType.HEAL, 1, 10, 0, 9.0), BattleSquadState.Side.ENEMY, &"enemy_front", 4)
	anchor.logical_center = 50.0; left.logical_center = 20.0; right_a.logical_center = 80.0; right_b.logical_center = 100.0; right_c.logical_center = 120.0
	controller.enemy_states.assign([left, anchor, right_a, right_b, right_c])
	var five_targets: Array[BattleSquadState] = controller._water_targets(anchor, BattleRules.WATER_CONFIG[5])
	_expect(five_targets.size() == 3 and five_targets.has(left) and five_targets.has(right_a) and five_targets.has(right_b) and not five_targets.has(right_c), "五水某侧不足时不从另一侧补位")
	var two_targets: Array[BattleSquadState] = controller._water_targets(anchor, BattleRules.WATER_CONFIG[2])
	_expect(two_targets.size() == 1 and two_targets[0] in [left, right_a], "二水只在左右最近合法邻居中随机一个")
	controller.queue_free()


func _test_structured_log_and_formula() -> void:
	var source := _state(_single_squad(CardData.ActionType.RANGED, 10, 10, 0, 9.0), BattleSquadState.Side.PLAYER, &"player_front", 0)
	var target := _state(_single_squad(CardData.ActionType.HEAL, 1, 10, 0, 9.0), BattleSquadState.Side.ENEMY, &"enemy_front", 0)
	var event := _raw_event(source, target, 0.03)
	event.group_id = 77
	event.action_type = CardData.ActionType.RANGED
	event.formula = BattleFormulaData.create("远程伤害", CardData.ActionType.RANGED, 10.0, 1.5, 0.002, source, target)
	event.exact_amount = 0.03
	var entry := BattleLogEntry.new()
	entry.group_id = 77
	entry.add_event(event)
	_expect(entry.events.size() == 1 and entry.to_bbcode().contains("[url=formula:77:0]0.03点远程伤害[/url]"), "0.03点远程伤害整段进入可悬停的结构化日志链接")
	_expect(is_equal_approx(event.formula.calculate_result(), 0.03) and event.formula.additive_terms.is_empty() and event.formula.other_multipliers.is_empty(), "公式结构保留前置加成、牌型、元素、其他倍率和固定加成入口")


func _test_formula_popup_ui() -> void:
	var main := MAIN_SCENE.instantiate()
	test_root.add_child(main)
	await process_frame
	var source := _state(_single_squad(CardData.ActionType.RANGED, 10, 10, 0, 9.0), BattleSquadState.Side.PLAYER, &"player_front", 0)
	var target := _state(_single_squad(CardData.ActionType.HEAL, 1, 10, 0, 9.0), BattleSquadState.Side.ENEMY, &"enemy_front", 0)
	var event := _raw_event(source, target, 0.03)
	event.group_id = 8801
	event.formula = BattleFormulaData.create("远程伤害", CardData.ActionType.RANGED, 10.0, 1.5, 0.002, source, target)
	event.exact_amount = 0.03
	main._on_battle_effect_resolved(event)
	main._on_battle_log_meta_hover_started("formula:8801:0")
	var popup_end: Vector2 = main.formula_popup.position + main.formula_popup.size
	var viewport_size: Vector2 = main.get_viewport_rect().size
	var compact_size: Vector2 = main._measure_formula_popup_size(main._format_formula_popup(event.formula))
	var detailed_formula := BattleFormulaData.create(
		"远程伤害",
		CardData.ActionType.RANGED,
		10.0,
		1.5,
		0.8,
		source,
		target,
		[{"name": "暗元素追加倍率", "value": 0.5}, {"name": "战场环境倍率", "value": 1.1}],
		[{"name": "装备加成", "value": 2.0}, {"name": "祝福加成", "value": 1.0}]
	)
	var detailed_size: Vector2 = main._measure_formula_popup_size(main._format_formula_popup(detailed_formula))
	_expect(main.formula_popup.visible and main.formula_popup_text.text.contains("基础数值") and main.formula_popup_text.text.contains("牌型倍率") and main.formula_popup_text.text.contains("本次进入小数累计"), "日志完整结果短语悬停显示公式弹窗")
	_expect(main.battle_log_text.meta_underlined, "日志中的完整结果链接始终显示下划线")
	_expect(compact_size.y < 238.0 and detailed_size.y > compact_size.y, "公式弹窗按实际行数收缩并随详细条目自动增高")
	_expect(main.formula_popup.position.x >= 0.0 and main.formula_popup.position.y >= 0.0 and popup_end.x <= viewport_size.x and popup_end.y <= viewport_size.y, "公式弹窗始终限制在窗口内")
	var water_color: Color = main._element_attack_color(CardData.ElementType.WATER)
	main._play_element_line(
		PackedVector2Array([Vector2(300, 120), Vector2(500, 180)]),
		&"water_spread",
		water_color,
		water_color
	)
	main._play_element_impact(Vector2(500, 180), &"water_spread")
	var beam_segment := main.battle_effect_layer.get_node_or_null("ElementEnergyBeam") as Node2D
	var beam_mesh := beam_segment.get_node_or_null("BeamMesh") as MeshInstance2D if beam_segment != null else null
	var beam_material := beam_mesh.material as ShaderMaterial if beam_mesh != null else null
	var beam_arrays: Array = beam_mesh.mesh.surface_get_arrays(0) if beam_mesh != null else []
	var beam_vertices: PackedVector2Array = beam_arrays[Mesh.ARRAY_VERTEX] if not beam_arrays.is_empty() else PackedVector2Array()
	var water_profile: Dictionary = BattleAttackEffectProfiles.get_profile(&"water_spread")
	var middle_vertex_index: int = floori(float(water_profile["curve_segments"]) * 0.5) * 2
	var ribbon_middle := (
		(beam_vertices[middle_vertex_index] + beam_vertices[middle_vertex_index + 1]) * 0.5
		if beam_vertices.size() > middle_vertex_index + 1
		else Vector2.ZERO
	)
	var straight_middle := Vector2(400, 150)
	var has_impact := main.battle_effect_layer.get_node_or_null("ElementImpact") != null
	_expect(
		main.battle_effect_layer.z_index == main.EFFECT_LAYER_Z_INDEX
		and main.EFFECT_LAYER_Z_INDEX > CardView.CARD_LAYER_Z_STEP * 3
		and beam_material != null
		and beam_material.shader.resource_path == "res://shaders/battle_energy_beam.gdshader"
		and is_equal_approx(float(beam_material.get_shader_parameter("pixel_size")), float(water_profile["pixel_size"]))
		and is_equal_approx(float(beam_material.get_shader_parameter("trail_length")), float(water_profile["trail_length"]))
		and beam_material.get_shader_parameter("trail_mask") == BattleAttackTrailRenderer.BATTLE_TRAIL_ENERGY_TEXTURE
		and bool(beam_material.get_shader_parameter("flip_mask_x"))
		and beam_material.get_shader_parameter("head_color") == water_color
		and beam_material.get_shader_parameter("tail_color") == water_color
		and is_equal_approx(
			float(beam_material.get_shader_parameter("flow_speed")),
			float(water_profile["flow_speed"])
		)
		and is_equal_approx(
			float(beam_material.get_shader_parameter("flow_frequency")),
			float(water_profile["flow_frequency"])
		)
		and is_equal_approx(float(beam_material.get_shader_parameter("warp_speed")), float(water_profile["warp_speed"]))
		and is_equal_approx(float(beam_material.get_shader_parameter("warp_frequency")), float(water_profile["warp_frequency"]))
		and is_equal_approx(float(beam_material.get_shader_parameter("twirl_frequency")), float(water_profile["twirl_frequency"]))
		and is_equal_approx(float(beam_material.get_shader_parameter("warp_strength")), float(water_profile["warp_strength"]))
		and is_equal_approx(float(beam_material.get_shader_parameter("edge_threshold")), float(water_profile["edge_threshold"]))
		and is_equal_approx(float(beam_material.get_shader_parameter("edge_softness")), float(water_profile["edge_softness"]))
		and ribbon_middle.distance_to(straight_middle) > 10.0
		and has_impact,
		"原图能量遮罩、纯元素色、内部流动、移动短尾巴和贝塞尔弧线建立在三卡堆之上的可见层级"
	)
	_expect(
		BattleAttackTrailRenderer.get_mask_texture(&"projectile") == BattleAttackTrailRenderer.BATTLE_TRAIL_PROJECTILE_TEXTURE
		and BattleAttackEffectProfiles.get_profile(&"ranged_attack")["mask_kind"] == &"projectile"
		and BattleAttackEffectProfiles.get_profile(&"wood_pierce")["mask_kind"] == &"projectile"
		and BattleAttackEffectProfiles.get_profile(&"light_reflect")["mask_kind"] == &"projectile",
		"远程、木穿刺和光折射使用原图尖头弹体遮罩"
	)
	var full_house_actor := _state(
		_squad_with_runes([
			CardData.ElementType.LIGHT,
			CardData.ElementType.LIGHT,
			CardData.ElementType.LIGHT,
			CardData.ElementType.WATER,
			CardData.ElementType.WATER,
		]),
		BattleSquadState.Side.PLAYER,
		&"player_front",
		0
	)
	var full_house_colors: Dictionary = main._attack_element_colors(full_house_actor)
	var two_pair_actor := _state(
		_squad_with_runes([
			CardData.ElementType.WOOD,
			CardData.ElementType.WOOD,
			CardData.ElementType.FIRE,
			CardData.ElementType.FIRE,
			CardData.ElementType.LIGHT,
		]),
		BattleSquadState.Side.PLAYER,
		&"player_front",
		1
	)
	var two_pair_colors: Dictionary = main._attack_element_colors(two_pair_actor)
	var no_element_colors: Dictionary = main._attack_element_colors(source)
	_expect(
		full_house_colors["head"] == main.EFFECT_COLOR_LIGHT
		and full_house_colors["tail"] == main.EFFECT_COLOR_WATER
		and two_pair_colors["head"] == main.EFFECT_COLOR_WOOD
		and two_pair_colors["tail"] == main.EFFECT_COLOR_FIRE
		and no_element_colors["head"] == main.EFFECT_COLOR_NONE
		and no_element_colors["tail"] == main.EFFECT_COLOR_NONE,
		"葫芦按三条→对子、两对按左组→右组生成头尾渐变，无元素保持纯白"
	)
	main._on_battle_log_meta_hover_ended("formula:8801:0")
	main.queue_free()
	await process_frame


func _controller_for_element(element: int, count: int, action_type: int, seed: int, base_value: int = 10, target_health: int = 200) -> BattleController:
	var controller := BattleController.new()
	test_root.add_child(controller)
	var runes: Array[int] = []
	for _index: int in count: runes.append(element)
	var actor := _squad_with_runes(runes, action_type, base_value, 100, 0, 9.0)
	var enemies: Array[Dictionary] = []
	for index: int in 4:
		var row := &"enemy_back" if element == CardData.ElementType.WOOD and index == 3 else &"enemy_front"
		enemies.append(_entry(_single_squad(CardData.ActionType.HEAL, 1, target_health, 0, 9.9), row, index if row == &"enemy_front" else 0))
	var players: Array[Dictionary] = [_entry(actor, &"player_front", 0)]
	if action_type in [CardData.ActionType.HEAL, CardData.ActionType.DEFENSE]:
		players.append(_entry(_single_squad(CardData.ActionType.HEAL, 1, 100, 0, 9.9), &"player_front", 1))
		players.append(_entry(_single_squad(CardData.ActionType.HEAL, 1, 100, 0, 9.9), &"player_front", 2))
		players.append(_entry(_single_squad(CardData.ActionType.HEAL, 1, 100, 0, 9.9), &"player_back", 0))
		players.append(_entry(_single_squad(CardData.ActionType.HEAL, 1, 100, 0, 9.9), &"player_back", 1))
	controller.start_battle(players, enemies, seed, false)
	return controller


func _same_element_two_pair_controller(seed: int) -> BattleController:
	var controller := BattleController.new()
	test_root.add_child(controller)
	var actor := _squad_with_runes([
		CardData.ElementType.FIRE,
		CardData.ElementType.FIRE,
		CardData.ElementType.WATER,
		CardData.ElementType.FIRE,
		CardData.ElementType.FIRE,
	], CardData.ActionType.MELEE, 10, 100, 0, 9.0)
	var target := _single_squad(CardData.ActionType.HEAL, 1, 500, 0, 9.9)
	controller.start_battle([_entry(actor, &"player_front", 0)], [_entry(target, &"enemy_front", 0)], seed, false)
	return controller


func _straight_controller(seed: int) -> BattleController:
	var controller := BattleController.new()
	test_root.add_child(controller)
	var actor := _squad_with_runes([
		CardData.ElementType.FIRE,
		CardData.ElementType.LIGHT,
		CardData.ElementType.DARK,
		CardData.ElementType.WATER,
		CardData.ElementType.WOOD,
	], CardData.ActionType.HEAL, 10, 100, 0, 9.0)
	var wounded := _single_squad(CardData.ActionType.MELEE, 1, 500, 0, 9.9)
	var players: Array[Dictionary] = [
		_entry(actor, &"player_front", 0),
		_entry(wounded, &"player_front", 1),
		_entry(_single_squad(CardData.ActionType.MELEE, 1, 500, 0, 9.9), &"player_front", 2),
		_entry(_single_squad(CardData.ActionType.MELEE, 1, 500, 0, 9.9), &"player_back", 0),
	]
	var enemies: Array[Dictionary] = [
		_entry(_single_squad(CardData.ActionType.HEAL, 1, 500, 0, 9.9), &"enemy_front", 0),
	]
	controller.start_battle(players, enemies, seed, false)
	# 只有这个前排友军受伤，保证顺子治疗的主目标确定且三秒内不会溢出。
	controller.player_states[1].current_health = 300.0
	controller.player_states[1].displayed_health = 300
	return controller


func _multi_target_controller(element: int, count: int, seed: int) -> BattleController:
	var controller := BattleController.new()
	test_root.add_child(controller)
	var runes: Array[int] = []
	for _index: int in count: runes.append(element)
	var enemies: Array[Dictionary] = []
	for index: int in 6:
		enemies.append(_entry(_single_squad(CardData.ActionType.HEAL, 1, 200, 0, 9.9), &"enemy_front", index))
	controller.start_battle([_entry(_squad_with_runes(runes, CardData.ActionType.MELEE, 10, 100, 0, 9.0), &"player_front", 0)], enemies, seed, false)
	return controller


func _wood_controller(count: int, mode: int, seed: int) -> BattleController:
	var controller := BattleController.new()
	test_root.add_child(controller)
	var runes: Array[int] = []
	for _index: int in count: runes.append(CardData.ElementType.WOOD)
	var player: Array[Dictionary] = [_entry(_squad_with_runes(runes, mode, 10, 100, 0, 9.0), &"player_front", 0)]
	if mode in [CardData.ActionType.HEAL, CardData.ActionType.DEFENSE]:
		player.append(_entry(_single_squad(CardData.ActionType.HEAL, 1, 100, 0, 9.9), &"player_back", 0))
	var enemies: Array[Dictionary] = [_entry(_single_squad(CardData.ActionType.HEAL, 1, 200, 50, 9.9), &"enemy_front", 0), _entry(_single_squad(CardData.ActionType.HEAL, 1, 200, 50, 9.9), &"enemy_back", 0)]
	controller.start_battle(player, enemies, seed, false)
	return controller


func _full_house_controller(seed: int) -> BattleController:
	var controller := BattleController.new(); test_root.add_child(controller)
	var actor := _squad_with_runes([CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.WATER, CardData.ElementType.WATER], CardData.ActionType.MELEE, 10, 100, 0, 9.0)
	var enemies: Array[Dictionary] = []
	for index: int in 6: enemies.append(_entry(_single_squad(CardData.ActionType.HEAL, 1, 200, 0, 9.9), &"enemy_front", index))
	controller.start_battle([_entry(actor, &"player_front", 0)], enemies, seed, false)
	return controller


func _wood_fire_two_pair_controller(seed: int) -> BattleController:
	var controller := BattleController.new(); test_root.add_child(controller)
	var actor := _squad_with_runes([CardData.ElementType.WOOD, CardData.ElementType.WOOD, CardData.ElementType.FIRE, CardData.ElementType.FIRE, CardData.ElementType.LIGHT], CardData.ActionType.MELEE, 10, 100, 0, 9.0)
	var enemies: Array[Dictionary] = [_entry(_single_squad(CardData.ActionType.HEAL, 1, 200, 0, 9.9), &"enemy_front", 0), _entry(_single_squad(CardData.ActionType.HEAL, 1, 200, 0, 9.9), &"enemy_back", 0)]
	var players: Array[Dictionary] = [_entry(actor, &"player_front", 0)]
	controller.start_battle(players, enemies, seed, false)
	return controller


func _fire_water_full_house_controller(seed: int) -> BattleController:
	var controller := BattleController.new(); test_root.add_child(controller)
	var actor := _squad_with_runes([CardData.ElementType.FIRE, CardData.ElementType.FIRE, CardData.ElementType.FIRE, CardData.ElementType.WATER, CardData.ElementType.WATER], CardData.ActionType.MELEE, 10, 100, 0, 9.0)
	var enemies: Array[Dictionary] = []
	for index: int in 5:
		enemies.append(_entry(_single_squad(CardData.ActionType.HEAL, 1, 300, 0, 9.9), &"enemy_front", index))
	var players: Array[Dictionary] = [_entry(actor, &"player_front", 0)]
	controller.start_battle(players, enemies, seed, false)
	return controller


func _simultaneous_controller(seed: int) -> BattleController:
	var controller := BattleController.new(); test_root.add_child(controller)
	controller.start_battle([_entry(_single_squad(CardData.ActionType.MELEE, 10, 10, 0, 1.0), &"player_front", 0)], [_entry(_single_squad(CardData.ActionType.MELEE, 10, 10, 0, 1.0), &"enemy_front", 0)], seed, false)
	return controller


func _squad_with_runes(runes_value: Array, action_type: int = CardData.ActionType.MELEE, base_value: int = 10, health: int = 100, armor: int = 0, cooldown: float = 9.0) -> SquadData:
	var runes: Array[CardData.ElementType] = []
	for value: Variant in runes_value: runes.append(int(value) as CardData.ElementType)
	if runes.size() <= 3:
		var card := _card(action_type, base_value, health, armor, cooldown)
		card.runes.assign(runes)
		return SquadData.from_card(card)
	var left := _card(action_type, base_value, health, armor, cooldown)
	left.runes.assign([runes[0], runes[1], runes[2]])
	var right := _card(action_type, base_value, health, armor, cooldown)
	if runes.size() == 4:
		right.runes.assign([runes[3], runes[3], runes[3]])
		var compact := SquadData.from_cards([left, right], SquadData.TwoCardLayout.COMPACT)
		return compact
	right.runes.assign([runes[3], runes[3], runes[4]])
	return SquadData.from_cards([left, right], SquadData.TwoCardLayout.EXPANDED)


func _single_squad(action_type: int, value: int, health: int, armor: int, cooldown: float) -> SquadData:
	return SquadData.from_card(_card(action_type, value, health, armor, cooldown))


func _card(action_type: int, value: int, health: int, armor: int, cooldown: float) -> CardData:
	var card := CardData.new()
	card.id = StringName("stage8_%d_%d_%d" % [action_type, value, randi()])
	card.display_name = "阶段8测试卡"
	card.action_type = action_type
	card.base_value = value
	card.max_health = health
	card.armor = armor
	card.cooldown_seconds = cooldown
	return card


func _state(squad: SquadData, side: int, row: StringName, index: int) -> BattleSquadState:
	var state := BattleSquadState.new()
	state.initialize(squad, side, row, index)
	return state


func _entry(squad: SquadData, row: StringName, index: int) -> Dictionary:
	return {"squad_data": squad, "row_key": row, "formation_index": index}


func _raw_event(source: BattleSquadState, target: BattleSquadState, amount: float) -> BattleEffectEvent:
	var event := BattleEffectEvent.new()
	event.source = source
	event.target = target
	event.exact_amount = amount
	event.formula = BattleFormulaData.create("伤害", CardData.ActionType.MELEE, amount, 1.0, 1.0, source, target)
	return event


func _kind_for_action(action_type: int) -> int:
	if action_type == CardData.ActionType.HEAL: return BattleEffectEvent.EffectKind.HEALING
	if action_type == CardData.ActionType.DEFENSE: return BattleEffectEvent.EffectKind.ARMOR
	return BattleEffectEvent.EffectKind.DAMAGE


func _action_name(action_type: int) -> String:
	return ["近战", "远程", "法术", "治疗", "防御"][action_type]


func _dispose(controller: BattleController) -> void:
	controller.queue_free()
	await process_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
