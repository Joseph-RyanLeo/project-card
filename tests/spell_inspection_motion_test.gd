extends "res://tests/enemy_spell_hover_20261020_test.gd"


func right_click_at(logical_position: Vector2) -> void:
	var point: Vector2 = shell.render_container.get_global_transform_with_canvas() * logical_position
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("法术检视往返测试超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-spell-inspection-motion.json"
	root.add_child(shell)
	root.size = Vector2i(2560, 1440)
	await create_timer(0.5).timeout
	maze = main.maze_controller
	maze.new_run(20261019)
	maze.choose_talent("sentry_guard")
	# 直接从第二天战斗选路起测，仍由正式遭遇生成器和存档事务创建敌方法术。
	maze.run.day = 2
	maze.run.round_index = ShortMazeRunState.ROUND_KINDS.find("battle")
	maze.run.paths.clear()
	maze._generate_paths()
	var player: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	player.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 3000)
	player.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 20)
	main.front_row.add_squad(SquadData.from_owned_card(player), 0)
	var path_id := ""
	for path: Dictionary in maze.run.paths:
		if not path.get("spells", []).is_empty(): path_id = path.path_id; break
	var entered: bool = not path_id.is_empty() and maze.select_path(path_id)
	check(entered, "进入包含真实敌方法术的遭遇")
	if not entered: quit(1); return
	var spell: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/damage_fireball.tres"))
	main.prepared_spell_instance_ids.append(spell.instance_id)
	main._refresh_spell_preparation_tray()
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	check(main.start_battle(20261024, false), "双方真实法术队列进入战斗")
	await create_timer(0.6).timeout
	main._update_battle_timer()
	for tray: Control in [main.enemy_spell_preparation_tray, main.spell_preparation_tray]:
		check(not tray._icons_by_instance_id.is_empty(), "真实法术托盘具有可检视令牌")
		if tray._icons_by_instance_id.is_empty(): continue
		var icon: Control = tray._icons_by_instance_id.values()[0]
		await move_pointer(icon.get_global_rect().get_center())
		await create_timer(0.1).timeout
		var source: CardView = tray._hover_card_popup
		check(is_instance_valid(source) and source.visible, "右键前显示真实悬停法术卡")
		if not is_instance_valid(source): continue
		await right_click_at(icon.get_global_rect().get_center())
		check(main._inspection_source_view == source and not source.visible and main._inspection_tween.is_running(), "右键令牌从对应悬停卡平滑移动放大，不直接出现在中央")
		check(paused and not main._inspection_tools_enabled(), "检视冻结真实战斗并保持只读")
		await create_timer(0.3).timeout
		check(main._inspection_owned_card == icon.owned_card and main._inspection_surface.scale == Vector2(4, 4), "检视落到正确实例与4倍尺寸")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-%s-spell-inspection.png" % ("enemy" if tray.enemy_display else "player"))
		main._close_card_inspection()
		await create_timer(0.35).timeout
		check(not paused and main._inspection_source_view == null and tray._hover_card_popup == source and source.visible, "关闭后平滑返回同一悬停卡，释放战斗暂停")
		await move_pointer(Vector2(640, 710))
		await process_frame
		check(not source.visible, "离开令牌后预览正常消失，不残留卡面")
	var enemy_tray: Control = main.enemy_spell_preparation_tray
	if not enemy_tray._icons_by_instance_id.is_empty():
		var enemy_icon: Control = enemy_tray._icons_by_instance_id.values()[0]
		main._on_battle_pause_button_pressed()
		var clock_before: float = main.battle_controller.elapsed_seconds
		var remaining_text: String = enemy_icon._remaining_label.text
		var spent_alpha: float = enemy_icon.modulate.a
		await move_pointer(enemy_icon.get_global_rect().get_center())
		await create_timer(0.5).timeout
		var preview: CardView = enemy_tray._hover_card_popup
		var popup := get_first_node_in_group(&"card_effect_popup")
		check(paused and is_instance_valid(preview) and preview.visible and preview.get_owned_card() == enemy_icon.owned_card,
			"手动暂停时悬停敌方法术仍展示对应完整卡牌")
		check(popup != null and popup.source == preview and popup.panel.visible, "手动暂停时显示法术效果说明弹窗")
		check(enemy_icon._remaining_label.text == remaining_text and is_equal_approx(enemy_icon.modulate.a, spent_alpha), "悬停不重置法术读秒或已释放亮度")
		await move_pointer(Vector2(640, 710))
		await process_frame
		check(not preview.visible, "暂停中移开指针会清除法术预览")
		await right_click_at(enemy_icon.get_global_rect().get_center())
		check(main._inspection_owned_card == enemy_icon.owned_card and main._inspection_source_view == preview and not main._inspection_tools_enabled(),
			"暂停中无需预先悬停，右键直接从对应法术卡开始只读检视")
		main._close_card_inspection()
		await create_timer(0.35).timeout
		check(paused and main._manual_pause_requested and main.battle_controller.elapsed_seconds == clock_before and preview.visible,
			"关闭敌方法术检视后保留手动暂停、战斗时间与悬停来源")
		main._on_battle_pause_button_pressed()
	shell.queue_free()
	await process_frame
	print("Spell inspection motion: ", assertions, " checks, ", failures, " failures")
	quit(1 if failures else 0)
