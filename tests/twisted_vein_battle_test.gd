extends SceneTree

## 全部使用正式资源、控制器、逻辑弹道与账本，不替换执行器或随机源。
var failures := 0
var assertions := 0
var sequence := 0
var catalog: Array[CardData] = []
var current: BattleController

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func owned(id: String, reveal: bool = false) -> OwnedCard:
	sequence += 1
	var result := OwnedCard.new()
	result.initialize(load("res://resources/cards/%s.tres" % id), StringName("twisted_test:%d" % sequence), sequence)
	result.rune_revealed.fill(reveal)
	return result

func formation(cards: Array[OwnedCard], side: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in cards.size():
		result.append({"squad_data": SquadData.from_owned_card(cards[index]), "row_key": &"player_front" if side == 0 else &"enemy_front", "formation_index": index})
	return result

func battle(player: Array[OwnedCard], enemy: Array[OwnedCard], resources: Array[OwnedCard] = [], spells: Array[OwnedCard] = [], context: Dictionary = {}, timed: bool = false) -> BattleController:
	if current != null:
		current.clear_battle()
		current.free()
	current = BattleController.new()
	root.add_child(current)
	current.use_projectile_timing = timed
	current.start_battle(formation(player, 0), formation(enemy, 1), 7041, false, StringName("tv:%d" % sequence), spells, [], resources, [], catalog, player, {}, context)
	return current

func echo(c: BattleController, state: BattleSquadState) -> void:
	c.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": state})
	c.effect_runtime.process_due(c.elapsed_seconds)

func hit(c: BattleController, source: BattleSquadState, target: BattleSquadState, amount: float, type: CardData.ActionType = CardData.ActionType.MELEE, pierces: bool = false, primary: bool = true) -> BattleEffectEvent:
	var event := c.twisted_vein.make_event(source, target, amount, type, false, "专项真实伤害")
	event.pierces_armor = pierces
	event.is_base_action = primary
	c._apply_effect_event(event)
	c._finalize_batch()
	return event

func _run() -> void:
	var file := FileAccess.open("res://data/demo2/twisted_vein_manifest.json", FileAccess.READ)
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	for entry: Dictionary in manifest.cards:
		var card := load("res://resources/cards/%s.tres" % entry.id) as CardData
		check(card != null and String(card.id) == entry.id and card.is_available, "正式资源身份：" + entry.name)
		check(card != null and card.deferred_effect_hooks.is_empty(), "矿脉没有未执行钩子：" + entry.name)
		if card != null: catalog.append(card)
	for id: String in ["fire_element_shard", "water_element_shard", "wood_element_shard", "light_element_shard", "dark_element_shard", "baggage_muleteer"]: catalog.append(load("res://resources/cards/%s.tres" % id))
	check((load("res://resources/cards/greed_demon.tres") as CardData).rarity == CardData.Rarity.III, "贪魔正式品级改III")
	check(manifest.cards.size() == 36, "36张唯一确认卡")
	check((load("res://resources/cards/golden_golem.tres") as CardData).cooldown_seconds == 10.0, "黄金魔像保留10秒冷却")
	check((load("res://resources/cards/rallying_mine_bell.tres") as CardData).race_type == CardData.RaceType.NONE, "矿铃无种族")
	check((load("res://resources/cards/guard_remains.tres") as CardData).max_health == 2, "守卫残骸修正生命2")
	test_mining()
	test_economy()
	test_timed_content_sleep()
	test_spirit_stack()
	test_triggers()
	test_damage_and_sleep()
	test_resources_and_equipment()
	test_area_death_order()
	test_spells()
	test_last_unit_death_projectiles()
	test_death_chains()
	test_passive_boundaries()
	test_fatigue_boundaries()
	test_npc_mining_commit()
	test_economy_settlement_boundaries()
	test_consumption_series()
	test_settlement()
	if current != null:
		current.clear_battle()
		current.free()
	print("扭曲矿脉：%d条断言，%d失败" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func test_mining() -> void:
	var c := battle([owned("gold_sprite"), owned("crystal_shell_broodmother"), owned("guard_remains")], [owned("guard_remains")], [owned("fire_element_shard"), owned("wood_element_shard")], [], {"mining_totals": [3, 4]}, true)
	var actor := c.player_states[0]
	check(c.player_states[2].is_sleeping(0.0), "残骸开场休眠")
	var launches: Array[BattleEffectEvent] = []
	c.projectile_launched.connect(func(event: BattleEffectEvent): launches.append(event))
	c.execute_immediate_action(actor, CardData.ActionType.MELEE)
	check(launches.size() == 2 and launches[0].resource_target != launches[1].resource_target, "双开采锁定两个不同资源")
	c.advance_time(0.8)
	check(c.twisted_vein.mining_events == 2 and c.twisted_vein.mining_totals == [5, 4], "每张成功资源各计事件和本局累计")
	check(c.player_states.size() == 5, "巢母两次开采召唤两只晶壳虫")
	check(not c.player_states[2].is_sleeping(c.elapsed_seconds) and not c.enemy_states[0].is_sleeping(c.elapsed_seconds), "双方残骸被开采唤醒")
	var extra := c.spawn_content_resource(load("res://resources/cards/light_element_shard.tres"), 1)
	check(extra != null, "战中资源正式部署")
	c.execute_immediate_action(actor, CardData.ActionType.MELEE)
	c.advance_time(0.8)
	check(c.twisted_vein.mining_events == 3, "无限开采在资源再出现后恢复，剩一张只采一次")
	check(c.player_states[3].get_effect_source().id == &"crystal_shell_beetle" and c.player_states[4].get_effect_source().id == &"crystal_shell_beetle", "巢母实际产物为晶壳虫")
	var beetle := c.summon_content_minion(actor, load("res://resources/cards/crystal_shard_beetle.tres"))
	var base := beetle.get_action_base_value()
	var display_before := beetle.get_display_action_value()
	var health := beetle.get_max_health()
	c.spawn_content_resource(load("res://resources/cards/light_element_shard.tres"), 1)
	c.execute_immediate_action(beetle, CardData.ActionType.MELEE)
	c.advance_time(0.8)
	check(beetle.get_action_base_value() == base and beetle.get_display_action_value() == display_before + 1 and beetle.get_max_health() == health + 1, "碎晶虫只因自身成功开采获得本场数值与生命")
	check(c.permanent_growth_ledger.get_entries().filter(func(e: Dictionary): return e.effect_id == &"crystal_shard_beetle").is_empty(), "碎晶虫成长不写永久账本")
	var full: Array[OwnedCard] = [owned("crystal_shell_broodmother")]
	for _index: int in 6: full.append(owned("guard_remains"))
	c = battle(full, [owned("guard_remains")])
	check(c.summon_content_minion(c.player_states[0], load("res://resources/cards/crystal_shard_beetle.tres")) == null and c.player_states.size() == 7, "21格满场召唤失败不补放")

func test_economy() -> void:
	var c := battle([owned("greed_demon"), owned("greedy_acolyte"), owned("miser")], [owned("miser"), owned("greed_demon")], [], [], {"player_gold": 5})
	var collector := c.enemy_states[0]
	collector.current_health = 1.0
	var healing_events: Array[BattleEffectEvent] = []
	c.effect_resolved.connect(func(e: BattleEffectEvent):
		if e.effect_kind == BattleEffectEvent.EffectKind.HEALING: healing_events.append(e))
	var before := c.player_states[0].get_display_action_value()
	c.record_pending_run_reward(BattleEffectOwnerRef.for_state(collector, BattleEffectDefinition.OwnerKind.OWNING_PLAYER), BattleRunRewardLedger.KIND_GOLD, 7, &"gold_batch", collector.runtime_id, 0)
	check(c.twisted_vein.wallets == [5, 22], "NPC初始15，金币归实际赚取方")
	check(c.player_states[0].get_display_action_value() == before + 7 and c.enemy_states[1].get_display_action_value() == 13, "双方贪魔按每枚金币增加本场数值")
	check(healing_events.size() == 1 and healing_events[0].target == collector and collector.current_health > 1.0, "休眠信徒一批金币治疗敌方赚取者一次")
	echo(c, collector)
	check(c.twisted_vein.wallets[0] == 3 and c.twisted_vein.stolen_from_player == 2, "NPC偷2金币计玩家损失")
	c.twisted_vein.wallets[0] = 1
	echo(c, collector)
	check(c.twisted_vein.wallets[0] == 1 and c.twisted_vein.stolen_from_player == 2, "不足2金币整次偷取失败")
	c.twisted_vein.finish(BattleController.Result.PLAYER_VICTORY)
	check(c.run_reward_ledger.get_total(BattleRunRewardLedger.KIND_PLAYER_REFUND, 0) == 2, "胜利返还玩家被偷金额入正式账本")
	check(c.player_states[1].is_sleeping(0), "反应治疗后信徒保持休眠")
	check(not SquadData.from_cards([owned("greedy_acolyte").card_data, owned("guard_remains").card_data]).is_valid(), "信徒禁止堆叠")

func test_triggers() -> void:
	var golem := owned("golden_golem")
	golem.set_emblem_slot(0, {"instance_id": &"golem_torch", "emblem_id": &"火把"})
	golem.set_emblem_slot(1, {"instance_id": &"golem_shield", "emblem_id": &"刺盾"})
	var c := battle([golem, owned("miserly_mine_owner"), owned("rallying_mine_bell")], [owned("guard_remains")], [], [], {"mining_totals": [4, 6]})
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 10, "魔像突击成功清除纹章才强化10")
	check(golem.emblem_slots.filter(func(s: Dictionary): return not s.is_empty()).size() == 1, "魔像只移除一个纹章")
	check(c.player_states[1].get_max_health() == 12 and c.player_states[1].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 10, "矿主读双方累计获得本场生命强化")
	check(c.player_states.size() == 4 and c.player_states[-1].get_effect_source().rarity in [CardData.Rarity.I, CardData.Rarity.II], "矿铃开场召唤合格低品级随从")
	echo(c, c.player_states[0])
	check(golem.emblem_slots.filter(func(s: Dictionary): return not s.is_empty()).is_empty(), "魔像回响移除剩余纹章")
	var reinforcement := c.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)
	echo(c, c.player_states[0])
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == reinforcement, "无纹章不获强化")
	var summoned := c.summon_content_minion(c.player_states[1], load("res://resources/cards/minecart_soul.tres"))
	check(summoned != null and summoned.remaining_cooldown == summoned.get_action_interval(), "新召唤矿车不补触发突击")
	var spirit := owned("ember_spirit", true)
	spirit.resolved_runes.assign([CardData.ElementType.WATER, CardData.ElementType.WOOD, CardData.ElementType.LIGHT])
	c = battle([spirit], [owned("guard_remains")])
	var state := c.player_states[0]
	check(state.runtime_rune_overrides.size() == 2 and spirit.resolved_runes == [1, 2, 3], "余火突击随机两个非火槽临时覆盖且原符文不变")
	var converted := state.runtime_rune_overrides.duplicate()
	echo(c, state)
	check(state.runtime_rune_overrides == converted and c.owned_card_change_ledger.get_entries().is_empty(), "余火不再响应回响、不写永久事务")
	spirit.resolved_runes.assign([CardData.ElementType.WATER, CardData.ElementType.FIRE, CardData.ElementType.FIRE])
	spirit.rune_revealed[0] = false
	c = battle([spirit], [owned("guard_remains")])
	check(c.player_states[0].runtime_rune_overrides.is_empty(), "未揭晓非火符文不被转换")
	spirit.set_rune_sticker(0, {"element": CardData.ElementType.WOOD, "instance_id": &"sticker"})
	c = battle([spirit], [owned("guard_remains")])
	check(c.player_states[0].runtime_rune_overrides.size() == 1 and c.player_states[0].get_active_rune_slots()[0].element == CardData.ElementType.FIRE, "不足两枚时有效贴纸仍临时转火")
	check(spirit.get_effective_rune(0) == CardData.ElementType.WOOD and spirit.resolved_runes[0] == CardData.ElementType.WATER, "转火保留原贴纸及底层符文")
	c.player_states[0].clear_precise_runtime()
	check(c.player_states[0].runtime_rune_overrides.is_empty() and c.player_states[0].get_active_rune_slots()[0].element == CardData.ElementType.WOOD, "战斗临时状态清理后恢复贴纸元素")
	c = battle([owned("mining_disaster_wraith")], [owned("guard_remains")])
	var armor_before := c.player_states[0].current_armor
	echo(c, c.player_states[0])
	check(is_equal_approx(c.player_states[0].current_armor, armor_before - 2.6), "怨灵回响包含自身并套远程有甲倍率")
	check(c.player_resource_states.size() + c.enemy_resource_states.size() == 1, "怨灵随后生成矿物")
	c = battle([owned("crystal_shell_beetle"), owned("guard_remains")], [owned("guard_remains")])
	var shell := c.player_states[0]
	var chosen := shell.get_effective_action_type()
	echo(c, shell)
	check(c.player_resource_states.is_empty() and c.enemy_resource_states.is_empty(), "晶壳虫回响不生成碎晶")
	check(shell.get_effective_action_type() == chosen, "晶壳虫行动方式在实例获得时固定")
	hit(c, c.enemy_states[0], shell, 20.0)
	check(c.player_resource_states.size() + c.enemy_resource_states.size() == 1, "晶壳虫真实死亡触发遗愿生成一张碎晶")

func test_damage_and_sleep() -> void:
	var c := battle([owned("subterranean_blindfish"), owned("rockwall_tongue_lizard")], [owned("guard_remains")])
	var target := c.enemy_states[0]
	hit(c, c.player_states[0], target, 0.1)
	check(target.get_target_weight() == 10, "盲鱼命中提升优先级2")
	for _index: int in 50: c.twisted_vein.on_hit(c.twisted_vein.make_event(c.player_states[0], target, 0, CardData.ActionType.MELEE, false, "附加非主伤害"))
	check(target.get_target_weight() == 10, "非主攻击不误触发盲鱼")
	hit(c, c.player_states[1], target, 0.1, CardData.ActionType.RANGED)
	check(c.player_states[1].is_sleeping(0) and target.is_sleeping(0), "舌蜥命中双方休眠3秒")
	c.player_states[1].grant_runtime_keyword(&"silenced", 987)
	check(c.player_states[1].is_sleeping(2.999) and target.is_sleeping(2.999), "沉默来源不提前解除定时休眠")
	check(not c.player_states[1].is_sleeping(3.0) and target.is_sleeping(3.0) and not target.sleep_source_until.has(StringName("tongue_sleep:%d" % c.player_states[1].runtime_id)), "舌蜥休眠在3秒准时到期，残骸自身休眠另计")
	c = battle([owned("guard_remains")], [owned("crystal_skin_sentry")])
	var sentinel := c.enemy_states[0]
	var event := hit(c, c.player_states[0], sentinel, 20.0)
	check(event.effective_amount == 1.0 and sentinel.current_armor == 1.0, "哨兵单次大伤害上限1")
	event = hit(c, c.player_states[0], sentinel, 0.25)
	check(event.effective_amount == 0.25 and sentinel.current_armor == 0.75, "哨兵小数伤害保留")
	hit(c, c.player_states[0], sentinel, 20.0)
	check(not sentinel.alive and c.owned_card_change_ledger.get_entries().any(func(e: Dictionary): return e.kind == BattleOwnedCardChangeLedger.KIND_DESTROY_CARD), "哨兵护甲耗尽死亡并永久销毁")
	c = battle([owned("guard_remains")], [owned("crystal_skin_sentry")])
	hit(c, c.player_states[0], c.enemy_states[0], 0.1, CardData.ActionType.MELEE, true)
	check(not c.enemy_states[0].alive, "哨兵穿甲即死")
	c = battle([owned("rusted_pickhand")], [owned("guard_remains")])
	hit(c, c.player_states[0], c.enemy_states[0], 0.1)
	check(c.enemy_states[0].squad_data.get_vitals_source_instance().get_base_stat_with_permanent_growth(OwnedCard.STAT_BASE_ARMOR) == 2 and is_equal_approx(c.enemy_states[0].current_armor, 1.9), "镐手命中永久基础减甲并即时扣当前甲")
	c = battle([owned("guard_remains"), owned("ghostface_beetle"), owned("guard_remains")], [owned("guard_remains")])
	hit(c, c.enemy_states[0], c.player_states[1], 100.0)
	check(c.player_states[0].get_max_health() == 4 and c.player_states[2].get_max_health() == 4, "鬼面虫遗愿为左右邻居加生命")
	c = battle([owned("mine_wailer"), owned("guard_remains")], [owned("guard_remains")])
	hit(c, c.enemy_states[0], c.player_states[0], 100.0)
	check(c.enemy_states[0].get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 2, "哀嚎者疲劳归最终击杀者")
	c.advance_time(1.0)
	check(c.enemy_states[0].current_health <= 0.0, "遗愿疲劳在30秒前按正式环境伤害每秒生效")
	c = battle([owned("mine_lamp_wisp")], [owned("guard_remains")])
	hit(c, c.enemy_states[0], c.player_states[0], 100.0)
	check(c.enemy_states[0].get_target_weight() == 16, "鬼火遗愿翻倍击杀者基础优先级")
	c.enemy_states[0].runtime_base_target_multiplier = 1024.0
	check(c.enemy_states[0].get_target_weight() == 99, "受击优先级封顶99")

func test_resources_and_equipment() -> void:
	var c := battle([owned("guard_remains")], [owned("gold_sprite")], [owned("light_element_shard"), owned("abandoned_toolbox")])
	c.execute_effect_mining(c.enemy_states[0], 2)
	check(c.twisted_vein.wallets == [0, 17], "NPC光碎晶奖励入NPC钱包")
	check(c.enemy_states[0].squad_data.get_equipped_item() != null, "NPC工具箱即时装备采集者")
	check(c.run_reward_ledger.get_total(BattleRunRewardLedger.KIND_OWNED_CARD_AWARD, 0) == 0, "NPC奖励不进入玩家收藏账本")
	c = battle([owned("guard_remains")], [owned("gold_sprite")], [owned("crystallized_remains")])
	c.execute_effect_mining(c.enemy_states[0], 1)
	check(c.enemy_resource_states.size() > 0 or not c._emblem_registrations.is_empty(), "NPC晶化残躯碎晶即时部署或纹章即时贴上")
	var holder := owned("guard_remains")
	var squad := SquadData.from_owned_card(holder)
	squad.equip_item(owned("dwarven_mining_helmet"))
	c = battle([holder], [owned("guard_remains")])
	c.player_states[0].squad_data.equip_item(squad.get_equipped_item())
	var target := c.player_states[0]
	var first := hit(c, c.enemy_states[0], target, 1, CardData.ActionType.RANGED)
	var second := hit(c, c.enemy_states[0], target, 1, CardData.ActionType.MAGIC)
	check(first.missed and second.missed, "矿工盔远程和法术各有独立免疫")
	var third := hit(c, c.enemy_states[0], target, 1, CardData.ActionType.RANGED)
	check(not third.missed and third.effective_amount == 1, "矿工盔同类型第二次承伤")
	var derived := hit(c, c.enemy_states[0], target, 0.2, CardData.ActionType.MAGIC, false, false)
	check(derived.effective_amount == 0.2, "矿工盔不抵消附加伤害")
	c = battle([owned("guard_remains"), owned("guard_remains")], [owned("guard_remains")], [owned("light_element_shard")])
	var lamp := owned("portable_mine_lamp")
	c.player_states[0].squad_data.equip_item(lamp)
	check(c.twisted_vein.has_lamp_aura(c.player_states[1]) and c.player_states[0].get_target_weight() == 9, "矿灯动态邻居光环及携带者优先级")
	var action := c._build_action(c.player_states[1], c.get_all_states(), CardData.ActionType.MELEE)
	check(action.resource_target == null, "矿灯邻居普通攻击排除资源")
	c.player_states[0].grant_runtime_keyword(&"silenced", 333)
	check(not c.twisted_vein.has_lamp_aura(c.player_states[1]) and c.player_states[0].get_target_weight() == 8, "矿灯来源失效立即撤销光环与优先级")
	c = battle([owned("guard_remains")], [owned("guard_remains")], [owned("light_element_shard")])
	c.player_states[0].squad_data.equip_item(owned("ghost_pick"))
	c._register_card_effects(c.player_states[0], c.player_states[0].squad_data.get_equipped_item().card_data, true)
	echo(c, c.player_states[0])
	check(c.twisted_vein.mining_events == 1 and c.twisted_vein.wallets[0] == 2, "幽魂矿镐回响附加开采一次无递归")

func test_spells() -> void:
	var c := battle([owned("gold_sprite"), owned("guard_remains")], [owned("guard_remains")], [owned("light_element_shard")], [owned("mine_collapse"), owned("soul_of_forging")])
	var resource: RefCounted = c.player_resource_states[0]
	var armor := c.player_states[1].current_armor
	c.execute_effect_mining(c.player_states[0], 1)
	check(c.twisted_vein.mineral_events == 1 and c.player_states[1].current_armor == armor + 2, "第一次双方开采触发锻造护甲")
	check(resource.revive(), "同一矿物资源正式复生")
	c.execute_effect_mining(c.player_states[0], 1)
	check(c.twisted_vein.mineral_events == 2 and c.player_states[1].current_armor == armor, "同资源复生再采计第二事件触发固定2坍塌伤害")
	check(c._processed_spell_event_ids.size() == 2, "锻造和坍塌各单场释放一次")
	c.execute_effect_mining(c.player_states[0], 1)
	check(c._processed_spell_event_ids.size() == 2, "后续开采不重复释放条件法术")
	c = battle([owned("guard_remains")], [owned("guard_remains")], [], [owned("giant_boulder")], {}, true)
	c.advance_time(8.8)
	check(c._elapsed_spell_attempted.size() == 1 and c.get_all_states().any(func(s: BattleSquadState): return not s.alive), "8秒落石通过真实弹道造成20×1.2魔法伤害")

func test_settlement() -> void:
	var collection := OwnedCardCollection.new()
	var spirit := collection.create_card(load("res://resources/cards/ember_spirit.tres"))
	spirit.rune_revealed.fill(true)
	spirit.resolved_runes.assign([1, 0, 0])
	var pouch := collection.create_card(load("res://resources/cards/crystal_shard_pouch.tres"))
	var spell := collection.create_card(load("res://resources/cards/soul_of_forging.tres"))
	var squad := SquadData.from_owned_card(spirit)
	squad.equip_item(pouch)
	var snapshot := BattlePreparationSnapshot.new()
	var spell_ids: Array[StringName] = [spell.instance_id]
	check(snapshot.initialize(&"settle_twisted", 7, collection, {&"player_front": [squad]}, spell_ids), "创建真实战前收藏快照")
	var c := battle([spirit], [owned("guard_remains")], [owned("light_element_shard")], [spell], {"player_gold": 10})
	c.battle_instance_id = &"settle_twisted"
	c.player_states[0].squad_data.equip_item(pouch)
	c._register_card_effects(c.player_states[0], pouch.card_data, true)
	echo(c, c.player_states[0])
	c.execute_effect_mining(c.player_states[0], 1)
	c.twisted_vein.finish(BattleController.Result.PLAYER_VICTORY)
	var rewards := RunRewardState.new()
	rewards.gold = 10
	var journal := RunSettlementJournal.new()
	var registry: Dictionary = {}
	for card: CardData in catalog: registry[card.id] = card
	var service := BattleSettlementService.new()
	var result := service.settle(snapshot, c.permanent_growth_ledger.get_entries(), c.run_reward_ledger.get_entries(), collection, rewards, journal, c.get_owned_card_change_entries_for_settlement(), registry)
	check(bool(result.get("success", false)), "矿脉永久事务正常提交：" + String(result.get("reason", "")))
	check(spirit.resolved_runes == [1, 0, 0] and pouch.equipment_durability == 9 and spell.spell_durability == 1, "临时转火不保存、装备耐久10→9和法术2→1跨战保存")
	check(rewards.mining_totals == [1, 0] and rewards.gold == 12, "正常提交双方累计与实际金币")
	result = service.settle(snapshot, c.permanent_growth_ledger.get_entries(), c.run_reward_ledger.get_entries(), collection, rewards, journal, c.get_owned_card_change_entries_for_settlement(), registry)
	check(result.status == BattleSettlementService.STATUS_ALREADY_COMMITTED and rewards.gold == 12 and pouch.equipment_durability == 9, "重复结算不重复扣耐久或发奖")
	var save := RunSaveService.new()
	var encoded := save._encode_collection_state(collection.capture_state())
	var decoded := save._decode_collection_state(encoded, registry)
	check(not decoded.is_empty(), "包含耐久和原符文的收藏可序列化解码")
	var saved_rewards := save._decode_reward_state(JSON.parse_string(JSON.stringify(rewards.capture_state())))
	var restored := RunRewardState.new()
	restored.restore_state(saved_rewards)
	check(restored.mining_totals == [1, 0], "双方本局开采计数存档恢复")
	check(snapshot.restore_collection(collection) and spirit.resolved_runes == [1, 0, 0] and pouch.equipment_durability == 10, "SL恢复战前符文与装备耐久")

func test_death_chains() -> void:
	var c := battle([owned("guard_remains"), owned("frenzied_gold_panner"), owned("guard_remains")], [owned("guard_remains")])
	var panner := c.player_states[1]
	c.twisted_vein.add_modifier(panner, BattleModifier.Stat.REINFORCEMENT, 4, &"test_pending_reinforcement")
	var expected := panner.get_display_action_value()
	var wishes: Array[BattleEffectEvent] = []
	c.effect_resolved.connect(func(e: BattleEffectEvent):
		if e.log_qualifier == "淘金者遗愿": wishes.append(e))
	hit(c, c.enemy_states[0], panner, 100)
	check(wishes.size() == 2 and wishes.all(func(e: BattleEffectEvent): return e.exact_amount == expected and not e.uses_attack_type_multiplier), "淘金者遗愿采用死亡前未用强化快照，左右各一次无类型伤害")
	c = battle([owned("minecart_soul"), owned("guard_remains")], [owned("guard_remains")], [], [], {}, true)
	var cart := c.player_states[0]
	c.twisted_vein.gain_health(c.enemy_states[0], 60, &"test_keep_target")
	c.twisted_vein.add_modifier(cart, BattleModifier.Stat.REINFORCEMENT, 6, &"test_pending_reinforcement")
	var cart_events: Array[BattleEffectEvent] = []
	c.projectile_launched.connect(func(e: BattleEffectEvent):
		if e.source == cart: cart_events.append(e))
	hit(c, c.enemy_states[0], cart, 100)
	check(cart_events.size() == 1 and cart_events[0].suppresses_echo and cart_events[0].formula.additive_terms.any(func(term: Dictionary): return term.name == "强化" and term.value == 6), "矿车遗愿真实发射一次、保留死亡公式强化且抑制回响")
	c.advance_time(0.8)
	check(cart_events[0].effective_amount > 0, "矿车死亡后遗愿弹道仍命中")
	c = battle([owned("clearing_machine"), owned("guard_remains")], [owned("guard_remains")], [owned("light_element_shard"), owned("wood_element_shard")], [], {}, true)
	c.twisted_vein.gain_health(c.enemy_states[0], 40, &"test_keep_target")
	var clearing: Array[BattleEffectEvent] = []
	c.projectile_launched.connect(func(e: BattleEffectEvent): clearing.append(e))
	hit(c, c.enemy_states[0], c.player_states[0], 100)
	check(clearing.size() == 2 and clearing[0].resource_target != clearing[1].resource_target, "清障机遗愿从死亡来源对两个不同资源发开采弹道")
	c.advance_time(1.5)
	var followups := clearing.filter(func(e: BattleEffectEvent): return e.origin_resource != null)
	check(followups.size() == 2 and followups.all(func(e: BattleEffectEvent): return e.formula.base_value == 2 and e.action_type == CardData.ActionType.MAGIC and e.effective_amount > 0), "每次成功开采各从原资源位置发一道基础2魔法弹道")
	c = battle([owned("clearing_machine"), owned("guard_remains")], [owned("guard_remains")], [owned("light_element_shard")], [], {}, true)
	var launches: Array[BattleEffectEvent] = []
	c.projectile_launched.connect(func(e: BattleEffectEvent): launches.append(e))
	hit(c, c.enemy_states[0], c.player_states[0], 100)
	c.player_resource_states[0].apply_damage(100)
	c.advance_time(0.8)
	check(launches.size() == 1 and c.twisted_vein.mining_events == 0, "清障机开采目标提前销毁不发后续伤害、不计成功开采")
	c = battle([owned("ember_residue"), owned("guard_remains")], [owned("guard_remains")], [], [], {}, true)
	c.twisted_vein.gain_health(c.enemy_states[0], 20, &"test_keep_target")
	var projectile: Array[BattleEffectEvent] = []
	var residue := c.player_states[0]
	c.projectile_launched.connect(func(e: BattleEffectEvent):
		if e.source == residue: projectile.append(e))
	c.execute_immediate_action(residue, CardData.ActionType.MAGIC)
	check(not residue.alive and projectile.size() == 1 and c.player_resource_states.size() + c.enemy_resource_states.size() == 1, "余烬回响自毁并只召唤一次碎晶，保留已发主弹道")
	c.advance_time(0.8)
	check(projectile[0].effective_amount > 0, "余烬已发主弹道在自毁后继续命中")
	c = battle([owned("crystal_shell_beetle")], [owned("guard_remains")])
	for side: String in ["player", "enemy"]:
		c.battle_resource_board.disabled_by_side[side] = ResourceHexLayout.valid_cells()
	hit(c, c.enemy_states[0], c.player_states[0], 20.0)
	check(c.player_resource_states.is_empty() and c.enemy_resource_states.is_empty(), "双方资源板均无合法位置时遗愿召唤失败且不补放")

func test_fatigue_boundaries() -> void:
	var c := battle([owned("mine_wailer"), owned("guard_remains")], [owned("guard_remains")])
	var killer := c.enemy_states[0]
	c.twisted_vein.gain_health(killer, 90, &"test_keep_target")
	c.twisted_vein.gain_health(c.player_states[1], 90, &"test_keep_target")
	hit(c, killer, c.player_states[0], 100)
	killer.moon_shadowed = true
	var health := killer.current_health
	c.advance_time(2.0)
	check(killer.current_health == health, "放逐暂停卡牌疲劳承伤")
	killer.moon_shadowed = false
	c.advance_time(0.9)
	check(killer.current_health == health, "解除放逐保留疲劳剩余计时")
	c.advance_time(0.1)
	check(killer.current_health == health - 2, "恢复后疲劳每秒按2层扣生命")
	c.advance_time(27.0)
	check(killer.get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 2, "30秒风暴不叠卡牌疲劳层")
	var storm_events: Array[BattleEffectEvent] = []
	c.effect_resolved.connect(func(e: BattleEffectEvent):
		if e.log_qualifier == "疲劳风暴": storm_events.append(e))
	c.advance_time(2.0)
	check(storm_events.size() == 4 and storm_events[0].exact_amount == 1 and storm_events[-1].exact_amount == 2, "风暴31秒1点、32秒2点，双方各一次")
	c = battle([owned("guard_remains")], [owned("crystal_skin_sentry")])
	var sentinel := c.enemy_states[0]
	var e := c.twisted_vein.make_event(null, sentinel, 2, CardData.ActionType.MELEE, false, "环境")
	e.is_environment_damage = true
	e.pierces_armor = true
	c.launch_content_effect(e, false)
	check(e.effective_amount == 1 and sentinel.alive and sentinel.current_armor == 2, "哨兵环境穿甲伤害封顶1且不触发攻击穿甲即死")

func test_consumption_series() -> void:
	var collection := OwnedCardCollection.new()
	var holder := collection.create_card(load("res://resources/cards/guard_remains.tres"))
	var pouch := collection.create_card(load("res://resources/cards/crystal_shard_pouch.tres"))
	var spell := collection.create_card(load("res://resources/cards/soul_of_forging.tres"))
	var rewards := RunRewardState.new()
	var journal := RunSettlementJournal.new()
	var service := BattleSettlementService.new()
	var registry: Dictionary = {}
	for card: CardData in catalog: registry[card.id] = card
	for index: int in 10:
		var squad := SquadData.from_owned_card(holder)
		squad.equip_item(pouch)
		var snapshot := BattlePreparationSnapshot.new()
		var prepared: Array[StringName] = []
		if index < 2: prepared.append(spell.instance_id)
		var id := StringName("durability_series:%d" % index)
		check(snapshot.initialize(id, index, collection, {&"player_front": [squad]}, prepared), "连续战斗%d战前快照" % index)
		var spells: Array[OwnedCard] = []
		if index < 2: spells.append(spell)
		var c := battle([holder], [owned("guard_remains")], [owned("light_element_shard")], spells)
		c.battle_instance_id = id
		c.player_states[0].squad_data.equip_item(pouch)
		c._register_card_effects(c.player_states[0], pouch.card_data, true)
		c.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.RUSH, {"actor": c.player_states[0]})
		c.effect_runtime.process_due(0)
		check(c.twisted_vein.mining_events == 0, "小包收获不生成开采事件")
		c.execute_effect_mining(c.player_states[0], 1)
		c.twisted_vein.finish(BattleController.Result.PLAYER_VICTORY)
		var result := service.settle(snapshot, c.permanent_growth_ledger.get_entries(), c.run_reward_ledger.get_entries(), collection, rewards, journal, c.get_owned_card_change_entries_for_settlement(), registry)
		check(bool(result.get("success", false)) and pouch.equipment_durability == 9 - index, "小包跨战斗逐次消耗%d→%d" % [10-index,9-index])
		if index == 1: check(collection.get_by_instance_id(spell.instance_id) == null, "锻造之魂跨战斗第二次释放后从收藏消耗")
	check(collection.get_by_instance_id(pouch.instance_id) == null, "小包第10场结算后从收藏消耗")

func test_passive_boundaries() -> void:
	var c := battle([owned("rusted_pickhand")], [owned("mine_lamp_wisp")])
	var target := c.enemy_states[0]
	c.twisted_vein.gain_health(target, 40, &"test_keep_target")
	target.apply_armor_exact(5)
	var armor_before := target.current_armor
	hit(c, c.player_states[0], target, 0.1)
	check(target.squad_data.get_vitals_source_instance().get_base_stat_with_permanent_growth(OwnedCard.STAT_BASE_ARMOR) == 0 and is_equal_approx(target.current_armor, armor_before - 1.1), "镐手在基础甲0时仍扣当前甲1且永久甲不为负")
	c = battle([owned("guard_remains"), owned("guard_remains"), owned("guard_remains")], [owned("guard_remains")])
	var holder := c.player_states[0]
	holder.squad_data.equip_item(owned("portable_mine_lamp"))
	var neighbor := c.player_states[1]
	var unit := neighbor.squad_data.get_effect_source_instance()
	unit.set_wound_slot(0, {"instance_id": &"lamp_blindness", "wound_id": &"致盲Ⅰ"})
	neighbor._load_owned_card_injuries()
	var bonus_count := 0
	for _index: int in 40:
		var roll := c._roll_action_blindness(neighbor)
		check(not roll.failed, "矿灯邻居免疫致盲行动落空")
		if int(roll.reinforcement) > 0: bonus_count += 1
	check(bonus_count > 0, "矿灯免疫降低命中率仍保留致盲成功掷骰的强化")
	hit(c, c.enemy_states[0], neighbor, 100)
	check(c.twisted_vein.has_lamp_aura(c.player_states[2]), "原邻居退场后矿灯光环动态覆盖新的相邻友军")
	var sentry := owned("crystal_skin_sentry")
	c = battle([owned("guard_remains")], [sentry])
	c.enemy_states[0].grant_runtime_keyword(&"silenced", 992)
	var e := hit(c, c.player_states[0], c.enemy_states[0], 1.5)
	check(e.effective_amount == 1.5 and not c.enemy_states[0].permanently_destroyed, "哨兵沉默后不应用伤害上限或销毁效果")

func test_economy_settlement_boundaries() -> void:
	var c := battle([owned("guard_remains"), owned("greedy_acolyte")], [owned("guard_remains")], [], [], {"player_gold": 1})
	var collector := c.player_states[0]
	var owner := BattleEffectOwnerRef.for_state(collector, BattleEffectDefinition.OwnerKind.OWNING_PLAYER)
	c.record_pending_run_reward(owner, BattleRunRewardLedger.KIND_GOLD_DELTA, 2, &"loss_to_zero", collector.runtime_id, 0, {"gold_delta": -2})
	check(c.twisted_vein.wallets[0] == 0 and c.run_reward_ledger.get_entries()[-1].parameters.gold_delta == -1, "失去金币仅扣实际余额，并按实际扣款记账")
	var before_entries := c.run_reward_ledger.get_entries().size()
	c.record_pending_run_reward(owner, BattleRunRewardLedger.KIND_GOLD_DELTA, 2, &"no_loss_at_zero", collector.runtime_id, 1, {"gold_delta": -2})
	check(c.twisted_vein.wallets[0] == 0 and c.run_reward_ledger.get_entries().size() == before_entries, "余额0时无额外扣款或赚金币事件")
	var found_highest := false
	for index: int in 500:
		var start := c.run_reward_ledger.get_entries().size()
		var wallet_before := c.twisted_vein.wallets[0]
		c.resolve_direct_shard_harvest(collector, load("res://resources/cards/rainbow_gold_ore.tres"))
		var entries := c.run_reward_ledger.get_entries().slice(start)
		if entries.size() == 2 and int(entries[-1].parameters.get("roll_total", 0)) == 20:
			check(entries[0].amount == 1 and entries[-1].amount == 20 and c.twisted_vein.wallets[0] == wallet_before + 21, "彩金矿2d10实际20仅基础1加最高20，不叠加5或10")
			found_highest = true
			break
	check(found_highest, "固定真实随机流覆盖彩金最高档")
	for outcome: int in [BattleController.Result.PLAYER_VICTORY, BattleController.Result.PLAYER_DEFEAT]:
		var collection := OwnedCardCollection.new()
		var player := collection.create_card(load("res://resources/cards/guard_remains.tres"))
		var snapshot := BattlePreparationSnapshot.new()
		var id := StringName("theft_settle:%d" % outcome)
		snapshot.initialize(id, 7039, collection, {&"player_front": [SquadData.from_owned_card(player)]})
		c = battle([player], [owned("miser")], [], [], {"player_gold": 5})
		c.battle_instance_id = id
		echo(c, c.enemy_states[0])
		c.twisted_vein.finish(outcome)
		var rewards := RunRewardState.new()
		rewards.gold = 5
		var result := BattleSettlementService.new().settle(snapshot, c.permanent_growth_ledger.get_entries(), c.run_reward_ledger.get_entries(), collection, rewards, RunSettlementJournal.new(), c.get_owned_card_change_entries_for_settlement())
		check(bool(result.get("success", false)) and rewards.gold == (5 if outcome == BattleController.Result.PLAYER_VICTORY else 3), "真实结算胜战返偷款、败战保留损失：%d" % outcome)
	c = battle([owned("guard_remains")], [owned("guard_remains"), owned("guard_remains")])
	var first := c.enemy_states[0]
	first.squad_data.equip_item(owned("mining_pick"))
	check(c.equip_npc_reward(first, load("res://resources/cards/crystal_shard_pouch.tres")) and c.enemy_states[1].squad_data.get_equipped_item().card_data.id == &"crystal_shard_pouch", "NPC收获者已装备时改装备到另一合法己方")
	check(not c.equip_npc_reward(first, load("res://resources/cards/mining_pick.tres")), "NPC全员已有装备时奖励不替换或挤出原物品")
	check(c.twisted_vein.mining_events == 0 and c.permanent_growth_ledger.get_entries().is_empty(), "战中装备小包不自动触发突击收获")

func test_npc_mining_commit() -> void:
	var collection := OwnedCardCollection.new()
	var player := collection.create_card(load("res://resources/cards/guard_remains.tres"))
	var snapshot := BattlePreparationSnapshot.new()
	snapshot.initialize(&"npc_mining_commit", 21, collection, {&"player_front": [SquadData.from_owned_card(player)]})
	var c := battle([player], [owned("gold_sprite")], [owned("light_element_shard")])
	c.battle_instance_id = &"npc_mining_commit"
	c.execute_effect_mining(c.enemy_states[0], 1)
	var rewards := RunRewardState.new()
	rewards.gold = 11
	var service := BattleSettlementService.new()
	var result := service.settle(snapshot, c.permanent_growth_ledger.get_entries(), c.run_reward_ledger.get_entries(), collection, rewards, RunSettlementJournal.new(), c.get_owned_card_change_entries_for_settlement())
	check(bool(result.get("success", false)) and rewards.mining_totals == [0,1] and rewards.gold == 11, "NPC开采累计正式提交，NPC金币不进入玩家经济")
	var invalid := c.run_reward_ledger.get_entries()
	invalid[0]["amount"] = -1
	result = service.settle(snapshot, [], invalid, collection, rewards, RunSettlementJournal.new())
	check(not bool(result.get("success", false)) and rewards.mining_totals == [0,1] and rewards.gold == 11, "拒绝非法NPC开采账本且整个经济状态保持不变")

func test_last_unit_death_projectiles() -> void:
	for id: String in ["minecart_soul", "clearing_machine", "ember_residue"]:
		var resources: Array[OwnedCard] = []
		if id == "clearing_machine": resources.assign([owned("light_element_shard"), owned("wood_element_shard")])
		var c := battle([owned(id)], [owned("guard_remains")], resources, [], {}, true)
		c.twisted_vein.gain_health(c.enemy_states[0], 40, &"test_keep_target")
		var launches: Array[BattleEffectEvent] = []
		c.projectile_launched.connect(func(e: BattleEffectEvent): launches.append(e))
		if id == "ember_residue": c.execute_immediate_action(c.player_states[0], CardData.ActionType.MAGIC)
		else: hit(c, c.enemy_states[0], c.player_states[0], 100)
		c._check_battle_result()
		check(c.current_result == BattleController.Result.NONE and launches.any(func(e: BattleEffectEvent): return e.waits_for_death_chain), "最后一张%s退场暂缓胜负直到遗愿／明确保留弹道完成" % id)
		c.advance_time(1.5)
		check(launches.any(func(e: BattleEffectEvent): return e.target != null and e.effective_amount > 0) and c.current_result == BattleController.Result.PLAYER_DEFEAT, "最后一张%s先实际命中再完成胜负判定" % id)

func test_area_death_order() -> void:
	var c := battle([owned("gold_sprite"), owned("guard_remains"), owned("guard_remains")], [owned("frenzied_gold_panner"), owned("guard_remains")], [owned("light_element_shard")], [owned("mine_collapse")])
	var resource: RefCounted = c.player_resource_states[0]
	c.execute_effect_mining(c.player_states[0], 1)
	resource.revive()
	c.enemy_states[0].current_health = 1
	c.enemy_states[0].current_armor = 0
	var order: Array[String] = []
	c.effect_resolved.connect(func(e: BattleEffectEvent):
		if e.log_qualifier == "矿道坍塌": order.append("damage"))
	c.squad_defeated.connect(func(_state: BattleSquadState): order.append("death"))
	c.execute_effect_mining(c.player_states[0], 1)
	check(order.count("damage") == 5 and order.find("death") == 5, "坍塌先完成双方全部5个独立伤害事件再执行死亡遗愿连锁")

func test_timed_content_sleep() -> void:
	var c := battle([owned("greedy_acolyte"), owned("guard_remains")], [owned("guard_remains")])
	var acolyte := c.player_states[0]
	var guard := c.player_states[1]
	check(acolyte.is_sleeping(29.999) and guard.is_sleeping(29.999), "30秒前保持初始休眠")
	check(not acolyte.is_sleeping(30.0) and not guard.is_sleeping(30.0), "信徒与残骸30秒自动唤醒")
	c = battle([owned("guard_remains")], [owned("guard_remains")])
	c.elapsed_seconds = 12.0
	var summoned := c.summon_content_minion(c.player_states[0], load("res://resources/cards/guard_remains.tres"))
	check(summoned.is_sleeping(41.999) and not summoned.is_sleeping(42.0), "战中召唤残骸从入场时计30秒")
	c = battle([owned("guard_remains")], [owned("guard_remains")], [owned("light_element_shard")])
	guard = c.player_states[0]
	guard.apply_sleep(&"independent_sleep", 4.0)
	c.execute_effect_mining(guard, 1)
	check(not guard.sleep_source_until.has(BattleSquadState.INITIAL_CONTENT_SLEEP_SOURCE) and guard.is_sleeping(0.0), "开采仅移除残骸初始休眠，保留其他来源")
	check(not guard.is_sleeping(4.0), "残骸其他休眠到期后唤醒")
	c = battle([owned("greedy_acolyte"), owned("guard_remains")], [owned("guard_remains")])
	for unit: BattleSquadState in c.get_all_states(): c.twisted_vein.gain_health(unit, 100, &"test_survival")
	var before := c.player_states[0].remaining_cooldown
	c.advance_time(29.5)
	check(c.player_states[0].remaining_cooldown == before, "真实战斗推进中休眠暂停冷却")
	c.advance_time(1.0)
	check(is_equal_approx(c.player_states[0].remaining_cooldown, before - 0.5), "30秒到期后仅推进醒来后的冷却")

func test_spirit_stack() -> void:
	var spirit := owned("ember_spirit", true)
	var other := owned("guard_remains", true)
	spirit.resolved_runes.fill(CardData.ElementType.FIRE)
	other.resolved_runes.fill(CardData.ElementType.WATER)
	var squad := SquadData.from_cards([spirit.get_battlefield_card(), other.get_battlefield_card()])
	squad.bind_owned_card(spirit.get_battlefield_card(), spirit)
	squad.bind_owned_card(other.get_battlefield_card(), other)
	var c := battle([spirit], [owned("guard_remains")])
	c.clear_battle()
	c.start_battle([{"squad_data": squad, "row_key": &"player_front", "formation_index": 0}], formation([owned("guard_remains")], 1), 7041, false, &"spirit_stack", [], [], [], [], catalog)
	var state := c.player_states[0]
	check(state.runtime_rune_overrides.size() == 2 and state.get_active_rune_slots().all(func(slot: Dictionary): return slot.element == CardData.ElementType.FIRE), "余火突击可转换下层其他卡的两枚显现非火符文")
	check(other.resolved_runes == [1, 1, 1] and c.owned_card_change_ledger.get_entries().is_empty(), "其他成员底层原符文不变，遮挡槽也不被改写")
