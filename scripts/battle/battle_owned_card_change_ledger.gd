class_name BattleOwnedCardChangeLedger
extends RefCounted

## 战斗中产生、但只能在正常战后写回 OwnedCard 的槽位与进度变化。
## 本账本不决定伤势类型、纹章目标或进化配方；这些玩法系统以后只需把已经
## 确认的结果记录在这里，D2-5 的统一事务负责一次性提交或整体回滚。

const KIND_SET_WOUND_SLOT: StringName = &"set_wound_slot"
const KIND_SET_EMBLEM_SLOT: StringName = &"set_emblem_slot"
const KIND_ADD_EMBLEM_PROGRESS: StringName = &"add_emblem_progress"
const KIND_CONSUME_EQUIPMENT: StringName = &"consume_equipment"

var _entries: Array[Dictionary] = []


func clear() -> void:
	_entries.clear()


func record_slot_change(
	owner: BattleEffectOwnerRef,
	kind: StringName,
	slot_index: int,
	slot_state: Dictionary,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int,
	battle_instance_id: StringName = &""
) -> bool:
	if (
		owner == null
		or owner.owned_card == null
		or kind not in [KIND_SET_WOUND_SLOT, KIND_SET_EMBLEM_SLOT]
		or slot_index < 0
	):
		return false
	_append_entry(owner, kind, effect_id, source_runtime_id, logical_time_us, battle_instance_id, {
		"slot_index": slot_index,
		"slot_state": slot_state.duplicate(true),
	})
	return true


func record_emblem_progress(
	owner: BattleEffectOwnerRef,
	emblem_instance_id: StringName,
	amount: int,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int,
	battle_instance_id: StringName = &""
) -> bool:
	if owner == null or owner.owned_card == null or emblem_instance_id.is_empty() or amount <= 0:
		return false
	_append_entry(owner, KIND_ADD_EMBLEM_PROGRESS, effect_id, source_runtime_id, logical_time_us, battle_instance_id, {
		"emblem_instance_id": emblem_instance_id,
		"amount": amount,
	})
	return true


func record_equipment_consumption(
	owner: BattleEffectOwnerRef,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int,
	battle_instance_id: StringName = &""
) -> bool:
	if (
		owner == null
		or owner.owned_card == null
		or owner.owned_card.card_data == null
		or owner.owned_card.card_data.card_type != CardData.CardType.EQUIPMENT
	):
		return false
	for entry: Dictionary in _entries:
		if (
			entry.get("kind") == KIND_CONSUME_EQUIPMENT
			and entry.get("owned_card_instance_id") == owner.owned_card_instance_id
		):
			return false
	_append_entry(owner, KIND_CONSUME_EQUIPMENT, effect_id, source_runtime_id, logical_time_us, battle_instance_id, {})
	return true


func get_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		result.append(entry.duplicate(true))
	return result


func _append_entry(
	owner: BattleEffectOwnerRef,
	kind: StringName,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int,
	battle_instance_id: StringName,
	parameters: Dictionary
) -> void:
	var entry_index := _entries.size()
	_entries.append({
		"entry_id": StringName("%s:owned_change:%d" % [battle_instance_id, entry_index]),
		"battle_instance_id": battle_instance_id,
		"kind": kind,
		"owned_card_instance_id": owner.owned_card_instance_id,
		"side": owner.state.side if owner.state != null else -1,
		"owner_kind": owner.owner_kind,
		"owner_runtime_id": owner.runtime_id,
		"effect_id": effect_id,
		"source_runtime_id": source_runtime_id,
		"logical_time_us": logical_time_us,
		"parameters": parameters.duplicate(true),
	})
