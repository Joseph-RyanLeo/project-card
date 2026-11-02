extends "res://tests/drag_camera_switch_20261026_test.gd"

## 正式界面实际携带：自动下移只移动视角，棋盘留在原上半世界位置。
func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-drag-camera-tabletop-anchor.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K if "--2k" in OS.get_cmdline_user_args() else shell.DisplayMode.WINDOW_720P)
	await create_timer(0.4).timeout
	var maze: ShortMazeController = main.maze_controller
	maze.new_run(1707)
	check(maze.choose_talent("sentry_guard"), "正式日初完成天赋选择")
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	var owned: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/militia.tres"))
	main.back_row.add_squad(SquadData.from_owned_card(owned), 0)
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	main._refresh_drag_availability()
	await process_frame
	for gesture: String in ["点按", "长按"]:
		await verify_board_anchor(maze._panel, owned, gesture, "事件板")
	check(maze.select_path(maze.run.paths[0].path_id) and maze.complete_event(false), "真实完成随机事件")
	check(maze.select_path(maze.run.paths[0].path_id) and maze.complete_event(false), "真实跳过强化")
	check(maze.select_path(maze.run.paths[0].path_id) and main.ordinary_shop_open, "真实路径进入商店")
	await create_timer(0.6).timeout
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	for gesture: String in ["点按", "长按"]:
		await verify_board_anchor(main.ordinary_shop_panel, owned, gesture, "商店板")
	shell.queue_free()
	await process_frame
	await process_frame
	print("拖动切视角棋盘原位专项：%d项，%d失败" % [assertions, failures])
	quit(failures)

func verify_board_anchor(panel: Control, owned: OwnedCard, gesture: String, label: String) -> void:
	var original_world: Vector2 = main.world_content.get_global_transform_with_canvas().affine_inverse() * panel.get_global_transform_with_canvas().origin
	var original_screen := panel.get_global_transform_with_canvas().origin
	var event_table: Control = main.maze_controller._event_table
	var original_offers: Array = main.ordinary_shop_service.offers.duplicate(true)
	var original_rng: int = main.maze_controller.run.rng.state
	var view: CardView = main.back_row.get_squads()[0].get_card_views()[0]
	var source := view.get_global_rect().get_center()
	await move(source)
	await button(source, true)
	if gesture == "长按":
		await create_timer(0.15).timeout
		await move(source + Vector2(40, 0), true)
		check(shell.internal_viewport.gui_is_dragging(), label + "真实原生卡牌拖动开始")
	else:
		await button(source, false)
		check(not main._click_carry_data.is_empty(), label + "真实点击携带开始")
	await move(Vector2(640, 710), gesture == "长按")
	await create_timer(1.15).timeout
	check(main.current_world_view == main.WorldView.COLLECTION and main._tabletop_panels_parked, label + gesture + "自动下移并留住上半棋盘")
	var during_world: Vector2 = main.world_content.get_global_transform_with_canvas().affine_inverse() * panel.get_global_transform_with_canvas().origin
	check(during_world.is_equal_approx(original_world), label + gesture + "移动途中世界位置不变")
	check(shell.internal_viewport.gui_is_dragging() if gesture == "长按" else not main._click_carry_data.is_empty(), label + gesture + "不结束携带")
	await create_timer(0.5).timeout
	var expected_screen: Vector2 = main.world_content.get_global_transform_with_canvas() * original_world
	check(panel.get_global_transform_with_canvas().origin.is_equal_approx(expected_screen), label + gesture + "切换后仍在原世界位置，不固定在下半屏幕")
	check(not panel.get_global_transform_with_canvas().origin.is_equal_approx(original_screen), label + gesture + "面板没有跟到下半视角")
	check(main.maze_controller._event_table == event_table and main.ordinary_shop_service.offers == original_offers and main.maze_controller.run.rng.state == original_rng, label + gesture + "不重建路径桌面或重抽商品与奖励")
	check(not main._tabletop_park_button.disabled, label + gesture + "保留手动移回棋盘的按钮")
	await button(Vector2(640, 710), true, MOUSE_BUTTON_RIGHT)
	await button(Vector2(640, 710), false, MOUSE_BUTTON_RIGHT)
	if gesture == "长按": await button(Vector2(640, 710), false)
	await create_timer(0.4).timeout
	check(main.back_row.get_squads()[0].get_squad_data().get_effect_source_instance() == owned and main._click_carry_data.is_empty() and not shell.internal_viewport.gui_is_dragging(), label + gesture + "取消携带不改变卡牌实例和阵容")
	main.maze_controller.refresh()
	var refreshed_world: Vector2 = main.world_content.get_global_transform_with_canvas().affine_inverse() * panel.get_global_transform_with_canvas().origin
	check(main._tabletop_panels_parked and refreshed_world.is_equal_approx(original_world), label + gesture + "刷新不把棋盘拉回下半视角")
	main._park_tabletop_panels()
	await create_timer(0.4).timeout
	check(not main._tabletop_panels_parked and panel.get_global_transform_with_canvas().origin.is_equal_approx(original_screen), label + gesture + "手动按钮仍可把棋盘移回当前视角")
	await key_tab()
	await create_timer(0.5).timeout
	check(main.current_world_view == main.WorldView.BATTLEFIELDS and not main._tabletop_panels_parked, label + gesture + "Tab返回上半仍恢复原跟随逻辑")
