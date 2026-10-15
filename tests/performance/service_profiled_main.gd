extends "res://scripts/main.gd"

## 专项测试用真实实现计时；不改变场景、交易或存档行为。
var service_profile: Array[Dictionary] = []

func record_service_step(step: String, began: int) -> void:
	service_profile.append({"step": step, "ms": (Time.get_ticks_usec() - began) / 1000.0})

func _build_collection_cards(entering_card: CardData = null, entry_global_position: Variant = null, reuse_unchanged: bool = false) -> void:
	var began := Time.get_ticks_usec()
	super._build_collection_cards(entering_card, entry_global_position, reuse_unchanged)
	record_service_step("collection", began)

func _refresh_resource_preparation_trays() -> void:
	var began := Time.get_ticks_usec()
	super._refresh_resource_preparation_trays()
	record_service_step("resource_trays", began)

func _refresh_spell_preparation_tray() -> void:
	var began := Time.get_ticks_usec()
	super._refresh_spell_preparation_tray()
	record_service_step("spell_tray", began)

func _refresh_ordinary_shop_panel() -> void:
	var began := Time.get_ticks_usec()
	super._refresh_ordinary_shop_panel()
	record_service_step("shop_panel", began)

func _capture_shop_card_transaction() -> Dictionary:
	var began := Time.get_ticks_usec()
	var result := super._capture_shop_card_transaction()
	record_service_step("transaction_snapshot", began)
	return result

func _record_run_diagnostic(kind: String, detail: Dictionary = {}, force: bool = false) -> void:
	var began := Time.get_ticks_usec()
	super._record_run_diagnostic(kind, detail, force)
	record_service_step("diagnostic", began)

func save_run_to_path(path: String) -> Error:
	var began := Time.get_ticks_usec()
	var result := super.save_run_to_path(path)
	record_service_step("save", began)
	return result
