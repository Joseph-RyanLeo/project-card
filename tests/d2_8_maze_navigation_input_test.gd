extends SceneTree

## 正式显示壳的鼠标输入、重复开局、跨日可见性与跨场景磁盘恢复。
const DISPLAY = preload("res://scenes/GameDisplay.tscn")
const SentryView = preload("res://scripts/ui/sentry_indicator_view.gd")
var shell: Control
var main: Control
var assertions := 0
var failures := 0
var pointer := Vector2.ZERO

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func open_game() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-maze-navigation.json"
	root.add_child(shell)
	await process_frame
	await process_frame

func move(point: Vector2, held: bool = false) -> void:
	var outer: Vector2 = shell.render_container.get_global_transform_with_canvas() * point
	var event := InputEventMouseMotion.new()
	event.position = outer
	event.global_position = outer
	event.relative = outer - pointer
	pointer = outer
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.warp_mouse(outer)
	root.push_input(event, true)
	await process_frame

func button(point: Vector2, pressed: bool, index: int = MOUSE_BUTTON_LEFT, double_click: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * point
	event.global_position = event.position
	event.button_index = index
	event.pressed = pressed
	event.double_click = double_click
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and index == MOUSE_BUTTON_LEFT else 0
	Input.warp_mouse(event.position)
	root.push_input(event, true)
	await process_frame

func click(point: Vector2, double_click: bool = false) -> void:
	await move(point)
	await button(point, true, MOUSE_BUTTON_LEFT, double_click)
	await button(point, false)
	await process_frame

func flow_button(index: int = 0) -> Button:
	var buttons: Array[Button] = []
	for child: Node in main.maze_controller._body.get_children():
		if child is Button: buttons.append(child)
	return buttons[index] if index < buttons.size() else null

func click_flow(index: int = 0) -> void:
	await process_frame
	await process_frame
	var target := flow_button(index)
	check(target != null and target.is_visible_in_tree(), "当前流程按钮可见")
	if target != null:
		await click(target.get_global_rect().get_center())

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child: Node in node.get_children():
		var result := find_button(child, text)
		if result != null: return result
	return null

func stock_view() -> Control:
	for child: Node in main.maze_controller._sentry_bar.get_children():
		if child.get_script() == SentryView: return child
	return null

func indicator_input() -> void:
	await click(main.player_avatar_button.get_global_rect().get_center())
	await create_timer(main.VIEW_TWEEN_DURATION + 0.05).timeout
	var maze = main.maze_controller
	var inventory: Control = main.celestial_indicators.get_inventory_host()
	check(maze._sentry_bar.get_parent() == inventory, "哨位库存使用原有指示物卡板")
	var view := stock_view()
	check(view != null and inventory.get_global_rect().encloses(view.get_global_rect()), "库存图标完整位于指示物区域")
	if view == null: return
	var id: String = maze.stock[0].instance_id
	var variant: int = maze.stock[0].visual_variant
	await click(view.get_global_rect().get_center())
	check(main.celestial_indicators._data.get("kind") == &"sentry_indicator", "真实点击拿起使用统一指示物携带入口")
	await click(main.front_row.get_global_rect().get_center())
	check(maze.stock.is_empty() and maze.deployed.size() == 1 and maze.deployed[0].region == "front", "再次点击前排提交部署")
	if maze.deployed.is_empty(): return
	view = maze._sentry_views.front
	var source := view.get_global_rect().get_center()
	await move(source)
	await button(source, true)
	await move(source + Vector2(-45, 0), true)
	await move(main.back_row.get_global_rect().get_center(), true)
	check(shell.internal_viewport.gui_is_dragging(), "同一哨位也能长按原生拖动")
	await button(main.back_row.get_global_rect().get_center(), false)
	check(maze.deployed.size() == 1 and maze.deployed[0].region == "back", "原生松手换排使用同一部署规则")
	await click(maze._sentry_views.back.get_global_rect().get_center())
	await click(main.spell_preparation_tray.get_global_rect().get_center())
	check(maze.deployed[0].region == "spells" and maze._sentry_views.spells.position == Vector2.ZERO, "点击放入法术区，图标在左上角")
	check(maze.deployed[0].instance_id == id and maze.deployed[0].visual_variant == variant, "两种操作保持实例、外观和容量")
	check(main.load_run_from_path(main.run_save_path) and maze._sentry_views.spells.position == Vector2.ZERO, "法术区哨位位置读档后保留")
	await click(main.player_avatar_button.get_global_rect().get_center())
	await create_timer(main.VIEW_TWEEN_DURATION + 0.05).timeout
	await click(maze._sentry_views.spells.get_global_rect().get_center())
	await button(Vector2(600, 350), true, MOUSE_BUTTON_RIGHT)
	await button(Vector2(600, 350), false, MOUSE_BUTTON_RIGHT)
	check(main.celestial_indicators._data.is_empty() and maze.deployed.size() == 1, "右键取消哨位携带，不改变部署")
	await click(maze._sentry_views.spells.get_global_rect().get_center())
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	shell.internal_viewport.push_input(key, true)
	await process_frame
	check(main.celestial_indicators._data.is_empty() and not paused, "Esc取消哨位携带")
	await click(maze._sentry_views.spells.get_global_rect().get_center())
	await click(Vector2(600, 350))
	check(main.celestial_indicators._data.is_empty() and maze.deployed[0].region == "spells", "非法落点还原，不丢失哨位")
	await click(maze._sentry_views.spells.get_global_rect().get_center())
	await click(inventory.get_global_rect().get_center())
	check(maze.deployed.is_empty() and maze.stock.size() == 1, "点击放回指示物库存")
	await click(main.player_avatar_button.get_global_rect().get_center())
	await create_timer(main.VIEW_TWEEN_DURATION + 0.05).timeout

func _run() -> void:
	root.size = Vector2i(2560, 1440) if "2k" in OS.get_cmdline_user_args() else Vector2i(1280, 720)
	await open_game()
	if "resume" in OS.get_cmdline_user_args():
		await click(main.continue_run_button.get_global_rect().get_center())
		check(main.maze_controller.run.day == 2 and main.maze_controller.hero.has_talent("sentry_spell") and main.ordinary_shop_open, "独立进程重启恢复第二天商店与咒天赋")
		await create_timer(main.SHOP_OPEN_DURATION + main.SHOP_REBOUND_DURATION).timeout
		var leave := find_button(main.ordinary_shop_panel, "离开")
		check(leave != null, "重启恢复的商店有离开入口")
		if leave != null: await click(leave.get_global_rect().get_center())
		await create_timer(main.SHOP_CLOSE_DURATION + 0.05).timeout
		check(main.maze_controller.run.round_index == 1 and main.maze_controller._panel.is_visible_in_tree(), "独立进程读档后仍能继续下一事件")
		print("独立进程恢复专项：", assertions, "项断言，失败", failures)
		shell.queue_free()
		await process_frame
		quit(1 if failures else 0)
		return
	for attempt: int in range(8):
		var maze = main.maze_controller
		maze.new_run(1707 + attempt)
		await process_frame
		await process_frame
		var id: String = maze.rewards.config.talent_choices["1"][attempt % 4]
		var point := flow_button(attempt % 4).get_global_rect().get_center()
		await click(point)
		check(maze.hero.has_talent(id) and maze.run.paths.size() == 3 and maze.stock.size() == 1, "四种一级天赋重复开局仍进入首日")
		var before: Dictionary = maze.capture_state()
		await click(point, true)
		check(maze.capture_state() == before and not main.ordinary_shop_open, "双击第二次不能误选下一屏商店")
		check(not maze.choose_talent(id) and maze.capture_state() == before, "重复选择不锁死或重复产出")
		if attempt == 0: await indicator_input()
		await click_flow()
		check(main.ordinary_shop_open, "鼠标选择首日商店")
		await create_timer(main.SHOP_OPEN_DURATION + main.SHOP_REBOUND_DURATION).timeout
		var leave := find_button(main.ordinary_shop_panel, "离开")
		check(leave != null, "商店有离开入口")
		if leave != null: await click(leave.get_global_rect().get_center())
		await create_timer(main.SHOP_CLOSE_DURATION + 0.05).timeout
		check(not main.ordinary_shop_open and maze.run.round_index == 1, "鼠标离店继续免费事件")
		await click_flow()
		await click_flow()
		check(maze.run.round_index == 2, "免费事件完成")
		await click_flow()
		await click_flow(1)
		check(maze.run.round_index == 3, "放弃付费事件继续日末战斗")
		await click_flow()
		check(main.start_battle_button.is_visible_in_tree(), "选择敌人后开战入口可见")
		await click(main.start_battle_button.get_global_rect().get_center())
		check(main.battle_controller.current_result == main.BattleController.Result.PLAYER_DEFEAT, "真实空阵战斗判负")
		main._show_battle_result(main.battle_controller.current_result)
		await process_frame
		check(main.continue_next_level_button.is_visible_in_tree() and not main.continue_next_level_button.disabled, "真实战后继续入口可用")
		await click(main.continue_next_level_button.get_global_rect().get_center())
		await create_timer(main.VIEW_TWEEN_DURATION + 0.05).timeout
		check(maze.run.day == 2 and maze.run.paths.size() == 3 and main.current_world_view == main.WorldView.BATTLEFIELDS and maze._panel.is_visible_in_tree(), "跨日生成路径后保持路径桌面可见")
		var saved: Dictionary = maze.capture_state()
		shell.queue_free()
		await process_frame
		await open_game()
		await click(main.continue_run_button.get_global_rect().get_center())
		maze = main.maze_controller
		check(JSON.parse_string(JSON.stringify(maze.capture_state())) == JSON.parse_string(JSON.stringify(saved)) and maze._panel.is_visible_in_tree(), "重启显示壳后点击继续，恢复第二天与已选天赋")
		var cards_before: int = main.owned_card_collection.size()
		await click_flow()
		check(main.ordinary_shop_open and main.owned_card_collection.size() == cards_before + 5, "重启后第二天仍可进入商店并领取一份大包")
		await process_frame
	print("迷宫输入专项：", assertions, "项断言，失败", failures)
	shell.queue_free()
	await process_frame
	quit(1 if failures else 0)
