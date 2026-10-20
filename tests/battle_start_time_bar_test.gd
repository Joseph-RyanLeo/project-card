extends "res://tests/board_ui_fixes_20261019_test.gd"

const START_SAVE := "/private/tmp/project-card-start-time-save.json"


func capture_start(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = shell.internal_viewport.get_texture().get_image()
	image.save_png("/private/tmp/project-card-start-time-%s.png" % label)
	return image


func verify_bar_pixels(ratio: float, label: String) -> void:
	var bar: Control = main.battle_time_bar
	var image := await capture_start(label)
	var original: Image = bar.FULL.get_image()
	var empty: Image = bar.EMPTY.get_image()
	var blue := original.get_pixel(67, 7)
	var origin := Vector2i(bar.global_position)
	var left_count := 0
	var right_count := 0
	var expected := floori(383 * ratio)
	var errors := 0
	# 主界面事件面板遮住素材最上3行，底部也有透明像素；核对实际完整露出的槽和金边。
	for y: int in range(3, 13):
		for x: int in 897:
			var color := image.get_pixelv(origin + Vector2i(x, y))
			var in_track := y >= 5 and y <= 10 and ((x >= 37 and x < 420) or (x >= 478 and x < 861))
			var wanted := empty.get_pixel(x, y)
			if in_track:
				var corner := 1 if y == 5 or y == 10 else 0
				var row_width := maxi(expected - corner, 0)
				if (x < 420 and x >= 420 - row_width) or (x >= 478 and x < 478 + row_width):
					wanted = blue
			# 眼睛独立覆盖中央装饰，不属于时间条填充。
			if x >= 441 and x < 457 and y >= 3 and y < 13:
				continue
			if not color.is_equal_approx(wanted):
				errors += 1
			if y == 7 and color.is_equal_approx(blue):
				if x < 420: left_count += 1
				elif x >= 478: right_count += 1
	check(left_count == expected and right_count == expected, "两边蓝条完整槽宽对称：" + label)
	check(errors == 0, "蓝条、圆角、空槽与金框实际像素正确：" + label)


func verify_button_motion() -> void:
	var button: Button = main.start_battle_button
	check(button.global_position == Vector2(999, 674) and button.size == Vector2(83, 29), "按钮原生83×29严格对应原稿(1019,674)扣20")
	var rect := button.get_global_rect()
	var visual: Control = button.get_node("ButtonVisual")
	await move_pointer(rect.get_center())
	var offsets: Dictionary = {}
	for index: int in 12:
		await create_timer(0.015).timeout
		offsets[visual.position] = true
		check(button.get_global_rect() == rect, "指向颤抖不移动原生点击范围")
	check(offsets.size() > 2 and not offsets.has(Vector2(2, 0)), "指向时显示层按原生像素轻微颤抖")
	await press_pointer(true)
	await create_timer(0.12).timeout
	check(main.current_phase == main.GamePhase.PREPARE and is_equal_approx(button.press_depth, 3), "按住时压入3像素，尚未释放开战")
	check(visual.position == Vector2.ZERO, "按住时停止颤抖，左右下框不漂移")
	var held := await capture_start("pressed")
	var source: Image = button.ART.get_image()
	var errors := 0
	var shifted := 0
	for y: int in source.get_height():
		for x: int in source.get_width():
			var original := source.get_pixel(x, y)
			var screen_color := held.get_pixelv(Vector2i(rect.position) + Vector2i(x, y))
			if original == Color.BLACK and y > 0:
				if not screen_color.is_equal_approx(Color.BLACK): errors += 1
			elif original.a > 0.0 and y >= 3 and x < 26:
				var shifted_color := source.get_pixel(x, y - 3)
				if shifted_color.a > 0 and shifted_color != Color.BLACK:
					shifted += 1
					if not screen_color.is_equal_approx(shifted_color): errors += 1
	check(shifted > 200 and errors == 0, "真实按住画面中图案下沉，左右下方黑框遮挡重合像素")
	check(button.get_node("ButtonVisual/ButtonCaption").position.y == 3, "开始战斗文字与按钮图案同步下沉")
	await move_pointer(Vector2(950, 660), true)
	await press_pointer(false)
	await create_timer(0.15).timeout
	check(main.current_phase == main.GamePhase.PREPARE and button.press_depth == 0, "拖出松开不误开战，按压正常回弹")
	check(visual.position == Vector2.ZERO, "鼠标离开后颤抖归位")
	var normal := await capture_start("normal")
	var normal_errors := 0
	for y: int in source.get_height():
		for x: int in 26:
			var color := source.get_pixel(x, y)
			if color.a == 1 and not normal.get_pixelv(Vector2i(rect.position) + Vector2i(x, y)).is_equal_approx(color):
				normal_errors += 1
	check(normal_errors == 0, "正常按钮图案保留原始像素和原稿位置")


func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = START_SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await process_frame
	maze = main.maze_controller
	_deal("loose_coins")
	await create_timer(0.4).timeout
	check(main.battle_time_bar.remaining_ratio == 1, "默认准备阶段的实际进度为满")
	await verify_bar_pixels(1.0, "default_full")
	for elapsed: float in [7.5, 15.0, 22.5, 30.0]:
		main.battle_time_bar.update_time(elapsed, 30.0)
		await verify_bar_pixels(1.0 - elapsed / 30.0, "bar_%d" % elapsed)
	main._update_battle_timer()
	finish_events()
	check(maze.select_path(maze.run.paths[0].path_id), "选择真实敌方遭遇进入战前准备")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	owned.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300)
	owned.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 20)
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	await process_frame
	await verify_button_motion()
	await move_pointer(main.start_battle_button.get_global_rect().get_center())
	await press_pointer(true)
	await create_timer(0.08).timeout
	await press_pointer(false)
	check(main.current_phase == main.GamePhase.BATTLE, "真实点击松开后沿用正式开战流程")
	check(main.battle_controller.elapsed_seconds == 0 and main.battle_time_bar.remaining_ratio == 1, "开场演出时实际计时从0秒、满条开始")
	# 自动演出仍使用实际控制器；暂停只为固定截图时刻，不伪造战斗数据。
	main.set_special_spell_pause_requested(true)
	await verify_bar_pixels(1.0, "battle_start")
	main.set_special_spell_pause_requested(false)
	await create_timer(1.8).timeout
	main.set_special_spell_pause_requested(true)
	var ratio: float = clampf(1.0 - main.battle_controller.elapsed_seconds / main.battle_controller.fatigue_start_seconds, 0, 1)
	check(ratio < 1 and ratio > 0 and is_equal_approx(main.battle_time_bar.remaining_ratio, ratio), "实际战斗时间推进后从满格减少")
	await verify_bar_pixels(ratio, "battle_progress")
	main.set_special_spell_pause_requested(false)
	await resolve_real_battle()
	check(main.current_phase == main.GamePhase.RESULT and main.battle_time_bar.is_visible_in_tree(), "真实结算后时间条仍持续显示")
	check(maze.continue_after_battle(), "完成结算进入下一天")
	check(main.battle_time_bar.remaining_ratio == 1, "下一天准备时恢复完整满条")
	await verify_bar_pixels(1.0, "next_day")
	check(main.save_run_to_path(START_SAVE) == OK and main.load_run_from_path(START_SAVE), "实际存读档仍正常")
	await create_timer(1.0).timeout # 等待上一场已发出的可视弹道退场，避免遮住读档后的槽位截图
	await verify_bar_pixels(1.0, "load_prepare")
	paused = false
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(START_SAVE)
	print("开始按钮与满格时间条：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
