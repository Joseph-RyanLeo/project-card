extends "res://tests/service_interaction_revision_20261020_test.gd"

## 正式F2／Esc输入和真实免费交易；等待黑场结束再继续操作。
const ENTRY_SAVE := "/private/tmp/project-card-rare-entry-original.json"

func _run() -> void:
	create_timer(80.0).timeout.connect(func(): push_error("稀有商店入口回归超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = ENTRY_SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.5).timeout
	var original: Control = main
	check(original.save_run_to_path(ENTRY_SAVE) == OK, "保存正式本局作为隔离基准")
	var file := FileAccess.get_file_as_bytes(ENTRY_SAVE)
	var collection: Dictionary = original.owned_card_collection.capture_state()
	var reward: Dictionary = original.run_reward_state.capture_state()
	var shop: Dictionary = original.ordinary_shop_service.capture_state()
	await open_rare(original)
	var rare: Control = shell._rare_shop
	if not is_instance_valid(rare): quit(1); return
	check(rare.ordinary_shop_open and rare.owned_card_collection.size() == 0 and rare.run_reward_state.gold == 0, "rare shop加载完成且为独立免费商店")
	check(not rare._shop_procurement_button.visible and not rare._shop_board_view.get_node("CardServicesTab").visible, "测试商店使用当前棋盘控件隐藏定向采购和卡牌服务")
	check(rare.ordinary_shop_service.offers.size() == 2 and rare.ordinary_shop_offer_list.find_children("ShopOffer_*", "Control", true, false).size() == 2, "普通与传奇两包都实际生成商品节点")
	var generation: int = rare.ordinary_shop_service.rng.state
	await _click(rare._shop_board_view._refresh)
	check(await wait_for(func(): return rare.ordinary_shop_service.rng.state != generation), "原生点击免费刷新能完整重建商品")
	var tile: Control = rare.ordinary_shop_offer_list.find_child("ShopOffer_0", true, false)
	await _click(tile)
	check(await wait_for(func(): return is_instance_valid(rare._card_pack_opening)), "rare shop原生购买进入正式开包控制器")
	check(rare.owned_card_collection.size() == 5 and rare.run_reward_state.gold == 0 and FileAccess.file_exists(rare.run_save_path), "免费购买五张卡真实写入独立临时存档")
	rare._close_card_inspection(true)
	await process_frame
	await verify_tuner(rare)
	var scratch: String = rare.run_save_path
	await _click(rare._shop_board_view.get_node("LeaveShopButton"))
	check(await wait_for(func(): return not is_instance_valid(shell._rare_shop) and not shell.screen_transition.busy), "原生离店结束黑场后回到正式本局")
	check(original.visible and original._escape_pause_menu.is_processing_input() and not FileAccess.file_exists(scratch), "来源输入恢复且临时交易文件已清理")
	await verify_tuner(original)
	await open_rare(original)
	check(is_instance_valid(shell._rare_shop) and shell._rare_shop.owned_card_collection.size() == 0, "再次进入rare shop重新建立独立测试收藏")
	shell.close_rare_shop()
	await process_frame
	check(original.owned_card_collection.capture_state() == collection and original.run_reward_state.capture_state() == reward and original.ordinary_shop_service.capture_state() == shop, "两个入口往返后正式收藏、金币和报价保持不变")
	check(FileAccess.get_file_as_bytes(ENTRY_SAVE) == file, "正式存档逐字节保持不变")
	shell.queue_free()
	await process_frame
	await process_frame
	for suffix: String in ["", ".bak"]: DirAccess.remove_absolute(ENTRY_SAVE + suffix)
	print("Rare shop and Esc entry: %d checks, %d failures" % [assertions, failures])
	quit(1 if failures else 0)

func press_key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func wait_for(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	return predicate.call()

func open_rare(source: Control) -> void:
	await press_key(KEY_F2)
	check(source._developer_console.visible and source._developer_console._command_input.has_focus(), "真实F2打开并聚焦控制台")
	source._developer_console._command_input.text = "rare shop"
	await press_key(KEY_ENTER)
	check(await wait_for(func(): return is_instance_valid(shell._rare_shop) and not shell.screen_transition.busy), "真实回车提交rare shop并等待加载结束")

func verify_tuner(source: Control) -> void:
	await press_key(KEY_ESCAPE)
	check(source._escape_pause_menu.is_menu_open(), "真实Esc打开当前来源的暂停菜单")
	var button: Button
	for candidate: Button in source._escape_pause_menu.find_children("*", "Button", true, false):
		if candidate.text == "开包特效调整器": button = candidate
	check(is_instance_valid(button), "暂停菜单存在开包特效入口")
	await _click(button)
	check(await wait_for(func(): return shell.is_pack_effect_tuner_open() and not shell.screen_transition.busy), "原生点击Esc菜单后开包特效调整器完成加载")
	if not shell.is_pack_effect_tuner_open(): return
	var tuner: Control = shell._pack_effect_tuner
	var preview: Control = tuner.preview_shop
	check(not source.visible and not source._escape_pause_menu.is_processing_input(), "调整器隔离来源场景显示和输入")
	check(tuner.controls.size() == 54 and preview.ordinary_shop_open and preview.ordinary_shop_service.offers.size() == 2, "全部54项参数与共用稀有商店预览加载完成")
	check(not preview._shop_procurement_button.visible and not preview._shop_board_view.get_node("CardServicesTab").visible, "嵌入预览同样使用当前棋盘控件")
	for index: int in 2:
		var count: int = preview.owned_card_collection.size()
		await _click(tuner.find_child("PreviewNormal" if index == 0 else "PreviewRare", true, false))
		check(await wait_for(func(): return is_instance_valid(preview._card_pack_opening)), "真实普通／传奇预览按钮启动开包")
		check(preview.owned_card_collection.size() == count + 5 and preview._card_pack_opening.has_rare == (index == 1), "预览五张包的实例与普通／传奇品级正确")
		await _click(tuner.find_child("PreviewShop", true, false))
		check(not is_instance_valid(preview._inspection_overlay), "原生回商店按钮可关闭预览并再次播放")
	var scratch: String = preview.run_save_path
	await _click(tuner.find_child("CloseEffects", true, false))
	check(await wait_for(func(): return not shell.is_pack_effect_tuner_open() and not shell.screen_transition.busy), "原生返回按钮关闭调整器并完成黑场返回")
	check(source.visible and source._escape_pause_menu.is_processing_input() and not FileAccess.file_exists(scratch), "返回准确来源并清理嵌入商店临时存档")
