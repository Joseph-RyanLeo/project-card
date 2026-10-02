extends "res://tests/d2_7_shop_presentation_test.gd"



func _run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("商店视觉验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if OS.get_cmdline_user_args().has("2k") else DisplayScript.DisplayMode.WINDOW_1080P)
	await create_timer(0.7).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-shop-polish-state.json"
	main.run_reward_state.gold = 1000
	var chosen := false
	for seed_value: int in range(1, 300):
		main.ordinary_shop_service.rng.seed = seed_value
		main._generate_ordinary_shop(false)
		var small := 0
		for offer: Dictionary in main.ordinary_shop_service.offers:
			if offer.kind == "card_pack" and offer.size == "small": small += 1
		if small >= 3:
			chosen = true
			break
	check(chosen, "正式生成三张同型小卡包，覆盖中间包遮挡右包的场景")
	main._toggle_ordinary_shop()
	check(main._shop_motion_root.position.y < -300, "整店从上方开始进入")
	await create_timer(main.SHOP_OPEN_DURATION + 0.01).timeout
	check(main._shop_motion_root.position.y > 0, "下落越过目标位置后开始回弹")
	await create_timer(main.SHOP_REBOUND_DURATION + 0.1).timeout
	check(is_zero_approx(main._shop_motion_root.position.y) and is_equal_approx(main._shop_motion_root.modulate.a, 1), "整店回弹归位且全程不淡出")
	var style := main.ordinary_shop_panel.get_theme_stylebox("panel") as StyleBoxFlat
	check(style.border_width_left == 0 and style.border_width_right == 0 and style.border_width_top == 0 and style.border_width_bottom == 0, "商店不绘制辅助黄色边框")
	var wallet: Control = main.ordinary_shop_offer_list.get_child(0)
	var coin := wallet.find_child("Coin", true, false) as TextureRect
	check(coin != null and coin.size == Vector2(25, 25) and coin.texture.resource_path.ends_with("gold_coin.png"), "商店余额使用25像素独立金币图片")
	check(main.theme == null, "商店金币不会替换全局正文主题")
	var stack := main.ordinary_shop_offer_list.find_child("ShopPackStack_ash_ledger_small", true, false) as ShopPackStackView
	if stack == null or stack._offers.size() < 3:
		quit(1)
		return
	var middle := stack._offers[1]
	var right := stack._offers[2]
	await move(middle.get_global_rect().position + Vector2(6, 70))
	await create_timer(0.18).timeout
	check(stack._hover_offer == middle, "指向中间包露出部分使它置顶")
	var center := middle.get_global_rect().get_center()
	check(right.get_global_rect().has_point(center), "中心点同时位于被遮挡右包的原始矩形内")
	await move(center)
	check(stack._hover_offer == middle, "已抬起的中间包中心不会误选背后的右包")
	await capture("polish-middle-hover")
	var gold_before: int = main.run_reward_state.gold
	var cards_before: int = main.owned_card_collection.get_cards().size()
	var rng_before: int = main.ordinary_shop_service.rng.state
	var toolbox_parent: Node = main.emblem_library.get_parent()
	await click(center, MOUSE_BUTTON_RIGHT)
	await create_timer(0.1).timeout
	check(is_instance_valid(main._inspection_overlay) and main._inspection_overlay.find_child("InspectionPackArt", true, false) != null, "真实右键打开前层卡包的检视图片")
	if is_instance_valid(main._inspection_overlay):
		var name_label := main._inspection_overlay.find_child("InspectionPackName", true, false) as Label
		check(name_label != null and name_label.text == "灰烬证册 · 小卡包", "卡包检视用文字显示正确名称")
		check(main._inspection_overlay.z_index > main.ordinary_shop_layer.z_index and main._inspection_read_only and not main._inspection_has_library_toolbox, "卡包检视位于商店上方且只读")
		await capture("polish-pack-inspect")
	await key(KEY_ESCAPE)
	await create_timer(0.25).timeout
	check(not is_instance_valid(main._inspection_overlay) and main.ordinary_shop_open and main.emblem_library.get_parent() == toolbox_parent, "Esc关闭卡包检视并保留商店与工具盒")
	await move(middle.get_global_rect().position + Vector2(6, 70))
	await move(center)
	await move(right.get_global_rect().position + Vector2(right.size.x - 8, 70))
	check(stack._hover_offer == right, "真实进入右包露出区域才将右包提到最前")
	await click(right.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await process_frame
	await click(Vector2(40, 450))
	await create_timer(0.25).timeout
	check(not is_instance_valid(main._inspection_overlay), "点击暗幕同样能关闭卡包检视")
	var sticker_index := -1
	for index: int in main.ordinary_shop_service.offers.size():
		if main.ordinary_shop_service.offers[index].kind == "sticker_pack": sticker_index = index; break
	check(sticker_index >= 0, "正式商店含纹章包")
	if sticker_index >= 0:
		var sticker := _tile(sticker_index)
		var base := sticker.find_child("PackBase", true, false) as TextureRect
		var seal := sticker.find_child("PackSeal", true, false) as TextureRect
		check(base != null and seal != null and base.texture.resource_path.ends_with("sticker_pack_base.png") and seal.texture.resource_path.ends_with("sticker_pack_seal.png"), "纹章包组合正式底壳与封皮素材")
		await click(sticker.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
		await process_frame
		check(is_instance_valid(main._inspection_overlay) and main._inspection_overlay.find_child("InspectionPackName", true, false).text == "纹章贴纸包", "纹章包右键检视名称与封装素材")
		await capture("polish-sticker-inspect")
		await click(Vector2(600, 350), MOUSE_BUTTON_RIGHT)
		await create_timer(0.25).timeout
		check(not is_instance_valid(main._inspection_overlay), "右键可关闭纹章包检视")
	check(main.run_reward_state.gold == gold_before and main.owned_card_collection.get_cards().size() == cards_before and main.ordinary_shop_service.rng.state == rng_before, "所有检视不扣金币、不获得卡牌、不推进抽取随机数")
	await move(Vector2(40, 650))
	await capture("polish-table")
	main._open_shop_sell_dialog()
	await process_frame
	var sale_buttons: Array[Node] = main._shop_sell_dialog.find_children("*", "Button", true, false)
	var sale_fonts_valid := false
	for button: Button in sale_buttons:
		if button.text.contains("金币"):
			sale_fonts_valid = not button.get_theme_font("font") is FontVariation
			break
	check(sale_fonts_valid, "出售清单使用普通金额文字，不改变窗口字体度量")
	main._confirm_shop_sale(main.owned_card_collection.get_cards()[0].instance_id)
	await process_frame
	var confirmation := main.ordinary_shop_layer.get_child(main.ordinary_shop_layer.get_child_count() - 1) as ConfirmationDialog
	check(confirmation != null and confirmation.dialog_text.contains("金币") and not confirmation.get_label().get_theme_font("font") is FontVariation, "出售确认金额保持普通文字与原窗口字体")
	if confirmation != null: confirmation.queue_free()
	await process_frame
	main._toggle_ordinary_shop()
	main._toggle_ordinary_shop()
	await process_frame
	main._toggle_ordinary_shop()
	await create_timer(main.SHOP_CLOSE_DURATION + 0.1).timeout
	check(is_zero_approx(main._shop_motion_root.position.y) and not main._shop_motion_root.get_node("ShopTableBackdrop").is_visible_in_tree(), "动画中离店可停止动画并清理背景")
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("D2-7 shop polish failures: ", failures)
	quit(1 if failures else 0)
