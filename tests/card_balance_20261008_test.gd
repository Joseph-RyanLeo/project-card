extends SceneTree

## 平衡更新使用正式卡牌、拥有实例、资源命中与效果队列验证，不替代战斗计算。
var failures := 0
var checks := 0
var sequence := 0
var current: BattleController

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func owned(id: String, with_effects: bool = true) -> OwnedCard:
	sequence += 1
	var definition := load("res://resources/cards/%s.tres" % id).duplicate(true) as CardData
	definition.cooldown_seconds = 99.0
	if not with_effects: definition.effect_ids.clear()
	var card := OwnedCard.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 71000 + sequence
	card.initialize(definition, StringName("balance:%d" % sequence), sequence, rng)
	card.rune_revealed.fill(false)
	return card

func entry(card: OwnedCard, index: int, row: StringName = &"player_front") -> Dictionary:
	return {"squad_data": SquadData.from_owned_card(card), "row_key": row, "formation_index": index}

func start(players: Array[Dictionary], resources: Array[OwnedCard] = [], timed: bool = false) -> BattleController:
	if current != null:
		current.clear_battle()
		current.free()
	current = BattleController.new()
	root.add_child(current)
	current.use_projectile_timing = timed
	current.start_battle(players, [entry(owned("militia", false), 0, &"enemy_front")], 71108, false, &"balance_update", [], [], resources)
	return current

func mine(actor: BattleSquadState, resource: RefCounted) -> void:
	current._apply_effect_event(current.make_mining_event(actor, resource))
	current._finalize_batch()

func _run() -> void:
	check(BattleEffectCatalog.load_from_file("res://data/demo2/ash_ledger_effect_samples.json").is_valid(), "正式灰烬效果目录通过严格校验")
	_test_baggage()
	_test_armorsmith()
	_test_timid()
	_test_fireman_and_dazzling()
	_test_poet()
	await _test_main_fireman_disk()
	if current != null:
		current.clear_battle()
		current.free()
	await process_frame
	print("10月8日平衡更新：%d项检查，%d失败" % [checks, failures])
	quit(1 if failures else 0)

func _test_baggage() -> void:
	for timed: bool in [false, true]:
		var left := owned("militia", false)
		var right := owned("militia", false)
		var mule := owned("baggage_muleteer")
		var c := start([entry(left, 0), entry(mule, 1), entry(right, 2)], [owned("wood_element_shard"), owned("water_element_shard")], timed)
		c.advance_time(2.0)
		check(c.twisted_vein.mining_events == 1, "开场乡邻成立只开采一次，真实弹道与无弹道一致")
		check(c.run_reward_ledger.get_total(BattleRunRewardLedger.KIND_GOLD, 0) == 1, "突击只获得1金币")
		check(c.player_states[0].get_max_health() == left.card_data.max_health and c.player_states[2].get_max_health() == right.card_data.max_health, "邻居不再获得旧生命光环")
		var target := c.player_states[2]
		target.alive = false
		c.effect_runtime.recheck_continuous_conditions()
		c.effect_runtime.process_due(c.elapsed_seconds)
		target.alive = true
		c.effect_runtime.recheck_continuous_conditions()
		c.effect_runtime.process_due(c.elapsed_seconds)
		check(c.twisted_vein.mining_events == 1, "乡邻条件战中恢复不补开采")
		check(int(c.mining_actions_remaining_by_runtime_id.get(c.player_states[1].runtime_id, 0)) == 0, "额外开采不改变普通行动开采额度")
	var c := start([entry(owned("old_wolf_kaspar"), 0), entry(owned("baggage_muleteer"), 1), entry(owned("militia", false), 2)], [owned("wood_element_shard"), owned("water_element_shard")])
	check(c.twisted_vein.mining_events == 2 and c.run_reward_ledger.get_total(BattleRunRewardLedger.KIND_GOLD, 0) == 1, "老狼额外执行乡邻开采，不重复突击金币")
	c = start([entry(owned("baggage_muleteer"), 0), entry(owned("militia", false), 1)], [owned("wood_element_shard")])
	check(c.twisted_vein.mining_events == 0, "开场乡邻不成立不采矿")
	c = start([entry(owned("militia", false), 0), entry(owned("baggage_muleteer"), 1), entry(owned("militia", false), 2)])
	var new_resource: RefCounted = c.spawn_content_resource(load("res://resources/cards/wood_element_shard.tres"), 0)
	check(new_resource != null and not new_resource.destroyed and c.twisted_vein.mining_events == 0, "开场无资源不延后补采新增资源")

func _test_armorsmith() -> void:
	var c := start([entry(owned("militia", false), 0), entry(owned("armorsmith"), 1), entry(owned("militia", false), 2), entry(owned("militia", false), 0, &"player_back")], [owned("water_element_shard"), owned("water_element_shard")])
	var before: Array[float] = []
	for state: BattleSquadState in c.player_states: before.append(state.current_armor)
	mine(c.player_states[0], c.player_resource_states[0])
	check(c.player_states.slice(0, 3).all(func(s: BattleSquadState): return s.current_armor == before[c.player_states.find(s)] + 1), "相邻成功开采给全部前排友军护甲+1，包括前排铸甲师")
	check(c.player_states[3].current_armor == before[3], "后排不受益")
	mine(c.player_states[2], c.player_resource_states[1])
	check(c.player_states[1].current_armor == before[1] + 2, "第二次成功开采继续触发，没有旧每场一次限制")
	var resource: RefCounted = c.spawn_content_resource(load("res://resources/cards/water_element_shard.tres"), 0)
	mine(c.player_states[3], resource)
	check(c.player_states[1].current_armor == before[1] + 2, "其他排的开采不误算相邻")
	resource = c.spawn_content_resource(load("res://resources/cards/water_element_shard.tres"), 0)
	mine(c.enemy_states[0], resource)
	check(c.player_states[1].current_armor == before[1] + 2, "敌方开采不触发我方铸甲师")
	resource = c.spawn_content_resource(load("res://resources/cards/light_element_shard.tres"), 0)
	var attack := c.make_mining_event(c.player_states[0], resource)
	attack.is_mining = false
	for _index: int in int(resource.current_health): c._apply_effect_event(attack)
	check(resource.destroyed and c.player_states[1].current_armor == before[1] + 2, "普通攻击击碎资源不算开采")
	mine(c.player_states[0], resource)
	check(c.player_states[1].current_armor == before[1] + 2, "开采命中已碎资源落空，不发护甲")
	var growth_count := c.permanent_growth_ledger.get_entries().size()
	c.player_states[0].current_health = 0.0
	c._finalize_batch()
	check(c.permanent_growth_ledger.get_entries().size() == growth_count, "旧相邻死亡永久护甲成长已删除")
	c = start([entry(owned("gold_sprite"), 0), entry(owned("armorsmith"), 1), entry(owned("militia", false), 2)], [owned("water_element_shard"), owned("water_element_shard")])
	var armor_before := c.player_states[1].current_armor
	c.execute_immediate_action(c.player_states[0], CardData.ActionType.MELEE)
	check(c.twisted_vein.mining_events == 2 and c.player_states[1].current_armor == armor_before + 2, "金光妖双开采每张成功资源各触发一次")
	c = start([entry(owned("armorsmith"), 0), entry(owned("militia", false), 1), entry(owned("shieldwall_private"), 2), entry(owned("militia", false), 3), entry(owned("anvil_margaret"), 0, &"player_back")], [owned("water_element_shard")])
	armor_before = c.player_states[2].current_armor
	mine(c.player_states[1], c.player_resource_states[0])
	check(c.player_states[2].current_armor == armor_before + 3, "新护甲按铁砧乘2后盾墙加1，追加护甲不递归")
	c = start([entry(owned("militia", false), 0), entry(owned("armorsmith"), 0, &"player_back"), entry(owned("militia", false), 1, &"player_back")], [owned("water_element_shard")])
	armor_before = c.player_states[0].current_armor
	var smith_armor := c.player_states[1].current_armor
	mine(c.player_states[2], c.player_resource_states[0])
	check(c.player_states[0].current_armor == armor_before + 1 and c.player_states[1].current_armor == smith_armor, "后排铸甲师仍增强前排，不增强自身后排")
	c.player_states[0].moon_shadowed = true
	resource = c.spawn_content_resource(load("res://resources/cards/water_element_shard.tres"), 0)
	mine(c.player_states[2], resource)
	check(c.player_states[0].current_armor == armor_before + 1, "放逐前排不成为护甲效果的目标")

func _test_timid() -> void:
	var c := start([entry(owned("timid_infantry"), 0), entry(owned("militia", false), 1), entry(owned("militia", false), 0, &"player_back")])
	for actor: BattleSquadState in [c.player_states[0], c.player_states[2], c.enemy_states[0]]:
		c.effect_runtime.notify_action_after(actor)
		c.effect_runtime.process_due(0.0)
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 0, "自身、其他排与敌方行动不提供强化")
	for _index: int in 7:
		c.execute_immediate_action(c.player_states[1], CardData.ActionType.DEFENSE)
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 7, "同排友军实际行动后提供强化且超过旧5点上限")
	c.execute_immediate_action(c.player_states[0], CardData.ActionType.MELEE)
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 0, "自身实际行动消费强化")
	c.execute_immediate_action(c.player_states[1], CardData.ActionType.DEFENSE)
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 1, "下一次同排友军行动重新积累")

func _test_fireman_and_dazzling() -> void:
	var kinds: Dictionary = {}
	for _index: int in 32:
		var fire := owned("fireman")
		kinds[fire.resolved_action_type] = true
		check(fire.resolved_action_type in [CardData.ActionType.HEAL, CardData.ActionType.MAGIC], "伙夫获得时只抽治疗或魔法")
		var restored := OwnedCard.new()
		check(restored.restore_state(fire.capture_state()) and restored.resolved_action_type == fire.resolved_action_type and SquadData.from_owned_card(restored).get_effective_action_type() == fire.resolved_action_type, "拥有实例恢复与战场行动沿用获得时选择")
	check(kinds.size() == 2, "固定种子序列覆盖治疗和魔法两种结果")
	var c := start([entry(owned("fireman"), 0), entry(owned("shieldwall_private"), 1)])
	check(c.has_effective_dazzling(c.player_states[0]) and c.has_effective_dazzling(c.player_states[1]), "伙夫与盾墙都有真实耀眼目标规则，不重复叠词条")

func _test_poet() -> void:
	var c := start([entry(owned("militia", false), 0), entry(owned("elegy_poet"), 1), entry(owned("militia", false), 2), entry(owned("militia", false), 0, &"player_back")])
	c.player_states[3].current_health = 0.0
	c._finalize_batch()
	check(c.player_states[0].get_zeal_layers() == 1 and c.player_states[2].get_zeal_layers() == 1 and c.player_states[1].get_zeal_layers() == 0, "其他非衍生友军死亡只增强诗人的相邻友军")
	c.player_states[1].current_health = 0.0
	c._finalize_batch()
	check(c.player_states[0].get_zeal_layers() == 1 and c.player_states[2].get_zeal_layers() == 1, "诗人自身死亡不再触发一次热诚")

func _test_main_fireman_disk() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-balance-fireman-run.json"
	root.add_child(main)
	await process_frame
	await process_frame
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	var rng := RandomNumberGenerator.new()
	rng.seed = 71108
	var samples: Dictionary = {}
	var selected: Dictionary = {}
	for _index: int in 16:
		var card: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/fireman.tres"), rng)
		samples[card.instance_id] = card.resolved_action_type
		selected[card.resolved_action_type] = card
	for card: OwnedCard in selected.values(): main.front_row.add_squad(SquadData.from_owned_card(card), main.front_row.get_squad_count())
	check(selected.size() == 2, "真实收藏获得伙夫覆盖两种行动")
	check(main.save_run_to_path(main.run_save_path) == OK, "真实Main把新伙夫行动写入隔离的磁盘JSON")
	main.queue_free()
	await process_frame
	main = load("res://scenes/Main.tscn").instantiate()
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-balance-fireman-restored-run.json"
	root.add_child(main)
	await process_frame
	await process_frame
	var loaded: bool = main.load_run_from_path("/private/tmp/project-card-balance-fireman-run.json")
	check(loaded, "新Main从磁盘重新加载伙夫实例")
	if loaded:
		var matching := true
		for id: StringName in samples:
			var restored: OwnedCard = main.owned_card_collection.get_by_instance_id(id)
			matching = matching and restored != null and restored.resolved_action_type == samples[id]
		check(matching and main.front_row.get_squad_count() == 2, "磁盘读档保留所有获得时选择及两张已部署伙夫")
	main.queue_free()
	await process_frame
