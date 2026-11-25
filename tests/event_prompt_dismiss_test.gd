extends "res://tests/tutorial_action_guidance_test.gd"

## 只验证事件／商店点开牌堆即收起提示，以及领奖后只有英雄对白。
const EVENT_PROMPT_DIR := "/private/tmp/project-card-event-prompts-test"


func expected_hint(id: String) -> Control:
	for index: int in 300:
		var current: Control = main.get_node_or_null("TaskHint")
		if is_instance_valid(current) and current.get_meta("hint_key", "") == "tutorial:step:" + id: return current
		await create_timer(0.1).timeout
	check(false, "等待当前提示超时：" + id)
	return null


func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("事件提示专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(EVENT_PROMPT_DIR)
	Effects.load_saved(EVENT_PROMPT_DIR.path_join("effects.cfg"))
	Effects.reset_defaults()
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = EVENT_PROMPT_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await frames()
	check(await shell.start_slot(0), "创建隔离事件测试档")
	check(shell.slot_progress.select_catalog_tasks("tutorial", "") and await shell.start_new_slot_run(), "正式开始教程")
	main = shell.main_screen
	var maze = main.maze_controller
	while shell.screen_transition.busy: await process_frame
	if is_instance_valid(maze._initial_pack_drop): await maze._initial_pack_drop.finished
	# 本专项从已读过开包教学的存档状态开始，仍走真实发卡与撕包流程。
	check(main.save_profile_action(func():
		for id: String in ["supplies"]:
			main.profile_progress.record_hint_read("tutorial:step:" + id, TaskCatalog.tutorial_hint(id), {"story": true, "teaching": true})
		return true), "准备已阅开包的隔离存档")
	check(maze.open_task_supply(), "正式领取初始包")
	await create_timer(0.7).timeout
	main._card_pack_opening.auto_tear()
	await create_timer(1.0).timeout
	main._close_card_inspection(true)
	await create_timer(0.4).timeout
	while not maze.hero.pending_talent_levels.is_empty(): maze.choose_talent(String(maze.hero.get_pending_choices()[0]))
	check(main.get_node_or_null("TaskHint") == null, "首个事件牌堆旁不再弹教学")
	while is_instance_valid(maze._event_table._deck_arrival): await process_frame
	await click_control(maze._event_table._deck)
	var table: Control = maze._event_table
	if table.busy: await table.choices_ready
	check(table.cards.size() == 3 and maze.run.step == maze.RunState.Step.CHOOSING, "三张候选照常展开")
	check(table.cards.all(func(card: Button): return card.definition.name == "福尔图纳的馈赠"), "三个候选均指向同一钱袋事件")
	await click_control(table.cards[0])
	while maze.run.step == maze.RunState.Step.CHOOSING: await process_frame
	check(maze.choose_story_option(0), "打开钱袋")
	if is_instance_valid(maze._story_roll): await maze._story_roll.finished
	if is_instance_valid(maze._event_gold_flight): await maze._event_gold_flight.finished
	check(maze.complete_event(true, true), "读取骰子结果后继续旅程")
	var hint := await expected_hint("event_reward")
	check(TaskCatalog.tutorial_hint("event_reward").instruction.is_empty() and hint.speech_only and not hint.panel.visible, "补给已收下不再出现浅色提示框")
	check(is_instance_valid(hint.speech) and not hint.content.dialogue.is_empty(), "保留领奖后的伊奥恩对白")
	check(maze.select_path(String(maze.run.paths[0].path_id)) and maze.complete_event(false, true), "正常走过付费事件到商店路线")
	hint = await expected_hint("shop_route")
	await click_control(maze._event_table._deck)
	check(not is_instance_valid(hint) or (hint._teaching_done and hint._surface.modulate.a < 0.01), "点击商店牌堆后前往商店说明和目标框均已淡出")
	check(main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:shop_route") and maze._event_table.cards.size() == 3 and not main.ordinary_shop_open, "商店候选显示时已完成提示，不必等进入店铺")
	shell.free()
	print("Event prompt dismissal: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
