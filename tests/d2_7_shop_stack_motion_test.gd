extends "res://tests/d2_7_shop_presentation_test.gd"


func move(point: Vector2) -> void:
	# 原生悬停需要同步系统指针，避免等待动画时真实鼠标覆盖模拟位置。
	Input.warp_mouse(shell.render_container.get_global_transform_with_canvas() * point)
	await super.move(point)


func _run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("卡包堆叠验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	root.add_child(shell)
	var is_2k := OS.get_cmdline_user_args().has("2k")
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if is_2k else DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(0.7).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-stack-motion-state.json"
	main.run_reward_state.gold = 1000
	var chosen := false
	for seed_value: int in range(1, 300):
		main.ordinary_shop_service.rng.seed = seed_value
		main._generate_ordinary_shop(false)
		var small := 0
		var large := 0
		for offer: Dictionary in main.ordinary_shop_service.offers:
			if offer.kind == "card_pack":
				if offer.size == "small": small += 1
				else: large += 1
		if small == 2 and large == 2:
			chosen = true
			break
	check(chosen, "正式生成的商店包含两小包与两大包")
	await click(main.ordinary_shop_entry_button.get_global_rect().get_center())
	await move(Vector2(40, 650))
	await create_timer(0.25).timeout
	var stacks: Array[Node] = main.ordinary_shop_offer_list.find_children("ShopPackStack_ash_ledger*", "Control", true, false)
	check(stacks.size() == 2, "小包与大包分别归入两堆")
	var small_stack: ShopPackStackView
	var large_stack: ShopPackStackView
	for stack: ShopPackStackView in stacks:
		if "small" in stack.name: small_stack = stack
		else: large_stack = stack
	check(small_stack._offers.size() == 2 and large_stack._offers.size() == 2, "每堆保留两件独立商品而非合并购买")
	var all_still := true
	for tile: ShopOfferView in main.ordinary_shop_offer_list.find_children("ShopOffer_*", "Control", true, false):
		all_still = all_still and not tile.is_processing() and is_zero_approx(tile._visual.rotation)
	check(all_still, "开店后所有未悬停商品静止，包括卡包、单卡与刮刀")
	await capture("stack-normal-2k" if is_2k else "stack-normal-720p")
	var back := small_stack._offers[0]
	var front := small_stack._offers[1]
	var point := back.get_global_rect().position + Vector2(6, 65)
	await move(point)
	await create_timer(0.2).timeout
	check(small_stack._hover_offer == back and back.z_index > front.z_index and back._visual.position.y < -4, "指向后层露出的包使其抬起并置顶")
	for step: int in 10:
		await move(point + Vector2(step % 2, 0))
	check(small_stack._hover_offer == back, "提层后的固定选择区不会反复切换卡包")
	var only_target_moves := true
	for tile: ShopOfferView in main.ordinary_shop_offer_list.find_children("ShopOffer_*", "Control", true, false):
		only_target_moves = only_target_moves and (tile.is_processing() == (tile == back))
	check(only_target_moves, "只有目标包晃动，其他商品保持静止")
	await capture("stack-hover-2k" if is_2k else "stack-hover-720p")
	await move(Vector2(40, 650))
	await create_timer(0.2).timeout
	check(small_stack._hover_offer == null and back.z_index == 0 and front.z_index == 1 and back._visual.position.is_equal_approx(Vector2.ZERO) and is_zero_approx(back._visual.rotation), "移开后恢复原层级和位置")
	var index := int(back.get_meta("shop_offer_index"))
	var sibling_index := int(front.get_meta("shop_offer_index"))
	var count_before: int = main.owned_card_collection.get_cards().size()
	var gold_before: int = main.run_reward_state.gold
	await click(point)
	await process_frame
	check(main.owned_card_collection.get_cards().size() == count_before + 3 and main.run_reward_state.gold == gold_before - 12 and main.ordinary_shop_service.offers[index].get("sold", false) and not main.ordinary_shop_service.offers[sibling_index].get("sold", false), "露出区域点击只购买目标小包，精确扣12金币并发3张卡")
	small_stack = main.ordinary_shop_offer_list.find_child("ShopPackStack_ash_ledger_small", true, false) as ShopPackStackView
	check(small_stack._offers.size() == 1, "购买后剩余卡包重新叠放并保留报价")
	await _check_crossfade_opacity()
	await create_timer(1.1).timeout # 等待已提交的卡包开包动画完成
	main._toggle_ordinary_shop()
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("D2-7 shop stack motion failures: ", failures)
	quit(1 if failures else 0)


func _check_crossfade_opacity() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(120, 158)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var source := CardData.new()
	var view := SHOP_CARD.instantiate() as ShopCardView
	view.configure_hidden(ShopCard.public_definition(source, {}), {})
	view.position = Vector2(10, 10)
	viewport.add_child(view)
	view._carousel_timer.stop()
	await RenderingServer.frame_post_draw
	var before := viewport.get_texture().get_image().get_pixel(60, 130)
	view._advance_carousel()
	await create_timer(ShopCard.CAROUSEL_FADE * 0.5).timeout
	await RenderingServer.frame_post_draw
	var middle := viewport.get_texture().get_image().get_pixel(60, 130)
	var amount: float = (view.card_frame.material as ShaderMaterial).get_shader_parameter("blend_amount")
	check(amount > 0 and amount < 1 and middle.a > 0.99 and before.a > 0.99, "真实渐变中间帧卡框仍完全不透明")
	viewport.get_texture().get_image().save_png("/private/tmp/project-card-shop-crossfade-middle.png")
	await create_timer(ShopCard.CAROUSEL_FADE).timeout
	await RenderingServer.frame_post_draw
	var after := viewport.get_texture().get_image().get_pixel(60, 130)
	check(before != after and after.a > 0.99 and view.card_frame.material == null, "渐变完成后显示新品级且清理过渡材质")
	viewport.queue_free()
	await process_frame
