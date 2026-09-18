class_name RunSettlementJournal
extends RefCounted

## 正常战后事务的一次性提交凭证。
## D2-5 后续消费永久成长、奖励、伤势与耐久时，必须先检查同一 battle_instance_id；
## 只有整批写回成功后才登记，重复按钮、重复信号或读档重放不能再次消费。

var _committed_battles: Dictionary = {}


func is_committed(battle_instance_id: StringName) -> bool:
	return not battle_instance_id.is_empty() and _committed_battles.has(battle_instance_id)


func mark_committed(battle_instance_id: StringName) -> bool:
	if battle_instance_id.is_empty() or is_committed(battle_instance_id):
		return false
	_committed_battles[battle_instance_id] = true
	return true


func capture_state() -> Dictionary:
	return _committed_battles.duplicate()


func restore_state(snapshot: Dictionary) -> void:
	_committed_battles = snapshot.duplicate()
