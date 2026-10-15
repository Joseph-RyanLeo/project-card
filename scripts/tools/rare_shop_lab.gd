extends "res://scripts/main.gd"

## 复用正式Main的商店、交易、包装和卡牌检视；测试状态归属独立实例。
signal close_requested
const RareShopService = preload("res://scripts/tools/rare_shop_service.gd")
var diagnostic_context: Callable
var diagnostic_feedback: Callable

func _ready() -> void:
	short_maze_enabled = false
	collection_cards.clear()
	run_save_path = "user://rare-shop-test-%d.json" % Time.get_ticks_usec()
	super._ready()
	ordinary_shop_service = RareShopService.new()
	ordinary_shop_service.initialize(Time.get_ticks_usec())
	run_reward_state.gold = 0
	_toggle_ordinary_shop()
	ordinary_shop_status.text = "购买与刷新免费；普通包4张I＋1张II，传奇包4张I＋1张IV；离开返回原游戏。"
	start_battle_button.hide()
	# 隔离商店只开放开包工具；其他实验室依赖正式Main的场景切换。
	for button: Button in _escape_pause_menu.find_children("*", "Button", true, false):
		if button.text in ["攻击特效调试器", "卡面调整器", "战斗实验室", "还原"]: button.hide()

func _refresh_ordinary_shop_panel() -> void:
	super._refresh_ordinary_shop_panel()
	if not ordinary_shop_service is RareShopService: return
	ordinary_shop_panel.find_child("OrdinaryShopTitle", true, false).text = "稀有商店 · 开包特效测试"
	for button_name: String in ["SellCardsButton", "ActionProcurementButton", "CardExchangeButton"]:
		ordinary_shop_panel.find_child(button_name, true, false).hide()
	debug_new_shop_button.hide()
	continue_run_button.hide()
	ordinary_shop_entry_button.hide()
	for stack: ShopPackStackView in ordinary_shop_offer_list.find_children("ShopPackStack_*", "Control", true, false):
		if stack.has_meta("rare_caption") or stack._offers.is_empty(): continue
		var index: int = stack._offers[0].get_meta("shop_offer_index")
		var caption := "普通" if index == 0 else "传奇"
		stack.set_price(_shop_price([0], caption))
		stack.set_meta("rare_caption", caption)

func _ordinary_shop_offer_text(offer: Dictionary, definitions: Dictionary = {}) -> String:
	if offer.has("display_name"):
		return "%s · 免费 · 4张I级＋1张%s级" % [offer.display_name, "II" if offer.pack_id == "ash_ledger" else "IV"]
	return super._ordinary_shop_offer_text(offer, definitions)

func _open_shop_pack_inspection(offer: Dictionary, source: Control = null, opening: bool = false, acquired: Array[OwnedCard] = [], offer_index: int = -1, sticker_ids: Array[StringName] = []) -> void:
	super._open_shop_pack_inspection(offer, source, opening, acquired, offer_index, sticker_ids)
	if offer.has("display_name") and is_instance_valid(_inspection_overlay):
		_inspection_overlay.get_node("InspectionPackName").text = String(offer.display_name) + " · 免费"

func _toggle_ordinary_shop() -> void:
	if ordinary_shop_open:
		if not is_instance_valid(_inspection_overlay): close_requested.emit()
		return
	super._toggle_ordinary_shop()


func _capture_run_diagnostic_state() -> Dictionary:
	var state := super._capture_run_diagnostic_state()
	var sequence: CardPackOpening = _card_pack_opening
	state["pack_test"] = {
		"save_path": ProjectSettings.globalize_path(run_save_path),
		"save_directory_exists": DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(run_save_path).get_base_dir()),
		"status": ordinary_shop_status.text if is_instance_valid(ordinary_shop_status) else "",
		"offers": ordinary_shop_service.offers.duplicate(true),
		"inspection_open": is_instance_valid(_inspection_overlay), "inspection_closing": _inspection_closing,
		"opening": _shop_pack_opening,
		"sequence": {"phase": CardPackOpening.Phase.keys()[sequence.phase], "card_count": sequence.cards.size(), "current_index": sequence.current_index, "prepared_cards": sequence._background_cards.size(), "has_rare": sequence.has_rare} if is_instance_valid(sequence) else {},
	}
	if diagnostic_context.is_valid(): state["pack_tuner"] = diagnostic_context.call()
	return state


func _buy_shop_card_pack(index: int, offer: Dictionary) -> Array[OwnedCard]:
	_record_run_diagnostic("pack_purchase_attempt", {"offer_index": index, "pack_id": offer.get("pack_id", "")}, true)
	var acquired := super._buy_shop_card_pack(index, offer)
	_record_run_diagnostic("pack_purchase_result", {"offer_index": index, "acquired_count": acquired.size(), "status": ordinary_shop_status.text}, true)
	return acquired


func _show_battle_diagnostic_message(message: String) -> void:
	if diagnostic_feedback.is_valid():
		diagnostic_feedback.call(message)
	else:
		super._show_battle_diagnostic_message(message)


func _exit_tree() -> void:
	super._exit_tree()
	for suffix: String in ["", ".bak", ".diagnostics.jsonl", ".diagnostics.jsonl.previous", ".diagnostics.jsonl.battle.json"]:
		if FileAccess.file_exists(run_save_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(run_save_path + suffix))
