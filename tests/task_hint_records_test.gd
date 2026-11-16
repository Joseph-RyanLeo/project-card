extends "res://tests/d3_4_ui_test.gd"

## 使用旧已阅夹具、正式保存与真实按钮，集中验证剧情／教学的生命周期。
const RECORDS_DIR := "/private/tmp/project-card-hint-records-test"

func finish_story(popup: Control) -> void:
	while is_instance_valid(popup) and not popup.panel.visible:
		await create_timer(0.1).timeout

func open_intro(main: Control) -> void:
	var drop: Tween = main.maze_controller._initial_pack_drop
	if is_instance_valid(drop) and drop.is_running(): await drop.finished
	check(main.maze_controller.open_task_supply(), "通过现有补给开包流程进入包装检视")
	await create_timer(0.7).timeout
	main._card_pack_opening.auto_tear()
	await create_timer(1.0).timeout

func _run() -> void:
	create_timer(70).timeout.connect(func(): push_error("对白记录专项超时"); quit(1))
	var p := ProfileProgress.new()
	var state := p.capture_state()
	state.profile.tutorial.erase("records_version")
	state.profile.tutorial.read_hints = ["tutorial:step:supplies", "tutorial:step:event_choice", "tutorial:1:0:day", "supply_first:1:0:supplies"]
	state.profile.tutorial.hint_texts = {"tutorial:step:supplies": "伊奥恩：旧版对白和教学混在一起"}
	state.run.erase("read_story_nodes")
	state.run["read_tutorial_hints"] = []
	check(p.restore_state(state), "旧版混合已阅记录可严格恢复并迁移")
	var key := "tutorial:step:supplies"
	var hint := TaskCatalog.tutorial_hint("supplies")
	check(p.hint_pending(key, hint) == {"story": true, "teaching": false}, "旧档读过教学不会阻止新局开场对白")
	check(p.profile.tutorial.hint_texts[key].contains("点击战场中央") and not p.profile.tutorial.hint_texts[key].contains("伊奥恩"), "迁移后教学回看只保留操作说明")
	check(not p.profile.tutorial.read_hints.has("supply_first:1:0:supplies"), "旧任务开场剧情不冒充操作教学")
	var same_run := state.duplicate(true)
	same_run.run.read_tutorial_hints = [key, "tutorial:1:0:day", "deep_survey:3:1:flickering_lantern"]
	var old_run := ProfileProgress.new()
	check(old_run.restore_state(same_run) and not old_run.hint_pending(key, hint).story, "旧档本局已实际读过的对白迁移后不重播")
	check(old_run.run.read_story_nodes.has("deep_survey:flickering_lantern"), "青灯形态剧情采用稳定节点，跨轮次不重复")
	check(not old_run.hint_pending("tutorial:step:deploy", TaskCatalog.tutorial_hint("deploy")).story, "旧档本局已读的整章对白也能按节点迁移")
	check(TaskCatalog.story_key("ironwall_support", 1, "supplies") == TaskCatalog.story_key("ironwall_support", 1, "day") and TaskCatalog.story_key("ironwall_support", 9, "supplies") != TaskCatalog.story_key("ironwall_support", 1, "day"), "同层赠包前后共享剧情节点，第二层独立触发")
	var fresh := ProfileProgress.new()
	fresh.record_hint_read(key, hint, fresh.hint_pending(key, hint))
	check(fresh.run.read_story_nodes.has(key) and fresh.profile.tutorial.read_hints.has(key), "首次确认分别写入本局剧情与长期教学")
	check(fresh.select_catalog_tasks("tutorial", "") and fresh.start_run(), "通过正式开局重置本局")
	check(fresh.hint_pending(key, hint) == {"story": true, "teaching": false}, "新局仅重播剧情，教学已阅保持")
	var bad := fresh.capture_state()
	bad.run.read_story_nodes = [7]
	check(not ProfileProgress.new().restore_state(bad), "剧情记录继续严格校验字符串节点")

	DirAccess.make_dir_recursive_absolute(RECORDS_DIR)
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = RECORDS_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await frames()
	check(await shell.start_slot(0), "创建隔离专项档")
	var migrated := p.capture_state()
	check(shell.slot_progress.restore_state(migrated) and shell.slot_progress.select_catalog_tasks("tutorial", ""), "装入已阅教学的旧档语义夹具并选择M1")
	check(await shell.start_new_slot_run(), "正式开始新一局教程")
	await create_timer(0.7).timeout
	var main = shell.main_screen
	check(main.get_node_or_null("TaskHint") == null, "新局进入时不提前播放撕包后的对白")
	await open_intro(main)
	main.maze_controller.show_task_hint()
	await frames()
	var popup = main.get_node_or_null("TaskHint")
	check(popup != null and not popup.content.dialogue.is_empty() and popup.instruction_label.text.is_empty(), "实际开场只显示剧情，不重弹已阅教学")
	if popup == null: shell.free(); quit(1); return
	var bytes := FileAccess.get_file_as_string(main.run_save_path)
	DirAccess.make_dir_absolute(main.run_save_path + ".tmp")
	await finish_story(popup)
	await click_control(main._inspection_surface)
	check(is_instance_valid(popup) and not main.profile_progress.run.read_story_nodes.has(key) and FileAccess.get_file_as_string(main.run_save_path) == bytes, "确认保存失败回退剧情记录，保留有效磁盘档")
	check(main._card_pack_opening.current_index == 0, "剧情已阅保存失败不透传收卡操作")
	DirAccess.remove_absolute(main.run_save_path + ".tmp")
	await click_control(popup.panel)
	check(main.get_node_or_null("TaskHint") == null and main.profile_progress.run.read_story_nodes.has(key), "重试成功只提交一次本局剧情")
	while is_instance_valid(main._card_pack_opening):
		check(not main.maze_controller._panel.visible, "实际逐张收卡期间不显示天赋页")
		await click_control(main._inspection_surface)
	await frames()
	check(main.maze_controller._panel.visible and not main.maze_controller.hero.pending_talent_levels.is_empty(), "最后一张收进收藏后恢复原有天赋页")
	var saved := RunSaveService.new().load_checkpoint(main.run_save_path)
	var restored := ProfileProgress.new()
	check(saved.success and restored.restore_state(saved.checkpoint.profile_progress) and not restored.hint_pending(key, hint).story, "从真实JSON恢复同局，不重复对白")
	check(main.load_run_from_path(main.run_save_path), "正式读档完整恢复本局")
	main.maze_controller.show_task_hint()
	await frames()
	check(main.get_node_or_null("TaskHint") == null, "实际同局读档后不再弹开场")
	await key_escape()
	await click_control(main._escape_pause_menu.find_child("TutorialHelpButton", true, false))
	var page = main._escape_pause_menu.find_child("TutorialHelpPage", true, false)
	var text: Label = page.find_child("TaskInfoText", true, false)
	check(main._escape_pause_menu.find_child("TutorialHelpButton", true, false).text == "教学回看" and text.text.contains("点击战场中央"), "Esc教学回看显示已阅操作教学")
	check(not text.text.contains("伊奥恩") and not text.text.contains("玛格丽特：") and not text.text.contains("制作备注"), "教学回看不混入剧情和制作脚本")
	await screenshot("11_teaching_review")
	await key_escape()
	await key_escape()
	check(not main._escape_pause_menu.is_menu_open() and not paused, "关闭回看后恢复对局输入")
	check(main.finish_maze_run("abandoned"), "通过正式结束本局流程准备重试")
	check(main.save_profile_action(main.profile_progress.show_selection) and main.save_profile_action(main.profile_progress.show_preview) and main.save_profile_action(main.profile_progress.confirm_collection), "完成本局零选卡总结并返回大厅")
	await frames()
	check(shell.slot_progress.select_catalog_tasks("tutorial", "") and await shell.start_new_slot_run(), "从大厅正式重试未完成的教程资格")
	main = shell.main_screen
	await create_timer(0.7).timeout
	await open_intro(main)
	main.maze_controller.show_task_hint()
	await frames()
	popup = main.get_node_or_null("TaskHint")
	check(popup != null and not popup.content.dialogue.is_empty() and popup.instruction_label.text.is_empty(), "实际重开一局再播剧情，仍不重弹教学")
	if popup != null:
		await click_control(main._inspection_surface)
		check(main.get_node_or_null("TaskHint") == popup, "重试局收起首张卡不会结束对白")
		await finish_story(popup)
	check(main.get_node_or_null("TaskHint") == null and main.profile_progress.run.read_story_nodes.has(key), "重开局确认后保存本局剧情节点")
	# 新局另一段故事也应独立出现，不能只恢复开场。
	while not main.maze_controller.hero.pending_talent_levels.is_empty(): main.maze_controller.choose_talent(String(main.maze_controller.hero.get_pending_choices()[0]))
	check(main.profile_progress.run.supplies.is_empty(), "撕包时已领取初始补给，不再次发放")
	main._close_card_inspection(true)
	var table = main.maze_controller._event_table
	if is_instance_valid(table) and table.busy: await table.choices_ready
	await frames()
	popup = main.get_node_or_null("TaskHint")
	check(popup == null, "旧记录恢复后也不重弹已取消的事件牌堆教学")
	if popup != null: await key_escape()
	shell.free()
	print("Hint records: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
