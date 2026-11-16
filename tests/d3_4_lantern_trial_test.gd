extends "res://tests/d3_4_task_loop_test.gd"

const LANTERN_DIR := "/private/tmp/project-card-d3-4-lantern-trial-test"


func pick_talents() -> void:
	while not main.maze_controller.hero.pending_talent_levels.is_empty():
		var choices: Array = main.maze_controller.hero.get_pending_choices()
		check(main.maze_controller.choose_talent("sentry_spell" if choices.has("sentry_spell") else "sentry_alchemy"), "选择咒／点金，保留青灯承载者的遗愿策略")
	dismiss_hints()


func sentry_regions() -> Array[String]:
	return ["back"]


func use_supplies() -> void:
	pass # 本专项把纹章留在工具箱，避免自动粘贴改变青灯承载者的生存策略。


func deploy() -> void:
	for row in [main.front_row, main.back_row]: row.clear_squads()
	var lantern: OwnedCard
	var fighters: Array[OwnedCard] = []
	for card: OwnedCard in main.owned_card_collection.get_cards():
		if card.card_data.card_type == CardData.CardType.MINION: fighters.append(card)
		if card.card_data.id in [&"extinguished_lantern", &"flickering_lantern", &"blazing_lantern"]: lantern = card
	if lantern == null: return
	var carrier: OwnedCard
	if lantern.card_data.id == &"extinguished_lantern":
		for card: OwnedCard in fighters:
			if card.card_data.id == &"town_priest": carrier = card
	else:
		fighters.sort_custom(func(a: OwnedCard, b: OwnedCard): return a.card_data.max_health + a.card_data.armor < b.card_data.max_health + b.card_data.armor)
		carrier = fighters[0]
	if carrier != null:
		var group := SquadData.from_owned_card(carrier)
		check(group.equip_item(lantern), "青灯装备到本局实际拥有的小队")
		var row = main.back_row if lantern.card_data.id == &"extinguished_lantern" else main.front_row
		row.add_squad(group, 0)
		print("LANTERN_CARRIER: ", carrier.card_data.id, " ", carrier.wound_slots)
	for card: OwnedCard in fighters:
		if card == carrier: continue
		var row = main.back_row if card.card_data.action_type in [CardData.ActionType.RANGED, CardData.ActionType.HEAL, CardData.ActionType.MAGIC] else main.front_row
		row.add_squad(SquadData.from_owned_card(card), row.get_squad_count())


func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("M3专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(LANTERN_DIR)
	root.size = Vector2i(1280, 720)
	shell = SHELL.instantiate()
	shell.run_slots.directory = LANTERN_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	await process_frame
	check(await shell.start_slot(0), "创建M3专项档")
	var p: ProfileProgress = shell.slot_progress
	check(p.complete_tutorial() and p.purchase_catalog_task("supply_first") and p.complete_task("supply_first", TaskCatalog.rewards_for("supply_first")), "准备M3已开放前置夹具")
	check(p.credit_once("lantern_fixture", 2000) and p.purchase_catalog_task("deep_survey") and p.select_catalog_tasks("deep_survey", ""), "按2000积分购买并携带M3")
	check(await shell.start_new_slot_run(), "真实开启M3")
	main = shell.main_screen
	main.maze_controller.new_run(20261105)
	check(main.save_run_to_path(main.run_save_path) == OK, "固定测试随机种子并保存真实开局")
	check(main.maze_controller.run.route_days == 8 and main.owned_card_collection.find_first_by_definition(load("res://resources/cards/extinguished_lantern.tres")) != null, "1-0获得熄灭青灯并走第一层八天")
	for day: int in 8:
		if not await play_day(): shell.free(); quit(1); return
		var lamps := []
		for card: OwnedCard in main.owned_card_collection.get_cards():
			if String(card.card_data.id).ends_with("_lantern"): lamps.append({"id": card.card_data.id, "progress": card.progress_by_source})
		print("LANTERN_DAY: ", day + 1, " ", lamps)
		if main.profile_progress.run.stage == "summary": break
	check(main.profile_progress.profile.tasks.deep_survey.completed, "八天实际挑战持有炽烈青灯完成M3")
	check(main.profile_progress.profile.unlocks.routes.has("second_floor") and main.owned_card_collection.find_first_by_definition(load("res://resources/cards/edwin_ash.tres")) != null, "M3永久开放第二层并获得尘灰")
	shell.free()
	print("D3-4 lantern trial: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
