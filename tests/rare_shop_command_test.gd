extends "res://tests/card_pack_opening_test.gd"

## 正式F2命令、鼠标购买和磁盘事务，验证免费测试商店及退出后本局不变。
func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("稀有商店验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	var original: Control = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	original.run_save_path = "/private/tmp/project-card-rare-shop-origin.json"
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if OS.get_cmdline_user_args().has("2k") else DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(0.7).timeout
	main = original
	original.run_reward_state.gold = 123
	check(original.save_run_to_path(original.run_save_path) == OK, "先保存正式本局作为隔离检查基准")
	var original_file := FileAccess.get_file_as_bytes(original.run_save_path)
	var collection: Dictionary = original.owned_card_collection.capture_state()
	var reward: Dictionary = original.run_reward_state.capture_state()
	var shop: Dictionary = original.ordinary_shop_service.capture_state()
	var config: Dictionary = original.ordinary_shop_service.config.duplicate(true)
	var maze: Dictionary = original.maze_controller.capture_state()
	var previous_process: int = original.process_mode
	var previous_escape: bool = original._escape_pause_menu.is_processing_input()
	await key(KEY_F2)
	check(original._developer_console.visible and original._developer_console._command_input.has_focus(), "真实F2打开并聚焦控制台")
	for character: String in "rare shop":
		var event := InputEventKey.new()
		event.keycode = KEY_NONE
		event.unicode = character.unicode_at(0)
		event.pressed = true
		root.push_input(event, true)
		await process_frame
	await key(KEY_ENTER)
	await create_timer(0.5).timeout
	check(is_instance_valid(shell._rare_shop) and not original.visible and not original._developer_console.visible, "键盘提交rare shop打开测试商店并关闭原控制台")
	if not is_instance_valid(shell._rare_shop): quit(1); return
	main = shell._rare_shop
	check(main.ordinary_shop_open and main.maze_controller == null and main.run_reward_state.gold == 0, "测试商店独立运行且零金币可购买")
	check(main.run_save_path != original.run_save_path and main.run_save_path.begins_with("user://rare-shop-test-"), "测试交易使用跨平台独立临时存档")
	check(not original._escape_pause_menu.is_processing_input() and original.process_mode == Node.PROCESS_MODE_DISABLED, "原游戏暂停输入和处理，不与测试商店争抢Esc")
	var registry: Dictionary = main._build_card_definition_registry()
	_check_offers(registry)
	await capture("rare-shop-free")
	var refresh: Button = main.ordinary_shop_panel.find_child("OrdinaryShopRefreshButton", true, false)
	var generation: int = main.ordinary_shop_service.rng.state
	await click(refresh.get_global_rect().get_center())
	await create_timer(0.3).timeout
	check(main.run_reward_state.gold == 0 and main.ordinary_shop_service.refresh_price() == 0 and main.ordinary_shop_service.rng.state != generation, "真实刷新按钮重新生成两包且保持免费")
	_check_offers(registry)
	for index: int in 2:
		var before: int = main.owned_card_collection.size()
		await click(_tile(index).get_global_rect().get_center())
		await create_timer(0.35).timeout
		var sequence: CardPackOpening = main._card_pack_opening
		check(is_instance_valid(sequence) and sequence.cards.size() == 5 and sequence.has_rare == (index == 1), "普通／传奇包走正式开包控制器并正确判定稀有")
		check(main.run_reward_state.gold == 0 and main.owned_card_collection.size() == before + 5 and FileAccess.file_exists(main.run_save_path), "零金币真实购买入测试收藏并保存一次")
		await click(_pointer_for_card_point(main._inspection_surface, Vector2(40, 70)))
		await create_timer(0.45).timeout
		check(sequence.phase == CardPackOpening.Phase.BURST and sequence.glow.rare == (index == 1), "单击撕包播放对应普通／稀有金光")
		if index == 1: await capture("rare-shop-legendary-burst")
		await create_timer(0.9).timeout
		for card_index: int in 5:
			if card_index == 4 and index == 1:
				check(main._inspection_owned_card.card_data.rarity == CardData.Rarity.IV and sequence.glow.rare, "传奇包最后一张为IV卡并播放独立揭晓光环")
			await click(_pointer_for_card_point(main._inspection_surface, Vector2(48, 65)))
		await create_timer(0.6).timeout
		check(not is_instance_valid(main._inspection_overlay) and main.ordinary_shop_open, "五张连点后返回测试商店")
	# 把全部开放IV加入测试收藏，再刷新；仍需稳定生成传奇包以反复测试。
	for definition: CardData in main.ordinary_shop_service._eligible_cards(main._get_shop_card_definitions(), []):
		if definition.rarity == CardData.Rarity.IV: main.owned_card_collection.create_card(definition)
	await click(refresh.get_global_rect().get_center())
	await create_timer(0.3).timeout
	_check_offers(registry)
	check(main._can_buy_shop_card_pack(main.ordinary_shop_service.offers[1]), "测试收藏持有全部IV后仍能重复生成并购买传奇包")
	var repeated_count: int = main.owned_card_collection.size()
	await click(_tile(1).get_global_rect().get_center())
	await create_timer(0.35).timeout
	check(main.owned_card_collection.size() == repeated_count + 5 and main.run_reward_state.gold == 0 and main._card_pack_opening.has_rare, "已持有IV仍能再次完成免费传奇包真实交易")
	main._close_card_inspection(true)
	await process_frame
	var scratch: String = main.run_save_path
	var close: Button = main.ordinary_shop_panel.find_child("OrdinaryShopCloseButton", true, false)
	await click(close.get_global_rect().get_center())
	await process_frame
	check(not is_instance_valid(shell._rare_shop) and original.visible and original.process_mode == previous_process and original._escape_pause_menu.is_processing_input() == previous_escape, "离开恢复原游戏画面、处理模式和Esc输入")
	check(original.owned_card_collection.capture_state() == collection and original.run_reward_state.capture_state() == reward and original.ordinary_shop_service.capture_state() == shop and original.ordinary_shop_service.config == config and original.maze_controller.capture_state() == maze, "退出后原收藏、金币、商店、配置及迷宫状态完全不变")
	check(FileAccess.get_file_as_bytes(original.run_save_path) == original_file and not FileAccess.file_exists(scratch), "正式存档逐字节不变且临时交易文件已清理")
	main = original
	await key(KEY_F2)
	check(original._developer_console.visible, "离开后F2控制台恢复正常")
	original._developer_console._command_input.text = "rare shop"
	await key(KEY_ENTER)
	await create_timer(0.5).timeout
	main = shell._rare_shop
	check(main.owned_card_collection.size() == 0, "重新进入得到新的测试收藏")
	await key(KEY_ESCAPE)
	await process_frame
	check(is_instance_valid(shell._rare_shop) and main._escape_pause_menu.is_menu_open() and not original._escape_pause_menu.is_menu_open(), "Esc打开测试商店自己的暂停菜单，不穿透原游戏")
	await key(KEY_ESCAPE)
	await click(main.ordinary_shop_panel.find_child("OrdinaryShopCloseButton", true, false).get_global_rect().get_center())
	await process_frame
	check(not is_instance_valid(shell._rare_shop) and original.visible, "关闭测试商店菜单后离开恢复原游戏")
	DirAccess.remove_absolute(original.run_save_path)
	DirAccess.remove_absolute(original.run_save_path + ".bak")
	shell.queue_free()
	await process_frame
	print("Rare shop command failures: ", failures)
	quit(1 if failures else 0)

func _check_offers(registry: Dictionary) -> void:
	check(main.ordinary_shop_service.offers.size() == 2, "每次只提供普通、传奇两种大包")
	for index: int in 2:
		var offer: Dictionary = main.ordinary_shop_service.offers[index]
		var tiers: Array[int] = []
		for id: String in offer.cards: tiers.append(registry[StringName(id)].rarity)
		check(offer.kind == "card_pack" and offer.size == "large" and offer.price == 0 and tiers.count(CardData.Rarity.I) == 4 and tiers.count(CardData.Rarity.II if index == 0 else CardData.Rarity.IV) == 1, "普通4I＋1II／传奇4I＋1IV，报价免费")
