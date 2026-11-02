extends SceneTree

const SHELL = preload("res://scenes/StartMenu.tscn")
const DIR := "/private/tmp/project-card-d3-2-flow"
const PREVIEWS := "res://docs/previews/d3_2_20261102"
var shell: Control
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, title: String) -> void:
	checks += 1
	if value: print("PASS: ", title)
	else:
		failures += 1
		push_error(title)

func frames() -> void:
	for i: int in 4: await process_frame

func wait_inspection_closed(panel: Control) -> void:
	var deadline := Time.get_ticks_msec() + 2000
	while is_instance_valid(panel._inspection) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not is_instance_valid(panel._inspection), "关闭动画在限定时间内完成并释放检视")

func capture(title: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEWS))
	root.get_texture().get_image().save_png(PREVIEWS.path_join(title + ".png"))

func button(name: String) -> Button:
	return shell._slot_progress_panel.find_child(name, true, false) as Button

func click(target: Control, mouse_button: int = MOUSE_BUTTON_LEFT) -> void:
	check(target != null and (not target is BaseButton or not target.disabled), "可点击：" + (target.name if target != null else "缺失按钮"))
	if target == null: return
	await frames()
	var at := target.get_global_rect().get_center()
	var viewport := target.get_viewport()
	if viewport is Window and viewport != root:
		at += Vector2(viewport.position)
	else:
		at = shell.render_container.get_global_transform_with_canvas() * at
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = mouse_button
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await frames()

func finish_events(main: Control) -> void:
	var maze = main.maze_controller
	while not maze.hero.pending_talent_levels.is_empty(): maze.choose_talent(String(maze.hero.get_pending_choices()[0]))
	var guard := 0
	while maze.run.get_round_kind() != "battle" and guard < 4:
		guard += 1
		check(maze.select_path(String(maze.run.paths[0].path_id)), "真实事件路径")
		if maze.run.get_round_kind() == "shop": check(maze.leave_shop(true), "离店正式提交")
		else: check(maze.complete_event(false, true), "无成本结束事件")
	check(maze.select_path(String(maze.run.paths[0].path_id)), "选择真实敌人")

func fight(main: Control, won: bool) -> void:
	finish_events(main)
	if won:
		main.front_row.clear_squads()
		var fighter: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
		if fighter == null: fighter = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
		fighter.apply_permanent_growth(&"base_value", 150)
		fighter.apply_permanent_growth(&"max_health", 400)
		main.front_row.add_squad(SquadData.from_owned_card(fighter), 0)
	check(main.start_battle(998, false), "真实开战")
	var batches := 0
	while main.battle_controller.current_result == BattleController.Result.NONE and batches < 8000:
		main.battle_controller.resolve_next_batch()
		batches += 1
	check((main.battle_controller.current_result == BattleController.Result.PLAYER_VICTORY) == won, "真实战斗按阵容产生胜负")
	main._show_battle_result(main.battle_controller.current_result)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	await frames()
	check(await shell.start_slot(0) and await shell.start_new_slot_run(), "建立真实档位和本局")
	var main: Control = shell.main_screen
	var path: String = main.run_save_path
	# 普通退出不结算；前两天确认放弃保留实际发现而没有分数和候选。
	var purchased: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/heavy_knight.tres"))
	check(main.save_run_to_path(path) == OK and main.profile_progress.run.stage == "active" and main.profile_progress.profile.points == 0, "普通保存不结束整局")
	main._on_escape_pause_menu_requested()
	var abandon := main._escape_pause_menu.find_child("AbandonRunButton", true, false) as Button
	await click(abandon)
	check(main.profile_progress.run.stage == "active", "点击放弃仅弹确认，不提前结束")
	var confirmation := main._escape_pause_menu.find_child("AbandonConfirmation", true, false) as ConfirmationDialog
	check(confirmation != null, "实际暂停菜单显示明确放弃确认")
	confirmation.confirmed.emit()
	await frames()
	check(shell.slot_progress.run.stage == "summary" and shell.slot_progress.profile.points == 0 and shell.slot_progress.run.candidates.is_empty(), "第一天确认放弃进入零分总结")
	check(shell.slot_progress.profile.discoveries.cards.has(String(purchased.card_data.id)), "未完事件实际获得的发现保留")
	await click(button("SummaryCollectionButton"))
	await click(button("CollectionPreviewButton"))
	check(shell.slot_progress.run.stage == "preview", "零张仍进入集合预览")
	await capture("00_empty_preview")
	await click(button("CollectionConfirmButton"))
	check(shell.slot_progress.run.stage == "hub", "零张最终确认回大厅")
	check(await shell.start_new_slot_run(), "完成收藏后开始新局")
	main = shell.main_screen
	# 八天正常通关使用真实正式资源、事件和战斗；只用成长构造稳定胜利输入。
	for day: int in range(1, 9):
		fight(main, true)
		while not main.maze_controller.hero.pending_talent_levels.is_empty(): main.maze_controller.choose_talent(String(main.maze_controller.hero.get_pending_choices()[0]))
		check(main.maze_controller.continue_after_battle(true), "战后继续或结束第%d天" % day)
		await frames()
	check(shell.slot_progress.run.stage == "summary" and shell.slot_progress.run.summary.outcome == "cleared", "第八天终点正常通关进入总结")
	check(shell.slot_progress.run.summary.completed_days == 8 and shell.slot_progress.run.summary.multiplier_tenths == 27, "八天一Boss与两保护倍率2.7")
	var balance: int = shell.slot_progress.profile.points
	check(balance > 0 and main.finish_maze_run() and shell.slot_progress.profile.points == balance, "重复结束不重复入账")
	var fighter: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	check(fighter.lifetime_stats.get("battles", 0) == 8 and fighter.lifetime_stats.get("damage_dealt", 0) > 0, "真实八场累计单卡战绩")
	await capture("01_summary")
	await click(button("ScoreDetailsButton"))
	check(shell._slot_progress_panel._details.visible, "默认总览可展开逐卡明细")
	await capture("02_details")
	# 保存失败结算保护由后面的失败局验证；当前总结退出重进。
	shell.return_to_start_menu()
	await frames()
	check(await shell.start_slot(0) and shell.slot_progress.run.stage == "summary" and shell.main_screen == null and shell.slot_progress.profile.points == balance, "重进恢复已入账总结，不预建本局")
	await click(button("SummaryCollectionButton"))
	check(shell.slot_progress.run.stage == "selection", "总结真实鼠标入口进入候选页")
	check(not await shell.start_new_slot_run(), "收藏未完成禁止新局")
	await capture("03_candidates")
	var id: String = shell.slot_progress.run.candidates.keys()[0]
	var before: Dictionary = shell.slot_progress.run.candidates.duplicate(true)
	await click(shell._slot_progress_panel._cells[id].view, MOUSE_BUTTON_RIGHT)
	var inspect := shell._slot_progress_panel.find_child("CollectionInspection", true, false) as Control
	check(inspect != null and inspect.visible, "真实候选按钮打开只读检视")
	await create_timer(1.1).timeout
	await capture("04_inspection")
	var tabs: TabBar = inspect.find_child("InspectionTabs", true, false)
	tabs.current_tab = 1
	await frames()
	check(shell.slot_progress.run.candidates == before, "切换积分页只改显示，不改候选实例")
	await click(inspect.find_child("CloseCollectionInspection", true, false))
	await wait_inspection_closed(shell._slot_progress_panel)
	await click(shell._slot_progress_panel._cells[id].view)
	check(shell.slot_progress.run.selection.size() == 1 and shell.slot_progress.run.candidates == before, "鼠标选择非零候选并保存，候选不被检视修改")
	await click(button("CollectionPreviewButton"))
	check(shell.slot_progress.profile.collection.is_empty() and shell.slot_progress.run.stage == "preview", "集合预览未提前入藏")
	await capture("05_preview")
	shell.return_to_start_menu()
	await frames()
	check(await shell.start_slot(0) and shell.slot_progress.run.stage == "preview" and shell.slot_progress.run.selection.size() == 1, "重进恢复非零集合与替换计划")
	await click(button("CollectionBackButton"))
	check(shell.slot_progress.run.stage == "selection", "集合可返回改选")
	await click(button("CollectionPreviewButton"))
	var disk := FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	await click(button("CollectionConfirmButton"))
	check(shell.slot_progress.run.stage == "preview" and shell.slot_progress.profile.collection.is_empty() and FileAccess.get_file_as_string(path) == disk, "最终保存失败保留阶段和旧收藏，磁盘不变")
	DirAccess.remove_absolute(path + ".tmp")
	var error_dialog := shell.find_child("PersistenceErrorDialog", true, false) as AcceptDialog
	if error_dialog != null: error_dialog.hide()
	# 关闭实际错误窗口后重试。
	for child: Node in shell.get_children():
		if child is AcceptDialog: child.hide()
	await click(button("CollectionConfirmButton"))
	check(shell.slot_progress.run.stage == "hub" and shell.slot_progress.profile.collection.size() == 1 and shell.slot_progress.profile.points == balance, "最终确认统一入藏回大厅，不再发分")
	await capture("06_hub")
	check(await shell.start_new_slot_run(), "入藏后新局保留旧收藏")
	main = shell.main_screen
	for day: int in range(1, 4):
		fight(main, false)
		if day < 3: check(main.maze_controller.continue_after_battle(true), "保护普通失败仍可继续")
	var before_profile: Dictionary = main.profile_progress.capture_state()
	disk = FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	check(not main.maze_controller.continue_after_battle(true), "整局失败结算保存失败可重试")
	check(main.profile_progress.capture_state() == before_profile and FileAccess.get_file_as_string(path) == disk, "失败结算完整回退余额、凭证、阶段和候选")
	DirAccess.remove_absolute(path + ".tmp")
	check(main.maze_controller.continue_after_battle(true), "重试失败结算成功")
	await frames()
	check(shell.slot_progress.run.stage == "summary" and shell.slot_progress.run.summary.outcome == "failed" and shell.slot_progress.run.summary.completed_days == 2, "第三败整局失败，当天不算完成")
	await capture("07_failed")
	print("D3-2 flow checks: %d, failures: %d" % [checks, failures])
	shell.free()
	await process_frame
	quit(1 if failures else 0)
