extends "res://tests/event_cards_test.gd"

const SPEED_SAVE := "/private/tmp/project-card-speed-bar-save.json"


func capture_speed(label: String) -> void:
	if "--capture-speed" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-speed-%s.png" % label)


func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = SPEED_SAVE
	root.add_child(shell)
	if "--2k" in OS.get_cmdline_user_args(): shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await process_frame
	maze = main.maze_controller
	_deal("loose_coins")
	var bar: Control = main.battle_speed_bar
	check(not bar.visible, "准备阶段隐藏速度条")
	check(maze.select_path("loose_coins") and maze.complete_event(), "完成真实随机事件")
	check(maze.select_path(maze.run.paths[0].path_id) and maze.complete_event(false), "完成强化轮")
	check(maze.select_path(maze.run.paths[0].path_id), "选择商店牌")
	maze.enter_selected_shop()
	main._toggle_ordinary_shop()
	check(maze.select_path(maze.run.paths[0].path_id), "选择真实敌方遭遇")
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	owned.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300)
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	check(main.start_battle(20261019, true), "启动自动播放的真实战斗")
	await create_timer(0.25).timeout
	if "--2k" in OS.get_cmdline_user_args():
		check(shell.render_container.get_global_transform_with_canvas().get_scale().is_equal_approx(Vector2(2, 2)), "2K真实窗口使用2倍显示和输入映射")
	check(bar.visible and bar.position == Vector2(558, 14) and bar.size == Vector2(164, 15), "原生素材尺寸与指定坐标一致")
	check(bar.buttons.size() == 4 and bar.selected_slot == 1 and main.battle_controller.battle_speed_multiplier == 1.0, "默认1倍，四个入口含暂停")
	await capture_speed("1x")
	await _click(bar.buttons[2])
	check(main.battle_controller.battle_speed_multiplier == 2.0 and bar.selected_slot == 2, "真实点击双箭头切到2倍")
	bar._transition.pause()
	bar._transition.custom_step(0.04)
	check(bar.slider.position.x > bar.SLIDER_X[1] and bar.slider.position.x < bar.SLIDER_X[2], "切换时滑块位于两档之间")
	check(bar.highlights[1].modulate.a > 0.0 and bar.highlights[1].modulate.a < 1.0 and bar.highlights[2].modulate.a > 0.0 and bar.highlights[2].modulate.a < 1.0, "旧图标与新图标同时平滑渐变")
	bar._transition.play()
	await create_timer(0.25).timeout
	check(is_equal_approx(bar.slider.position.x, bar.SLIDER_X[2]) and is_equal_approx(bar.highlights[2].modulate.a, 1.0), "滑动与亮起正确收尾")
	await _click(bar.buttons[0])
	check(paused and main._manual_pause_requested and bar.selected_slot == 0, "点击暂停档停止实际战斗")
	var frozen: float = main.battle_controller.elapsed_seconds
	await create_timer(0.30).timeout
	check(main.battle_controller.elapsed_seconds == frozen, "暂停后实际战斗逻辑不前进")
	check(is_equal_approx(bar.slider.position.x, bar.SLIDER_X[0]) and is_equal_approx(bar.highlights[0].modulate.a, 1.0), "战斗暂停时速度条仍可完成动画")
	await capture_speed("paused")
	await _click(bar.buttons[0])
	check(not paused and bar.selected_slot == 2 and main.battle_controller.battle_speed_multiplier == 2.0, "再次点击暂停恢复之前2倍速度")
	await create_timer(0.1).timeout
	check(main.battle_controller.elapsed_seconds > frozen, "继续后实际战斗恢复推进")
	await _click(bar.buttons[0])
	await _click(bar.buttons[3])
	check(not paused and not main._manual_pause_requested and main.battle_controller.battle_speed_multiplier == 3.0, "暂停时点击三箭头直接3倍继续")
	await _click(bar.buttons[1])
	await _click(bar.buttons[3])
	await _click(bar.buttons[1])
	await create_timer(0.25).timeout
	check(bar.selected_slot == 1 and is_equal_approx(bar.slider.position.x, bar.SLIDER_X[1]) and main.battle_controller.battle_speed_multiplier == 1.0, "快速反向连点最终正确落到1倍")
	for index: int in 4:
		check(is_equal_approx(bar.highlights[index].modulate.a, 1.0 if index == 1 else 0.0), "快速切换后没有遗留半亮图标")
	main.set_special_spell_pause_requested(true)
	await _click(bar.buttons[3])
	check(paused and bar.selected_slot == 0 and not main._manual_pause_requested, "速度按钮不能解除其他系统持有的暂停")
	main.set_special_spell_pause_requested(false)
	check(not paused and bar.selected_slot == 3 and main.battle_controller.battle_speed_multiplier == 3.0, "外部暂停解除后显示实际选择的3倍")
	await create_timer(0.25).timeout
	await capture_speed("3x")
	check(main.save_run_to_path(SPEED_SAVE) == OK and main.load_run_from_path(SPEED_SAVE), "真实战斗存档恢复到战前准备")
	check(main.current_phase == main.GamePhase.PREPARE and not bar.visible, "读档离开战斗后隐藏速度条")
	paused = false
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(SPEED_SAVE)
	print("像素速度条：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
