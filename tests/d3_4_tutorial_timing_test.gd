extends "res://tests/d3_4_task_loop_test.gd"

## 真实四天教程：逐段确认、正式事件／购买／部署／刮擦／战斗触发，不直接授予提示进度。
const TIMING_DIR := "/private/tmp/project-card-tutorial-timing-test"

func wait_ui() -> void:
	for index: int in 5: await process_frame

func expect_hint(id: String) -> void:
	await wait_ui()
	var hint = main.get_node_or_null("TaskHint")
	if hint == null:
		await create_timer(0.7).timeout
		hint = main.get_node_or_null("TaskHint")
	check(hint != null and hint.get_meta("hint_key", "") == "tutorial:step:" + id, "实际阶段仅出现提示：" + id)
	if hint != null:
		check(paused == (main.current_phase == main.GamePhase.BATTLE) and main._task_hint_pause_requested == paused, "战斗提示暂停时间轴，准备阶段保留界面动画")
		check(not hint.title.contains("1-") and not hint.title.contains("阶段"), "标题不展示脚本阶段标记")
		check(hint is Control and not hint is Window and hint.panel.get_theme_stylebox("panel").bg_color == hint.PANEL_FILL, "操作教学使用画布内浅色提示框")
		check(Rect2(0, 0, 1280, 720).encloses(hint.panel.get_rect()) and hint.focus_rect.has_area(), "提示框及对应目标保持在逻辑画布内：%s / %s" % [hint.panel.get_rect(), hint.focus_rect])
		check(not hint.instruction_label.text.contains("伊奥恩："), "操作说明不混入英雄对白")
		var hero_lines: Array = hint.content.dialogue.filter(func(line: Dictionary): return String(line.speaker).begins_with("伊奥恩"))
		if not hero_lines.is_empty():
			check(is_instance_valid(hint.speech) and hint.speech.get_script().resource_path == "res://scripts/ui/hero_speech_bubble.gd" and hint.speech._pinned, "伊奥恩对白复用现有英雄气泡并保持可读")
			check(not hint.panel.get_rect().intersects(hint.speech.get_rect()), "浅色说明框避让英雄对白气泡")
			print("TUTORIAL_SPEECH_METRICS: ", id, " scale=", hint.speech._display_scale, " logical=", hint.speech.size, " visual=", hint.speech._visual.get_rect(), " label=", hint.speech.text_label.get_rect(), " minimum=", hint.speech.text_label.get_minimum_size())
			check(hint.speech._visual.get_rect().encloses(hint.speech.text_label.get_global_rect()) and hint.speech.text_label.get_minimum_size().y <= hint.speech.text_label.size.y + 1, "完整教学对白保持在原生文字气泡内")

func acknowledge() -> void:
	var hint = main.get_node_or_null("TaskHint")
	if hint != null: hint.confirmed.emit()
	await wait_ui()
	check(not main._task_hint_pause_requested and not paused, "确认后恢复原有运行状态")

func capture_hint(name_text: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var hint = main.get_node_or_null("TaskHint")
	if hint != null and is_instance_valid(hint.speech) and is_instance_valid(hint.speech._text_reveal) and hint.speech._text_reveal.is_running(): await hint.speech._text_reveal.finished
	await create_timer(0.15).timeout
	var directory := "res://docs/previews/d3_4_20261105"
	var suffix := "_2k" if "2k" in OS.get_cmdline_user_args() else "_720p"
	root.get_texture().get_image().save_png(directory.path_join(name_text + suffix + ".png"))

func choose_pending() -> void:
	while not main.maze_controller.hero.pending_talent_levels.is_empty():
		check(main.maze_controller.choose_talent(String(main.maze_controller.hero.get_pending_choices()[0])), "正式选择待处理天赋")
	await wait_ui()

func advance_events() -> void:
	var maze = main.maze_controller
	while maze.run.get_round_kind() != "battle":
		var choice: Dictionary = maze.run.paths[0]
		check(maze.select_path(String(choice.path_id)), "继续真实事件")
		if maze.run.get_round_kind() == "shop":
			await create_timer(0.6).timeout
			shop_recruit()
			await wait_ui()
			if main.get_node_or_null("TaskHint") != null:
				await expect_hint("shop_purchased")
				await acknowledge()
			main._toggle_ordinary_shop(true)
			await create_timer(0.6).timeout
			check(not main.ordinary_shop_open and not main.ordinary_shop_panel.visible, "通过正式按钮路由完成离店及演出")
		else: check(maze.complete_event(false, true), "跳过当前奖励")
	check(maze.select_path(String(maze.run.paths[0].path_id)), "进入实际战斗准备")
	await wait_ui()

func resolve_battle() -> void:
	deploy()
	for region: String in ["front", "back"]:
		if not main.maze_controller.stock.is_empty(): main.maze_controller.deploy_sentry(String(main.maze_controller.stock[0].instance_id), region)
	check(main.start_battle(-1, false), "正式开战")
	var batches := 0
	while main.battle_controller.current_result == BattleController.Result.NONE and batches < 20000:
		main.battle_controller.resolve_next_batch()
		batches += 1
		if main.maze_controller.run.day == 4 and main.profile_progress.run.tasks.main.progress.get("tutorial_actions", {}).get("attack_observed", false):
			await wait_ui()
			if main.get_node_or_null("TaskHint") != null:
				await expect_hint("attack_observed")
				await acknowledge()
	check(main.battle_controller.current_result == BattleController.Result.PLAYER_VICTORY, "实际阵容战胜教程敌人")
	if main.current_phase != main.GamePhase.RESULT: main._show_battle_result(main.battle_controller.current_result)
	await choose_pending()

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("教程时机专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(TIMING_DIR)
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = TIMING_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K if "2k" in OS.get_cmdline_user_args() else shell.DisplayMode.WINDOW_720P)
	await process_frame
	check(await shell.start_slot(0), "创建新档")
	check(shell.slot_progress.select_catalog_tasks("tutorial", ""), "正式选择教程")
	check(await shell.start_new_slot_run(), "新档正常开启教程")
	main = shell.main_screen
	var maze = main.maze_controller
	maze.new_run(20261105)
	await choose_pending()
	check(main.get_node_or_null("TaskHint") == null, "初始包不提前弹教学或对白")
	check(maze.open_task_supply(), "真实打开初始补给")
	await create_timer(0.7).timeout
	check(main.get_node_or_null("TaskHint") == null, "进入包装检视不提前说开场对白")
	main._card_pack_opening.auto_tear()
	await create_timer(1.0).timeout
	await expect_hint("supplies")
	DirAccess.make_dir_absolute(main.run_save_path + ".tmp")
	main.get_node("TaskHint").confirmed.emit()
	await wait_ui()
	check(main.get_node("TaskHint").visible and not main.profile_progress.run.read_story_nodes.has("tutorial:step:supplies"), "剧情已阅保存失败时保留窗口及未阅状态")
	DirAccess.remove_absolute(main.run_save_path + ".tmp")
	await acknowledge()
	check(main.get_node_or_null("TaskHint") == null, "开包检视过程中不抢先弹下一段教学")
	main._close_card_inspection(true)
	check(main.get_node_or_null("TaskHint") == null, "事件牌堆教学已取消")
	check(maze.select_path(String(maze.run.paths[0].path_id)), "实际翻开福尔图纳的馈赠")
	check(maze.choose_story_option(0), "正式打开钱袋并投掷")
	if is_instance_valid(maze._story_roll): await maze._story_roll.finished
	check(maze.complete_event(true, true), "查看结果后继续")
	await expect_hint("event_reward")
	await acknowledge()
	check(maze.select_path(String(maze.run.paths[0].path_id)) and maze.complete_event(false, true), "完成付费事件轮")
	await expect_hint("shop_route")
	await acknowledge()
	check(maze.select_path(String(maze.run.paths[0].path_id)), "实际打开商店")
	await expect_hint("shop_entered")
	await acknowledge()
	shop_recruit()
	await wait_ui()
	if main.ordinary_shop_service.offers.any(func(offer: Dictionary): return offer.get("sold", false)):
		await expect_hint("shop_purchased")
		await acknowledge()
	else: check(main.get_node_or_null("TaskHint") == null, "未购入卡牌时不提前播放购买成功提示")
	main._toggle_ordinary_shop(true)
	await create_timer(0.6).timeout
	check(not main.ordinary_shop_open and maze.select_path(String(maze.run.paths[0].path_id)), "离店后选择敌人")
	await expect_hint("deploy")
	await acknowledge()
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/shieldwall_private.tres"))
	check(main._transfer_card({"kind": &"card", "source_type": &"collection", "card_data": owned.card_data, "owned_card": owned}, &"board", main.front_row), "用正式转移入口部署真实随从")
	await expect_hint("battle_ready")
	await acknowledge()
	await resolve_battle()
	await expect_hint("first_victory")
	await acknowledge()
	check(maze.continue_after_battle(true), "战后进入第二天，正式获得铁匠")
	await choose_pending()
	await expect_hint("smith")
	await capture_hint("06_smith_context")
	await acknowledge()
	check(main.get_node_or_null("TaskHint") == null, "领取刮刀后不提前讲战斗遮挡")
	owned = main.owned_card_collection.get_by_instance_id(owned.instance_id)
	main._open_card_inspection(owned.card_data, owned)
	await expect_hint("scraper_inspection")
	await acknowledge()
	await create_timer(0.5).timeout
	main._toggle_inspection_library()
	await create_timer(0.5).timeout
	main._toggle_rune_scraper_mode()
	check(main._rune_scraper_mode, "通过工具箱进入真实刮刀模式")
	var surface: InspectionCardSurface = main._inspection_surface
	var origin: Vector2 = main._inspection_card_view.rune_area_position
	var data: Dictionary = main._rune_scraper_drag_data
	var pointer: Vector2 = surface.get_global_transform_with_canvas() * (surface.PADDING + origin + Vector2(5, 5))
	var dirty := {}
	main._apply_rune_scrape_sample(pointer, data, dirty)
	# 结束一次确已产生擦痕的付费刮擦，沿用正式收刀入口完成揭晓。
	check(not main._rune_scraper_paid_slots.is_empty() or owned.rune_revealed[0], "真实刀头命中符文并产生擦痕")
	main._finish_rune_scraper_mode()
	await expect_hint("rune_revealed")
	await acknowledge()
	main._close_card_inspection(true)
	await advance_events()
	check(main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:shop_purchased"), "有足够金币后实际购买才归档招募反馈")
	await expect_hint("formation")
	await capture_hint("07_formation_context")
	await acknowledge()
	await resolve_battle()
	check(maze.continue_after_battle(true), "进入第三天")
	await choose_pending()
	await expect_hint("squad_intro")
	await acknowledge()
	for row: BattlefieldRow in [main.front_row, main.back_row]: row.clear_squads()
	var fighters: Array[OwnedCard] = []
	for card: OwnedCard in main.owned_card_collection.get_cards():
		if card.card_data.card_type == CardData.CardType.MINION: fighters.append(card)
	var squad := SquadData.from_owned_card(fighters[0])
	check(squad.insert_card(fighters[1].get_battlefield_card(), 1), "对真实随从执行小队组合")
	squad.bind_owned_card(fighters[1].get_battlefield_card(), fighters[1])
	main.front_row.add_squad(squad, 0)
	await expect_hint("squad_formed")
	await acknowledge()
	await advance_events()
	await resolve_battle()
	check(maze.continue_after_battle(true), "进入第四天")
	await choose_pending()
	await advance_events()
	await expect_hint("attack_intro")
	await acknowledge()
	await resolve_battle()
	check(main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:attack_observed"), "攻击命中后才归档表现教学")
	var loaded := RunSaveService.new().load_checkpoint(main.run_save_path)
	check(loaded.success and loaded.checkpoint.profile_progress.profile.tutorial.read_hints.has("tutorial:step:attack_observed"), "战中已阅保存不破坏正式战斗存档")
	maze.show_task_hint()
	check(main.get_node_or_null("TaskHint") == null, "重复刷新不弹已阅提示")
	shell.free()
	print("D3-4 tutorial timing: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
