extends SceneTree

## 使用真实显示壳和鼠标输入，对照点按与长按的部署、回收、拒绝和取消。
const DISPLAY := preload("res://scenes/GameDisplay.tscn")
const SentryView := preload("res://scripts/ui/sentry_indicator_view.gd")
const SAVE_PATH := "/private/tmp/project-card-sentry-carry-test.json"
var shell: Control
var main: Control
var pointer := Vector2.ZERO
var assertions := 0
var failures := 0

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("哨位输入专项超时"); quit(2))
	_run.call_deferred()

func check(value: bool, message: String) -> bool:
	assertions += 1
	print("PASS: " if value else "FAIL: ", message)
	if not value: failures += 1
	return value

func move(point: Vector2, held: bool = false) -> void:
	var outer: Vector2 = shell.render_container.get_global_transform_with_canvas() * point
	var event := InputEventMouseMotion.new()
	event.position = outer
	event.global_position = outer
	event.relative = outer - pointer
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	pointer = outer
	Input.warp_mouse(outer)
	root.push_input(event, true)
	await process_frame

func button(point: Vector2, pressed: bool, index: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * point
	event.global_position = event.position
	event.button_index = index
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and index == MOUSE_BUTTON_LEFT else 0
	Input.warp_mouse(event.position)
	root.push_input(event, true)
	await process_frame

func click(point: Vector2) -> void:
	await move(point)
	await button(point, true)
	await button(point, false)
	await process_frame

func view_for(id: String) -> Control:
	for view: Control in main.maze_controller._sentry_bar.get_children():
		if view.get_script() == SentryView and view.sentry_data.instance_id == id: return view
	for view: Control in main.maze_controller._sentry_views.values():
		if view.sentry_data.instance_id == id: return view
	return null

func pick_up(id: String, gesture: String) -> void:
	var view := view_for(id)
	var source := view.get_global_rect().get_center()
	await move(source)
	await button(source, true)
	if gesture == "长按":
		await create_timer(0.15).timeout
		await move(source + Vector2(-48, 0), true)
		check(shell.internal_viewport.gui_is_dragging(), "长按进入真实原生拖动")
	else:
		await button(source, false)
	check(main.celestial_indicators._data.get("instance_id") == id, gesture + "共用携带状态中的哨位实例")

func place(id: String, target: Vector2, gesture: String) -> void:
	await pick_up(id, gesture)
	if gesture == "长按":
		await move(target, true)
		await button(target, false)
	else:
		await click(target)
	await create_timer(0.35).timeout
	check(main.celestial_indicators._data.is_empty() and not shell.internal_viewport.gui_is_dragging(), gesture + "放置后完整结束携带")

func zone_center(region: String) -> Vector2:
	return main.maze_controller._sentry_zones[region].get_global_rect().get_center()

func close_game() -> void:
	shell.queue_free()
	await process_frame
	print("哨位双输入专项：%d条断言，%d失败" % [assertions, failures])
	quit(failures)

func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = SAVE_PATH
	root.add_child(shell)
	await process_frame
	await process_frame
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K if "--2k" in OS.get_cmdline_user_args() else shell.DisplayMode.WINDOW_720P)
	for index: int in 6: await process_frame
	var maze = main.maze_controller
	maze.new_run(1707)
	check(maze.choose_talent("sentry_guard"), "真实英雄日初产生哨位")
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	await process_frame
	var id: String = maze.stock[0].instance_id
	var variant: int = maze.stock[0].visual_variant
	for gesture: String in ["点按", "长按"]:
		for region: String in ["front", "back", "spells"]:
			await place(id, zone_center(region), gesture)
			if not check(maze.deployed.size() == 1 and maze.deployed[0].region == region, gesture + "实际放入" + region):
				await close_game()
				return
			check(maze.deployed[0].instance_id == id and maze.deployed[0].visual_variant == variant, gesture + "保留实例和外观")
		await place(id, zone_center("stock"), gesture)
		check(maze.deployed.is_empty() and maze.stock.size() == 1 and maze.stock[0].has("stock_position"), gesture + "回收入库存并保存位置")
	maze._add_sentry()
	maze.refresh()
	var occupied_id: String = maze.stock[1].instance_id
	check(maze.deploy_sentry(occupied_id, "front"), "真实事务建立已占用的前排")
	await process_frame
	for gesture: String in ["点按", "长按"]:
		for invalid: Vector2 in [zone_center("front"), Vector2(600, 350)]:
			var before: Dictionary = maze.capture_state()
			var source_position: Vector2 = view_for(id).position
			await place(id, invalid, gesture)
			check(maze.capture_state() == before and view_for(id).visible and view_for(id).position == source_position, gesture + "拒绝已占用／非法位置，保持数据并回位")
		for cancel: String in ["右键", "Esc"]:
			var before: Dictionary = maze.capture_state()
			await pick_up(id, gesture)
			await move(Vector2(600, 350), gesture == "长按")
			if cancel == "右键":
				await button(Vector2(600, 350), true, MOUSE_BUTTON_RIGHT)
				await button(Vector2(600, 350), false, MOUSE_BUTTON_RIGHT)
			else:
				var event := InputEventKey.new()
				event.keycode = KEY_ESCAPE
				event.pressed = true
				root.push_input(event, true)
				await process_frame
			if gesture == "长按": await button(Vector2(600, 350), false)
			await create_timer(0.35).timeout
			check(maze.capture_state() == before and main.celestial_indicators._data.is_empty() and not shell.internal_viewport.gui_is_dragging() and view_for(id).visible and not paused, gesture + cancel + "取消不改数据、不误开暂停菜单")
	# JSON会把数字读为float；归一化两侧后仍比较所有字段，避免类型差异误报。
	var before_load: Dictionary = JSON.parse_string(JSON.stringify(maze.capture_state()))
	var loaded: bool = main.load_run_from_path(SAVE_PATH)
	var after_load: Dictionary = JSON.parse_string(JSON.stringify(maze.capture_state()))
	check(loaded and after_load == before_load, "合法投放保存的数据真实读档后保持一致")
	await close_game()
