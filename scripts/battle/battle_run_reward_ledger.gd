class_name BattleRunRewardLedger
extends RefCounted

## D2-4 的本局奖励待结算边界。
## 突击只记录已经确认产生的金币或随机卡请求，不会同时修改玩家余额或收藏。
## D2-5 在正常战后结合收藏、唯一性与本局卡池消费每条记录一次；中途重试
## 不会提前污染真实本局数据，也不会因结算界面读取这些记录而重复发放。

const KIND_GOLD: StringName = &"gold"
const KIND_RANDOM_CARD_REQUEST: StringName = &"random_card_request"
const STATUS_PENDING_RUN_RESOLUTION: StringName = &"pending_run_resolution"

var _entries: Array[Dictionary] = []


func clear() -> void:
	_entries.clear()


func record(
	owner: BattleEffectOwnerRef,
	kind: StringName,
	amount: int,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int,
	parameters: Dictionary = {},
	battle_instance_id: StringName = &""
) -> bool:
	if (
		owner == null
		or owner.state == null
		or owner.owner_kind != BattleEffectDefinition.OwnerKind.OWNING_PLAYER
		or kind not in [KIND_GOLD, KIND_RANDOM_CARD_REQUEST]
		or amount <= 0
	):
		return false
	var entry_index := _entries.size()
	_entries.append({
		"entry_id": StringName("%s:reward:%d" % [battle_instance_id, entry_index]),
		"battle_instance_id": battle_instance_id,
		"kind": kind,
		"amount": amount,
		"side": owner.state.side,
		"owner_kind": owner.owner_kind,
		"owner_runtime_id": owner.runtime_id,
		"effect_id": effect_id,
		"source_runtime_id": source_runtime_id,
		"logical_time_us": logical_time_us,
		"status": STATUS_PENDING_RUN_RESOLUTION,
		"parameters": parameters.duplicate(true),
	})
	return true


func get_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		result.append(entry.duplicate(true))
	return result


func get_total(kind: StringName, side: int) -> int:
	var result := 0
	for entry: Dictionary in _entries:
		if entry.get("kind") == kind and int(entry.get("side", -1)) == side:
			result += int(entry.get("amount", 0))
	return result
