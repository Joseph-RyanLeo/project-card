extends "res://tests/d3_4_ui_test.gd"

## 真实菜单、滑块与拖点；配置和本局都写独立临时目录。
const Effects = preload("res://scripts/ui/pack_opening_effect_settings.gd")
const Arrival = preload("res://scripts/ui/pack_arrival_animation.gd")
const ARRIVAL_DIR := "/private/tmp/project-card-arrival-tuner-test"
var main


func drag_point(tuner: Control, from: Vector2, to: Vector2) -> void:
	var transform: Transform2D = shell.render_container.get_global_transform_with_canvas() * tuner.preview_container.get_global_transform_with_canvas()
	var motion := InputEventMouseMotion.new()
	motion.position = transform * from
	root.push_input(motion, true)
	await process_frame
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = true
	button.position = transform * from
	root.push_input(button, true)
	await process_frame
	motion = InputEventMouseMotion.new()
	motion.position = transform * to
	root.push_input(motion, true)
	await process_frame
	button = InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.position = transform * to
	root.push_input(button, true)
	await frames()


func _run() -> void:
	create_timer(65).timeout.connect(func(): push_error("入场调整器专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(ARRIVAL_DIR)
	var settings_path := ARRIVAL_DIR.path_join("effects.cfg")
	DirAccess.remove_absolute(settings_path)
	Effects.load_saved(settings_path)
	check(Effects.save_path == settings_path, "配置路径在静态初始化后仍为隔离文件")
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = ARRIVAL_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await frames()
	check(await shell.start_slot(0), "创建独立工具测试档")
	check(shell.slot_progress.select_catalog_tasks("tutorial", "") and await shell.start_new_slot_run(), "正式开始M1")
	main = shell.main_screen
	if main.maze_controller._initial_pack_drop.is_running(): await main.maze_controller._initial_pack_drop.finished
	var original_profile: Dictionary = main.profile_progress.capture_state()
	var original_collection: Dictionary = main.owned_card_collection.capture_state()
	await key_escape()
	await click_control(main._escape_pause_menu.find_child("DeveloperToolsButton", true, false))
	await click_control(main._escape_pause_menu.find_child("PackEffectTunerButton", true, false))
	await create_timer(0.7).timeout
	var tuner: Control = shell._pack_effect_tuner
	check(tuner != null and not main.visible, "真实Esc开发工具打开原开包调整器")
	if tuner == null: shell.free(); quit(1); return
	await click_control(tuner.find_child("PreviewArrival", true, false))
	check(tuner._previewing_arrival and tuner.preview_arrival.visible and not tuner.preview_shop.visible, "卡包入场按钮切换专用预览，不进入业务开包")
	check(tuner._parameter_tabs.get_current_tab_control().name == "入场" and tuner.controls.has("arrival_slide_power"), "选中入场参数页，提供速度曲线与坐标控件")
	tuner.controls.arrival_start_x.spin.value = 80
	tuner.controls.arrival_start_y.spin.value = 180
	tuner.controls.arrival_end_x.spin.value = 850
	tuner.controls.arrival_end_y.spin.value = 400
	tuner.controls.arrival_fall_speed.spin.value = 700
	tuner.controls.arrival_slide_speed.spin.value = 900
	tuner.controls.arrival_slide_power.spin.value = 3
	tuner.controls.arrival_dust_spread.spin.value = 52
	check(Effects.get_values().arrival_dust_spread == 52 and tuner.controls.arrival_dust_spread.slider.value == 52, "烟尘扩散参数与数值框、滑块联动")
	check(Effects.get_values().arrival_slide_speed == 900 and tuner.controls.arrival_slide_speed.slider.value == 900, "数值输入联动共享配置与滑块")
	await drag_point(tuner, Vector2(270, 305), Vector2(400, 330))
	check(Arrival.point(Effects.get_values(), "contact").distance_to(Vector2(400, 330)) < 2 and absf(tuner.controls.arrival_contact_x.spin.value - 400) < 2, "在缩放预览中真实拖动着地点并同步数值")
	var before := Arrival.timing(Effects.get_values())
	Effects.set_value("arrival_slide_speed", 1800)
	check(is_equal_approx(Arrival.timing(Effects.get_values()).y, before.y * 0.5), "初速度加倍后停止时间减半，飞入时间独立")
	Effects.set_value("arrival_slide_speed", 900)
	check(Arrival.speed_ratio(0.5, 4) < Arrival.speed_ratio(0.5, 2), "减速曲线指数改变实际速度曲线")
	await click_control(tuner.find_child("ReplayEffects", true, false))
	var preview: Control = tuner.preview_arrival
	check(preview.motion != null and preview.motion.is_running(), "重播使用当前草稿参数")
	var dust := preview.get_node_or_null("EventLandingDust")
	var slide := Arrival.point(Effects.get_values(), "end") - Arrival.point(Effects.get_values(), "contact")
	var half_extent: float = preview.package.size.dot(slide.normalized().abs()) * Effects.get_values().arrival_end_scale * 0.5
	check(dust != null and is_equal_approx(dust.directional_spread.length(), slide.length() + half_extent + 52), "重播烟尘覆盖滑行路线及停止后卡包边缘，再额外扩散52像素")
	if preview.motion.is_running(): await preview.motion.finished
	check((preview.package.position + preview.package.pivot_offset).distance_to(Vector2(850, 400)) < 1 and is_zero_approx(preview.package.rotation), "预览停在自定义终点并回正")
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/previews/d3_4_20261106"))
	root.get_texture().get_image().save_png("res://docs/previews/d3_4_20261106/10_arrival_tuner.png")
	await click_control(tuner.find_child("SaveEffects", true, false))
	var config := ConfigFile.new()
	check(Effects.save_path == settings_path and config.load(settings_path) == OK and config.get_value("opening", "arrival_end_x") == 850 and config.get_value("opening", "arrival_slide_power") == 3 and config.get_value("opening", "arrival_dust_spread") == 52, "保存按钮只写指定隔离配置文件，包含烟尘扩散值")
	tuner.controls.arrival_end_x.spin.value = 600
	await click_control(tuner.find_child("ReloadEffects", true, false))
	check(tuner.controls.arrival_end_x.spin.value == 850, "重新载入恢复已保存的入场数值")
	await click_control(tuner.find_child("ResetEffects", true, false))
	check(tuner.controls.arrival_end_x.spin.value == 640 and Effects.get_values().arrival_slide_power == 2, "恢复默认包含入场参数和减速曲线")
	check(config.get_value("opening", "arrival_end_x") == 850, "默认草稿不覆盖已保存设置")
	# 合法重合端点也应能重播，不发生除零或无限时长。
	for key: String in ["start", "contact", "end"]:
		Effects.set_value("arrival_" + key + "_x", 500)
		Effects.set_value("arrival_" + key + "_y", 350)
	Effects.set_value("arrival_arc_height", 0)
	preview.replay()
	await preview.motion.finished
	check((preview.package.position + preview.package.pivot_offset).distance_to(Vector2(500, 350)) < 1, "三个端点重合时仍可安全播放与结束")
	await click_control(tuner.find_child("CloseEffects", true, false))
	await create_timer(0.5).timeout
	check(not shell.is_pack_effect_tuner_open() and main.visible and Effects.get_values().arrival_end_x == 850, "返回丢弃未保存草稿，保留已保存入场参数")
	check(main.profile_progress.capture_state() == original_profile and main.owned_card_collection.capture_state() == original_collection, "预览与调参不更改本局任务、卡牌或已阅记录")
	main.maze_controller._drop_initial_pack()
	check((main.maze_controller._initial_pack_button.position + main.maze_controller._initial_pack_button.pivot_offset).distance_to(Vector2(80, 180)) < 1, "正式流程读取保存后的自定义起点")
	await main.maze_controller._initial_pack_drop.finished
	check((main.maze_controller._initial_pack_button.position + main.maze_controller._initial_pack_button.pivot_offset).distance_to(Vector2(850, 400)) < 1, "正式流程与预览共用动画并采用保存后的终点")
	shell.free()
	print("Arrival tuner: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
