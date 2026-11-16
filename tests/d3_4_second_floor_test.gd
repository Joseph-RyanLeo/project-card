extends "res://tests/d3_4_task_loop_test.gd"

const FLOOR_DIR := "/private/tmp/project-card-d3-4-second-floor-test"


func pick_talents() -> void:
	while not main.maze_controller.hero.pending_talent_levels.is_empty():
		var choices: Array = main.maze_controller.hero.get_pending_choices()
		var id: String = "three_celestial_marks" if choices.has("three_celestial_marks") else String(choices[0])
		check(main.maze_controller.choose_talent(id), "正式选择已接入天赋，至高天暂缓")
	dismiss_hints()


func play_trial(id: String, code: String) -> void:
	check(shell.slot_progress.select_catalog_tasks(id, ""), "携带" + code)
	check(await shell.start_new_slot_run(), "正式开启" + code)
	await process_frame
	main = shell.main_screen
	check(main.maze_controller.run.route_days == 16, code + "使用两层正式路线")
	check(main.profile_progress.run.supplies.size() == 1, code + "1-0赠一个指定大包")
	if id == "temple_boon":
		check(main.front_row.get_squad_count() == 1 and main.owned_card_collection.find_first_by_definition(load("res://resources/cards/il_ancient_speaker.tres")) != null, "M5伊尔同一实例直接上场并留在收藏")
	while not main.profile_progress.run.supplies.is_empty(): check(await open_supply(), "实际打开任务大包")
	for day: int in 16:
		if not await play_day(): return
		if day == 7:
			check(main.maze_controller.run.day == 9 and main.profile_progress.run.supplies.size() == 2, code + "2-0准确发两个大包")
			check(main.maze_controller.floor_number() == 2 and main.profile_progress.run.stage == "active", "第一层胜利后进入第二层，未提前结束")
			var saved_supplies: Array = main.profile_progress.run.supplies.duplicate(true)
			shell.return_to_start_menu()
			await process_frame
			check(await shell.start_slot(0), "2-0礼包中断后正常读档")
			main = shell.main_screen
			check(main.profile_progress.run.supplies == saved_supplies, "两大包内容与身份读档不重抽／重发")
			while not main.profile_progress.run.supplies.is_empty(): check(await open_supply(), "实际打开2-0指定大包")
		if main.profile_progress.run.stage == "summary": break
	check(main.profile_progress.profile.tasks[id].completed, code + "第二层Boss真实胜利完成")
	check(main.profile_progress.profile.unlocks.packs.has("ironwall_inscription" if id == "ironwall_support" else "silvermoon_chapter"), code + "永久开放对应卡包")
	await finish_collection()


func _run() -> void:
	create_timer(180).timeout.connect(func(): push_error("两层专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(FLOOR_DIR)
	root.size = Vector2i(1280, 720)
	shell = SHELL.instantiate()
	shell.run_slots.directory = FLOOR_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	await process_frame
	check(await shell.start_slot(0), "建立两层专项独立档")
	var p: ProfileProgress = shell.slot_progress
	# 前置与购买积分仅是本专项夹具；本测试仍通过16场真实战斗完成每项试炼。
	check(p.complete_tutorial() and p.purchase_catalog_task("supply_first") and p.complete_task("supply_first", TaskCatalog.rewards_for("supply_first")), "准备已完成M2的范围夹具")
	check(p.credit_once("floor_fixture", 5000) and p.purchase_catalog_task("deep_survey") and p.complete_task("deep_survey", TaskCatalog.rewards_for("deep_survey")), "准备第二层资格夹具")
	check(p.purchase_catalog_task("ironwall_support"), "M4按3000积分购买资格")
	await play_trial("ironwall_support", "M4")
	if failures: shell.free(); quit(1); return
	p = shell.slot_progress
	check(TaskCatalog.available(p, "temple_boon"), "M5按用户修正的M4前置出现")
	check(p.credit_once("temple_fixture", 8000) and p.purchase_catalog_task("temple_boon"), "M5按8000积分购买资格")
	await play_trial("temple_boon", "M5")
	shell.free()
	print("D3-4 second floor: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
