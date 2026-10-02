extends "res://tests/d2_7_shop_presentation_test.gd"

const ShopPrice = preload("res://scripts/ui/shop_price_view.gd")

func move(point: Vector2) -> void:
	# 表面的连续跟随读取原生鼠标位置，按刮刀原生测试一样同步移动系统指针。
	Input.warp_mouse(shell.render_container.get_global_transform_with_canvas() * point)
	await super.move(point)

func _run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("包装检视验收超时"); quit(1))
	await _check_coin_pixels()
	shell = DISPLAY.instantiate()
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K)
	await create_timer(0.7).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-pack-surface-save.json"
	main.run_reward_state.gold = 1000
	var chosen := false
	for seed_value: int in range(1, 300):
		main.ordinary_shop_service.rng.seed = seed_value
		main._generate_ordinary_shop(false)
		var stickers := 0
		for offer: Dictionary in main.ordinary_shop_service.offers:
			if offer.kind == "sticker_pack": stickers += 1
		if stickers >= 2:
			chosen = true
			break
	check(chosen, "真实商店生成两个贴纸包")
	main._toggle_ordinary_shop()
	await create_timer(main.SHOP_OPEN_DURATION + main.SHOP_REBOUND_DURATION + 0.1).timeout
	var stack := main.ordinary_shop_offer_list.find_child("ShopPackStack_sticker_pack", true, false) as ShopPackStackView
	check(stack != null and stack._offers.size() == 2, "贴纸包叠放但仍保留两个独立商品")
	if stack == null: quit(1); return
	var back := stack._offers[0]
	var front := stack._offers[1]
	var selected := back.get_global_rect().position + Vector2(7, 70)
	await move(selected)
	await create_timer(0.18).timeout
	await move(back.get_global_rect().get_center())
	check(stack._hover_offer == back and back.z_index > front.z_index, "贴纸包露出部位抬起置顶，重叠部位不抢选")
	var rng_before: int = main.ordinary_shop_service.rng.state
	await click(back.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await create_timer(0.3).timeout
	await _check_pack_surface("sticker")
	check(main._inspection_card_view == null and not main._inspection_surface.can_drop_global(main._inspection_surface.get_global_rect().get_center(), {}), "包装表面只读，不接受卡牌贴纸操作")
	await key(KEY_ESCAPE)
	await create_timer(0.25).timeout
	check(not is_instance_valid(main._inspection_overlay), "复用表面后贴纸包仍可Esc关闭")
	var card_stack: ShopPackStackView
	for candidate: ShopPackStackView in main.ordinary_shop_offer_list.find_children("ShopPackStack_*", "Control", true, false):
		if candidate != stack: card_stack = candidate; break
	check(card_stack != null, "正式商店存在卡包堆")
	if card_stack != null:
		await click(card_stack._offers.back().get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
		await create_timer(0.3).timeout
		await _check_pack_surface("cards")
		await click(Vector2(40, 450))
		await create_timer(0.25).timeout
		check(not is_instance_valid(main._inspection_overlay), "复用表面后卡包仍可暗幕关闭")
	check(main.ordinary_shop_service.rng.state == rng_before, "检视扫光倾斜不会改变商品随机数")
	var gold_before: int = main.run_reward_state.gold
	var count_before: int = main.emblem_library.get_inventory_state().size()
	var index := int(back.get_meta("shop_offer_index"))
	var other_index := int(front.get_meta("shop_offer_index"))
	await click(selected)
	await process_frame
	check(main.run_reward_state.gold == gold_before - 15 and main.emblem_library.get_inventory_state().size() == count_before + 5 and main.ordinary_shop_service.offers[index].get("sold", false) and not main.ordinary_shop_service.offers[other_index].get("sold", false), "购买露出的贴纸包只扣15金币并入库5枚，未购买邻包")
	stack = main.ordinary_shop_offer_list.find_child("ShopPackStack_sticker_pack", true, false)
	check(stack != null and stack._offers.size() == 1, "购买后剩余贴纸包正确重新叠放")
	check(main.battle_log_text.get_theme_font("normal_font") == main.BATTLE_LOG_FONT and main.battle_result_summary_label.get_theme_font("normal_font") == main.BATTLE_LOG_FONT, "战斗正文继续使用原字体而不引入金币图片度量")
	await create_timer(1.1).timeout # 等待已提交交易的开包动画结束
	main._toggle_ordinary_shop()
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("D2-7 pack surface failures: ", failures)
	quit(1 if failures else 0)

func _check_pack_surface(tag: String) -> void:
	var surface := main._inspection_surface as InspectionCardSurface
	check(surface != null and surface.scale == Vector2(4, 4), tag + "包装检视使用基础4倍缩放")
	check(surface != null and surface.viewport != null and surface.effect.shader.resource_path == "res://shaders/card_preview_3d.gdshader", tag + "包装复用卡牌原始检视着色器")
	if surface == null: return
	await move(surface.get_global_transform_with_canvas() * (surface.size * Vector2(0.8, 0.65)))
	await create_timer(0.35).timeout
	var hovered: Vector2 = surface.effect.get_shader_parameter("pointer_force")
	check(hovered.x > 0.35 and hovered.y > 0.1 and surface.effect.get_shader_parameter("use_3d") and surface.effect.get_shader_parameter("use_flash"), tag + "真实鼠标驱动倾斜与光栅")
	await RenderingServer.frame_post_draw
	var with_flash: Image = main.get_viewport().get_texture().get_image()
	surface.effect.set_shader_parameter("use_flash", false)
	await RenderingServer.frame_post_draw
	var without_flash: Image = main.get_viewport().get_texture().get_image()
	check(with_flash.get_data() != without_flash.get_data(), tag + "实际渲染可见扫光变化")
	surface.effect.set_shader_parameter("use_flash", true)
	await capture("surface-" + tag + "-hover")
	await move(Vector2(40, 450))
	await create_timer(0.5).timeout
	check(surface.force.length() < 0.015, tag + "离开检视包装后倾斜平滑归位")

func _check_coin_pixels() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(240, 100)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var source := Image.load_from_file(ProjectSettings.globalize_path("res://assets/ui/currency/gold_coin.png"))
	var used := source.get_used_rect()
	for font_size: int in [8, 10, 16, 25, 32]:
		var label := ShopPrice.new()
		label.position = Vector2(20, 20)
		label.configure([])
		label.add_theme_font_size_override("font_size", font_size)
		viewport.add_child(label)
		await process_frame
		await RenderingServer.frame_post_draw
		var output := viewport.get_texture().get_image()
		var bounds := output.get_used_rect()
		var same := bounds.size == used.size
		if same:
			for y: int in used.size.y:
				for x: int in used.size.x:
					var expected := source.get_pixelv(used.position + Vector2i(x, y))
					var actual := output.get_pixelv(bounds.position + Vector2i(x, y))
					if expected.a > 0.5 and (absf(expected.r - actual.r) > 0.012 or absf(expected.g - actual.g) > 0.012 or absf(expected.b - actual.b) > 0.012): same = false
		check(same, "独立金币节点在字号%d时与原图像素尺寸、颜色一致" % font_size)
		label.queue_free()
		await process_frame
	viewport.queue_free()
	await process_frame
