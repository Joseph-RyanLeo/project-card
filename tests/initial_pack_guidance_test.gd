extends "res://tests/d3_4_ui_test.gd"

## 只走初始包的真实按钮、空闲计时、撕封口与保存读档，不跑后续四天教程。
const PACK_DIR := "/private/tmp/project-card-initial-pack-test"
var main


func capture_pack(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var directory := "res://docs/previews/d3_4_20261106"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))


func wait_hint(key: String) -> Control:
	for index: int in 180:
		var hint: Control = main.get_node_or_null("TaskHint")
		if hint != null:
			check(hint.get_meta("hint_key") == key, "只出现当前节点提示：" + key)
			return hint
		await create_timer(0.1).timeout
	check(false, "等待提示超时：" + key)
	return null


func tear_pack() -> void:
	var opening: CardPackOpening = main._card_pack_opening
	var surface := opening.surface
	var points := [Vector2(opening.tear_art.size.x * 0.12, 5), Vector2(opening.tear_art.size.x * 0.95, 5)]
	var transform: Transform2D = shell.render_container.get_global_transform_with_canvas() * surface.get_global_transform_with_canvas()
	var start: Vector2 = transform * (surface.content_padding + points[0])
	var end: Vector2 = transform * (surface.content_padding + points[1])
	var motion := InputEventMouseMotion.new()
	motion.position = start
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	root.push_input(press, true)
	for index: int in range(1, 9):
		motion = InputEventMouseMotion.new()
		motion.position = start.lerp(end, index / 8.0)
		root.push_input(motion, true)
		await process_frame
	press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = end
	root.push_input(press, true)
	await create_timer(1.0).timeout
	check(opening.phase not in [CardPackOpening.Phase.SEALED, CardPackOpening.Phase.TEARING], "真实横拉封口完成撕包")


func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("初始包专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(PACK_DIR)
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = PACK_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await frames()
	check(await shell.start_slot(0), "创建隔离存档")
	check(shell.slot_progress.select_catalog_tasks("tutorial", "") and await shell.start_new_slot_run(), "正式进入新局M1")
	main = shell.main_screen
	var maze = main.maze_controller
	check(maze._initial_pack_prompt.visible and not maze._panel.visible, "初始包直接出现，移除原补给事件板")
	check(is_instance_valid(maze._initial_pack_drop), "初始包复用Tween从近处缩小落到桌面")
	if maze._initial_pack_drop.is_running():
		check(maze._initial_pack_button.disabled, "下落和回弹期间不误触开包")
		await maze._initial_pack_drop.finished
	check(maze._initial_pack_button.get_global_rect().get_center().distance_to(Vector2(640, 360)) < 1, "回弹结束后卡包落在屏幕正中央")
	check(main.get_node_or_null("TaskHint") == null and not main.profile_progress.run.read_story_nodes.has("tutorial:step:supplies"), "入场不提前弹教学或记录开场对白")
	await capture_pack("01_initial_pack_center")
	await create_timer(3.0).timeout
	check(maze._initial_pack_idle_seconds < 5 and main.get_node_or_null("TaskHint") == null, "未满5秒不打断玩家")
	var hint = await wait_hint("tutorial:step:supplies")
	if hint == null: shell.free(); quit(1); return
	check(hint.content.dialogue.is_empty() and hint.instruction_label.text.contains("点击战场中央"), "5秒后只提示点包，不播放英雄开场")
	await capture_pack("02_click_pack_hint")
	check(hint.find_children("*", "Button", true, false).is_empty(), "点包提示不要求额外确认按钮")
	DirAccess.make_dir_absolute(main.run_save_path + ".tmp")
	await click_control(maze._initial_pack_button)
	check(main.get_node_or_null("TaskHint") == hint and main.owned_card_collection.get_cards().is_empty(), "直接点包保存失败时保留提示，不发卡或误关闭")
	DirAccess.remove_absolute(main.run_save_path + ".tmp")
	await click_control(maze._initial_pack_button)
	check(main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:supplies") and not main.profile_progress.run.read_story_nodes.has("tutorial:step:supplies"), "点包教学只记录长期已阅")
	check(is_instance_valid(main._card_pack_opening) and not maze._initial_pack_prompt.visible, "点击中央包进入复用的开包界面")
	check(not maze._panel.visible and not maze.hero.pending_talent_levels.is_empty(), "开包时保留待选天赋数据，背景不提前切换到天赋页")
	check(main.owned_card_collection.get_cards().size() == 5 and main.profile_progress.run.supplies.is_empty(), "初始五张卡仅发放一次")
	check(main.get_node_or_null("TaskHint") == null, "刚进入开包不弹撕包教学或英雄对白")
	hint = await wait_hint("tutorial:step:tear_pack")
	if hint == null: shell.free(); quit(1); return
	check(maze._initial_pack_idle_seconds >= 5 and hint.content.dialogue.is_empty() and hint.focus_rect.size.y < 150, "封口闲置5秒后才在封口旁提示横拉")
	await capture_pack("03_tear_pack_hint")
	check(hint.find_children("*", "Button", true, false).is_empty(), "横拉提示不要求额外确认按钮")
	await tear_pack()
	check(main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:tear_pack"), "直接拉封口关闭提示，同一次按压继续撕包并记录已阅")
	hint = await wait_hint("tutorial:step:supplies")
	if hint == null: shell.free(); quit(1); return
	check(hint.content.dialogue.size() == 2 and hint.instruction_label.text.is_empty() and is_instance_valid(hint.speech), "包装实际撕开后复用英雄气泡呈现两句对白")
	check(hint.speech_only and not hint.panel.visible and not hint.has_node("HintTargetOutline"), "纯英雄对白不显示出发补给标题框与继续按钮")
	var dim: ColorRect = main._inspection_dim
	check(dim.visible and dim.material == hint._focus_material and main.player_avatar_button.modulate == Color.WHITE, "对白在原检视暗幕上打开英雄亮区")
	check(not maze._panel.visible, "揭卡期间背景不显示天赋选择")
	if is_instance_valid(hint.speech) and is_instance_valid(hint.speech._text_reveal) and hint.speech._text_reveal.is_running(): await hint.speech._text_reveal.finished
	await capture_pack("04_after_tear_dialogue")
	await click_control(main._inspection_surface)
	check(main.get_node_or_null("TaskHint") == hint and dim.visible and dim.material == hint._focus_material, "收起首张卡时继续复用同一道暗幕")
	while is_instance_valid(hint) and not hint.panel.visible: await create_timer(0.1).timeout
	check(main.profile_progress.run.read_story_nodes.has("tutorial:step:supplies"), "确认对白后写入本局剧情记录")
	check(main._card_pack_opening.current_index == 1 and dim.visible and dim.material == null, "对白结束后恢复原暗幕材质，保持当前开包进度")
	var loaded := RunSaveService.new().load_checkpoint(main.run_save_path)
	var restored := ProfileProgress.new()
	check(loaded.success and restored.restore_state(loaded.checkpoint.profile_progress) and not restored.hint_pending("tutorial:step:supplies", TaskCatalog.tutorial_hint("supplies")).story, "真实存档恢复同局已阅对白")
	check(main.task_help_text(true).contains("横拉") and not main.task_help_text(true).contains("尸体"), "Esc教学回看收录两项教学，排除剧情")
	main._close_card_inspection(true)
	await frames()
	check(maze._panel.visible and not maze.hero.pending_talent_levels.is_empty(), "开包结束后正常恢复天赋选择")
	check(main.load_run_from_path(main.run_save_path), "正式读档恢复开包后的本局")
	await frames()
	check(main.get_node_or_null("TaskHint") == null, "同局读档不重复开场对白")
	check(main.finish_maze_run("abandoned"), "正式结束本局")
	check(main.save_profile_action(main.profile_progress.show_selection) and main.save_profile_action(main.profile_progress.show_preview) and main.save_profile_action(main.profile_progress.confirm_collection), "完成零收藏结算回大厅")
	await frames()
	check(shell.slot_progress.select_catalog_tasks("tutorial", "") and await shell.start_new_slot_run(), "正式重试M1")
	main = shell.main_screen
	maze = main.maze_controller
	await create_timer(6.2).timeout
	check(main.get_node_or_null("TaskHint") == null and maze._initial_pack_prompt.visible, "重开局即使等待5秒也不重复已阅点包教学")
	await click_control(maze._initial_pack_button)
	await tear_pack()
	hint = await wait_hint("tutorial:step:supplies")
	check(hint != null and hint.content.dialogue.size() == 2 and hint.instruction_label.text.is_empty(), "新局仍按撕包节点播放剧情，教学不干扰")
	shell.free()
	print("Initial pack guidance: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
