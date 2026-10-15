extends SceneTree

## 实际伤害写入到死亡确认之间，中毒计时不能阻塞下一次弹道／行动。
var failures := 0
var assertions := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error(message)
func _run() -> void:
	var definition := load("res://resources/cards/militia.tres") as CardData
	var owned := OwnedCard.new()
	owned.initialize(definition, &"poison_pending_death", 0)
	owned.wound_slots[0] = {"wound_id": &"中毒Ⅰ", "level": 1}
	var controller := BattleController.new()
	root.add_child(controller)
	controller.start_battle(
		[{"squad_data": SquadData.from_card(definition), "row_key": &"player_front", "formation_index": 0}],
		[{"squad_data": SquadData.from_owned_card(owned), "row_key": &"enemy_front", "formation_index": 0}],
		71428, false
	)
	var target := controller.enemy_states[0]
	check(controller._wound_periodic_effects.size() == 1, "正式中毒伤势注册周期计时")
	controller._decrease_living_cooldowns(2.0)
	controller.elapsed_seconds = 2.0
	check(is_zero_approx(controller._get_next_event_delay()), "存活单位到期中毒进入调度")
	# 单位状态先写入真实伤害，控制器随后才完成遗愿／死亡链，alive此刻仍为true。
	target.apply_damage_exact(target.current_health, null, null, true)
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	check(target.alive and is_zero_approx(target.current_health), "生命归零与正式阵亡是两个结算步骤")
	check(controller._get_next_event_delay() > 0.0, "零生命单位的到期中毒不占用下一事件时刻")
	target.apply_damage_exact(1.0, null, null, true)
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	check(target.alive and target.current_health < 0.0, "溢出伤害产生等待死亡确认的负生命单位")
	check(controller._get_next_event_delay() > 0.0, "负生命单位的到期中毒不阻塞战斗推进")
	var health := target.current_health
	controller._collect_due_wound_periodic_events()
	check(target.current_health == health, "待死亡单位不再追加中毒伤害")
	# 若在死亡确认前由明确效果恢复生命，原中毒仍能按其现有时钟结算。
	target.apply_healing_exact(float(target.get_max_health()) + 1.0)
	check(target.current_health > 0.0 and is_zero_approx(controller._get_next_event_delay()), "恢复生命后保留到期中毒计时")
	controller._collect_due_wound_periodic_events()
	check(float(controller._wound_periodic_effects[0].next_time) == 4.0, "恢复后的中毒正常结算并安排下一跳")
	controller.queue_free()
	await process_frame
	print("致命伤中毒调度：%d项，%d失败" % [assertions, failures])
	quit(failures)
