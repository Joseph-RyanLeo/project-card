extends "res://tests/sentry_carry_input_test.gd"

## 准备阶段及真实商店事件中，自由摆放哨位库存并跨区域部署。
func stock_entry(id: String) -> Dictionary:
	for entry: Dictionary in main.maze_controller.stock:
		if entry.instance_id == id: return entry
	return {}

func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-sentry-inventory-revision.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K if "--2k" in OS.get_cmdline_user_args() else shell.DisplayMode.WINDOW_720P)
	await create_timer(0.4).timeout
	var maze: ShortMazeController = main.maze_controller
	maze.new_run(1707)
	check(maze.choose_talent("sentry_guard"), "真实日初产生哨位")
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	var id: String = maze.stock[0].instance_id
	var variant: int = maze.stock[0].visual_variant
	for gesture: String in ["点按", "长按"]:
		var zone: Control = maze._sentry_zones.stock
		var local := Vector2(150, 150) if gesture == "点按" else Vector2(25, 160)
		var previous := view_for(id).position
		await place(id, zone.get_global_transform_with_canvas() * local, gesture)
		check(not stock_entry(id).is_empty() and stock_entry(id).has("stock_position"), gesture + "库存内移动仍属于库存并保存位置")
		check(not view_for(id).position.is_equal_approx(previous), gesture + "库存内图标实际移动")
		check(stock_entry(id).visual_variant == variant, gesture + "库存移动保留原外观")
		var bounds := Rect2(view_for(id).position, view_for(id).size)
		check(Rect2(Vector2.ZERO, main.celestial_indicators.TRAY_SIZE).encloses(bounds), gesture + "库存内位置不越界")
		for other: Control in main.celestial_indicators._tray_views.values():
			check(not bounds.intersects(Rect2(other.position, other.size)), gesture + "哨位不与日月星库存重叠")
	check(maze.select_path(maze.run.paths[0].path_id) and maze.complete_event(false), "正常完成首个事件")
	check(maze.select_path(maze.run.paths[0].path_id) and maze.complete_event(false), "正常跳过强化进入商店选择")
	check(maze.select_path(maze.run.paths[0].path_id) and main.ordinary_shop_open, "正常路径进入商店，不伪造商店开关")
	main.set_world_view(main.WorldView.COLLECTION, false)
	await create_timer(0.6).timeout
	main._park_tabletop_panels()
	await create_timer(0.4).timeout
	check(main._tabletop_panels_parked, "收起真实商店棋盘，避免点击被棋盘遮住的前排图标")
	for gesture: String in ["点按", "长按"]:
		check(maze.can_drop_sentry(id, "front"), gesture + "商店中的准备阶段允许放置")
		await place(id, zone_center("front"), gesture)
		check(maze.deployed.size() == 1 and maze.deployed[0].region == "front", gesture + "商店中真实部署前排")
		await place(id, zone_center("back"), gesture)
		check(maze.deployed.size() == 1 and maze.deployed[0].region == "back", gesture + "商店中真实换到后排")
		await place(id, zone_center("stock"), gesture)
		check(maze.deployed.is_empty() and stock_entry(id).visual_variant == variant, gesture + "商店中真实回收且不改变实例")
	var saved_position: Array = stock_entry(id).stock_position.duplicate()
	check(main.save_run_to_path(main.run_save_path) == OK and main.load_run_from_path(main.run_save_path), "商店哨位状态真实保存并恢复")
	check(stock_entry(id).stock_position == saved_position and stock_entry(id).visual_variant == variant, "读档后库存坐标及外观不变")
	main.current_phase = main.GamePhase.BATTLE
	check(not maze.can_drop_sentry(id, "front") and not maze.can_drop_sentry(id, "stock"), "战斗时仍不可部署或移动库存")
	main.current_phase = main.GamePhase.PREPARE
	shell.queue_free()
	await process_frame
	await process_frame
	print("哨位库存专项：%d项，%d失败" % [assertions, failures])
	quit(failures)
