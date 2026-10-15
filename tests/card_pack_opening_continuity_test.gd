extends "res://tests/card_pack_opening_test.gd"

## 使用真实混合卡包，逐帧检查暗幕与后层身份图标在轮换时保持一致。
func _run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("开包连续性验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = false
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if OS.get_cmdline_user_args().has("2k") else DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(0.7).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-opening-continuity-state.json"
	main.run_reward_state.gold = 1000
	main.scraper_count = 2
	main.emblem_library.set_scraper_count(2)
	await click(main.ordinary_shop_entry_button.get_global_rect().get_center())
	await create_timer(0.45).timeout
	var offer_index := _find_mixed_pack()
	check(offer_index >= 0, "真实抽取提供后层同时有法术和装备的混合卡包")
	if offer_index < 0: quit(1); return
	await create_timer(0.2).timeout
	# 商店进入动画会调整桌面视角；归位基准应取购买前的商店画布，而非进入商店前。
	var original_library_parent: Node = main.emblem_library.get_parent()
	var original_library_transform: Transform2D = main.emblem_library.get_global_transform_with_canvas()
	await click(_tile(offer_index).get_global_rect().get_center())
	await create_timer(0.35).timeout
	await click(Vector2(640, 340), MOUSE_BUTTON_RIGHT)
	var sequence = main._card_pack_opening
	sequence.card_requested.connect(func(_owned: OwnedCard):
		var stack_ready := true
		for back_index: int in sequence._background_cards.size():
			var back: InspectionCardSurface = sequence._background_cards[back_index]
			stack_ready = stack_ready and back.position.is_equal_approx(sequence.surface.position - sequence._stack_force * Vector2(sequence.effects.stack_parallax_x, sequence.effects.stack_parallax_y) * (back_index + 1)) and back.scale == sequence.surface.scale
		check(stack_ready, "第%d张揭晓回调已完成后层定位和缩放，不等待下一帧" % (sequence.current_index + 1))
		if OS.get_cmdline_user_args().has("frames"):
			await capture("pack-immediate-%d" % sequence.current_index)
	)
	var expected: Array[OwnedCard] = sequence.cards.duplicate()
	var expected_icons: Array[PackedByteArray] = []
	var expected_icon_rects: Array[Rect2] = []
	for owned: OwnedCard in expected:
		var view := CARD.instantiate() as CardView
		view.set_card_data(owned.card_data)
		view.set_owned_card(owned)
		root.add_child(view)
		expected_icons.append(view.action_icon.texture.get_image().get_data())
		expected_icon_rects.append(view.action_icon.get_rect())
		view.queue_free()
	await create_timer(1.7).timeout
	await capture("pack-continuity-stack")
	for index: int in expected.size():
		var is_minion: bool = expected[index].card_data.card_type == CardData.CardType.MINION
		check(main.emblem_library.get_parent() == main._inspection_overlay, "第%d张保留左侧真实工具箱" % (index + 1))
		check(main.emblem_library._drag_enabled == is_minion and main.emblem_library._scraper.enabled == is_minion, "第%d张按当前卡大类启用或禁用工具" % (index + 1))
		if not is_minion:
			await click(main._inspection_library_toggle.get_global_rect().get_center())
			await create_timer(0.3).timeout
			await click(main.emblem_library._scraper.get_global_rect().get_center())
			check(not main._rune_scraper_mode and main.scraper_count == 2, "非随从卡展开工具箱后刮刀仍禁用且不扣库存")
			await capture("pack-disabled-toolbox")
			await click(main._inspection_library_toggle.get_global_rect().get_center())
			await create_timer(0.3).timeout
		check(main._inspection_owned_card == expected[index], "第%d张轮换保持原实例" % (index + 1))
		check(main._inspection_card_view.action_icon.texture.get_image().get_data() == expected_icons[index], "第%d张前层身份图标正确" % (index + 1))
		check(main._inspection_card_view.action_icon.get_rect() == expected_icon_rects[index], "第%d张前层身份图标位置和尺寸正确" % (index + 1))
		for back_index: int in sequence._background_cards.size():
			var back: CardView = sequence._background_cards[back_index].card
			check(back.action_icon.texture.get_image().get_data() == expected_icons[index + back_index + 1], "第%d张后层身份图标与前层一致" % (index + back_index + 2))
			if back.action_icon.get_rect() != expected_icon_rects[index + back_index + 1]:
				print("图标布局差异：", back.card_data.id, " 后层 ", back.action_icon.get_rect(), " 前层 ", expected_icon_rects[index + back_index + 1])
			check(back.action_icon.get_rect() == expected_icon_rects[index + back_index + 1], "第%d张后层身份图标位置和尺寸与前层一致" % (index + back_index + 2))
		var library_transform: Transform2D = main.emblem_library.get_global_transform_with_canvas()
		var prepared_next: InspectionCardSurface = sequence._background_cards[0] if not sequence._background_cards.is_empty() else null
		var prepared_texture: Texture2D = prepared_next.texture if prepared_next != null else null
		await click(_pointer_for_card_point(main._inspection_surface, Vector2(48, 65)))
		var minimum_dim := 1.0
		var library_stayed := true
		var sampled_index := index
		var sampled_frames := 0
		var deadline := Time.get_ticks_msec() + 1100
		while Time.get_ticks_msec() < deadline:
			await process_frame
			if OS.get_cmdline_user_args().has("frames") and is_instance_valid(main._card_pack_opening):
				if sequence.current_index != sampled_index:
					sampled_index = sequence.current_index
					sampled_frames = 0
				if sampled_index > index and sampled_frames < 6:
					await capture("pack-transition-%d-%d" % [sampled_index, sampled_frames])
					if is_instance_valid(main._inspection_surface):
						print("换卡帧 ", sampled_index, "/", sampled_frames, " 前层 ", main._inspection_surface.get_rect(), " 后层 ", sequence._background_cards[0].get_rect() if is_instance_valid(sequence) and not sequence._background_cards.is_empty() else Rect2())
					sampled_frames += 1
			if is_instance_valid(main._inspection_dim):
				minimum_dim = minf(minimum_dim, main._inspection_dim.modulate.a)
			if index + 1 < expected.size():
				library_stayed = library_stayed and main.emblem_library.get_global_transform_with_canvas().is_equal_approx(library_transform)
		if index + 1 < expected.size():
			print("轮换暗幕最小透明度：", minimum_dim)
			check(minimum_dim >= 0.999, "第%d张到第%d张切换期间暗幕不重新淡入" % [index + 1, index + 2])
			check(library_stayed, "第%d张到第%d张工具箱位置和倍率逐帧不变" % [index + 1, index + 2])
			check(main._inspection_surface == prepared_next and main._inspection_surface.texture == prepared_texture, "下一张直接提升已绘好的后层画布，不重建纹理")
	check(not is_instance_valid(main._inspection_overlay) and main.ordinary_shop_open, "最后一张结束后才退出检视返回商店")
	check(main.emblem_library.get_parent() == original_library_parent and main.emblem_library.get_global_transform_with_canvas().is_equal_approx(original_library_transform), "整包结束后工具箱统一恢复原父节点、位置和倍率")
	main._toggle_ordinary_shop()
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Card pack continuity failures: ", failures)
	quit(1 if failures else 0)


func _find_mixed_pack() -> int:
	var registry: Dictionary = main._build_card_definition_registry()
	for seed_value: int in range(1, 600):
		main.ordinary_shop_service.initialize(seed_value)
		main.ordinary_shop_service.refresh(main._get_shop_card_definitions(), main.owned_card_collection.get_cards(), main._get_shop_sticker_definitions(), main._get_all_held_stickers())
		for index: int in main.ordinary_shop_service.offers.size():
			var offer: Dictionary = main.ordinary_shop_service.offers[index]
			if offer.kind != "card_pack" or offer.size != "large": continue
			var has_spell := false
			var has_equipment := false
			for card_index: int in range(1, offer.cards.size()):
				var type: int = registry[StringName(offer.cards[card_index])].card_type
				has_spell = has_spell or type == CardData.CardType.SPELL
				has_equipment = has_equipment or type == CardData.CardType.EQUIPMENT
			if has_spell and has_equipment:
				print("连续性验收真实卡包：", offer.cards)
				main._refresh_ordinary_shop_panel()
				return index
	return -1
