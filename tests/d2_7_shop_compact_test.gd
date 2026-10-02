extends "res://tests/d2_7_pack_surface_test.gd"

func _run() -> void:
	create_timer(55.0).timeout.connect(func(): push_error("商店紧凑布局验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if OS.get_cmdline_user_args().has("2k") else DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(0.7).timeout
	main = shell.main_screen
	check(CardView.format_gold_symbols("获得12金币和金币袋") == "获得12¤和金币袋" and main.battle_log_text.get_theme_font("normal_font") == main.BATTLE_LOG_FONT, "卡面金额使用普通符号并保留纹章名字、战斗原字体")
	main.run_save_path = "/private/tmp/project-card-shop-compact-save.json"
	main.run_reward_state.gold = 1000
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	check(main.ordinary_shop_panel.find_children("*", "ScrollContainer", true, false).is_empty(), "商店商品区没有滚动容器")
	var all_fit := true
	var all_one_row := true
	var single_offer: Dictionary = {}
	for seed_value: int in range(1, 21):
		main.ordinary_shop_service.rng.seed = seed_value
		main._generate_ordinary_shop(false)
		for offer: Dictionary in main.ordinary_shop_service.offers:
			if offer.kind == "single_card": single_offer = offer.duplicate(true)
		await process_frame
		await process_frame
		await process_frame
		var grid := main.ordinary_shop_offer_list.find_child("OrdinaryShopOfferGrid", true, false) as HBoxContainer
		var panel_rect: Rect2 = main.ordinary_shop_panel.get_global_rect()
		all_fit = all_fit and main.ordinary_shop_panel.size == Vector2(864, 360)
		var top: float = -1.0
		for product: Control in grid.get_children():
			var rect := product.get_global_rect()
			all_fit = all_fit and panel_rect.encloses(rect)
			if top < 0: top = rect.position.y
			all_one_row = all_one_row and is_equal_approx(top, rect.position.y)
		var services := main.ordinary_shop_offer_list.find_child("ShopServices", true, false) as Control
		all_fit = all_fit and panel_rect.encloses(services.get_global_rect())
	check(all_fit and all_one_row, "20组真实报价全部在固定敌方区域首排内，服务区也没有撑大面板")
	check(not single_offer.is_empty(), "真实报价包含可用于悬停验收的单卡")
	if not single_offer.is_empty():
		var index: int = main.ordinary_shop_service.offers.size()
		main.ordinary_shop_service.offers.append(single_offer)
		for hidden: bool in [false, true]:
			single_offer.hidden = hidden
			main._refresh_ordinary_shop_panel()
			await create_timer(0.1).timeout
			var tile := _tile(index) as ShopOfferView
			var price := tile.get_node("ShopPrice") as Control
			var before := price.get_global_transform_with_canvas()
			await move(tile.get_global_rect().get_center())
			await create_timer(0.2).timeout
			check(price.get_global_transform_with_canvas() == before and tile._visual.position.y < -4, ("暗单" if hidden else "明单") + "仅卡图抬起，价格固定在原位")
	var scraper_tile: ShopOfferView
	for tile: ShopOfferView in main.ordinary_shop_offer_list.find_children("ShopOffer_*", "Control", true, false):
		var offer: Dictionary = main.ordinary_shop_service.offers[int(tile.get_meta("shop_offer_index"))]
		if offer.kind == "scraper": scraper_tile = tile
		if offer.kind in ["scraper", "tear_service", "single_card"]:
			var price := tile.get_node("ShopPrice") as Control
			var before := price.get_global_transform_with_canvas()
			await move(tile.get_global_rect().get_center())
			await create_timer(0.2).timeout
			check(price.get_global_transform_with_canvas() == before, offer.kind + "底部价格不随图片旋转或抬起")
			if offer.kind != "single_card":
				check(not tile.is_processing() and tile._visual.position == Vector2.ZERO and tile._visual.rotation == 0, offer.kind + "服务图片指向时保持静止")
	check(scraper_tile != null and scraper_tile._visual.get_child(0).size == Vector2(59, 59), "商店刮刀保持原生59像素尺寸")
	await move(Vector2(40, 650))
	await capture("compact-table")
	# PNG编码是同步操作，先跨过两帧，避免编码耗时成为新Tween的首帧delta。
	await process_frame
	await process_frame
	main._toggle_ordinary_shop()
	check(not main.ordinary_shop_open and main.ordinary_shop_panel.visible, "离店先停止交易，保留画面播放收起动画")
	await create_timer(main.SHOP_CLOSE_DURATION * 0.5).timeout
	check(main._shop_motion_root.position.y < -1 and main.ordinary_shop_panel.visible, "离店中途整块商店向上回收")
	await create_timer(main.SHOP_CLOSE_DURATION).timeout
	check(not main.ordinary_shop_panel.visible and main.get_node("%EnemyBoardSection").visible, "离店动画结束后恢复正常敌方战场")
	var owned: OwnedCard
	var source: CardView
	for slot: Control in main._get_collection_card_slots():
		var candidate := slot.get_meta("owned_card", null) as OwnedCard
		if candidate != null and candidate.card_data.card_type == CardData.CardType.MINION:
			owned = candidate
			source = slot.get_child(0)
			break
	check(owned != null, "收藏提供真实可检视随从")
	if owned != null:
		main._open_card_inspection(owned.card_data, owned, source)
		await create_timer(0.3).timeout
		if not main._inspection_library_expanded:
			main._toggle_inspection_library()
			await create_timer(0.3).timeout
		var scraper: TextureRect = main.emblem_library._scraper
		main.scraper_count = 2
		main.emblem_library.set_scraper_count(2)
		check(main._inspection_card_view.effect_text_label.get_theme_font("font") == main._inspection_card_view.CARD_TEXT_FONT, "卡面使用原生正文字体，不再被金币包装字体改变间距")
		check(main.emblem_library._scraper_groove.visible and main.emblem_library._scraper_groove.position == scraper.position and scraper.size == Vector2(59, 59), "工具箱有与刮刀真实轮廓对齐的凹槽")
		await click(scraper.get_global_rect().get_center())
		check(main._rune_scraper_mode and not scraper.visible and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "点击工具箱拿起刮刀，原位仅留凹槽且隐藏系统指针")
		check(main._rune_scraper_visual.size == scraper.size and main._rune_scraper_visual.scale == scraper.get_global_transform_with_canvas().get_scale(), "手持刮刀与工具箱内显示尺寸完全一致")
		await move(Vector2(1080, 440))
		await capture("compact-held-scraper")
		await key(KEY_ESCAPE)
		check(not main._rune_scraper_mode and is_instance_valid(main._rune_scraper_visual) and not scraper.visible, "取消动作后保留飞回动画，原位不会提前出现第二把刀")
		await create_timer(main.SCRAPER_RETURN_DURATION + 0.1).timeout
		check(scraper.visible and not is_instance_valid(main._rune_scraper_visual) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "飞回结束后恢复工具箱刮刀与普通鼠标")
		await click(scraper.get_global_rect().get_center())
		main._close_card_inspection()
		await create_timer(0.4).timeout
		check(not is_instance_valid(main._inspection_overlay) and scraper.visible and not is_instance_valid(main._rune_scraper_visual), "拿着刮刀关闭检视，刮刀仍飞回正在移动的工具箱")
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("D2-7 compact shop failures: ", failures)
	quit(1 if failures else 0)
