class_name BattleSquadState
extends RefCounted

## 单个小队的一场战斗临时状态。
## current_health/current_armor 保存精确值；displayed_* 只保存卡面整数。

const BattleRules = preload("res://scripts/battle/battle_rules.gd")

signal integer_settlement_committed(event: Dictionary)

enum Side { PLAYER, ENEMY }

const CHANNEL_HEALTH_DAMAGE: StringName = &"health_damage"
const CHANNEL_ARMOR_DAMAGE: StringName = &"armor_damage"
const CHANNEL_HEALING: StringName = &"healing"
const CHANNEL_ARMOR_GAIN: StringName = &"armor_gain"

var squad_data: SquadData
var side: int = Side.PLAYER
var row_key: StringName = &""
var formation_index: int = 0
var current_health = 0:
	set(value):
		current_health = value
		if not _precise_write:
			displayed_health = clampi(roundi(value), 0, get_max_health())
var current_armor = 0:
	set(value):
		current_armor = value
		if not _precise_write:
			displayed_armor = clampi(roundi(value), 0, CardData.MAXIMUM_ARMOR)
var displayed_health: int = 0
var displayed_armor: int = 0
var remaining_cooldown: float = 0.0
var alive: bool = true
var buff_stacks: Dictionary = {} # 本场战斗的临时 Buff 层数，键使用稳定标识
var fractional_accumulators: Dictionary = {
	CHANNEL_HEALTH_DAMAGE: 0.0,
	CHANNEL_ARMOR_DAMAGE: 0.0,
	CHANNEL_HEALING: 0.0,
	CHANNEL_ARMOR_GAIN: 0.0,
}
var pending_kill_source: BattleSquadState
var pending_kill_event: BattleEffectEvent
var logical_left: float = 0.0
var logical_right: float = 0.0
var logical_center: float = 0.0
var battle_damage_dealt: float = 0.0
var battle_damage_taken: float = 0.0
var battle_healing_done: float = 0.0
var battle_armor_granted: float = 0.0

var _precise_write: bool = false


func initialize(value: SquadData, battle_side: int, row: StringName, index: int) -> void:
	squad_data = value
	side = battle_side
	row_key = row
	formation_index = index
	var vitals_source := value.get_vitals_source() if value != null else null
	var action_source := value.get_action_source() if value != null else null
	_set_exact_health(clampi(vitals_source.max_health, 0, CardData.MAXIMUM_HEALTH) if vitals_source != null else 0)
	_set_exact_armor(clampi(vitals_source.armor, 0, CardData.MAXIMUM_ARMOR) if vitals_source != null else 0)
	displayed_health = clampi(roundi(current_health), 0, get_max_health())
	displayed_armor = clampi(roundi(current_armor), 0, CardData.MAXIMUM_ARMOR)
	remaining_cooldown = BattleRules.get_effective_cooldown(action_source.cooldown_seconds) if action_source != null else BattleRules.MINIMUM_COOLDOWN_SECONDS
	alive = current_health > 0.0
	buff_stacks.clear()
	clear_precise_runtime()
	clear_battle_statistics()


func clear_precise_runtime() -> void:
	for channel: StringName in fractional_accumulators.keys():
		fractional_accumulators[channel] = 0.0
	pending_kill_source = null
	pending_kill_event = null


func clear_battle_statistics() -> void:
	battle_damage_dealt = 0.0
	battle_damage_taken = 0.0
	battle_healing_done = 0.0
	battle_armor_granted = 0.0


func get_battle_statistics() -> Dictionary:
	return {
		"damage_dealt": battle_damage_dealt,
		"damage_taken": battle_damage_taken,
		"healing_done": battle_healing_done,
		"armor_granted": battle_armor_granted,
	}


func get_action_source() -> CardData:
	return squad_data.get_action_source() if squad_data != null else null


func get_vitals_source() -> CardData:
	return squad_data.get_vitals_source() if squad_data != null else null


func get_effect_source() -> CardData:
	return squad_data.get_effect_source() if squad_data != null else null


func get_max_health() -> int:
	var source := get_vitals_source()
	return clampi(source.max_health, 0, CardData.MAXIMUM_HEALTH) if source != null else 0


func get_target_weight() -> int:
	var source := get_action_source()
	return maxi(source.get_base_target_priority(), 1) if source != null else 1


func get_exact_action_amount() -> float:
	var source := get_action_source()
	if source == null or squad_data == null:
		return 0.0
	return BattleRules.calculate_exact_action_amount(source.base_value, squad_data.get_rune_pattern_result().pattern_type)


func get_action_amount() -> int:
	return roundi(get_exact_action_amount())


func apply_damage_exact(amount: float, source_state: BattleSquadState = null, event: BattleEffectEvent = null, pierces_armor: bool = false) -> Dictionary:
	var damage := maxf(amount, 0.0)
	var armor_damage := 0.0
	if not pierces_armor:
		armor_damage = minf(current_armor, damage)
		_set_exact_armor(current_armor - armor_damage)
		damage -= armor_damage
	var health_before: float = float(current_health)
	var health_damage := damage
	_set_exact_health(current_health - health_damage)
	if armor_damage > 0.0:
		_accumulate(CHANNEL_ARMOR_DAMAGE, armor_damage, source_state, event)
	if health_damage > 0.0:
		_accumulate(CHANNEL_HEALTH_DAMAGE, health_damage, source_state, event)
	if health_before > 0.0 and current_health <= 0.0 and pending_kill_event == null:
		pending_kill_source = source_state
		pending_kill_event = event
	if current_armor <= 0.0:
		displayed_armor = 0
	if current_health <= 0.0:
		displayed_health = 0
	return {"armor_damage": armor_damage, "health_damage": health_damage, "total": armor_damage + health_damage}


func apply_direct_health_damage_exact(amount: float, source_state: BattleSquadState = null, event: BattleEffectEvent = null) -> float:
	return float(apply_damage_exact(amount, source_state, event, true)["health_damage"])


func apply_healing_exact(amount: float, source_state: BattleSquadState = null, event: BattleEffectEvent = null) -> float:
	var before: float = float(current_health)
	var effective := minf(maxf(amount, 0.0), maxf(float(get_max_health()) - current_health, 0.0))
	_set_exact_health(current_health + effective)
	if effective > 0.0:
		_accumulate(CHANNEL_HEALING, effective, source_state, event)
	if before <= 0.0 and current_health > 0.0:
		displayed_health = clampi(floori(current_health + 0.000001), 0, get_max_health())
		pending_kill_source = null
		pending_kill_event = null
	if current_health >= float(get_max_health()):
		displayed_health = get_max_health()
	return effective


func apply_armor_exact(amount: float, source_state: BattleSquadState = null, event: BattleEffectEvent = null) -> float:
	var effective := minf(maxf(amount, 0.0), maxf(float(CardData.MAXIMUM_ARMOR) - current_armor, 0.0))
	_set_exact_armor(current_armor + effective)
	if effective > 0.0:
		_accumulate(CHANNEL_ARMOR_GAIN, effective, source_state, event)
	if current_armor >= float(CardData.MAXIMUM_ARMOR):
		displayed_armor = CardData.MAXIMUM_ARMOR
	return effective


func apply_damage(amount: int) -> int:
	return roundi(float(apply_damage_exact(float(maxi(amount, 0)))["total"]))


func apply_direct_health_damage(amount: int) -> int:
	return roundi(apply_direct_health_damage_exact(float(maxi(amount, 0))))


func apply_healing(amount: int) -> int:
	return roundi(apply_healing_exact(float(maxi(amount, 0))))


func apply_armor(amount: int) -> int:
	return roundi(apply_armor_exact(float(maxi(amount, 0))))


func finalize_batch_survival() -> void:
	if current_health > 0.0:
		pending_kill_source = null
		pending_kill_event = null
	else:
		displayed_health = 0


func force_boundary_sync() -> void:
	if current_health <= 0.0:
		displayed_health = 0
	elif current_health >= float(get_max_health()):
		displayed_health = get_max_health()
	if current_armor <= 0.0:
		displayed_armor = 0
	elif current_armor >= float(CardData.MAXIMUM_ARMOR):
		displayed_armor = CardData.MAXIMUM_ARMOR


func add_buff_stacks(buff_id: StringName, amount: int = 1) -> int:
	var next_stacks := maxi(get_buff_stacks(buff_id) + amount, 0)
	if next_stacks == 0:
		buff_stacks.erase(buff_id)
	else:
		buff_stacks[buff_id] = next_stacks
	return next_stacks


func get_buff_stacks(buff_id: StringName) -> int:
	return int(buff_stacks.get(buff_id, 0))


func _accumulate(channel: StringName, amount: float, source_state: BattleSquadState, event: BattleEffectEvent) -> void:
	var next := float(fractional_accumulators.get(channel, 0.0)) + amount
	var committed := floori(next + 0.0000001)
	fractional_accumulators[channel] = next - float(committed)
	if event != null and event.formula != null:
		event.formula.fractional_remainder = float(fractional_accumulators[channel])
	if committed <= 0:
		return
	match channel:
		CHANNEL_HEALTH_DAMAGE:
			displayed_health = maxi(displayed_health - committed, 0)
		CHANNEL_ARMOR_DAMAGE:
			displayed_armor = maxi(displayed_armor - committed, 0)
		CHANNEL_HEALING:
			displayed_health = mini(displayed_health + committed, get_max_health())
		CHANNEL_ARMOR_GAIN:
			displayed_armor = mini(displayed_armor + committed, CardData.MAXIMUM_ARMOR)
	integer_settlement_committed.emit({"state": self, "channel": channel, "amount": committed, "source": source_state, "effect_event": event, "remainder": float(fractional_accumulators[channel])})


func _set_exact_health(value) -> void:
	_precise_write = true
	current_health = value
	_precise_write = false


func _set_exact_armor(value) -> void:
	_precise_write = true
	current_armor = value
	_precise_write = false
