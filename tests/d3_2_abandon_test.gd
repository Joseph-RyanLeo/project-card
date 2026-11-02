extends "res://tests/d3_2_flow_test.gd"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = DIR
	var read_mode := OS.get_cmdline_user_args().has("read")
	if not read_mode: shell.run_slots.delete_slot(1)
	root.add_child(shell)
	await frames()
	check(await shell.start_slot(1), "进入隔离放弃测试档")
	if read_mode:
		check(shell.main_screen == null and shell.slot_progress.run.stage == "summary" and shell.slot_progress.run.summary.outcome == "abandoned", "独立进程恢复放弃总结")
		var balance: int = shell.slot_progress.profile.points
		var receipt: String = "run_end:" + String(shell.slot_progress.run.id)
		check(shell.slot_progress.profile.receipts[receipt] == balance, "余额与本局唯一凭证一致")
		await click(button("SummaryCollectionButton"))
		var id: String = shell.slot_progress.run.candidates.keys()[0]
		shell._apply_collection_selection([{"candidate_id": id, "slot": 0}])
		await click(button("CollectionPreviewButton"))
		check(shell.slot_progress.profile.points == balance and shell.slot_progress.run.selection.size() == 1, "恢复后仍可非零选卡且不重发积分")
	else:
		check(await shell.start_new_slot_run(), "手动开始放弃测试局")
		var main: Control = shell.main_screen
		for day: int in range(1, 3):
			fight(main, true)
			check(main.maze_controller.continue_after_battle(true), "完成前两天")
		finish_events(main)
		var card: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
		# 使用真实实例数值准备一场不会立即结束的战斗。
		card.permanent_growth[&"base_value"] = 0
		main.front_row.clear_squads()
		main.front_row.add_squad(SquadData.from_owned_card(card), 0)
		var before_battles: float = card.lifetime_stats.get("battles", 0)
		var before_damage: float = card.lifetime_stats.get("damage_dealt", 0)
		check(main.start_battle(221, false), "第三天开始真实战斗")
		var batches := 0
		while main.battle_controller.owned_card_statistics.is_empty() and main.battle_controller.current_result == BattleController.Result.NONE and batches < 50:
			main.battle_controller.resolve_next_batch()
			batches += 1
		check(main.battle_controller.current_result == BattleController.Result.NONE, "已有实际战绩但战斗仍在进行")
		var path: String = main.run_save_path
		check(main.save_run_to_path(path) == OK, "普通战斗中保存成功")
		var saved: Dictionary = RunSaveService.new().load_checkpoint(path).checkpoint
		check(saved.profile_progress.run.stage == "active" and saved.profile_progress.profile.points == 0 and saved.short_maze.run.step == ShortMazeRunState.Step.BATTLE_PREPARE, "普通保存仍回战前，不结束或加分")
		var previous: Dictionary = main.profile_progress.capture_state()
		var disk := FileAccess.get_file_as_string(path)
		var journal: Dictionary = main.settlement_journal.capture_state()
		DirAccess.make_dir_absolute(path + ".tmp")
		check(not main.finish_maze_run("abandoned"), "战斗中放弃保存失败返回失败")
		check(main.profile_progress.capture_state() == previous and main.settlement_journal.capture_state() == journal and main.current_phase == main.GamePhase.BATTLE and main.maze_controller.run.step == ShortMazeRunState.Step.BATTLE_ACTIVE, "放弃失败回退阶段、积分凭证及本场提交标记，保留运行战斗")
		check(FileAccess.get_file_as_string(path) == disk, "放弃失败磁盘原样保留")
		DirAccess.remove_absolute(path + ".tmp")
		check(main.finish_maze_run("abandoned"), "同一进行中战斗可重试确认放弃")
		await frames()
		check(shell.slot_progress.run.stage == "summary" and shell.slot_progress.run.summary.outcome == "abandoned" and shell.slot_progress.run.summary.completed_days == 2 and shell.slot_progress.run.summary.protection == 0, "第三天放弃按前两天完成进度计分，无保护奖励")
		var owned: OwnedCard = main.owned_card_collection.get_by_instance_id(card.instance_id)
		check(owned.lifetime_stats.battles == before_battles + 1 and owned.lifetime_stats.get("damage_dealt", 0) >= before_damage, "确认放弃正式累计本场参战及已产生战绩")
		check(main.settlement_journal.is_committed(main._battle_snapshot.battle_instance_id), "本场账本正式提交")
		var balance: int = shell.slot_progress.profile.points
		var stats: Dictionary = owned.lifetime_stats.duplicate(true)
		check(main.finish_maze_run("abandoned") and shell.slot_progress.profile.points == balance and owned.lifetime_stats == stats, "重复放弃不重发积分也不重复累计战绩")
		await capture("11_battle_abandon")
		shell.return_to_start_menu()
		await frames()
	print("D3-2 abandon %s checks: %d, failures: %d" % ["read" if read_mode else "write", checks, failures])
	shell.free()
	await process_frame
	quit(1 if failures else 0)
