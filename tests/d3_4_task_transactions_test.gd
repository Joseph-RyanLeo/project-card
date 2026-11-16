extends SceneTree

const SHELL = preload("res://scenes/StartMenu.tscn")
const DIR := "/private/tmp/project-card-d3-4-transactions-test"
var checks := 0
var failures := 0


func _initialize() -> void: _run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("D3-4专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(DIR)
	var shell = SHELL.instantiate()
	shell.run_slots.directory = DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	await process_frame
	check(await shell.start_slot(0), "创建独立事务测试档")
	var p: ProfileProgress = shell.slot_progress
	# 只准备本专项所需的前置；M1→M2正常积分与挑战由task_loop_test覆盖。
	check(p.complete_tutorial() and p.purchase_catalog_task("supply_first") and p.complete_task("supply_first", TaskCatalog.rewards_for("supply_first")), "建立已完成M2的窄范围资格夹具")
	check(p.credit_once("side_test_fixture", 6000) and p.purchase_catalog_task("portable_runes"), "S2按目录价6000购买")
	check(p.select_catalog_tasks("", "portable_runes"), "仅携带支线合法")
	check(not p.select_catalog_tasks("portable_runes", ""), "支线不能放入主线位置")
	check(await shell.start_new_slot_run(), "真实开启S2专项局")
	await process_frame
	var main = shell.main_screen
	var maze = main.maze_controller
	var hint = main.get_node_or_null("TaskHint")
	if hint != null: hint.free()
	check(main.emblem_library.get_inventory_state().size() == 5 and not main.run_item_enabled("光贴纸"), "五枚试用元素贴纸已赠送，普通包未提前开放元素")
	check(not main.run_item_enabled("emblem_fusion"), "未携带S1且未解锁，融合功能关闭")
	while not maze.hero.pending_talent_levels.is_empty(): maze.choose_talent(String(maze.hero.get_pending_choices()[0]))
	while maze.run.get_round_kind() != "battle":
		check(maze.select_path(String(maze.run.paths[0].path_id)), "专项推进真实事件路径")
		if maze.run.get_round_kind() == "shop": check(maze.leave_shop(true), "专项正式离店")
		else: check(maze.complete_event(false, true), "专项正式离开事件")
	check(maze.select_path(String(maze.run.paths[0].path_id)), "专项选择真实战斗")
	var minions: Array[OwnedCard] = []
	for owned: OwnedCard in main.owned_card_collection.get_cards():
		if owned.card_data.card_type == CardData.CardType.MINION: minions.append(owned)
	# 用实际拥有的两张卡组成展开双卡小队，五枚试用贴纸贴到五个显现槽。
	var squad := SquadData.from_owned_card(minions[0])
	check(squad.insert_card(minions[1].get_battlefield_card(), 1, SquadData.TwoCardLayout.EXPANDED), "通过真实双卡展开形成五个可见槽")
	squad.bind_owned_card(minions[1].get_battlefield_card(), minions[1])
	var inventory: Array = main.emblem_library.get_inventory_state()
	var slots := squad.get_visible_rune_slots()
	for index: int in slots.size():
		var slot: Dictionary = slots[index]
		var owned := squad.get_owned_card(slot.card)
		var sticker: Dictionary = inventory[index].duplicate(true)
		sticker["element"] = EmblemLibraryData.RUNE_ELEMENT_BY_ID[StringName(sticker.emblem_id)]
		sticker.erase("storage")
		sticker.erase("drop_position")
		check(owned.set_rune_sticker(int(slot.rune_index), sticker), "将本局真实试用贴纸贴到显现符文槽")
		main.emblem_library.consume_returned(inventory[index])
	main.front_row.add_squad(squad, 0)
	check(main.start_battle(12003, false), "正式开始五元素小队战斗")
	check(main.profile_progress.run.tasks.side.progress.get("five_elements_pending", false) and not main.profile_progress.profile.tasks.portable_runes.completed, "战中只记待结算，不提前永久完成")
	var path: String = main.run_save_path
	check(main.save_run_to_path(path) == OK, "战中普通退出安全保存")
	var saved: Dictionary = RunSaveService.new().load_checkpoint(path).checkpoint.profile_progress
	check(not saved.run.tasks.side.progress.get("five_elements_pending", false) and not saved.profile.tasks.portable_runes.completed, "磁盘使用战前快照回滚本场目标")
	check(main.restart_battle() and not main.profile_progress.run.tasks.side.progress.get("five_elements_pending", false), "进程内重试同样回滚战中目标")
	check(main.start_battle(12003, false), "原战前队伍可重新参战")
	var original := FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	check(not main.finish_maze_run("abandoned"), "确认放弃保存失败不提交任务")
	check(not main.profile_progress.profile.tasks.portable_runes.completed and FileAccess.get_file_as_string(path) == original, "失败回退永久奖励，磁盘原样保留")
	DirAccess.remove_absolute(path + ".tmp")
	var ended: bool = main.finish_maze_run("abandoned")
	check(ended, "确认放弃正式提交本场已达标支线")
	if not ended: shell.free(); quit(1); return
	check(main.profile_progress.profile.tasks.portable_runes.completed and main.profile_progress.profile.unlocks.items.has("光贴纸"), "无需伪造胜利即可完成一场参战目标")
	check(not main.run_item_enabled("光贴纸"), "永久完成不改变当局冻结的普通获取范围")
	check(main.save_profile_action(main.profile_progress.show_selection) and main.save_profile_action(main.profile_progress.show_preview) and main.save_profile_action(main.profile_progress.confirm_collection), "确认放弃也完成正式局后流程")
	await process_frame
	shell.return_to_start_menu()
	await process_frame
	check(await shell.start_slot(0) and await shell.start_new_slot_run(), "S2完成后保存重读并开启新局")
	main = shell.main_screen
	var empty_stickers: Array[Dictionary] = []
	var candidates: Array = main.ordinary_shop_service._eligible_stickers(main._get_shop_sticker_definitions(), empty_stickers, empty_stickers)
	check(main.run_item_enabled("光贴纸") and candidates.any(func(item: Dictionary): return item.id == "光贴纸"), "下一局五元素按既有II级抽取权重进入纹章包")
	var gallery := preload("res://scripts/data/gallery_catalog.gd").new()
	check(gallery.visible_stickers(main.profile_progress.profile, "rune").size() == 5, "永久奖励与D3-3五元素贴纸图鉴一致")
	shell.return_to_start_menu()
	await process_frame
	check(await shell.start_slot(2) and shell.slot_progress.profile.points == 0 and not shell.slot_progress.profile.tasks.has("portable_runes"), "第三档隔离，没有S2资格或积分")
	shell.free()
	print("D3-4 transactions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
