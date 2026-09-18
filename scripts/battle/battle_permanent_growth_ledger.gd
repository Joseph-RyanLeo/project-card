class_name BattlePermanentGrowthLedger
extends RefCounted

## 战后写回边界。
## 这里只记录本场确认产生的永久成长及其真实 OwnedCard 归属；D2-5 的统一
## 战后事务负责消费这些记录。账本绝不直接修改共享 CardData 资源。

const STAT_BASE_VALUE: StringName = &"base_value"
const STAT_BASE_ARMOR: StringName = &"base_armor"

var _entries: Array[Dictionary] = []


func clear() -> void:
	_entries.clear()


func record(
	owner: BattleEffectOwnerRef,
	stat: StringName,
	amount: float,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int,
	battle_instance_id: StringName = &""
) -> bool:
	if (
		owner == null
		or owner.card_data == null
		or stat not in [STAT_BASE_VALUE, STAT_BASE_ARMOR]
		or is_zero_approx(amount)
	):
		return false
	var entry_index := _entries.size()
	_entries.append({
		"entry_id": StringName("%s:growth:%d" % [battle_instance_id, entry_index]),
		"battle_instance_id": battle_instance_id,
		"card_data": owner.card_data,
		"card_id": owner.card_data.id,
		"owned_card": owner.owned_card,
		"owned_card_instance_id": owner.owned_card_instance_id,
		"side": owner.state.side if owner.state != null else -1,
		"owner_runtime_id": owner.runtime_id,
		"owner_kind": owner.owner_kind,
		"card_index": owner.card_index,
		"stat": stat,
		"amount": amount,
		"effect_id": effect_id,
		"source_runtime_id": source_runtime_id,
		"logical_time_us": logical_time_us,
	})
	return true


func get_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		result.append(entry.duplicate())
	return result


func get_amount_for_card(card_data: CardData, stat: StringName) -> float:
	var result := 0.0
	for entry: Dictionary in _entries:
		if entry.get("card_data") == card_data and entry.get("stat") == stat:
			result += float(entry.get("amount", 0.0))
	return result


func get_amount_for_owned_card(instance_id: StringName, stat: StringName) -> float:
	var result := 0.0
	for entry: Dictionary in _entries:
		if entry.get("owned_card_instance_id") == instance_id and entry.get("stat") == stat:
			result += float(entry.get("amount", 0.0))
	return result
