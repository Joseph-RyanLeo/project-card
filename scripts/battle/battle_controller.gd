class_name BattleController
extends Node

## 敌我双方共用的自动战斗时间轴与分层批次协调器。
## 目标先按逻辑层统一选完，再执行该层全部效果，场景节点不参与规则判断。

const BattleSquadState = preload("res://scripts/battle/battle_squad_state.gd")
const BattleEffectEvent = preload("res://scripts/battle/battle_effect_event.gd")
const BattleFormulaData = preload("res://scripts/battle/battle_formula_data.gd")
const BattleElementResolver = preload("res://scripts/battle/battle_element_resolver.gd")
const BattleAttackEffectProfiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
const BattleProjectileTiming = preload("res://scripts/battle/battle_projectile_timing.gd")
const BattleEffectRuntime = preload("res://scripts/battle/effects/battle_effect_runtime.gd")
const BattleEffectCatalog = preload("res://scripts/battle/effects/battle_effect_catalog.gd")
const BattlePermanentGrowthLedger = preload("res://scripts/battle/battle_permanent_growth_ledger.gd")
const BattleRunRewardLedger = preload("res://scripts/battle/battle_run_reward_ledger.gd")
const BattleOwnedCardChangeLedger = preload("res://scripts/battle/battle_owned_card_change_ledger.gd")

const EFFECT_DATA_PATH: String = "res://data/demo2/ash_ledger_effect_samples.json"

signal states_changed
signal action_resolved(actor: BattleSquadState, target: BattleSquadState, action_type: CardData.ActionType, amount: int)
signal projectile_launched(event: BattleEffectEvent)
signal effect_resolved(event: BattleEffectEvent)
signal integer_settlement_resolved(event: Dictionary)
signal kill_resolved(killer: BattleSquadState, target: BattleSquadState, event: BattleEffectEvent)
signal squad_defeated(state: BattleSquadState)
signal squad_revived(state: BattleSquadState)
signal buff_stacks_changed(state: BattleSquadState, buff_id: StringName, stacks: int)
signal direct_damage_resolved(state: BattleSquadState, source_id: StringName, amount: int)
signal effect_trace_emitted(entry: BattleEffectTraceEntry)
signal permanent_growth_recorded(entry: Dictionary)
signal pending_run_reward_recorded(entry: Dictionary)
signal pending_owned_card_change_recorded(entry: Dictionary)
signal battle_finished(result: Result)
signal indicator_transferred(indicator: CelestialIndicator, source: BattleSquadState, target: BattleSquadState)

enum Result { NONE, PLAYER_VICTORY, PLAYER_DEFEAT, DRAW }

const COOLDOWN_EPSILON: float = 0.0001 # 同一时间点冷却完成的浮点判断容差（秒）

var player_states: Array[BattleSquadState] = []
var enemy_states: Array[BattleSquadState] = []
var current_result: Result = Result.NONE
var elapsed_seconds: float = 0.0
var batch_count: int = 0
var battle_speed_multiplier: float = 1.0
var use_projectile_timing: bool = false
var active_continuous_effects: Array[Dictionary] = []
var battle_seed: int = 0
var battle_instance_id: StringName = &"" # 一次战前快照对应的稳定身份；战后账本与防重复提交共用
var effect_runtime := BattleEffectRuntime.new()
var effect_catalog: BattleEffectCatalog
var permanent_growth_ledger := BattlePermanentGrowthLedger.new()
var run_reward_ledger := BattleRunRewardLedger.new()
var owned_card_change_ledger := BattleOwnedCardChangeLedger.new()

var _random := RandomNumberGenerator.new()
var _running: bool = false
var _next_fatigue_stack_seconds: float = BattleRules.FATIGUE_START_SECONDS
var _next_fatigue_damage_seconds: float = BattleRules.FATIGUE_START_SECONDS
var _next_group_id: int = 1
var _continuous_followups: Dictionary = {}
var _pending_projectile_contexts: Dictionary = {}
var _pending_projectile_batch_counts: Dictionary = {}
var _next_projectile_batch_id: int = 1
var _next_projectile_launch_sequence: int = 1
var _next_state_runtime_id: int = 1
var _next_local_battle_sequence: int = 1


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	advance_time(delta * battle_speed_multiplier)


func start_battle(
	player_formation: Array[Dictionary],
	enemy_formation: Array[Dictionary],
	random_seed: int = -1,
	auto_run: bool = true,
	requested_battle_instance_id: StringName = &""
) -> void:
	battle_instance_id = _resolve_battle_instance_id(requested_battle_instance_id)
	_initialize_battle_state(player_formation, enemy_formation, random_seed)
	if not effect_runtime.bindings.is_empty():
		effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.RUSH)
		effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.CONTINUOUS)
		effect_runtime.process_due(elapsed_seconds)
	_running = true
	recalculate_logical_layout()
	set_process(auto_run)
	states_changed.emit()
	_check_battle_result()


func prepare_battle_preview(player_formation: Array[Dictionary], enemy_formation: Array[Dictionary], random_seed: int = -1) -> void:
	## 只建立站位并结算持续光环；不会触发突击、推进时间或产生战斗结果。
	battle_instance_id = &""
	_initialize_battle_state(player_formation, enemy_formation, random_seed)
	if not effect_runtime.bindings.is_empty():
		effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.CONTINUOUS)
		effect_runtime.process_due(elapsed_seconds)
	stop_battle()
	recalculate_logical_layout()
	states_changed.emit()


func _initialize_battle_state(player_formation: Array[Dictionary], enemy_formation: Array[Dictionary], random_seed: int) -> void:
	stop_battle()
	_release_current_states()
	_next_state_runtime_id = 1
	player_states = _create_states(player_formation, BattleSquadState.Side.PLAYER)
	enemy_states = _create_states(enemy_formation, BattleSquadState.Side.ENEMY)
	current_result = Result.NONE
	elapsed_seconds = 0.0
	batch_count = 0
	_next_group_id = 1
	_next_projectile_batch_id = 1
	_next_projectile_launch_sequence = 1
	active_continuous_effects.clear()
	_continuous_followups.clear()
	permanent_growth_ledger.clear()
	run_reward_ledger.clear()
	owned_card_change_ledger.clear()
	_next_fatigue_stack_seconds = BattleRules.FATIGUE_START_SECONDS
	_next_fatigue_damage_seconds = BattleRules.FATIGUE_START_SECONDS
	if random_seed >= 0:
		battle_seed = random_seed
		_random.seed = random_seed
	else:
		_random.randomize()
		battle_seed = _random.seed
	effect_runtime.initialize(self, battle_seed)
	if not effect_runtime.trace_emitted.is_connected(_on_effect_trace_emitted):
		effect_runtime.trace_emitted.connect(_on_effect_trace_emitted)
	_register_formation_card_effects()
	recalculate_logical_layout()


func _register_formation_card_effects() -> void:
	if effect_catalog == null:
		effect_catalog = BattleEffectCatalog.load_from_file(EFFECT_DATA_PATH)
	if not effect_catalog.is_valid():
		for error: String in effect_catalog.errors:
			push_error(error)
		return
	for state: BattleSquadState in get_all_states():
		var card := state.get_effect_source()
		_register_card_effects(state, card)
		var equipped_item := (
			state.squad_data.get_equipped_item()
			if state.squad_data != null
			else null
		)
		if equipped_item != null:
			_register_card_effects(state, equipped_item.card_data, true)


func _register_card_effects(
	state: BattleSquadState,
	card: CardData,
	is_equipment: bool = false
) -> void:
	if card == null or not card.is_available:
		return
	for effect_id: StringName in card.effect_ids:
		var definition := effect_catalog.get_definition(effect_id)
		if definition == null:
			push_error("卡牌 %s 绑定了效果目录中不存在的效果：%s" % [card.id, effect_id])
			continue
		if is_equipment and definition.source_owner != BattleEffectDefinition.OwnerKind.EQUIPMENT_INSTANCE:
			push_error("装备 %s 的效果 %s 必须以 equipment_instance 为来源" % [card.id, effect_id])
			continue
		effect_runtime.register_definition(
			definition,
			BattleEffectOwnerRef.for_state(state, definition.source_owner)
		)


func stop_battle() -> void:
	_running = false
	set_process(false)
	_pending_projectile_contexts.clear()
	_pending_projectile_batch_counts.clear()


func clear_battle() -> void:
	stop_battle()
	_release_current_states()
	active_continuous_effects.clear()
	_continuous_followups.clear()
	current_result = Result.NONE
	elapsed_seconds = 0.0
	batch_count = 0
	_next_group_id = 1
	_next_projectile_batch_id = 1
	_next_projectile_launch_sequence = 1
	_next_state_runtime_id = 1
	_next_fatigue_stack_seconds = BattleRules.FATIGUE_START_SECONDS
	_next_fatigue_damage_seconds = BattleRules.FATIGUE_START_SECONDS
	_random = RandomNumberGenerator.new()
	effect_runtime.initialize(self, 0)
	battle_instance_id = &""
	permanent_growth_ledger.clear()
	run_reward_ledger.clear()
	owned_card_change_ledger.clear()


func _release_current_states() -> void:
	for state: BattleSquadState in get_all_states():
		state.force_boundary_sync()
		state.clear_precise_runtime()
		if state.integer_settlement_committed.is_connected(_on_integer_settlement_committed):
			state.integer_settlement_committed.disconnect(_on_integer_settlement_committed)
		if state.health_lost_accumulated.is_connected(_on_health_lost_accumulated):
			state.health_lost_accumulated.disconnect(_on_health_lost_accumulated)
	player_states.clear()
	enemy_states.clear()


func is_running() -> bool:
	return _running


func set_battle_speed_multiplier(value: float) -> void:
	battle_speed_multiplier = clampf(value, 1.0, 3.0)


func get_all_states() -> Array[BattleSquadState]:
	var states: Array[BattleSquadState] = []
	states.append_array(player_states)
	states.append_array(enemy_states)
	return states


func get_living_states(side: int) -> Array[BattleSquadState]:
	var living: Array[BattleSquadState] = []
	var source := player_states if side == BattleSquadState.Side.PLAYER else enemy_states
	for state: BattleSquadState in source:
		if state.alive:
			living.append(state)
	return living


func revive_state_at_original_position(
	state: BattleSquadState,
	health_amount: float
) -> bool:
	if state == null or state.alive or state.current_health > 0.0:
		return false
	for candidate: BattleSquadState in get_all_states():
		if (
			candidate != state
			and candidate.alive
			and candidate.side == state.side
			and candidate.row_key == state.row_key
			and candidate.formation_index == state.formation_index
		):
			return false
	if not state.revive_at_current_maximum(health_amount):
		return false
	recalculate_logical_layout()
	effect_runtime.recheck_continuous_conditions()
	squad_revived.emit(state)
	states_changed.emit()
	return true


func record_pending_permanent_growth(
	owner: BattleEffectOwnerRef,
	stat: StringName,
	amount: float,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int
) -> bool:
	if not permanent_growth_ledger.record(
		owner,
		stat,
		amount,
		effect_id,
		source_runtime_id,
		logical_time_us,
		battle_instance_id
	):
		return false
	var entries := permanent_growth_ledger.get_entries()
	permanent_growth_recorded.emit(entries[-1])
	return true


func record_pending_run_reward(
	owner: BattleEffectOwnerRef,
	kind: StringName,
	amount: int,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int,
	parameters: Dictionary = {}
) -> bool:
	if not run_reward_ledger.record(
		owner,
		kind,
		amount,
		effect_id,
		source_runtime_id,
		logical_time_us,
		parameters,
		battle_instance_id
	):
		return false
	var entries := run_reward_ledger.get_entries()
	pending_run_reward_recorded.emit(entries[-1])
	return true


func record_pending_owned_card_slot_change(
	owner: BattleEffectOwnerRef,
	kind: StringName,
	slot_index: int,
	slot_state: Dictionary,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int
) -> bool:
	if not owned_card_change_ledger.record_slot_change(
		owner,
		kind,
		slot_index,
		slot_state,
		effect_id,
		source_runtime_id,
		logical_time_us,
		battle_instance_id
	):
		return false
	var entries := owned_card_change_ledger.get_entries()
	pending_owned_card_change_recorded.emit(entries[-1])
	return true


func record_pending_equipment_consumption(
	owner: BattleEffectOwnerRef,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int
) -> bool:
	return owned_card_change_ledger.record_equipment_consumption(
		owner, effect_id, source_runtime_id, logical_time_us, battle_instance_id
	)


func record_pending_emblem_progress(
	owner: BattleEffectOwnerRef,
	emblem_instance_id: StringName,
	amount: int,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int
) -> bool:
	if not owned_card_change_ledger.record_emblem_progress(
		owner,
		emblem_instance_id,
		amount,
		effect_id,
		source_runtime_id,
		logical_time_us,
		battle_instance_id
	):
		return false
	var entries := owned_card_change_ledger.get_entries()
	pending_owned_card_change_recorded.emit(entries[-1])
	return true


func _resolve_battle_instance_id(requested_id: StringName) -> StringName:
	if not requested_id.is_empty():
		return requested_id
	var result := StringName("controller_battle_%06d" % _next_local_battle_sequence)
	_next_local_battle_sequence += 1
	return result


func advance_time(delta: float) -> void:
	var time_left := maxf(delta, 0.0)
	while _running and time_left > COOLDOWN_EPSILON:
		var next_time := _get_next_event_delay()
		if not is_finite(next_time):
			return
		if time_left + COOLDOWN_EPSILON < next_time:
			_decrease_living_cooldowns(time_left)
			elapsed_seconds += time_left
			states_changed.emit()
			return
		_decrease_living_cooldowns(next_time)
		elapsed_seconds += next_time
		time_left -= next_time
		_resolve_ready_batch()


func resolve_next_batch() -> bool:
	if not _running:
		return false
	var next_time := _get_next_event_delay()
	if not is_finite(next_time):
		return false
	_decrease_living_cooldowns(next_time)
	elapsed_seconds += next_time
	_resolve_ready_batch()
	return true


func choose_weighted_target(candidates: Array[BattleSquadState], forced_roll: int = -1) -> BattleSquadState:
	var valid: Array[BattleSquadState] = []
	var total_weight := 0
	for candidate: BattleSquadState in candidates:
		if candidate != null and candidate.alive and candidate.current_health > 0.0:
			valid.append(candidate)
			total_weight += get_effective_target_weight(candidate)
	if valid.is_empty() or total_weight <= 0:
		return null
	var roll := clampi(forced_roll, 0, total_weight - 1) if forced_roll >= 0 else _random.randi_range(0, total_weight - 1)
	var boundary := 0
	for candidate: BattleSquadState in valid:
		boundary += get_effective_target_weight(candidate)
		if roll < boundary:
			return candidate
	return valid[-1]


func choose_base_target(
	actor: BattleSquadState,
	candidates: Array[BattleSquadState],
	action_type: CardData.ActionType,
	forced_roll: int = -1
) -> BattleSquadState:
	# 治疗和防御选友军，不能让敌方攻击的耀眼规则改写它们的目标池。
	if action_type in [CardData.ActionType.HEAL, CardData.ActionType.DEFENSE]:
		return choose_weighted_target(candidates, forced_roll)
	if actor == null:
		return null
	var preference := actor.get_target_action_type_preference()
	var source := actor.get_effect_source()
	var beast_attack := source != null and source.race_type == CardData.RaceType.BEAST
	var best_tier := 5
	var tier_candidates: Array[BattleSquadState] = []
	for candidate: BattleSquadState in candidates:
		if candidate == null or not candidate.alive or candidate.current_health <= 0.0 or candidate.moon_shadowed or get_effective_target_weight(candidate) <= 0:
			continue
		var tier := _attack_target_tier(candidate, preference, beast_attack)
		if tier < best_tier:
			best_tier = tier
			tier_candidates.clear()
		if tier == best_tier:
			tier_candidates.append(candidate)
	return choose_weighted_target(tier_candidates, forced_roll)


func _attack_target_tier(candidate: BattleSquadState, preference: int, beast_attack: bool) -> int:
	# “野兽不会优先攻击”高于耀眼及常规类型偏好，但并不使目标永久不可选。
	if beast_attack and candidate.has_targeting_keyword(&"beast_last"):
		return 4
	var dazzling := has_effective_dazzling(candidate)
	if preference >= 0:
		if candidate.get_effective_action_type() == preference:
			return 0 if dazzling else 1
		return 2 if dazzling else 3
	return 0 if dazzling else 1


func has_effective_dazzling(candidate: BattleSquadState) -> bool:
	if candidate.squad_data.has_indicator(CelestialIndicator.Kind.SUN):
		return true
	for state: BattleSquadState in get_all_states():
		if state.alive and state.current_health > 0.0 and state.squad_data.has_indicator(CelestialIndicator.Kind.SUN):
			return false
	return candidate.squad_data.has_indicator(CelestialIndicator.Kind.STAR) or candidate.has_targeting_keyword(&"dazzling")


func _on_indicator_action_launched(actor: BattleSquadState) -> void:
	if actor == null or not actor.squad_data.has_indicator(CelestialIndicator.Kind.MOON):
		return
	actor.moon_shadowed = false
	if not is_finite(actor.moon_restore_time):
		actor.moon_restore_time = elapsed_seconds + CelestialIndicator.MOON_RESTORE_SECONDS


func _transfer_defeated_star(source: BattleSquadState) -> void:
	if not source.squad_data.has_indicator(CelestialIndicator.Kind.STAR):
		return
	var candidates: Array[BattleSquadState] = []
	for target: BattleSquadState in get_all_states():
		if target != source and target.side == source.side and target.alive and target.current_health > 0.0 and not target.squad_data.has_indicator(CelestialIndicator.Kind.STAR):
			candidates.append(target)
	if candidates.is_empty():
		return
	var target := candidates[_random.randi_range(0, candidates.size() - 1)]
	for attachment: Dictionary in source.squad_data.indicator_attachments:
		var indicator := attachment["indicator"] as CelestialIndicator
		if indicator.kind != CelestialIndicator.Kind.STAR:
			continue
		target.squad_data.attach_indicator(indicator, attachment["position"], int(attachment["order"]))
		source.squad_data.detach_indicator(indicator.instance_id)
		var bonus := BattleModifier.new()
		bonus.stat = BattleModifier.Stat.ACTION_VALUE
		bonus.value = 1.0
		bonus.effect_id = &"star_transfer"
		bonus.source_runtime_id = source.runtime_id
		target.modifiers.add_modifier(bonus)
		indicator_transferred.emit(indicator, source, target)
		break


func get_effective_target_weight(state: BattleSquadState) -> int:
	var base_weight := state.get_target_weight()
	if base_weight <= 0:
		return 0
	var penalty := 1 if is_back_row(state.row_key) and get_front_cover_ratio(state) > BattleRules.FRONT_COVER_THRESHOLD else 0
	return maxi(base_weight - penalty, 1)


func recalculate_logical_layout() -> void:
	var rows: Dictionary = {}
	for state: BattleSquadState in get_all_states():
		if state.alive and state.current_health > 0.0:
			if not rows.has(state.row_key):
				rows[state.row_key] = []
			(rows[state.row_key] as Array).append(state)
	for row_value: Variant in rows.values():
		var row_states: Array = row_value as Array
		row_states.sort_custom(func(left: BattleSquadState, right: BattleSquadState) -> bool: return left.formation_index < right.formation_index)
		var total_width := BattleRules.LOGICAL_SQUAD_GAP * maxf(float(row_states.size() - 1), 0.0)
		for state: BattleSquadState in row_states:
			total_width += float(state.squad_data.get_display_width())
		var cursor := (BattleRules.LOGICAL_ROW_WIDTH - total_width) * 0.5
		for state: BattleSquadState in row_states:
			var width := float(state.squad_data.get_display_width())
			state.logical_left = cursor
			state.logical_right = cursor + width
			state.logical_center = cursor + width * 0.5
			cursor += width + BattleRules.LOGICAL_SQUAD_GAP


func get_front_cover_ratio(back_state: BattleSquadState) -> float:
	if back_state == null or not is_back_row(back_state.row_key):
		return 0.0
	var width := back_state.logical_right - back_state.logical_left
	if width <= 0.0:
		return 0.0
	var intervals: Array[Vector2] = []
	var front_key := _front_row_for_side(back_state.side)
	for state: BattleSquadState in get_all_states():
		if state.side != back_state.side or state.row_key != front_key or not state.alive or state.current_health <= 0.0:
			continue
		var left := maxf(back_state.logical_left, state.logical_left)
		var right := minf(back_state.logical_right, state.logical_right)
		if right > left:
			intervals.append(Vector2(left, right))
	if intervals.is_empty():
		return 0.0
	intervals.sort_custom(func(left: Vector2, right: Vector2) -> bool: return left.x < right.x)
	var covered := 0.0
	var union_left := intervals[0].x
	var union_right := intervals[0].y
	for index: int in range(1, intervals.size()):
		if intervals[index].x <= union_right:
			union_right = maxf(union_right, intervals[index].y)
		else:
			covered += union_right - union_left
			union_left = intervals[index].x
			union_right = intervals[index].y
	covered += union_right - union_left
	return covered / width


static func is_back_row(row_key: StringName) -> bool:
	return String(row_key).ends_with("_back")


func _create_states(formation: Array[Dictionary], side: int) -> Array[BattleSquadState]:
	var states: Array[BattleSquadState] = []
	for entry: Dictionary in formation:
		var squad := entry.get("squad_data") as SquadData
		if squad == null or not squad.is_valid():
			continue
		var state := BattleSquadState.new()
		state.runtime_id = _next_state_runtime_id
		_next_state_runtime_id += 1
		state.initialize(
			squad,
			side,
			StringName(entry.get("row_key", &"")),
			int(entry.get("formation_index", states.size())),
			float(entry.get("base_cooldown_override", -1.0))
		)
		state.integer_settlement_committed.connect(_on_integer_settlement_committed)
		state.health_lost_accumulated.connect(_on_health_lost_accumulated)
		states.append(state)
	return states


func _get_next_cooldown() -> float:
	var next_time := INF
	for state: BattleSquadState in get_all_states():
		if state.alive and state.current_health > 0.0:
			next_time = minf(next_time, maxf(state.remaining_cooldown, 0.0))
	return next_time


func _get_next_event_delay() -> float:
	var next_time := _get_next_cooldown()
	for state: BattleSquadState in get_all_states():
		if state.alive and is_finite(state.moon_restore_time):
			next_time = minf(next_time, maxf(state.moon_restore_time - elapsed_seconds, 0.0))
	var next_effect_time := effect_runtime.get_next_event_time_seconds()
	if is_finite(next_effect_time):
		next_time = minf(next_time, maxf(next_effect_time - elapsed_seconds, 0.0))
	for event_value: Variant in _pending_projectile_contexts:
		var event := event_value as BattleEffectEvent
		next_time = minf(next_time, maxf(event.impact_time - elapsed_seconds, 0.0))
	next_time = minf(next_time, maxf(_next_fatigue_stack_seconds - elapsed_seconds, 0.0))
	next_time = minf(next_time, maxf(_next_fatigue_damage_seconds - elapsed_seconds, 0.0))
	for status: Dictionary in active_continuous_effects:
		next_time = minf(next_time, maxf(float(status["next_time"]) - elapsed_seconds, 0.0))
	return next_time


func _decrease_living_cooldowns(amount: float) -> void:
	for state: BattleSquadState in get_all_states():
		if state.alive:
			state.advance_action_cooldown(amount)


func _resolve_ready_batch() -> void:
	for state: BattleSquadState in get_all_states():
		if state.alive and state.moon_restore_time <= elapsed_seconds + COOLDOWN_EPSILON:
			state.moon_shadowed = state.squad_data.has_indicator(CelestialIndicator.Kind.MOON)
			state.moon_restore_time = INF
	effect_runtime.process_due(elapsed_seconds)
	if use_projectile_timing:
		_resolve_ready_projectile_batch()
		return
	recalculate_logical_layout()
	var living_snapshot := get_all_states().filter(
		func(state: BattleSquadState) -> bool:
			return state.alive and state.current_health > 0.0
	)
	var actors: Array[BattleSquadState] = []
	for state: BattleSquadState in living_snapshot:
		if state.remaining_cooldown <= COOLDOWN_EPSILON:
			actors.append(state)
	actors.sort_custom(_is_actor_before)
	var actions := _select_base_actions(actors, living_snapshot)
	for action: Dictionary in actions:
		_on_indicator_action_launched(action["actor"])
	var layer_zero: Array[BattleEffectEvent] = _collect_due_continuous_events()
	var fatigue_events := _prepare_fatigue_events(living_snapshot)
	layer_zero.append_array(fatigue_events)
	for action: Dictionary in actions:
		layer_zero.append(action["base_event"] as BattleEffectEvent)
	_resolve_effect_layer(layer_zero)
	for event: BattleEffectEvent in fatigue_events:
		direct_damage_resolved.emit(event.target, BattleRules.FATIGUE_BUFF_ID, roundi(event.effective_amount))

	var carriers_by_action: Array[Array] = []
	for action: Dictionary in actions:
		carriers_by_action.append([action["base_event"] as BattleEffectEvent])
	# 两个元素组最多形成两个额外逻辑层。每层必须先为全部行动者选完目标，
	# 才统一执行数值，不能让 actions 数组顺序形成隐性先手。
	for group_index: int in 2:
		var layer_events: Array[BattleEffectEvent] = []
		if group_index == 0:
			layer_events.append_array(_build_due_continuous_followups())
		var next_carriers: Array[Array] = []
		next_carriers.resize(actions.size())
		for action_index: int in actions.size():
			var action: Dictionary = actions[action_index]
			var groups := action["element_groups"] as Array
			var action_events: Array[BattleEffectEvent] = []
			if group_index < groups.size():
				for carrier_value: Variant in carriers_by_action[action_index]:
					action_events.append_array(_build_element_events(action, carrier_value as BattleEffectEvent, groups[group_index], group_index + 1))
			elif group_index == 0 and (action["pattern"] as RunePatternResult).pattern_type == RunePatternResult.PatternType.STRAIGHT:
				action_events.append_array(_build_straight_bonus_events(action, action["base_event"] as BattleEffectEvent, group_index + 1))
			next_carriers[action_index] = action_events
			layer_events.append_array(action_events)
		_resolve_effect_layer(layer_events)
		carriers_by_action = next_carriers
		recalculate_logical_layout()

	_finalize_batch()
	batch_count += 1
	states_changed.emit()
	_check_battle_result()


func _resolve_ready_projectile_batch() -> void:
	## 固定逻辑时轴先处理已到达弹道，再处理同刻计时事件和新行动。
	recalculate_logical_layout()
	_resolve_due_projectile_impacts()
	if not _running:
		return
	var living_snapshot := get_all_states().filter(
		func(state: BattleSquadState) -> bool:
			return state.alive and state.current_health > 0.0
	)
	var actors: Array[BattleSquadState] = []
	for state: BattleSquadState in living_snapshot:
		if state.remaining_cooldown <= COOLDOWN_EPSILON:
			actors.append(state)
	actors.sort_custom(_is_actor_before)
	var actions := _select_base_actions(actors, living_snapshot)
	var immediate_events: Array[BattleEffectEvent] = _collect_due_continuous_events()
	var fatigue_events := _prepare_fatigue_events(living_snapshot)
	immediate_events.append_array(fatigue_events)
	if actions.is_empty() and immediate_events.is_empty():
		return
	_resolve_effect_layer(immediate_events)
	for event: BattleEffectEvent in fatigue_events:
		direct_damage_resolved.emit(event.target, BattleRules.FATIGUE_BUFF_ID, roundi(event.effective_amount))
	if actions.is_empty():
		_finalize_batch()
		batch_count += 1
		states_changed.emit()
		_check_battle_result()
		return
	var projectile_batch_id := _next_projectile_batch_id
	_next_projectile_batch_id += 1
	_pending_projectile_batch_counts[projectile_batch_id] = 0
	var base_events: Array[BattleEffectEvent] = []
	for action: Dictionary in actions:
		var event := action["base_event"] as BattleEffectEvent
		_register_projectile(event, action, 0, projectile_batch_id)
		base_events.append(event)
	if base_events.is_empty():
		_complete_projectile_batch(projectile_batch_id)
		return
	_launch_registered_projectiles(base_events)


func _resolve_projectile_impact(event: BattleEffectEvent) -> void:
	if not _pending_projectile_contexts.has(event):
		return
	var context := _pending_projectile_contexts[event] as Dictionary
	var projectile_batch_id := int(context["projectile_batch_id"])
	_pending_projectile_contexts.erase(event)
	_pending_projectile_batch_counts[projectile_batch_id] = int(_pending_projectile_batch_counts[projectile_batch_id]) - 1
	event.timestamp = elapsed_seconds
	_resolve_arrived_event(event)
	var followups := _build_projectile_followups(event, context)
	for followup: BattleEffectEvent in followups:
		_register_projectile(
			followup,
			context["action"] as Dictionary,
			int(context["next_group_index"]) + 1,
			projectile_batch_id
		)
	if not followups.is_empty():
		_launch_registered_projectiles(followups)
	if int(_pending_projectile_batch_counts.get(projectile_batch_id, 0)) <= 0:
		_complete_projectile_batch(projectile_batch_id)


func _resolve_due_projectile_impacts() -> void:
	var due_events: Array[BattleEffectEvent] = []
	for event_value: Variant in _pending_projectile_contexts:
		var event := event_value as BattleEffectEvent
		if event.impact_time <= elapsed_seconds + COOLDOWN_EPSILON:
			due_events.append(event)
	due_events.sort_custom(func(left: BattleEffectEvent, right: BattleEffectEvent) -> bool:
		if not is_equal_approx(left.impact_time, right.impact_time):
			return left.impact_time < right.impact_time
		return left.launch_sequence < right.launch_sequence
	)
	for event: BattleEffectEvent in due_events:
		_resolve_projectile_impact(event)


func _register_projectile(event: BattleEffectEvent, action: Dictionary, next_group_index: int, projectile_batch_id: int) -> void:
	event.launch_sequence = _next_projectile_launch_sequence
	_next_projectile_launch_sequence += 1
	event.projectile_speed_variant = _random.randi_range(
		0,
		BattleProjectileTiming.TRAVEL_SPEED_VARIANT_COUNT - 1
	)
	var profile := BattleAttackEffectProfiles.get_profile(_visual_kind_for_event(event))
	event.projectile_impact_delay = BattleProjectileTiming.calculate_impact_delay(
		profile,
		event.projectile_speed_variant
	)
	event.impact_time = elapsed_seconds + event.projectile_impact_delay
	_pending_projectile_contexts[event] = {
		"action": action,
		"next_group_index": next_group_index,
		"projectile_batch_id": projectile_batch_id,
	}
	_pending_projectile_batch_counts[projectile_batch_id] = int(_pending_projectile_batch_counts.get(projectile_batch_id, 0)) + 1


func _launch_registered_projectiles(events: Array[BattleEffectEvent]) -> void:
	for event: BattleEffectEvent in events:
		if event.effect_kind == BattleEffectEvent.EffectKind.PLACEHOLDER:
			_resolve_projectile_impact(event)
		else:
			projectile_launched.emit(event)
			if event.is_base_action:
				_on_indicator_action_launched(event.source)
				effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": event.source})
				effect_runtime.process_due(elapsed_seconds)


func _resolve_arrived_event(event: BattleEffectEvent) -> void:
	# 生命归零、正式退场或放逐都会让已锁定的主效果命中空位；元素链仍以原锚点继续判断。
	if event.target == null or not event.target.alive or event.target.current_health <= 0.0:
		event.missed = true
		event.effective_amount = 0.0
		effect_resolved.emit(event)
		if event.is_base_action:
			action_resolved.emit(event.source, event.target, event.action_type, 0)
		return
	_apply_effect_event(event)


func _build_projectile_followups(event: BattleEffectEvent, context: Dictionary) -> Array[BattleEffectEvent]:
	var action := context["action"] as Dictionary
	var group_index := int(context["next_group_index"])
	var groups := action["element_groups"] as Array
	if group_index < groups.size():
		return _build_element_events(action, event, groups[group_index], group_index + 1)
	if group_index == 0 and (action["pattern"] as RunePatternResult).pattern_type == RunePatternResult.PatternType.STRAIGHT:
		return _build_straight_bonus_events(action, event, 1)
	return []


func _complete_projectile_batch(projectile_batch_id: int) -> void:
	_pending_projectile_batch_counts.erase(projectile_batch_id)
	_finalize_batch()
	batch_count += 1
	states_changed.emit()
	if _pending_projectile_contexts.is_empty():
		_check_battle_result()


func _select_base_actions(actors: Array[BattleSquadState], living_snapshot: Array) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for actor: BattleSquadState in actors:
		var action := _build_action(actor, living_snapshot, actor.get_effective_action_type())
		if not action.is_empty():
			actions.append(action)
		actor.reset_action_cooldown()
	return actions


func execute_immediate_action(
	actor: BattleSquadState,
	action_type: CardData.ActionType,
	action_value_delta: float = 0.0
) -> bool:
	if actor == null or not actor.alive or actor.current_health <= 0.0:
		return false
	var living_snapshot := get_all_states().filter(
		func(state: BattleSquadState) -> bool:
			return state.alive and state.current_health > 0.0
	)
	var action := _build_action(actor, living_snapshot, action_type, action_value_delta)
	if action.is_empty():
		return false
	actor.reset_action_cooldown()
	var base_event := action["base_event"] as BattleEffectEvent
	if use_projectile_timing:
		var projectile_batch_id := _next_projectile_batch_id
		_next_projectile_batch_id += 1
		_pending_projectile_batch_counts[projectile_batch_id] = 0
		_register_projectile(base_event, action, 0, projectile_batch_id)
		_launch_registered_projectiles([base_event])
		return true
	# 无弹道计时时仍发出“已发射”信号，再同步结算命中，保持事件语义一致。
	projectile_launched.emit(base_event)
	_on_indicator_action_launched(actor)
	effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": actor})
	effect_runtime.process_due(elapsed_seconds)
	_resolve_effect_layer([base_event])
	var carriers: Array[BattleEffectEvent] = [base_event]
	var groups := action["element_groups"] as Array
	for group_index: int in 2:
		var layer_events: Array[BattleEffectEvent] = []
		if group_index < groups.size():
			for carrier: BattleEffectEvent in carriers:
				layer_events.append_array(_build_element_events(action, carrier, groups[group_index], group_index + 1))
		elif group_index == 0 and (action["pattern"] as RunePatternResult).pattern_type == RunePatternResult.PatternType.STRAIGHT:
			layer_events.append_array(_build_straight_bonus_events(action, base_event, 1))
		_resolve_effect_layer(layer_events)
		carriers.assign(layer_events)
	_finalize_batch()
	batch_count += 1
	states_changed.emit()
	_check_battle_result()
	return true


func _build_action(
	actor: BattleSquadState,
	living_snapshot: Array,
	action_type: CardData.ActionType,
	action_value_delta: float = 0.0
) -> Dictionary:
	if actor.get_action_source() == null:
		return {}
	var candidates: Array[BattleSquadState] = []
	for value: Variant in living_snapshot:
		var candidate := value as BattleSquadState
		if _is_base_candidate(actor, candidate, action_type):
			candidates.append(candidate)
	if action_type == CardData.ActionType.HEAL:
		var wounded: Array[BattleSquadState] = []
		for candidate: BattleSquadState in candidates:
			if candidate.current_health < float(candidate.get_max_health()):
				wounded.append(candidate)
		if not wounded.is_empty():
			var largest_missing_ratio := -1.0
			for candidate: BattleSquadState in wounded:
				largest_missing_ratio = maxf(largest_missing_ratio, _missing_health_ratio(candidate))
			candidates.clear()
			for candidate: BattleSquadState in wounded:
				if is_equal_approx(_missing_health_ratio(candidate), largest_missing_ratio):
					candidates.append(candidate)
	var target := choose_base_target(actor, candidates, action_type)
	if target == null:
		return {}
	var pattern := actor.get_rune_pattern_result()
	var action := {
		"actor": actor,
		"target": target,
		"action_type": action_type,
		"pattern": pattern,
		"group_id": _take_group_id(),
		"action_value_delta": action_value_delta,
	}
	var groups := BattleElementResolver.get_element_groups(pattern)
	action["element_groups"] = groups
	var pierces := not groups.is_empty() and int(groups[0]["element"]) == CardData.ElementType.WOOD and int(groups[0]["count"]) == 5 and action_type in [CardData.ActionType.MELEE, CardData.ActionType.RANGED, CardData.ActionType.MAGIC]
	action["base_event"] = _make_value_event(action, target, 1.0, 0, true, pierces)
	return action


func _missing_health_ratio(state: BattleSquadState) -> float:
	if state == null or state.get_max_health() <= 0:
		return 0.0
	return clampf(1.0 - state.current_health / float(state.get_max_health()), 0.0, 1.0)


func _is_actor_before(left: BattleSquadState, right: BattleSquadState) -> bool:
	if left.side != right.side:
		return left.side == BattleSquadState.Side.PLAYER
	var left_back := is_back_row(left.row_key)
	var right_back := is_back_row(right.row_key)
	if left_back != right_back:
		return not left_back
	return left.formation_index < right.formation_index


func _is_base_candidate(actor: BattleSquadState, candidate: BattleSquadState, action_type: CardData.ActionType) -> bool:
	if candidate == null or not candidate.alive:
		return false
	if action_type in [CardData.ActionType.HEAL, CardData.ActionType.DEFENSE]:
		return candidate.side == actor.side
	return candidate.side != actor.side and not candidate.moon_shadowed


func _make_value_event(action: Dictionary, target: BattleSquadState, element_multiplier: float, layer: int, base_action: bool = false, pierces: bool = false) -> BattleEffectEvent:
	var actor := action["actor"] as BattleSquadState
	var action_type := action["action_type"] as CardData.ActionType
	var pattern := action["pattern"] as RunePatternResult
	var event := BattleEffectEvent.new()
	event.group_id = int(action["group_id"])
	event.logical_layer = layer
	event.timestamp = elapsed_seconds
	event.source = actor
	event.target = target
	event.anchor = target
	event.action_type = action_type
	event.effect_kind = _kind_for_action(action_type)
	event.uses_attack_type_multiplier = event.effect_kind == BattleEffectEvent.EffectKind.DAMAGE
	event.is_base_action = base_action
	event.pierces_armor = pierces
	var additions: Array[Dictionary] = []
	var action_bonus := actor.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE)
	var reinforcement := actor.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)
	var immediate_action_delta := float(action.get("action_value_delta", 0.0))
	if not is_zero_approx(action_bonus):
		additions.append({"name": "效果数值修正", "value": action_bonus})
	if not is_zero_approx(reinforcement):
		additions.append({"name": "强化", "value": reinforcement})
	if not is_zero_approx(immediate_action_delta):
		additions.append({"name": "即时行动数值修正", "value": immediate_action_delta})
	event.formula = BattleFormulaData.create(
		_value_name_for_action(action_type),
		action_type,
		float(actor.squad_data.get_effective_action_base_value()),
		BattleRules.get_pattern_multiplier(pattern.pattern_type),
		element_multiplier,
		actor,
		target,
		_action_multipliers(actor),
		additions
	)
	event.exact_amount = event.formula.exact_result
	return event


func _build_element_events(action: Dictionary, carrier: BattleEffectEvent, group: Dictionary, layer: int) -> Array[BattleEffectEvent]:
	if not carrier.can_trigger_element_chain:
		return []
	if carrier.visual_kind == &"fire_burn":
		# 火作为主元素时，副元素跟随每一次真实 DOT/持续治疗/持续护甲，
		# 而不是在施加状态当下凭空结算一次未乘火倍率的效果。
		for status: Dictionary in active_continuous_effects:
			if status.get("marker") == carrier:
				status["secondary_group"] = group.duplicate(true)
				status["secondary_action"] = action.duplicate(true)
				break
		return []
	var element := int(group["element"]) as CardData.ElementType
	var count := int(group["count"])
	var config := BattleRules.get_element_config(element, count)
	if config.is_empty():
		return []
	match element:
		CardData.ElementType.FIRE:
			return _build_fire_events(action, carrier, count, config, layer)
		CardData.ElementType.WATER:
			return _build_water_events(action, carrier, count, config, layer)
		CardData.ElementType.DARK:
			return _build_dark_events(action, carrier, count, config, layer)
		CardData.ElementType.LIGHT:
			return _build_light_events(action, carrier, count, config, layer)
		CardData.ElementType.WOOD:
			return _build_wood_events(action, carrier, count, config, layer)
		_:
			return []


func _build_fire_events(action: Dictionary, carrier: BattleEffectEvent, count: int, config: Dictionary, layer: int) -> Array[BattleEffectEvent]:
	if carrier.target == null or carrier.target.current_health <= 0.0:
		return []
	var tick_multiplier := float(config["tick_multiplier"])
	var marker := _copy_carrier_event(action, carrier, carrier.target, carrier.formula.element_multiplier, layer)
	marker.effect_kind = BattleEffectEvent.EffectKind.PLACEHOLDER
	marker.element_type = CardData.ElementType.FIRE
	marker.element_count = count
	marker.visual_kind = &"fire_burn"
	marker.log_qualifier = "施加灼烧" if marker.action_type not in [CardData.ActionType.HEAL, CardData.ActionType.DEFENSE] else "施加持续效果"
	active_continuous_effects.append({
		"source": action["actor"], "target": carrier.target, "action_type": action["action_type"],
		"base_value": carrier.formula.base_value, "pattern_multiplier": carrier.formula.pattern_multiplier,
		"element_multiplier": carrier.formula.element_multiplier * tick_multiplier,
		"ticks_remaining": int(config["ticks"]), "interval": float(config["interval"]),
		"duration": float(config["ticks"]) * float(config["interval"]), "applied_at": elapsed_seconds,
		"next_time": elapsed_seconds + float(config["interval"]),
		"finisher_multiplier": carrier.formula.element_multiplier * float(config["finisher_multiplier"]),
		"element_count": count, "pierces_armor": carrier.pierces_armor, "marker": marker,
		"can_trigger_element_chain": bool(config.get("can_trigger_element_chain", true)),
	})
	marker.can_trigger_element_chain = bool(config.get("can_trigger_element_chain", true))
	return [marker]


func _build_straight_bonus_events(action: Dictionary, carrier: BattleEffectEvent, layer: int) -> Array[BattleEffectEvent]:
	# 顺子一次性选择五类追加效果；返回事件不会作为下一元素层载体。
	var config := BattleRules.STRAIGHT_BONUS_CONFIG
	var result: Array[BattleEffectEvent] = []
	result.append_array(_build_dark_events(action, carrier, 1, config["dark"] as Dictionary, layer))
	result.append_array(_build_water_events(action, carrier, 1, config["water"] as Dictionary, layer))
	result.append_array(_build_wood_events(action, carrier, 1, config["wood"] as Dictionary, layer))
	result.append_array(_build_light_events(action, carrier, 1, config["light"] as Dictionary, layer))
	result.append_array(_build_fire_events(action, carrier, 1, config["fire"] as Dictionary, layer))
	for event: BattleEffectEvent in result:
		event.can_trigger_element_chain = false
		if event.visual_kind == &"dark_repeat": event.log_qualifier = "顺子·连击"
		elif event.visual_kind == &"water_spread": event.log_qualifier = "顺子·扩散"
		elif event.visual_kind == &"wood_pierce": event.log_qualifier = "顺子·穿刺"
		elif event.visual_kind == &"light_reflect": event.log_qualifier = "顺子·折射"
		elif event.visual_kind == &"fire_burn": event.log_qualifier = "顺子·施加灼烧"
	return result


func _build_water_events(action: Dictionary, carrier: BattleEffectEvent, count: int, config: Dictionary, layer: int) -> Array[BattleEffectEvent]:
	var targets := _water_targets(carrier.target, config)
	var result: Array[BattleEffectEvent] = []
	for target: BattleSquadState in targets:
		var event := _copy_carrier_event(action, carrier, target, carrier.formula.element_multiplier * float(config["multiplier"]), layer)
		event.element_type = CardData.ElementType.WATER
		event.element_count = count
		event.visual_kind = &"water_spread"
		event.log_qualifier = "扩散"
		result.append(event)
	return result


func _build_dark_events(action: Dictionary, carrier: BattleEffectEvent, count: int, config: Dictionary, layer: int) -> Array[BattleEffectEvent]:
	if carrier.target == null or carrier.target.current_health <= 0.0:
		return []
	var result: Array[BattleEffectEvent] = []
	for index: int in int(config["count"]):
		var event := _copy_carrier_event(action, carrier, carrier.target, carrier.formula.element_multiplier * float(config["multiplier"]), layer)
		event.element_type = CardData.ElementType.DARK
		event.element_count = count
		event.sequence_index = index
		event.visual_kind = &"dark_repeat"
		event.log_qualifier = "暗追加"
		result.append(event)
	return result


func _build_light_events(action: Dictionary, carrier: BattleEffectEvent, count: int, config: Dictionary, layer: int) -> Array[BattleEffectEvent]:
	var candidates: Array[BattleSquadState] = []
	for state: BattleSquadState in get_all_states():
		if state.side == carrier.target.side and state != carrier.target and state.alive and state.current_health > 0.0:
			candidates.append(state)
	var result: Array[BattleEffectEvent] = []
	for _bounce: int in mini(int(config["count"]), candidates.size()):
		var index := _random.randi_range(0, candidates.size() - 1)
		var target := candidates.pop_at(index) as BattleSquadState
		var event := _copy_carrier_event(action, carrier, target, carrier.formula.element_multiplier * float(config["multiplier"]), layer)
		event.element_type = CardData.ElementType.LIGHT
		event.element_count = count
		event.visual_kind = &"light_reflect"
		event.log_qualifier = "折射"
		result.append(event)
	return result


func _build_wood_events(action: Dictionary, carrier: BattleEffectEvent, count: int, config: Dictionary, layer: int) -> Array[BattleEffectEvent]:
	var target := _wood_projection_target(carrier.target)
	if target == null:
		return []
	var result: Array[BattleEffectEvent] = []
	var multiplier := carrier.formula.element_multiplier * float(config["multiplier"])
	var event := _copy_carrier_event(action, carrier, target, multiplier, layer)
	event.element_type = CardData.ElementType.WOOD
	event.element_count = count
	event.pierces_armor = bool(config["pierces_armor"])
	event.visual_kind = &"wood_pierce"
	event.log_qualifier = "跨排穿刺" if event.pierces_armor else "跨排"
	result.append(event)
	if count >= 3 and event.effect_kind in [BattleEffectEvent.EffectKind.HEALING, BattleEffectEvent.EffectKind.ARMOR]:
		var converted := _copy_carrier_event(action, carrier, target, multiplier, layer)
		converted.element_type = CardData.ElementType.WOOD
		converted.element_count = count
		converted.effect_kind = BattleEffectEvent.EffectKind.ARMOR if event.effect_kind == BattleEffectEvent.EffectKind.HEALING else BattleEffectEvent.EffectKind.HEALING
		converted.visual_kind = &"wood_pierce"
		converted.log_qualifier = "木额外转换"
		converted.formula.display_name = "护甲" if converted.effect_kind == BattleEffectEvent.EffectKind.ARMOR else "治疗"
		result.append(converted)
	return result


func _copy_carrier_event(action: Dictionary, carrier: BattleEffectEvent, target: BattleSquadState, element_multiplier: float, layer: int) -> BattleEffectEvent:
	var event := _make_value_event(action, target, element_multiplier, layer)
	event.anchor = carrier.target
	return event


func _water_targets(anchor: BattleSquadState, config: Dictionary) -> Array[BattleSquadState]:
	if anchor == null:
		return []
	var left: Array[BattleSquadState] = []
	var right: Array[BattleSquadState] = []
	for state: BattleSquadState in get_all_states():
		if state == anchor or state.side != anchor.side or state.row_key != anchor.row_key or not state.alive or state.current_health <= 0.0:
			continue
		if state.logical_center < anchor.logical_center:
			left.append(state)
		else:
			right.append(state)
	left.sort_custom(func(a: BattleSquadState, b: BattleSquadState) -> bool: return a.logical_center > b.logical_center)
	right.sort_custom(func(a: BattleSquadState, b: BattleSquadState) -> bool: return a.logical_center < b.logical_center)
	if bool(config["random_one_side"]):
		var nearest: Array[BattleSquadState] = []
		if not left.is_empty(): nearest.append(left[0])
		if not right.is_empty(): nearest.append(right[0])
		var selected: Array[BattleSquadState] = []
		if not nearest.is_empty():
			selected.append(nearest[_random.randi_range(0, nearest.size() - 1)])
		return selected
	var result: Array[BattleSquadState] = []
	for index: int in mini(int(config["left"]), left.size()): result.append(left[index])
	for index: int in mini(int(config["right"]), right.size()): result.append(right[index])
	return result


func _wood_projection_target(anchor: BattleSquadState) -> BattleSquadState:
	if anchor == null:
		return null
	var other_row := _back_row_for_side(anchor.side) if not is_back_row(anchor.row_key) else _front_row_for_side(anchor.side)
	var best: BattleSquadState
	var best_distance := INF
	for state: BattleSquadState in get_all_states():
		if state.side != anchor.side or state.row_key != other_row or not state.alive or state.current_health <= 0.0:
			continue
		var distance := absf(state.logical_center - anchor.logical_center)
		if distance < best_distance:
			best = state
			best_distance = distance
	return best


func _resolve_effect_layer(events: Array[BattleEffectEvent]) -> void:
	var ordered: Array[BattleEffectEvent] = []
	for event: BattleEffectEvent in events:
		if event.effect_kind == BattleEffectEvent.EffectKind.DAMAGE: ordered.append(event)
	for event: BattleEffectEvent in events:
		if event.effect_kind in [BattleEffectEvent.EffectKind.HEALING, BattleEffectEvent.EffectKind.ARMOR]: ordered.append(event)
	for event: BattleEffectEvent in events:
		if event.effect_kind == BattleEffectEvent.EffectKind.PLACEHOLDER: ordered.append(event)
	var cancelled_dark_groups: Dictionary = {}
	for event: BattleEffectEvent in ordered:
		if event.log_qualifier == "暗追加" and event.sequence_index > 0 and cancelled_dark_groups.has(event.group_id):
			continue
		_apply_effect_event(event)
		if event.log_qualifier == "暗追加" and event.target.current_health <= 0.0:
			cancelled_dark_groups[event.group_id] = true


func _apply_effect_event(event: BattleEffectEvent) -> void:
	if event.target == null:
		return
	match event.effect_kind:
		BattleEffectEvent.EffectKind.DAMAGE:
			_apply_attack_type_multiplier(event)
			var incoming_multiplier := event.target.modifiers.get_multiplier(BattleModifier.Stat.INCOMING_DAMAGE)
			var incoming_addition := event.target.modifiers.get_additive(BattleModifier.Stat.INCOMING_DAMAGE)
			if event.formula != null and not is_equal_approx(incoming_multiplier, 1.0):
				event.formula.other_multipliers.append({"name": "承伤修正", "value": incoming_multiplier})
			if event.formula != null and not is_zero_approx(incoming_addition):
				event.formula.final_flat_bonus += incoming_addition
			if event.formula != null:
				event.formula.exact_result = maxf(event.formula.calculate_result(), 0.0)
				event.exact_amount = event.formula.exact_result
			var split := event.target.apply_damage_exact(event.exact_amount, event.source, event, event.pierces_armor)
			event.armor_amount = float(split["armor_damage"])
			event.health_amount = float(split["health_damage"])
			event.effective_amount = float(split["total"])
			if event.is_base_action and event.effective_amount > 0.0:
				effect_runtime.emit_trigger(
					BattleEffectDefinition.Trigger.EQUIPPED_UNIT_AFTER_BASIC_ACTION_DAMAGE,
					{
						"actor": event.target,
						"damage_source": event.source,
						"current_armor_after_damage": event.target.current_armor,
					}
				)
		BattleEffectEvent.EffectKind.HEALING:
			event.effective_amount = event.target.apply_healing_exact(event.exact_amount, event.source, event)
			if event.is_base_action:
				effect_runtime.emit_trigger(
					BattleEffectDefinition.Trigger.AFTER_BASIC_HEAL,
					{"actor": event.source, "healed_target": event.target}
				)
		BattleEffectEvent.EffectKind.ARMOR:
			var armor_multiplier := event.target.modifiers.get_multiplier(BattleModifier.Stat.ARMOR_GAIN)
			var armor_addition := event.target.modifiers.get_additive(BattleModifier.Stat.ARMOR_GAIN)
			var effect_adjustments := effect_runtime.resolve_armor_gain_modifiers(event.target)
			armor_multiplier *= float(effect_adjustments["multiplier"])
			armor_addition += float(effect_adjustments["addition"])
			if event.formula != null and not is_equal_approx(armor_multiplier, 1.0):
				event.formula.other_multipliers.append({"name": "获得护甲乘法修正", "value": armor_multiplier})
			if event.formula != null and not is_zero_approx(armor_addition):
				event.formula.final_flat_bonus += armor_addition
			if event.formula != null:
				event.formula.exact_result = maxf(event.formula.calculate_result(), 0.0)
				event.exact_amount = event.formula.exact_result
			event.effective_amount = event.target.apply_armor_exact(event.exact_amount, event.source, event)
			if event.effective_amount > 0.0:
				effect_runtime.emit_trigger(
					BattleEffectDefinition.Trigger.SOURCE_ARMOR_GAINED,
					{"actor": event.target, "amount": event.effective_amount}
				)
		BattleEffectEvent.EffectKind.PLACEHOLDER:
			event.effective_amount = 0.0
	_record_battle_statistics(event)
	effect_runtime.recheck_continuous_conditions()
	effect_runtime.process_due(elapsed_seconds)
	effect_resolved.emit(event)
	if event.is_base_action:
		action_resolved.emit(event.source, event.target, event.action_type, roundi(event.effective_amount))
		effect_runtime.notify_action_after(event.source)
		effect_runtime.process_due(elapsed_seconds)


func _apply_attack_type_multiplier(event: BattleEffectEvent) -> void:
	if not event.uses_attack_type_multiplier or event.formula == null:
		return
	event.target_had_armor_on_impact = event.target.current_armor > 0.0
	event.attack_type_multiplier = BattleRules.get_attack_type_multiplier(
		event.action_type,
		event.target_had_armor_on_impact
	)
	event.formula.other_multipliers.append({
		"name": "攻击类型（%s）" % ("有护甲" if event.target_had_armor_on_impact else "无护甲"),
		"value": event.attack_type_multiplier,
	})
	event.formula.exact_result = event.formula.calculate_result()
	event.exact_amount = event.formula.exact_result


func _record_battle_statistics(event: BattleEffectEvent) -> void:
	# 统计只记录实际生效值，因此不会把过量治疗、护甲溢出或占位效果算入战绩。
	var effective := maxf(event.effective_amount, 0.0)
	if effective <= 0.0:
		return
	match event.effect_kind:
		BattleEffectEvent.EffectKind.DAMAGE:
			# 伤害统计由 BattleSquadState.apply_damage_exact 的实际扣减入口统一记录，
			# 这里不再重复累计；治疗与护甲仍在各自控制器事件中归属来源。
			pass
		BattleEffectEvent.EffectKind.HEALING:
			if event.source != null:
				event.source.battle_healing_done += effective
		BattleEffectEvent.EffectKind.ARMOR:
			if event.source != null:
				event.source.battle_armor_granted += effective


func _collect_due_continuous_events() -> Array[BattleEffectEvent]:
	var events: Array[BattleEffectEvent] = []
	_continuous_followups.clear()
	var remaining: Array[Dictionary] = []
	for status: Dictionary in active_continuous_effects:
		var target := status["target"] as BattleSquadState
		if target == null or not target.alive or target.current_health <= 0.0:
			continue
		if elapsed_seconds + COOLDOWN_EPSILON < float(status["next_time"]):
			remaining.append(status)
			continue
		var group_id := _take_group_id()
		var event := _make_continuous_event(status, group_id, false)
		events.append(event)
		if status.has("secondary_group"):
			_continuous_followups[event] = {"group": status["secondary_group"], "action": status["secondary_action"]}
		status["ticks_remaining"] = int(status["ticks_remaining"]) - 1
		if int(status["ticks_remaining"]) <= 0:
			if float(status["finisher_multiplier"]) > 0.0:
				var finisher := _make_continuous_event(status, group_id, true)
				events.append(finisher)
				if status.has("secondary_group"):
					_continuous_followups[finisher] = {"group": status["secondary_group"], "action": status["secondary_action"]}
		else:
			status["next_time"] = float(status["next_time"]) + float(status["interval"])
			remaining.append(status)
	active_continuous_effects = remaining
	return events


func _build_due_continuous_followups() -> Array[BattleEffectEvent]:
	var events: Array[BattleEffectEvent] = []
	for carrier_value: Variant in _continuous_followups:
		var carrier := carrier_value as BattleEffectEvent
		var followup := _continuous_followups[carrier] as Dictionary
		var action := (followup["action"] as Dictionary).duplicate(true)
		action["group_id"] = carrier.group_id
		events.append_array(_build_element_events(action, carrier, followup["group"] as Dictionary, 1))
	return events


func _make_continuous_event(status: Dictionary, group_id: int, finisher: bool) -> BattleEffectEvent:
	var source := status["source"] as BattleSquadState
	var target := status["target"] as BattleSquadState
	var action_type := status["action_type"] as CardData.ActionType
	var multiplier := float(status["finisher_multiplier"] if finisher else status["element_multiplier"])
	var event := BattleEffectEvent.new()
	event.group_id = group_id
	event.timestamp = elapsed_seconds
	event.source = source
	event.target = target
	event.anchor = target
	event.action_type = action_type
	event.effect_kind = _kind_for_action(action_type)
	event.uses_attack_type_multiplier = event.effect_kind == BattleEffectEvent.EffectKind.DAMAGE
	event.element_type = CardData.ElementType.FIRE
	event.element_count = int(status["element_count"])
	event.is_continuous = true
	event.is_finisher = finisher
	event.can_trigger_element_chain = bool(status.get("can_trigger_element_chain", true))
	event.pierces_armor = bool(status["pierces_armor"])
	event.visual_kind = &"fire_finish" if finisher else &"fire_tick"
	event.log_qualifier = "灼烧终结" if finisher else "灼烧"
	event.formula = BattleFormulaData.create(_value_name_for_action(action_type), action_type, float(status["base_value"]), float(status["pattern_multiplier"]), multiplier, source, target)
	event.exact_amount = event.formula.exact_result
	return event


func _prepare_fatigue_events(living_snapshot: Array) -> Array[BattleEffectEvent]:
	var events: Array[BattleEffectEvent] = []
	var stack_due := elapsed_seconds + COOLDOWN_EPSILON >= _next_fatigue_stack_seconds
	var damage_due := elapsed_seconds + COOLDOWN_EPSILON >= _next_fatigue_damage_seconds
	if stack_due:
		for value: Variant in living_snapshot:
			var state := value as BattleSquadState
			var stacks := state.add_buff_stacks(BattleRules.FATIGUE_BUFF_ID)
			buff_stacks_changed.emit(state, BattleRules.FATIGUE_BUFF_ID, stacks)
		while elapsed_seconds + COOLDOWN_EPSILON >= _next_fatigue_stack_seconds:
			_next_fatigue_stack_seconds += BattleRules.FATIGUE_STACK_INTERVAL_SECONDS
	if damage_due:
		for value: Variant in living_snapshot:
			var state := value as BattleSquadState
			var damage := float(state.get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) * BattleRules.FATIGUE_DAMAGE_PER_STACK)
			var event := BattleEffectEvent.new()
			event.group_id = _take_group_id()
			event.timestamp = elapsed_seconds
			event.target = state
			event.anchor = state
			event.effect_kind = BattleEffectEvent.EffectKind.DAMAGE
			event.exact_amount = damage
			event.pierces_armor = true
			event.log_qualifier = "疲劳"
			event.formula = BattleFormulaData.create("伤害", CardData.ActionType.MELEE, damage, 1.0, 1.0, null, state)
			events.append(event)
		while elapsed_seconds + COOLDOWN_EPSILON >= _next_fatigue_damage_seconds:
			_next_fatigue_damage_seconds += BattleRules.FATIGUE_DAMAGE_INTERVAL_SECONDS
	return events


func _finalize_batch() -> void:
	var defeated: Array[BattleSquadState] = []
	for state: BattleSquadState in get_all_states():
		state.finalize_batch_survival()
		if state.alive and state.current_health <= 0.0:
			state.alive = false
			state.force_boundary_sync()
			defeated.append(state)
			if (
				state.pending_kill_event != null
				and state.pending_kill_source != null
				and state.pending_kill_source.alive
				and state.pending_kill_source.current_health > 0.0
			):
				kill_resolved.emit(state.pending_kill_source, state, state.pending_kill_event)
	recalculate_logical_layout()
	for state: BattleSquadState in defeated:
		_transfer_defeated_star(state)
		squad_defeated.emit(state)
		effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.LAST_WISH, {"actor": state})
		effect_runtime.notify_source_defeated(state)
		effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ADJACENT_ALLY_DESTROYED, {"actor": state})
		effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.OTHER_ALLY_DESTROYED, {"actor": state})
	effect_runtime.recheck_continuous_conditions()
	effect_runtime.process_due(elapsed_seconds)


func _action_multipliers(actor: BattleSquadState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var multiplier_bonus := actor.modifiers.get_additive(BattleModifier.Stat.ACTION_MULTIPLIER)
	if not is_zero_approx(multiplier_bonus):
		result.append({"name": "行动倍率修正", "value": maxf(0.0, 1.0 + multiplier_bonus)})
	return result


func _kind_for_action(action_type: CardData.ActionType) -> BattleEffectEvent.EffectKind:
	if action_type == CardData.ActionType.HEAL:
		return BattleEffectEvent.EffectKind.HEALING
	if action_type == CardData.ActionType.DEFENSE:
		return BattleEffectEvent.EffectKind.ARMOR
	return BattleEffectEvent.EffectKind.DAMAGE


func _value_name_for_action(action_type: CardData.ActionType) -> String:
	if action_type == CardData.ActionType.HEAL:
		return "治疗"
	if action_type == CardData.ActionType.DEFENSE:
		return "护甲"
	return "%s伤害" % ["近战", "远程", "法术"][action_type]


func _visual_kind_for_event(event: BattleEffectEvent) -> StringName:
	if event.visual_kind != &"":
		return event.visual_kind
	match event.action_type:
		CardData.ActionType.RANGED:
			return &"ranged_attack"
		CardData.ActionType.MAGIC:
			return &"magic_attack"
		CardData.ActionType.HEAL:
			return &"heal_action"
		CardData.ActionType.DEFENSE:
			return &"defense_action"
		_:
			return &"melee_attack"


func _front_row_for_side(side: int) -> StringName:
	return &"player_front" if side == BattleSquadState.Side.PLAYER else &"enemy_front"


func _back_row_for_side(side: int) -> StringName:
	return &"player_back" if side == BattleSquadState.Side.PLAYER else &"enemy_back"


func _take_group_id() -> int:
	var result := _next_group_id
	_next_group_id += 1
	return result


func _on_integer_settlement_committed(event: Dictionary) -> void:
	integer_settlement_resolved.emit(event)


func _on_health_lost_accumulated(event: Dictionary) -> void:
	var state := event.get("state") as BattleSquadState
	if state == null:
		return
	effect_runtime.emit_trigger(
		BattleEffectDefinition.Trigger.SOURCE_HEALTH_LOST_ACCUMULATED,
		{
			"actor": state,
			"amount": float(event.get("amount", 0.0)),
			"accumulated_health_loss": float(event.get("accumulated_health_loss", 0.0)),
			"damage_source": event.get("source"),
			"effect_event": event.get("effect_event"),
		}
	)


func _on_effect_trace_emitted(entry: BattleEffectTraceEntry) -> void:
	effect_trace_emitted.emit(entry)


func _check_battle_result() -> void:
	if current_result != Result.NONE:
		return
	var player_alive := not get_living_states(BattleSquadState.Side.PLAYER).is_empty()
	var enemy_alive := not get_living_states(BattleSquadState.Side.ENEMY).is_empty()
	if player_alive and enemy_alive:
		return
	if not player_alive and not enemy_alive:
		current_result = Result.DRAW
	elif player_alive:
		current_result = Result.PLAYER_VICTORY
	else:
		current_result = Result.PLAYER_DEFEAT
	if current_result == Result.PLAYER_VICTORY:
		effect_runtime.emit_trigger(
			BattleEffectDefinition.Trigger.BATTLE_WON,
			{"winner_side": BattleSquadState.Side.PLAYER}
		)
		effect_runtime.process_due(elapsed_seconds)
	effect_runtime.notify_battle_end()
	effect_runtime.process_due(elapsed_seconds)
	stop_battle()
	for state: BattleSquadState in get_all_states():
		state.force_boundary_sync()
	battle_finished.emit(current_result)
