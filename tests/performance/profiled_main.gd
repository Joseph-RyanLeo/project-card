## 用 super 调用正式实现，只包住计时；子步骤耗时包含在父步骤中。
extends "res://scripts/main.gd"

var diagnostic_samples: Array[Dictionary] = []
var diagnostic_stage := "startup"

func diagnostic_record(tag: String, began: int) -> void:
	diagnostic_samples.append({"stage": diagnostic_stage, "tag": tag, "ms": (Time.get_ticks_usec() - began) / 1000.0, "frame": Engine.get_process_frames()})

func _build_card_definition_registry() -> Dictionary:
	var began := Time.get_ticks_usec()
	var result = super._build_card_definition_registry()
	diagnostic_record("_build_card_definition_registry", began)
	return result

func _can_buy_shop_card_pack(offer: Dictionary, definitions: Dictionary = {}, candidates: Array[CardData] = []) -> bool:
	var began := Time.get_ticks_usec()
	var result = super._can_buy_shop_card_pack(offer, definitions, candidates)
	diagnostic_record("_can_buy_shop_card_pack", began)
	return result

func _get_shop_card_definitions() -> Array[CardData]:
	var began := Time.get_ticks_usec()
	var result = super._get_shop_card_definitions()
	diagnostic_record("_get_shop_card_definitions", began)
	return result

func turn_collection_page(page: int, method: StringName = &"direct") -> bool:
	var began := Time.get_ticks_usec()
	var result = super.turn_collection_page(page, method)
	diagnostic_record("turn_collection_page", began)
	return result

func _build_collection_cards(
	entering_card: CardData = null,
	entry_global_position: Variant = null
) -> void:
	var began := Time.get_ticks_usec()
	super._build_collection_cards(entering_card, entry_global_position)
	diagnostic_record("_build_collection_cards", began)

func _create_page_turn_snapshot(
	page_side: int,
	page_index: int,
	filtered_cards: Array[CardData],
	page_texture: Texture2D,
	include_cards: bool
) -> Control:
	var began := Time.get_ticks_usec()
	var result = super._create_page_turn_snapshot(page_side, page_index, filtered_cards, page_texture, include_cards)
	diagnostic_record("_create_page_turn_snapshot", began)
	return result

func _swap_page_turn_face(moving_page: Control, target_side: int) -> void:
	var began := Time.get_ticks_usec()
	super._swap_page_turn_face(moving_page, target_side)
	diagnostic_record("_swap_page_turn_face", began)

func _create_collection_card_slot(
	card_data: CardData,
	is_deployed_ghost: bool = false,
	interactive: bool = true,
	owned_card: OwnedCard = null
) -> Control:
	var began := Time.get_ticks_usec()
	var result = super._create_collection_card_slot(card_data, is_deployed_ghost, interactive, owned_card)
	diagnostic_record("_create_collection_card_slot", began)
	return result

func get_filtered_collection_cards() -> Array[CardData]:
	var began := Time.get_ticks_usec()
	var result = super.get_filtered_collection_cards()
	diagnostic_record("get_filtered_collection_cards", began)
	return result

func _refresh_resource_preparation_trays() -> void:
	var began := Time.get_ticks_usec()
	super._refresh_resource_preparation_trays()
	diagnostic_record("_refresh_resource_preparation_trays", began)

func _toggle_ordinary_shop() -> void:
	var began := Time.get_ticks_usec()
	super._toggle_ordinary_shop()
	diagnostic_record("_toggle_ordinary_shop", began)

func _refresh_ordinary_shop_panel() -> void:
	var began := Time.get_ticks_usec()
	super._refresh_ordinary_shop_panel()
	diagnostic_record("_refresh_ordinary_shop_panel", began)

func _create_shop_offer_tile(index: int, offer: Dictionary, stacked: bool, definitions: Dictionary, candidates: Array[CardData]) -> ShopOfferView:
	var began := Time.get_ticks_usec()
	var result = super._create_shop_offer_tile(index, offer, stacked, definitions, candidates)
	diagnostic_record("_create_shop_offer_tile", began)
	return result

func _create_click_carry_preview(
	drag_data: Dictionary,
	pointer_global_position: Vector2
) -> Control:
	var began := Time.get_ticks_usec()
	var result = super._create_click_carry_preview(drag_data, pointer_global_position)
	diagnostic_record("_create_click_carry_preview", began)
	return result

func _update_card_carry_target(
	pointer_global_position: Vector2,
	drag_data: Dictionary
) -> Dictionary:
	var began := Time.get_ticks_usec()
	var result = super._update_card_carry_target(pointer_global_position, drag_data)
	diagnostic_record("_update_card_carry_target", began)
	return result

func start_battle(random_seed: int = -1, auto_run: bool = true) -> bool:
	var began := Time.get_ticks_usec()
	var result = super.start_battle(random_seed, auto_run)
	diagnostic_record("start_battle", began)
	return result

func _clear_battle_presentation_for_preparation() -> void:
	var began := Time.get_ticks_usec()
	super._clear_battle_presentation_for_preparation()
	diagnostic_record("_clear_battle_presentation_for_preparation", began)

func _capture_battle_snapshot(
	battle_instance_id: StringName,
	battle_seed: int
) -> BattlePreparationSnapshot:
	var began := Time.get_ticks_usec()
	var result = super._capture_battle_snapshot(battle_instance_id, battle_seed)
	diagnostic_record("_capture_battle_snapshot", began)
	return result

func _build_battle_formation(
	row: BattlefieldRow,
	row_key: StringName
) -> Array[Dictionary]:
	var began := Time.get_ticks_usec()
	var result = super._build_battle_formation(row, row_key)
	diagnostic_record("_build_battle_formation", began)
	return result

func _build_reward_card_catalog() -> Array[CardData]:
	var began := Time.get_ticks_usec()
	var result = super._build_reward_card_catalog()
	diagnostic_record("_build_reward_card_catalog", began)
	return result

func _on_battle_states_changed() -> void:
	var began := Time.get_ticks_usec()
	super._on_battle_states_changed()
	diagnostic_record("_on_battle_states_changed", began)

func _on_battle_finished(result: BattleController.Result) -> void:
	var began := Time.get_ticks_usec()
	super._on_battle_finished(result)
	diagnostic_record("_on_battle_finished", began)

func _show_battle_result(result: BattleController.Result) -> void:
	var began := Time.get_ticks_usec()
	super._show_battle_result(result)
	diagnostic_record("_show_battle_result", began)

func _restore_battle_result_layout() -> void:
	var began := Time.get_ticks_usec()
	super._restore_battle_result_layout()
	diagnostic_record("_restore_battle_result_layout", began)

func _restore_battle_snapshot(restore_collection_state: bool = true) -> void:
	var began := Time.get_ticks_usec()
	super._restore_battle_snapshot(restore_collection_state)
	diagnostic_record("_restore_battle_snapshot", began)

func settle_current_battle() -> Dictionary:
	var began := Time.get_ticks_usec()
	var result = super.settle_current_battle()
	diagnostic_record("settle_current_battle", began)
	return result

func save_run_to_path(path: String) -> Error:
	var began := Time.get_ticks_usec()
	var result = super.save_run_to_path(path)
	diagnostic_record("save_run_to_path", began)
	return result

func _refresh_preparation_effect_preview() -> void:
	var began := Time.get_ticks_usec()
	super._refresh_preparation_effect_preview()
	diagnostic_record("_refresh_preparation_effect_preview", began)


var diagnostic_rows: Array[Node] = []
func _build_scene_structure() -> void:
	super._build_scene_structure()
	for path: String in ["%FrontRow", "%BackRow", "%EnemyFrontRow", "%EnemyBackRow"]:
		var row := get_node(path)
		# Main 在入树后才动态建立战场行；替换计时脚本后重新绑定已存在的四个节点引用。
		var title: String = row.row_title
		row.set_script(load("res://tests/performance/profiled_battlefield_row.gd"))
		row.row_title = title
		row.row_title_label = row.get_node("%RowTitleLabel")
		row.row_display_area = row.get_node("%RowDisplayArea")
		row.squad_row = row.get_node("%SquadRow")
		row.placement_overlay = row.get_node("%PlacementOverlay")
		row._ready()
		diagnostic_rows.append(row)

func _restore_row_from_snapshot(row: BattlefieldRow, snapshot_value: Variant) -> void:
	var began := Time.get_ticks_usec()
	super._restore_row_from_snapshot(row, snapshot_value)
	diagnostic_record("_restore_row_from_snapshot", began)
