extends SceneTree

## 真实GPU、鼠标／键盘输入及嵌入弹窗；资格源自连续任务链留下的临时档。
const SHELL = preload("res://scenes/StartMenu.tscn")
const DIR := "/private/tmp/project-card-d3-4-ui-test"
const PREVIEWS := "res://docs/previews/d3_4_20261105"
var shell
var checks := 0
var failures := 0


func _initialize() -> void: _run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func frames() -> void:
	for index: int in 8: await process_frame


func click_control(control: Control) -> void:
	var local := control.get_global_rect().get_center()
	var window := control.get_window()
	var at: Vector2
	if window != root:
		at = Vector2(window.position) + local * Vector2(window.size) / window.get_visible_rect().size
	else: at = shell.render_container.get_global_transform_with_canvas() * local
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await create_timer(0.6).timeout
	await frames()


func key_escape() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await create_timer(0.6).timeout
	await frames()


func screenshot(title: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEWS))
	root.get_texture().get_image().save_png(PREVIEWS.path_join(title + ("_2k" if "2k" in OS.get_cmdline_user_args() else "_720p") + ".png"))


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("D3-4界面专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(DIR)
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 720)
	shell = SHELL.instantiate()
	shell.run_slots.directory = DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	var source := "/private/tmp/project-card-d3-4-loop-test/project_card_run.json"
	check(DirAccess.copy_absolute(source, shell.run_slots.get_slot_path(0)) == OK, "复用已实际通关教程的临时档作为跳过资格来源")
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K if "2k" in OS.get_cmdline_user_args() else shell.DisplayMode.WINDOW_720P)
	await frames()
	check(await shell.start_slot(1), "新建后续存档，通过真实来源获得教程跳过资格")
	await frames()
	await click_control(shell._slot_progress_panel.find_child("MazeShopButton", true, false))
	check(is_instance_valid(shell._task_panel), "鼠标点击大厅进入任务商店")
	await screenshot("01_task_shop")
	var scroll = shell._task_panel.get_node("TaskDetailScroll")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await frames()
	check(scroll.scroll_vertical > 0 and shell._task_panel.find_child("SkipTutorialButton", true, false).is_visible_in_tree(), "长篇教程原文可以滚动至跳过按钮")
	await click_control(shell._task_panel.find_child("SkipTutorialButton", true, false))
	var skip = shell._task_panel.get_child(shell._task_panel.get_child_count() - 1)
	check(skip is ConfirmationDialog and skip.visible, "鼠标打开整项跳过确认")
	await screenshot("01b_skip_confirmation")
	await click_control(skip.get_ok_button())
	check(shell.slot_progress.profile.points == 1000 and shell.slot_progress.profile.tutorial.skipped, "实际确认跳过只发一次1000引导积分")
	await click_control(shell._slot_progress_panel.find_child("MazeShopButton", true, false))
	await click_control(shell._task_panel.find_child("Task_supply_first", true, false))
	check(shell._task_panel._detail_id == "supply_first", "鼠标选中M2任务详情")
	scroll = shell._task_panel.get_node("TaskDetailScroll")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await frames()
	await screenshot("02a_purchase_detail")
	await click_control(shell._task_panel.find_child("PurchaseTaskButton", true, false))
	var dialog = shell._task_panel.get_node_or_null("TaskPurchaseConfirmation")
	if dialog == null:
		await screenshot("02b_purchase_missing")
		check(false, "真实点击应打开购买确认")
		shell.free()
		quit(1)
		return
	check(dialog.visible and shell.slot_progress.profile.points == 1000, "真实购买弹窗出现，尚未扣款")
	await screenshot("02_purchase_confirmation")
	await click_control(dialog.get_cancel_button())
	check(shell.slot_progress.profile.points == 1000 and not shell.slot_progress.profile.tasks.has("supply_first"), "鼠标取消购买保持余额与资格")
	await click_control(shell._task_panel.find_child("PurchaseTaskButton", true, false))
	dialog = shell._task_panel.get_node("TaskPurchaseConfirmation")
	await click_control(dialog.get_ok_button())
	check(shell.slot_progress.profile.points == 0 and shell.slot_progress.profile.tasks.supply_first.purchased, "鼠标确认购买按目录扣款并保存")
	await key_escape()
	check(not is_instance_valid(shell._task_panel) and shell._slot_progress_panel.visible, "Esc从任务商店返回大厅")
	check(shell._slot_progress_panel.get_node("PointsBalance").text == "积分余额 0", "返回大厅立即同步已扣款余额")
	await click_control(shell._slot_progress_panel.find_child("NewRunButton", true, false))
	check(is_instance_valid(shell._task_panel) and shell._task_panel.selecting, "开始新局先进入任务选择")
	await screenshot("03_task_selection")
	var choice = shell._task_panel.get_node("MainTaskChoice")
	choice.select(1)
	await click_control(shell._task_panel.find_child("BeginSelectedRunButton", true, false))
	while shell.screen_transition.busy or shell._entering_slot: await process_frame
	await frames()
	var main = shell.main_screen
	check(is_instance_valid(main) and TaskCatalog.selected(main.profile_progress, "main") == "supply_first", "鼠标确认后手动开始携带M2的新局")
	if not is_instance_valid(main): shell.free(); quit(1); return
	var hint = main.get_node_or_null("TaskHint")
	if hint != null:
		await screenshot("04_task_hint")
		while is_instance_valid(hint): await create_timer(0.1).timeout
	await key_escape()
	var task_side = main._escape_pause_menu.find_child("RunTasksPage", true, false)
	var home = main._escape_pause_menu.find_child("PauseMenuPanel", true, false)
	check(task_side != null and task_side.is_visible_in_tree() and home.is_visible_in_tree(), "Esc打开时直接并列显示菜单和本局任务")
	check(not task_side.get_global_rect().intersects(home.get_global_rect()) and Rect2(0, 0, 1280, 720).encloses(task_side.get_global_rect()), "任务侧栏不覆盖菜单且完整位于720p逻辑画布内")
	check(main._escape_pause_menu.find_child("RunTasksButton", true, false) == null and task_side.find_child("TaskHelpBackButton", true, false) == null, "固定展开的任务侧栏没有重复入口或收起按钮")
	await click_control(main._escape_pause_menu.find_child("PauseSettingsButton", true, false))
	await key_escape()
	check(task_side.is_visible_in_tree() and home.is_visible_in_tree(), "从设置返回后任务侧栏仍默认展开")
	check(not main.task_help_text(false).contains("后勤机器人：“"), "任务侧栏只列目标进度奖励，不附带整段剧情脚本")
	await screenshot("05_run_task_page")
	await key_escape()
	check(not main._escape_pause_menu.is_menu_open() and not paused, "一次Esc关闭侧栏及暂停菜单，恢复游戏")
	shell.return_to_start_menu()
	await frames()
	shell.free()
	print("D3-4 UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
