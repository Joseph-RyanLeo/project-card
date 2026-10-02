extends SceneTree

const DISPLAY_SCENE: PackedScene = preload("res://scenes/GameDisplay.tscn")
const GameDisplayScript = preload("res://scripts/ui/game_display.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _click(point: Vector2, transform: Transform2D) -> void:
	var event := InputEventMouseButton.new()
	event.position = transform * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = InputEventMouseButton.new()
	event.position = transform * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func _offer_button(container: Node, main: Node, kind: String) -> Control:
	var pending: Array[Node] = [container]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child: Node in current.get_children():
			if child is Control and child.has_meta("shop_offer_index"):
				var index := int(child.get_meta("shop_offer_index"))
				if index >= 0 and index < main.ordinary_shop_service.offers.size() and main.ordinary_shop_service.offers[index].get("kind") == kind:
					return child as Control
			pending.append(child)
	return null


func _has_offer_kind(main: Node, kind: String) -> bool:
	for offer: Dictionary in main.ordinary_shop_service.offers:
		if String(offer.get("kind", "")) == kind:
			return true
	return false


func _run() -> void:
	var is_2k := OS.get_cmdline_user_args().has("2k")
	var resolution := Vector2i(2560, 1440) if is_2k else Vector2i(1280, 720)
	root.size = resolution
	var shell := DISPLAY_SCENE.instantiate()
	root.add_child(shell)
	shell.apply_display_mode(GameDisplayScript.DisplayMode.WINDOW_2K if is_2k else GameDisplayScript.DisplayMode.WINDOW_720P)
	for _frame: int in 90:
		await process_frame
		if shell.get_window().size == resolution:
			break
	var main = shell.main_screen
	var world_view_before_shop: int = main.current_world_view
	var test_save_path := "/private/tmp/project-card-d2-7-shop-input-state.json"
	main.run_save_path = test_save_path
	var seeded_shop := false
	for seed_value: int in range(1, 200):
		main.ordinary_shop_service.rng.seed = seed_value
		if main._generate_ordinary_shop(false) and _has_offer_kind(main, "sticker_pack") and _has_offer_kind(main, "card_pack"):
			seeded_shop = true
			break
	_check(seeded_shop, "GUI验收商店种子包含可点击卡包和贴纸包")
	var transform: Transform2D = shell.render_container.get_global_transform_with_canvas()
	_check(transform.get_scale().is_equal_approx(Vector2(2, 2) if is_2k else Vector2.ONE), "商店输入测试运行于真实%s显示壳" % ("2K" if is_2k else "720p"))
	var entry_point: Vector2 = main.ordinary_shop_entry_button.get_global_rect().get_center()
	await _click(entry_point, transform)
	for _frame: int in 3:
		await process_frame
	await create_timer(main.SHOP_OPEN_DURATION + main.SHOP_REBOUND_DURATION).timeout
	_check(main.ordinary_shop_panel.visible and not main.ordinary_shop_service.offers.is_empty(), "鼠标点击打开普通商店并显示真实配置生成的报价")
	_check(main.current_world_view == 0, "进入商店自动切换到敌方战场桌面")
	_check(main.ordinary_shop_panel.position == Vector2(208, 0) and main.ordinary_shop_panel.size == Vector2(864, 360), "商店面板按敌方中央两排逻辑坐标定位")
	var shop_backdrop := main.ordinary_shop_layer.get_node_or_null("ShopMotionRoot/ShopTableBackdrop") as TextureRect
	_check(shop_backdrop != null and shop_backdrop.texture.resource_path == "res://assets/card_ui/shop/background.png" and shop_backdrop.position == main.SHOP_BACKGROUND_POSITION, "商店窗口显示对应位置的桌布素材")
	main.run_reward_state.gold = 100
	main._refresh_ordinary_shop_panel()
	await process_frame # 等待容器按新商品列表完成布局，再读取真实屏幕坐标
	await process_frame
	if OS.get_cmdline_user_args().has("capture"):
		root.get_texture().get_image().save_png("/private/tmp/project-card-d2-7-shop-%s.png" % ("2k" if is_2k else "720p"))
	var pack_button := _offer_button(main.ordinary_shop_offer_list, main, "card_pack")
	var pack_index := int(pack_button.get_meta("shop_offer_index")) if pack_button != null else -1
	var pack_offer: Dictionary = main.ordinary_shop_service.offers[pack_index] if pack_index >= 0 else {}
	var had_pack_button := pack_button != null
	var pack_gold_before: int = main.run_reward_state.gold
	var pack_card_count: int = main.owned_card_collection.get_cards().size()
	if pack_button != null:
		await _click(pack_button.get_global_rect().get_center(), transform)
	var expected_pack_count := int(main.ordinary_shop_service.config.card_pack_sizes.get(pack_offer.get("size", "small"), 0)) if not pack_offer.is_empty() else 0
	_check(had_pack_button and main.owned_card_collection.get_cards().size() == pack_card_count + expected_pack_count and main.run_reward_state.gold == pack_gold_before - int(pack_offer.get("price", 0)), "真实鼠标购买卡包后收藏与金币按商品内容同时变化")
	await process_frame
	await process_frame
	var sticker_button := _offer_button(main.ordinary_shop_offer_list, main, "sticker_pack")
	var had_sticker_button := sticker_button != null
	var sticker_gold_before: int = main.run_reward_state.gold
	var sticker_count_before: int = main.emblem_library.get_inventory_state().size()
	var sticker_offer: Dictionary = main.ordinary_shop_service.offers[int(sticker_button.get_meta("shop_offer_index"))] if sticker_button != null else {}
	if sticker_button != null:
		await _click(sticker_button.get_global_rect().get_center(), transform)
	_check(had_sticker_button and main.emblem_library.get_inventory_state().size() == sticker_count_before + 5 and main.run_reward_state.gold == sticker_gold_before - int(sticker_offer.get("price", 0)), "真实鼠标购买贴纸包后工具箱增加五枚独立实例并扣除报价")
	await process_frame
	await process_frame
	var scraper_button := _offer_button(main.ordinary_shop_offer_list, main, "scraper")
	var had_scraper_button := scraper_button != null
	if scraper_button != null:
		(main.ordinary_shop_offer_list.get_parent() as ScrollContainer).ensure_control_visible(scraper_button)
		await process_frame
		await process_frame
	var scraper_before: int = main.scraper_count
	var scraper_gold_before: int = main.run_reward_state.gold
	if scraper_button != null:
		await _click(scraper_button.get_global_rect().get_center(), transform)
	_check(had_scraper_button and main.scraper_count == scraper_before + 1 and main.run_reward_state.gold == scraper_gold_before - 2, "真实鼠标购买刮刀后数量增加且扣除2金币")
	var refresh_button := main.ordinary_shop_panel.find_child("OrdinaryShopRefreshButton", true, false) as Button
	var refresh_gold_before: int = main.run_reward_state.gold
	for _frame: int in 2:
		await process_frame
	refresh_button = main.ordinary_shop_panel.find_child("OrdinaryShopRefreshButton", true, false) as Button
	if refresh_button != null:
		await _click(refresh_button.get_global_rect().get_center(), transform)
	_check(refresh_button != null and main.ordinary_shop_service.refresh_count == 1 and main.run_reward_state.gold == refresh_gold_before - 1, "真实鼠标刷新后替换报价并扣除第1次刷新费")
	var retained_offers := JSON.stringify(main.ordinary_shop_service.offers)
	var retained_gold: int = main.run_reward_state.gold
	var retained_scrapers: int = main.scraper_count
	var close_button := main.ordinary_shop_panel.find_child("OrdinaryShopCloseButton", true, false) as Button
	if close_button != null:
		await _click(close_button.get_global_rect().get_center(), transform)
	await create_timer(main.SHOP_CLOSE_DURATION + 0.1).timeout
	_check(close_button != null and not main.ordinary_shop_panel.visible and FileAccess.file_exists(test_save_path), "鼠标离店关闭商店并写入本局存档")
	_check(main.current_world_view == world_view_before_shop, "离店恢复进入商店前的主视图")
	await _click(main.ordinary_shop_entry_button.get_global_rect().get_center(), transform)
	_check(main.ordinary_shop_panel.visible and JSON.stringify(main.ordinary_shop_service.offers) == retained_offers and main.ordinary_shop_service.refresh_count == 1, "重新进入同一家商店保留刷新后的原报价")
	await _click(main.ordinary_shop_panel.find_child("OrdinaryShopCloseButton", true, false).get_global_rect().get_center(), transform)
	await create_timer(main.SHOP_CLOSE_DURATION + 0.1).timeout
	if main.continue_run_button.visible:
		await _click(main.continue_run_button.get_global_rect().get_center(), transform)
	_check(not main.ordinary_shop_panel.visible and main.run_reward_state.gold == retained_gold and main.scraper_count == retained_scrapers, "真实鼠标继续游戏恢复离店存档且不重复扣费或发货")
	var panel_rect: Rect2 = main.ordinary_shop_panel.get_global_rect()
	_check(panel_rect.position.x >= 0 and panel_rect.end.x <= 1280 and panel_rect.position.y >= 0 and panel_rect.end.y <= 720, "商店面板完整位于720p逻辑画布内")
	DirAccess.remove_absolute(test_save_path)
	print("D2-7 shop input failures: ", failures)
	quit(1 if failures else 0)
