extends "res://tests/d2_8_card_exchange_ui_test.gd"

## 真实显示壳和鼠标逐帧验证松手起点、容器重排与战场来源。
func run() -> void:
	create_timer(75).timeout.connect(func(): push_error("服务入槽时序专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-service-entry-timing.json"
	root.add_child(shell)
	shell.apply_display_mode(2 if "2k" in OS.get_cmdline_user_args() else 0)
	await create_timer(0.3).timeout
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	main._toggle_ordinary_shop()
	await create_timer(0.4).timeout
	main._open_shop_exchange()
	var owned: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/heavy_knight.tres"))
	main._sync_legacy_collection_cards()
	show_page_for(owned)
	await process_frame
	var source_slot: Control = main._find_collection_slot_for_owned_card(owned)
	var card: CardView = source_slot.get_child(0)
	# 用真实预览节点检验Godot移走拖拽层之后的查询，不使用替身对象。
	var preview := CardView.create_drag_visual(card._build_drag_data(card.card_size * 0.5))
	main.add_child(preview)
	preview.global_position = Vector2(733, 233)
	var visible_position := preview.get_card_global_position()
	main.remove_child(preview)
	check(preview.get_card_global_position().is_equal_approx(visible_position), "离树后的预览仍返回最后可见位置，不退回局部原点")
	preview.free()
	for index: int in 12:
		var service: Control = main._shop_exchange_slots[0]
		await native_pickup(card)
		var point: Vector2 = service.get_global_rect().get_center() if index % 2 == 0 else service.get_global_rect().position - Vector2(35, 20)
		await motion(point, true)
		await process_frame
		var live: CardDragPreview = shell.internal_viewport.gui_get_drag_data().drag_visual
		var entry := live.get_card_global_position()
		var expected: Vector2 = service._empty_outline.get_parent().get_global_transform_with_canvas() * service.CARD_POSITION if index % 2 == 0 else source_slot.get_global_transform_with_canvas() * card._layout_resting_position
		await button(point, false)
		if index % 2 == 0:
			check(service._card_view == card, "反复原生拖入融合槽保留原卡")
			await check_path(card, entry, expected, "融合入槽")
			service.return_card()
			await process_frame
		else:
			check(service._card_view == null and card.get_parent() == source_slot, "槽外松手拒绝入槽并归还收藏")
			await check_path(card, entry, expected, "无效落点归还")
		await create_timer(0.05).timeout
	await test_board_services(owned)
	shell.queue_free()
	await process_frame
	await test_enhancement()
	print("服务入槽时序：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func native_pickup(card: CardView) -> void:
	var point := card.get_global_transform_with_canvas() * (card.card_size * 0.5)
	await motion(point)
	await button(point, true)
	await motion(point + Vector2(35, 3), true)
	check(shell.internal_viewport.gui_is_dragging(), "正式卡面可通过长按抓取")

func check_path(card: CardView, entry: Vector2, target: Vector2, label: String) -> void:
	var stayed_on_path := true
	var minimum_progress := -0.01
	var direction := target - entry
	for frame: int in 16:
		var point := card.get_global_transform_with_canvas().origin
		var hover_target := target - Vector2(0, card._external_lift)
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, entry, target)) > 3.0 and point.distance_to(hover_target) > 1.0:
			stayed_on_path = false
		if direction.length_squared() > 0.1:
			var progress := (point - entry).dot(direction) / direction.length_squared()
			if progress < minimum_progress - 0.03 and point.distance_to(hover_target) > 1.0: stayed_on_path = false
			minimum_progress = progress
		await create_timer(0.02).timeout
	check(stayed_on_path, label + "逐帧沿松手位置到目标的线段移动，不向左上角或右侧跳变")
	check(card.get_global_transform_with_canvas().origin.distance_to(target - Vector2(0, card._external_lift)) < 1.0, label + "最终精确归位，正常收藏悬停按已有抽出距离显示")

func test_board_services(owned: OwnedCard) -> void:
	main._close_shop_card_services()
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	main._build_collection_cards()
	var board_slot: BoardSlot = main.front_row.get_squads()[0]
	var card := board_slot.get_primary_card_view()
	for kind: int in 2:
		if kind == 0: main._open_shop_exchange()
		else: main._open_shop_card_services()
		main.set_world_view(main.WorldView.BATTLEFIELDS, false)
		await create_timer(0.2).timeout
		var service: Control = main._shop_exchange_slots[0] if kind == 0 else main._shop_service_slot
		check(card._drag_enabled and not main.front_row.can_receive_card_drag(card._build_drag_data(Vector2.ZERO)), "服务中战场卡可抓取，战场仍不能接收放置")
		await native_pickup(card)
		await motion(service.get_global_rect().get_center(), true)
		var live: CardDragPreview = shell.internal_viewport.gui_get_drag_data().drag_visual
		var entry := live.get_card_global_position()
		var target: Vector2 = service._empty_outline.get_parent().get_global_transform_with_canvas() * service.CARD_POSITION
		await button(service.get_global_rect().get_center(), false)
		check(service._card_view == card and card._drag_source_type == &"card_service" and board_slot.get_squad_data().get_owned_card(card.card_data) == owned, "战场原卡可长按拖入融合或卡牌服务且部署数据保留")
		await check_path(card, entry, target, "战场服务入槽")
		main._refresh_drag_availability()
		check(card._drag_source_type == &"card_service", "刷新战场输入不会覆盖槽内卡的来源绑定")
		main._close_shop_card_services()
		await process_frame
		check(card.get_parent() == board_slot.card_visual_layer and card._drag_source_type == &"board" and not card.is_set_as_top_level(), "关闭服务恢复同一卡面和战场输入绑定")
		# 点击携带也要允许从战场抓取到同一个槽。
		if kind == 0: main._open_shop_exchange()
		else: main._open_shop_card_services()
		main.set_world_view(main.WorldView.BATTLEFIELDS, false)
		await create_timer(0.2).timeout
		service = main._shop_exchange_slots[0] if kind == 0 else main._shop_service_slot
		await click(card.get_global_rect().get_center())
		check(main._click_carry_data.get("source_type") == &"board", "服务期间战场卡也可以点击携带")
		await click(service.get_global_rect().get_center())
		await create_timer(0.25).timeout
		check(service._card_view == card and main._click_carry_data.is_empty(), "战场卡点击携带可进入融合或卡牌服务")
		main._close_shop_card_services()
		await process_frame

func test_enhancement() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-enhancement-entry-timing.json"
	root.add_child(shell)
	shell.apply_display_mode(2 if "2k" in OS.get_cmdline_user_args() else 0)
	await create_timer(0.3).timeout
	var maze: ShortMazeController = main.maze_controller
	maze.new_run(1205)
	maze.choose_talent("sentry_guard")
	maze.select_path(maze.run.paths[0].path_id)
	maze.complete_event(false)
	maze.select_path(maze.run.paths[0].path_id)
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	var source_slot: Control = main._find_collection_slot_for_owned_card(owned)
	var card: CardView = source_slot.get_child(0)
	for index: int in 5:
		var slot: Control = maze._enhancement_slot
		await native_pickup(card)
		await motion(slot.get_global_rect().get_center() - Vector2(25, 0), true)
		var live: CardDragPreview = shell.internal_viewport.gui_get_drag_data().drag_visual
		var entry := live.get_card_global_position()
		await button(slot.get_global_rect().get_center() - Vector2(25, 0), false)
		slot = maze._enhancement_slot
		# 原槽会被替换，等待容器排版后读取最终目标，再检查逐帧路径。
		var target: Vector2 = slot._empty_outline.get_parent().get_global_transform_with_canvas() * slot.CARD_POSITION
		check(slot._card_view == card, "强化原生松手后新槽接收原卡")
		await check_path(card, entry, target, "强化界面重排入槽")
		slot.return_card()
		await process_frame
		await process_frame
	# 从真实战场小队抓取原卡进行强化。
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	main._build_collection_cards()
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await create_timer(0.2).timeout
	var board_slot: BoardSlot = main.front_row.get_squads()[0]
	card = board_slot.get_primary_card_view()
	check(card._drag_enabled and not main.front_row.can_receive_card_drag(card._build_drag_data(Vector2.ZERO)), "强化期间战场只开放抓取，关闭部署")
	await native_pickup(card)
	await motion(maze._enhancement_slot.get_global_rect().get_center(), true)
	await button(maze._enhancement_slot.get_global_rect().get_center(), false)
	await create_timer(0.25).timeout
	check(maze._enhancement_slot._card_view == card and card._drag_source_type == &"card_service", "战场卡可长按拖入强化槽")
	maze._enhancement_slot.return_card()
	await process_frame
	await process_frame
	await click(card.get_global_rect().get_center())
	await click(maze._enhancement_slot.get_global_rect().get_center())
	await create_timer(0.25).timeout
	check(maze._enhancement_slot._card_view == card, "战场卡可点击携带进入强化槽")
	maze.complete_event(false)
	await process_frame
	check(card.get_parent() == board_slot.card_visual_layer and not card.is_set_as_top_level(), "离开强化把原卡归还原小队")
	shell.queue_free()
	await process_frame
