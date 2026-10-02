extends "res://tests/d2_7_shop_presentation_test.gd"

## 原生输入验收：失败购买保留轮播，成功交易补位，检视往返及开包只结算一次。
func _run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("商店动画验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if OS.get_cmdline_user_args().has("2k") else DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(0.7).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-shop-animation-state.json"
	main.run_reward_state.gold = 200
	main.ordinary_shop_service.rng.seed = 12
	await click(main.ordinary_shop_entry_button.get_global_rect().get_center())
	await create_timer(0.45).timeout
	var original: Array = main.ordinary_shop_service.offers.duplicate(true)
	var definition: CardData
	for card: CardData in main._get_shop_card_definitions():
		if card.card_type == CardData.CardType.MINION and card.rarity == CardData.Rarity.I:
			definition = card
			break
	check(definition != null, "真实卡池提供暗单测试随从")
	if definition == null: quit(1); return
	var pack: Dictionary
	var sticker: Dictionary
	var scraper: Dictionary
	for offer: Dictionary in original:
		if offer.kind == "card_pack" and pack.is_empty(): pack = offer
		if offer.kind == "sticker_pack" and sticker.is_empty(): sticker = offer
		if offer.kind == "scraper": scraper = offer
	check(not pack.is_empty() and not sticker.is_empty(), "真实生成商品提供卡包及贴纸包")
	var hidden := {"kind": "single_card", "card_id": String(definition.id), "hidden": true, "hint": "card_type", "price": 8, "instance_seed": "13", "offer_id": "animation_hidden"}
	var visible: Dictionary = hidden.duplicate(true)
	visible.hidden = false
	visible.offer_id = "animation_visible"
	main.ordinary_shop_service.offers.clear()
	for offer: Dictionary in [pack, hidden, sticker, visible, scraper]:
		main.ordinary_shop_service.offers.append(offer)
	main._refresh_ordinary_shop_panel()
	await create_timer(1.2).timeout
	var dark_tile := _tile(1) as ShopOfferView
	var dark := dark_tile._visual.get_child(0) as ShopCardView
	var timer := dark._carousel_timer
	check(dark._carousel_index > 0, "暗单轮播已经离开初始形态")
	main.run_reward_state.gold = 0
	var before_rng: int = main.ordinary_shop_service.rng.state
	var previous_frame := dark._carousel_index
	await click(dark_tile.get_global_rect().get_center())
	check(_tile(1) == dark_tile and dark._carousel_timer == timer and dark._carousel_index >= previous_frame, "金币不足点击暗卡不会重建节点或重置轮播")
	check(main.run_reward_state.gold == 0 and main.ordinary_shop_service.rng.state == before_rng and not hidden.get("sold", false), "失败购买不扣款或推进商品随机流")
	main.run_reward_state.gold = 200
	main._refresh_ordinary_shop_panel()
	var gold_before: int = main.run_reward_state.gold
	await click(_tile(4).get_global_rect().get_center())
	check(_tile(1) == dark_tile and dark._carousel_timer == timer and dark._carousel_index >= previous_frame, "购买刮刀后暗单继续使用原轮播节点")
	check(main.run_reward_state.gold == gold_before - int(scraper.price), "服务购买正确结算")
	# 明暗单均从商店图片实际位置放大，关闭时仍保留表面用于回退。
	for index: int in [1, 3]:
		var source := main._shop_offer_art(index) as Control
		await click(_tile(index).get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
		check(is_instance_valid(main._inspection_surface) and main._inspection_surface.scale.x < 4.0 and not source.visible, "单卡检视从商品原尺寸开始放大")
		if index == 1:
			check(main._inspection_card_view._carousel_index == dark._carousel_index and main._inspection_card_view.card_data.rarity == dark.card_data.rarity, "暗单放大沿用当前公开轮播形态")
		await create_timer(0.3).timeout
		check(main._inspection_surface.scale.is_equal_approx(Vector2(4, 4)), "单卡检视到达基础4倍")
		await key(KEY_ESCAPE)
		check(is_instance_valid(main._inspection_overlay) and main._inspection_closing, "取消单卡检视进入回退动画")
		await create_timer(0.25).timeout
		check(not is_instance_valid(main._inspection_overlay) and source.visible, "单卡回退后恢复原商品")
	for index: int in [0, 2]:
		var source := main._shop_offer_art(index) as Control
		await click(_tile(index).get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
		check(is_instance_valid(main._inspection_surface) and main._inspection_surface.scale.x < 4.0 and not source.visible, "包装检视从商品原尺寸开始放大")
		await create_timer(0.3).timeout
		check(main._inspection_surface.scale.is_equal_approx(Vector2(4, 4)), "包装检视到达基础4倍")
		await key(KEY_ESCAPE)
		check(is_instance_valid(main._inspection_overlay) and main._inspection_closing, "包装取消检视有回退而非立即消失")
		await create_timer(0.25).timeout
		check(not is_instance_valid(main._inspection_overlay) and source.visible, "包装回退结束恢复陈列图片")
	# 卡包存档失败时必须保留库存，不启动动画。
	main.run_save_path = "/private/tmp/project-card-shop-missing-directory/state.json"
	gold_before = main.run_reward_state.gold
	before_rng = main.ordinary_shop_service.rng.state
	main._on_ordinary_shop_offer_pressed(0)
	check(not is_instance_valid(main._inspection_overlay) and not pack.get("sold", false) and main.run_reward_state.gold == gold_before and main.ordinary_shop_service.rng.state == before_rng, "存档失败交易回滚，不误播放开包")
	main.run_save_path = "/private/tmp/project-card-shop-animation-state.json"
	for index: int in [0, 2]:
		var offer: Dictionary = main.ordinary_shop_service.offers[index]
		gold_before = main.run_reward_state.gold
		var old_origin := dark_tile._visual.get_global_transform_with_canvas().origin
		var card_count: int = main.owned_card_collection.get_cards().size()
		var sticker_count: int = main.emblem_library.get_inventory_state().size()
		await click(_tile(index).get_global_rect().get_center())
		check(main._shop_pack_opening and main._inspection_surface.scale.x < 4.0, "成功购买从点击的包装位置放大进入开包")
		check(main.run_reward_state.gold == gold_before - int(offer.price) and offer.get("sold", false), "动画开始前已完成单次扣款并标记售出")
		check(_tile(1) == dark_tile and dark._carousel_timer == timer, "成功买包后未购买暗卡仍保留原节点和计时器")
		if index == 0:
			check(dark_tile._reflow_offset > 1.0 and absf(dark_tile._visual.get_global_transform_with_canvas().origin.x - old_origin.x) < 30.0, "售出商品后通过位置补偿平滑补位")
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(main.run_save_path))
		check(not saved.is_empty(), "动画开始时交易已经写入真实存档")
		main._on_ordinary_shop_offer_pressed(index)
		await key(KEY_ESCAPE)
		check(main._shop_pack_opening and is_instance_valid(main._inspection_overlay), "开包期间重复购买与关闭不会中断或二次结算")
		await create_timer(0.43).timeout
		var material: ShaderMaterial = main._inspection_surface.material
		check(material.shader.resource_path == "res://shaders/card_death_dissolve.gdshader" and float(material.get_shader_parameter("dissolve_progress")) > 0.0, "放大后复用战斗死亡噪声溶解材质")
		await capture("opening-" + str(index))
		await create_timer(0.65).timeout
		check(not is_instance_valid(main._inspection_overlay) and not main._shop_pack_opening and main.ordinary_shop_open, "包装溶解结束自动回到商店")
		check(main.run_reward_state.gold == gold_before - int(offer.price), "开包结束没有额外扣款")
		check(main.owned_card_collection.get_cards().size() == card_count + (offer.cards.size() if index == 0 else 0) and main.emblem_library.get_inventory_state().size() == sticker_count + (offer.stickers.size() if index == 2 else 0), "开包奖励只入库一次")
	check(is_zero_approx(dark_tile._reflow_offset), "补位动画结束回到逻辑位置")
	main._close_card_inspection(true)
	main._toggle_ordinary_shop()
	await create_timer(0.3).timeout
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("D2-7 shop animation failures: ", failures)
	quit(1 if failures else 0)
