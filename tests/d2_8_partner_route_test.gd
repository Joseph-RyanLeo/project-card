extends SceneTree

const MainScene = preload("res://scenes/Main.tscn")
var assertions := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var legacy := ShortMazeRunState.new()
	legacy.initialize(1707)
	var legacy_start := legacy.capture_state()
	legacy_start.state_version = 1
	check(legacy.restore_state(legacy_start) and legacy.get_round_kind() == "free_event", "旧日初存档恢复到新版第一轮")
	var main: Control = MainScene.instantiate()
	main.short_maze_enabled = true
	main.run_save_path = "/private/tmp/project-card-partner-route.json"
	root.add_child(main)
	await process_frame
	var maze: ShortMazeController = main.maze_controller
	maze.new_run(1707)
	check(maze.choose_talent("sentry_guard"), "首日选择天赋")
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	# 固定强度的真实随从让测试关注八天事务，不伪造战斗结果。
	owned.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 100.0)
	owned.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300.0)
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	for day: int in range(1, 9):
		check(maze.run.day == day and maze.run.get_round_kind() == "free_event", "第%d天从随机事件开始" % day)
		var count_before: int = main.owned_card_collection.size()
		check(maze.select_path(maze.run.paths[0].path_id), "第%d天随机路径" % day)
		var gifts := 5 if day == 2 else (8 if day == 3 else 0)
		check(main.owned_card_collection.size() == count_before + gifts, "第%d天首事件礼包数量" % day)
		if day in [2, 3]:
			var count_after: int = main.owned_card_collection.size()
			check(main.load_run_from_path(main.run_save_path), "礼包提交存档可读回")
			owned = main.owned_card_collection.get_by_instance_id(owned.instance_id)
			check(main.owned_card_collection.size() == count_after, "读档不重复发礼包")
		check(maze.complete_event(false), "跳过随机事件")
		check(maze.run.get_round_kind() == "paid_event" and maze.select_path(maze.run.paths[0].path_id), "第二轮单卡强化")
		var old_value: float = owned.get_permanent_growth(OwnedCard.STAT_BASE_VALUE)
		check(maze.select_enhancement_card({"kind": &"card", "owned_card": owned}) and maze.apply_card_enhancement(0), "可强化已部署随从且不移除阵容")
		check(owned.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == old_value, "所有免费选项不增加行动数值")
		check(maze.run.get_round_kind() == "shop" and maze.select_path(maze.run.paths[0].path_id), "第三轮商店")
		check(main.ordinary_shop_open and maze.leave_shop(), "商店打开后正常离店")
		check(maze.run.get_round_kind() == "battle" and maze.select_path(maze.run.paths[0].path_id), "第四轮战斗")
		check(main.start_battle(day, false), "第%d天正式开战" % day)
		var batches := 0
		while main.battle_controller.current_result == main.BattleController.Result.NONE and batches < 1200:
			main.battle_controller.resolve_next_batch()
			batches += 1
		check(main.battle_controller.current_result == main.BattleController.Result.PLAYER_VICTORY, "第%d天战斗获胜" % day)
		main._show_battle_result(main.battle_controller.current_result)
		var choosing_talent := not maze.hero.pending_talent_levels.is_empty()
		check(
			maze.run.step == ShortMazeRunState.Step.BATTLE_RESULT
			and main.battle_result_panel.visible == (not choosing_talent)
			and (not choosing_talent or maze._panel.is_visible_in_tree()),
			"真实结算按升级状态显示天赋或结算面板"
		)
		var gold: int = main.run_reward_state.gold
		var xp: int = maze.hero.experience
		main._set_result_battlefield_visible(true)
		main._set_result_battlefield_visible(false)
		check(main.run_reward_state.gold == gold and maze.hero.experience == xp, "查看战场不重复结算")
		check(main.load_run_from_path(main.run_save_path) and maze.run.step == ShortMazeRunState.Step.BATTLE_RESULT, "结算磁盘存档读回")
		owned = main.owned_card_collection.get_by_instance_id(owned.instance_id)
		while not maze.hero.pending_talent_levels.is_empty():
			check(maze.choose_talent(maze.hero.get_pending_choices()[0]), "选择升级天赋")
		check(maze.continue_after_battle(), "第%d天结算继续" % day)
		await process_frame
	check(maze.run.step == ShortMazeRunState.Step.ENDED and maze.hero.experience == 16, "八天通关经验正确")
	check(not main.start_battle(1, false), "通关后不能开始第九战")
	main.queue_free()
	await process_frame
	print("合作伙伴路线闭环：%d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
