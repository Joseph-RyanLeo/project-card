class_name BattleController
extends Node

## 敌我双方共用的自动战斗时间轴。
## 每个冷却时间点只建立一个行动批次，避免场景节点顺序产生隐性先手。

const BattleSquadState = preload("res://scripts/battle/battle_squad_state.gd")

signal states_changed
signal action_resolved(
	actor: BattleSquadState,
	target: BattleSquadState,
	action_type: CardData.ActionType,
	amount: int
)
signal squad_defeated(state: BattleSquadState)
signal buff_stacks_changed(
	state: BattleSquadState,
	buff_id: StringName,
	stacks: int
)
signal direct_damage_resolved(
	state: BattleSquadState,
	source_id: StringName,
	amount: int
)
signal battle_finished(result: Result)

enum Result {
	NONE,
	PLAYER_VICTORY,
	PLAYER_DEFEAT,
	DRAW,
}

const COOLDOWN_EPSILON: float = 0.0001 # 同一时间点冷却完成的浮点判断容差（秒）

var player_states: Array[BattleSquadState] = []
var enemy_states: Array[BattleSquadState] = []
var current_result: Result = Result.NONE
var elapsed_seconds: float = 0.0
var batch_count: int = 0
var battle_speed_multiplier: float = 1.0

var _random := RandomNumberGenerator.new()
var _running: bool = false
var _next_fatigue_stack_seconds: float = BattleRules.FATIGUE_START_SECONDS
var _next_fatigue_damage_seconds: float = BattleRules.FATIGUE_START_SECONDS


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	advance_time(delta * battle_speed_multiplier)


func start_battle(
	player_formation: Array[Dictionary],
	enemy_formation: Array[Dictionary],
	random_seed: int = -1,
	auto_run: bool = true
) -> void:
	stop_battle()
	player_states = _create_states(player_formation, BattleSquadState.Side.PLAYER)
	enemy_states = _create_states(enemy_formation, BattleSquadState.Side.ENEMY)
	current_result = Result.NONE
	elapsed_seconds = 0.0
	batch_count = 0
	_next_fatigue_stack_seconds = BattleRules.FATIGUE_START_SECONDS
	_next_fatigue_damage_seconds = BattleRules.FATIGUE_START_SECONDS
	if random_seed >= 0:
		_random.seed = random_seed
	else:
		_random.randomize()
	_running = true
	set_process(auto_run)
	states_changed.emit()
	_check_battle_result()


func stop_battle() -> void:
	_running = false
	set_process(false)


func clear_battle() -> void:
	stop_battle()
	player_states.clear()
	enemy_states.clear()
	current_result = Result.NONE
	elapsed_seconds = 0.0
	batch_count = 0
	_next_fatigue_stack_seconds = BattleRules.FATIGUE_START_SECONDS
	_next_fatigue_damage_seconds = BattleRules.FATIGUE_START_SECONDS
	_random = RandomNumberGenerator.new()


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


func choose_weighted_target(
	candidates: Array[BattleSquadState],
	forced_roll: int = -1
) -> BattleSquadState:
	var valid: Array[BattleSquadState] = []
	var total_weight := 0
	for candidate: BattleSquadState in candidates:
		if candidate != null and candidate.alive:
			valid.append(candidate)
			total_weight += candidate.get_target_weight()
	if valid.is_empty() or total_weight <= 0:
		return null
	var roll := (
		clampi(forced_roll, 0, total_weight - 1)
		if forced_roll >= 0
		else _random.randi_range(0, total_weight - 1)
	)
	var boundary := 0
	for candidate: BattleSquadState in valid:
		boundary += candidate.get_target_weight()
		if roll < boundary:
			return candidate
	return valid[-1]


func _create_states(
	formation: Array[Dictionary],
	side: int
) -> Array[BattleSquadState]:
	var states: Array[BattleSquadState] = []
	for entry: Dictionary in formation:
		var squad := entry.get("squad_data") as SquadData
		if squad == null or not squad.is_valid():
			continue
		var state := BattleSquadState.new()
		state.initialize(
			squad,
			side,
			StringName(entry.get("row_key", &"")),
			int(entry.get("formation_index", states.size()))
		)
		states.append(state)
	return states


func _get_next_cooldown() -> float:
	var next_time := INF
	for state: BattleSquadState in get_all_states():
		if state.alive:
			next_time = minf(next_time, maxf(state.remaining_cooldown, 0.0))
	return next_time


func _get_next_event_delay() -> float:
	var next_time := _get_next_cooldown()
	next_time = minf(
		next_time,
		maxf(_next_fatigue_stack_seconds - elapsed_seconds, 0.0)
	)
	next_time = minf(
		next_time,
		maxf(_next_fatigue_damage_seconds - elapsed_seconds, 0.0)
	)
	return next_time


func _decrease_living_cooldowns(amount: float) -> void:
	for state: BattleSquadState in get_all_states():
		if state.alive:
			state.remaining_cooldown = maxf(state.remaining_cooldown - amount, 0.0)


func _resolve_ready_batch() -> void:
	# 快照必须在任何数值变化前建立；本批次所有行动者与目标均据此确定。
	var player_snapshot := get_living_states(BattleSquadState.Side.PLAYER)
	var enemy_snapshot := get_living_states(BattleSquadState.Side.ENEMY)
	var living_snapshot: Array[BattleSquadState] = []
	living_snapshot.append_array(player_snapshot)
	living_snapshot.append_array(enemy_snapshot)
	var fatigue_stack_due := (
		elapsed_seconds + COOLDOWN_EPSILON >= _next_fatigue_stack_seconds
	)
	var fatigue_damage_due := (
		elapsed_seconds + COOLDOWN_EPSILON >= _next_fatigue_damage_seconds
	)
	var actors: Array[BattleSquadState] = []
	for state: BattleSquadState in get_all_states():
		if state.alive and state.remaining_cooldown <= COOLDOWN_EPSILON:
			actors.append(state)
	var actions: Array[Dictionary] = []
	for actor: BattleSquadState in actors:
		var action_source := actor.get_action_source()
		if action_source == null:
			continue
		var friendly := player_snapshot if actor.side == BattleSquadState.Side.PLAYER else enemy_snapshot
		var hostile := enemy_snapshot if actor.side == BattleSquadState.Side.PLAYER else player_snapshot
		var candidates: Array[BattleSquadState] = []
		if action_source.action_type == CardData.ActionType.HEAL:
			# 优先只在受伤友军中加权；全员满血时退回完整友军池，
			# 让本次治疗仍可成为后续元素与触发效果的载体。
			for candidate: BattleSquadState in friendly:
				if candidate.current_health < candidate.get_max_health():
					candidates.append(candidate)
			if candidates.is_empty():
				candidates.assign(friendly)
		elif action_source.action_type == CardData.ActionType.DEFENSE:
			candidates.assign(friendly)
		else:
			candidates.assign(hostile)
		var target := choose_weighted_target(candidates)
		if target != null:
			actions.append({
				"actor": actor,
				"target": target,
				"action_type": action_source.action_type,
				"amount": actor.get_action_amount(),
			})
		actor.remaining_cooldown = BattleRules.get_effective_cooldown(
			action_source.cooldown_seconds
		)

	# 第一段只结算三种伤害；被打到 0 以下的小队仍可接收本批次治疗。
	for action: Dictionary in actions:
		var action_type := action["action_type"] as CardData.ActionType
		if action_type in [CardData.ActionType.MELEE, CardData.ActionType.RANGED, CardData.ActionType.MAGIC]:
			var effective_damage := (
				(action["target"] as BattleSquadState)
				.apply_damage(int(action["amount"]))
			)
			action_resolved.emit(
				action["actor"],
				action["target"],
				action_type,
				effective_damage
			)

	# 疲劳与同秒行动属于同一批次：先叠层，再按新层数直扣生命。
	# 它不经过护甲，也不会提前剥夺本批次开始时已锁定的行动资格。
	if fatigue_stack_due:
		for state: BattleSquadState in living_snapshot:
			var stacks := state.add_buff_stacks(BattleRules.FATIGUE_BUFF_ID)
			buff_stacks_changed.emit(state, BattleRules.FATIGUE_BUFF_ID, stacks)
		while elapsed_seconds + COOLDOWN_EPSILON >= _next_fatigue_stack_seconds:
			_next_fatigue_stack_seconds += BattleRules.FATIGUE_STACK_INTERVAL_SECONDS
	if fatigue_damage_due:
		for state: BattleSquadState in living_snapshot:
			var damage := (
				state.get_buff_stacks(BattleRules.FATIGUE_BUFF_ID)
				* BattleRules.FATIGUE_DAMAGE_PER_STACK
			)
			var effective_damage := state.apply_direct_health_damage(damage)
			direct_damage_resolved.emit(
				state,
				BattleRules.FATIGUE_BUFF_ID,
				effective_damage
			)
		while elapsed_seconds + COOLDOWN_EPSILON >= _next_fatigue_damage_seconds:
			_next_fatigue_damage_seconds += BattleRules.FATIGUE_DAMAGE_INTERVAL_SECONDS

	# 第二段结算治疗和护甲；二者都不能让节点顺序影响本批次伤害。
	for action: Dictionary in actions:
		var action_type := action["action_type"] as CardData.ActionType
		var target := action["target"] as BattleSquadState
		if action_type == CardData.ActionType.HEAL:
			var effective_healing := target.apply_healing(int(action["amount"]))
			action_resolved.emit(action["actor"], target, action_type, effective_healing)
		elif action_type == CardData.ActionType.DEFENSE:
			var effective_armor := target.apply_armor(int(action["amount"]))
			action_resolved.emit(action["actor"], target, action_type, effective_armor)

	var defeated: Array[BattleSquadState] = []
	for state: BattleSquadState in get_all_states():
		if state.alive and state.current_health <= 0:
			state.alive = false
			defeated.append(state)
	batch_count += 1
	states_changed.emit()
	for state: BattleSquadState in defeated:
		squad_defeated.emit(state)
	_check_battle_result()


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
	stop_battle()
	battle_finished.emit(current_result)
