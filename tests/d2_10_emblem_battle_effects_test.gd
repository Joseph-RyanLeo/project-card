extends SceneTree

## 通过真实 OwnedCard、SquadData 与 BattleController 入口核对普通纹章战斗效果。

const OwnedCard = preload("res://scripts/data/owned_card.gd")
const BattleFormulaPresenter = preload("res://scripts/battle/battle_formula_presenter.gd")
const ANVIL: CardData = preload("res://resources/cards/anvil_margaret.tres")

var failures := 0
var serial := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_visible_instance_registration()
	_test_torch_and_cloak_targeting()
	_test_rush_reinforcement_and_charge()
	_test_brain_death_rush_echo_sleep()
	_test_light_blood_keyword()
	_test_masked_wound_effects_and_paused_clock()
	_test_covered_emblem_clock_and_masked_fire_rune()
	_test_wound_action_windows()
	_test_poison_damage_windows()
	_test_fracture_battle_growth()
	_test_tear_echo_armor_order()
	_test_corpse_poison_and_temporary_restore()
	_test_crystallization_conversion()
	_test_probability_wound_rolls()
	_test_magic_mark_and_greed()
	_test_sandwich_neighbors_and_instance_stacking()
	_test_periodic_healing_and_anvil_armor()
	if failures == 0:
		print("D2-10 emblem battle effect checks passed.")
	else:
		push_error("D2-10 emblem battle effect checks failed: %d" % failures)
	quit(failures)


func _test_visible_instance_registration() -> void:
	var left := _card(&"action_source_card", CardData.ActionType.MELEE)
	var emblem_card := _card(&"non_action_emblem_card", CardData.ActionType.MELEE)
	emblem_card.emblem_slot_count = 1
	var owner := OwnedCard.new()
	owner.initialize(emblem_card, &"non_action_emblem_owner", 1)
	owner.set_emblem_slot(0, {"emblem_id": &"火把", "instance_id": &"visible_torch_instance"})
	var visible_squad := SquadData.from_cards(_typed_cards([left, emblem_card]))
	visible_squad.bind_owned_card(emblem_card, owner)
	visible_squad.layer_cards.assign([emblem_card, left])
	var visible_controller := _start([_entry(visible_squad, &"player_front", 0, 60.0)], [_entry(SquadData.from_card(_card(&"visible_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)])
	_expect(visible_controller.player_states[0].get_action_source() == left and visible_controller.player_states[0].has_targeting_keyword(&"dazzling") and visible_controller._emblem_registrations.size() == 1, "行动来源之外的显现纹章实例仍注册到整个小队")
	_free(visible_controller)

	var hidden_left := _card(&"hidden_left_source", CardData.ActionType.MELEE)
	var hidden_card := _card(&"covered_emblem_card", CardData.ActionType.MELEE)
	hidden_card.emblem_slot_count = 1
	hidden_card.wound_slot_count = 2
	var hidden_owner := OwnedCard.new()
	hidden_owner.initialize(hidden_card, &"covered_emblem_owner", 2)
	# 固定到合法且被上层卡覆盖的左侧纹章槽，避免随机布局把槽放到未重叠的右侧边缘。
	hidden_owner.slot_layout.assign([1, 0, -1, -1, 0, -1, -1, -1])
	hidden_owner.set_emblem_slot(0, {"emblem_id": &"火把", "instance_id": &"covered_torch_instance"})
	var hidden_squad := SquadData.from_cards(_typed_cards([hidden_left, hidden_card]))
	hidden_squad.bind_owned_card(hidden_card, hidden_owner)
	hidden_squad.layer_cards.assign([hidden_left, hidden_card])
	var hidden_controller := _start([_entry(hidden_squad, &"player_front", 0, 60.0)], [_entry(SquadData.from_card(_card(&"hidden_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)])
	_expect(hidden_squad.get_visible_emblem_slot_indices(hidden_card).is_empty() and not hidden_controller.player_states[0].has_targeting_keyword(&"dazzling") and hidden_controller._emblem_registrations.is_empty(), "被上层卡遮挡的纹章槽不注册且不赋予战斗关键词")
	_free(hidden_controller)


func _test_torch_and_cloak_targeting() -> void:
	var torch_owner := _owned_with_emblems(&"torch_owner", [&"火把"])
	var torch_squad := SquadData.from_owned_card(torch_owner)
	var normal_squad := SquadData.from_card(_card(&"ordinary_target", CardData.ActionType.MELEE))
	var controller := _start([
		_entry(normal_squad, &"player_front", 0, 60.0),
		_entry(torch_squad, &"player_front", 1, 60.0),
	], [_entry(SquadData.from_card(_card(&"target_attacker", CardData.ActionType.MELEE)), &"enemy_front", 0, 0.5)])
	var observed_targets: Array[BattleSquadState] = []
	controller.action_resolved.connect(func(_actor: BattleSquadState, target: BattleSquadState, _type: CardData.ActionType, _amount: int) -> void: observed_targets.append(target))
	controller.advance_time(0.5)
	_expect(controller.player_states[1].has_targeting_keyword(&"dazzling") and observed_targets.has(controller.player_states[1]), "火把从真实纹章实例注册耀眼，敌方实际行动选择该目标")
	_free(controller)
	var heal_torch := _owned_with_emblems(&"heal_torch", [&"火把"])
	var heal_controller := _start([
		_entry(SquadData.from_card(_card(&"torch_healer", CardData.ActionType.HEAL)), &"player_front", 0, 0.5),
		_entry(SquadData.from_owned_card(heal_torch), &"player_front", 1, 60.0),
		_entry(SquadData.from_card(_card(&"less_wounded_ally", CardData.ActionType.MELEE)), &"player_front", 2, 60.0),
	], [_entry(SquadData.from_card(_card(&"heal_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)])
	heal_controller.player_states[1].current_health = 10.0
	heal_controller.player_states[2].current_health = 20.0
	var healed_targets: Array[BattleSquadState] = []
	heal_controller.action_resolved.connect(func(_actor: BattleSquadState, target: BattleSquadState, _type: CardData.ActionType, _amount: int) -> void: healed_targets.append(target))
	heal_controller.advance_time(0.5)
	_expect(healed_targets.has(heal_controller.player_states[1]), "真实火把纹章不妨碍治疗按损失生命比例选择目标")
	_free(heal_controller)

	var cloak_owner := _owned_with_emblems(&"cloak_owner", [&"斗篷"])
	var cloak_controller := _start([
		_entry(SquadData.from_owned_card(cloak_owner), &"player_front", 0, 60.0),
		_entry(SquadData.from_card(_card(&"cloak_exposed", CardData.ActionType.MELEE)), &"player_front", 1, 60.0),
	], [_entry(SquadData.from_card(_card(&"cloak_attacker", CardData.ActionType.MELEE)), &"enemy_front", 0, 0.5)])
	var cloak_targets: Array[BattleSquadState] = []
	cloak_controller.action_resolved.connect(func(_actor: BattleSquadState, target: BattleSquadState, _type: CardData.ActionType, _amount: int) -> void: cloak_targets.append(target))
	cloak_controller.advance_time(0.5)
	_expect(cloak_targets.has(cloak_controller.player_states[1]) and not cloak_targets.has(cloak_controller.player_states[0]), "斗篷在首个敌方攻击主目标池中排除，其他副效果规则不在主目标过滤处改写")
	_free(cloak_controller)
	var secondary_cloak := _owned_with_emblems(&"secondary_cloak", [&"斗篷"])
	var water_attacker := _card(&"water_attacker", CardData.ActionType.MELEE)
	water_attacker.runes.assign([CardData.ElementType.WATER, CardData.ElementType.WATER])
	var secondary_controller := _start([
		_entry(SquadData.from_card(_card(&"water_primary_target", CardData.ActionType.MELEE)), &"player_front", 0, 60.0),
		_entry(SquadData.from_owned_card(secondary_cloak), &"player_front", 1, 60.0),
	], [_entry(SquadData.from_card(water_attacker), &"enemy_front", 0, 0.5)])
	secondary_controller.advance_time(0.5)
	_expect(secondary_controller.player_states[1].current_health < secondary_controller.player_states[1].get_max_health() and not secondary_controller.player_states[1].has_runtime_keyword(&"emblem_shadow"), "水扩散副目标实际命中斗篷并按受伤条件提前解除影蔽")
	_free(secondary_controller)

	var revealing_owner := _owned_with_emblems(&"revealing_owner", [&"斗篷"])
	var revealing_controller := _start([_entry(SquadData.from_owned_card(revealing_owner), &"player_front", 0, 0.5)], [_entry(SquadData.from_card(_card(&"revealing_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)])
	revealing_controller.advance_time(0.5)
	_expect(not revealing_controller.player_states[0].has_runtime_keyword(&"emblem_shadow"), "斗篷单位实际行动后提前解除影蔽")
	_free(revealing_controller)
	var duration_owner := _owned_with_emblems(&"duration_owner", [&"斗篷"])
	var duration_controller := _start([_entry(SquadData.from_owned_card(duration_owner), &"player_front", 0, 60.0)], [_entry(SquadData.from_card(_card(&"duration_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)])
	duration_controller.advance_time(14.9)
	_expect(duration_controller.player_states[0].has_runtime_keyword(&"emblem_shadow"), "斗篷未行动且未受伤时15秒内保持影蔽")
	duration_controller.advance_time(0.1)
	_expect(not duration_controller.player_states[0].has_runtime_keyword(&"emblem_shadow"), "斗篷影蔽由确定性战斗时钟在15秒到期")
	_free(duration_controller)

	var overlap_owner := _owned_with_emblems(&"overlap_owner", [&"火把", &"斗篷"])
	var overlap_controller := _start([
		_entry(SquadData.from_owned_card(overlap_owner), &"player_front", 0, 60.0),
	], [_entry(SquadData.from_card(_card(&"overlap_attacker", CardData.ActionType.MELEE)), &"enemy_front", 0, 0.5)])
	var overlap_targets: Array[BattleSquadState] = []
	overlap_controller.action_resolved.connect(func(_actor: BattleSquadState, target: BattleSquadState, _type: CardData.ActionType, _amount: int) -> void: overlap_targets.append(target))
	overlap_controller.advance_time(0.5)
	_expect(overlap_controller.player_states[0].has_targeting_keyword(&"dazzling") and overlap_controller.player_states[0].has_runtime_keyword(&"emblem_shadow") and not overlap_targets.has(overlap_controller.player_states[0]), "同单位同时耀眼和影蔽时先由影蔽排除攻击主目标")
	_free(overlap_controller)


func _test_rush_reinforcement_and_charge() -> void:
	var owner := _owned_with_emblems(&"ham_owner", [&"火腿", &"烤火腿", &"火腿面包", &"奶酪"])
	var squad := SquadData.from_owned_card(owner)
	var controller := _start([_entry(squad, &"player_front", 0, 10.0)], [_entry(SquadData.from_card(_card(&"rush_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)])
	var state := controller.player_states[0]
	_expect(is_equal_approx(state.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT), 8.0), "火腿、烤火腿、火腿面包按四枚实例在战斗开始各叠加强化+2/+3/+3")
	_expect(is_equal_approx(state.remaining_cooldown, 9.5), "奶酪突击通过现有冷却进度充能0.5秒")
	_expect(is_zero_approx(float(owner.permanent_growth.get(OwnedCard.STAT_BASE_VALUE, 0.0))), "战斗强化未写入OwnedCard永久成长")
	_free(controller)
	var action_owner := _owned_with_emblems(&"acting_ham_owner", [&"火腿"])
	var action_controller := _start([_entry(SquadData.from_owned_card(action_owner), &"player_front", 0, 0.5)], [_entry(SquadData.from_card(_card(&"ham_action_target", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)])
	var action_amounts: Array[int] = []
	action_controller.action_resolved.connect(func(actor: BattleSquadState, _target: BattleSquadState, _type: CardData.ActionType, amount: int) -> void:
		if actor.side == BattleSquadState.Side.PLAYER:
			action_amounts.append(amount)
	)
	action_controller.advance_time(0.5)
	_expect(action_amounts.size() == 1 and action_amounts[0] > 2 and is_zero_approx(action_controller.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)), "火腿强化进入实际自动战斗行动数值并在行动后消费，而非只显示在属性检查中")
	_free(action_controller)
	var restarted := _start([_entry(squad, &"player_front", 0, 10.0)], [_entry(SquadData.from_card(_card(&"restart_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)])
	_expect(is_equal_approx(restarted.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT), 8.0), "重开战斗每枚可见实例只初始化一次，没有累积上场次")
	_free(restarted)


func _test_brain_death_rush_echo_sleep() -> void:
	var owner := _owned_with_wounds(&"brain_death_owner", &"脑死亡")
	var controller := _start([
		_entry(SquadData.from_owned_card(owner), &"player_front", 0, 0.5),
	], [_entry(SquadData.from_card(_card(&"brain_death_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)])
	var state := controller.player_states[0]
	_expect(controller._wound_registrations.size() == 1 and state.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 8.0, "显现脑死亡伤势注册并在战斗开始突击获得强化+8")
	controller.advance_time(0.5)
	var cooldown_after_action := state.remaining_cooldown
	_expect(state.is_sleeping(controller.elapsed_seconds), "脑死亡回响在实际行动后施加15秒休眠")
	controller.advance_time(10.0)
	_expect(is_equal_approx(state.remaining_cooldown, cooldown_after_action), "休眠期间行动冷却暂停")
	controller.advance_time(5.0)
	_expect(not state.is_sleeping(controller.elapsed_seconds), "休眠按战斗时钟到期且不依赖帧数")
	controller.advance_time(0.5)
	var refreshed_until := float(state.sleep_source_until.values()[0]) if not state.sleep_source_until.is_empty() else -1.0
	_expect(state.is_sleeping(controller.elapsed_seconds) and is_equal_approx(refreshed_until, controller.elapsed_seconds + 15.0), "脑死亡再次回响刷新15秒休眠而非叠加来源")
	_free(controller)


func _test_light_blood_keyword() -> void:
	var owner := _owned_with_wounds(&"light_blood_owner", &"光血")
	var controller := _start([
		_entry(SquadData.from_owned_card(owner), &"player_front", 0, 60.0),
	], [_entry(SquadData.from_card(_card(&"light_blood_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)])
	var state := controller.player_states[0]
	_expect(
		state.has_targeting_keyword(&"dazzling")
		and controller.has_effective_dazzling(state)
		and controller._wound_registrations.size() == 1,
		"显现光血伤势赋予耀眼关键词并进入战场目标筛选"
	)
	var injury_id := StringName("%s:wound:0" % owner.instance_id)
	state.mask_injury(injury_id, 101)
	_expect(not state.has_targeting_keyword(&"dazzling") and not controller.has_effective_dazzling(state), "光血被遮蔽后立即失去耀眼")
	state.unmask_injury(injury_id, 101)
	_expect(state.has_targeting_keyword(&"dazzling") and controller.has_effective_dazzling(state), "光血解除遮蔽后恢复耀眼")
	_free(controller)


func _test_masked_wound_effects_and_paused_clock() -> void:
	var poison_owner := _owned_with_wounds(&"masked_poison", &"中毒Ⅱ")
	var controller := _start(
		[_entry(SquadData.from_owned_card(poison_owner), &"player_front", 0, 60.0)],
		[_entry(SquadData.from_card(_card(&"masked_poison_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)]
	)
	var state := controller.player_states[0]
	var injury_id := StringName("%s:wound:0" % poison_owner.instance_id)
	var initial_health := state.current_health
	controller.advance_time(0.75)
	state.mask_injury(injury_id, 101)
	controller.advance_time(5.0)
	_expect(is_equal_approx(state.current_health, initial_health), "中毒遮蔽期间不跳伤，剩余周期不偷偷流逝")
	state.mask_injury(injury_id, 202)
	state.unmask_injury(injury_id, 101)
	controller.advance_time(1.0)
	_expect(is_equal_approx(state.current_health, initial_health), "多重遮蔽在尚有来源时继续暂停中毒")
	state.unmask_injury(injury_id, 202)
	controller.advance_time(1.24)
	_expect(is_equal_approx(state.current_health, initial_health), "解除遮蔽后保留首次遮蔽时剩余的1.25秒")
	controller.advance_time(0.01)
	_expect(is_equal_approx(state.current_health, initial_health - 2.0), "剩余时间走完才恢复一次中毒跳伤")
	_free(controller)

	var fracture_owner := _owned_with_wounds(&"masked_fracture", &"骨折Ⅰ")
	var fracture_controller := _start(
		[_entry(SquadData.from_owned_card(fracture_owner), &"player_front", 0, 60.0)],
		[_entry(SquadData.from_card(_card(&"masked_fracture_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)]
	)
	var fracture_state := fracture_controller.player_states[0]
	var fracture_id := StringName("%s:wound:0" % fracture_owner.instance_id)
	_expect(is_equal_approx(fracture_state.modifiers.get_additive(BattleModifier.Stat.ARMOR_GAIN), -1.0), "骨折未遮蔽时减少获得护甲")
	fracture_state.mask_injury(fracture_id, 303)
	_expect(is_zero_approx(fracture_state.modifiers.get_additive(BattleModifier.Stat.ARMOR_GAIN)), "骨折遮蔽期间暂停已登记的护甲修正")
	fracture_state.unmask_injury(fracture_id, 303)
	_expect(is_equal_approx(fracture_state.modifiers.get_additive(BattleModifier.Stat.ARMOR_GAIN), -1.0), "骨折解除遮蔽后恢复护甲修正")
	_free(fracture_controller)


func _test_covered_emblem_clock_and_masked_fire_rune() -> void:
	var apple_card := _card(&"covered_apple_card", CardData.ActionType.MELEE)
	apple_card.emblem_slot_count = 1
	apple_card.wound_slot_count = 2
	var apple_owner := OwnedCard.new()
	apple_owner.initialize(apple_card, &"covered_apple_owner", 1001)
	apple_owner.slot_layout.assign([1, 0, -1, -1, 0, -1, -1, -1])
	apple_owner.set_emblem_slot(0, {"emblem_id": &"苹果", "instance_id": &"covered_apple_instance"})
	var blocker := _card(&"apple_blocker", CardData.ActionType.MELEE)
	var squad := SquadData.from_cards(_typed_cards([blocker, apple_card]))
	squad.bind_owned_card(apple_card, apple_owner)
	squad.layer_cards.assign([apple_card, blocker])
	var controller := _start(
		[_entry(squad, &"player_front", 0, 60.0)],
		[_entry(SquadData.from_card(_card(&"apple_clock_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)]
	)
	var state := controller.player_states[0]
	state.current_health -= 10.0
	var health_before := state.current_health
	controller.advance_time(1.0)
	state.squad_data.layer_cards.assign([blocker, apple_card])
	controller._get_next_event_delay()
	_expect(state.squad_data.get_visible_emblem_slot_indices(apple_card).is_empty(), "上层卡遮住苹果纹章后停用该实例")
	controller.advance_time(5.0)
	_expect(is_equal_approx(state.current_health, health_before), "苹果被遮挡时不治疗，剩余周期不流逝")
	state.squad_data.layer_cards.assign([apple_card, blocker])
	controller._get_next_event_delay()
	controller.advance_time(1.99)
	_expect(is_equal_approx(state.current_health, health_before), "苹果重现后保留遮挡前剩余的2秒")
	controller.advance_time(0.01)
	_expect(is_equal_approx(state.current_health, health_before + 1.0), "苹果剩余计时走完才恢复治疗")
	_free(controller)
	var cloak_owner := OwnedCard.new()
	cloak_owner.initialize(apple_card, &"covered_cloak_owner", 1003)
	cloak_owner.slot_layout.assign([1, 0, -1, -1, 0, -1, -1, -1])
	cloak_owner.set_emblem_slot(0, {"emblem_id": &"斗篷", "instance_id": &"covered_cloak_instance"})
	var cloak_squad := SquadData.from_cards(_typed_cards([blocker, apple_card]))
	cloak_squad.bind_owned_card(apple_card, cloak_owner)
	cloak_squad.layer_cards.assign([apple_card, blocker])
	var cloak_controller := _start(
		[_entry(cloak_squad, &"player_front", 0, 60.0)],
		[_entry(SquadData.from_card(_card(&"cloak_clock_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)]
	)
	var cloak_state := cloak_controller.player_states[0]
	cloak_controller.advance_time(1.0)
	cloak_state.squad_data.layer_cards.assign([blocker, apple_card])
	cloak_controller._get_next_event_delay()
	_expect(not cloak_state.has_runtime_keyword(&"emblem_shadow"), "斗篷纹章被遮挡后立即停用影蔽")
	cloak_controller.advance_time(5.0)
	cloak_state.squad_data.layer_cards.assign([apple_card, blocker])
	cloak_controller._get_next_event_delay()
	cloak_controller.advance_time(13.9)
	_expect(cloak_state.has_runtime_keyword(&"emblem_shadow"), "斗篷重现后保留遮挡前剩余的14秒影蔽")
	cloak_controller.advance_time(0.1)
	_expect(not cloak_state.has_runtime_keyword(&"emblem_shadow"), "斗篷的有效15秒走完后影蔽到期")
	_free(cloak_controller)

	var fire_card := _card(&"masked_fire_rune", CardData.ActionType.MELEE)
	fire_card.runes.assign([CardData.ElementType.WOOD])
	var fire_owner := OwnedCard.new()
	fire_owner.initialize(fire_card, &"masked_fire_sticker_owner", 1002)
	fire_owner.set_rune_sticker(0, {"instance_id": &"masked_fire_sticker", "emblem_id": &"火贴纸", "element": CardData.ElementType.FIRE})
	var fire_controller := _start(
		[_entry(SquadData.from_owned_card(fire_owner), &"player_front", 0, 60.0)],
		[_entry(SquadData.from_card(_card(&"fire_mask_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)]
	)
	var fire_state := fire_controller.player_states[0]
	_expect(is_equal_approx(fire_state.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT), 2.0), "火贴纸覆盖木符文后提供一次未消耗强化")
	fire_state.mask_rune_slot(fire_card, 0)
	_expect(is_zero_approx(fire_state.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)), "符文贴纸所在槽遮蔽期间暂时停用火强化")
	fire_state.unmask_rune_slot(fire_card, 0)
	_expect(is_equal_approx(fire_state.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT), 2.0), "火符文解除遮蔽后恢复尚未消耗的强化")
	_free(fire_controller)


func _test_wound_action_windows() -> void:
	var concussion_owner := _owned_with_wounds(&"concussion_action", &"脑震荡")
	var concussion_controller := _start(
		[_entry(SquadData.from_owned_card(concussion_owner), &"player_front", 0, 0.5)],
		[_entry(SquadData.from_card(_card(&"concussion_target", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)]
	)
	var concussion_formula: Array[BattleFormulaData] = []
	concussion_controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.is_base_action and event.source.side == BattleSquadState.Side.PLAYER:
			concussion_formula.append(event.formula)
	)
	concussion_controller.advance_time(concussion_controller.player_states[0].remaining_cooldown)
	_expect(
		concussion_formula.size() == 1
		and concussion_formula[0].immediate_action_source.get("source_kind") == "wound_action_roll"
		and int(concussion_formula[0].immediate_action_source.get("amount", 0)) >= 1
		and int(concussion_formula[0].immediate_action_source.get("amount", 0)) <= 10,
		"脑震荡每次实际普通行动掷一次1至10并把结果写入该行动公式快照"
	)
	_free(concussion_controller)

	var blind_owner := _owned_with_wounds(&"blind_action", &"致盲Ⅰ")
	var blind_controller := _start(
		[_entry(SquadData.from_owned_card(blind_owner), &"player_front", 0, 0.5)],
		[_entry(SquadData.from_card(_card(&"blind_target", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)]
	)
	var failing_seed := _seed_for_d8_roll(1, 2)
	blind_controller._random.seed = failing_seed
	var blind_action_count := [0]
	blind_controller.action_resolved.connect(func(actor: BattleSquadState, _target: BattleSquadState, _type: CardData.ActionType, _amount: int) -> void:
		if actor.side == BattleSquadState.Side.PLAYER:
			blind_action_count[0] += 1
	)
	var existing_reinforcement := BattleModifier.new()
	existing_reinforcement.stat = BattleModifier.Stat.REINFORCEMENT
	existing_reinforcement.mode = BattleModifier.Mode.ADD
	existing_reinforcement.value = 4.0
	blind_controller.player_states[0].modifiers.add_modifier(existing_reinforcement)
	blind_controller.advance_time(0.5)
	_expect(
		blind_action_count[0] == 0
		and is_equal_approx(blind_controller.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT), 4.0)
		and is_equal_approx(blind_controller.player_states[0].remaining_cooldown, blind_controller.player_states[0].get_action_interval()),
		"致盲失败跳过行动、冷却重置且不消耗已有强化"
	)
	_free(blind_controller)

	var wound_owner := _owned_with_wounds(&"inner_wound_action", &"内伤Ⅲ")
	var internal_controller := _start(
		[_entry(SquadData.from_owned_card(wound_owner), &"player_front", 0, 0.5)],
		[_entry(SquadData.from_card(_card(&"inner_target", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)]
	)
	var internal_action_count := [0]
	internal_controller.action_resolved.connect(func(actor: BattleSquadState, _target: BattleSquadState, _type: CardData.ActionType, _amount: int) -> void:
		if actor.side == BattleSquadState.Side.PLAYER:
			internal_action_count[0] += 1
	)
	internal_controller.advance_time(0.5)
	var internal_state := internal_controller.player_states[0]
	var remaining := internal_state.remaining_cooldown
	internal_controller.advance_time(remaining)
	_expect(internal_action_count[0] == 1 and not internal_state.skip_next_ordinary_action, "内伤Ⅲ执行一次普通行动后，下一行动窗口跳过并消费标记")
	_free(internal_controller)

	var confused_owner := _owned_with_wounds(&"confused_action", &"混乱")
	var confused_controller := _start([
		_entry(SquadData.from_owned_card(confused_owner), &"player_front", 0, 0.5),
		_entry(SquadData.from_card(_card(&"confused_ally", CardData.ActionType.MELEE)), &"player_front", 1, 60.0),
	], [
		_entry(SquadData.from_card(_card(&"confused_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0),
	])
	var coin_seed := _seed_for_coin_result(0)
	confused_controller._random.seed = coin_seed
	var confused_targets: Array[BattleSquadState] = []
	confused_controller.action_resolved.connect(func(actor: BattleSquadState, target: BattleSquadState, _type: CardData.ActionType, _amount: int) -> void:
		if actor.side == BattleSquadState.Side.PLAYER:
			confused_targets.append(target)
	)
	confused_controller.advance_time(0.5)
	_expect(
		confused_targets.size() == 1
		and confused_targets[0] in confused_controller.get_all_states(),
		"混乱反面把包括自身在内的敌我存活单位放进主目标随机池"
	)
	_free(confused_controller)

	var healer_card := _card(&"inner_healer", CardData.ActionType.HEAL)
	var healer_owner := OwnedCard.new()
	healer_card.wound_slot_count = 1
	healer_owner.initialize(healer_card, &"inner_healer_owned", 600)
	healer_owner.set_wound_slot(0, {"wound_id": &"内伤Ⅲ", "level": 1})
	var ally_card := _card(&"wounded_ally", CardData.ActionType.MELEE)
	var healing_controller := _start([
		_entry(SquadData.from_owned_card(healer_owner), &"player_front", 0, 0.5),
		_entry(SquadData.from_card(ally_card), &"player_front", 1, 60.0),
	], [
		_entry(SquadData.from_card(_card(&"healing_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0),
	])
	var ally_state := healing_controller.player_states[1]
	ally_state.current_health = 10.0
	var healing_amounts: Array[int] = []
	healing_controller.action_resolved.connect(func(actor: BattleSquadState, target: BattleSquadState, action_type: CardData.ActionType, amount: int) -> void:
		if actor.side == BattleSquadState.Side.PLAYER and action_type == CardData.ActionType.HEAL:
			healing_amounts.append(amount)
	)
	healing_controller.advance_time(0.5)
	_expect(healing_amounts == [3], "内伤Ⅲ的行动值-2与治疗+3仅在治疗主目标公式中合并")
	_free(healing_controller)


func _test_poison_damage_windows() -> void:
	var action_owner := _owned_with_wounds(&"poison_action", &"中毒Ⅰ")
	var armored_target := _card(&"poison_action_target", CardData.ActionType.MELEE)
	armored_target.armor = 20
	var action_controller := _start(
		[_entry(SquadData.from_owned_card(action_owner), &"player_front", 0, 0.5)],
		[_entry(SquadData.from_card(armored_target), &"enemy_front", 0, 60.0)]
	)
	var action_target := action_controller.enemy_states[0]
	var action_hp_before := action_target.current_health
	action_controller.advance_time(0.5)
	_expect(
		is_equal_approx(action_target.current_health, action_hp_before - 2.0)
		and action_target.current_armor < 20.0,
		"中毒Ⅰ行动附加的2点生命伤害先作用于生命且绕过护甲"
	)
	_free(action_controller)
	var support_owner := _owned_with_wounds(&"poison_support_action", &"中毒Ⅰ")
	support_owner.card_data.action_type = CardData.ActionType.DEFENSE
	var support_controller := _start(
		[_entry(SquadData.from_owned_card(support_owner), &"player_front", 0, 0.5)],
		[_entry(SquadData.from_card(_card(&"poison_support_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)]
	)
	var support_target := support_controller.player_states[0]
	var support_health_before := support_target.current_health
	var support_events: Array[BattleEffectEvent] = []
	support_controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.visual_kind == &"wound_poison_action": support_events.append(event)
	)
	support_controller.advance_time(0.5)
	_expect(
		support_events.size() == 1
		and support_events[0].target == support_target
		and is_equal_approx(support_target.current_health, support_health_before - 2.0),
		"中毒附伤作用于护甲行动主目标，伤害忽略护甲"
	)
	_free(support_controller)
	var heal_poison_owner := _owned_with_wounds(&"poison_heal_action", &"中毒Ⅱ")
	heal_poison_owner.card_data.action_type = CardData.ActionType.HEAL
	var injured_ally := SquadData.from_card(_card(&"poison_heal_target", CardData.ActionType.MELEE))
	var heal_controller := _start(
		[_entry(SquadData.from_owned_card(heal_poison_owner), &"player_front", 0, 0.5), _entry(injured_ally, &"player_front", 1, 60.0)],
		[_entry(SquadData.from_card(_card(&"poison_heal_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)]
	)
	heal_controller.player_states[1].current_health -= 10.0
	var poison_events: Array[BattleEffectEvent] = []
	heal_controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.visual_kind == &"wound_poison_action": poison_events.append(event)
	)
	heal_controller.advance_time(0.5)
	_expect(poison_events.size() == 1 and poison_events[0].target == heal_controller.player_states[1] and is_equal_approx(poison_events[0].health_amount, 3.0), "中毒附伤作用于治疗行动主目标且不把治疗副效果当成另一目标")
	_free(heal_controller)

	var periodic_owner := _owned_with_wounds(&"poison_periodic", &"中毒Ⅱ")
	var periodic_controller := _start(
		[_entry(SquadData.from_card(_card(&"periodic_enemy", CardData.ActionType.MELEE)), &"player_front", 0, 60.0)],
		[_entry(SquadData.from_owned_card(periodic_owner), &"enemy_front", 0, 60.0)]
	)
	var periodic_state := periodic_controller.enemy_states[0]
	var health_before := periodic_state.current_health
	var armor_before := periodic_state.current_armor
	periodic_controller.advance_time(2.0)
	_expect(
		is_equal_approx(periodic_state.current_health, health_before - 2.0)
		and is_equal_approx(periodic_state.current_armor, armor_before),
		"中毒Ⅱ每2秒造成2点直失生命且不消耗护甲"
	)
	_free(periodic_controller)


func _test_probability_wound_rolls() -> void:
	var owner := _owned_with_wounds(&"misfortune_two_dice", &"厄运缠身")
	owner.card_data.wound_slot_count = 2
	owner.wound_slots = OwnedCard._empty_slot_array(2)
	owner.set_wound_slot(0, {"wound_id": &"厄运缠身", "level": 1})
	var controller := _start([_entry(SquadData.from_owned_card(owner), &"player_front", 0, 60.0)], [])
	var state := controller.player_states[0]
	var injury_instance_id := StringName("%s:wound:0" % owner.instance_id)
	var counter_key := StringName("misfortune:%s" % injury_instance_id)
	owner.wound_battle_counters[counter_key] = 2
	controller._random.seed = _seed_for_adopted_dice(8, 2, 2, 0, [1, 1])
	var two_ones := controller._roll_probability(state, 8, 2)
	_expect(
		(two_ones.get("faces", []) as Array) == [1, 1]
		and controller.run_reward_ledger.get_total(BattleRunRewardLedger.KIND_GOLD, BattleSquadState.Side.PLAYER) == 30
		and int(owner.wound_battle_counters.get(counter_key, -1)) == 1,
		"原计数2加本次两个1奖励30金币并保留余数1"
	)
	_free(controller)

	var mixed_owner := _owned_with_wounds(&"misfortune_mixed_dice", &"厄运缠身")
	mixed_owner.card_data.wound_slot_count = 2
	mixed_owner.wound_slots = OwnedCard._empty_slot_array(2)
	mixed_owner.set_wound_slot(0, {"wound_id": &"厄运缠身", "level": 1})
	var mixed_controller := _start([_entry(SquadData.from_owned_card(mixed_owner), &"player_front", 0, 60.0)], [])
	var mixed_state := mixed_controller.player_states[0]
	var mixed_key := StringName("misfortune:%s:wound:0" % mixed_owner.instance_id)
	mixed_owner.wound_battle_counters[mixed_key] = 2
	mixed_controller._random.seed = _seed_for_adopted_dice(8, 2, 2, -1, [1, 2])
	var mixed_roll := mixed_controller._roll_probability(mixed_state, 8, 2)
	_expect(
		(mixed_roll.get("faces", []) as Array) == [1, 2]
		and mixed_controller.run_reward_ledger.get_total(BattleRunRewardLedger.KIND_GOLD, BattleSquadState.Side.PLAYER) == 30
		and int(mixed_owner.wound_battle_counters.get(mixed_key, -1)) == 0,
		"原计数2加[1,非1]仍奖励30金币并清为0"
	)
	_free(mixed_controller)

	var lucky_owner := _owned_with_emblems(&"two_luck_emblems", [&"天选之子", &"天选之子"])
	var lucky_controller := _start([_entry(SquadData.from_owned_card(lucky_owner), &"player_front", 0, 60.0)], [])
	var lucky_result := lucky_controller._roll_probability(lucky_controller.player_states[0], 10, 1)
	var unlucky_owner := _owned_with_wounds(&"two_misfortune_wounds", &"厄运缠身")
	unlucky_owner.card_data.wound_slot_count = 2
	unlucky_owner.wound_slots = OwnedCard._empty_slot_array(2)
	unlucky_owner.set_wound_slot(0, {"wound_id": &"厄运缠身", "level": 1})
	unlucky_owner.set_wound_slot(1, {"wound_id": &"厄运缠身", "level": 1})
	_free(lucky_controller)
	var unlucky_controller := _start([_entry(SquadData.from_owned_card(unlucky_owner), &"player_front", 0, 60.0)], [])
	var unlucky_result := unlucky_controller._roll_probability(unlucky_controller.player_states[0], 10, 1)
	_expect(
		(lucky_result.get("candidate_sets", []) as Array).size() == 3
		and (unlucky_result.get("candidate_sets", []) as Array).size() == 3
		and int(unlucky_result.get("total", 0)) <= int(unlucky_result.candidate_sets[0][0]),
		"两个天选之子投3次取高，两个厄运投3次取低"
	)
	_free(unlucky_controller)


func _seed_for_adopted_dice(sides: int, dice_count: int, candidate_count: int, direction: int, expected: Array[int]) -> int:
	for seed_value: int in range(1, 100000):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		var sets: Array[Array] = []
		var totals: Array[int] = []
		for _candidate: int in candidate_count:
			var faces: Array[int] = []
			var total := 0
			for _die: int in dice_count:
				var face := probe.randi_range(1, sides)
				faces.append(face)
				total += face
			sets.append(faces)
			totals.append(total)
		var selected := 0
		for index: int in range(1, totals.size()):
			if direction > 0 and totals[index] > totals[selected]: selected = index
			elif direction < 0 and totals[index] < totals[selected]: selected = index
		if sets[selected] == expected:
			return seed_value
	return 1


func _test_magic_mark_and_greed() -> void:
	var magic_owner := _owned_with_wounds(&"magic_mark_three", &"魔痕Ⅲ")
	magic_owner.card_data.armor = 5
	var magic_controller := _start(
		[_entry(SquadData.from_owned_card(magic_owner), &"player_front", 0, 60.0)],
		[_entry(SquadData.from_card(_card(&"spell_event_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)]
	)
	var magic_state := magic_controller.player_states[0]
	var health_before := magic_state.current_health
	var logged_rolls: Array[Dictionary] = []
	magic_controller.special_effect_resolved.connect(func(record: Dictionary) -> void:
		if record.get("kind") == "roll": logged_rolls.append(record.duplicate(true))
	)
	for activation_index: int in 5:
		_expect(magic_controller.notify_spell_triggered(&"test_spell_instance", activation_index), "每次唯一法术释放事件应触发启咒 #%d" % (activation_index + 1))
	_expect(
		is_zero_approx(magic_state.current_armor)
		and is_equal_approx(magic_state.current_health, health_before - 10.0)
		and is_equal_approx(magic_state.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT), 15.0)
		and magic_state.is_sleeping(magic_controller.elapsed_seconds),
		"魔痕Ⅲ每张法术先受3点护甲优先伤害再强化+3，五次后本小队眩晕3秒"
	)
	var health_after_duplicate := magic_state.current_health
	_expect(not magic_controller.notify_spell_triggered(&"test_spell_instance", 4) and is_equal_approx(magic_state.current_health, health_after_duplicate), "重复收到同一法术释放事件不会重复启咒")
	_free(magic_controller)

	var greed_owner := _owned_with_wounds(&"greed_holder", &"贪婪")
	greed_owner.card_data.base_value = 3
	var greed_controller := _start(
		[_entry(SquadData.from_owned_card(greed_owner), &"player_front", 0, 60.0), _entry(SquadData.from_card(_card(&"gold_source_ally", CardData.ActionType.MELEE)), &"player_front", 1, 60.0)],
		[_entry(SquadData.from_card(_card(&"greed_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)]
	)
	var greed_state := greed_controller.player_states[0]
	var reward_source := BattleEffectOwnerRef.for_state(greed_controller.player_states[1], BattleEffectDefinition.OwnerKind.OWNING_PLAYER)
	var unlocked_action_value := greed_state.get_action_value_without_reinforcement()
	var first_reward := greed_controller.record_pending_run_reward(reward_source, BattleRunRewardLedger.KIND_GOLD, 1, &"test_gold_event_1", 2, 100)
	var second_reward := greed_controller.record_pending_run_reward(reward_source, BattleRunRewardLedger.KIND_GOLD, 12, &"test_gold_event_2", 2, 200)
	_expect(
		first_reward and second_reward
		and greed_state.get_display_action_value() == 1 + (unlocked_action_value + 5) * 2
		and is_equal_approx(greed_state.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT), float((unlocked_action_value + 5) * 2)),
		"贪婪把基础行动值锁1并在每次金币入账（不看金额）给每名持有队伍原值+5强化"
	)
	var entries_before_read := greed_state.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)
	greed_controller.run_reward_ledger.get_entries()
	_expect(is_equal_approx(greed_state.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT), entries_before_read), "读取金币账本不重复触发贪婪")
	_free(greed_controller)


func _test_fracture_battle_growth() -> void:
	var fracture_owner := _owned_with_wounds(&"fracture_growth", &"骨折Ⅰ")
	var squad := SquadData.from_owned_card(fracture_owner)
	var controller := _start([_entry(squad, &"player_front", 0, 60.0)], [])
	_expect(
		is_equal_approx(controller.player_states[0].modifiers.get_additive(BattleModifier.Stat.ARMOR_GAIN), -1.0)
		and int(fracture_owner.wound_battle_counters.values().front()) == 1
		and is_zero_approx(fracture_owner.get_permanent_growth(OwnedCard.STAT_BASE_ARMOR)),
		"骨折Ⅰ降低获得护甲且参战后跨战计数一次"
	)
	_free(controller)
	var second_battle := _start([_entry(squad, &"player_front", 0, 60.0)], [])
	_free(second_battle)
	var third_battle := _start([_entry(squad, &"player_front", 0, 60.0)], [])
	_expect(
		is_equal_approx(fracture_owner.get_permanent_growth(OwnedCard.STAT_BASE_ARMOR), 1.0)
		and int(fracture_owner.wound_battle_counters.values().front()) == 0,
		"骨折Ⅰ每参战三场永久增加基础护甲+1并清除已完成计数"
	)
	_free(third_battle)


func _test_tear_echo_armor_order() -> void:
	var tear_owner := _owned_with_wounds(&"tear_echo", &"撕裂Ⅲ")
	tear_owner.card_data.armor = 3
	var controller := _start(
		[_entry(SquadData.from_owned_card(tear_owner), &"player_front", 0, 0.5)],
		[_entry(SquadData.from_card(_card(&"tear_target", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)]
	)
	var state := controller.player_states[0]
	var health_before := state.current_health
	controller.advance_time(0.5)
	_expect(is_zero_approx(state.current_armor) and is_equal_approx(state.current_health, health_before - 1.0), "撕裂Ⅲ回响自伤先扣除3点护甲，再对生命造成余下1点伤害")
	_free(controller)


func _test_corpse_poison_and_temporary_restore() -> void:
	var corpse_owner := _owned_with_wounds(&"corpse_poison_one", &"尸毒Ⅰ")
	var left_owner := _empty_wound_owner(&"corpse_left_ally")
	var right_owner := _empty_wound_owner(&"corpse_right_ally")
	var controller := _start([
		_entry(SquadData.from_owned_card(left_owner), &"player_front", 0, 60.0),
		_entry(SquadData.from_owned_card(corpse_owner), &"player_front", 1, 60.0),
		_entry(SquadData.from_owned_card(right_owner), &"player_front", 2, 60.0),
	], [
		_entry(SquadData.from_card(_card(&"corpse_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0),
	])
	_expect(controller.player_states[1].get_max_health() == 33, "尸毒Ⅰ显现后令小队最大生命+3")
	controller.player_states[1].current_health = 0.0
	controller._finalize_batch()
	_expect(
		left_owner.wound_slots[0].get("wound_id") == &"中毒Ⅰ"
		and right_owner.wound_slots[0].get("wound_id") == &"中毒Ⅰ"
		and bool(left_owner.wound_slots[0].get("temporary", false)),
		"尸毒Ⅰ阵亡遗愿为左右相邻小队临时添加中毒Ⅰ"
	)
	controller.enemy_states[0].current_health = 0.0
	controller._finalize_batch()
	controller._check_battle_result()
	_expect(left_owner.wound_slots[0].is_empty() and right_owner.wound_slots[0].is_empty(), "战斗结束撤销临时新增中毒槽")
	_free(controller)

	var corpse_two := _owned_with_wounds(&"corpse_poison_two", &"尸毒Ⅱ")
	var poisoned_ally := _owned_with_wounds(&"permanent_poison_ally", &"中毒Ⅰ")
	poisoned_ally.card_data.armor = 5
	var upgrade_controller := _start([
		_entry(SquadData.from_owned_card(corpse_two), &"player_front", 0, 60.0),
		_entry(SquadData.from_owned_card(poisoned_ally), &"player_front", 1, 60.0),
	], [
		_entry(SquadData.from_card(_card(&"corpse_two_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0),
	])
	var ally_state := upgrade_controller.player_states[1]
	var ally_health_before := ally_state.current_health
	upgrade_controller.player_states[0].current_health = 0.0
	upgrade_controller._finalize_batch()
	_expect(
		is_equal_approx(ally_state.current_health, ally_health_before - 5.0)
		and is_zero_approx(ally_state.current_armor)
		and poisoned_ally.wound_slots[0].get("wound_id") == &"中毒Ⅱ"
		and bool(poisoned_ally.wound_slots[0].get("temporary", false)),
		"尸毒Ⅱ遗愿先造成10点护甲优先伤害，再临时把既有中毒Ⅰ升级到Ⅱ"
	)
	upgrade_controller.enemy_states[0].current_health = 0.0
	upgrade_controller._finalize_batch()
	upgrade_controller._check_battle_result()
	_expect(poisoned_ally.wound_slots[0].get("wound_id") == &"中毒Ⅰ", "战后只撤销临时升级并恢复原有永久中毒Ⅰ")
	_free(upgrade_controller)


func _test_crystallization_conversion() -> void:
	var owner := _owned_with_wounds(&"crystallization_owner", &"晶体化")
	owner.card_data.armor = 2
	owner.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 2.0)
	var squad := SquadData.from_owned_card(owner)
	_expect(squad.get_effective_max_health() == 30 and squad.get_effective_base_armor() == 4, "晶体化把正向永久额外生命转为护甲且不增加最大生命")
	var controller := _start([_entry(squad, &"player_front", 0, 60.0)], [])
	var state := controller.player_states[0]
	state.current_armor = 0.0
	_expect(
		is_equal_approx(state.current_armor, 1.0)
		and state.get_max_health() == 29
		and owner.crystallization_health_loss == 0
		and controller.permanent_growth_ledger.get_entries().size() == 2
		and controller.permanent_growth_ledger.get_entries()[0].get("stat") == BattlePermanentGrowthLedger.STAT_CRYSTALLIZATION_HEALTH_LOSS,
		"護甲首次歸零時戰鬥內生命-1並護甲+1，永久變更只記入戰後賬本"
	)
	state.current_armor = 0.0
	_expect(controller.permanent_growth_ledger.get_entries().size() == 4 and state.get_max_health() == 28, "重新获得的护甲再次归零可触发晶体化")
	state.current_armor = 1.0
	state.current_armor = 0.0
	_expect(controller.permanent_growth_ledger.get_entries().size() == 6 and state.get_max_health() == 27, "再次获得护甲后第三次归零继续转换")
	_free(controller)

	var zero_armor_owner := _owned_with_wounds(&"crystallization_zero_armor", &"晶体化")
	var zero_armor_controller := _start([_entry(SquadData.from_owned_card(zero_armor_owner), &"player_front", 0, 60.0)], [])
	zero_armor_controller.player_states[0].apply_damage_exact(1.0)
	_expect(zero_armor_controller.permanent_growth_ledger.get_entries().is_empty(), "开战时护甲已为0后承受伤害不会触发晶体化")
	_free(zero_armor_controller)

	var floor_owner := _owned_with_wounds(&"crystallization_floor", &"晶体化")
	floor_owner.card_data.max_health = 2
	var floor_controller := _start([_entry(SquadData.from_owned_card(floor_owner), &"player_front", 0, 60.0)], [])
	var floor_state := floor_controller.player_states[0]
	floor_state.current_armor = 0.0
	floor_state.current_armor = 1.0
	floor_state.current_armor = 0.0
	_expect(floor_controller.permanent_growth_ledger.get_entries().size() == 2 and floor_state.get_max_health() == 1, "晶体化生命降至1后停止永久护甲循环")
	_free(floor_controller)


func _empty_wound_owner(card_id: StringName) -> OwnedCard:
	serial += 1
	var card := _card(card_id, CardData.ActionType.MELEE)
	card.wound_slot_count = 1
	var owned := OwnedCard.new()
	owned.initialize(card, StringName("%s_owned_%d" % [card_id, serial]), serial)
	return owned


func _seed_for_d8_roll(low: int, high: int) -> int:
	for seed_value: int in range(1, 1001):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		var roll := probe.randi_range(1, 8)
		if roll >= low and roll <= high:
			return seed_value
	return 1


func _seed_for_coin_result(expected_result: int) -> int:
	for seed_value: int in range(1, 1001):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		if probe.randi_range(0, 1) == expected_result:
			return seed_value
	return 1


func _test_sandwich_neighbors_and_instance_stacking() -> void:
	var source := _owned_with_emblems(&"sandwich_owner", [&"三明治", &"三明治"])
	var controller := _start([
		_entry(SquadData.from_card(_card(&"left_neighbor", CardData.ActionType.MELEE)), &"player_front", 0, 10.0),
		_entry(SquadData.from_owned_card(source), &"player_front", 1, 10.0),
		_entry(SquadData.from_card(_card(&"right_neighbor", CardData.ActionType.MELEE)), &"player_front", 2, 10.0),
		_entry(SquadData.from_card(_card(&"other_row", CardData.ActionType.MELEE)), &"player_back", 1, 10.0),
	], [_entry(SquadData.from_card(_card(&"sandwich_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)])
	_expect(is_zero_approx(controller.player_states[1].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)), "三明治不会把强化给纹章自身")
	_expect(controller.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 10.0 and controller.player_states[2].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 10.0, "两枚三明治按同排邻接规则分别给左右友军强化+10")
	_expect(is_zero_approx(controller.player_states[3].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)), "不同排同索引单位不是相邻友军")
	_expect(is_equal_approx(controller.player_states[0].remaining_cooldown, 9.0) and is_equal_approx(controller.player_states[2].remaining_cooldown, 9.0), "三明治两实例各为左右邻军充能0.5秒")
	_free(controller)


func _test_periodic_healing_and_anvil_armor() -> void:
	var owner := _owned_with_emblems(&"fruit_owner", [&"苹果", &"苹果派", &"烤苹果", &"金苹果"])
	var fruit_squad := SquadData.from_owned_card(owner)
	var controller := _start([
		_entry(fruit_squad, &"player_front", 0, 60.0),
		_entry(SquadData.from_card(ANVIL), &"player_front", 1, 60.0),
	], [_entry(SquadData.from_card(_card(&"fruit_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)])
	var periodic_events: Array[BattleEffectEvent] = []
	controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.is_continuous:
			periodic_events.append(event)
	)
	var state := controller.player_states[0]
	state.current_health -= 8.0
	controller.advance_time(2.0)
	var heal_event := periodic_events.filter(func(event: BattleEffectEvent) -> bool:
		return event.effect_kind == BattleEffectEvent.EffectKind.HEALING
	).front() as BattleEffectEvent if periodic_events.any(func(event: BattleEffectEvent) -> bool:
		return event.effect_kind == BattleEffectEvent.EffectKind.HEALING
	) else null
	var heal_popup := BattleFormulaPresenter.format_popup(heal_event.formula, heal_event) if heal_event != null else ""
	_expect(
		is_equal_approx(state.current_health, float(state.get_max_health()) - 7.0)
		and heal_event != null
		and is_equal_approx(heal_event.effective_amount, 1.0)
		and heal_popup.contains("苹果派")
		and heal_popup.contains("实际生效 1 点治疗")
		and not heal_popup.contains("周期治疗"),
		"苹果派第2秒只治疗1点，简洁公式保留数值来源并省略重复触发标签"
	)
	controller.advance_time(1.0)
	_expect(is_equal_approx(state.battle_healing_done, 4.0), "苹果、烤苹果、苹果派各自按实例周期累计实际治疗")
	_expect(is_equal_approx(state.current_armor, 4.0) and is_equal_approx(state.battle_armor_granted, 4.0), "金苹果周期护甲作为正式护甲获得事件经过铁砧翻倍")
	_expect(controller._emblem_registrations.size() == 4 and controller._emblem_registrations[3].get("owner") == owner and controller._emblem_registrations[3].get("instance_id") == owner.emblem_slots[3].get("instance_id"), "周期事件注册记录保留纹章实例及OwnedCard归属")
	_free(controller)

	var death_owner := _owned_with_emblems(&"death_fruit", [&"苹果"])
	var deadly_enemy := _card(&"period_killer", CardData.ActionType.MELEE)
	deadly_enemy.base_value = 100
	var death_controller := _start([
		_entry(SquadData.from_owned_card(death_owner), &"player_front", 0, 60.0),
		_entry(SquadData.from_card(_card(&"period_live_ally", CardData.ActionType.MELEE)), &"player_front", 1, 60.0),
	], [_entry(SquadData.from_card(deadly_enemy), &"enemy_front", 0, 0.5)])
	var fruit_state := death_controller.player_states[0]
	var ally_priority := BattleModifier.new()
	ally_priority.stat = BattleModifier.Stat.TARGET_PRIORITY
	ally_priority.value = -100.0
	death_controller.player_states[1].modifiers.add_modifier(ally_priority)
	death_controller.advance_time(0.5)
	var died: bool = fruit_state.current_health <= 0.0
	var revived: bool = death_controller.revive_state_at_original_position(fruit_state, 20.0)
	death_controller.advance_time(3.0)
	_expect(died and revived and is_zero_approx(fruit_state.battle_healing_done), "周期拥有者实际阵亡后停止计时，复活不会恢复本场苹果周期")
	_free(death_controller)

	var burned_apple_card := _card(&"burned_apple", CardData.ActionType.MELEE)
	burned_apple_card.emblem_slot_count = 1
	burned_apple_card.wound_slot_count = 1
	var burned_apple_owner := OwnedCard.new()
	burned_apple_owner.initialize(burned_apple_card, &"burned_apple_owned", 700)
	burned_apple_owner.set_emblem_slot(0, {"emblem_id": &"苹果", "instance_id": &"burned_apple_emblem"})
	burned_apple_owner.set_wound_slot(0, {"wound_id": &"烧伤Ⅰ", "level": 1})
	var burned_controller := _start([
		_entry(SquadData.from_owned_card(burned_apple_owner), &"player_front", 0, 60.0),
	], [_entry(SquadData.from_card(_card(&"burned_apple_enemy", CardData.ActionType.MELEE)), &"enemy_front", 0, 60.0)])
	var burned_state := burned_controller.player_states[0]
	burned_state.current_health -= 5.0
	var burned_heal_amount := [0.0]
	var burned_zeal := burned_state.get_zeal_layers()
	burned_controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.is_continuous and event.effect_kind == BattleEffectEvent.EffectKind.HEALING:
			burned_heal_amount[0] = event.effective_amount
	)
	burned_controller.advance_time(3.0)
	_expect(burned_zeal == 1 and is_equal_approx(burned_heal_amount[0], 2.0), "烧伤Ⅰ热诚+1，并使拥有者的持续治疗只增加1点")
	_free(burned_controller)


func _owned_with_emblems(card_id: StringName, emblem_ids: Array[StringName]) -> OwnedCard:
	serial += 1
	var card := _card(card_id, CardData.ActionType.MELEE)
	card.emblem_slot_count = emblem_ids.size()
	var owned := OwnedCard.new()
	owned.initialize(card, StringName("%s_owned_%d" % [card_id, serial]), serial)
	for index: int in emblem_ids.size():
		owned.set_emblem_slot(index, {"emblem_id": emblem_ids[index], "instance_id": StringName("%s_emblem_%d" % [card_id, index])})
	return owned


func _owned_with_wounds(card_id: StringName, wound_id: StringName) -> OwnedCard:
	serial += 1
	var card := _card(card_id, CardData.ActionType.MELEE)
	card.wound_slot_count = 1
	var owned := OwnedCard.new()
	owned.initialize(card, StringName("%s_owned_%d" % [card_id, serial]), serial)
	owned.set_wound_slot(0, {"wound_id": wound_id, "level": 1})
	return owned


func _card(card_id: StringName, action_type: CardData.ActionType) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = String(card_id)
	card.action_type = action_type
	card.base_value = 2
	card.max_health = 30
	card.cooldown_seconds = 9.0
	return card


func _entry(squad: SquadData, row: StringName, index: int, cooldown: float) -> Dictionary:
	return {"squad_data": squad, "row_key": row, "formation_index": index, "base_cooldown_override": cooldown}


func _typed_cards(cards: Array) -> Array[CardData]:
	var result: Array[CardData] = []
	for card: CardData in cards:
		result.append(card)
	return result


func _start(players: Array[Dictionary], enemies: Array[Dictionary]) -> BattleController:
	var controller := BattleController.new()
	root.add_child(controller)
	controller.start_battle(players, enemies, 7101, false)
	return controller


func _free(controller: BattleController) -> void:
	controller.clear_battle()
	controller.free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
