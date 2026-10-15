extends "res://tests/card_pack_opening_test.gd"

## 正式商店、实际包装素材与原生输入：完整1倍包装和固定4倍抽卡。
func _run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("包装原生尺寸验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = false
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K)
	await create_timer(0.7).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-pack-native-size-state.json"
	main.run_reward_state.gold = 1000
	await click(main.ordinary_shop_entry_button.get_global_rect().get_center())
	await create_timer(0.45).timeout
	for pack_size: String in ["small", "large"]:
		var index := _find_generated_pack(pack_size, false)
		check(index >= 0, pack_size + "真实商店生成包装")
		if index < 0: quit(1); return
		await create_timer(0.3).timeout
		await capture("native-" + pack_size + "-shop")
		await _check_native_pack(index, pack_size)
		await click(_tile(index).get_global_rect().get_center())
		await create_timer(0.35).timeout
		var sequence: CardPackOpening = main._card_pack_opening
		var pack: InspectionCardSurface = main._inspection_surface
		var mouth_center := pack.position + (pack.PADDING + Vector2(sequence.tear_art.size.x * 0.5, sequence.TearArt.SEAL_HEIGHT * 0.5)) * pack.scale
		check(mouth_center.is_equal_approx(main.size * 0.5) and main._inspection_overlay.get_node_or_null("InspectionPackPurchase") == null, pack_size + "商店单击直接购买并放大到撕口居中位置，跳过购买按钮")
		await capture("native-" + pack_size + "-ready")
		var hover := _pointer_for_card_point(pack, Vector2(20, 7))
		root.warp_mouse(shell.render_container.get_global_transform_with_canvas() * hover)
		await move(hover)
		await create_timer(0.25).timeout
		await click(hover, MOUSE_BUTTON_RIGHT)
		await create_timer(0.08).timeout
		check(sequence.phase == CardPackOpening.Phase.TEARING and not pack.tilt_locked and pack.force.length() > 0.2, pack_size + "右键自动撕包也保持原生鼠标倾斜")
		while sequence.phase != CardPackOpening.Phase.BURST: await process_frame
		var start_y := sequence.surface.position.y
		var pack_y := pack.position.y
		var card_body := Rect2(sequence.surface.position + sequence.surface.PADDING * 4, sequence.surface.card.card_size * 4)
		var pack_body := Rect2(pack.position + pack.PADDING * 4, sequence.tear_art.size * 4)
		check(pack_body.encloses(card_body), pack_size + "抽出起点的4倍裸卡完整位于4倍包装内")
		var scales_fixed := true
		while sequence.phase == CardPackOpening.Phase.BURST:
			scales_fixed = scales_fixed and sequence.surface.scale.is_equal_approx(Vector2(4, 4))
			for back: InspectionCardSurface in sequence._background_cards:
				scales_fixed = scales_fixed and back.scale.is_equal_approx(Vector2(4, 4))
			if is_instance_valid(sequence._pack_surface) and pack.position.y > pack_y + 50:
				await capture("native-" + pack_size + "-extract")
				pack_y = INF
			await process_frame
		check(scales_fixed, pack_size + "整段抽出前后层始终4倍，没有缩小再放大")
		check(sequence.surface.position.y < start_y - 20, pack_size + "抽出靠卡叠向上移动完成")
		while sequence.phase == CardPackOpening.Phase.REVEALING: await process_frame
		await _finish_cards(sequence)
		check(shell.display_mode_option.is_visible_in_tree(), pack_size + "整包结束恢复窗口倍率菜单")
	# 行动定向包同样用原生小包画布，原图标依然3倍。
	main._select_action_procurement(0)
	await create_timer(0.3).timeout
	var action_index := -1
	for index: int in main.ordinary_shop_service.offers.size():
		var offer: Dictionary = main.ordinary_shop_service.offers[index]
		if offer.get("kind") == "card_pack" and int(offer.get("procurement_action", -1)) == 0:
			action_index = index
			break
	check(action_index >= 0, "实际采购页提供定向小包")
	if action_index >= 0:
		var art: Control = main._shop_offer_art(action_index)
		check(art.size == Vector2(115, 174) and art.scale == Vector2.ONE, "定向小包也按完整115×174原生画布陈列")
		await click(_tile(action_index).get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
		await create_timer(0.35).timeout
		check(main._inspection_surface.scale == Vector2(4, 4) and main._card_pack_opening.tear_art.size == art.size, "定向包检视4倍且沿用原生尺寸")
		await key(KEY_ESCAPE)
		await create_timer(0.25).timeout
		check(shell.display_mode_option.is_visible_in_tree(), "定向包退出检视恢复窗口倍率菜单")
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Native pack size failures: ", failures)
	quit(1 if failures else 0)


func _check_native_pack(index: int, tag: String) -> void:
	var source := main._shop_offer_art(index) as TextureRect
	var expected := Vector2(115, 174) if tag == "small" else Vector2(125, 188)
	check(source.size == expected and source.size == source.texture.get_size() and source.scale == Vector2.ONE, tag + "商品1倍画布保留原图尺寸")
	var tile := _tile(index) as ShopOfferView
	check(Rect2(Vector2.ZERO, tile._visual.size).encloses(Rect2(source.position, source.size)), tag + "商品画布包住完整包装")
	var stack := tile.get_parent() as ShopPackStackView
	check(stack._description.position.y >= source.position.y + source.size.y, tag + "价格位于包装底部之外")
	await click(tile.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await create_timer(0.35).timeout
	var surface: InspectionCardSurface = main._inspection_surface
	var sequence: CardPackOpening = main._card_pack_opening
	check(not shell.display_mode_option.is_visible_in_tree(), tag + "卡包检视暂时收起窗口倍率菜单，避免挡住右侧封口")
	check(surface.scale == Vector2(4, 4) and sequence.tear_art.size == expected, tag + "检视直接对完整原图放大4倍")
	check(Vector2(sequence.tear_art.source_viewport.size) == expected, tag + "撕包离屏画布覆盖全部原图")
	await RenderingServer.frame_post_draw
	var original := source.texture.get_image()
	original.convert(Image.FORMAT_RGBA8)
	var rendered := sequence.tear_art.source_viewport.get_texture().get_image()
	rendered.convert(Image.FORMAT_RGBA8)
	check(original.get_data() == rendered.get_data(), tag + "实际1倍离屏像素与完整原图相同，没有内部缩放或裁切")
	await capture("native-" + tag + "-preview")
	await key(KEY_ESCAPE)
	await create_timer(0.25).timeout
	check(source.visible and source.scale == Vector2.ONE, tag + "取消检视后回到完整1倍商品")
	check(shell.display_mode_option.is_visible_in_tree(), tag + "取消检视恢复窗口倍率菜单")
