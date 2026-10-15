extends "res://tests/d2_7_shop_presentation_test.gd"

## 真实商品、真实购买事务与原生输入，覆盖撕包、稀有光束、顺序及新卡刮符文。
func _run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("开包验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	# 独立商店实验入口不要求先走迷宫天赋与路径选择；交易与全部UI仍使用正式场景。
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = OS.get_cmdline_user_args().has("maze")
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if OS.get_cmdline_user_args().has("2k") else DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(0.7).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-opening-test-state.json"
	if main.maze_controller != null:
		var maze: ShortMazeController = main.maze_controller
		maze.new_run(1205)
		maze.choose_talent("sentry_guard")
		maze.select_path(maze.run.paths[0].path_id)
		maze.complete_event(false)
		maze.select_path(maze.run.paths[0].path_id)
		maze.complete_event(false)
		maze.select_path(maze.run.paths[0].path_id)
	main.run_reward_state.gold = 1000
	if not main.ordinary_shop_open:
		await click(main.ordinary_shop_entry_button.get_global_rect().get_center())
	await create_timer(0.45).timeout
	check(main.ordinary_shop_open, "真实输入打开商店")
	var small_index := _find_generated_pack("small", false)
	check(small_index >= 0, "真实商品生成可刮符文的普通三张小包")
	if small_index < 0: quit(1); return
	var offer: Dictionary = main.ordinary_shop_service.offers[small_index]
	var before_count: int = main.owned_card_collection.get_cards().size()
	var before_gold: int = main.run_reward_state.gold
	await create_timer(0.2).timeout
	await click(_tile(small_index).get_global_rect().get_center())
	await create_timer(0.35).timeout
	var sequence: CardPackOpening = main._card_pack_opening
	check(sequence != null and sequence.phase == CardPackOpening.Phase.SEALED and sequence.cards.size() == 3 and not sequence.has_rare, "购买后停在正面包装等待撕开，不自动跳过")
	if sequence == null: quit(1); return
	check(main.run_reward_state.gold == before_gold - int(offer.price) and main.owned_card_collection.get_cards().size() == before_count + 3 and not FileAccess.get_file_as_string(main.run_save_path).is_empty(), "撕开前扣款与三张真实实例已经一致保存")
	var rng_after_purchase: int = main.ordinary_shop_service.rng.state
	await key(KEY_ESCAPE)
	main._on_ordinary_shop_offer_pressed(small_index)
	check(main._card_pack_opening == sequence and main.run_reward_state.gold == before_gold - int(offer.price), "等待撕包期间Esc与重复购买不关闭或重复扣款")
	var surface: InspectionCardSurface = main._inspection_surface
	surface.tilt_locked = true
	surface.force = Vector2.ZERO
	var start := _pointer_for_card_point(surface, Vector2(9, 7))
	await _button(start, true)
	await _held_motion(_pointer_for_card_point(surface, Vector2(40, 7)))
	await _button(_pointer_for_card_point(surface, Vector2(40, 7)), false)
	check(sequence.phase == CardPackOpening.Phase.TEARING and sequence.tear_art.progress > 0.2 and sequence.tear_art.progress < 1.0, "横向拖动推进裂口，松手保留未完成进度")
	await _button(_pointer_for_card_point(surface, Vector2(40, 7)), true)
	await _held_motion(_pointer_for_card_point(surface, Vector2(sequence.tear_art.size.x - 1, 7)))
	await _button(_pointer_for_card_point(surface, Vector2(sequence.tear_art.size.x - 1, 7)), false)
	check(sequence.phase == CardPackOpening.Phase.BURST and sequence.glow.strength > 0.0, "拖过封口后播放普通金光与退壳")
	await create_timer(1.4).timeout
	check(sequence.phase == CardPackOpening.Phase.INSPECTING and main._inspection_owned_card == sequence.cards[0] and sequence._background_cards.size() == 2, "原抽取第一张可检视，后两张露出真实卡边")
	check(sequence._background_cards[0].card.get_owned_card() == sequence.cards[1] and sequence._background_cards[1].card.get_owned_card() == sequence.cards[2], "卡叠按抽取顺序绑定对应实际实例")
	main.scraper_count = 2
	main.emblem_library.set_scraper_count(2)
	await click(main._inspection_library_toggle.get_global_rect().get_center())
	await create_timer(0.3).timeout
	check(main.emblem_library.get_parent() == main._inspection_overlay and main._inspection_library_expanded, "开包新卡检视复用真实左侧工具包")
	await capture("pack-toolbox")
	var owned: OwnedCard = main._inspection_owned_card
	var scraper: TextureRect = main.emblem_library._scraper
	await click(scraper.get_global_rect().get_center())
	await process_frame
	check(main._rune_scraper_mode, "点击工具包刮刀进入当前新卡的刮符文模式")
	var rune_origin: Vector2 = main._inspection_card_view.rune_area_position
	surface = main._inspection_surface
	surface.force = Vector2.ZERO
	var blade_offset: Vector2 = main._rune_scraper_drag_data.get("hit_rect_offset", Vector2.ZERO) / surface.get_global_transform_with_canvas().get_scale()
	var blade_size: Vector2 = main._rune_scraper_drag_data.get("hit_rect_size", Vector2.ZERO) / surface.get_global_transform_with_canvas().get_scale()
	var scrape_pointer := _pointer_for_card_point(surface, rune_origin + Vector2(4, 4)) - surface.get_global_transform_with_canvas().basis_xform(blade_offset + blade_size * 0.5)
	await _button(scrape_pointer, true)
	await _button(scrape_pointer, false)
	check(owned.get_rune_scraped_pixel_count(0) > 0 and main.scraper_count == 1 and sequence.current_index == 0, "刮当前新卡消耗一把刀且不会收起卡牌")
	await click(scrape_pointer, MOUSE_BUTTON_RIGHT)
	await create_timer(0.3).timeout
	check(not main._rune_scraper_mode and owned.rune_revealed[0] and main._card_pack_opening == sequence, "右键退出工具模式，已付费符文完整揭晓并留在本张卡")
	await click(_pointer_for_card_point(main._inspection_surface, Vector2(48, 65)))
	await create_timer(0.35).timeout
	check(sequence.current_index == 0 and main._inspection_owned_card == owned, "工具箱展开时点击卡面不会切换下一张")
	await click(main._inspection_library_toggle.get_global_rect().get_center())
	await create_timer(0.35).timeout
	check(not main._inspection_library_expanded, "收起工具箱后才允许逐张收卡")
	await _finish_cards(sequence)
	check(owned.rune_revealed[0] and main.run_reward_state.gold == before_gold - int(offer.price) and main.owned_card_collection.get_cards().size() == before_count + 3, "收卡后真实实例保留刮开结果且发卡扣款各一次")
	check(main.ordinary_shop_service.rng.state == rng_after_purchase, "撕包、粒子、检视和逐张收起不消耗商品随机流")
	var large_index := _find_generated_pack("large", true)
	check(large_index >= 0, "真实抽取提供含IV卡的五张大包")
	if large_index < 0: quit(1); return
	await create_timer(0.2).timeout
	await click(_tile(large_index).get_global_rect().get_center())
	await create_timer(0.35).timeout
	sequence = main._card_pack_opening
	check(sequence.cards.size() == 5 and sequence.has_rare, "含IV大包使用真实五张结果判断稀有金光")
	await click(Vector2(640, 340), MOUSE_BUTTON_RIGHT)
	await create_timer(0.43).timeout
	check(sequence.phase == CardPackOpening.Phase.BURST and sequence.glow.rare and sequence._shake_elapsed >= 0.0 and sequence.glow.strength > 0.6, "右键自动撕开后稀有包释放冲天金光并轻微震荡")
	await capture("pack-rare-burst")
	check(sequence.glow.size == sequence.overlay.size, "金光画布覆盖检视范围，避免零尺寸控件被渲染剔除")
	await create_timer(1.1).timeout
	check(main.position.is_equal_approx(Vector2.ZERO), "震荡结束恢复主画布原位")
	await _finish_cards(sequence)
	# 外部读档／还原所用的强制关闭必须停止动画并归还工具包。
	var cancel_index := _find_generated_pack("small", false)
	await create_timer(0.2).timeout
	await click(_tile(cancel_index).get_global_rect().get_center())
	await create_timer(0.35).timeout
	surface = main._inspection_surface
	surface.tilt_locked = true
	surface.force = Vector2.ZERO
	await _button(_pointer_for_card_point(surface, Vector2(main._card_pack_opening.tear_art.size.x - 9, 7)), true)
	await _held_motion(_pointer_for_card_point(surface, Vector2(5, 7)))
	await _button(_pointer_for_card_point(surface, Vector2(5, 7)), false)
	check(main._card_pack_opening.phase == CardPackOpening.Phase.BURST and not main._card_pack_opening.tear_art.from_left, "封口可从右向左撕开")
	main._close_card_inspection(true)
	await process_frame
	check(not is_instance_valid(main._card_pack_opening) and not is_instance_valid(main._inspection_overlay) and main.position.is_equal_approx(Vector2.ZERO), "强制还原停止开包控制器且不残留画面位移")
	main._toggle_ordinary_shop()
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Card pack opening failures: ", failures)
	quit(1 if failures else 0)


func _find_generated_pack(pack_size: String, rare: bool) -> int:
	var registry: Dictionary = main._build_card_definition_registry()
	for seed_value: int in range(1, 600):
		main.ordinary_shop_service.initialize(seed_value)
		main.ordinary_shop_service.refresh(main._get_shop_card_definitions(), main.owned_card_collection.get_cards(), main._get_shop_sticker_definitions(), main._get_all_held_stickers())
		for index: int in main.ordinary_shop_service.offers.size():
			var offer: Dictionary = main.ordinary_shop_service.offers[index]
			if offer.kind != "card_pack" or offer.size != pack_size: continue
			if not rare and offer.get("pack_id", "") != "ash_ledger": continue
			var has_iv := false
			for id: String in offer.cards:
				if registry[StringName(id)].rarity == CardData.Rarity.IV: has_iv = true
			if has_iv != rare or registry[StringName(offer.cards[0])].card_type != CardData.CardType.MINION: continue
			main._refresh_ordinary_shop_panel()
			return index
	return -1


func _finish_cards(sequence: CardPackOpening) -> void:
	var expected := sequence.cards.duplicate()
	for index: int in expected.size():
		while sequence.phase == CardPackOpening.Phase.REVEALING:
			await process_frame
		check(main._inspection_owned_card == expected[index], "第%d张沿用原抽取顺序与实例" % (index + 1))
		if expected[index].card_data.rarity == CardData.Rarity.IV:
			check(sequence.glow.rare, "IV卡有独立揭晓光环")
			await capture("pack-iv-card")
		await click(_pointer_for_card_point(main._inspection_surface, Vector2(48, 65)))
		check(sequence.current_index == index + 1, "每次点击立即推进一张，后续点击不再被收卡等待吞掉")
		await create_timer(1.05).timeout
	check(not is_instance_valid(main._inspection_overlay) and not is_instance_valid(main._card_pack_opening) and main.ordinary_shop_open, "最后一张收起后直接返回商店并归还工具包")


func _pointer_for_card_point(surface: InspectionCardSurface, point: Vector2) -> Vector2:
	var local := surface.PADDING + point
	for iteration: int in 8:
		var projected := surface.card_point(local)
		var error := point - projected
		if error.length() < 0.001: break
		var dx := surface.card_point(local + Vector2.RIGHT) - projected
		var dy := surface.card_point(local + Vector2.DOWN) - projected
		local += Transform2D(dx, dy, Vector2.ZERO).affine_inverse() * error
	return surface.get_global_transform_with_canvas() * local


func _button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame


func _held_motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * point
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)
	await process_frame
