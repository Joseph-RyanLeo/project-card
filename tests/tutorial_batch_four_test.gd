extends SceneTree

const DISPLAY := preload("res://scenes/GameDisplay.tscn")
const SAVE_PATH := "/private/tmp/project-card-batch4-tutorial.json"
var shell: Control
var main: Control
var viewport: SubViewport
var maze: ShortMazeController
var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value


func _until(predicate: Callable, seconds: float = 2.5) -> bool:
	var timeout := create_timer(seconds)
	while timeout.time_left > 0.0 and not predicate.call():
		await process_frame
	return predicate.call()


func _input_at(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for down: bool in [true, false]:
		var input := InputEventMouseButton.new()
		input.position = pos
		input.global_position = pos
		input.button_index = button
		input.pressed = down
		input.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if down else 0
		viewport.push_input(input, true)
		await process_frame


func _click(control: Control, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await _input_at((control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)).get_center(), button)


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func _capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("/private/tmp/project-card-batch4-" + label + ".png")


func _hint(key: String, seconds: float = 2.5) -> Control:
	await _until(func():
		var candidate := main.get_node_or_null("TaskHint")
		return is_instance_valid(candidate) and candidate.get_meta("hint_key", "") == key, seconds)
	var candidate := main.get_node_or_null("TaskHint") as Control
	return candidate if is_instance_valid(candidate) and candidate.get_meta("hint_key", "") == key else null


func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("第四批教程回归超时"); quit(1))
	shell = DISPLAY.instantiate()
	viewport = shell.get_node("RenderContainer/InternalViewport")
	main = viewport.get_node("DesignCanvas/Main")
	main.run_save_path = SAVE_PATH
	root.add_child(shell)
	await process_frame
	maze = main.maze_controller
	maze.new_run(501)
	check(maze.choose_talent("sentry_guard"), "建立测试前的原对局")
	main.run_reward_state.gold = 76
	check(main.save_run_to_path(SAVE_PATH) == OK and main.save_run_to_path(SAVE_PATH) == OK, "保存原对局及其备份")
	var original := FileAccess.get_file_as_string(SAVE_PATH)
	var backup := FileAccess.get_file_as_string(SAVE_PATH + ".bak")
	var original_id: String = main.profile_progress.run.id
	await _test_trial()
	var session: RefCounted = main._developer_event_test
	if session.is_active(): check(session.stop().is_empty(), "退出测试并恢复原局")
	check(main.profile_progress.run.id == original_id and main.run_reward_state.gold == 76 and main.run_save_path == SAVE_PATH, "退出后恢复原本任务、金币与保存位置")
	check(FileAccess.get_file_as_string(SAVE_PATH) == original and FileAccess.get_file_as_string(SAVE_PATH + ".bak") == backup, "测试过程未改写原存档或备份")
	await _test_squad_teaching()
	if session.is_active(): check(session.stop().is_empty(), "结束教程重玩并恢复对局")
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(SAVE_PATH)
	DirAccess.remove_absolute(SAVE_PATH + ".bak")
	print("第四批教程：%d项断言，%d失败" % [checks, failures])
	quit(1 if failures else 0)


func _test_trial() -> void:
	var console: DeveloperConsole = main._developer_console
	var developer_key := InputEventKey.new()
	developer_key.pressed = true
	developer_key.keycode = KEY_F2
	viewport.push_input(developer_key, true)
	if not check(console.visible, "F2打开开发面板"): return
	check(console._tasks.item_count == 7, "开发选项列出已实现的五个主线与两个支线任务")
	var index := -1
	for item: int in console._tasks.item_count:
		if console._tasks.get_item_metadata(item) == "supply_first": index = item
	if not check(index >= 0, "F2提供已接入的纹章包试炼"): return
	console._tabs.current_tab = console._tabs.get_tab_count() - 1
	console._tasks.select(index)
	await _capture("task-replay")
	console._start_task_test.pressed.emit()
	if not check(main._developer_event_test.task_id == "supply_first" and main.run_save_path != SAVE_PATH, "任务选项启动独立测试局"): return
	check(not maze.hero.pending_talent_levels.is_empty() and maze._find_tutorial_card_view(&"logistics_robot") == null and not maze._initial_pack_prompt.visible, "开局先显示天赋，机器人和纹章包尚未登场")
	check(not maze.open_task_supply(), "天赋和剧情前无法提前开启纹章包")
	check(maze.choose_talent("sentry_guard"), "实际选择天赋后提交后勤机器人")
	check(await _until(func():
		var landing_card: CardView = maze._find_tutorial_card_view(&"logistics_robot")
		return landing_card != null and landing_card._board_landing_lift > 0.0 and landing_card.z_index > main.battle_time_bar.z_index
	), "下落中的机器人绘制层级高于时间条")
	await _capture("robot-landing")
	var dialogue := await _hint("supply_first:opening")
	if not check(dialogue != null and dialogue.blocks_gameplay() and not maze._initial_pack_prompt.visible, "机器人落地后播放锁定对白，桌上仍无纹章包"): return
	var view: CardView = maze._find_tutorial_card_view(&"logistics_robot")
	check(view != null and dialogue.speech._speaker == view, "后勤机器人从实际卡面说话")
	var dust := view.get_node_or_null("EventLandingDust") as Control if view != null else null
	check(dust != null and dust.show_behind_parent and dust.z_as_relative, "后勤机器人落地时烟尘绘制在卡面后方")
	if dust != null:
		var dust_bounds := Rect2(dust.position, dust.size * dust.scale)
		check(dust_bounds.get_center().is_equal_approx(view.card_size * 0.5) and dust_bounds.grow(-1.0).encloses(Rect2(Vector2.ZERO, view.card_size)), "烟尘以卡面为中心，四边都留有扩散空间")
	if "--capture" in OS.get_cmdline_user_args(): await create_timer(0.10).timeout
	await _capture("robot-dust")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	viewport.push_input(escape, true)
	check(not main._escape_pause_menu.blocks_gameplay(), "对白期间Esc不会开启其他界面")
	await _input_at(Vector2(420, 380))
	check(dialogue._hero_line_index == 0 and dialogue.speech.text_label.visible_ratio == 1.0, "第一次点击补全当前台词")
	await _input_at(Vector2(420, 380))
	check(await _until(func(): return dialogue._hero_line_index == 1 and dialogue.speech.visible), "第二次点击推进到伊奥恩")
	await _input_at(Vector2(420, 380))
	await _input_at(Vector2(420, 380))
	var pack_hint := await _hint("supply_first:open_pack")
	if not check(pack_hint != null and maze._initial_pack_prompt.visible, "对白完成才飞出纹章包并出现高亮"): return
	var button := maze._initial_pack_button
	check(button.disabled and button.scale.x < 1.0, "抛出的纹章包从小到大，飞行期间不可点击")
	check(not pack_hint.panel.visible and pack_hint._focus_material.get_shader_parameter("dim_opacity") == 0.0, "纹章包阶段只显示高亮，没有提示框或暗幕")
	await _capture("sticker-toss")
	if not check(await _until(func(): return not maze._initial_pack_button.disabled), "包装飞行完成后可点击"): return
	var robot_rect := view.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, view.size)
	var pack_rect := button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, button.size)
	check(not robot_rect.intersects(pack_rect) and absf(robot_rect.end.y - pack_rect.end.y) < 8.0, "纹章包落在机器人身侧并和卡脚对齐")
	await _capture("sticker-pack")
	await process_frame
	await _click(maze._initial_pack_button)
	var opening: Node = main._sticker_pack_opening
	if not check(is_instance_valid(opening), "实点包装进入原纹章开包动画"): return
	if not check(await _until(func(): return opening.phase == opening.Phase.SEALED), "纹章包放大后进入可揭状态"): return
	opening.auto_peel()
	if not check(await _until(func(): return opening.phase == opening.Phase.REVEALED), "封皮揭开后显示贴纸"): return
	opening.collect()
	if not check(await _until(func(): return opening.phase == opening.Phase.EMPTY_REVEALED, 8.0), "五枚贴纸飞入工具箱"): return
	opening.collect()
	var emblems := await _hint("supply_first:emblems")
	if not check(emblems != null and emblems.instruction_label.text.contains("右键"), "开包结束才提示检视随从"): return
	var robot: CardView = maze._find_tutorial_card_view(&"logistics_robot")
	robot.rotation_degrees = -5.0 # 显式倾斜用于校验卡框及高亮共用的变换
	await process_frame
	await process_frame
	var mask := emblems._focus_texture as Texture2D
	var axes := Vector4(emblems._focus_material.get_shader_parameter("canvas_to_focus_axes"))
	check(emblems.silhouette_target == robot.card_frame and absf(axes.y) > 0.01 and absf(axes.z) > 0.01, "机器人卡框和轮廓高亮使用同一倾斜变换")
	check(mask != null and mask.get_image().get_pixelv(Vector2i(mask.get_size() * 0.5)).a > 0.9, "卡面透明窗口不会产生内描边")
	if "--capture" in OS.get_cmdline_user_args(): await create_timer(0.25).timeout
	await _capture("robot-outline")
	robot.rotation_degrees = 0.0
	await _click(maze._find_tutorial_card_view(&"logistics_robot"), MOUSE_BUTTON_RIGHT)
	check(await _until(func(): return emblems.instruction_label.text.contains("展开")), "实际检视后高亮工具箱入口")
	if not check(is_instance_valid(main._inspection_library_toggle), "检视真实工具箱入口存在"): return
	await _click(main._inspection_library_toggle)
	check(await _until(func(): return emblems.instruction_label.text.contains("空槽") and emblems._focus_regions.size() >= 2), "展开后高亮试用纹章与真实空槽")
	if is_instance_valid(main._inspection_tween) and main._inspection_tween.is_running(): await main._inspection_tween.finished
	await _capture("sticker-slots")
	var item: Dictionary = main.emblem_library.get_inventory_state()[0]
	check(main.emblem_library.move_sticker(StringName(item.instance_id), Vector2i(3, 6)), "试用纹章可在工具箱内移动")
	await process_frame
	check(not main.profile_progress.profile.tutorial.read_hints.has("supply_first:emblems"), "挪动纹章不能提前完成教学")
	var owner: OwnedCard = main._inspection_owned_card
	var slot := owner.emblem_slots.find({})
	var slot_point: Vector2 = main._get_emblem_slot_rect(slot).get_center()
	check(main._drop_emblem_on_inspection_card(main._inspection_card_view, slot_point, {"kind": &"emblem_library", "emblem_id": item.emblem_id, "definition": {"id": item.emblem_id, "returned_state": item}}), "通过正式纹章落槽路径贴上试用纹章")
	check(await _until(func(): return main.profile_progress.profile.tutorial.read_hints.has("supply_first:emblems")), "完成进度以试用纹章真实附着为准")


func _test_squad_teaching() -> void:
	var session: RefCounted = main._developer_event_test
	if not check(session.start_task("tutorial").is_empty() and main.is_smith_tutorial(), "在已完成过任务的环境也能进入隔离教程"): return
	check(main.profile_progress.profile.tutorial.read_hints.is_empty(), "测试教程从未读状态开始")
	var initial := maze._initial_pack_button
	var away := Vector2(60, 650)
	_move_pointer(away)
	check(await _until(func(): return not initial.disabled), "初始卡包落稳")
	var rest := initial.position
	_move_pointer((initial.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, initial.size)).get_center())
	await create_timer(0.65).timeout
	check(initial.position.y < rest.y and maze._initial_pack_shadow.visible, "持续悬停超过原跳动时长，卡包保持悬空并显示阴影")
	_move_pointer(away)
	check(await _until(func(): return initial.position.is_equal_approx(rest) and not maze._initial_pack_shadow.visible), "移开鼠标后卡包落回并收起阴影")
	_move_pointer((initial.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, initial.size)).get_center())
	await _until(func(): return maze._initial_pack_shadow.visible)
	await _click(initial)
	if not check(is_instance_valid(main._card_pack_opening), "能实际点开悬空的初始卡包"): return
	main._close_card_inspection(true)
	await process_frame
	for id: String in ["supplies", "first_victory"]:
		main.profile_progress.record_hint_read("tutorial:step:" + id, TaskCatalog.tutorial_hint(id), {"story": true, "teaching": true})
	# 直接定位到第二战的备战轮，仅跳过前置路线，叠卡走真实拖放事务。
	maze.run.day = 2
	maze.run.round_index = 3
	maze.run.step = ShortMazeRunState.Step.CHOOSING
	maze.run.paths.clear()
	maze._generate_paths()
	if not check(not maze.run.paths.is_empty() and maze.select_path(String(maze.run.paths[0].path_id)), "第二战正式读取配置的扭曲矿脉阵容"): return
	check(main.enemy_front_row.get_squads().map(func(slot: BoardSlot): return slot.get_squad_data().horizontal_cards[0].id) == [&"subterranean_blindfish", &"mine_wailer"], "第二战两张独立随从符合确认阵容")
	main.set_world_view(main.WorldView.COLLECTION, false)
	var first := await _hint("tutorial:step:squad_sources")
	if not check(first != null and first.instruction_label.text.contains("拖到") and not first.instruction_label.text.contains("最上层"), "先只要求操作，未预先展示四段原理"): return
	var row: BattlefieldRow = main.front_row
	var cards: Array[OwnedCard] = main.owned_card_collection.get_cards().filter(func(card: OwnedCard): return card.card_data.card_type == CardData.CardType.MINION)
	cards[0].rune_revealed.fill(true)
	var target := row.add_card(cards[0].card_data, 0, cards[0])
	var source := row.add_card(cards[1].card_data, 1, cards[1])
	await process_frame
	var member := source.get_squad_data().horizontal_cards[0]
	var drag := {"kind": &"card", "source_type": &"board", "source_row": row, "source_slot": source, "squad_data": source.get_squad_data(), "card_data": member}
	drag.drop_intent = row._build_merge_intent(target, row._get_slot_visual_rect(target).get_center().x, drag)
	check(main._transfer_drop_intent(drag, row), "实际提交叠卡事务")
	for step: String in maze.SQUAD_TEACHING_STEPS:
		var hint := await _hint("tutorial:step:" + step, 6.0)
		await process_frame
		if not check(hint != null and not hint.instruction_label.text.is_empty() and hint.focus_rect.has_area(), "正确高亮并说明 %s（当前 %s，已读 %s）" % [step, maze._tutorial_hint_id(), main.profile_progress.profile.tutorial.read_hints]): return
		if step == "squad_effect" or step == "squad_runes":
			if "--capture" in OS.get_cmdline_user_args(): await create_timer(0.25).timeout # 等待说明与高亮淡入
			await _capture(step)
		await _input_at(Vector2(410, 610))
