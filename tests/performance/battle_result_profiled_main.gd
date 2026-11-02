extends "res://scripts/main.gd"

## 只包裹正式结算与显示调用，不替代业务实现。
var result_profile: Dictionary = {}

func _measure(tag: String, began: int) -> void:
	var entry: Dictionary = result_profile.get(tag, {"calls": 0, "total_us": 0})
	entry.calls += 1
	entry.total_us += Time.get_ticks_usec() - began
	result_profile[tag] = entry

func _restore_battle_snapshot(restore_collection_state: bool = true) -> void:
	var began := Time.get_ticks_usec()
	super._restore_battle_snapshot(restore_collection_state)
	_measure("快照恢复", began)

func _restore_row_from_snapshot(row: BattlefieldRow, snapshot_value: Variant, retain_removed_members: bool = false) -> void:
	var began := Time.get_ticks_usec()
	super._restore_row_from_snapshot(row, snapshot_value, retain_removed_members)
	_measure("阵容恢复", began)

func _build_collection_cards(entering_card: CardData = null, entry_global_position: Variant = null, reuse_unchanged: bool = false) -> void:
	var began := Time.get_ticks_usec()
	super._build_collection_cards(entering_card, entry_global_position, reuse_unchanged)
	_measure("收藏刷新", began)

func settle_current_battle(refresh_collection: bool = true) -> Dictionary:
	var began := Time.get_ticks_usec()
	var result := super.settle_current_battle(refresh_collection)
	_measure("结算事务", began)
	return result

func _refresh_resource_preparation_trays() -> void:
	var began := Time.get_ticks_usec()
	super._refresh_resource_preparation_trays()
	_measure("资源显示刷新", began)

func save_run_to_path(path: String) -> Error:
	var began := Time.get_ticks_usec()
	var result := super.save_run_to_path(path)
	_measure("存档", began)
	return result
