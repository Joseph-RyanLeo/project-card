extends "res://tests/event_cards_test.gd"

const HERO_SAVE := "/private/tmp/project-card-hero-lamps-save.json"
const PREVIEWS := "res://docs/previews/hero_progress_20261019/"
const HERO_ART := "res://assets/ui/hero_progress_20261019/"
var hud: Control


func capture_hero(filename: String = "") -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = shell.internal_viewport.get_texture().get_image()
	if not filename.is_empty():
		check(image.save_png(PREVIEWS + filename) == OK, "保存实际英雄面板渲染" + filename)
	return image


func check_lamps(image: Image, level: int, earned: int, required: int, label: String) -> void:
	# 用原始图片与明确的参考图坐标核对渲染，不调用产品绘制函数生成预期结果。
	var origin := Vector2i(hud._hero_progress_lamps.global_position.round())
	var empty: Image = load(HERO_ART + "progress_empty.png").get_image()
	var lit_level: Image = load(HERO_ART + "level_lit.png").get_image()
	var lit_xp: Image = load(HERO_ART + "experience_lit.png").get_image()
	var unused: Image = load(HERO_ART + "experience_unused.png").get_image()
	var errors := 0
	for index: int in 10:
		for y: int in 15:
			for x: int in 14:
				var at := Vector2i(7 + 14 * index + x, y)
				var expected := empty.get_pixelv(at)
				if index < level and lit_level.get_pixel(x, y).a > 0:
					expected = lit_level.get_pixel(x, y)
				if expected.a > 0 and not image.get_pixelv(origin + at).is_equal_approx(expected):
					errors += 1
	check(errors == 0, label + "：10盏等级灯实际像素正确")
	errors = 0
	for index: int in 18:
		for y: int in 6:
			for x: int in 6:
				var expected := empty.get_pixel(7 + 7 * index + x, 18 + y)
				var overlay := lit_xp if required == 0 or index < earned else (unused if index >= required else null)
				if overlay != null and overlay.get_pixel(x, y).a > 0:
					expected = overlay.get_pixel(x, y)
				var at := origin + Vector2i(14 + 7 * index + x, 18 + y)
				if not image.get_pixelv(at).is_equal_approx(expected):
					errors += 1
	check(errors == 0, label + "：18盏经验灯的亮／暗／不涉及实际像素正确")
	var left_corner := origin + Vector2i(7, 17)
	var right_corner := origin + Vector2i(139, 17)
	errors = 0
	for y: int in 8:
		for x: int in 7:
			var left := empty.get_pixel(x, 17 + y)
			var right := empty.get_pixel(146 + x, 17 + y)
			if left.a > 0 and not image.get_pixelv(left_corner + Vector2i(x, y)).is_equal_approx(left): errors += 1
			if right.a > 0 and not image.get_pixelv(right_corner + Vector2i(x, y)).is_equal_approx(right): errors += 1
	check(errors == 0, label + "：缩短经验条两端原像素保持")


func hover(control: Control) -> void:
	var event := InputEventMouseMotion.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * control.get_global_rect().get_center()
	event.global_position = event.position
	Input.warp_mouse(event.position)
	root.push_input(event, true)
	await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(PREVIEWS)
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = HERO_SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await process_frame
	maze = main.maze_controller
	maze.new_run(20261019)
	check(maze.choose_talent("sentry_guard"), "实际选择1级天赋")
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	hud = maze._status
	check(hud._hero_panel.size == Vector2(185, 357), "使用185×357新版底板")
	check(hud._hero_panel.global_position == Vector2(1085, 381), "下半视角底板左上角精确为1085、381")
	check(hud._hero_panel.position == Vector2(1084, 749), "世界坐标只补偿一次下半视角原点")
	var positions: Array[Vector2] = [Vector2(47, 235), Vector2(103, 235), Vector2(47, 281), Vector2(103, 281)]
	for index: int in 4:
		check(hud._talent_slots[index].position == positions[index], "天赋位%d按参考图对齐" % index)
	check(hud._hero_progress_lamps.position == Vector2(16, 197), "等级经验灯槽按参考图定位")
	check(not hud._hero_label.text.contains("经验") and hud._hero_label.text == "伊奥恩·沃登", "姓名与灯条分开，不重复显示旧经验文字")
	check_lamps(await capture_hero(), 1, 0, 2, "开局")
	check(maze.hero.grant_experience("hero_ui:level2", 2), "真实经验接口升2级")
	maze.refresh()
	check(maze.hero.level == 2 and maze.hero.get_current_level_experience() == 0 and maze.hero.get_next_level_experience_required() == 4, "升级后本级经验清零，需求取正式曲线")
	check_lamps(await capture_hero(), 2, 0, 4, "2级0/4")
	check(maze.hero.grant_experience("hero_ui:level3", 7), "真实经验接口跨级并保留余量")
	maze.refresh()
	check(maze.hero.level == 3 and maze.hero.experience == 9 and maze.hero.get_current_level_experience() == 3, "总经验9转换为3级本级经验3")
	check_lamps(await capture_hero("level3.png"), 3, 3, 6, "3级3/6")
	check(hud._hero_progress_lamps.tooltip_text.contains("3/6"), "悬停说明包含精确本级经验")
	await hover(hud._hero_progress_lamps)
	check(shell.internal_viewport.gui_get_hovered_control() == hud._hero_progress_lamps, "2K原生鼠标能命中灯条")
	check(main.save_run_to_path(HERO_SAVE) == OK and main.load_run_from_path(HERO_SAVE), "真实磁盘保存与读取")
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	check_lamps(await capture_hero(), 3, 3, 6, "读档")
	check(maze.hero.grant_experience("hero_ui:level4", 3), "真实经验达到4级")
	check(maze.choose_talent("sentry_fortify"), "实际选择4级天赋")
	maze.refresh()
	check(hud._talent_slots[0].color == Color("2b7718") and hud._talent_slots[1].color == Color("1e6bcd"), "保留1／4级天赋绿蓝显示")
	check(hud._talent_slots[2].color == Color("8c8d8e") and hud._talent_slots[3].color == Color("8c8d8e"), "7／10级天赋仍保持未选灰色")
	check_lamps(await capture_hero("level4.png"), 4, 0, 8, "4级0/8")
	await hover(hud._talent_slots[1])
	check(shell.internal_viewport.gui_get_hovered_control() == hud._talent_slots[1] and hud._talent_slots[1].tooltip_text.contains("4级"), "新位置天赋仍可原生悬停并提供效果说明")
	# 单独验证正式状态模型的9／10级显示，不开放当前短路线的高等级天赋。
	var full_hero := HeroProgressState.new()
	var thresholds: Array[int] = []
	thresholds.assign(maze.rewards.config.experience.level_thresholds)
	check(full_hero.initialize(thresholds, maze.rewards.config.talent_choices), "独立英雄状态使用正式曲线")
	check(full_hero.grant_experience("hero_ui:level9", 89), "正式模型达到9级17/18")
	hud._hero_progress_lamps.sync(full_hero)
	check_lamps(await capture_hero("level9.png"), 9, 17, 18, "9级17/18")
	check(full_hero.grant_experience("hero_ui:level10", 1), "正式模型达到10级")
	hud._hero_progress_lamps.sync(full_hero)
	check_lamps(await capture_hero("maximum.png"), 10, 0, 0, "满级")
	check(full_hero.get_next_level_experience_required() == 0 and hud._hero_progress_lamps.tooltip_text.contains("满级"), "满级无下一档需求，18盏全亮")
	check(full_hero.grant_experience("hero_ui:overflow", 30), "满级继续记录累计经验")
	hud._hero_progress_lamps.sync(full_hero)
	check_lamps(await capture_hero(), 10, 30, 0, "满级溢出经验")
	hud.sync(maze, false)
	check(maze.hero.level == 4, "UI满级单元验证不改变真实短路线英雄等级")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await process_frame
	check(hud._hero_panel.position == Vector2(1084, 749) and hud._hero_panel.global_position == Vector2(1084, 746), "切换视角不改变世界位置")
	main.set_world_view(main.WorldView.COLLECTION, false)
	await capture_hero("collection.png")
	shell.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(HERO_SAVE)
	print("英雄面板等级经验灯：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
