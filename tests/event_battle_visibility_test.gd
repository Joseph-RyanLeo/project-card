extends "res://tests/event_cards_test.gd"

## 真实迷宫路径、战斗与结算，覆盖准备阶段隐藏父节点后未恢复的回归。
const BATTLE_SAVE_PATH := "/private/tmp/project-card-event-battle-visibility.json"
const PREPARE_SAVE_PATH := "/private/tmp/project-card-event-battle-visibility-prepare.json"


func _capture_battle() -> void:
	if "--capture-battle-visibility" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-event-battle-visible.png")


func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = BATTLE_SAVE_PATH
	root.add_child(shell)
	await process_frame
	maze = main.maze_controller
	_deal("loose_coins")
	check(maze.select_path("loose_coins") and maze.complete_event(), "完成真实随机事件")
	check(maze.select_path(maze.run.paths[0].path_id) and maze.complete_event(false), "完成强化轮")
	check(maze.select_path(maze.run.paths[0].path_id), "选中商店牌")
	maze.enter_selected_shop()
	main._toggle_ordinary_shop()
	check(maze.run.get_round_kind() == "battle", "离店进入战斗选牌")
	check(maze.select_path(maze.run.paths[0].path_id), "战斗牌生成真实敌方阵容")
	var enemy_section: Control = main.get_node("WorldContent/EnemyBoardSection")
	var enemy_count: int = main.enemy_front_row.get_squad_count() + main.enemy_back_row.get_squad_count()
	check(enemy_count > 0 and not enemy_section.visible, "准备阶段保留敌方数据并隐藏精确阵容")
	var player: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	player.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300.0)
	player.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 10.0)
	main.front_row.add_squad(SquadData.from_owned_card(player), 0)
	check(main.start_battle(-1, false), "实际开战成功")
	await process_frame
	check(main.battle_controller.enemy_states.size() == enemy_count, "敌方真实战斗单元数量与遭遇相符")
	check(enemy_section.is_visible_in_tree(), "开战时恢复敌方场景父节点显示")
	check(not maze._panel.visible, "开战时事件牌面板收起")
	for row: BattlefieldRow in [main.enemy_front_row, main.enemy_back_row]:
		for slot: BoardSlot in row.get_squads():
			check(slot.is_visible_in_tree(), "敌方每个实际小队在场上可见")
	await _capture_battle()
	check(main.save_run_to_path(PREPARE_SAVE_PATH) == OK, "保存真实战前恢复点")
	var damaged_enemy := false
	var batches := 0
	while main.battle_controller.current_result == main.BattleController.Result.NONE and batches < 1200:
		main.battle_controller.resolve_next_batch()
		for state: BattleSquadState in main.battle_controller.enemy_states:
			if float(state.get_battle_statistics().damage_taken) > 0.0:
				damaged_enemy = true
		batches += 1
	check(damaged_enemy, "实际攻击命中敌方并产生真实受伤统计")
	check(main.battle_controller.current_result != main.BattleController.Result.NONE, "实际战斗能正常结束")
	main._show_battle_result(main.battle_controller.current_result)
	main._set_result_battlefield_visible(true)
	await process_frame
	check(main.current_phase == main.GamePhase.RESULT and enemy_section.is_visible_in_tree(), "战后查看战场仍显示敌方场景")
	check(main.load_run_from_path(PREPARE_SAVE_PATH), "战斗存档回到本场准备")
	check(maze.run.step == ShortMazeRunState.Step.BATTLE_PREPARE and not enemy_section.visible, "读档后准备阶段仍隐藏精确阵容")
	check(main.start_battle(-1, false), "读档重试同一真实遭遇")
	await process_frame
	check(enemy_section.is_visible_in_tree() and not main.battle_controller.enemy_states.is_empty(), "读档重试再次显示真实敌人")
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(BATTLE_SAVE_PATH)
	DirAccess.remove_absolute(PREPARE_SAVE_PATH)
	print("事件战斗可见性：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
