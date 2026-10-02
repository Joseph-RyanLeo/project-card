class_name BattleDiagnosticRecorder
extends RefCounted

## 单场战斗的只读诊断采集器。回调中立即把对象引用展开成纯数据，不回看战后对象。

signal recording_completed

var capture_enabled: bool = true
var is_complete: bool = false
var record: Dictionary = {}
var _next_sequence: int = 1
var _controller: BattleController


func attach(controller: BattleController) -> void:
	_controller = controller
	if not controller.battle_initialized.is_connected(_on_battle_initialized):
		controller.battle_initialized.connect(_on_battle_initialized)
	if not controller.effect_resolved.is_connected(_on_effect_resolved):
		controller.effect_resolved.connect(_on_effect_resolved)
	if not controller.special_effect_resolved.is_connected(_on_special_effect_resolved):
		controller.special_effect_resolved.connect(_on_special_effect_resolved)
	if not controller.effect_trace_emitted.is_connected(_on_effect_trace_emitted):
		controller.effect_trace_emitted.connect(_on_effect_trace_emitted)
	if not controller.integer_settlement_resolved.is_connected(_on_integer_settlement_resolved):
		controller.integer_settlement_resolved.connect(_on_integer_settlement_resolved)
	if not controller.battle_finished.is_connected(_on_battle_finished):
		controller.battle_finished.connect(_on_battle_finished)


func detach() -> void:
	if not is_instance_valid(_controller):
		return
	if _controller.battle_initialized.is_connected(_on_battle_initialized):
		_controller.battle_initialized.disconnect(_on_battle_initialized)
	if _controller.effect_resolved.is_connected(_on_effect_resolved):
		_controller.effect_resolved.disconnect(_on_effect_resolved)
	if _controller.special_effect_resolved.is_connected(_on_special_effect_resolved):
		_controller.special_effect_resolved.disconnect(_on_special_effect_resolved)
	if _controller.effect_trace_emitted.is_connected(_on_effect_trace_emitted):
		_controller.effect_trace_emitted.disconnect(_on_effect_trace_emitted)
	if _controller.integer_settlement_resolved.is_connected(_on_integer_settlement_resolved):
		_controller.integer_settlement_resolved.disconnect(_on_integer_settlement_resolved)
	if _controller.battle_finished.is_connected(_on_battle_finished):
		_controller.battle_finished.disconnect(_on_battle_finished)
	_controller = null


func get_record_copy() -> Dictionary:
	return record.duplicate(true)


func _on_battle_initialized() -> void:
	if not capture_enabled or not is_instance_valid(_controller):
		return
	_next_sequence = 1
	is_complete = false
	record = {
		"started_at": Time.get_datetime_string_from_system(true),
		"battle_instance_id": String(_controller.battle_instance_id),
		"battle_seed": _controller.battle_seed,
		"settings": {
			"use_projectile_timing": _controller.use_projectile_timing,
			"battle_speed_multiplier": _controller.battle_speed_multiplier,
			"settings_capture_status": "captured_from_BattleController_at_initialization",
		},
		"initial_random_state": {
			"battle_controller_rng_state": _controller._random.state,
			"effect_runtime_rng_state": _controller.effect_runtime._random.state,
			"capture_phase": "after_initialize_before_rush",
			"random_sources_complete": false,
			"unknown_sources": ["战斗逻辑以外的全局随机源未纳入该战斗 RNG 快照"],
		},
		"initial_states": _snapshot_states(_controller.get_all_states()),
		"timeline": [],
		"capture_status": {
			"complete": false,
			"truncated": false,
			"truncation_reason": null,
			"unknowns": [],
			"event_count": 0,
			"effect_trace_count": 0,
			"integer_settlement_count": 0,
		},
		"final": {},
	}


func _on_effect_resolved(event: BattleEffectEvent) -> void:
	if not capture_enabled or record.is_empty() or event == null:
		return
	var type := "secondary_effect"
	if event.is_base_action:
		type = "primary_action"
	elif event.is_continuous:
		type = "continuous_effect"
	elif event.element_type >= 0:
		type = "refraction"
	elif event.effect_kind == BattleEffectEvent.EffectKind.PLACEHOLDER:
		type = "placeholder"
	var formula: Dictionary = _snapshot_formula(event.formula)
	_append_timeline({
		"record_type": "effect_event",
		"sequence": _take_sequence(),
		"logical_time_seconds": event.timestamp,
		"event_type": type,
		"group_id": event.group_id,
		"logical_layer": event.logical_layer,
		"sequence_index": event.sequence_index,
		"launch_sequence": event.launch_sequence,
		"source": _state_reference(event.source),
		"target": _state_reference(event.target),
		"anchor": _state_reference(event.anchor),
		"source_emblem_instance_id": String(event.source_emblem_instance_id),
		"source_owned_card_instance_id": String(event.source_owned_card_instance_id),
		"action_type": int(event.action_type),
		"effect_kind": int(event.effect_kind),
		"element_type": event.element_type,
		"element_count": event.element_count,
		"qualifier": event.log_qualifier,
		"visual_kind": String(event.visual_kind),
		"is_base_action": event.is_base_action,
		"is_continuous": event.is_continuous,
		"is_finisher": event.is_finisher,
		"missed": event.missed,
		"pierces_armor": event.pierces_armor,
		"armor_on_impact": event.target_had_armor_on_impact,
		"attack_type_multiplier": event.attack_type_multiplier,
		"projectile_speed_variant": event.projectile_speed_variant,
		"projectile_impact_delay": event.projectile_impact_delay,
		"impact_time_seconds": event.impact_time,
		"formula": formula,
		"amounts": {
			"formula_exact_result": event.formula.exact_result if event.formula != null else event.exact_amount,
			"event_exact_amount": event.exact_amount,
			"effective_amount": event.effective_amount,
			"armor_change": event.armor_amount,
			"health_change": event.health_amount,
			"rounding_and_fractional_channels": event.fractional_channel_snapshots.duplicate(true),
		},
		"target_after_event": _snapshot_vitals(event.target),
	})
	var status := record.capture_status as Dictionary
	status["event_count"] = int(status.get("event_count", 0)) + 1


func _on_special_effect_resolved(event: Dictionary) -> void:
	if not capture_enabled or record.is_empty() or event.is_empty():
		return
	_append_timeline({
		"record_type": "special_effect",
		"sequence": _take_sequence(),
		"logical_time_seconds": float(event.get("logical_time_seconds", _controller.elapsed_seconds)),
		"effect": event.duplicate(true),
	})
	var status := record.capture_status as Dictionary
	status["special_effect_count"] = int(status.get("special_effect_count", 0)) + 1


func _on_effect_trace_emitted(entry: BattleEffectTraceEntry) -> void:
	if not capture_enabled or record.is_empty() or entry == null:
		return
	_append_timeline({
		"record_type": "effect_trace",
		"sequence": _take_sequence(),
		"logical_time_microseconds": entry.logical_time_us,
		"event_id": entry.event_id,
		"root_event_id": entry.root_event_id,
		"parent_event_id": entry.parent_event_id,
		"effect_id": String(entry.effect_id),
		"effect_group": String(entry.effect_group),
		"source": _state_reference(_state_by_runtime_id(entry.source_runtime_id)),
		"target": _state_reference(_state_by_runtime_id(entry.target_runtime_id)),
		"phase": String(entry.phase),
		"result": String(entry.result),
		"detail": entry.detail,
	})
	var status := record.capture_status as Dictionary
	status["effect_trace_count"] = int(status.get("effect_trace_count", 0)) + 1


func _on_integer_settlement_resolved(event: Dictionary) -> void:
	if not capture_enabled or record.is_empty():
		return
	var effect_event := event.get("effect_event") as BattleEffectEvent
	_append_timeline({
		"record_type": "integer_settlement",
		"sequence": _take_sequence(),
		"logical_time_seconds": effect_event.timestamp if effect_event != null else _controller.elapsed_seconds,
		"channel": String(event.get("channel", &"")),
		"committed_integer": int(event.get("amount", 0)),
		"new_fractional_remainder": float(event.get("remainder", 0.0)),
		"state": _state_reference(event.get("state") as BattleSquadState),
		"source": _state_reference(event.get("source") as BattleSquadState),
		"effect_event_group_id": effect_event.group_id if effect_event != null else -1,
		"fractional_channel_snapshot": (
			effect_event.fractional_channel_snapshots.back().duplicate(true)
			if effect_event != null and not effect_event.fractional_channel_snapshots.is_empty()
			else {"known": false, "reason": "settlement event did not retain a fractional channel snapshot"}
		),
	})
	var status := record.capture_status as Dictionary
	status["integer_settlement_count"] = int(status.get("integer_settlement_count", 0)) + 1


func _on_battle_finished(result: BattleController.Result) -> void:
	finish(result)


func finish(result: BattleController.Result) -> void:
	if not capture_enabled or record.is_empty() or is_complete or not is_instance_valid(_controller):
		return
	record["result"] = _result_name(result)
	record["final"] = {
		"logical_time_seconds": _controller.elapsed_seconds,
		"batch_count": _controller.batch_count,
		"states": _snapshot_states(_controller.get_all_states()),
		"pending_projectiles": _controller._pending_projectile_contexts.size(),
		"random_state": {
			"battle_controller_rng_state": _controller._random.state,
			"effect_runtime_rng_state": _controller.effect_runtime._random.state,
			"random_sources_complete": false,
		},
	}
	is_complete = true
	var status := record.capture_status as Dictionary
	status["complete"] = true
	recording_completed.emit()


func _append_timeline(entry: Dictionary) -> void:
	(record.timeline as Array).append(entry)


func _take_sequence() -> int:
	var result := _next_sequence
	_next_sequence += 1
	return result


func _snapshot_formula(formula: BattleFormulaData) -> Dictionary:
	if formula == null:
		return {"available": false, "unknown_reason": "effect event had no BattleFormulaData"}
	return {
		"available": true,
		"display_name": formula.display_name,
		"action_type": int(formula.action_type),
		"base_value": formula.base_value,
		"base_value_sources": formula.base_value_sources.duplicate(true),
		"additive_terms": formula.additive_terms.duplicate(true),
		"pattern_multiplier_sources": formula.pattern_multiplier_sources.duplicate(true),
		"element_multiplier_sources": formula.element_multiplier_sources.duplicate(true),
		"action_value_modifier_sources": formula.action_value_modifier_sources.duplicate(true),
		"reinforcement_modifier_sources": formula.reinforcement_modifier_sources.duplicate(true),
		"immediate_action_source": formula.immediate_action_source.duplicate(true),
		"pattern_multiplier": formula.pattern_multiplier,
		"element_multiplier": formula.element_multiplier,
		"other_multipliers": formula.other_multipliers.duplicate(true),
		"final_flat_bonus": formula.final_flat_bonus,
		"final_flat_bonus_sources": formula.final_flat_bonus_sources.duplicate(true),
		"theoretical_result": formula.exact_result,
		"fractional_remainder": formula.fractional_remainder,
	}


func _snapshot_states(states: Array[BattleSquadState]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for state: BattleSquadState in states:
		result.append(_snapshot_state(state))
	return result


func _snapshot_state(state: BattleSquadState) -> Dictionary:
	var squad := state.squad_data
	var cards: Array[Dictionary] = []
	var card_ids: Array[String] = []
	if squad != null:
		for card_index: int in squad.horizontal_cards.size():
			var card := squad.horizontal_cards[card_index]
			var owned := squad.get_owned_card(card)
			cards.append({
				"card_index": card_index,
				"definition": _snapshot_card_definition(card),
				"owned_instance": _snapshot_owned_card(owned),
			})
			card_ids.append(String(card.id))
	var equipped := _snapshot_owned_card(squad.get_equipped_item() if squad != null else null)
	var indicators: Array[Dictionary] = squad.capture_indicators() if squad != null else []
	var source_card := state.get_effect_source()
	var stable_key := "%s|%s|%d|%s" % [
		"player" if state.side == BattleSquadState.Side.PLAYER else "enemy",
		String(state.row_key),
		state.formation_index,
		",".join(card_ids),
	]
	var pattern := squad.get_rune_pattern_result() if squad != null else null
	var active_modifiers: Array[Dictionary] = []
	for modifier: BattleModifier in state.modifiers.modifiers:
		active_modifiers.append({
			"effect_id": String(modifier.effect_id),
			"stat": int(modifier.stat),
			"mode": int(modifier.mode),
			"value": modifier.value,
			"source_instance_id": modifier.source_instance_id,
			"source_runtime_id": modifier.source_runtime_id,
			"active": modifier.active,
		})
	return {
		"cross_run_alignment_key": stable_key,
		"runtime_id": state.runtime_id,
		"owned_card_instance_ids": _owned_ids(cards, equipped),
		"side": "player" if state.side == BattleSquadState.Side.PLAYER else "enemy",
		"row_key": String(state.row_key),
		"formation_index": state.formation_index,
		"horizontal_card_order": card_ids.duplicate(),
		"layer_card_order": _card_ids(squad.layer_cards) if squad != null else [],
		"two_card_layout": int(squad.two_card_layout) if squad != null else -1,
		"cards": cards,
		"equipment": equipped,
		"indicators": indicators,
		"actual_initial_attributes": {
			"health": state.current_health,
			"armor": state.current_armor,
			"max_health": state.get_max_health(),
			"action_base_value": (
				squad.get_effective_action_base_value(state.get_unmasked_active_injuries(), true)
				if squad != null
				else 0
			),
			"action_type": int(state.get_effective_action_type()),
			"action_interval_seconds": state.get_action_interval(),
			"rune_pattern_type": int(pattern.pattern_type) if pattern != null else -1,
			"rune_pattern_name": pattern.get_pattern_name() if pattern != null else "unknown",
			"rune_elements": _effective_rune_elements(state),
			"active_rune_slots": _active_rune_slots(state),
			"vitals_source_card_id": String(state.get_vitals_source().id) if state.get_vitals_source() != null else "",
			"action_source_card_id": String(state.get_action_source().id) if state.get_action_source() != null else "",
			"effect_source_card_id": String(source_card.id) if source_card != null else "",
		},
		"vitals": _snapshot_vitals(state),
		"battle_status": {
			"alive": state.alive,
			"buff_stacks": _string_key_dictionary(state.buff_stacks),
			"active_injury_ids": _string_array(state.battle_active_injury_ids),
			"injury_levels": _string_key_dictionary(state.battle_injury_levels),
			"masked_rune_slots": _snapshot_masked_runes(state),
			"runtime_rune_overrides": _string_key_dictionary(state.runtime_rune_overrides),
			"fractional_accumulators": _string_key_dictionary(state.fractional_accumulators),
			"modifiers": active_modifiers,
			"statistics": _string_key_dictionary(state.get_battle_statistics()),
		},
	}


func _snapshot_card_definition(card: CardData) -> Dictionary:
	if card == null:
		return {"available": false, "unknown_reason": "null CardData"}
	return {
		"stable_card_id": String(card.id),
		"resource_path": card.resource_path,
		"display_name": card.display_name,
		"pack_id": String(card.pack_id),
		"card_type": int(card.card_type),
		"rarity": int(card.rarity),
		"action_type": int(card.action_type),
		"base_value": card.base_value,
		"cooldown_seconds": card.cooldown_seconds,
		"max_health": card.max_health,
		"armor": card.armor,
		"runes": _enum_array(card.runes),
		"race_type": int(card.race_type),
		"effect_ids": _string_array(card.effect_ids),
		"keywords": _string_array(card.keywords),
	}


func _snapshot_owned_card(owned: OwnedCard) -> Dictionary:
	if owned == null:
		return {"available": false}
	var card := owned.card_data
	return {
		"available": true,
		"instance_id": String(owned.instance_id),
		"stable_card_id": String(card.id) if card != null else "",
		"acquisition_order": owned.acquisition_order,
		"resolved_action_type": owned.resolved_action_type,
		"spell_durability": owned.spell_durability,
		"permanent_growth": _string_key_dictionary(owned.permanent_growth),
		"wound_slots": _json_safe(owned.wound_slots),
		"emblem_slots": _json_safe(owned.emblem_slots),
		"slot_layout": owned.slot_layout.duplicate(),
		"rune_revealed": owned.rune_revealed.duplicate(),
		"rune_stickers": _json_safe(owned.rune_stickers),
		"progress_by_source": _string_key_dictionary(owned.progress_by_source),
	}


func _snapshot_vitals(state: BattleSquadState) -> Dictionary:
	if state == null:
		return {"available": false}
	return {
		"health": state.current_health,
		"armor": state.current_armor,
		"displayed_health": state.displayed_health,
		"displayed_armor": state.displayed_armor,
		"max_health": state.get_max_health(),
	}


func _state_reference(state: BattleSquadState) -> Dictionary:
	if state == null:
		return {"available": false}
	var card_ids := _card_ids(state.squad_data.horizontal_cards) if state.squad_data != null else []
	return {
		"available": true,
		"cross_run_alignment_key": "%s|%s|%d|%s" % [
			"player" if state.side == BattleSquadState.Side.PLAYER else "enemy",
			String(state.row_key),
			state.formation_index,
			",".join(card_ids),
		],
		"runtime_id": state.runtime_id,
		"side": "player" if state.side == BattleSquadState.Side.PLAYER else "enemy",
		"row_key": String(state.row_key),
		"formation_index": state.formation_index,
		"card_ids": card_ids,
		"owned_card_instance_ids": _owned_ids_from_state(state),
	}


func _state_by_runtime_id(runtime_id: int) -> BattleSquadState:
	if runtime_id <= 0 or not is_instance_valid(_controller):
		return null
	for state: BattleSquadState in _controller.get_all_states():
		if state.runtime_id == runtime_id:
			return state
	return null


func _effective_rune_elements(state: BattleSquadState) -> Array[int]:
	var result: Array[int] = []
	if state == null:
		return result
	for slot: Dictionary in state.get_active_rune_slots():
		if bool(slot.get("hidden", false)):
			continue
		result.append(int(slot.get("element", -1)))
	return result


func _active_rune_slots(state: BattleSquadState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state == null:
		return result
	for slot: Dictionary in state.get_active_rune_slots():
		if bool(slot.get("hidden", false)):
			continue
		var card := slot.get("card") as CardData
		result.append({
			"card_id": String(card.id) if card != null else "",
			"rune_index": int(slot.get("rune_index", -1)),
			"element": int(slot.get("element", -1)),
		})
	return result


func _snapshot_masked_runes(state: BattleSquadState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in state.masked_rune_slots.values():
		if not value is Dictionary:
			continue
		var slot: Dictionary = value
		var card := slot.get("card") as CardData
		result.append({
			"card_id": String(card.id) if card != null else "",
			"rune_index": int(slot.get("rune_index", -1)),
		})
	return result


func _owned_ids(cards: Array[Dictionary], equipment: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for card: Dictionary in cards:
		var owned := card.get("owned_instance", {}) as Dictionary
		if bool(owned.get("available", false)):
			result.append(String(owned.get("instance_id", "")))
	if bool(equipment.get("available", false)):
		result.append(String(equipment.get("instance_id", "")))
	return result


func _owned_ids_from_state(state: BattleSquadState) -> Array[String]:
	var result: Array[String] = []
	if state == null or state.squad_data == null:
		return result
	for card: CardData in state.squad_data.horizontal_cards:
		var owned := state.squad_data.get_owned_card(card)
		if owned != null:
			result.append(String(owned.instance_id))
	var equipment := state.squad_data.get_equipped_item()
	if equipment != null:
		result.append(String(equipment.instance_id))
	return result


func _card_ids(cards: Array[CardData]) -> Array[String]:
	var result: Array[String] = []
	for card: CardData in cards:
		result.append(String(card.id) if card != null else "")
	return result


func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(String(value))
	return result


func _enum_array(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	return result


func _string_key_dictionary(values: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in values.keys():
		result[str(key)] = _json_safe(values[key])
	return result


func _json_safe(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		var source: Dictionary = value
		for key: Variant in source.keys():
			result[str(key)] = _json_safe(source[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_json_safe(item))
		return result
	if value is StringName:
		return str(value)
	if value is Object:
		var object: Object = value
		if object is CardData:
			return {"resource_type": "CardData", "stable_card_id": String((object as CardData).id)}
		if object is OwnedCard:
			return {"resource_type": "OwnedCard", "instance_id": String((object as OwnedCard).instance_id)}
		return {"available": false, "unknown_reason": "unsupported object value", "class_name": object.get_class()}
	return value


func _result_name(result: BattleController.Result) -> String:
	match result:
		BattleController.Result.PLAYER_VICTORY:
			return "player_victory"
		BattleController.Result.PLAYER_DEFEAT:
			return "player_defeat"
		BattleController.Result.DRAW:
			return "draw"
	return "unknown"
