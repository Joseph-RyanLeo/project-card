extends "res://tests/sentry_carry_input_test.gd"

## 真实显示壳和鼠标/键盘输入，覆盖携带途中切视角而不提交卡牌。
func key_tab(echo_event: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.pressed = true
	event.echo = echo_event
	root.push_input(event, true)
	await process_frame
	event = InputEventKey.new()
	event.keycode = KEY_TAB
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-drag-camera-revision.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K if "--2k" in OS.get_cmdline_user_args() else shell.DisplayMode.WINDOW_720P)
	await create_timer(0.4).timeout
	var maze: ShortMazeController = main.maze_controller
	maze.new_run(1707)
	check(maze.choose_talent("sentry_guard"), "真实日初结束天赋选择")
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	var owned: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/militia.tres"))
	main.back_row.add_squad(SquadData.from_owned_card(owned), 0)
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	main._refresh_drag_availability()
	await process_frame
	await key_tab()
	check(main.current_world_view == main.WorldView.COLLECTION, "Tab切换下半视角")
	await key_tab(true)
	check(main.current_world_view == main.WorldView.COLLECTION, "长按键盘重复事件不来回切换")
	await key_tab()
	check(main.current_world_view == main.WorldView.BATTLEFIELDS, "再次Tab返回上半视角")
	await create_timer(0.5).timeout
	await move(Vector2(640, 710))
	await create_timer(1.15).timeout
	check(main.current_world_view == main.WorldView.BATTLEFIELDS, "空手停留底边不切视角")
	for gesture: String in ["点按", "长按"]:
		var slot: BoardSlot = main.back_row.get_squads()[0]
		var view: CardView = slot.get_card_views()[0]
		var source := view.get_global_rect().get_center()
		await move(source)
		await button(source, true)
		if gesture == "长按":
			await create_timer(0.15).timeout
			await move(source + Vector2(40, 0), true)
			check(shell.internal_viewport.gui_is_dragging() and not main._native_carry_data.is_empty(), "真实原生卡牌拖动开始")
		else:
			await button(source, false)
			check(not main._click_carry_data.is_empty(), "真实点击携带开始")
		await key_tab()
		check(main.current_world_view == main.WorldView.COLLECTION, gesture + "携带中Tab切换")
		check(shell.internal_viewport.gui_is_dragging() if gesture == "长按" else not main._click_carry_data.is_empty(), gesture + "Tab不结束携带")
		await key_tab()
		await create_timer(0.5).timeout
		await move(Vector2(640, 710), gesture == "长按")
		await create_timer(0.4).timeout
		check(main.current_world_view == main.WorldView.BATTLEFIELDS, gesture + "不足一秒不切换")
		await move(Vector2(900, 500), gesture == "长按")
		await create_timer(0.8).timeout
		check(main.current_world_view == main.WorldView.BATTLEFIELDS, gesture + "离开底边重置计时")
		await move(Vector2(640, 710), gesture == "长按")
		await create_timer(1.15).timeout
		check(main.current_world_view == main.WorldView.COLLECTION, gesture + "底边连续一秒自动切下半视角")
		check(shell.internal_viewport.gui_is_dragging() if gesture == "长按" else not main._click_carry_data.is_empty(), gesture + "自动切换仍保留携带")
		await create_timer(0.5).timeout
		check(main.world_content.position.is_equal_approx(-main.COLLECTION_VIEW_ORIGIN), gesture + "沿用原位移和回弹动画终点")
		await button(Vector2(640, 710), true, MOUSE_BUTTON_RIGHT)
		await button(Vector2(640, 710), false, MOUSE_BUTTON_RIGHT)
		if gesture == "长按": await button(Vector2(640, 710), false)
		await create_timer(0.4).timeout
		check(main._click_carry_data.is_empty() and not shell.internal_viewport.gui_is_dragging(), gesture + "切换后仍可正常取消")
		check(main.back_row.get_squads()[0].get_squad_data().get_effect_source_instance() == owned, gesture + "取消不改变卡牌归属与阵容")
		main.set_world_view(main.WorldView.BATTLEFIELDS, false)
		await process_frame
	main.set_world_view(main.WorldView.COLLECTION, false)
	main.search_edit.grab_focus()
	await key_tab()
	check(main.current_world_view == main.WorldView.COLLECTION, "搜索框内Tab保留输入焦点导航，不移动视角")
	main.search_edit.release_focus()
	main._open_card_inspection(owned.card_data, owned)
	await create_timer(0.3).timeout
	await key_tab()
	check(main.current_world_view == main.WorldView.COLLECTION, "检视弹层内Tab不移动底下视角")
	main._close_card_inspection(true)
	shell.queue_free()
	await process_frame
	await process_frame
	print("拖动视角专项：%d项，%d失败" % [assertions, failures])
	quit(failures)
