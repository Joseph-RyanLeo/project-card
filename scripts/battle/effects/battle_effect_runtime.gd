class_name BattleEffectRuntime
extends RefCounted

const BattlePermanentGrowthLedger = preload("res://scripts/battle/battle_permanent_growth_ledger.gd")
const BattleRunRewardLedger = preload("res://scripts/battle/battle_run_reward_ledger.gd")

## D2-3 通用效果执行器。
## BattleController 负责战斗主循环；本对象负责效果定义、目标、生命周期、叠加与因果日志。

signal trace_emitted(entry: BattleEffectTraceEntry)

var controller: Node
var queue := BattleEventQueue.new()
var bindings: Array[BattleEffectBinding] = []
var active_instances: Array[BattleEffectInstance] = []
var traces: Array[BattleEffectTraceEntry] = []

var _random := RandomNumberGenerator.new()
var _next_binding_id: int = 1
var _next_instance_id: int = 1
var _counter_values: Dictionary = {}
var _counter_last_root: Dictionary = {}
var _chain_execution_counts: Dictionary = {}


func initialize(value: Node, battle_seed: int) -> void:
	controller = value
	queue.clear()
	bindings.clear()
	active_instances.clear()
	traces.clear()
	_next_binding_id = 1
	_next_instance_id = 1
	_counter_values.clear()
	_counter_last_root.clear()
	_chain_execution_counts.clear()
	# 效果选目标使用独立随机流，避免改变 D2-2 弹道随机序列。
	_random.seed = battle_seed ^ 0x5EED23


func register_definition(
	definition: BattleEffectDefinition,
	source: BattleEffectOwnerRef
) -> BattleEffectBinding:
	if source != null and source.state != null and source.owner_kind != definition.source_owner:
		source = BattleEffectOwnerRef.for_state(source.state, definition.source_owner)
	var binding := BattleEffectBinding.new()
	binding.binding_id = _next_binding_id
	_next_binding_id += 1
	binding.definition = definition
	binding.source = source
	bindings.append(binding)
	if definition.trigger == BattleEffectDefinition.Trigger.ELAPSED_BATTLE_TIME:
		var at_seconds: Variant = definition.parameters.get("at_seconds")
		if typeof(at_seconds) in [TYPE_INT, TYPE_FLOAT]:
			schedule_trigger_at(
				BattleEffectDefinition.Trigger.ELAPSED_BATTLE_TIME,
				float(at_seconds),
				{"binding_id": binding.binding_id}
			)
	return binding


func emit_trigger(
	trigger: BattleEffectDefinition.Trigger,
	context: Dictionary = {},
	parent: BattleRuntimeEvent = null
) -> BattleRuntimeEvent:
	var event := BattleRuntimeEvent.new()
	event.kind = BattleRuntimeEvent.Kind.TRIGGER
	event.trigger = trigger
	event.logical_time_us = _current_time_us()
	event.priority = BattleRuntimeEvent.Priority.TRIGGER
	event.payload = context.duplicate(true)
	if parent != null:
		event.tags.assign(parent.tags)
	queue.schedule(event, parent)
	return event


func schedule_trigger_at(
	trigger: BattleEffectDefinition.Trigger,
	absolute_seconds: float,
	context: Dictionary = {},
	parent: BattleRuntimeEvent = null
) -> BattleRuntimeEvent:
	var event := BattleRuntimeEvent.new()
	event.kind = BattleRuntimeEvent.Kind.TRIGGER
	event.trigger = trigger
	event.logical_time_us = BattleEventQueue.seconds_to_us(absolute_seconds)
	event.priority = BattleRuntimeEvent.Priority.TRIGGER
	event.payload = context.duplicate(true)
	if parent != null:
		event.tags.assign(parent.tags)
	queue.schedule(event, parent)
	return event


func process_due(seconds: float) -> void:
	var time_us := BattleEventQueue.seconds_to_us(seconds)
	while process_next_due_us(time_us):
		pass


func process_next_due_us(logical_time_us: int) -> bool:
	var event := queue.pop_next_due(logical_time_us)
	if event == null:
		return false
	match event.kind:
		BattleRuntimeEvent.Kind.TRIGGER:
			_handle_trigger(event)
		BattleRuntimeEvent.Kind.SELECT_TARGETS:
			_handle_select_targets(event)
		BattleRuntimeEvent.Kind.APPLY_OPERATION:
			_handle_apply_operation(event)
		BattleRuntimeEvent.Kind.EXPIRE:
			_handle_expire(event)
		BattleRuntimeEvent.Kind.CONDITION_RECHECK:
			recheck_continuous_conditions(event)
		BattleRuntimeEvent.Kind.ACTION_AFTER:
			_handle_action_after(event)
		BattleRuntimeEvent.Kind.SOURCE_DEFEATED:
			_handle_source_defeated(event)
		BattleRuntimeEvent.Kind.BATTLE_END:
			_handle_battle_end(event)
	return true


func get_next_event_time_seconds() -> float:
	var time_us := queue.get_next_time_us()
	return BattleEventQueue.us_to_seconds(time_us) if time_us >= 0 else INF


func notify_action_after(actor: BattleSquadState, parent: BattleRuntimeEvent = null) -> void:
	var event := BattleRuntimeEvent.new()
	event.kind = BattleRuntimeEvent.Kind.ACTION_AFTER
	event.logical_time_us = _current_time_us()
	event.priority = BattleRuntimeEvent.Priority.POST_APPLY
	event.target = actor
	queue.schedule(event, parent)


func notify_source_defeated(source_state: BattleSquadState, parent: BattleRuntimeEvent = null) -> void:
	var event := BattleRuntimeEvent.new()
	event.kind = BattleRuntimeEvent.Kind.SOURCE_DEFEATED
	event.logical_time_us = _current_time_us()
	event.priority = BattleRuntimeEvent.Priority.POST_APPLY
	event.target = source_state
	queue.schedule(event, parent)


func notify_battle_end(parent: BattleRuntimeEvent = null) -> void:
	var event := BattleRuntimeEvent.new()
	event.kind = BattleRuntimeEvent.Kind.BATTLE_END
	event.logical_time_us = _current_time_us()
	event.priority = BattleRuntimeEvent.Priority.EXPIRE
	queue.schedule(event, parent)


func recheck_continuous_conditions(parent: BattleRuntimeEvent = null) -> void:
	var instances := active_instances.duplicate()
	for instance_value: Variant in instances:
		var instance := instance_value as BattleEffectInstance
		if not instance.active or not instance.definition.end_conditions.has(BattleEffectDefinition.EndCondition.CONDITION_INVALID):
			continue
		var event := BattleRuntimeEvent.new()
		event.definition = instance.definition
		event.effect_instance = instance
		event.source = instance.source
		event.target = instance.target
		if not _all_conditions_pass(instance.definition, instance.source, instance.target, event):
			_mark_end_condition(instance, BattleEffectDefinition.EndCondition.CONDITION_INVALID, event)
	# 持续定义在条件恢复后可以重新安装；叠加规则会阻止重复发放。
	emit_trigger(BattleEffectDefinition.Trigger.CONTINUOUS, {}, parent)


func get_trace_signatures() -> Array[String]:
	var result: Array[String] = []
	for entry: BattleEffectTraceEntry in traces:
		result.append(entry.stable_signature())
	return result


func resolve_armor_gain_modifiers(target: BattleSquadState) -> Dictionary:
	# 护甲获得属于正式行动公式的一部分，必须在数值写入前同步读取拦截器。
	# 返回乘法与加法两个区段，让控制器固定执行“先乘后加”。
	var result := {"multiplier": 1.0, "addition": 0.0}
	if target == null:
		return result
	var event := BattleRuntimeEvent.new()
	event.logical_time_us = _current_time_us()
	event.payload = {"actor": target}
	var used_nonstacking_effects: Dictionary = {}
	for binding: BattleEffectBinding in bindings:
		var definition := binding.definition
		if (
			not binding.enabled
			or definition == null
			or definition.trigger != BattleEffectDefinition.Trigger.ARMOR_GAIN_BEFORE_APPLY
			or definition.operation != BattleEffectDefinition.Operation.MODIFY_EFFECT
			or binding.source == null
			or binding.source.state == null
			or binding.source.state.side != target.side
			or String(definition.modifier.filter.get("operation", "")) != "gain_armor"
		):
			continue
		if (
			definition.stacking.kind == BattleEffectStacking.Kind.SAME_NAME_NONSTACKING
			and used_nonstacking_effects.has(definition.effect_id)
		):
			_trace(event, definition, binding.source, target, &"modify", &"suppressed", "同名护甲拦截器只采用最早合法来源")
			continue
		if not _all_conditions_pass(definition, binding.source, target, event):
			continue
		match definition.modifier.mode:
			BattleEffectModifierSpec.Mode.MULTIPLY_VALUE:
				result["multiplier"] = float(result["multiplier"]) * definition.modifier.amount
			BattleEffectModifierSpec.Mode.ADD_VALUE:
				result["addition"] = float(result["addition"]) + definition.modifier.amount
			_:
				continue
		used_nonstacking_effects[definition.effect_id] = true
		_trace(event, definition, binding.source, target, &"modify", &"applied", "护甲获得修正=%.2f" % definition.modifier.amount)
	return result


func _handle_trigger(event: BattleRuntimeEvent) -> void:
	var only_binding_id := int(event.payload.get("binding_id", 0))
	for binding: BattleEffectBinding in bindings:
		if not binding.enabled or binding.definition == null or binding.definition.trigger != event.trigger:
			continue
		if only_binding_id > 0 and binding.binding_id != only_binding_id:
			continue
		if not _binding_matches_event_actor(binding, event):
			continue
		var effect_tag := StringName("effect:%s" % binding.definition.effect_id)
		if event.has_tag(effect_tag) and not binding.definition.modifier.recursive:
			_trace(event, binding.definition, binding.source, null, &"trigger", &"blocked_recursive", "事件标签已包含同一效果")
			continue
		var select_event := BattleRuntimeEvent.new()
		select_event.kind = BattleRuntimeEvent.Kind.SELECT_TARGETS
		select_event.logical_time_us = event.logical_time_us
		select_event.priority = BattleRuntimeEvent.Priority.SELECT_TARGETS
		select_event.definition = binding.definition
		select_event.source = binding.source
		select_event.payload = event.payload.duplicate(true)
		select_event.tags.assign(event.tags)
		select_event.add_tag(effect_tag)
		select_event.add_tag(StringName("group:%s" % binding.definition.effect_group))
		queue.schedule(select_event, event)


func _handle_select_targets(event: BattleRuntimeEvent) -> void:
	var definition := event.definition
	if definition == null or event.source == null:
		return
	# 累计阈值事件会在每次生命损失时发出；未达到阈值只是“尚未触发”，
	# 不能提前消耗每场次数。计时法术等一次性机会仍沿用先扣额度的规则。
	if (
		definition.trigger == BattleEffectDefinition.Trigger.SOURCE_HEALTH_LOST_ACCUMULATED
		and definition.conditions.has(
			BattleEffectDefinition.Condition.ACCUMULATED_HEALTH_LOSS_AT_LEAST_VALUE
		)
	):
		var accumulated_loss := float(event.payload.get("accumulated_health_loss", 0.0))
		var threshold := float(definition.parameters.get("health_loss_threshold", 0.0))
		if accumulated_loss < threshold:
			_trace(event, definition, event.source, null, &"select", &"threshold_not_met", "累计条件尚未达到，不消耗本场次数")
			return
	if not _reserve_trigger_limit(definition, event.source, event.root_event_id):
		_trace(event, definition, event.source, null, &"select", &"limit_reached", "共享次数额度已用尽")
		return
	var candidates := _resolve_targets(definition, event.source, event)
	if candidates.is_empty():
		_trace(event, definition, event.source, null, &"select", &"no_legal_target", "没有合法目标，本次机会已消耗")
		return
	for target: BattleSquadState in candidates:
		var apply_event := BattleRuntimeEvent.new()
		apply_event.kind = BattleRuntimeEvent.Kind.APPLY_OPERATION
		apply_event.logical_time_us = event.logical_time_us
		apply_event.priority = BattleRuntimeEvent.Priority.EXECUTE
		apply_event.definition = definition
		apply_event.source = event.source
		apply_event.target = target
		apply_event.payload = event.payload.duplicate(true)
		apply_event.tags.assign(event.tags)
		queue.schedule(apply_event, event)
		_trace(event, definition, event.source, target, &"select", &"selected", "稳定目标序=%d" % target.runtime_id)


func _handle_apply_operation(event: BattleRuntimeEvent) -> void:
	var definition := event.definition
	var target := event.target
	if definition == null or event.source == null:
		return
	if not _is_target_still_legal(definition, event.source, target, event):
		_trace(event, definition, event.source, target, &"apply", &"invalidated", "执行前合法性重验失败")
		return
	var chain_key := "%d:%s:%s:%d" % [
		event.root_event_id,
		definition.effect_id,
		event.source.stable_key(),
		target.runtime_id,
	]
	var chain_count := int(_chain_execution_counts.get(chain_key, 0))
	var neighbor_modifiers := _get_neighbor_extra_execution_bindings(definition, event.source)
	var allowed_count := (
		1
		+ maxi(int(event.payload.get("extra_execution_count", 0)), 0)
		+ neighbor_modifiers.size()
	)
	if chain_count >= allowed_count:
		_trace(event, definition, event.source, target, &"apply", &"duplicate_blocked", "同一因果链运行实例次数已达上限")
		return
	var execution_count := allowed_count - chain_count
	_chain_execution_counts[chain_key] = chain_count + execution_count
	for modifier_binding: BattleEffectBinding in neighbor_modifiers:
		_trace(
			event,
			modifier_binding.definition,
			modifier_binding.source,
			target,
			&"modify",
			&"extra_execution",
			"使%s额外执行一次" % definition.effect_id
		)
	# 当前灰烬乡邻效果均为加法数值；把各次执行聚合为同一来源实例，
	# 才能同时满足“老狼可额外执行”与“同名来源本身不叠加”。
	var value := _resolve_value(definition, event.source, target, event) * float(execution_count)
	_apply_definition(definition, event.source, target, value, event)


func _apply_definition(
	definition: BattleEffectDefinition,
	source: BattleEffectOwnerRef,
	target: BattleSquadState,
	value: float,
	event: BattleRuntimeEvent
) -> void:
	var existing := _find_active_source_instance(definition, source, target)
	if definition.stacking.kind == BattleEffectStacking.Kind.REFRESH and existing != null:
		existing.applied_value = value
		_schedule_expiry(existing, event)
		_trace(event, definition, source, target, &"stack", &"refreshed", "刷新持续时间，不增加层数")
		return
	if definition.stacking.kind == BattleEffectStacking.Kind.CAPPED_ADDITIVE and existing != null:
		existing.applied_value = minf(existing.applied_value + value, definition.stacking.cap)
		target.modifiers.update_source_instance_value(existing.instance_id, existing.applied_value)
		target.refresh_cooldown_after_modifier_change()
		_schedule_expiry(existing, event)
		_trace(event, definition, source, target, &"stack", &"capped", "本效果贡献=%.2f" % existing.applied_value)
		return
	if definition.trigger == BattleEffectDefinition.Trigger.CONTINUOUS and existing != null:
		if not is_equal_approx(existing.applied_value, value):
			var previous_value := existing.applied_value
			existing.applied_value = value
			target.modifiers.update_source_instance_value(existing.instance_id, value)
			target.refresh_cooldown_after_modifier_change()
			_adjust_current_health_for_maximum_modifier(existing, value - previous_value)
			_trace(event, definition, source, target, &"stack", &"recalculated", "持续效果实时重算为%.2f" % value)
		else:
			_trace(event, definition, source, target, &"stack", &"already_active", "持续检查不重复发放")
		return

	var instance := BattleEffectInstance.new()
	instance.instance_id = _next_instance_id
	_next_instance_id += 1
	instance.definition = definition
	instance.source = source
	instance.result_owner = BattleEffectOwnerRef.for_state(target, definition.result_owner)
	instance.target = target
	instance.started_at_us = event.logical_time_us
	instance.applied_value = minf(value, definition.stacking.cap) if definition.stacking.kind == BattleEffectStacking.Kind.CAPPED_ADDITIVE else value
	instance.execution_count = 1
	active_instances.append(instance)

	var supported := _apply_operation(instance, event)
	if not supported:
		_end_instance(instance, BattleEffectInstance.EndReason.INSTANT_RESOLVED, event, "操作尚未接入D2-3执行器")
		return
	if definition.stacking.kind == BattleEffectStacking.Kind.SAME_NAME_NONSTACKING:
		_recompute_same_name_group(instance.stack_key(), event)
	_schedule_expiry(instance, event)
	_trace(event, definition, source, target, &"apply", &"applied", "实例=%d 数值=%.2f" % [instance.instance_id, instance.applied_value])
	if definition.duration.kind == BattleEffectDuration.Kind.INSTANT:
		_mark_end_condition(instance, BattleEffectDefinition.EndCondition.OPERATION_RESOLVED, event)


func _apply_operation(instance: BattleEffectInstance, event: BattleRuntimeEvent) -> bool:
	var definition := instance.definition
	var target := instance.target
	match definition.operation:
		BattleEffectDefinition.Operation.ADD_ZEAL:
			_add_modifier(instance, BattleModifier.Stat.ZEAL, BattleModifier.Mode.ADD, instance.applied_value)
		BattleEffectDefinition.Operation.ADD_ATTRIBUTE:
			var stat_name := String(definition.parameters.get("stat", "base_value"))
			var stat := BattleModifier.Stat.ACTION_VALUE
			if stat_name == "max_health": stat = BattleModifier.Stat.MAX_HEALTH
			elif stat_name == "base_armor": stat = BattleModifier.Stat.BASE_ARMOR
			_add_modifier(instance, stat, BattleModifier.Mode.ADD, instance.applied_value)
			if stat == BattleModifier.Stat.MAX_HEALTH and bool(definition.parameters.get("increase_current_health", false)):
				target.current_health = minf(target.current_health + instance.applied_value, float(target.get_max_health()))
			if stat == BattleModifier.Stat.BASE_ARMOR:
				target.apply_armor_exact(instance.applied_value, instance.source.state)
		BattleEffectDefinition.Operation.ADD_ACTION_MULTIPLIER:
			_add_modifier(instance, BattleModifier.Stat.ACTION_MULTIPLIER, BattleModifier.Mode.ADD, instance.applied_value)
		BattleEffectDefinition.Operation.ADD_TARGET_PRIORITY:
			_add_modifier(instance, BattleModifier.Stat.TARGET_PRIORITY, BattleModifier.Mode.ADD, instance.applied_value)
		BattleEffectDefinition.Operation.ADD_REINFORCEMENT:
			_add_modifier(instance, BattleModifier.Stat.REINFORCEMENT, BattleModifier.Mode.ADD, instance.applied_value)
		BattleEffectDefinition.Operation.SET_MINIMUM_HEALTH:
			_add_modifier(instance, BattleModifier.Stat.MINIMUM_HEALTH, BattleModifier.Mode.SET_MINIMUM, instance.applied_value)
		BattleEffectDefinition.Operation.GAIN_ARMOR:
			var armor_amount := instance.applied_value * target.modifiers.get_multiplier(BattleModifier.Stat.ARMOR_GAIN)
			armor_amount += target.modifiers.get_additive(BattleModifier.Stat.ARMOR_GAIN)
			target.apply_armor_exact(maxf(armor_amount, 0.0), instance.source.state)
			emit_trigger(
				BattleEffectDefinition.Trigger.SOURCE_ARMOR_GAINED,
				{"actor": target, "amount": armor_amount, "generated_effect_id": definition.effect_id},
				event
			)
		BattleEffectDefinition.Operation.DEAL_NON_ACTION_DAMAGE:
			target.apply_damage_exact(maxf(instance.applied_value, 0.0), instance.source.state)
		BattleEffectDefinition.Operation.GAIN_GOLD, BattleEffectDefinition.Operation.GRANT_RANDOM_CARD:
			if controller == null or not controller.has_method("record_pending_run_reward"):
				return false
			var reward_kind := (
				BattleRunRewardLedger.KIND_GOLD
				if definition.operation == BattleEffectDefinition.Operation.GAIN_GOLD
				else BattleRunRewardLedger.KIND_RANDOM_CARD_REQUEST
			)
			if not controller.record_pending_run_reward(
				instance.result_owner,
				reward_kind,
				maxi(roundi(instance.applied_value), 0),
				definition.effect_id,
				instance.source.runtime_id,
				event.logical_time_us,
				definition.parameters
			):
				return false
		BattleEffectDefinition.Operation.IMMEDIATE_ACTION:
			var forced_action := _action_type_from_name(StringName(definition.parameters.get("forced_action", "")))
			if forced_action < 0 or controller == null or not controller.has_method("execute_immediate_action"):
				return false
			controller.execute_immediate_action(
				target,
				forced_action as CardData.ActionType,
				float(definition.parameters.get("action_value_delta", 0.0))
			)
		BattleEffectDefinition.Operation.SET_ACTION_TYPE:
			var action_name := definition.value.enum_value
			if action_name == &"":
				action_name = StringName(definition.parameters.get("action_type", ""))
			var action_type := _action_type_from_name(action_name)
			if action_type < 0:
				return false
			target.set_runtime_action_type(action_type as CardData.ActionType)
		BattleEffectDefinition.Operation.FORBID_STACKING:
			# 编队限制在 SquadData 中先行执行；这里登记持续实例，使战斗效果
			# 审计不会把已经生效的固有规则误报成“未支持操作”。
			if (
				target.squad_data == null
				or target.squad_data.get_card_count() != 1
				or not target.squad_data.contains_stacking_forbidden_card()
			):
				return false
		BattleEffectDefinition.Operation.MASK_INJURY:
			var eligible_injuries := target.get_unmasked_active_injuries()
			if eligible_injuries.is_empty():
				return false
			var selected_injury := eligible_injuries[
				_random.randi_range(0, eligible_injuries.size() - 1)
			]
			if not target.mask_injury(selected_injury, instance.instance_id):
				return false
			instance.payload["masked_injury_id"] = selected_injury
			_trace(event, definition, instance.source, target, &"mask_injury", &"applied", "伤势=%s" % selected_injury)
		BattleEffectDefinition.Operation.MASK_RUNE:
			var masked_slots: Array[Dictionary] = []
			var mask_count := maxi(roundi(instance.applied_value), 0)
			for _mask_index: int in mask_count:
				var active_slots := target.get_active_rune_slots()
				if active_slots.is_empty():
					break
				var selected_index := _random.randi_range(0, active_slots.size() - 1)
				var selected := active_slots[selected_index]
				var card := selected.get("card") as CardData
				var rune_index := int(selected.get("rune_index", -1))
				if target.mask_rune_slot(card, rune_index):
					masked_slots.append({"card": card, "rune_index": rune_index})
					_trace(event, definition, instance.source, target, &"mask_rune", &"applied", "卡=%s 槽=%d" % [card.id, rune_index])
			if masked_slots.is_empty():
				return false
			instance.payload["masked_rune_slots"] = masked_slots
		BattleEffectDefinition.Operation.REVIVE:
			if controller == null or not controller.has_method("revive_state_at_original_position"):
				return false
			if not controller.revive_state_at_original_position(target, instance.applied_value):
				_trace(event, definition, instance.source, target, &"revive", &"original_position_unavailable", "原位置已有存活单位，本次亡语结束")
				return true
			_trace(event, definition, instance.source, target, &"revive", &"applied", "恢复生命=%.2f 基础护甲=%d" % [target.current_health, target.displayed_armor])
		BattleEffectDefinition.Operation.PERMANENTLY_ADD_BASE_VALUE, BattleEffectDefinition.Operation.PERMANENTLY_ADD_ARMOR:
			if controller == null or not controller.has_method("record_pending_permanent_growth"):
				return false
			var growth_stat := (
				BattlePermanentGrowthLedger.STAT_BASE_VALUE
				if definition.operation == BattleEffectDefinition.Operation.PERMANENTLY_ADD_BASE_VALUE
				else BattlePermanentGrowthLedger.STAT_BASE_ARMOR
			)
			if not controller.record_pending_permanent_growth(
				instance.result_owner,
				growth_stat,
				instance.applied_value,
				definition.effect_id,
				instance.source.runtime_id,
				event.logical_time_us
			):
				return false
			var modifier_stat := (
				BattleModifier.Stat.ACTION_VALUE
				if growth_stat == BattlePermanentGrowthLedger.STAT_BASE_VALUE
				else BattleModifier.Stat.BASE_ARMOR
			)
			_add_modifier(instance, modifier_stat, BattleModifier.Mode.ADD, instance.applied_value)
			if (
				growth_stat == BattlePermanentGrowthLedger.STAT_BASE_ARMOR
				and bool(definition.parameters.get("increase_current_armor", false))
			):
				target.apply_armor_exact(instance.applied_value, instance.source.state)
		BattleEffectDefinition.Operation.MODIFY_EFFECT:
			var stat := BattleModifier.Stat.ARMOR_GAIN if String(definition.modifier.filter.get("operation", "")) == "gain_armor" else BattleModifier.Stat.INCOMING_DAMAGE
			var mode := BattleModifier.Mode.MULTIPLY if definition.modifier.mode == BattleEffectModifierSpec.Mode.MULTIPLY_VALUE else BattleModifier.Mode.ADD
			_add_modifier(instance, stat, mode, definition.modifier.amount)
		_:
			_trace(event, definition, instance.source, target, &"apply", &"unsupported_operation", "枚举已识别，真实卡操作留待后续阶段")
			return false
	return true


func _add_modifier(
	instance: BattleEffectInstance,
	stat: BattleModifier.Stat,
	mode: BattleModifier.Mode,
	value: float
) -> void:
	var modifier := BattleModifier.new()
	modifier.source_instance_id = instance.instance_id
	modifier.effect_id = instance.definition.effect_id
	modifier.source_runtime_id = instance.source.runtime_id
	modifier.stat = stat
	modifier.mode = mode
	modifier.value = value
	instance.target.modifiers.add_modifier(modifier)
	instance.target.refresh_cooldown_after_modifier_change()


func _schedule_expiry(instance: BattleEffectInstance, parent: BattleRuntimeEvent) -> void:
	if instance.definition.duration.kind != BattleEffectDuration.Kind.SECONDS:
		return
	instance.expires_at_us = parent.logical_time_us + BattleEventQueue.seconds_to_us(instance.definition.duration.seconds)
	var expire_event := BattleRuntimeEvent.new()
	expire_event.kind = BattleRuntimeEvent.Kind.EXPIRE
	expire_event.logical_time_us = instance.expires_at_us
	expire_event.priority = BattleRuntimeEvent.Priority.EXPIRE
	expire_event.effect_instance = instance
	expire_event.definition = instance.definition
	expire_event.source = instance.source
	expire_event.target = instance.target
	queue.schedule(expire_event, parent)


func _handle_expire(event: BattleRuntimeEvent) -> void:
	var instance := event.effect_instance
	if instance == null or not instance.active or event.logical_time_us != instance.expires_at_us:
		return
	_mark_end_condition(instance, BattleEffectDefinition.EndCondition.DURATION_EXPIRED, event)


func _handle_action_after(event: BattleRuntimeEvent) -> void:
	var instances := active_instances.duplicate()
	for value: Variant in instances:
		var instance := value as BattleEffectInstance
		if instance.active and instance.target == event.target and (
			instance.definition.duration.kind == BattleEffectDuration.Kind.UNTIL_ACTION
			or instance.definition.end_conditions.has(BattleEffectDefinition.EndCondition.SPECIFIED_ACTION_AFTER)
		):
			_mark_end_condition(instance, BattleEffectDefinition.EndCondition.SPECIFIED_ACTION_AFTER, event)
	emit_trigger(BattleEffectDefinition.Trigger.OTHER_ALLY_ACTION_AFTER, {"actor": event.target}, event)


func _handle_source_defeated(event: BattleRuntimeEvent) -> void:
	var instances := active_instances.duplicate()
	for value: Variant in instances:
		var instance := value as BattleEffectInstance
		if instance.active and instance.source.state == event.target and instance.definition.end_conditions.has(BattleEffectDefinition.EndCondition.SOURCE_DEATH):
			_mark_end_condition(instance, BattleEffectDefinition.EndCondition.SOURCE_DEATH, event)


func _handle_battle_end(event: BattleRuntimeEvent) -> void:
	var instances := active_instances.duplicate()
	for value: Variant in instances:
		var instance := value as BattleEffectInstance
		if (
			instance.active
			and instance.definition.duration.kind
			!= BattleEffectDuration.Kind.CURRENT_RUN_PERMANENT
		):
			_end_instance(instance, BattleEffectInstance.EndReason.BATTLE_ENDED, event, "战斗结束统一清理")


func _mark_end_condition(instance: BattleEffectInstance, condition: int, event: BattleRuntimeEvent) -> void:
	if not instance.active:
		return
	instance.end_satisfied[condition] = true
	var should_end := instance.definition.end_relation == BattleEffectDefinition.EndRelation.ANY
	if instance.definition.end_relation == BattleEffectDefinition.EndRelation.ALL:
		should_end = true
		for required: int in instance.definition.end_conditions:
			if not instance.end_satisfied.has(required):
				should_end = false
				break
	if not should_end:
		return
	var reason := BattleEffectInstance.EndReason.INSTANT_RESOLVED
	match condition:
		BattleEffectDefinition.EndCondition.DURATION_EXPIRED:
			reason = BattleEffectInstance.EndReason.DURATION_EXPIRED
		BattleEffectDefinition.EndCondition.SPECIFIED_ACTION_AFTER:
			reason = BattleEffectInstance.EndReason.ACTION_CONSUMED
		BattleEffectDefinition.EndCondition.SOURCE_DEATH:
			reason = BattleEffectInstance.EndReason.SOURCE_DEFEATED
		BattleEffectDefinition.EndCondition.CONDITION_INVALID, BattleEffectDefinition.EndCondition.SOURCE_EFFECT_INVALID, BattleEffectDefinition.EndCondition.NEIGHBOR_INVALID:
			reason = BattleEffectInstance.EndReason.CONDITION_INVALID
		BattleEffectDefinition.EndCondition.BATTLE_END:
			reason = BattleEffectInstance.EndReason.BATTLE_ENDED
	_end_instance(instance, reason, event, "结束条件=%d" % condition)


func _end_instance(
	instance: BattleEffectInstance,
	reason: BattleEffectInstance.EndReason,
	event: BattleRuntimeEvent,
	detail: String
) -> void:
	if not instance.active:
		return
	instance.active = false
	instance.end_reason = reason
	queue.cancel_instance(instance.instance_id)
	instance.target.modifiers.remove_source_instance(instance.instance_id)
	instance.target.refresh_cooldown_after_modifier_change()
	if instance.definition.operation == BattleEffectDefinition.Operation.SET_ACTION_TYPE:
		instance.target.clear_runtime_action_type()
	if instance.definition.operation == BattleEffectDefinition.Operation.MASK_RUNE:
		for slot_value: Variant in instance.payload.get("masked_rune_slots", []):
			var slot := slot_value as Dictionary
			instance.target.unmask_rune_slot(
				slot.get("card") as CardData,
				int(slot.get("rune_index", -1))
			)
	if instance.definition.operation == BattleEffectDefinition.Operation.MASK_INJURY:
		instance.target.unmask_injury(
			StringName(instance.payload.get("masked_injury_id", "")),
			instance.instance_id
		)
	_adjust_current_health_for_maximum_modifier(instance, -instance.applied_value)
	_trace(event, instance.definition, instance.source, instance.target, &"end", StringName(BattleEffectInstance.EndReason.keys()[reason].to_lower()), detail)
	if instance.definition.stacking.kind == BattleEffectStacking.Kind.SAME_NAME_NONSTACKING:
		_recompute_same_name_group(instance.stack_key(), event)


func _recompute_same_name_group(stack_key: String, event: BattleRuntimeEvent) -> void:
	var group: Array[BattleEffectInstance] = []
	for instance: BattleEffectInstance in active_instances:
		if instance.active and instance.stack_key() == stack_key:
			group.append(instance)
	group.sort_custom(func(left: BattleEffectInstance, right: BattleEffectInstance) -> bool: return left.instance_id < right.instance_id)
	for index: int in group.size():
		var instance := group[index]
		var next_suppressed := index > 0
		if instance.suppressed != next_suppressed:
			instance.suppressed = next_suppressed
			instance.target.modifiers.set_source_instance_active(instance.instance_id, not next_suppressed)
			instance.target.refresh_cooldown_after_modifier_change()
			_trace(event, instance.definition, instance.source, instance.target, &"stack", &"suppressed" if next_suppressed else &"activated", "同名不叠加按最早合法来源")


func _resolve_targets(
	definition: BattleEffectDefinition,
	source: BattleEffectOwnerRef,
	event: BattleRuntimeEvent
) -> Array[BattleSquadState]:
	var result: Array[BattleSquadState] = []
	var source_state := source.state
	match definition.target:
		BattleEffectDefinition.Target.SOURCE_COMBAT_UNIT, BattleEffectDefinition.Target.SOURCE_CARD_INSTANCE:
			if source_state != null: result.append(source_state)
		BattleEffectDefinition.Target.SOURCE_DEAD_CARD:
			if source_state != null and not source_state.alive:
				result.append(source_state)
		BattleEffectDefinition.Target.SOURCE_ACTIVE_RUNE:
			if source_state != null and not source_state.get_active_rune_slots().is_empty():
				result.append(source_state)
		BattleEffectDefinition.Target.ALL_FRIENDLY_COMBAT_UNITS:
			if source_state != null: result.assign(controller.get_living_states(source_state.side))
		BattleEffectDefinition.Target.ADJACENT_FRIENDLY_UNITS, BattleEffectDefinition.Target.SAME_ROW_FRIENDLY_UNITS, BattleEffectDefinition.Target.SELF_AND_ADJACENT_HUMAN_UNITS:
			for state: BattleSquadState in controller.get_living_states(source_state.side):
				if state.row_key != source_state.row_key:
					continue
				if definition.target == BattleEffectDefinition.Target.SAME_ROW_FRIENDLY_UNITS:
					result.append(state)
				elif state == source_state or abs(state.formation_index - source_state.formation_index) == 1:
					if definition.target == BattleEffectDefinition.Target.SELF_AND_ADJACENT_HUMAN_UNITS:
						if not _is_human(state):
							continue
						if (
							state != source_state
							and bool(definition.parameters.get("adjacent_target_requires_squad", false))
							and state.squad_data.get_card_count() <= 1
						):
							continue
					result.append(state)
		BattleEffectDefinition.Target.DAMAGE_SOURCE:
			var damage_source := event.payload.get("damage_source") as BattleSquadState
			if damage_source != null: result.append(damage_source)
		BattleEffectDefinition.Target.HEALED_TARGET_ACTIVE_INJURY:
			var healed_target := event.payload.get("healed_target") as BattleSquadState
			if healed_target != null and healed_target.has_unmasked_active_injury():
				result.append(healed_target)
		BattleEffectDefinition.Target.OWNING_PLAYER:
			# 玩家不是战斗单位；D2-4 以效果来源状态作为阵营锚点，
			# 真正的收藏/金币身份由战后系统消费待结算记录时提供。
			if source_state != null: result.append(source_state)
		BattleEffectDefinition.Target.GRANTED_EFFECT_HOLDER, BattleEffectDefinition.Target.EQUIPPED_UNIT:
			var holder := event.payload.get("holder") as BattleSquadState
			if holder != null: result.append(holder)
	result.sort_custom(_is_state_before)
	var legal: Array[BattleSquadState] = []
	for candidate: BattleSquadState in result:
		if _all_conditions_pass(definition, source, candidate, event):
			legal.append(candidate)
	result = legal
	var selection := String(definition.parameters.get("selection", ""))
	if selection in ["random", "random_one"] and result.size() > 1:
		var selection_index := _random.randi_range(0, result.size() - 1)
		var selected := result[selection_index]
		_trace(event, definition, source, selected, &"target_rng", &"rolled", "index=%d pool=%d" % [selection_index, result.size()])
		result.assign([selected])
	return result


func _is_target_still_legal(
	definition: BattleEffectDefinition,
	source: BattleEffectOwnerRef,
	target: BattleSquadState,
	event: BattleRuntimeEvent
) -> bool:
	if target == null:
		return false
	if definition.target == BattleEffectDefinition.Target.SOURCE_DEAD_CARD:
		return target == source.state and not target.alive and _all_conditions_pass(definition, source, target, event)
	if definition.target == BattleEffectDefinition.Target.SOURCE_ACTIVE_RUNE:
		return target == source.state and not target.get_active_rune_slots().is_empty() and _all_conditions_pass(definition, source, target, event)
	if definition.trigger == BattleEffectDefinition.Trigger.SOURCE_HEALTH_LOST_ACCUMULATED:
		return target == source.state and _all_conditions_pass(definition, source, target, event)
	if not target.alive or target.current_health <= 0.0:
		return false
	return _all_conditions_pass(definition, source, target, event)


func _all_conditions_pass(
	definition: BattleEffectDefinition,
	source: BattleEffectOwnerRef,
	target: BattleSquadState,
	event: BattleRuntimeEvent
) -> bool:
	for condition: int in definition.conditions:
		var passed := _condition_passes(condition, definition, source, target, event)
		_trace(
			event,
			definition,
			source,
			target,
			&"condition",
			&"passed" if passed else &"failed",
			String(BattleEffectDefinition.Condition.keys()[condition]).to_lower()
		)
		if not passed:
			return false
	return true


func _condition_passes(
	condition: BattleEffectDefinition.Condition,
	definition: BattleEffectDefinition,
	source: BattleEffectOwnerRef,
	target: BattleSquadState,
	event: BattleRuntimeEvent
) -> bool:
	match condition:
		BattleEffectDefinition.Condition.ALWAYS:
			return true
		BattleEffectDefinition.Condition.SOURCE_EFFECT_ACTIVE:
			return source.is_alive()
		BattleEffectDefinition.Condition.TARGET_HAS_ARMOR:
			return target != null and target.current_armor > 0.0
		BattleEffectDefinition.Condition.TARGET_IS_HUMAN:
			return _is_human(target)
		BattleEffectDefinition.Condition.TARGET_IS_NON_ELF:
			return target != null and target.get_effect_source() != null and target.get_effect_source().race_type != CardData.RaceType.ELF
		BattleEffectDefinition.Condition.NEIGHBOR_ACTIVE:
			# “乡邻”描述的是效果持有者的站位条件，不应随着当前遍历到的
			# 受益目标改变。持有者左右都必须有同种族存活单位才算成立。
			return _has_living_same_race_neighbors_on_both_sides(source.state)
		BattleEffectDefinition.Condition.PER_BATTLE_COUNT_BELOW_LIMIT:
			return _counter_below_limit(definition, source, event.root_event_id)
		BattleEffectDefinition.Condition.EVENT_ACTOR_IS_OTHER_ALLY:
			var actor := event.payload.get("actor") as BattleSquadState
			return actor != null and source.state != null and actor != source.state and actor.side == source.state.side
		BattleEffectDefinition.Condition.DAMAGE_SOURCE_EXISTS:
			return event.payload.get("damage_source") is BattleSquadState
		BattleEffectDefinition.Condition.TARGET_HAS_ACTIVE_INJURY:
			return target != null and target.has_unmasked_active_injury()
		BattleEffectDefinition.Condition.DEAD_UNIT_NOT_DERIVED:
			var dead_actor := event.payload.get("actor") as BattleSquadState
			return dead_actor != null and dead_actor.get_effect_source() != null and not dead_actor.get_effect_source().is_derived
		BattleEffectDefinition.Condition.HAS_GRANTED_EFFECT:
			return bool(event.payload.get("has_granted_effect", false))
		BattleEffectDefinition.Condition.NOT_SAME_EFFECT_GENERATED_GAIN:
			return StringName(event.payload.get("generated_effect_id", "")) != definition.effect_id
		BattleEffectDefinition.Condition.ACCUMULATED_HEALTH_LOSS_AT_LEAST_VALUE:
			return (
				target != null
				and float(event.payload.get("accumulated_health_loss", 0.0))
				>= float(definition.parameters.get("health_loss_threshold", 0.0))
			)
		_:
			return false


func _resolve_value(
	definition: BattleEffectDefinition,
	source: BattleEffectOwnerRef,
	target: BattleSquadState,
	event: BattleRuntimeEvent
) -> float:
	var value := definition.value
	match value.kind:
		BattleEffectValue.Kind.FIXED:
			return value.amount
		BattleEffectValue.Kind.HEALTH_FRACTION:
			return float(target.get_max_health()) * value.amount
		BattleEffectValue.Kind.READ_STAT:
			if value.stat == &"current_armor": return float(target.current_armor) * value.multiplier
			if value.stat == &"current_health": return float(target.current_health) * value.multiplier
		BattleEffectValue.Kind.COUNT_SCALED:
			var count := _resolve_count_query(value.query, source, target)
			if value.max_count >= 0: count = mini(count, value.max_count)
			return float(count) * value.per_count
		BattleEffectValue.Kind.FLAG:
			return 1.0 if value.enabled else 0.0
		BattleEffectValue.Kind.ENUM_VALUE:
			return 0.0
		BattleEffectValue.Kind.FORMULA:
			if value.expression == "min(current_armor_after_damage * 0.2, 4)":
				return minf(float(target.current_armor) * 0.2, 4.0)
	_trace(event, definition, source, target, &"value", &"unsupported_value", "当前取值种类尚不能生成数字")
	return 0.0


func _resolve_count_query(query: StringName, _source: BattleEffectOwnerRef, target: BattleSquadState) -> int:
	if query == &"target_adjacent_friendly_humans":
		var count := 0
		for state: BattleSquadState in controller.get_living_states(target.side):
			if state.row_key == target.row_key and abs(state.formation_index - target.formation_index) == 1 and _is_human(state):
				count += 1
		return count
	if query == &"all_active_fire_runes_both_sides":
		var count := 0
		for state: BattleSquadState in controller.get_all_states():
			if state.alive:
				for rune: CardData.ElementType in state.get_active_runes():
					if rune == CardData.ElementType.FIRE: count += 1
		return count
	return 0


func _reserve_trigger_limit(definition: BattleEffectDefinition, source: BattleEffectOwnerRef, root_event_id: int) -> bool:
	var limit := definition.trigger_limit
	if limit == null or limit.scope == BattleEffectTriggerLimit.Scope.CONTINUOUS:
		return true
	var shared_name := String(limit.counter_key) if limit.counter_key != &"" else String(definition.effect_id)
	var key := "%d:%s:%s" % [limit.scope, shared_name, source.stable_key()]
	var last_root := int(_counter_last_root.get(key, -1))
	if last_root == root_event_id:
		return true
	# event 次数只约束当前根事件；下一个独立行动/触发必须重新拥有额度。
	# 同一根事件中的多个原子步骤仍通过 last_root 共用一次扣减。
	if limit.scope == BattleEffectTriggerLimit.Scope.EVENT and last_root != root_event_id:
		_counter_values[key] = 0
	var current := int(_counter_values.get(key, 0))
	if current >= limit.count:
		return false
	_counter_values[key] = current + 1
	_counter_last_root[key] = root_event_id
	return true


func _counter_below_limit(
	definition: BattleEffectDefinition,
	source: BattleEffectOwnerRef,
	root_event_id: int
) -> bool:
	var limit := definition.trigger_limit
	if limit == null or limit.scope == BattleEffectTriggerLimit.Scope.CONTINUOUS:
		return true
	var shared_name := String(limit.counter_key) if limit.counter_key != &"" else String(definition.effect_id)
	var key := "%d:%s:%s" % [limit.scope, shared_name, source.stable_key()]
	var current := int(_counter_values.get(key, 0))
	# 选目标前已经为本根事件预占了一次额度；条件重验时应允许这次预占本身，
	# 但其他根事件仍必须严格低于上限。
	if int(_counter_last_root.get(key, -1)) == root_event_id:
		return current <= limit.count
	return current < limit.count


func _find_active_source_instance(
	definition: BattleEffectDefinition,
	source: BattleEffectOwnerRef,
	target: BattleSquadState
) -> BattleEffectInstance:
	for instance: BattleEffectInstance in active_instances:
		if (
			instance.active
			and instance.definition.effect_id == definition.effect_id
			and instance.source.stable_key() == source.stable_key()
			and instance.target == target
		):
			return instance
	return null


func _has_living_same_race_neighbors_on_both_sides(source_state: BattleSquadState) -> bool:
	if source_state == null or not source_state.alive:
		return false
	var source_card := source_state.get_effect_source()
	if source_card == null:
		return false
	var has_left := false
	var has_right := false
	for state: BattleSquadState in controller.get_living_states(source_state.side):
		if state == source_state or state.row_key != source_state.row_key:
			continue
		var neighbor_card := state.get_effect_source()
		if neighbor_card == null or neighbor_card.race_type != source_card.race_type:
			continue
		if state.formation_index == source_state.formation_index - 1:
			has_left = true
		elif state.formation_index == source_state.formation_index + 1:
			has_right = true
	return has_left and has_right


func _binding_matches_event_actor(binding: BattleEffectBinding, event: BattleRuntimeEvent) -> bool:
	var actor := event.payload.get("actor") as BattleSquadState
	if event.trigger == BattleEffectDefinition.Trigger.DEATHRATTLE:
		# 亡语必须明确携带这次真正阵亡的单位；缺少 actor 时不能广播触发。
		return actor != null and binding.source != null and binding.source.state == actor
	if event.trigger in [
		BattleEffectDefinition.Trigger.ECHO,
		BattleEffectDefinition.Trigger.AFTER_BASIC_HEAL,
		BattleEffectDefinition.Trigger.SOURCE_ARMOR_GAINED,
		BattleEffectDefinition.Trigger.SOURCE_HEALTH_LOST_ACCUMULATED,
	]:
		# D2-3 合成测试允许直接发出无 actor 的系统触发；真实战斗钩子始终携带 actor，
		# 此时必须与效果来源一致，避免其他单位的行动或获得护甲误触发本卡。
		return actor == null or (binding.source != null and binding.source.state == actor)
	if event.trigger == BattleEffectDefinition.Trigger.ADJACENT_ALLY_DESTROYED:
		return (
			actor != null
			and binding.source != null
			and binding.source.state != null
			and binding.source.state.side == actor.side
			and binding.source.state.row_key == actor.row_key
			and abs(binding.source.state.formation_index - actor.formation_index) == 1
		)
	return true


func _get_neighbor_extra_execution_bindings(
	definition: BattleEffectDefinition,
	source: BattleEffectOwnerRef
) -> Array[BattleEffectBinding]:
	var result: Array[BattleEffectBinding] = []
	if (
		definition == null
		or source == null
		or source.state == null
		or not definition.tags.has(&"乡邻")
		or definition.modifier.mode == BattleEffectModifierSpec.Mode.EXTRA_EXECUTION
	):
		return result
	for binding: BattleEffectBinding in bindings:
		if (
			binding.enabled
			and binding.definition != null
			and binding.definition.operation == BattleEffectDefinition.Operation.MODIFY_EFFECT
			and binding.definition.modifier.mode == BattleEffectModifierSpec.Mode.EXTRA_EXECUTION
			and binding.source != null
			and binding.source.state != null
			and binding.source.state.side == source.state.side
			and binding.source.is_alive()
		):
			var tags_all: Array = binding.definition.modifier.filter.get("tags_all", []) as Array
			if tags_all.all(func(tag: Variant) -> bool: return definition.tags.has(StringName(tag))):
				result.append(binding)
	return result


func _is_human(target: BattleSquadState) -> bool:
	return target != null and target.get_effect_source() != null and target.get_effect_source().race_type == CardData.RaceType.HUMAN


func _action_type_from_name(value: StringName) -> int:
	match value:
		&"melee": return CardData.ActionType.MELEE
		&"ranged": return CardData.ActionType.RANGED
		&"magic": return CardData.ActionType.MAGIC
		&"heal": return CardData.ActionType.HEAL
		&"defense": return CardData.ActionType.DEFENSE
		_: return -1


func _adjust_current_health_for_maximum_modifier(instance: BattleEffectInstance, modifier_delta: float = 0.0) -> void:
	if (
		instance == null
		or instance.target == null
		or instance.definition == null
		or instance.definition.operation != BattleEffectDefinition.Operation.ADD_ATTRIBUTE
		or String(instance.definition.parameters.get("stat", "")) != "max_health"
	):
		return
	# 增加生命上限的效果可按定义同时补当前生命；但上限回落时
	# 不再反向扣除当前生命。这会允许当前生命暂时高于新上限。
	if bool(instance.definition.parameters.get("increase_current_health", false)) and modifier_delta > 0.0:
		instance.target.current_health = minf(
			float(instance.target.current_health) + modifier_delta,
			float(instance.target.get_max_health())
		)
	else:
		# 重新走一次 setter，让卡面立即同步未被扣除的当前生命。
		instance.target.current_health = instance.target.current_health


func _is_state_before(left: BattleSquadState, right: BattleSquadState) -> bool:
	if left.side != right.side:
		return left.side < right.side
	var left_back := String(left.row_key).ends_with("_back")
	var right_back := String(right.row_key).ends_with("_back")
	if left_back != right_back:
		return not left_back
	if left.formation_index != right.formation_index:
		return left.formation_index < right.formation_index
	return left.runtime_id < right.runtime_id


func _trace(
	event: BattleRuntimeEvent,
	definition: BattleEffectDefinition,
	source: BattleEffectOwnerRef,
	target: BattleSquadState,
	phase: StringName,
	result: StringName,
	detail: String
) -> void:
	var entry := BattleEffectTraceEntry.new()
	entry.logical_time_us = event.logical_time_us if event != null else _current_time_us()
	entry.event_id = event.event_id if event != null else 0
	entry.root_event_id = event.root_event_id if event != null else 0
	entry.parent_event_id = event.parent_event_id if event != null else 0
	entry.effect_id = definition.effect_id if definition != null else &""
	entry.effect_group = definition.effect_group if definition != null else &""
	entry.source_runtime_id = source.runtime_id if source != null else 0
	entry.target_runtime_id = target.runtime_id if target != null else 0
	entry.phase = phase
	entry.result = result
	entry.detail = detail
	traces.append(entry)
	trace_emitted.emit(entry)


func _current_time_us() -> int:
	return BattleEventQueue.seconds_to_us(controller.elapsed_seconds) if controller != null else 0
