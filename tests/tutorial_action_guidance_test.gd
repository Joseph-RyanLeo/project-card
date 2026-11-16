extends "res://tests/initial_pack_guidance_test.gd"

## 真实开包、选路和部署验证；不跑整段四天教程，不写玩家配置。
const ACTION_DIR := "/private/tmp/project-card-action-guidance-test"
const Effects = preload("res://scripts/ui/pack_opening_effect_settings.gd")
const Hint = preload("res://scripts/ui/task_hint_overlay.gd")


func wait_closed(hint: Control) -> void:
	for index: int in 260:
		if not is_instance_valid(hint): return
		await create_timer(0.1).timeout
	check(false, "等待对白自然结束超时")


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("操作教学专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(ACTION_DIR)
	Effects.load_saved(ACTION_DIR.path_join("effects.cfg"))
	Effects.reset_defaults()
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = ACTION_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await frames()
	check(await shell.start_slot(0), "创建隔离教学档")
	check(shell.slot_progress.select_catalog_tasks("tutorial", "") and await shell.start_new_slot_run(), "正式进入教程")
	main = shell.main_screen
	# 本专项验证通用操作提示；关键词练习由独立真实交互专项覆盖。
	check(main.save_profile_action(func():
		for id: String in ["militia_inspect", "militia_keywords", "militia_neighbor"]:
			main.profile_progress.record_hint_read("tutorial:step:" + id, TaskCatalog.tutorial_hint(id), {"story": false, "teaching": true})
		return true), "使用已阅关键词的隔离档验证通用提示")
	var maze = main.maze_controller
	while shell.screen_transition.busy: await process_frame
	if is_instance_valid(maze._initial_pack_drop): await maze._initial_pack_drop.finished
	await create_timer(3.5).timeout
	check(main.get_node_or_null("TaskHint") == null and maze._initial_pack_idle_seconds < 5, "5秒前不弹点包提示")
	var hint = await wait_hint("tutorial:step:supplies")
	check(maze._initial_pack_idle_seconds >= 5 and maze.INITIAL_PACK_HINT_DELAY == 5, "点包等待阈值为5秒")
	check(hint.find_children("*", "Button", true, false).is_empty(), "教学中没有知道了或关闭按钮")
	DirAccess.make_dir_absolute(main.run_save_path + ".tmp")
	await click_control(maze._initial_pack_button)
	check(is_instance_valid(hint) and not hint._closing and main.owned_card_collection.get_cards().is_empty(), "保存失败时保留点包提示，不执行开包")
	DirAccess.remove_absolute(main.run_save_path + ".tmp")
	await click_control(maze._initial_pack_button)
	check(main.get_node_or_null("TaskHint") == null and is_instance_valid(main._card_pack_opening), "点击卡包即完成教学并淡出，同次输入开包")
	hint = await wait_hint("tutorial:step:tear_pack")
	check(maze._initial_pack_idle_seconds >= 5, "封口等待阈值同样为5秒")
	if "pause-only" in OS.get_cmdline_user_args():
		await key_escape()
		check(main._escape_pause_menu.is_menu_open() and main.get_node_or_null("TaskHint") == hint and is_instance_valid(main._card_pack_opening), "教学期间Esc打开暂停菜单，不误确认提示或关闭包装")
		await key_escape()
		check(not main._escape_pause_menu.is_menu_open() and main.get_node_or_null("TaskHint") == hint, "关闭暂停菜单恢复未完成的教学与包装")
		await tear_pack()
		check(main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:tear_pack"), "从暂停返回后仍可按提示直接撕包")
		shell.free()
		print("Guidance pause: %d checks, %d failures" % [checks, failures])
		quit(1 if failures else 0)
		return
	await tear_pack()
	check(main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:tear_pack"), "真实拖拽撕封口完成教学并写入已阅")
	hint = await wait_hint("tutorial:step:supplies")
	check(main._inspection_dim.visible and main._inspection_dim.material == hint._focus_material, "开包对白复用原暗幕，只改变局部亮区")
	await wait_closed(hint)
	check(main.profile_progress.run.read_story_nodes.has("tutorial:step:supplies"), "两句对白自然结束后保存剧情记录")
	main._close_card_inspection(true)
	await create_timer(0.6).timeout
	while not maze.hero.pending_talent_levels.is_empty():
		check(maze.choose_talent(String(maze.hero.get_pending_choices()[0])), "正式处理天赋")
	check(main.get_node_or_null("TaskHint") == null, "不再弹出事件牌堆教学")
	await click_control(maze._event_table._deck)
	var table = maze._event_table
	if table.busy: await table.choices_ready
	check(table.cards.size() == 3, "点击牌堆照常展开三张候选")
	await click_control(table.cards[0])
	while maze.run.step == maze.RunState.Step.CHOOSING: await process_frame
	check(maze.choose_story_option(0), "打开福尔图纳的钱袋")
	if is_instance_valid(maze._story_roll): await maze._story_roll.finished
	check(maze.complete_event(true, true), "查看结果后推进事件")
	check(maze._queued_tutorial_stories.has("event_reward") or main.get_node_or_null("TaskHint").get_meta("hint_key", "") == "tutorial:step:event_reward", "快速完成下一步时，后续对白进入队列而非被略过")
	if is_instance_valid(hint): await wait_closed(hint)
	if is_instance_valid(main._inspection_overlay): main._close_card_inspection(true)
	# 复用真实对白组件做淡入淡出及不额外压暗的界面单元验证。
	var story := Hint.new()
	story.title = "对白"
	story.content = {"instruction": "", "dialogue": [{"speaker": "伊奥恩", "text": "继续前进。"}]}
	story.speaker = main.player_avatar_button
	main.add_child(story)
	check(story._surface.get_children().all(func(child: Node): return not child is ColorRect), "正常画面单独说话时不创建额外暗幕")
	check(story.speech._visual.modulate.a < 0.01 and story._surface.modulate.a < 0.01, "英雄气泡与提示层均从透明开始淡入")
	await create_timer(0.09).timeout
	check(story.speech._visual.modulate.a > 0.01 and story.speech._visual.modulate.a < 1.0, "气泡淡入有中间透明度")
	story.dismiss()
	check(is_instance_valid(story) and story._closing, "提示关闭时先播放渐隐，不立即删除")
	await create_timer(0.3).timeout
	check(not is_instance_valid(story), "渐隐完成后释放提示")
	while maze.run.get_round_kind() != "battle":
		check(maze.select_path(String(maze.run.paths[0].path_id)), "正式继续后续事件路线")
		await create_timer(0.6).timeout
		if maze.run.get_round_kind() == "shop":
			if is_instance_valid(main._shop_open_tween) and main._shop_open_tween.is_running(): await main._shop_open_tween.finished
			await click_control(main._shop_leave_button)
			check(not main.ordinary_shop_open, "点击正式按钮离店")
		else: check(maze.complete_event(false, true), "正式跳过付费奖励")
		await create_timer(0.4).timeout
	check(maze.select_path(String(maze.run.paths[0].path_id)), "正式进入战斗准备")
	for index: int in 400:
		var current: Control = main.get_node_or_null("TaskHint")
		if is_instance_valid(current) and current.get_meta("hint_key", "") == "tutorial:step:deploy_view": await click_control(main.player_avatar_button)
		if is_instance_valid(current) and current.get_meta("hint_key", "") == "tutorial:step:deploy": break
		await create_timer(0.1).timeout
	hint = main.get_node_or_null("TaskHint")
	check(hint != null and hint.get_meta("hint_key", "") == "tutorial:step:deploy", "排队对白顺序播放完毕后，正常出现部署提示")
	for index: int in 100:
		if hint._hero_done: break
		await create_timer(0.1).timeout
	check(main.profile_progress.run.read_story_nodes.has("tutorial:step:deploy") and not hint._teaching_done and not main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:deploy"), "对白先结束时独立保存剧情，仍保留尚未操作的教学")
	var owned: OwnedCard
	for card: OwnedCard in main.owned_card_collection.get_cards():
		if card.card_data.card_type == CardData.CardType.MINION: owned = card; break
	check(main._transfer_card({"kind": &"card", "source_type": &"collection", "card_data": owned.card_data, "owned_card": owned}, &"board", main.front_row), "通过正式拖放转移入口部署真实随从")
	await create_timer(0.3).timeout
	check((not is_instance_valid(hint) or hint._teaching_done) and main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:deploy"), "部署成功后提示自动淡出并即时记教学已阅")
	if is_instance_valid(hint): await wait_closed(hint)
	hint = await wait_hint("tutorial:step:battle_ready")
	await click_control(main.start_battle_button)
	check(main.current_phase == main.GamePhase.BATTLE and not is_instance_valid(hint) and main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:battle_ready"), "点击开始战斗正常开战并自动完成提示")
	shell.free()
	print("Action guidance: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
