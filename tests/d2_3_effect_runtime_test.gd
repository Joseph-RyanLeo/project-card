extends SceneTree

## D2-3 通用效果运行时测试：只使用真实类型与执行器，不使用 mock。

const EFFECT_DATA_PATH := "res://data/demo2/ash_ledger_effect_samples.json"
const BattleControllerScript = preload("res://scripts/battle/battle_controller.gd")
const CardViewScript = preload("res://scripts/ui/card_view.gd")

var failures: int = 0
var _card_serial: int = 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_effect_schema_import()
	_test_event_queue_and_causal_chain()
	_test_seeded_target_and_preapply_revalidation()
	_test_same_name_takeover_and_battle_cleanup()
	_test_timed_action_and_condition_lifecycles()
	_test_refresh_and_capped_stacking()
	_test_shared_group_limit_and_recursion_guard()
	_test_zeal_speed_and_progress_preservation()
	_test_modifier_order_in_real_action()
	_test_scheduled_trigger()
	_test_runtime_clock_determinism()
	if failures == 0:
		print("D2-3 effect runtime checks passed.")
	else:
		push_error("D2-3 effect runtime checks failed: %d" % failures)
	quit(failures)


func _test_effect_schema_import() -> void:
	var catalog := BattleEffectCatalog.load_from_file(EFFECT_DATA_PATH)
	_expect(catalog.is_valid(), "38条活动效果全部转换为严格类型")
	_expect(catalog.definitions.size() == 38, "严格效果目录保持38条活动效果")
	var zeal := catalog.get_definition(&"anvil_margaret.effect.02")
	_expect(
		zeal != null
		and zeal.trigger == BattleEffectDefinition.Trigger.CONTINUOUS
		and zeal.operation == BattleEffectDefinition.Operation.ADD_ZEAL
		and zeal.value.kind == BattleEffectValue.Kind.FIXED
		and is_equal_approx(zeal.value.amount, -4.0)
		and zeal.duration.kind == BattleEffectDuration.Kind.WHILE_ACTIVE
		and zeal.stacking.kind == BattleEffectStacking.Kind.SAME_NAME_NONSTACKING,
		"热诚效果不再依赖自由文本字段"
	)
	if not catalog.errors.is_empty():
		for error: String in catalog.errors:
			push_error(error)


func _test_event_queue_and_causal_chain() -> void:
	var queue := BattleEventQueue.new()
	var root_event := BattleRuntimeEvent.new()
	root_event.kind = BattleRuntimeEvent.Kind.TRIGGER
	root_event.logical_time_us = BattleEventQueue.seconds_to_us(1.25)
	root_event.priority = BattleRuntimeEvent.Priority.TRIGGER
	queue.schedule(root_event)

	var late_child := BattleRuntimeEvent.new()
	late_child.kind = BattleRuntimeEvent.Kind.APPLY_OPERATION
	late_child.logical_time_us = root_event.logical_time_us
	late_child.priority = BattleRuntimeEvent.Priority.EXECUTE
	queue.schedule(late_child, root_event)
	var early_child := BattleRuntimeEvent.new()
	early_child.kind = BattleRuntimeEvent.Kind.APPLY_OPERATION
	early_child.logical_time_us = root_event.logical_time_us
	early_child.priority = BattleRuntimeEvent.Priority.PRE_APPLY
	queue.schedule(early_child, root_event)

	var due := queue.pop_due(root_event.logical_time_us)
	_expect(
		due.size() == 3
		and due[0] == early_child
		and due[1] == root_event
		and due[2] == late_child,
		"同刻事件按优先级与稳定序号排序"
	)
	_expect(
		early_child.parent_event_id == root_event.event_id
		and early_child.root_event_id == root_event.event_id
		and late_child.parent_event_id == root_event.event_id,
		"子事件保存父事件与根事件因果链"
	)
	_expect(
		BattleEventQueue.seconds_to_us(0.123456) == 123456
		and is_equal_approx(BattleEventQueue.us_to_seconds(123456), 0.123456),
		"逻辑时间使用整数微秒往返"
	)


func _test_seeded_target_and_preapply_revalidation() -> void:
	var first := _make_controller(32001, 3)
	var second := _make_controller(32001, 3)
	var definition := _synthetic_definition(
		"synthetic.seeded",
		"battlecry",
		["always", "target_has_armor"],
		"all_friendly_combat_units",
		"add_zeal",
		4.0,
		{"kind": "battle"},
		{"kind": "additive"},
		{"selection": "random_one"},
		["战斗结束"]
	)
	for controller: BattleController in [first, second]:
		controller.effect_runtime.register_definition(
			definition,
			BattleEffectOwnerRef.for_state(controller.player_states[0], BattleEffectDefinition.OwnerKind.MINION_CARD_INSTANCE)
		)
		controller.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.BATTLECRY)
		# 先处理根触发与目标选择，故意把真正执行留在队列中。
		controller.effect_runtime.process_next_due_us(0)
		controller.effect_runtime.process_next_due_us(0)
	var first_selected := _last_trace_target(first.effect_runtime, &"selected")
	var second_selected := _last_trace_target(second.effect_runtime, &"selected")
	_expect(first_selected > 0 and first_selected == second_selected, "固定种子得到相同的稳定目标")

	var invalidated_target := _state_by_runtime_id(first, first_selected)
	invalidated_target.current_health = 0.0
	invalidated_target.alive = false
	first.effect_runtime.process_due(0.0)
	second.effect_runtime.process_due(0.0)
	_expect(
		invalidated_target.get_zeal_layers() == 0
		and _has_trace_result(first.effect_runtime, &"invalidated")
		and _state_by_runtime_id(second, second_selected).get_zeal_layers() == 4,
		"目标选择后失效会在操作前重验并跳过，不自动改选"
	)
	_dispose_controller(first)
	_dispose_controller(second)


func _test_same_name_takeover_and_battle_cleanup() -> void:
	var controller := _make_controller(32002, 3)
	var definition := _synthetic_definition(
		"synthetic.nonstacking",
		"battlecry",
		["always"],
		"granted_effect_holder",
		"add_zeal",
		4.0,
		{"kind": "battle"},
		{"kind": "same_name_nonstacking"},
		{},
		["来源死亡", "战斗结束"]
	)
	var target := controller.player_states[2]
	for source_index: int in 2:
		controller.effect_runtime.register_definition(
			definition,
			BattleEffectOwnerRef.for_state(controller.player_states[source_index], BattleEffectDefinition.OwnerKind.MINION_CARD_INSTANCE)
		)
	controller.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.BATTLECRY, {"holder": target})
	controller.effect_runtime.process_due(0.0)
	var active_count := 0
	var suppressed_count := 0
	for instance: BattleEffectInstance in controller.effect_runtime.active_instances:
		if instance.active:
			active_count += 1
			if instance.suppressed: suppressed_count += 1
	_expect(target.get_zeal_layers() == 4 and active_count == 2 and suppressed_count == 1, "同名不叠加只启用最早合法来源")

	var first_source := controller.player_states[0]
	first_source.current_health = 0.0
	first_source.alive = false
	controller.effect_runtime.notify_source_defeated(first_source)
	controller.effect_runtime.process_due(0.0)
	_expect(target.get_zeal_layers() == 4 and _has_trace_result(controller.effect_runtime, &"activated"), "最早来源结束后，受抑制来源自动接替")
	controller.effect_runtime.notify_battle_end()
	controller.effect_runtime.process_due(0.0)
	_expect(target.get_zeal_layers() == 0, "战斗结束只撤销各运行实例自己的修正")
	_dispose_controller(controller)


func _test_timed_action_and_condition_lifecycles() -> void:
	var timed := _make_controller(32003, 2)
	var timed_definition := _synthetic_definition(
		"synthetic.timed", "battlecry", ["always"], "source_combat_unit", "add_zeal", 2.0,
		{"kind": "seconds", "amount": 2.0}, {"kind": "independent_by_source"}, {}, ["持续时间到期", "战斗结束"]
	)
	_register_and_fire(timed, timed_definition, timed.player_states[0], BattleEffectDefinition.Trigger.BATTLECRY)
	_expect(timed.player_states[0].get_zeal_layers() == 2, "固定秒数效果安装运行实例")
	timed.effect_runtime.process_due(1.999)
	_expect(timed.player_states[0].get_zeal_layers() == 2, "固定秒数到期前保持生效")
	timed.effect_runtime.process_due(2.0)
	_expect(timed.player_states[0].get_zeal_layers() == 0, "固定秒数到期后移除本来源")
	_dispose_controller(timed)

	var action := _make_controller(32004, 2)
	var action_definition := _synthetic_definition(
		"synthetic.until_action", "battlecry", ["always"], "source_combat_unit", "add_reinforcement", 3.0,
		{"kind": "until_consumed_by_action"}, {"kind": "additive"}, {}, ["指定行动后", "战斗结束"]
	)
	_register_and_fire(action, action_definition, action.player_states[0], BattleEffectDefinition.Trigger.BATTLECRY)
	var unreinforced_value := action.player_states[0].get_action_source().base_value
	_expect(
		is_equal_approx(action.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT), 3.0)
		and action.player_states[0].get_display_action_value() == unreinforced_value + 3,
		"行动后生命周期先保存强化，并把强化反映到卡面行动值"
	)
	action.effect_runtime.notify_action_after(action.player_states[0])
	action.effect_runtime.process_due(0.0)
	_expect(
		is_zero_approx(action.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT))
		and action.player_states[0].get_display_action_value() == unreinforced_value,
		"指定行动后消费强化并让卡面行动值回落"
	)
	_dispose_controller(action)

	var conditional := _make_controller(32005, 2)
	var conditional_definition := _synthetic_definition(
		"synthetic.conditional", "continuous", ["source_effect_active", "target_has_armor"], "source_combat_unit", "add_zeal", -4.0,
		{"kind": "while_active"}, {"kind": "same_name_nonstacking"}, {}, ["条件不再满足", "来源死亡", "战斗结束"]
	)
	_register_and_fire(conditional, conditional_definition, conditional.player_states[0], BattleEffectDefinition.Trigger.CONTINUOUS)
	_expect(conditional.player_states[0].get_zeal_layers() == -4, "持续条件成立时只安装一次修正")
	conditional.player_states[0].current_armor = 0.0
	conditional.effect_runtime.recheck_continuous_conditions()
	conditional.effect_runtime.process_due(0.0)
	_expect(conditional.player_states[0].get_zeal_layers() == 0, "条件失效时撤销本来源持续修正")
	conditional.player_states[0].current_armor = 2.0
	conditional.effect_runtime.recheck_continuous_conditions()
	conditional.effect_runtime.process_due(0.0)
	_expect(conditional.player_states[0].get_zeal_layers() == -4, "条件恢复后重新安装，但持续检查不重复累加")
	_dispose_controller(conditional)


func _test_refresh_and_capped_stacking() -> void:
	var refresh := _make_controller(32006, 2)
	var refresh_definition := _synthetic_definition(
		"synthetic.refresh", "battlecry", ["always"], "source_combat_unit", "add_zeal", 1.0,
		{"kind": "seconds", "amount": 2.0}, {"kind": "refresh"}, {}, ["持续时间到期", "战斗结束"]
	)
	_register_and_fire(refresh, refresh_definition, refresh.player_states[0], BattleEffectDefinition.Trigger.BATTLECRY)
	refresh.elapsed_seconds = 1.0
	refresh.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.BATTLECRY)
	refresh.effect_runtime.process_due(1.0)
	refresh.effect_runtime.process_due(2.1)
	_expect(refresh.player_states[0].get_zeal_layers() == 1 and _has_trace_result(refresh.effect_runtime, &"refreshed"), "刷新只重置持续时间，不增加层数")
	refresh.effect_runtime.process_due(3.0)
	_expect(refresh.player_states[0].get_zeal_layers() == 0, "刷新后的新到期时刻正确移除效果")
	_dispose_controller(refresh)

	var capped := _make_controller(32007, 2)
	var capped_definition := _synthetic_definition(
		"synthetic.capped", "battlecry", ["always"], "source_combat_unit", "add_zeal", 2.0,
		{"kind": "battle"}, {"kind": "capped_additive", "cap": 5.0}, {}, ["战斗结束"]
	)
	capped.effect_runtime.register_definition(capped_definition, BattleEffectOwnerRef.for_state(capped.player_states[0]))
	for _index: int in 3:
		capped.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.BATTLECRY)
		capped.effect_runtime.process_due(0.0)
	_expect(capped.player_states[0].get_zeal_layers() == 5, "封顶叠加限制本效果贡献，不影响其他来源")
	_dispose_controller(capped)


func _test_shared_group_limit_and_recursion_guard() -> void:
	var grouped := _make_controller(32009, 2)
	var first := _synthetic_definition(
		"synthetic.group_a", "battlecry", ["always"], "source_combat_unit", "add_zeal", 1.0,
		{"kind": "battle"}, {"kind": "additive"}, {}, ["战斗结束"]
	)
	var second := _synthetic_definition(
		"synthetic.group_b", "battlecry", ["always"], "source_combat_unit", "add_zeal", 1.0,
		{"kind": "battle"}, {"kind": "additive"}, {}, ["战斗结束"]
	)
	second.effect_group = first.effect_group
	for definition: BattleEffectDefinition in [first, second]:
		definition.trigger_limit.scope = BattleEffectTriggerLimit.Scope.GROUP_BATTLE
		definition.trigger_limit.count = 2
		definition.trigger_limit.counter_key = &"synthetic.shared_group"
		grouped.effect_runtime.register_definition(definition, BattleEffectOwnerRef.for_state(grouped.player_states[0]))
	for _index: int in 3:
		grouped.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.BATTLECRY)
		grouped.effect_runtime.process_due(0.0)
	_expect(
		grouped.player_states[0].get_zeal_layers() == 4
		and _has_trace_result(grouped.effect_runtime, &"limit_reached"),
		"同组多步骤共享两次额度，每次各步骤只扣一次"
	)
	_dispose_controller(grouped)

	var recursive := _make_controller(32010, 2)
	var recursive_definition := _synthetic_definition(
		"synthetic.recursion", "source_armor_gained", ["always"], "source_combat_unit", "gain_armor", 1.0,
		{"kind": "instant"}, {"kind": "not_applicable"}, {}, ["操作结算完成"]
	)
	var armor_before := float(recursive.player_states[0].current_armor)
	_register_and_fire(recursive, recursive_definition, recursive.player_states[0], BattleEffectDefinition.Trigger.SOURCE_ARMOR_GAINED)
	_expect(
		is_equal_approx(float(recursive.player_states[0].current_armor), armor_before + 1.0)
		and _has_trace_result(recursive.effect_runtime, &"blocked_recursive"),
		"事件标签阻止效果由自身生成事件递归触发"
	)
	_dispose_controller(recursive)


func _test_zeal_speed_and_progress_preservation() -> void:
	var controller := _make_controller(32008, 2, 9.0)
	var state := controller.player_states[0]
	state.advance_action_cooldown(4.5)
	var progress_before := state.cooldown_progress
	var modifier := BattleModifier.new()
	modifier.source_instance_id = 9901
	modifier.stat = BattleModifier.Stat.ZEAL
	modifier.mode = BattleModifier.Mode.ADD
	modifier.value = 4.0
	state.modifiers.add_modifier(modifier)
	state.refresh_cooldown_after_modifier_change()
	_expect(
		is_equal_approx(progress_before, 0.5)
		and is_equal_approx(state.cooldown_progress, 0.5)
		and is_equal_approx(state.get_action_interval(), 7.5)
		and is_equal_approx(state.remaining_cooldown, 3.75),
		"热诚变化保留已完成进度，只换算剩余时间"
	)
	_expect(
		is_equal_approx(BattleRules.get_action_speed(-100), 0.3)
		and is_equal_approx(BattleRules.get_action_interval(9.0, 1000), 0.5)
		and BattleRules.format_action_cooldown(10.9) == "10"
		and CardViewScript.format_cooldown_seconds(10.9) == "10"
		and CardViewScript.format_cooldown_seconds(98.1) == "98",
		"热诚使用每层5%、30%速度下限、0.5秒间隔下限与独立显示格式"
	)
	_dispose_controller(controller)


func _test_runtime_clock_determinism() -> void:
	var controllers: Array[BattleController] = []
	for _index: int in 3:
		var controller := _make_controller(32011, 3, 9.0)
		var definition := _synthetic_definition(
			"synthetic.clock", "battlecry", ["always"], "all_friendly_combat_units", "add_zeal", 4.0,
			{"kind": "seconds", "amount": 2.0}, {"kind": "independent_by_source"}, {"selection": "random_one"}, ["持续时间到期", "战斗结束"]
		)
		controller.effect_runtime.register_definition(definition, BattleEffectOwnerRef.for_state(controller.player_states[0]))
		controller.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.BATTLECRY)
		controller.effect_runtime.process_due(0.0)
		controllers.append(controller)

	controllers[0].advance_time(3.0)
	controllers[1].advance_time(0.5)
	controllers[1].advance_time(1.25)
	controllers[1].advance_time(1.25)
	controllers[2].set_battle_speed_multiplier(3.0)
	controllers[2]._process(1.0)
	var deterministic := true
	for index: int in range(1, controllers.size()):
		deterministic = (
			deterministic
			and controllers[index].effect_runtime.get_trace_signatures() == controllers[0].effect_runtime.get_trace_signatures()
			and is_equal_approx(controllers[index].elapsed_seconds, controllers[0].elapsed_seconds)
		)
		for state_index: int in controllers[0].player_states.size():
			deterministic = (
				deterministic
				and controllers[index].player_states[state_index].get_zeal_layers() == controllers[0].player_states[state_index].get_zeal_layers()
				and is_equal_approx(
					controllers[index].player_states[state_index].remaining_cooldown,
					controllers[0].player_states[state_index].remaining_cooldown
				)
			)
	_expect(deterministic, "拆帧与3×现实时间换算不改变效果事件轨迹或最终状态")
	for controller: BattleController in controllers:
		_dispose_controller(controller)


func _test_modifier_order_in_real_action() -> void:
	var controller := _make_controller(32012, 1, 1.0)
	var state := controller.player_states[0]
	state.get_action_source().action_type = CardData.ActionType.DEFENSE
	state.get_action_source().base_value = 3
	var multiply := BattleModifier.new()
	multiply.source_instance_id = 7001
	multiply.stat = BattleModifier.Stat.ARMOR_GAIN
	multiply.mode = BattleModifier.Mode.MULTIPLY
	multiply.value = 2.0
	state.modifiers.add_modifier(multiply)
	var addition := BattleModifier.new()
	addition.source_instance_id = 7002
	addition.stat = BattleModifier.Stat.ARMOR_GAIN
	addition.mode = BattleModifier.Mode.ADD
	addition.value = 1.0
	state.modifiers.add_modifier(addition)
	var armor_before := float(state.current_armor)
	controller.resolve_next_batch()
	_expect(
		is_equal_approx(float(state.current_armor), armor_before + 7.0),
		"真实防御行动按乘法后加法结算：3×2+1=7"
	)
	_dispose_controller(controller)


func _test_scheduled_trigger() -> void:
	var controller := _make_controller(32013, 2, 9.0)
	var definition := _synthetic_definition(
		"synthetic.scheduled", "elapsed_battle_time", ["always"], "source_combat_unit", "add_zeal", 2.0,
		{"kind": "battle"}, {"kind": "additive"}, {"at_seconds": 1.5}, ["战斗结束"]
	)
	controller.effect_runtime.register_definition(definition, BattleEffectOwnerRef.for_state(controller.player_states[0]))
	controller.advance_time(1.49)
	var before_schedule := controller.player_states[0].get_zeal_layers() == 0
	controller.advance_time(0.01)
	_expect(
		before_schedule and controller.player_states[0].get_zeal_layers() == 2,
		"按整数逻辑时刻触发定时效果，提前不执行且到点只尝试一次"
	)
	_dispose_controller(controller)


func _synthetic_definition(
	effect_name: String,
	trigger_name: String,
	condition_names: Array,
	target_name: String,
	operation_name: String,
	amount: float,
	duration_data: Dictionary,
	stacking_data: Dictionary,
	parameters: Dictionary,
	end_condition_names: Array
) -> BattleEffectDefinition:
	var errors: Array[String] = []
	var definition := BattleEffectDefinition.from_dictionary({
		"effect_id": "%s.effect.01" % effect_name,
		"effect_group": "%s.group.01" % effect_name,
		"group_order": 1,
		"trigger": trigger_name,
		"conditions": condition_names,
		"target": target_name,
		"operation": operation_name,
		"value": {"kind": "fixed", "amount": amount},
		"duration": duration_data,
		"stacking": stacking_data,
		"source_owner": "minion_card_instance",
		"result_owner": "affected_combat_unit",
		"end_conditions": end_condition_names,
		"end_relation": "任一满足",
		"trigger_limit": {"scope": "continuous"},
		"tags": [],
		"related_effects": [],
		"modifier": null,
		"parameters": parameters,
		"reading": "D2-3合成测试效果",
	}, effect_name, errors)
	if not errors.is_empty():
		for error: String in errors: push_error(error)
		failures += errors.size()
	return definition


func _register_and_fire(
	controller: BattleController,
	definition: BattleEffectDefinition,
	source: BattleSquadState,
	trigger: BattleEffectDefinition.Trigger
) -> void:
	controller.effect_runtime.register_definition(definition, BattleEffectOwnerRef.for_state(source))
	controller.effect_runtime.emit_trigger(trigger)
	controller.effect_runtime.process_due(controller.elapsed_seconds)


func _make_controller(seed: int, player_count: int, cooldown: float = 9.0) -> BattleController:
	var controller := BattleControllerScript.new() as BattleController
	get_root().add_child(controller)
	var players: Array[Dictionary] = []
	for index: int in player_count:
		players.append(_entry(_single_squad(CardData.ActionType.MELEE, 2, 30, 2, cooldown), &"player_front", index))
	var enemies: Array[Dictionary] = [
		_entry(_single_squad(CardData.ActionType.HEAL, 1, 100, 0, 9.9), &"enemy_front", 0),
	]
	controller.start_battle(players, enemies, seed, false)
	return controller


func _single_squad(action_type: int, value: int, health: int, armor: int, cooldown: float) -> SquadData:
	var card := CardData.new()
	card.id = StringName("d2_3_card_%d" % _card_serial)
	_card_serial += 1
	card.display_name = "D2-3测试卡"
	card.action_type = action_type
	card.base_value = value
	card.max_health = health
	card.armor = armor
	card.cooldown_seconds = cooldown
	return SquadData.from_card(card)


func _entry(squad: SquadData, row: StringName, index: int) -> Dictionary:
	return {"squad_data": squad, "row_key": row, "formation_index": index}


func _last_trace_target(runtime: BattleEffectRuntime, result: StringName) -> int:
	for index: int in range(runtime.traces.size() - 1, -1, -1):
		if runtime.traces[index].result == result:
			return runtime.traces[index].target_runtime_id
	return 0


func _has_trace_result(runtime: BattleEffectRuntime, result: StringName) -> bool:
	for trace: BattleEffectTraceEntry in runtime.traces:
		if trace.result == result:
			return true
	return false


func _state_by_runtime_id(controller: BattleController, runtime_id: int) -> BattleSquadState:
	for state: BattleSquadState in controller.get_all_states():
		if state.runtime_id == runtime_id:
			return state
	return null


func _dispose_controller(controller: BattleController) -> void:
	controller.queue_free()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
