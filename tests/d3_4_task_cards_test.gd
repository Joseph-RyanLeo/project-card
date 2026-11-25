extends SceneTree

var checks := 0
var failures := 0
var sequence := 0
var current: BattleController


func _initialize() -> void: _run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func owned(id: String) -> OwnedCard:
	sequence += 1
	var card := OwnedCard.new()
	card.initialize(load("res://resources/cards/%s.tres" % id), StringName("task_unit_%d" % sequence), 0)
	return card


func squad(card: OwnedCard, item: OwnedCard = null) -> SquadData:
	var result := SquadData.from_owned_card(card)
	if item != null: check(result.equip_item(item), "装备青灯到真实小队")
	return result


func formation(squads: Array[SquadData], side: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in squads.size(): result.append({"squad_data": squads[index], "row_key": &"player_front" if side == 0 else &"enemy_front", "formation_index": index})
	return result


func battle(player: Array[SquadData], enemy: Array[SquadData], deaths: int = 0, talents: Array = []) -> BattleController:
	if current != null: current.clear_battle(); current.free()
	var config := MazeRewardService.new()
	config.load_config()
	var context := {"level": 7, "talents": talents, "sentries": [], "rules": config.config}
	current = BattleController.new()
	root.add_child(current)
	current.start_battle(formation(player, 0), formation(enemy, 1), 20261105, false, StringName("task_cards_%d" % sequence), [], [], [], [], [], [], context, {"ally_deaths": deaths})
	return current


func kill(target: BattleSquadState, source: BattleSquadState) -> void:
	var event := current.twisted_vein.make_event(source, target, 9999, CardData.ActionType.MAGIC, false, "致命伤害边界夹具")
	current.launch_content_effect(event, false)


func _run() -> void:
	var item := owned("extinguished_lantern")
	var wearer := owned("ironhand_arno")
	var c := battle([squad(wearer, item)], [squad(owned("golden_golem"))])
	check(c.effect_catalog.is_valid(), "新增任务效果定义通过正式解析器")
	var state := c.player_states[0]
	var enemy := c.enemy_states[0]
	var before: float = enemy.current_health + enemy.current_armor
	for index: int in 9:
		c.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": state, "action": {}})
		c.effect_runtime.process_due(c.elapsed_seconds)
	check(item.card_data.id == &"extinguished_lantern" and int(item.progress_by_source.get(&"task_lantern_triggers", 0)) == 9, "9次回响尚未变形")
	c.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": state, "action": {}})
	c.effect_runtime.process_due(c.elapsed_seconds)
	check(item.card_data.id == &"flickering_lantern", "第10次实际回响变为摇曳青灯")
	check(is_equal_approx(before - enemy.current_health - enemy.current_armor, 10.0), "熄灭青灯每次对敌军造成1点伤害")
	var collection := OwnedCardCollection.new()
	collection.add_existing(item)
	check(c.task_cards.commit_to_collection(collection), "青灯变形可通过结算提交到原装备实例")
	for index: int in 4:
		var left := owned("militia")
		var right := owned("militia")
		c = battle([squad(left), squad(owned("shieldwall_private"), item), squad(right)], [squad(owned("golden_golem"))])
		state = c.player_states[1]
		kill(state, c.enemy_states[0])
		var growth: Array = c.permanent_growth_ledger.get_entries()
		check(growth.size() == 2 and growth.all(func(entry: Dictionary): return entry.stat == OwnedCard.STAT_BONUS_MAX_HEALTH and entry.amount == 2), "摇曳遗愿为左右相邻友军各永久最大生命+2")
		var ally: BattleSquadState = c.player_states[0]
		check(ally.get_max_health() == 4 and ally.current_health == 4 and ally.get_display_base_stats(ally.get_active_rune_slots()).y == 2, "摇曳青灯即时增加上限和当前，不改基础白字")
		check(c.task_cards.commit_to_collection(collection), "跨战斗保留青灯遗愿进度")
	check(item.card_data.id == &"blazing_lantern" and item.card_data.equipment_action_delta == 1 and item.card_data.equipment_zeal_delta == 2, "4次遗愿后变为炽烈青灯并读取正式属性")
	c = battle([squad(owned("militia"), item)], [squad(owned("golden_golem")), squad(owned("golden_golem"))], 5)
	before = 0
	for target: BattleSquadState in c.enemy_states: before += target.current_health + target.current_armor
	kill(c.player_states[0], c.enemy_states[0])
	var after := 0.0
	for target: BattleSquadState in c.enemy_states: after += target.current_health + target.current_armor
	check(is_equal_approx(before - after, 6.0), "炽烈青灯把含本次阵亡的6点总伤害随机分配给敌方")
	# 尘灰同时覆盖左侧单卡与右侧展开双卡，检查死亡、伤势和永久纹章账本。
	var left := owned("militia")
	left.set_wound_slot(0, {"instance_id": "fixture_wound", "wound_id": "骨折Ⅰ"})
	var stacked := squad(owned("militia"))
	var extra := owned("musketeer")
	stacked.insert_card(extra.get_battlefield_card(), 1, SquadData.TwoCardLayout.EXPANDED)
	stacked.bind_owned_card(extra.get_battlefield_card(), extra)
	c = battle([squad(left), squad(owned("edwin_ash")), stacked], [squad(owned("golden_golem"))])
	check(not c.player_states[0].alive and not c.player_states[2].alive and c.player_states[1].alive, "尘灰牺牲左右单卡／小队，自身保留")
	check(left.wound_slots[0].is_empty(), "尘灰治愈相邻友军一处旧伤势")
	var changes := c.get_owned_card_change_entries_for_settlement()
	check(changes.filter(func(entry: Dictionary): return entry.kind == BattleOwnedCardChangeLedger.KIND_SET_EMBLEM_SLOT).size() == 2, "尘灰为两侧友军各登记一枚永久随机纹章")
	# 孤星耀开局触发、全伤害免疫、到期恢复受伤；不改变控制／放逐语义。
	c = battle([squad(owned("musketeer"))], [squad(owned("golden_golem"))], 0, ["lone_star"])
	state = c.player_states[0]
	check(c.hero_runtime._lone_star_used and c.hero_runtime.lone_star_immune(state), "孤星耀对开局唯一小队立即生效")
	before = state.current_health + state.current_armor
	kill(state, c.enemy_states[0])
	check(state.alive and is_equal_approx(before, state.current_health + state.current_armor), "孤星耀5秒内免疫致命伤害")
	c.elapsed_seconds = 5.0
	kill(state, c.enemy_states[0])
	check(not state.alive, "孤星耀5秒届满后正常受伤且不再触发")
	current.clear_battle()
	current.free()
	print("D3-4 task cards: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
