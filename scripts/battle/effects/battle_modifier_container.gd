class_name BattleModifierContainer
extends RefCounted

## 小队的通用修正容器。每一项都保留来源，撤销时不会误删其他效果。

var modifiers: Array[BattleModifier] = []
var _next_modifier_id: int = 1
var _next_created_order: int = 1


func add_modifier(modifier: BattleModifier) -> BattleModifier:
	modifier.modifier_id = _next_modifier_id
	_next_modifier_id += 1
	modifier.created_order = _next_created_order
	_next_created_order += 1
	modifiers.append(modifier)
	return modifier


func remove_source_instance(source_instance_id: int) -> int:
	var removed := 0
	for index: int in range(modifiers.size() - 1, -1, -1):
		if modifiers[index].source_instance_id == source_instance_id:
			modifiers.remove_at(index)
			removed += 1
	return removed


func set_source_instance_active(source_instance_id: int, active: bool) -> void:
	for modifier: BattleModifier in modifiers:
		if modifier.source_instance_id == source_instance_id:
			modifier.active = active


func update_source_instance_value(source_instance_id: int, value: float) -> void:
	for modifier: BattleModifier in modifiers:
		if modifier.source_instance_id == source_instance_id:
			modifier.value = value


func get_additive(stat: BattleModifier.Stat) -> float:
	var total := 0.0
	for modifier: BattleModifier in modifiers:
		if modifier.active and modifier.stat == stat and modifier.mode == BattleModifier.Mode.ADD:
			total += modifier.value
	return total


func get_multiplier(stat: BattleModifier.Stat) -> float:
	var result := 1.0
	for modifier: BattleModifier in modifiers:
		if modifier.active and modifier.stat == stat and modifier.mode == BattleModifier.Mode.MULTIPLY:
			result *= modifier.value
	return result


func get_minimum(stat: BattleModifier.Stat, fallback: float = -INF) -> float:
	var result := fallback
	for modifier: BattleModifier in modifiers:
		if modifier.active and modifier.stat == stat and modifier.mode == BattleModifier.Mode.SET_MINIMUM:
			result = maxf(result, modifier.value)
	return result


func clear() -> void:
	modifiers.clear()
	_next_modifier_id = 1
	_next_created_order = 1
