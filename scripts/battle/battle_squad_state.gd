class_name BattleSquadState
extends RefCounted

## 单个小队的一场战斗临时状态。
## 这里引用准备阶段的 SquadData 作为只读配置来源，但生命、护甲、冷却与
## 存活状态全部独立保存，绝不写回卡牌资源或准备阵容。

const BattleRules = preload("res://scripts/battle/battle_rules.gd")

enum Side { PLAYER, ENEMY }

var squad_data: SquadData
var side: int = Side.PLAYER
var row_key: StringName = &""
var formation_index: int = 0
var current_health: int = 0
var current_armor: int = 0
var remaining_cooldown: float = 0.0
var alive: bool = true
var buff_stacks: Dictionary = {} # 本场战斗的临时 Buff 层数，键使用 BattleRules 中的稳定标识


func initialize(
	value: SquadData,
	battle_side: int,
	row: StringName,
	index: int
) -> void:
	squad_data = value
	side = battle_side
	row_key = row
	formation_index = index
	var vitals_source := value.get_vitals_source() if value != null else null
	var action_source := value.get_action_source() if value != null else null
	current_health = (
		clampi(vitals_source.max_health, 0, CardData.MAXIMUM_HEALTH)
		if vitals_source != null else 0
	)
	current_armor = (
		clampi(vitals_source.armor, 0, CardData.MAXIMUM_ARMOR)
		if vitals_source != null else 0
	)
	remaining_cooldown = (
		BattleRules.get_effective_cooldown(action_source.cooldown_seconds)
		if action_source != null
		else BattleRules.MINIMUM_COOLDOWN_SECONDS
	)
	alive = current_health > 0
	buff_stacks.clear()


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


func get_action_amount() -> int:
	var source := get_action_source()
	if source == null or squad_data == null:
		return 0
	return BattleRules.calculate_action_amount(
		source.base_value,
		squad_data.get_rune_pattern_result().pattern_type
	)


func apply_damage(amount: int) -> int:
	var health_before := current_health
	var armor_before := current_armor
	var remaining_damage := maxi(amount, 0)
	var absorbed := mini(current_armor, remaining_damage)
	current_armor -= absorbed
	remaining_damage -= absorbed
	current_health -= remaining_damage
	var health_damage := mini(remaining_damage, maxi(health_before, 0))
	return mini(absorbed, maxi(armor_before, 0)) + health_damage


func apply_direct_health_damage(amount: int) -> int:
	# 疲劳等明确标注为直伤的效果绕过护甲，但仍在统一批次末尾判定死亡。
	var damage := maxi(amount, 0)
	var effective_damage := mini(damage, maxi(current_health, 0))
	current_health -= damage
	return effective_damage


func apply_healing(amount: int) -> int:
	var health_before := current_health
	current_health = mini(current_health + maxi(amount, 0), get_max_health())
	return maxi(current_health - health_before, 0)


func apply_armor(amount: int) -> int:
	var armor_before := current_armor
	current_armor = clampi(
		current_armor + maxi(amount, 0),
		0,
		CardData.MAXIMUM_ARMOR
	)
	return maxi(current_armor - armor_before, 0)


func add_buff_stacks(buff_id: StringName, amount: int = 1) -> int:
	var next_stacks := maxi(get_buff_stacks(buff_id) + amount, 0)
	if next_stacks == 0:
		buff_stacks.erase(buff_id)
	else:
		buff_stacks[buff_id] = next_stacks
	return next_stacks


func get_buff_stacks(buff_id: StringName) -> int:
	return int(buff_stacks.get(buff_id, 0))
