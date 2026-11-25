extends SceneTree

const DISPLAY = preload("res://scenes/GameDisplay.tscn")
const Preferences = preload("res://scripts/data/game_preferences.gd")
const CrtProjection = preload("res://scripts/ui/crt_projection.gd")
const CARD = preload("res://resources/cards/militia.tres")
const DIRECTORY := "/private/tmp/project-card-hit-crt-test"
const PREFERENCES_PATH := DIRECTORY + "/game_preferences.cfg"
var checks := 0
var failures := 0
var shell: GameDisplay
var main: Control


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _frame_image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _sample_luminance(pixel: Color) -> float:
	return Vector3(pixel.r, pixel.g, pixel.b).dot(Vector3(0.2126, 0.7152, 0.0722))


func _capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var frame := await _frame_image()
	frame.save_png("/private/tmp/project-card-hit-crt-" + label + ".png")


func _click(control: Control) -> void:
	var transform := shell.render_container.get_global_transform_with_canvas() * control.get_global_transform_with_canvas()
	var point := transform * (control.size * 0.5)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _send_window_mouse(event: InputEventMouse, point: Vector2) -> void:
	event.window_id = root.get_window_id()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame


func _test_curved_pointer(frame_size: Vector2i) -> void:
	var scale_factor := float(frame_size.y) / 720.0
	var root_point := Vector2(26, 18) * scale_factor
	var game_point := Vector2(26, 702) * scale_factor
	var root_source := CrtProjection.to_source(root_point, Vector2(frame_size), shell._crt_curvature)
	var game_source := CrtProjection.to_source(game_point, Vector2(frame_size), shell._crt_curvature)
	var world_to_game := shell.render_container.get_global_transform_with_canvas().affine_inverse()
	var native_button := Button.new()
	native_button.position = root_source - Vector2(6, 6) * scale_factor
	native_button.size = Vector2(12, 12) * scale_factor
	native_button.z_index = 205
	var paint := StyleBoxFlat.new()
	paint.bg_color = Color(0.04, 0.94, 0.19)
	native_button.add_theme_stylebox_override("normal", paint)
	shell.add_child(native_button)
	var game_layer := CanvasLayer.new()
	game_layer.layer = 105
	shell.internal_viewport.add_child(game_layer)
	var game_button := Button.new()
	game_button.position = world_to_game * game_source - Vector2(6, 6)
	game_button.size = Vector2(12, 12)
	game_layer.add_child(game_button)
	var hits := [0, 0]
	var drag_step := [Vector2.ZERO]
	native_button.pressed.connect(func(): hits[0] += 1)
	game_button.pressed.connect(func(): hits[1] += 1)
	game_button.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseMotion: drag_step[0] = event.relative)
	var captured := await _frame_image()
	var painted := captured.get_pixelv(Vector2i(root_point))
	var old_pixel := captured.get_pixelv(Vector2i(root_source))
	_check(painted.g > 0.36 and painted.g > painted.r * 3.0 and old_pixel.g < 0.12, "GPU将角落已有内容移入曲面 %s" % frame_size)
	for point: Vector2 in [root_source, root_point, game_point]:
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(4, 6) * scale_factor
		await _send_window_mouse(motion, point)
		if point == game_point:
			var previous := CrtProjection.to_source(point - Vector2(4, 6) * scale_factor, Vector2(frame_size), shell._crt_curvature)
			var expected_delta := world_to_game.basis_xform(game_source - previous)
			_check((drag_step[0] as Vector2).distance_to(expected_delta) < 0.02, "游戏内鼠标位移也随曲面换算 %s" % frame_size)
		for down: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			await _send_window_mouse(event, point)
		if point == root_source:
			_check(hits == [0, 0], "曲面外的旧按钮位置不响应 %s" % frame_size)
		elif point == root_point:
			_check(root.gui_get_hovered_control() == native_button, "窗体控件悬停使用曲面位置 %s" % frame_size)
	_check(hits == [1, 1] and shell.internal_viewport.gui_get_hovered_control() == game_button, "根窗口和游戏画布控件都在变形位置点击命中 %s" % frame_size)
	var physical_mouse := root.get_mouse_position()
	var expected_mouse := world_to_game * CrtProjection.to_source(physical_mouse, Vector2(frame_size), shell._crt_curvature)
	_check(CrtProjection.viewport_mouse(shell.internal_viewport).distance_to(expected_mouse) < 2.0, "主动查询游戏鼠标位置也使用曲面坐标 %s" % frame_size)
	native_button.queue_free()
	game_layer.queue_free()


func _run() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var legacy := ConfigFile.new()
	legacy.set_value("settings", "display_mode", GameDisplay.DisplayMode.WINDOW_720P)
	legacy.set_value("settings", "volume", 36.0)
	legacy.set_value("settings", "crt_strength", 37.0)
	legacy.set_value("settings", "crt_brightness_variation", 62.0)
	legacy.save(PREFERENCES_PATH)
	var old_preferences := Preferences.new()
	old_preferences.path = PREFERENCES_PATH
	old_preferences.load_settings()
	_check(old_preferences.crt_strength == 37.0, "含明暗起伏的旧偏好仍可读取 CRT 强度")
	legacy.erase_section_key("settings", "crt_strength")
	legacy.set_value("settings", "crt_scanline_strength", 37.0)
	legacy.set_value("settings", "crt_curvature_strength", 29.0)
	legacy.save(PREFERENCES_PATH)
	root.size = Vector2i(1280, 720)
	shell = DISPLAY.instantiate()
	shell.run_slots.directory = DIRECTORY
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = DIRECTORY + "/run.json"
	root.add_child(shell)
	await process_frame
	await process_frame
	await _test_crt()
	await _test_hit()
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(PREFERENCES_PATH)
	print("受击反馈与CRT：%d项断言，%d失败" % [checks, failures])
	quit(1 if failures else 0)


func _test_crt() -> void:
	_check(not shell._crt_layer.visible and shell._preferences.crt_strength == 37.0 and shell._preferences.volume == 36.0, "更早的横纹设置可迁移为统一强度")
	shell.open_settings()
	await process_frame
	var panel: Control = shell._settings_panel
	_check(not panel.crt_strength_slider.editable and panel.find_child("SettingsCRTBrightness", true, false) == null, "关闭 CRT 时强度滑杆禁用，已移除明暗起伏选项")
	await _click(panel.crt_option)
	_check(panel.crt_option.button_pressed and shell._crt_layer.visible and panel.crt_strength_slider.editable, "设置实际点击开启整屏效果")
	panel.crt_strength_slider.value = 75.0
	var combined_curvature := CrtProjection.MAX_CURVATURE * 0.75
	_check(shell._crt_curvature.is_equal_approx(combined_curvature), "CRT 强度同时调整横纹和内弯")
	var stored := Preferences.new()
	stored.path = PREFERENCES_PATH
	stored.load_settings()
	_check(stored.crt_enabled and stored.crt_strength == 75.0 and is_equal_approx(float(shell._crt_material.get_shader_parameter("scanline_strength")), 0.75), "保存 CRT 开关和强度")
	var saved_config := ConfigFile.new()
	_check(saved_config.load(PREFERENCES_PATH) == OK and not saved_config.has_section_key("settings", "crt_brightness_variation"), "保存偏好时移除废弃的明暗起伏参数")
	_check(panel._settings_body.get_global_rect().end.y <= 720.0, "主设置面板完整在画布内")
	var probe := ColorRect.new()
	probe.color = Color(0.72, 0.72, 0.72)
	probe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	probe.z_index = 200
	shell.add_child(probe)
	if DisplayServer.get_name() != "headless":
		panel.crt_strength_slider.value = 100.0
		var old_14_percent := Vector2(0.16, 0.23) * 0.14
		_check(shell._crt_curvature.is_equal_approx(old_14_percent) and (shell._crt_material.get_shader_parameter("curvature") as Vector2).is_equal_approx(old_14_percent), "最大强度的画面和鼠标曲率均相当于上一版的 14%")
		for requested_size: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
			root.size = requested_size
			probe.size = Vector2(requested_size)
			await process_frame
			panel.crt_strength_slider.value = 0.0
			var flat := await _frame_image()
			panel.crt_strength_slider.value = 1.0
			var lowest := await _frame_image()
			panel.crt_strength_slider.value = 100.0
			var captured := await _frame_image()
			_check(captured.get_size() == requested_size, "实际CRT采样画幅 %s" % requested_size)
			if requested_size.y == 720 and "--capture" in OS.get_cmdline_user_args():
				captured.get_region(Rect2i(500, 220, 280, 168)).save_png("/private/tmp/project-card-crt-rgb-gray.png")
			var first := captured.get_pixel(125, 192).r
			var low_delta := 0.0
			var center_x := requested_size.x / 2
			for row: int in range(12, requested_size.y - 12):
				var low_pixel := lowest.get_pixel(center_x, row)
				var flat_pixel := flat.get_pixel(center_x, row)
				for channel: int in 3:
					low_delta = maxf(low_delta, absf(low_pixel[channel] - flat_pixel[channel]))
			var rows: Array[float] = []
			var chroma: Array[float] = []
			for row: int in range(168, 192):
				var pixel := captured.get_pixel(125, row)
				rows.append(_sample_luminance(pixel))
				chroma.append(pixel.r - pixel.b)
			var full_contrast := float(rows.max()) - float(rows.min())
			_check(low_delta < 0.002, "1%% 横纹应接近未开启 %s，像素最大差 %.3f" % [requested_size, low_delta])
			_check(full_contrast > 0.07 and full_contrast < 0.16, "满强度横纹能分辨，且避免深黑条纹 %s，明暗差 %.3f" % [requested_size, full_contrast])
			_check(float(chroma.max()) > 0.065 and float(chroma.min()) < -0.065, "灰底在固定明暗下有清楚的偏红和偏蓝横纹 %s" % requested_size)
			await create_timer(0.25).timeout
			var static_later := await _frame_image()
			var sample_rect := Rect2i(125, 168, 1, 24)
			_check(static_later.get_region(sample_rect).get_data() == captured.get_region(sample_rect).get_data(), "彩色横纹的亮度与位置随时间保持稳定 %s" % requested_size)
			var adjacent := captured.get_pixel(126, 192).r
			var third := captured.get_pixel(127, 192).r
			_check(maxf(absf(first - adjacent), absf(first - third)) < 0.01, "横向相邻像素保持同色，没有竖向格栅 %s" % requested_size)
			var inset := roundi(requested_size.y * 0.008)
			var opposite := requested_size - Vector2i(inset + 1, inset + 1)
			var corners := [Vector2i(inset, inset), Vector2i(opposite.x, inset), Vector2i(inset, opposite.y), opposite]
			var edge_light := captured.get_pixel(center_x, inset).r
			_check(edge_light > 0.35 and corners.all(func(at: Vector2i) -> bool: return captured.get_pixelv(at).r < edge_light * 0.25), "最外侧少量角落收弯，边缘中间保留画面 %s" % requested_size)
			_check(flat.get_pixelv(corners[0]).r > 0.35, "强度为零时四角平直 %s" % requested_size)
			await _test_curved_pointer(requested_size)
	root.size = Vector2i(1280, 720)
	await process_frame
	if DisplayServer.get_name() != "headless":
		var display_point := Vector2(1170, 25)
		await _send_window_mouse(InputEventMouseMotion.new(), display_point)
		for down: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			await _send_window_mouse(event, display_point)
		_check(shell.display_mode_option.get_popup().visible, "右上角实际被弯曲的分辨率按钮能展开下拉菜单")
		shell.display_mode_option.get_popup().hide()
	panel.crt_strength_slider.value = 0.0
	_check(not shell._crt_layer.visible and shell._crt_curvature == Vector2.ZERO, "合并强度归零时关闭整屏后处理和鼠标换算")
	panel.crt_strength_slider.value = 75.0
	await _click(panel.crt_option)
	_check(not shell._crt_layer.visible and not panel.crt_strength_slider.editable, "CRT开启时鼠标仍能命中开关并关闭")
	await _click(panel.crt_option)
	_check(panel.crt_strength_slider.value == 75.0, "开关保留 CRT 强度")
	probe.queue_free()
	panel.hide()
	main._on_escape_pause_menu_requested()
	while main._escape_pause_menu.is_transitioning(): await process_frame
	var pause_button := main._escape_pause_menu.find_child("PauseSettingsButton", true, false) as Button
	await _click(pause_button)
	var pause_settings: Control = main._escape_pause_menu._settings
	_check(pause_settings.crt_option.button_pressed and pause_settings.crt_strength_slider.value == 75.0, "局内暂停书读取同一 CRT 强度")
	_check(main._escape_pause_menu.book_rect.encloses(pause_settings._settings_body.get_rect()), "暂停书设置仍完整在纸面内")
	pause_settings.crt_strength_slider.value = 70.0
	_check(shell._preferences.crt_strength == 70.0 and shell._crt_curvature.is_equal_approx(CrtProjection.MAX_CURVATURE * 0.70), "暂停书内可调统一强度并实时更新画面")
	await _capture("settings")
	main._close_escape_pause_menu(false)
	await process_frame


func _test_hit() -> void:
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]:
		row.clear_squads()
	main.front_row.add_squad(SquadData.from_card(CARD), 0)
	main.enemy_front_row.add_squad(SquadData.from_card(CARD), 0)
	await process_frame
	_check(main.start_battle(674, false), "真实战斗初始化")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await process_frame
	shell._crt_layer.hide()
	await _capture("battle-flat")
	shell._crt_layer.show()
	await _capture("battle-crt")
	if "--capture" in OS.get_cmdline_user_args():
		var previous_strength: float = shell._preferences.crt_strength
		shell.set_crt_preference(true, 1.0)
		await _capture("battle-crt-strength-01")
		shell.set_crt_preference(true, 100.0)
		await _capture("battle-crt-strength-100")
		shell.set_crt_preference(true, previous_strength)
	var target: BattleSquadState = main.battle_controller.enemy_states[0]
	var slot := main._battle_state_slots.get(target) as BoardSlot
	target.current_armor = 5.0
	target.current_health = 30.0
	target.apply_damage_exact(0.0)
	_check(slot._battle_hit_flash == null, "零伤害没有受击反馈")
	slot.squad_lift_layer.position.y = -4.0
	target.apply_damage_exact(3.0)
	_check(target.current_armor == 2.0 and slot._battle_hit_flash.visible and slot.squad_lift_layer.position == Vector2(2, -4), "轻微纯护甲伤害闪白，横抖与出手抬升独立")
	_check(slot._battle_hit_flash.get_child_count() == 1 and main._pending_battle_damage_numbers.is_empty(), "低于大伤害阈值仍闪白，复用单卡剪影")
	var flash := slot._battle_hit_flash
	var attack := BattleEffectEvent.new()
	attack.visual_kind = &"fire_tick"
	attack.target = target
	attack.hellfire_adjusted = true
	target.apply_damage_exact(6.0, null, attack, true)
	main._play_battle_effect_visual(attack)
	var fire: BattleFireVisual = main._fire_burn_visuals.get(target)
	_check(target.current_health == 24.0 and slot._battle_hit_flash == flash and flash.visible and is_instance_valid(fire) and not fire.white_flash.visible, "灼烧伤害也走统一受击，火焰不叠第二层瞬白")
	var flash_alpha: float = flash.modulate.a
	paused = true
	await create_timer(0.14).timeout
	_check(flash.visible and flash.modulate.a == flash_alpha and slot.squad_lift_layer.position.x == 2.0, "战斗暂停时受击闪白和横抖冻结")
	await _capture("battle-flash")
	paused = false
	await create_timer(slot.BATTLE_HIT_SECONDS + 0.08).timeout
	_check(not flash.visible and is_zero_approx(slot.squad_lift_layer.position.x) and slot.squad_lift_layer.position.y == -4.0, "反馈短暂完成后回位，保留原有纵向抬升")
