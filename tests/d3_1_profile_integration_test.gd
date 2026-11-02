extends SceneTree

const SHELL = preload("res://scenes/StartMenu.tscn")
const DIR := "/private/tmp/project-card-d3-1-integration-test"
var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	root.size = Vector2i(1280, 720)
	var shell = SHELL.instantiate()
	shell.run_slots.directory = DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	await process_frame
	check(await shell.start_slot(0) and await shell.start_new_slot_run(), "真实显示壳创建首档并手动开启本局")
	await process_frame
	var main = shell.main_screen
	check(main.owned_card_collection.size() == 5, "D3-1不重复赠送伊奥恩初始5卡")
	check(main.profile_progress.profile.points == 0 and main.profile_progress.profile.unlocks.packs == ["ash_ledger"], "真实开局初始化独立局外基线")
	check(main.profile_progress.profile.discoveries.cards.size() == 5, "初始卡在首事件前提交发现")
	var path: String = main.run_save_path
	check(main.save_profile_action(main.profile_progress.credit_once.bind("fixture", 321)), "积分通过实际Main同档保存")
	var original := FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	check(not main.save_profile_action(main.profile_progress.credit_once.bind("failed", 500)) and main.profile_progress.profile.points == 321 and not main.profile_progress.profile.receipts.has("failed"), "积分动作保存失败回滚内存")
	check(FileAccess.get_file_as_string(path) == original, "动作失败不破坏磁盘有效数据")
	DirAccess.remove_absolute(path + ".tmp")
	# 真实商店事件中获得再卖出，保存中间状态，不能提前正式发现。
	var rare := load("res://resources/cards/heavy_knight.tres") as CardData
	var previous_collection: Dictionary = main.owned_card_collection.capture_state()
	var purchased: OwnedCard = main.owned_card_collection.create_card(rare)
	main.owned_card_collection.remove_by_instance_id(purchased.instance_id)
	check(main.save_run_to_path(path) == OK and main.profile_progress.run.pending_discoveries.cards.has("heavy_knight") and not main.profile_progress.profile.discoveries.cards.has("heavy_knight"), "事件中已卖出卡仍有待提交发现，尚不永久提交")
	check(main.save_run_to_path(path, true) == OK and main.profile_progress.profile.discoveries.cards.has("heavy_knight"), "事件结束后与本局同事务提交发现")
	# 失败购买应随收藏快照撤销，不能残留发现。
	var failed_card := load("res://resources/cards/militia.tres") as CardData
	var before_failed: Dictionary = main.owned_card_collection.capture_state()
	var failed_owned: OwnedCard = main.owned_card_collection.create_card(failed_card)
	main.owned_card_collection.restore_state(before_failed)
	check(not main.owned_card_collection.acquired_discoveries.has("militia"), "回滚获得时同时回滚待发现账本")
	var save := RunSaveService.new()
	# 通过现有事件调用链进入战斗，验证本局中断不永久提交发现。
	var maze = main.maze_controller
	while not maze.hero.pending_talent_levels.is_empty():
		check(maze.choose_talent(String(maze.hero.get_pending_choices()[0])), "选择实际起始天赋")
	while maze.run.get_round_kind() != "battle":
		check(maze.select_path(String(maze.run.paths[0].path_id)), "通过实际路径进入事件")
		if maze.run.get_round_kind() == "shop": check(maze.leave_shop(true), "实际离店调用提交发现")
		else: check(maze.complete_event(false, true), "实际事件结束调用提交发现")
	check(maze.select_path(String(maze.run.paths[0].path_id)), "通过实际路径选择战斗")
	var fighter: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	main.front_row.add_squad(SquadData.from_owned_card(fighter), 0)
	check(main.start_battle(12345, false), "建立真实战前本局及局外快照")
	main.profile_progress.note_discovery("cards", "uncommitted_battle_marker")
	check(main.save_run_to_path(path) == OK, "战斗中保存安全战前数据")
	var interrupted: Dictionary = save.load_checkpoint(path).checkpoint.profile_progress
	check(not interrupted.run.pending_discoveries.cards.has("uncommitted_battle_marker") and interrupted.profile.points == 321, "磁盘回滚本场未提交发现，退出不发积分")
	check(main.restart_battle() and not main.profile_progress.run.pending_discoveries.cards.has("uncommitted_battle_marker"), "进程内重试同样回滚本场局外待提交状态")
	check(main.start_battle(12345, false), "中断后继续相同战斗")
	var batches := 0
	while main.battle_controller.current_result == BattleController.Result.NONE and batches < 8000:
		main.battle_controller.resolve_next_batch()
		batches += 1
	check(main.battle_controller.current_result != BattleController.Result.NONE, "真实战斗得到结果")
	if main.current_phase != main.GamePhase.RESULT: main._show_battle_result(main.battle_controller.current_result)
	check(main.save_run_to_path(path) == OK and main.profile_progress.profile.points == 321, "单场正式战后保存不触发整局重复计分")
	# 用真实文件模拟Demo2：删掉不存在的D3字段与历史字段，不读取用户存档。
	var old: Dictionary = save.load_checkpoint(path).checkpoint
	old.erase("profile_progress")
	old.collection.erase("acquired_discoveries")
	for card: Dictionary in old.collection.cards:
		for key: String in ["acquired_at", "acquisition_source", "recruited_by", "lifetime_stats"]: card.erase(key)
	check(save.save_checkpoint(shell.run_slots.get_slot_path(1), old) == OK, "生成真实Demo2兼容夹具")
	shell.return_to_start_menu()
	await process_frame
	check(await shell.start_slot(1), "旧档可由正常菜单读入并补充D3基线")
	main = shell.main_screen
	var old_owned: OwnedCard = main.owned_card_collection.get_cards()[0]
	check(old_owned.acquired_at == 0 and old_owned.acquisition_source.is_empty() and old_owned.recruited_by.is_empty() and old_owned.lifetime_stats.is_empty(), "旧档未知获得时间/来源/战绩留空，不伪造")
	check(main.profile_progress.profile.points == 0 and main.profile_progress.profile.collection.is_empty() and not main.profile_progress.profile.tutorial.actually_completed, "旧档不凭空还原积分、收藏、教程记录")
	check(save.load_checkpoint(main.run_save_path).checkpoint.has("profile_progress"), "旧档迁移成功才写回新字段")
	# 验证阶段路由不会因Main初始化重新开局，也不覆盖另一档。
	var chosen := main.owned_card_collection.get_cards()[0] as OwnedCard
	var choice_id := String(chosen.instance_id)
	check(main.begin_run_collection(), "结束阶段入口冻结真实当前单卡候选并保存")
	check(main.save_profile_action(main.profile_progress.set_selection.bind([{"candidate_id": choice_id, "slot": 0}])), "所选单卡通过Main保存")
	check(main.save_profile_action(main.profile_progress.show_preview), "集合阶段通过Main保存")
	var run_id: String = main.profile_progress.run.id
	var maze_bytes := JSON.stringify(main.maze_controller.capture_state())
	shell.return_to_start_menu()
	await process_frame
	check(await shell.start_slot(1), "菜单重新进入待完成集合档")
	check(shell.slot_progress.run.stage == "preview" and shell.slot_progress.run.id == run_id and shell.slot_progress.run.selection[0].candidate_id == choice_id, "集合阶段、原run_id与所选单卡原样恢复")
	check(shell._slot_progress_panel != null and shell.main_screen == null, "待完成收藏直接恢复轻量阶段面板")
	check(not await shell.start_new_slot_run(), "待完成收藏阻止新局重置")
	var preview_path: String = shell.run_slots.get_slot_path(1)
	var preview_bytes := FileAccess.get_file_as_string(preview_path)
	DirAccess.make_dir_absolute(preview_path + ".tmp")
	var confirm := shell._slot_progress_panel.find_child("CollectionConfirmButton", true, false) as Button
	confirm.pressed.emit()
	check(shell.slot_progress.run.stage == "preview" and shell.slot_progress.profile.collection.is_empty() and shell._persistence_dialog.visible, "实际确认按钮保存失败，保留预览/选择/旧收藏")
	check(FileAccess.get_file_as_string(preview_path) == preview_bytes, "收藏提交失败原档字节不变")
	DirAccess.remove_absolute(preview_path + ".tmp")
	shell._persistence_dialog.hide()
	confirm.pressed.emit()
	await process_frame
	check(shell.slot_progress.run.stage == "hub", "实际最终确认按钮统一保存正式收藏")
	check(shell._slot_progress_panel != null, "确认后到存档内局外状态")
	var collection_id: String = shell.slot_progress.profile.collection[String(chosen.card_data.id)][0].archive_id
	check(await shell.start_new_slot_run(), "局外手动开启新局")
	main = shell.main_screen
	check(main.profile_progress.run.stage == "active" and main.visible and main.profile_progress.profile.collection[String(chosen.card_data.id)][0].archive_id == collection_id, "局外启动新局保留已收藏完整实例")
	shell.return_to_start_menu()
	await process_frame
	check(await shell.start_slot(0), "再回首档")
	check(shell.main_screen.profile_progress.profile.points == 321 and shell.main_screen.profile_progress.profile.collection.is_empty(), "另一档的积分与收藏没有混用")
	shell.return_to_start_menu()
	await process_frame
	# 损坏局外字段不能被加载覆盖，也不能被误当成空档。
	var broken := save.load_checkpoint(path).checkpoint as Dictionary
	broken.profile_progress.profile.points = -1
	check(save.save_checkpoint(path, broken) == OK, "构造局外损坏夹具")
	var broken_bytes := FileAccess.get_file_as_string(path)
	check(not await shell.start_slot(0) and shell.main_screen == null, "局外数据损坏时阻止进入，不以默认值覆盖")
	check(FileAccess.get_file_as_string(path) == broken_bytes, "损坏原档保留以便排查")
	broken.profile_progress = []
	check(save.save_checkpoint(path, broken) == OK and shell.run_slots.describe_slot(0).contains("无法读取"), "局外段类型损坏时菜单摘要也安全拒绝")
	for index: int in 3: shell.run_slots.delete_slot(index)
	check(not FileAccess.file_exists(path + ".diagnostics.jsonl"), "删除档位同时清除该档诊断文件")
	shell.queue_free()
	await process_frame
	print("D3-1 integration checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
