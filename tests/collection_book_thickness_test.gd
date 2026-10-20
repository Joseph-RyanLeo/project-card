extends "res://tests/aseprite_board_realign_test.gd"

const BOOK_SAVE := "/private/tmp/project-card-book-thickness-save.json"


func capture_book(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = shell.internal_viewport.get_texture().get_image()
	image.save_png("/private/tmp/project-card-book-thickness-%s.png" % label)
	return image


func verify_stack_pixels(label: String) -> void:
	var stack: TextureRect = main.get_node("%PageStackArt")
	var image := await capture_book(label)
	var source: Image = stack.texture.get_image()
	var compared := 0
	var differences := 0
	# 最下方纸叠不属于翻动纸面，也不经过页码或卡牌区域。
	for x: int in source.get_width():
		var point := Vector2i(x, 314)
		var color := source.get_pixelv(point)
		if color.a < 1.0:
			continue
		compared += 1
		if not image.get_pixelv(Vector2i(stack.global_position) + point).is_equal_approx(color):
			differences += 1
	check(compared > 800 and differences == 0, "原生渲染纸叠厚度逐像素一致：" + label)
	check(stack.global_position == Vector2(219, 402) and stack.scale == Vector2.ONE,
		"纸叠在翻页和最近页中保持固定位置及尺寸：" + label)


func verify_page_turn(forward: bool) -> void:
	var button: Button = main.right_edge_button if forward else main.left_edge_button
	await _click(button)
	check(is_instance_valid(main._page_turn_overlay), "原生鼠标点击启动前翻／后翻")
	if not is_instance_valid(main._page_turn_overlay):
		return
	main._page_tween.pause()
	main._page_tween.custom_step(0.07)
	var moving: Control = main._page_turn_overlay.get_node("MovingPage")
	var texture: Texture2D = moving.get_node("PageArt").texture
	check(moving.size == Vector2(413, 309) and moving.scale.x > 0 and moving.scale.x < 1,
		"实际翻动只有上层纸面，保留原生纸面尺寸")
	check(texture == main._get_regular_page_texture(1 if forward else 0), "动画使用新版左右纸面裁切")
	await verify_stack_pixels("forward" if forward else "backward")
	main._page_tween.play()
	await create_timer(0.45).timeout
	check(not is_instance_valid(main._page_turn_overlay), "翻页结束销毁演出层并归还真实卡面")
	check(main.current_collection_page == (1 if forward else 0), "翻页后显示正确收藏页")
	check(main.left_page_number_label.text == ("3" if forward else "1"), "翻页后更新实际物理页码")
	var slot: Control = main._get_collection_card_slots()[0]
	check(slot.get_child(0).global_position == Vector2(250, 415), "翻页结束后卡位仍按图层9精确对齐")


func verify_return_and_recent() -> void:
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	var board_slot: BoardSlot = main.front_row.get_squads()[0]
	var returned: OwnedCard = board_slot.squad_data.get_owned_card(board_slot.squad_data.horizontal_cards[0])
	await move_pointer(board_slot.card_view.get_global_rect().get_center())
	await press_pointer(true)
	await move_pointer(pointer + Vector2(24, 4), true)
	check(shell.internal_viewport.gui_is_dragging(), "战场真实卡面启动原生拖拽")
	await move_pointer(Vector2(642, 680), true)
	await press_pointer(false)
	await create_timer(0.2).timeout
	check(main.recently_returned_owned_cards.has(returned), "放回新版收藏书后记录实际卡牌实例")
	await _click(main.recent_bookmark_button)
	await create_timer(0.3).timeout
	check(main.collection_bookmark_active and main.recent_left_page_art.is_visible_in_tree(), "真实书签切到最近使用页")
	check(main.recent_left_page_art.texture == main.RECENT_CARDS_LEFT_PAGE_TEXTURE
		and main.recent_right_page_art.texture == main.RECENT_CARDS_RIGHT_PAGE_TEXTURE,
		"最近页保留现有图案")
	check(is_instance_valid(main._find_collection_slot_for_owned_card(returned)), "最近页显示同一张返还实卡")
	await move_pointer(Vector2(100, 600))
	await verify_stack_pixels("recent")
	await _click(main.recent_bookmark_button)
	await create_timer(0.3).timeout
	check(not main.collection_bookmark_active, "再次点击返回普通新版纸页")


func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = BOOK_SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await process_frame
	maze = main.maze_controller
	_deal("loose_coins")
	await create_timer(0.4).timeout
	await verify_source_positions()
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	var book: Control = main.get_node("%BookPanel")
	var stack: Control = main.get_node("%PageStackArt")
	check(book.position == Vector2(203, 0) and book.size == Vector2(874, 361), "新版书皮原生尺寸和世界位置")
	check(stack.position == Vector2(15, 23) and stack.size == Vector2(844, 316), "新版纸叠按原稿对齐")
	check(main.action_filter_tabs.global_position - main.world_content.position == Vector2(244, 735), "行动标签世界位置不变")
	check(main.card_type_filter_tabs.global_position - main.world_content.position == Vector2(463, 745), "种类标签世界位置不变")
	await move_pointer(Vector2(100, 600))
	await verify_stack_pixels("regular")
	for index: int in 13:
		main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	await process_frame
	var owned_before: Array = main.owned_card_collection.get_cards().duplicate()
	await verify_page_turn(true)
	await verify_page_turn(false)
	check(main.owned_card_collection.get_cards() == owned_before, "往返翻页不复制、丢失或重排真实拥有实例")
	await verify_return_and_recent()
	# 新局恢复少量可见卡，继续覆盖新版书本中的真实资源、法术拖放。
	_deal("loose_coins")
	await create_timer(0.4).timeout
	main.set_world_view(main.WorldView.COLLECTION, false)
	await verify_resource_drag()
	await verify_spell_drag()
	check(main.save_run_to_path(BOOK_SAVE) == OK and main.load_run_from_path(BOOK_SAVE), "更换素材后仍可正常存读档")
	paused = false
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(BOOK_SAVE)
	print("新版收藏书厚度：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
