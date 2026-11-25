extends "res://tests/event_prompt_dismiss_test.gd"

## 真实准备、英雄切视角、部署与开战；只覆盖首战教学，不运行整段教程。
const DEPLOY_DIR := "/private/tmp/project-card-deployment-tutorial-test"


func capture_pack(label: String) -> void:
	if DisplayServer.get_name() != "headless": await super.capture_pack(label)


func check_soft_hint(hint: Control, title_text: String) -> void:
	check(hint._surface.get_children().all(func(child: Node): return not child is ColorRect), title_text + "不创建背景暗幕")
	check(is_equal_approx(hint.panel.position.x, 12) and absf(hint.panel.get_rect().end.y - 708) <= 1 and Rect2(0, 0, 1280, 720).encloses(hint.panel.get_rect()), title_text + "完整位于左下角")
	check(not paused and not main._task_hint_pause_requested, title_text + "不暂停准备或阻止继续部署")


func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("部署教学专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(DEPLOY_DIR)
	Effects.load_saved(DEPLOY_DIR.path_join("effects.cfg"))
	Effects.reset_defaults()
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = DEPLOY_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await frames()
	check(await shell.start_slot(0), "创建隔离部署测试档")
	check(shell.slot_progress.select_catalog_tasks("tutorial", "") and await shell.start_new_slot_run(), "正式进入教程")
	main = shell.main_screen
	var maze = main.maze_controller
	while shell.screen_transition.busy: await process_frame
	if "--replay" in OS.get_cmdline_user_args():
		check(main._developer_event_test.start_task("tutorial").is_empty(), "通过开发重玩入口进入教程副本")
	if is_instance_valid(maze._initial_pack_drop): await maze._initial_pack_drop.finished
	check(main.save_profile_action(func():
		for id: String in ["supplies", "event_reward", "shop_route", "shop_entered", "militia_inspect", "militia_keywords", "militia_neighbor"]:
			main.profile_progress.record_hint_read("tutorial:step:" + id, TaskCatalog.tutorial_hint(id), {"story": true, "teaching": true})
		return true), "准备已阅事件和关键词的隔离存档")
	check(maze.open_task_supply(), "通过实际初始包获得本局卡牌")
	await create_timer(0.7).timeout
	main._card_pack_opening.auto_tear()
	await create_timer(1.0).timeout
	main._close_card_inspection(true)
	await create_timer(0.4).timeout
	while not maze.hero.pending_talent_levels.is_empty(): maze.choose_talent(String(maze.hero.get_pending_choices()[0]))
	while maze.run.get_round_kind() != "battle":
		check(maze.select_path(String(maze.run.paths[0].path_id)), "正式选择首战前事件")
		if maze.run.get_round_kind() == "shop":
			if is_instance_valid(main._shop_open_tween) and main._shop_open_tween.is_running(): await main._shop_open_tween.finished
			await click_control(main._shop_leave_button)
			check(not main.ordinary_shop_open and not main.ordinary_shop_panel.visible, "点击离店按钮关闭真实商店及其动画")
		else: check(maze.complete_event(false, true), "正式完成事件")
	check(maze.select_path(String(maze.run.paths[0].path_id)), "正式选择战斗遭遇")
	var hint := await expected_hint("deploy_view")
	check(main.current_world_view == main.WorldView.BATTLEFIELDS and hint.instruction_label.text.contains("英雄按钮"), "上半视角先提示点击英雄按钮，不提前提示拖拽")
	check(maze._panel.is_visible_in_tree() and maze._panel.get_parent() == main.world_content and maze._panel.position == Vector2(189, 0), "战斗遭遇板一开始就固定在世界顶部")
	check(hint.silhouette_target == main.player_avatar_button and hint._focus_material.get_shader_parameter("use_silhouette") and hint.find_child("HintTargetOutline", true, false) == null, "英雄教学沿当前英雄图集帧生成轮廓柔光")
	var breath := float(hint._focus_material.get_shader_parameter("focus_breath"))
	await create_timer(0.15).timeout
	check(not is_equal_approx(breath, float(hint._focus_material.get_shader_parameter("focus_breath"))), "教学光晕连续呼吸")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-six-ui-hero-breath.png")
	main._on_escape_pause_menu_requested()
	while main._escape_pause_menu.is_transitioning(): await process_frame
	main._escape_pause_menu.open_teaching()
	main._escape_pause_menu.find_child("TaskHelpBackButton", true, false).pressed.emit()
	while main._escape_pause_menu.is_transitioning(): await process_frame
	check(not main._escape_pause_menu.is_menu_open() and not paused, "玩法教学返回按钮直接恢复游戏")
	await click_control(main.player_avatar_button)
	hint = await expected_hint("deploy")
	check(main.current_world_view == main.WorldView.COLLECTION and hint.instruction_label.text.contains("拖到"), "实际点击英雄切换完视角才出现拖动部署教学")
	check(maze._panel.get_parent() == main.world_content and maze._panel.position == Vector2(189, 0) and maze._panel.global_position.y < -350, "下半视角遭遇板留在世界顶部，不跟随屏幕")
	check_soft_hint(hint, "拖动部署提示")
	await capture_pack("13_deployment_hint_right")
	# 上下切换并刷新，始终保持同一块遭遇板的世界位置。
	await click_control(main.player_avatar_button)
	maze.refresh()
	check(maze._panel.get_parent() == main.world_content and maze._panel.position == Vector2(189, 0), "返回上半并刷新不把遭遇板重新固定到屏幕")
	await click_control(main.player_avatar_button)
	check_soft_hint(hint, "切回下半后的提示")
	if not hint._hero_done:
		for index: int in 100:
			if hint._hero_done: break
			await create_timer(0.1).timeout
	var deployed := 0
	for owned: OwnedCard in main.owned_card_collection.get_cards():
		if owned.card_data.card_type != CardData.CardType.MINION: continue
		var row: BattlefieldRow = main.front_row if deployed == 0 else main.back_row
		check(main._transfer_card({"kind": &"card", "source_type": &"collection", "card_data": owned.card_data, "owned_card": owned}, &"board", row), "通过真实转移入口继续部署随从")
		deployed += 1
		await create_timer(0.3).timeout
		if deployed == 1:
			hint = await expected_hint("battle_ready")
			check_soft_hint(hint, "继续安排队伍提示")
			check(hint.instruction_label.text.contains("继续") and not hint.instruction_label.text.contains("行动冷却"), "一名上场后只提醒继续布阵，不提前混入战斗规则")
	check(deployed >= 2 and main.get_node_or_null("TaskHint") == hint, "轻提示不妨碍继续部署多名随从")
	await capture_pack("14_continue_deploy_no_dim")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	var verify_slide := func():
		check(maze._panel.position.y < 0 and main.current_phase == main.GamePhase.PREPARE and not main.enemy_front_row.is_visible_in_tree(), "上半视角开战时准备板先上滑，敌阵保持隐藏")
	main.start_battle_button.pressed.connect(func(): create_timer(0.12).timeout.connect(verify_slide), CONNECT_ONE_SHOT)
	await click_control(main.start_battle_button)
	hint = await expected_hint("battle_intro")
	check(main.current_phase == main.GamePhase.BATTLE and paused and main._task_hint_pause_requested, "真正开战后才暂停并显示自动战斗说明")
	var enemy_cards: Array[CardView] = []
	for row: BattlefieldRow in [main.enemy_front_row, main.enemy_back_row]:
		for slot: BoardSlot in row.get_squads():
			enemy_cards.append_array(slot.get_card_views())
	for view: CardView in enemy_cards:
		check(view.is_visible_in_tree() and view.position.is_equal_approx(view._layout_resting_position) and is_zero_approx(view._board_landing_lift), "开战后敌方原阵容直接显示在各自槽位")
	var time: float = main.battle_controller.elapsed_seconds
	await create_timer(0.4).timeout
	check(is_equal_approx(main.battle_controller.elapsed_seconds, time), "说明期间实际战斗时间轴停止")
	for view: CardView in enemy_cards:
		check(view.get_node_or_null("EventLandingDust") == null, "敌方原阵容开战后没有延迟触发入场烟尘")
	check(main.current_world_view == main.WorldView.BATTLEFIELDS and main.world_content.position == Vector2.ZERO, "战斗暂停不阻断视角归位，也不会死等镜头Tween")
	await capture_pack("15_battle_intro_paused")
	await click_control(main.front_row)
	check(paused and main._task_hint_pause_requested and not is_instance_valid(hint), "点击战场后首段淡出，下一段继续保持暂停")
	await expected_hint("battle_retreat")
	check(main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:battle_intro"), "开战说明已阅独立保存")
	var spawned: BattleSquadState = main.battle_controller.summon_content_minion(main.battle_controller.enemy_states[0], preload("res://resources/cards/crystal_shard_beetle.tres"))
	await process_frame
	var spawned_slot := main._battle_state_slots.get(spawned) as BoardSlot
	var spawned_card := spawned_slot.get_card_view(spawned.get_effect_source()) if spawned_slot != null else null
	check(spawned_card != null and spawned_card._board_landing_lift > 0.0, "同场战斗中单独召唤的敌卡仍从上方落下")
	await create_timer(0.35).timeout
	check(spawned_card != null and is_zero_approx(spawned_card._board_landing_lift) and spawned_card.get_node_or_null("EventLandingDust") != null, "单独召唤的敌卡落地后仍冒烟尘")
	shell.free()
	print("Deployment tutorial: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
