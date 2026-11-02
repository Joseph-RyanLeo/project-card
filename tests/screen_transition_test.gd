extends SceneTree

const SCENE := preload("res://scenes/StartMenu.tscn")
const DIRECTORY := "/private/tmp/project-card-screen-transition-test"

var failures := 0
var animation_frames := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var shell = SCENE.instantiate()
	shell.run_slots.directory = DIRECTORY
	for index: int in 3:
		shell.run_slots.delete_slot(index)
	shell.run_slots.select_slot(0)
	root.add_child(shell)
	await process_frame
	var transition = shell.screen_transition
	create_timer(30.0).timeout.connect(func():
		push_error("转场测试超时：busy=%s alpha=%s paused=%s tweens=%s" % [transition.busy, transition._veil.modulate.a, paused, get_processed_tweens().size()])
		quit(1)
	)
	var frames: SpriteFrames = transition.WALK_FRAMES
	check(frames.get_frame_count(&"walk") == 6 and frames.get_frame_duration(&"walk", 0) == 0.5 and frames.get_animation_speed(&"walk") == 10.0, "六帧行走动画保留GIF的首帧50ms、其余100ms时序")
	transition._walker.frame_changed.connect(func(): animation_frames += 1)
	shell.start_menu.find_child("StartButton", true, false).pressed.emit()
	await process_frame
	check(transition.busy and shell.main_screen == null, "点击开始先淡出，黑场完成前不阻塞初始化")
	shell._request_start_slot(1)
	if not transition.is_covered:
		await transition.covered
	check(transition._veil.modulate.a == 1.0 and transition._loading.visible, "全黑后显示行走人物与加载提示")
	await create_timer(0.12).timeout
	check(animation_frames > 0 and transition.busy, "真实初始化与最短展示期间行走帧持续更新")
	if transition.busy:
		await transition.finished
	var main = shell.main_screen
	check(main != null and main.startup_complete and main.frame_budgeted_startup, "分帧初始化完成后才亮起游戏")
	check(shell.run_slots.selected_slot == 0 and not FileAccess.file_exists(shell.run_slots.get_slot_path(1)), "重复开始请求被屏蔽，不多建另一个档")
	check(not transition._veil.visible and not transition._loading.visible and not paused, "转场结束释放遮罩与输入，不改变暂停状态")
	check(not main._startup_runtime_snapshot.short_maze.is_empty(), "启动快照在迷宫初始化后捕获")
	print("Startup milliseconds: ", shell.last_startup_timings)
	main.set_world_view(main.WorldView.COLLECTION)
	check(not transition.busy, "战场与收藏保留上下移动，不触发黑场")
	await create_timer(main.VIEW_TWEEN_DURATION + main.VIEW_SETTLE_DURATION + 0.05).timeout
	main._on_escape_pause_menu_requested()
	check(paused and not transition.busy, "暂停弹窗保留原行为，不触发黑场")
	main._on_escape_pause_menu_requested()
	main._on_card_art_tuner_button_pressed()
	check(main.visible and transition.busy, "打开工具前保持旧界面，先淡出")
	await transition.finished
	check(shell.is_card_art_tuner_open() and not main.visible, "卡面调整器在黑场内创建后淡入")
	shell._card_art_tuner._on_back_button_pressed()
	await transition.finished
	check(main.visible and not shell.is_card_art_tuner_open(), "工具返回游戏也走黑场")
	var maze = main.maze_controller
	if not maze.hero.pending_talent_levels.is_empty():
		var id: String = maze.hero.get_pending_choices()[0]
		var talent_name: String = maze.rewards.config.talents[id].display_name
		var talent_button: Button
		for button: Button in maze._panel.find_children("*", "Button", true, false):
			if button.text.begins_with(talent_name):
				talent_button = button
				break
		check(talent_button != null, "真实初始天赋面板提供可选择按钮")
		if talent_button != null:
			talent_button.pressed.emit()
			check(not transition.busy and maze.hero.pending_talent_levels.is_empty(), "游戏内天赋选择立即提交，不触发黑场")
	check(maze.run.paths.size() == 3, "天赋选择后正常显示原三张路径候选")
	if maze.run.paths.size() == 3:
		var path_id: String = maze.run.paths[0].path_id
		maze._event_table.path_chosen.emit(path_id)
		check(not transition.busy and maze.run.selected_path.get("path_id", "") == path_id, "游戏内选择事件保留原演出，不触发黑场")
	await _test_battle_flow(shell)
	main._on_escape_pause_menu_requested()
	main._escape_pause_menu.main_menu_requested.emit()
	await process_frame
	check(transition.busy and paused, "暂停中返回菜单仍能启动淡出")
	await transition.finished
	check(shell.main_screen == null and shell.start_menu.visible and not paused, "黑场中保存释放游戏，菜单淡入后恢复输入")
	var invalid_path: String = shell.run_slots.get_slot_path(1)
	var invalid_file := FileAccess.open(invalid_path, FileAccess.WRITE)
	invalid_file.store_string("{\"schema_version\":999}")
	invalid_file.close()
	shell._request_start_slot(1)
	await transition.finished
	check(shell.main_screen == null and shell.start_menu.visible and not shell.start_menu._status.text.is_empty(), "加载损坏存档后淡回菜单并显示错误，不滞留黑场")
	check(not transition.busy and FileAccess.get_file_as_string(invalid_path) == "{\"schema_version\":999}", "加载失败仍恢复输入并保留原存档")
	shell.queue_free()
	await process_frame
	print("Screen transition failures: ", failures)
	quit(1 if failures else 0)


func _test_battle_flow(shell: Control) -> void:
	var main = shell.main_screen
	var maze = main.maze_controller
	maze.new_run(1707)
	if not maze.choose_talent("sentry_guard"):
		check(false, "真实战斗初始化天赋")
		return
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	owned.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 100.0)
	owned.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300.0)
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	for round_index: int in 2:
		if not maze.select_path(maze.run.paths[0].path_id) or not maze.complete_event(false):
			check(false, "真实战斗前事件推进")
			return
		check(not shell.screen_transition.busy, "游戏内事件结束沿用原流程，不触发黑场")
	if not maze.select_path(maze.run.paths[0].path_id) or not maze.leave_shop() or not maze.select_path(maze.run.paths[0].path_id):
		check(false, "真实战斗前商店与遭遇推进")
		return
	check(not shell.screen_transition.busy, "游戏内商店和遭遇切换不触发黑场")
	main.battle_controller.use_projectile_timing = false
	check(main.start_battle(1707, false) and not shell.screen_transition.busy, "游戏内开战直接进入真实战斗，不触发黑场")
	var batches := 0
	while main.battle_controller.is_running() and batches < 1200:
		main.battle_controller.resolve_next_batch()
		batches += 1
	check(main.battle_controller.current_result == BattleController.Result.PLAYER_VICTORY, "正式控制器完成真实战斗")
	await create_timer(0.7).timeout
	check(not shell.screen_transition.busy and main.current_phase == main.GamePhase.RESULT and maze.run.step == ShortMazeRunState.Step.BATTLE_RESULT, "游戏内战斗结束正常结算，不触发黑场")
	main.continue_next_level_button.pressed.emit()
	check(not shell.screen_transition.busy and maze.run.day == 2, "游戏内进入下一天直接推进一次，不触发黑场")


func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
