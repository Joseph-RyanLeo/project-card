extends SceneTree

const BattleController = preload("res://scripts/battle/battle_controller.gd")
const BattleEffectEvent = preload("res://scripts/battle/battle_effect_event.gd")
const BattleResourceState = preload("res://scripts/battle/battle_resource_state.gd")
const BattleSquadState = preload("res://scripts/battle/battle_squad_state.gd")
const BattlePermanentGrowthLedger = preload("res://scripts/battle/battle_permanent_growth_ledger.gd")
const BattleRunRewardLedger = preload("res://scripts/battle/battle_run_reward_ledger.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const EmblemLibraryData = preload("res://scripts/data/emblem_library_data.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var player_card := CardData.new()
	player_card.id = &"resource_test_unit"
	player_card.display_name = "测试单位"
	player_card.card_type = CardData.CardType.MINION
	player_card.max_health = 12
	player_card.base_value = 1
	player_card.cooldown_seconds = 9.9
	var player_owned := OwnedCard.new()
	player_owned.initialize(player_card, &"resource_test_player", 0)
	var player_squad := SquadData.from_owned_card(player_owned)
	var player_formation: Array[Dictionary] = [{"squad_data": player_squad, "row_key": &"player_front", "formation_index": 0}]
	var enemy_formation: Array[Dictionary] = []
	var resource_data := load("res://resources/cards/fire_element_shard.tres") as CardData
	var resource_owned := OwnedCard.new()
	resource_owned.initialize(resource_data, &"resource_test_fire", 1)
	var resources: Array[OwnedCard] = [resource_owned]
	var catalog: Array[CardData] = [resource_data]
	var controller := BattleController.new()
	root.add_child(controller)
	controller.start_battle(player_formation, enemy_formation, 1234, false, &"resource_test_battle", [], [], resources, [], catalog)
	var resource: RefCounted = controller.player_resource_states[0]
	_expect(controller.player_resource_states.size() == 1 and controller.get_living_states(BattleSquadState.Side.PLAYER).size() == 1, "资源战斗状态独立于双方随从存活池")
	_expect(resource.get("current_health") == resource_data.max_health and resource.call("apply_damage", 1) == 1 and resource.get("current_health") == resource_data.max_health - 1, "资源受击按固定生命扣减且可单独击破")
	var event := BattleEffectEvent.new()
	event.source = controller.player_states[0]
	event.resource_target = resource
	controller.call("_resolve_resource_harvest", event)
	_expect(resource.get("harvested") and controller.permanent_growth_ledger.get_entries().size() == 1 and controller.permanent_growth_ledger.get_entries()[0].get("stat") == BattlePermanentGrowthLedger.STAT_BASE_VALUE, "玩家收获火碎晶只记录行动来源卡永久数值+1")
	_expect(controller.run_reward_ledger.get_entries().is_empty(), "火碎晶不混入金币或随机奖励账本")
	var npc_resource_owned := OwnedCard.new()
	npc_resource_owned.initialize(load("res://resources/cards/light_element_shard.tres") as CardData, &"resource_test_npc", 1)
	var npc_resource := BattleResourceState.new()
	npc_resource.initialize(npc_resource_owned, BattleSquadState.Side.ENEMY)
	var npc_event := BattleEffectEvent.new()
	npc_event.source = controller.player_states[0]
	npc_event.source.side = BattleSquadState.Side.ENEMY
	npc_event.resource_target = npc_resource
	controller.call("_resolve_resource_harvest", npc_event)
	_expect(controller.run_reward_ledger.get_entries().is_empty(), "NPC侧资源收获入口不发放金币或其他奖励")
	controller.queue_free()
	await process_frame
	await _test_no_resource_does_not_spend_mining()
	await _test_real_projectile_resource_flow()
	await _test_mining_action_pipeline()
	await _test_harvest_and_reward_pools()
	if failures == 0:
		print("D2-6C resource battle checks passed.")
	quit(failures)

func _test_mining_action_pipeline() -> void:
	var tide := load("res://resources/cards/tide_archer.tres") as CardData
	var tide_owned := OwnedCard.new()
	tide_owned.initialize(tide, &"resource_test_tide", 0)
	var tide_squad := SquadData.from_owned_card(tide_owned)
	var pick := OwnedCard.new()
	pick.initialize(load("res://resources/cards/mining_pick.tres") as CardData, &"resource_test_pick", 1)
	_expect(tide_squad.equip_item(pick), "测试为潮汐射手装备矿镐")
	var formation: Array[Dictionary] = [{"squad_data": tide_squad, "row_key": &"player_front", "formation_index": 0}]
	var resource_data := load("res://resources/cards/fire_element_shard.tres") as CardData
	var resource_owned := OwnedCard.new()
	resource_owned.initialize(resource_data, &"resource_test_mine_target", 2)
	var controller := BattleController.new()
	root.add_child(controller)
	controller.start_battle(formation, [], 5678, false, &"resource_test_mining_battle", [], [], [resource_owned], [], [resource_data])
	var actor: BattleSquadState = controller.player_states[0]
	var resource: RefCounted = controller.player_resource_states[0]
	_expect(int(controller.mining_actions_remaining_by_runtime_id[actor.runtime_id]) == 2, "开采次数按运行时小队叠加潮汐射手与矿镐")
	var action: Dictionary = controller.call("_build_action", actor, controller.get_all_states(), CardData.ActionType.HEAL)
	var mining_event := action.get("base_event") as BattleEffectEvent
	_expect(bool(action.get("is_mining", false)) and mining_event != null and mining_event.is_mining, "有资源时治疗行动被开采覆盖")
	_expect(mining_event != null and mining_event.effect_kind == BattleEffectEvent.EffectKind.DAMAGE and is_equal_approx(mining_event.exact_amount, float(resource.current_health)), "开采事件归类为伤害并以资源当前生命为伤害值")
	_expect(int(controller.mining_actions_remaining_by_runtime_id[actor.runtime_id]) == 1, "开采次数在行动发射时消费")
	controller.call("_apply_effect_event", mining_event)
	_expect(resource.destroyed and is_equal_approx(mining_event.effective_amount, float(resource_data.max_health)), "开采单次击碎资源并造成全部剩余生命伤害")
	_expect(
		controller.permanent_growth_ledger.get_entries().size() == 1
		and is_equal_approx(actor.get_display_action_value() - actor.get_action_base_value(), 1.0),
		"火晶只记一条成长，潮汐射手击碎资源仅增加1点强化"
	)
	var late_resource_owned := OwnedCard.new()
	late_resource_owned.initialize(resource_data, &"resource_test_late_resource", 3)
	var late_state := BattleResourceState.new()
	late_state.initialize(late_resource_owned, BattleSquadState.Side.PLAYER)
	controller.player_resource_states.append(late_state)
	var late_action: Dictionary = controller.call("_build_action", actor, controller.get_all_states(), CardData.ActionType.MELEE)
	var late_event := late_action.get("base_event") as BattleEffectEvent
	_expect(late_event != null and late_event.resource_target == late_state, "第二次开采为新资源建立目标")
	late_state.apply_damage(late_state.current_health)
	controller.call("_apply_effect_event", late_event)
	_expect(late_event.missed and late_state.destroyed and controller.player_resource_states.size() == 2, "目标在结算前被摧毁时原动作落空且不替换目标")
	_expect(int(controller.mining_actions_remaining_by_runtime_id[actor.runtime_id]) == 0, "目标迟死不返还已在发射时消费的开采次数")
	controller.queue_free()
	await process_frame

func _test_real_projectile_resource_flow() -> void:
	var tide := load("res://resources/cards/tide_archer.tres") as CardData
	var enemy_data := _test_minion(&"resource_test_enemy", "存活敌军", CardData.ActionType.DEFENSE)
	var tide_owned := OwnedCard.new()
	tide_owned.initialize(tide, &"real_tide", 0)
	var tide_squad := SquadData.from_owned_card(tide_owned)
	var pick := OwnedCard.new()
	pick.initialize(load("res://resources/cards/mining_pick.tres") as CardData, &"real_pick", 1)
	tide_squad.equip_item(pick)
	var enemy_owned := OwnedCard.new()
	enemy_owned.initialize(enemy_data, &"real_enemy", 2)
	var companion := _test_minion(&"unmined_companion", "未开采友军", CardData.ActionType.DEFENSE)
	var companion_owned := OwnedCard.new()
	companion_owned.initialize(companion, &"unmined_companion_owned", 10)
	var resource_data := load("res://resources/cards/rainbow_gold_ore.tres") as CardData
	var resource_owned := OwnedCard.new()
	resource_owned.initialize(resource_data, &"real_rainbow", 3)
	var controller := BattleController.new()
	root.add_child(controller)
	controller.use_projectile_timing = true
	controller.start_battle(
		[
			{"squad_data": tide_squad, "row_key": &"player_front", "formation_index": 0},
			{"squad_data": SquadData.from_owned_card(companion_owned), "row_key": &"player_front", "formation_index": 1},
		],
		[{"squad_data": SquadData.from_owned_card(enemy_owned), "row_key": &"enemy_front", "formation_index": 0}],
		24680, false, &"real_resource_projectile", [], [], [resource_owned], [], _all_card_definitions(), [tide_owned, enemy_owned, companion_owned]
	)
	var actor := controller.player_states[0] as BattleSquadState
	var enemy := controller.enemy_states[0] as BattleSquadState
	var companion_state := controller.player_states[1] as BattleSquadState
	actor.remaining_cooldown = 0.001
	enemy.remaining_cooldown = 99.0
	companion_state.remaining_cooldown = 99.0
	actor.runtime_action_type_override = CardData.ActionType.HEAL
	var retained_modifier := BattleModifier.new()
	retained_modifier.stat = BattleModifier.Stat.REINFORCEMENT
	retained_modifier.mode = BattleModifier.Mode.ADD
	retained_modifier.value = 2.0
	retained_modifier.effect_id = &"test_existing_reinforcement"
	actor.modifiers.add_modifier(retained_modifier)
	var launched: Array[BattleEffectEvent] = []
	var resolved: Array[BattleEffectEvent] = []
	controller.projectile_launched.connect(func(event: BattleEffectEvent) -> void:
		if event.is_base_action: launched.append(event)
	)
	controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.is_base_action: resolved.append(event)
	)
	_expect(controller.resolve_next_batch() and launched.size() == 1, "双方随从存活时正常战斗推进会发射玩家开采弹道")
	var mining_event: BattleEffectEvent = launched[0] if not launched.is_empty() else null
	_expect(
		mining_event != null and mining_event.is_mining and mining_event.resource_target == controller.player_resource_states[0]
		and mining_event.action_type == CardData.ActionType.HEAL and controller.player_resource_states[0].current_health == 7,
		"治疗行动被开采替代；彩金矿7HP在发射阶段保留生命并成为目标"
	)
	_expect(
		mining_event != null and mining_event.effect_kind == BattleEffectEvent.EffectKind.DAMAGE
		and is_equal_approx(actor.get_display_action_value() - actor.get_action_base_value(), 2.0),
		"开采是伤害事件且不会消费开采前已有的2点强化"
	)
	if mining_event != null:
		controller.advance_time(mining_event.projectile_impact_delay)
	_expect(
		resolved.size() == 1 and resolved[0].resource_target.destroyed
		and is_equal_approx(resolved[0].effective_amount, 7.0),
		"命中时开采一次击碎7HP彩金矿"
	)
	_expect(
		is_equal_approx(actor.get_display_action_value() - actor.get_action_base_value(), 3.0)
		and controller.run_reward_ledger.get_entries().size() > 0,
		"潮汐射手实际获得+1强化且彩金矿只在玩家命中后记奖励"
	)
	var defense_resource_owned := OwnedCard.new()
	defense_resource_owned.initialize(load("res://resources/cards/fire_element_shard.tres") as CardData, &"defense_mining_resource", 11)
	var defense_resource := BattleResourceState.new()
	defense_resource.initialize(defense_resource_owned, BattleSquadState.Side.PLAYER)
	controller.player_resource_states.append(defense_resource)
	actor.runtime_action_type_override = CardData.ActionType.DEFENSE
	actor.remaining_cooldown = 0.001
	launched.clear()
	resolved.clear()
	_expect(controller.resolve_next_batch() and launched.size() == 1, "正常时序将防御动作发射为第二次开采")
	var defense_event: BattleEffectEvent = launched[0] if not launched.is_empty() else null
	_expect(
		defense_event != null and defense_event.is_mining and defense_event.action_type == CardData.ActionType.DEFENSE
		and defense_event.effect_kind == BattleEffectEvent.EffectKind.DAMAGE,
		"防御动作被开采覆盖后仍归类为伤害"
	)
	if defense_event != null: controller.advance_time(defense_event.projectile_impact_delay)
	_expect(
		int(controller.mining_actions_remaining_by_runtime_id[actor.runtime_id]) == 0,
		"潮汐射手与矿镐两次开采额度分别在各自发射时消费"
	)
	_expect(
		int(controller.mining_actions_remaining_by_runtime_id[companion_state.runtime_id]) == 0,
		"没有开采关键词的友军小队不继承潮汐射手与矿镐次数"
	)
	controller.queue_free()
	await process_frame

	var ordinary := load("res://resources/cards/tide_archer.tres") as CardData
	var ordinary_owned := OwnedCard.new()
	ordinary_owned.initialize(ordinary, &"ordinary_owned", 4)
	var hidden_enemy := OwnedCard.new()
	hidden_enemy.initialize(enemy_data, &"ordinary_enemy", 5)
	var ordinary_resource := OwnedCard.new()
	ordinary_resource.initialize(resource_data, &"ordinary_resource", 6)
	controller = BattleController.new()
	root.add_child(controller)
	controller.use_projectile_timing = true
	controller.start_battle(
		[{"squad_data": SquadData.from_owned_card(ordinary_owned), "row_key": &"player_front", "formation_index": 0}],
		[{"squad_data": SquadData.from_owned_card(hidden_enemy), "row_key": &"enemy_front", "formation_index": 0}],
		1357, false, &"ordinary_resource_projectile", [], [], [ordinary_resource], [], _all_card_definitions(), [ordinary_owned, hidden_enemy]
	)
	actor = controller.player_states[0] as BattleSquadState
	enemy = controller.enemy_states[0] as BattleSquadState
	enemy.moon_shadowed = true
	(controller.player_resource_states[0] as RefCounted).apply_damage(6)
	controller.mining_actions_remaining_by_runtime_id[actor.runtime_id] = 0
	actor.remaining_cooldown = 0.001
	enemy.remaining_cooldown = 99.0
	launched.clear()
	resolved.clear()
	controller.projectile_launched.connect(func(event: BattleEffectEvent) -> void:
		if event.is_base_action: launched.append(event)
	)
	controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.is_base_action: resolved.append(event)
	)
	_expect(controller.resolve_next_batch() and launched.size() == 1, "普通攻击者经正常推进向唯一合法的资源目标发射")
	var ordinary_event: BattleEffectEvent = launched[0] if not launched.is_empty() else null
	_expect(
		ordinary_event != null and not ordinary_event.is_mining and ordinary_event.resource_target == controller.player_resource_states[0]
		and not ordinary_event.uses_attack_type_multiplier and is_equal_approx(ordinary_event.exact_amount, 1.0),
		"资源普通攻击固定1点且不建立元素派生"
	)
	if ordinary_event != null: controller.advance_time(ordinary_event.projectile_impact_delay)
	_expect(
		resolved.size() == 1 and controller.player_resource_states[0].current_health == 0
		and is_equal_approx(ordinary_event.effective_amount, 1.0)
		and is_equal_approx(actor.get_display_action_value() - actor.get_action_base_value(), 1.0),
		"潮汐射手普通攻击抵达彩金矿只扣1HP且同样获得+1强化"
	)
	controller.queue_free()
	await process_frame

	var late_owned := OwnedCard.new()
	late_owned.initialize(tide, &"late_tide", 7)
	var late_resource := OwnedCard.new()
	late_resource.initialize(resource_data, &"late_rainbow", 8)
	var late_enemy := OwnedCard.new()
	late_enemy.initialize(enemy_data, &"late_enemy", 9)
	controller = BattleController.new()
	root.add_child(controller)
	controller.use_projectile_timing = true
	controller.start_battle(
		[{"squad_data": SquadData.from_owned_card(late_owned), "row_key": &"player_front", "formation_index": 0}],
		[{"squad_data": SquadData.from_owned_card(late_enemy), "row_key": &"enemy_front", "formation_index": 0}],
		8642, false, &"late_resource_projectile", [], [], [late_resource], [], [resource_data], [late_owned, late_enemy]
	)
	actor = controller.player_states[0] as BattleSquadState
	actor.remaining_cooldown = 0.001
	(controller.enemy_states[0] as BattleSquadState).remaining_cooldown = 99.0
	launched.clear()
	resolved.clear()
	controller.projectile_launched.connect(func(event: BattleEffectEvent) -> void:
		if event.is_base_action: launched.append(event)
	)
	controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void:
		if event.is_base_action: resolved.append(event)
	)
	controller.resolve_next_batch()
	var late_event: BattleEffectEvent = launched[0] if not launched.is_empty() else null
	if late_event != null:
		(controller.player_resource_states[0] as RefCounted).apply_damage(7)
		controller.advance_time(late_event.projectile_impact_delay)
	_expect(
		late_event != null and resolved.size() == 1 and late_event.missed
		and int(controller.mining_actions_remaining_by_runtime_id[actor.runtime_id]) == 0
		and controller.run_reward_ledger.get_entries().is_empty(),
		"发射后资源先被摧毁时弹道落空、不退款、不补选且不发奖励"
	)
	controller.queue_free()
	await process_frame

func _test_minion(card_id: StringName, label: String, action_type: CardData.ActionType) -> CardData:
	var data := CardData.new()
	data.id = card_id
	data.display_name = label
	data.card_type = CardData.CardType.MINION
	data.action_type = action_type
	data.base_value = 1
	data.max_health = 20
	data.cooldown_seconds = 4.0
	return data

func _test_no_resource_does_not_spend_mining() -> void:
	var tide := load("res://resources/cards/tide_archer.tres") as CardData
	var enemy := _test_minion(&"no_resource_enemy", "无资源敌军", CardData.ActionType.DEFENSE)
	var tide_owned := OwnedCard.new()
	tide_owned.initialize(tide, &"no_resource_tide", 0)
	var enemy_owned := OwnedCard.new()
	enemy_owned.initialize(enemy, &"no_resource_enemy_owned", 1)
	var controller := BattleController.new()
	root.add_child(controller)
	controller.use_projectile_timing = true
	controller.start_battle(
		[{"squad_data": SquadData.from_owned_card(tide_owned), "row_key": &"player_front", "formation_index": 0}],
		[{"squad_data": SquadData.from_owned_card(enemy_owned), "row_key": &"enemy_front", "formation_index": 0}],
		97531, false, &"no_resource_mining", [], [], [], [], [], [tide_owned, enemy_owned]
	)
	var actor := controller.player_states[0] as BattleSquadState
	var enemy_state := controller.enemy_states[0] as BattleSquadState
	actor.remaining_cooldown = 0.001
	enemy_state.remaining_cooldown = 99.0
	var launched: Array[BattleEffectEvent] = []
	controller.projectile_launched.connect(func(event: BattleEffectEvent) -> void:
		if event.is_base_action: launched.append(event)
	)
	controller.resolve_next_batch()
	_expect(
		launched.size() == 1 and not launched[0].is_mining
		and int(controller.mining_actions_remaining_by_runtime_id[actor.runtime_id]) == 1,
		"没有资源时潮汐射手正常攻击敌方，不消费开采额度"
	)
	controller.queue_free()
	await process_frame

func _test_harvest_and_reward_pools() -> void:
	var receiver_data := _test_minion(&"resource_harvest_receiver", "资源成长接收者", CardData.ActionType.DEFENSE)
	var receiver := OwnedCard.new()
	receiver.initialize(receiver_data, &"resource_harvest_receiver", 0)
	var enemy_owned := OwnedCard.new()
	enemy_owned.initialize(_test_minion(&"resource_harvest_enemy", "对手", CardData.ActionType.DEFENSE), &"resource_harvest_enemy", 1)
	var controller := BattleController.new()
	root.add_child(controller)
	controller.start_battle(
		[{"squad_data": SquadData.from_owned_card(receiver), "row_key": &"player_front", "formation_index": 0}],
		[{"squad_data": SquadData.from_owned_card(enemy_owned), "row_key": &"enemy_front", "formation_index": 0}],
		1122, false, &"resource_harvest_receivers", [], [], [], [], _all_card_definitions(), [receiver, enemy_owned]
	)
	var actor := controller.player_states[0] as BattleSquadState
	actor.current_armor = 0
	for resource_id: StringName in [&"fire_element_shard", &"water_element_shard", &"wood_element_shard"]:
		var resource_owned := OwnedCard.new()
		resource_owned.initialize(load("res://resources/cards/%s.tres" % resource_id) as CardData, StringName("receiver_%s" % resource_id), 2)
		var resource_state := BattleResourceState.new()
		resource_state.initialize(resource_owned, BattleSquadState.Side.PLAYER)
		var event := BattleEffectEvent.new()
		event.source = actor
		event.resource_target = resource_state
		controller.call("_resolve_resource_harvest", event)
	_expect(
		receiver.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == 1.0
		and receiver.get_permanent_growth(OwnedCard.STAT_MAX_HEALTH) == 2.0
		and receiver.get_permanent_growth(OwnedCard.STAT_BASE_ARMOR) == 1.0
		and controller.permanent_growth_ledger.get_entries().size() == 3,
		"火水木成长各记账一次并归属战斗中的实际OwnedCard接收者"
	)
	_expect(
		actor.get_max_health() == 22 and is_equal_approx(actor.current_health, 22.0)
		and is_equal_approx(actor.current_armor, 1.0),
		"水晶+2当前生命与上限、木晶+1当前护甲即时生效且不重复"
	)
	var wound_card := _test_minion(&"dark_shard_wound_holder", "暗蚀测试者", CardData.ActionType.DEFENSE)
	wound_card.wound_slot_count = 2
	var wound_owner := OwnedCard.new()
	wound_owner.initialize(wound_card, &"dark_shard_wound_owner", 7)
	wound_owner.wound_slots[0] = {"wound_id": &"scar", "level": 1}
	wound_owner.wound_slots[1] = {"wound_id": &"bruise", "level": 1}
	var wound_state := BattleSquadState.new()
	wound_state.initialize(SquadData.from_owned_card(wound_owner), BattleSquadState.Side.PLAYER, &"player_front", 1)
	var dark_card := OwnedCard.new()
	dark_card.initialize(load("res://resources/cards/dark_element_shard.tres") as CardData, &"dark_shard_owner", 8)
	var dark_state := BattleResourceState.new()
	dark_state.initialize(dark_card, BattleSquadState.Side.PLAYER)
	var dark_event := BattleEffectEvent.new()
	dark_event.source = wound_state
	dark_event.resource_target = dark_state
	controller.call("_resolve_resource_harvest", dark_event)
	_expect(
		int(wound_owner.wound_slots[0].is_empty()) + int(wound_owner.wound_slots[1].is_empty()) == 1
		and controller.owned_card_change_ledger.get_entries().size() == 1,
		"暗晶从行动者自己的可见伤势槽中清除一个确定目标并记入槽位账本"
	)
	var masked_owner := OwnedCard.new()
	masked_owner.initialize(wound_card, &"dark_shard_masked_owner", 9)
	masked_owner.wound_slots[0] = {"wound_id": &"scar", "level": 1}
	var masked_state := BattleSquadState.new()
	masked_state.initialize(SquadData.from_owned_card(masked_owner), BattleSquadState.Side.PLAYER, &"player_front", 2)
	masked_state.mask_injury(StringName("%s:wound:0" % masked_owner.instance_id), 991)
	var masked_resource_owned := OwnedCard.new()
	masked_resource_owned.initialize(load("res://resources/cards/dark_element_shard.tres") as CardData, &"masked_dark_shard", 10)
	var masked_resource := BattleResourceState.new()
	masked_resource.initialize(masked_resource_owned, BattleSquadState.Side.PLAYER)
	var masked_event := BattleEffectEvent.new()
	masked_event.source = masked_state
	masked_event.resource_target = masked_resource
	controller.call("_resolve_resource_harvest", masked_event)
	_expect(
		masked_owner.wound_slots[0].get("wound_id", &"") == &"scar"
		and controller.owned_card_change_ledger.get_entries().size() == 1,
		"暗晶跳过全部被遮蔽伤势，不跨到其他小队清除伤势"
	)
	var rewards := RunRewardState.new()
	rewards.gold = 3
	var first_loss := rewards.apply_gold_delta(-2)
	var second_loss := rewards.apply_gold_delta(-8)
	_expect(first_loss == -2 and second_loss == -1 and rewards.gold == 0, "连续负金币条目逐条结算且最低金币为0")
	for rarity: int in [CardData.Rarity.I, CardData.Rarity.II, CardData.Rarity.III]:
		var emblem: Dictionary = controller.call("_random_emblem_definition", rarity)
		_expect(not emblem.is_empty() and int(emblem.get("rarity", -1)) == rarity and emblem.get("target", "") != "rune", "指定纹章池只抽对应品级的非元素贴纸")
	_expect((controller.call("_random_emblem_definition", 99) as Dictionary).is_empty(), "不存在的指定纹章品级返回空奖励")
	var toolbox_pool_has_labyrinth_item := false
	for seed: int in range(1, 150):
		controller._random.seed = seed
		var equipment := controller._random_equipment_definition(CardData.Rarity.I)
		if equipment != null and equipment.pack_id == &"labyrinth":
			toolbox_pool_has_labyrinth_item = true
			break
	_expect(toolbox_pool_has_labyrinth_item, "废弃工具箱I级池包含正常迷宫卡包装备")
	var synthetic_iv := CardData.new()
	synthetic_iv.id = &"test_iv_unique_equipment"
	synthetic_iv.display_name = "唯一性测试装备"
	synthetic_iv.card_type = CardData.CardType.EQUIPMENT
	synthetic_iv.rarity = CardData.Rarity.IV
	synthetic_iv.pack_id = &"labyrinth"
	controller._reward_card_catalog = [synthetic_iv]
	controller._player_owned_card_ids[synthetic_iv.id] = true
	_expect(controller._random_equipment_definition(CardData.Rarity.IV) == null, "IV装备池排除玩家全收藏中已持有同名ID")
	controller._player_owned_card_ids.erase(synthetic_iv.id)
	var award_owner := BattleEffectOwnerRef.for_state(actor, BattleEffectDefinition.OwnerKind.OWNING_PLAYER)
	controller.record_pending_run_reward(
		award_owner, BattleRunRewardLedger.KIND_OWNED_CARD_AWARD, 1,
		&"test_prior_iv_award", actor.runtime_id, 900,
		{"card_id": synthetic_iv.id, "card_name": synthetic_iv.display_name}
	)
	_expect(controller._random_equipment_definition(CardData.Rarity.IV) == null, "IV装备池排除本场先前已经发出的同名装备")
	var npc_owned := OwnedCard.new()
	npc_owned.initialize(load("res://resources/cards/tide_archer.tres") as CardData, &"npc_harvest_effect_owner", 3)
	var npc_enemy := OwnedCard.new()
	npc_enemy.initialize(receiver_data, &"npc_harvest_enemy", 4)
	var npc_controller := BattleController.new()
	root.add_child(npc_controller)
	npc_controller.start_battle(
		[{"squad_data": SquadData.from_owned_card(npc_enemy), "row_key": &"player_front", "formation_index": 0}],
		[{"squad_data": SquadData.from_card(npc_owned.card_data), "row_key": &"enemy_front", "formation_index": 0}],
		3344, false, &"npc_all_resource_harvests", [], [], [], [], [], [npc_enemy]
	)
	var npc_actor := npc_controller.enemy_states[0] as BattleSquadState
	for filename: String in DirAccess.get_files_at("res://resources/cards"):
		if filename.get_extension() != "tres": continue
		var definition := load("res://resources/cards/%s" % filename) as CardData
		if definition == null or definition.card_type != CardData.CardType.RESOURCE: continue
		var npc_resource_card := OwnedCard.new()
		npc_resource_card.initialize(definition, StringName("npc_harvest_%s" % definition.id), 5)
		var npc_resource := BattleResourceState.new()
		npc_resource.initialize(npc_resource_card, BattleSquadState.Side.ENEMY)
		var npc_event := BattleEffectEvent.new()
		npc_event.source = npc_actor
		npc_event.resource_target = npc_resource
		npc_controller.call("_resolve_resource_harvest", npc_event)
	_expect(
		npc_controller.run_reward_ledger.get_entries().is_empty()
		and npc_controller.permanent_growth_ledger.get_entries().is_empty()
		and npc_controller.owned_card_change_ledger.get_entries().is_empty(),
		"NPC开采九种资源不产生金币、卡牌、装备、纹章、成长或伤势变化"
	)
	var npc_resource_card := OwnedCard.new()
	npc_resource_card.initialize(load("res://resources/cards/fire_element_shard.tres") as CardData, &"npc_tide_actual_break", 6)
	var npc_resource := BattleResourceState.new()
	npc_resource.initialize(npc_resource_card, BattleSquadState.Side.ENEMY)
	var npc_break := BattleEffectEvent.new()
	npc_break.source = npc_actor
	npc_break.resource_target = npc_resource
	npc_break.is_mining = true
	npc_controller.call("_apply_effect_event", npc_break)
	_expect(
		is_equal_approx(npc_actor.get_display_action_value() - npc_actor.get_action_base_value(), 1.0)
		and npc_controller.run_reward_ledger.get_entries().is_empty(),
		"无OwnedCard实例的NPC潮汐射手击碎资源仍强化而不发放玩家奖励"
	)
	npc_controller.queue_free()
	controller.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)

func _all_card_definitions() -> Array[CardData]:
	var cards: Array[CardData] = []
	for filename: String in DirAccess.get_files_at("res://resources/cards"):
		if filename.get_extension() != "tres": continue
		var card := load("res://resources/cards/%s" % filename) as CardData
		if card != null: cards.append(card)
	return cards
