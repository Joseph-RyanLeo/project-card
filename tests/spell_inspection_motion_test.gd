extends "res://tests/enemy_spell_hover_20261020_test.gd"


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
	finish_events()
	maze.select_path(maze.run.paths[0].path_id)
	var player: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	player.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 3000)
	player.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 20)
	main.front_row.add_squad(SquadData.from_owned_card(player), 0)
	check(main.start_battle(20261024, false), "启动真实首日战斗")
	await resolve_real_battle()
	check(maze.continue_after_battle(), "正常结算推进到第二天")
	while not maze.hero.pending_talent_levels.is_empty(): maze.choose_talent(maze.hero.get_pending_choices()[0])
	finish_events()
	var path_id := ""
	for path: Dictionary in maze.run.paths:
		if not path.get("spells", []).is_empty(): path_id = path.path_id; break
	check(not path_id.is_empty() and maze.select_path(path_id), "进入包含真实敌方法术的遭遇")
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
		var event := InputEventMouseButton.new()
		event.position = shell.render_container.get_global_transform_with_canvas() * icon.get_global_rect().get_center()
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = true
		root.push_input(event, true)
		await process_frame
		event.pressed = false
		root.push_input(event, true)
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
	shell.queue_free()
	await process_frame
	print("Spell inspection motion: ", assertions, " checks, ", failures, " failures")
	quit(1 if failures else 0)
