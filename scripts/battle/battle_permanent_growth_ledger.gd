class_name BattlePermanentGrowthLedger
extends RefCounted

## D2-4 的战后写回边界。
## 这里只记录本场确认产生的永久成长及其真实单卡归属；D2-5 建立收藏实例后
## 再负责消费这些记录。账本绝不直接修改共享 CardData 资源。

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
	logical_time_us: int
) -> bool:
	if (
		owner == null
		or owner.card_data == null
		or stat not in [STAT_BASE_VALUE, STAT_BASE_ARMOR]
		or is_zero_approx(amount)
	):
		return false
	_entries.append({
		"card_data": owner.card_data,
		"card_id": owner.card_data.id,
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
