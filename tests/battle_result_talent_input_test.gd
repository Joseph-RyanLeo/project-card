extends SceneTree

## 真正走六天战斗或载入伙伴的结算存档，再用鼠标选择四项升级天赋和继续。
const DISPLAY := preload("res://scenes/GameDisplay.tscn")
const SAVE_PATH := "/private/tmp/project-card-talent-input-run.json"
const SOURCE_PATH := "/private/tmp/project-card-talent-input-source.json"
var shell: Control
var main: Control
var assertions := 0
var failures := 0

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("结算天赋输入专项超时"); quit(2))
	_run.call_deferred()

func check(value: bool, message: String) -> bool:
	assertions += 1
	print("PASS: " if value else "FAIL: ", message)
	if not value: failures += 1
	return value

func click(point: Vector2) -> void:
	var screen: Vector2 = shell.render_container.get_global_transform_with_canvas() * point
	Input.warp_mouse(screen)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = screen
		event.global_position = screen
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func talent_buttons() -> Array[Button]:
	var result: Array[Button] = []
	for child: Node in main.maze_controller._body.get_children():
		if child is Button: result.append(child)
	return result

func effective_z(item: CanvasItem) -> int:
	var result := item.z_index
	while item.z_as_relative and item.get_parent() is CanvasItem:
		item = item.get_parent() as CanvasItem
		result += item.z_index
	return result

func check_statistics_below_talent() -> void:
	var checked := 0
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]:
		for slot: BoardSlot in row.get_squads():
			var overlay: Control = slot._battle_result_overlay
			if not is_instance_valid(overlay): continue
			checked += 1
			check(effective_z(overlay) < effective_z(main.maze_controller._panel), "真实战后统计绘制在天赋面板下方：" + str(slot.name))
	check(checked > 0, "层级检查使用实际胜战生成的统计节点")

func build_six_day_checkpoint() -> bool:
	var maze: ShortMazeController = main.maze_controller
	maze.new_run(1707)
	if not maze.choose_talent("sentry_guard"): return false
	var owned := main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres")) as OwnedCard
	# 使用真实永久成长提高测试阵容强度，战斗结果仍由正式控制器计算。
	owned.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 100.0)
	owned.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300.0)
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	main.battle_controller.use_projectile_timing = false
	for day: int in range(1, 7):
		if not maze.select_path(maze.run.paths[0].path_id) or not maze.complete_event(false): return false
		if not maze.select_path(maze.run.paths[0].path_id) or not maze.complete_event(false): return false
		if not maze.select_path(maze.run.paths[0].path_id) or not maze.leave_shop(): return false
		if not maze.select_path(maze.run.paths[0].path_id) or not main.start_battle(day, false): return false
		var batches := 0
		while main.battle_controller.is_running() and batches < 1200:
			main.battle_controller.resolve_next_batch()
			batches += 1
		if main.battle_controller.current_result != BattleController.Result.PLAYER_VICTORY: return false
		main._show_battle_result(main.battle_controller.current_result)
		if day < 6 and not maze.continue_after_battle(): return false
		await process_frame
	return true

func finish() -> void:
	shell.queue_free()
	await process_frame
	print("战后升级输入专项：%d项，%d失败" % [assertions, failures])
	quit(failures)

func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = SAVE_PATH
	root.add_child(shell)
	await process_frame
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K if "--2k" in OS.get_cmdline_user_args() else shell.DisplayMode.WINDOW_1080P)
	for index: int in 8: await process_frame
	var checkpoint := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--checkpoint="): checkpoint = argument.trim_prefix("--checkpoint=")
	if checkpoint.is_empty():
		if not check(await build_six_day_checkpoint(), "正式路线六天实际胜战到达升级结算"):
			await finish()
			return
		check_statistics_below_talent()
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-talent-live-statistics-fixed.png")
		checkpoint = SAVE_PATH
	if not check(main.load_run_from_path(checkpoint), "载入真实第六天战后存档"):
		await finish()
		return
	check(main.save_run_to_path(SOURCE_PATH) == OK, "测试源快照独立保存")
	var maze: ShortMazeController = main.maze_controller
	check(maze.run.day == 6 and maze.hero.experience == 12 and maze.hero.pending_talent_levels == [4], "第六天经验12触发四级待选天赋")
	var choices := maze.hero.get_pending_choices()
	for choice_index: int in choices.size():
		check(main.load_run_from_path(SOURCE_PATH), "每项天赋从同一真实结算重新载入")
		await process_frame
		await process_frame
		var before: Dictionary = maze.capture_state()
		var gold: int = main.run_reward_state.gold
		var committed: Dictionary = main.settlement_journal.capture_state()
		if not check(not main.battle_result_panel.visible and maze._panel.is_visible_in_tree() and talent_buttons().size() == 4, "待选时完整显示四个天赋，结算面板不遮挡"):
			await RenderingServer.frame_post_draw
			shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-talent-before.png")
			await finish()
			return
		check(not main.continue_next_level_button.is_visible_in_tree() and not maze.continue_after_battle(), "天赋未选完仍禁止跨日")
		if choice_index == 0 and "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-talent-choice-fixed.png")
		if choice_index == 0:
			main.run_save_path = "/private/tmp/project-card-talent-missing-directory/run.json"
			await click(talent_buttons()[choice_index].get_global_rect().get_center())
			check(maze.capture_state() == before and not main.battle_result_panel.visible and maze._panel.is_visible_in_tree(), "天赋保存失败回退数据并保留可选界面")
			main.run_save_path = SAVE_PATH
		var point := talent_buttons()[choice_index].get_global_rect().get_center()
		await click(point)
		check(maze.hero.pending_talent_levels.is_empty() and maze.hero.selected_talents.get("4") == choices[choice_index], "真实鼠标选中天赋：" + choices[choice_index])
		check(maze.run.day == 6 and maze.hero.experience == 12 and main.run_reward_state.gold == gold and main.settlement_journal.capture_state() == committed, "选天赋不重复奖励、不提前跨日")
		check(main.battle_result_panel.is_visible_in_tree() and not maze._panel.visible and main.continue_next_level_button.is_visible_in_tree() and not main.continue_next_level_button.disabled, "选完自动恢复结算与可用的下一天按钮")
		if choice_index == 0 and "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-talent-result-fixed.png")
		check(main.load_run_from_path(SAVE_PATH) and maze.hero.pending_talent_levels.is_empty() and main.battle_result_panel.visible and main.continue_next_level_button.visible, "天赋已选的结算存档恢复继续入口")
		await process_frame
		await click(main.continue_next_level_button.get_global_rect().get_center())
		check(maze.run.day == 7 and main.current_phase == main.GamePhase.PREPARE and maze.run.paths.size() == 3, "真实点击继续进入第七天并生成路径")
		check(maze.hero.experience == 12 and main.run_reward_state.gold == gold, "继续下一天不重复发金币和经验")
		check(main.load_run_from_path(SAVE_PATH) and maze.run.day == 7 and maze.hero.pending_talent_levels.is_empty(), "第七天存档恢复后继续可玩")
	await finish()
