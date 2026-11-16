extends SceneTree

## 使用真实显示壳、卡牌、战斗和临时存档验证任务链；不直接授予积分或永久解锁。
const SHELL = preload("res://scenes/StartMenu.tscn")
const DIR := "/private/tmp/project-card-d3-4-loop-test"
var failures := 0
var checks := 0
var shell
var main


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> bool:
	checks += 1
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
	return value


func dismiss_hints() -> void:
	var hint = main.get_node_or_null("TaskHint")
	if hint != null: hint.free()


func open_supply() -> bool:
	dismiss_hints()
	var result: bool = main.maze_controller.open_task_supply()
	if is_instance_valid(main._inspection_overlay): main._close_card_inspection(true)
	await process_frame
	dismiss_hints()
	return result


func pick_talents() -> void:
	while not main.maze_controller.hero.pending_talent_levels.is_empty():
		check(main.maze_controller.choose_talent(String(main.maze_controller.hero.get_pending_choices()[0])), "选择已开放天赋")
	dismiss_hints()


func deploy() -> void:
	for row in [main.front_row, main.back_row]: row.clear_squads()
	for owned: OwnedCard in main.owned_card_collection.get_cards():
		if owned.card_data.card_type != CardData.CardType.MINION: continue
		var row = main.back_row if owned.card_data.action_type in [CardData.ActionType.RANGED, CardData.ActionType.HEAL, CardData.ActionType.MAGIC] else main.front_row
		row.add_squad(SquadData.from_owned_card(owned), row.get_squad_count())


func use_supplies() -> void:
	var fighters: Array[OwnedCard] = []
	for owned: OwnedCard in main.owned_card_collection.get_cards():
		if owned.card_data.card_type == CardData.CardType.MINION: fighters.append(owned)
	for sticker: Dictionary in main.emblem_library.get_inventory_state():
		if sticker.get("element_sticker", false): continue
		var done := false
		for owned: OwnedCard in fighters:
			for slot: int in owned.emblem_slots.size():
				if owned.emblem_slots[slot].is_empty() and owned.set_emblem_slot(slot, sticker):
					main.emblem_library.consume_returned(sticker)
					done = true
					break
			if done: break


func shop_recruit() -> void:
	for index: int in main.ordinary_shop_service.offers.size():
		var offer: Dictionary = main.ordinary_shop_service.offers[index]
		if offer.get("sold", false) or int(offer.get("price", 0)) > main.run_reward_state.gold: continue
		if offer.kind == "card_pack": main._buy_shop_card_pack(index, offer)
		elif offer.kind == "single_card": main._buy_shop_single_card(index, offer)


func force_battle_save_failure() -> bool:
	return false


func sentry_regions() -> Array[String]:
	return ["front", "back"]


func play_day() -> bool:
	var maze = main.maze_controller
	pick_talents()
	while maze.run.get_round_kind() != "battle":
		var choice: Dictionary = maze.run.paths[0]
		for candidate: Dictionary in maze.run.paths:
			if candidate.get("reward", "") in ["pack", "minion", "gold"] and int(candidate.get("cost", 0)) <= main.run_reward_state.gold: choice = candidate
		if not check(maze.select_path(String(choice.path_id)), "从真实路径进入事件／商店"): return false
		if maze.run.get_round_kind() == "shop":
			shop_recruit()
			if not check(maze.leave_shop(true), "正式离店提交事务"): return false
		else:
			var accept: bool = choice.get("reward", "") in ["pack", "minion", "gold", "emblem"] and int(choice.get("cost", 0)) <= main.run_reward_state.gold
			if not check(maze.complete_event(accept, true), "正式结束事件"): return false
		dismiss_hints()
	if not check(maze.select_path(String(maze.run.paths[0].path_id)), "选择真实敌人"): return false
	deploy()
	use_supplies()
	for region: String in sentry_regions():
		if not maze.stock.is_empty(): maze.deploy_sentry(String(maze.stock[0].instance_id), region)
	dismiss_hints()
	if not check(main.start_battle(12345, false), "从准备阶段开始真实战斗"): return false
	var blocked := force_battle_save_failure()
	var before_points: int = main.profile_progress.profile.points
	var previous_bytes := FileAccess.get_file_as_string(main.run_save_path)
	if blocked: DirAccess.make_dir_absolute(main.run_save_path + ".tmp")
	var batches := 0
	while main.battle_controller.current_result == BattleController.Result.NONE and batches < 20000:
		main.battle_controller.resolve_next_batch()
		batches += 1
	check(main.battle_controller.current_result != BattleController.Result.NONE, "真实战斗产生结果")
	if main.current_phase != main.GamePhase.RESULT: main._show_battle_result(main.battle_controller.current_result)
	if blocked:
		check(not main.profile_progress.profile.tasks.tutorial.completed and main.profile_progress.profile.points == before_points, "教程终点保存失败时不提前完成任务或发1000积分")
		check(FileAccess.get_file_as_string(main.run_save_path) == previous_bytes, "战后保存失败保留战前有效档案")
		DirAccess.remove_absolute(main.run_save_path + ".tmp")
		check(main.save_run_to_path(main.run_save_path) == OK and main.profile_progress.profile.tasks.tutorial.completed and main.profile_progress.profile.points == before_points + 1000, "战后重试同一存档候选仅提交一次任务奖励")
	print("DAY_RESULT: ", maze.run.day, " ", main.battle_controller.current_result, " ending ", maze.run.battle_results)
	if not check(main.current_phase == main.GamePhase.RESULT and maze.run.step == ShortMazeRunState.Step.BATTLE_RESULT, "战后事务完成"): return false
	pick_talents()
	if not check(maze.continue_after_battle(true), "正式继续或局后结算"): return false
	await process_frame
	return true


func finish_collection() -> void:
	check(main.save_profile_action(main.profile_progress.show_selection), "打开本次收藏")
	check(main.save_profile_action(main.profile_progress.show_preview), "零选卡进入集合确认")
	check(main.save_profile_action(main.profile_progress.confirm_collection), "正式完成收藏返回大厅")
	await process_frame


func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("D3-4专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(DIR)
	root.size = Vector2i(1280, 720)
	shell = SHELL.instantiate()
	shell.run_slots.directory = DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	await process_frame
	if not check(await shell.start_slot(0), "新档正常进入大厅"): quit(1); return
	check(TaskCatalog.visible_tasks(shell.slot_progress).size() == 1, "新档只显示M1，未满足前置项隐藏")
	check(not shell.slot_progress.purchase_catalog_task("supply_first"), "前置与余额不足不能购买M2")
	check(not shell.slot_progress.select_catalog_tasks("", "tutorial"), "主线不能塞入支线位置")
	check(shell.slot_progress.select_catalog_tasks("tutorial", ""), "选择免费M1教程资格")
	if not check(await shell.start_new_slot_run(), "通过真实大厅开启教程"): quit(1); return
	await process_frame
	main = shell.main_screen
	check(main.maze_controller.run.route_days == 4 and main.owned_card_collection.size() == 0, "四天教程仅赠固定初始包，未重复赠5张")
	check(not main.run_item_enabled("scraper"), "1-0未提前开放无限刮刀")
	check(await open_supply() and main.owned_card_collection.size() == 5, "点击真实开包入口得到五张固定初始卡")
	check(not main.maze_controller.open_task_supply(), "重复开补给包拒绝")
	for day: int in 4:
		if not await play_day(): quit(1); return
		if day == 1:
			check(main.unlimited_scraper() and main.owned_card_collection.find_first_by_definition(load("res://resources/cards/anvil_margaret.tres")) != null, "完成第二天找到铁匠事件后领取玛格丽特和无限刮刀")
	if not check(main.profile_progress.profile.tutorial.actually_completed, "真实四天胜利完成教程"): quit(1); return
	check(main.profile_progress.profile.receipts.tutorial_guidance == 1000 and main.profile_progress.run.summary.total > 0, "正常计分另加同档一次1000引导分")
	check(not main.profile_progress.complete_tutorial(), "重复教程奖励拒绝")
	await finish_collection()
	var before: int = main.profile_progress.profile.points
	check(TaskCatalog.available(main.profile_progress, "supply_first"), "完成M1后开放M2购买")
	shell._open_task_shop()
	shell._task_panel.show_detail("supply_first")
	check(main.profile_progress.profile.points == before, "浏览详情不扣分")
	shell._task_panel._confirm_purchase("supply_first")
	var dialog = shell._task_panel.get_node("TaskPurchaseConfirmation")
	dialog.canceled.emit()
	await process_frame
	check(main.profile_progress.profile.points == before and not main.profile_progress.profile.tasks.has("supply_first"), "取消购买不扣积分")
	var path: String = main.run_save_path
	var bytes := FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	shell._purchase_task("supply_first")
	check(main.profile_progress.profile.points == before and not main.profile_progress.profile.tasks.has("supply_first"), "真实保存失败回滚余额和资格")
	check(FileAccess.get_file_as_string(path) == bytes, "失败购买保留原存档字节")
	DirAccess.remove_absolute(path + ".tmp")
	shell._persistence_dialog.hide()
	shell._task_panel._confirm_purchase("supply_first")
	shell._task_panel.get_node("TaskPurchaseConfirmation").confirmed.emit()
	await process_frame
	check(main.profile_progress.profile.points == before - 1000 and main.profile_progress.profile.tasks.supply_first.purchased, "真实确认购买扣1000并落盘")
	shell._purchase_task("supply_first")
	check(main.profile_progress.profile.points == before - 1000, "重复购买不重复扣分")
	shell._close_task_shop()
	check(main.profile_progress.select_catalog_tasks("supply_first", ""), "已购M2可携带")
	if not check(await shell.start_new_slot_run(), "开启M2真实新局"): quit(1); return
	main = shell.main_screen
	await process_frame
	check(main.owned_card_collection.size() == 6 and main.front_row.get_squad_count() == 1, "后勤机器人同一实例加入收藏并部署")
	check(main.run_pack_enabled("emblem_pack") and not main.profile_progress.profile.unlocks.packs.has("emblem_pack"), "试用普通纹章包不提前永久开放")
	check(await open_supply() and main.emblem_library.get_inventory_state().size() == 5, "M2开局纹章包按既有规格抽取5枚")
	# 此处验证终点任务奖励和存档。加强现有参战实例，避免随机事件和商店经济决定能否走到终点。
	var trial_leader: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	trial_leader.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 200)
	trial_leader.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 80)
	for day: int in 8:
		if not await play_day(): quit(1); return
		if main.profile_progress.run.stage == "summary": break
	check(main.profile_progress.profile.tasks.supply_first.completed, "M2第一层终点真实胜利完成任务")
	check(main.profile_progress.profile.unlocks.packs.has("emblem_pack"), "任务永久开放纹章包")
	await finish_collection()
	shell.return_to_start_menu()
	await process_frame
	check(await shell.start_slot(0), "正常菜单重新读取已完成档")
	check(shell.slot_progress.profile.tasks.supply_first.completed and shell.slot_progress.profile.unlocks.packs.has("emblem_pack"), "重读保留完成资格与奖励")
	check(await shell.start_new_slot_run(), "不带已完成任务开启下一局")
	main = shell.main_screen
	check(main.run_pack_enabled("emblem_pack") and main.ordinary_shop_service.sticker_packs_enabled, "后续新局普通获取正式开放纹章包")
	check(not main.profile_progress.run.tasks.has("main"), "完成任务不再自动携带")
	shell.return_to_start_menu()
	await process_frame
	check(await shell.start_slot(1) and shell.slot_progress.profile.points == 0 and not shell.slot_progress.profile.tasks.tutorial.completed, "第二档独立且可跳过资格仅来自实际通关")
	check(shell.slot_progress.profile.tutorial.skip_eligible_at_creation, "后续新档获得跳过教程资格")
	check(shell.slot_progress.complete_tutorial(true) and not shell.slot_progress.profile.tutorial.actually_completed and shell.slot_progress.profile.points == 1000, "跳过只发引导奖励不伪造通关")
	shell.free()
	print("D3-4 loop: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
