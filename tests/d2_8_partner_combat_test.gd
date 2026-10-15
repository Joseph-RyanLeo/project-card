extends SceneTree

const Controller = preload("res://scripts/battle/battle_controller.gd")
const SquadScene = preload("res://scenes/ui/BoardSlot.tscn")
var assertions: int = 0
var failures: int = 0
var controller: BattleController
var captured: Array[BattleEffectEvent] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func card(id: String) -> CardData:
	var definition := load("res://resources/cards/%s.tres" % id).duplicate(true) as CardData
	definition.runes.clear()
	definition.cooldown_seconds = 99.0
	return definition

func entry(definition: CardData, row: StringName, index: int) -> Dictionary:
	return {"squad_data": SquadData.from_card(definition), "row_key": row, "formation_index": index}

func _run() -> void:
	controller = Controller.new()
	root.add_child(controller)
	controller.effect_resolved.connect(func(event: BattleEffectEvent) -> void: captured.append(event))
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/demo2/ioann_warden_config.json"))
	controller.start_battle([entry(card("shieldwall_private"), &"player_front", 0)], [entry(card("heavy_knight"), &"enemy_front", 0)], 18181, false, &"feedback_combat", [], [], [], [], [], [], {"level": 4, "talents": ["sentry_guard", "sentry_break", "sentry_needle"], "sentries": [{"instance_id": "test_front", "visual_variant": 0, "region": "front", "remaining": 20, "capacity": 20}], "rules": rules})
	var armor_event: BattleEffectEvent
	for event: BattleEffectEvent in captured:
		if event.log_qualifier == "哨位：护": armor_event = event
	check(armor_event != null and armor_event.effective_amount == 4.0, "护天赋真实提供4护甲")
	if armor_event != null:
		var log := BattleLogEntry.new()
		log.add_event(armor_event)
		check(log.to_bbcode().contains("哨位：护") and log.to_bbcode().contains("4点"), "护甲提供量进入结构化日志")
	var target: BattleSquadState = controller.player_states[0]
	var enemy: BattleSquadState = controller.enemy_states[0]
	var hit := BattleEffectEvent.new()
	hit.group_id = 91
	hit.source = enemy
	hit.target = target
	hit.exact_amount = 3.0
	hit.action_type = CardData.ActionType.MELEE
	hit.formula = BattleFormulaData.create("伤害", hit.action_type, 3.0, 1.0, 1.0, enemy, target)
	controller._apply_effect_event(hit)
	check(hit.sentry_absorbed == 1.0 and hit.sentry_remaining == 19.0 and hit.exact_amount == 2.0, "哨位分担后记录剩余伤害和容量")
	var absorb_log := BattleLogEntry.new()
	absorb_log.add_event(hit)
	check(absorb_log.to_bbcode().contains("前排哨位") and absorb_log.to_bbcode().contains("吸收1点伤害") and absorb_log.to_bbcode().contains("剩余容量19"), "哨位吸收日志包含区域、受保护者、吸收量和剩余容量")
	var needle: BattleEffectEvent
	for event: BattleEffectEvent in captured:
		if event.log_qualifier.contains("针刺"): needle = event
	check(needle != null and needle.effective_amount == 1.0 and needle.group_id > 0, "针刺反弹生成独立真实伤害日志组")
	controller.hero_runtime.process_due(4.0)
	var break_event: BattleEffectEvent
	for event: BattleEffectEvent in captured:
		if event.log_qualifier == "哨位：破": break_event = event
	check(break_event != null and break_event.effective_amount > 0.0, "破天赋造成真实远程伤害并发出日志")

	enemy.clear_battle_statistics()
	controller._emit_wound_damage(enemy, target, 2.0, &"中毒Ⅰ", &"wound_poison_action", 92, true)
	check(enemy.battle_damage_dealt_by_action.get(&"poison", 0.0) == 2.0 and not enemy.battle_damage_dealt_by_action.has(CardData.ActionType.MELEE), "中毒附伤按中毒独立统计，不归入近战")
	var slot: BoardSlot = SquadScene.instantiate()
	slot.set_squad_data(enemy.squad_data)
	root.add_child(slot)
	await process_frame
	slot.show_battle_result_statistics(enemy.get_battle_statistics(), false, enemy.get_effective_action_type())
	var has_poison := false
	for stat: Dictionary in slot._get_visible_battle_result_entries():
		if stat.kind == &"poison_damage":
			has_poison = stat.texture == StatusIndicatorStyle.get_texture(CardSlotLayout.Kind.WOUND, &"中毒Ⅰ") and stat.value == 2.0
	check(has_poison, "结算中毒伤害显示原中毒伤势图标")
	slot.queue_free()
	controller.clear_battle()
	captured.clear()

	# 平衡更新：只有开场乡邻开采，金币仍为1，旧生命光环移除。
	var left := card("shieldwall_private")
	var mule := card("baggage_muleteer")
	var right := card("shieldwall_private")
	var resource := OwnedCard.new()
	resource.initialize(load("res://resources/cards/water_element_shard.tres"), &"feedback_mule_resource", 0)
	controller.use_projectile_timing = false
	controller.start_battle([entry(left, &"player_front", 0), entry(mule, &"player_front", 1), entry(right, &"player_front", 2)], [entry(card("heavy_knight"), &"enemy_front", 0)], 17171, false, &"feedback_mule", [], [], [resource])
	check(controller.run_reward_ledger.get_total(BattleRunRewardLedger.KIND_GOLD, BattleSquadState.Side.PLAYER) == 1, "辎重驮夫突击只获得1金币")
	check(controller.player_states[0].get_max_health() == left.max_health and controller.player_states[2].get_max_health() == right.max_health, "乡邻不再给左右友军旧生命加成")
	check(controller.twisted_vein.mining_events == 1, "开场乡邻成立成功开采一次")
	controller.player_states[2].alive = false
	controller.effect_runtime.recheck_continuous_conditions()
	controller.effect_runtime.process_due(0.0)
	controller.player_states[2].alive = true
	controller.effect_runtime.recheck_continuous_conditions()
	controller.effect_runtime.process_due(0.0)
	check(controller.twisted_vein.mining_events == 1, "乡邻战中恢复不重新触发开采")
	controller.clear_battle()
	controller.queue_free()
	await process_frame
	print("合作伙伴战斗反馈专项：%d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
