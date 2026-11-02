extends "res://tests/shop_event_materials_20261020_test.gd"

const LabScene = preload("res://scenes/tools/CardFontLab.tscn")
const Settings = preload("res://scripts/ui/card_text_display_settings.gd")
const PROFILE := "/private/tmp/project-card-font-lab-test.cfg"


func _motion(point: Vector2, held := false) -> void:
	if DisplayServer.get_name() != "headless": Input.warp_mouse(shell.render_container.get_global_transform_with_canvas() * point)
	await super._motion(point, held)


func key_escape() -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_ESCAPE
	root.push_input(key, true)
	await process_frame
	key = key.duplicate()
	key.pressed = false
	root.push_input(key, true)
	await process_frame


func shot() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	return root.get_texture().get_image()


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("卡名字体调试专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-font-lab-run.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_720P)
	await create_timer(0.6).timeout
	var collection: Dictionary = main.owned_card_collection.capture_state()
	var original_font: Font = Settings.readable_font()
	var original_aa: int = original_font.base_font.antialiasing
	var original_sampling: float = original_font.base_font.oversampling
	var original_canvas: Transform2D = shell.internal_viewport.canvas_transform
	var original_filter: int = shell.render_container.texture_filter
	await key_escape()
	check(main._escape_pause_menu.is_menu_open(), "真实Esc打开暂停菜单")
	var entry := main._escape_pause_menu.find_child("CardFontLabButton", true, false) as Button
	check(entry != null and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(entry.get_global_rect()), "字体调试入口完整位于720p菜单内")
	check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(main._escape_pause_menu.find_child("PauseMenuPanel", true, false).get_global_rect()), "新增按钮后暂停菜单没有超出画布")
	await _click(entry)
	await create_timer(0.7).timeout
	var lab: Control = shell._card_font_lab
	check(is_instance_valid(lab) and not main.visible and not main._escape_pause_menu.is_processing_input(), "真实菜单进入调试器，隔离原游戏输入")
	if not is_instance_valid(lab): quit(1); return
	lab.profile_path = PROFILE
	lab.apply_profile(lab.DEFAULTS)
	await process_frame
	check(lab.comparisons.size() == 12, "四种字体和三种抗锯齿同时对比")
	for sample: Dictionary in lab.comparisons:
		check(sample.viewport.size == Vector2i(61, 9) and sample.viewport.canvas_transform == Transform2D.IDENTITY, "对比样本固定61×9原生像素，不提高渲染密度")
		check(sample.actual.texture == sample.enlarged.texture and sample.actual.texture.get_size() == Vector2(61, 9), "1×和4×直接显示同一张9px纹理")
	# 真实点击选中10px候选，改变的是名义字号，9px可用高度保持固定。
	await _click(lab.find_child("FontComparison_2_0", true, false))
	await process_frame
	check(lab.controls.font.selected == 2 and lab.controls.aa.selected == 0 and lab.controls["size"].value == 10, "点击样本格选中对应黑体和抗锯齿，使用该字体的原生字号")
	check(lab.selected.viewport.size == Vector2i(61, 9) and lab.selected.label.get_theme_font_size("font_size") == 10, "10号候选仍裁在9px高度，不偷偷扩大名字区域")
	var profile: Dictionary = lab.get_profile()
	profile.font = 0
	profile.aa = 0
	profile["size"] = 9
	profile.oversampling = 1
	profile.hint = 0
	profile.subpixel = 0
	profile.offset = 0
	profile.zoom = 8
	lab.apply_profile(profile)
	await process_frame
	if DisplayServer.get_name() != "headless":
		var image := await shot()
		var native: Image = lab.selected.viewport.get_texture().get_image()
		var palette := {}
		for y: int in native.get_height():
			for x: int in native.get_width(): palette[native.get_pixel(x, y).to_rgba32()] = true
		check(palette.size() == 2, "关闭抗锯齿且1倍采样时，GPU结果只有纸色和字色")
		var enlarged: Rect2 = lab.magnified.get_global_rect()
		var identical := true
		for y: int in 9:
			for x: int in 61:
				var native_color := native.get_pixel(x, y)
				for yy: int in 8:
					for xx: int in 8:
						var difference := image.get_pixel(int(enlarged.position.x) + x * 8 + xx, int(enlarged.position.y) + y * 8 + yy) - native_color
						if maxf(absf(difference.r), maxf(absf(difference.g), absf(difference.b))) > 0.01: identical = false
		check(identical, "8倍放大镜逐像素复制原图，没有重新用大字号渲染")
		profile.aa = 1
		lab.apply_profile(profile)
		await shot()
		var gray: Image = lab.selected.viewport.get_texture().get_image()
		palette.clear()
		for y: int in gray.get_height():
			for x: int in gray.get_width(): palette[gray.get_pixel(x, y).to_rgba32()] = true
		check(palette.size() > 2 and gray.get_data() != native.get_data(), "灰度抗锯齿真实产生边缘中间色，图像与关闭模式不同")
		var full: Image = lab.full_sample.viewport.get_texture().get_image()
		check(full.get_region(Rect2i(0, lab.FULL_INSET, 61, 9)).get_data() == gray.get_data(), "完整行盒红线内与9px裁切样本完全一致")
		profile.grid = true
		lab.apply_profile(profile)
		var final := await shot()
		final.save_png("/private/tmp/project-card-font-lab-comparison.png")
	profile.offset = 1
	lab.apply_profile(profile)
	await process_frame
	check(lab.selected.label.position.y == floorf((9.0 - lab.selected.label.size.y) * 0.5) + 1, "上下微调只移动字形，不改变9px采样区域")
	check(lab.save_profile() == OK, "调试参数保存到独立配置文件")
	var saved: Dictionary = lab.get_profile()
	var reopened := LabScene.instantiate()
	reopened.profile_path = PROFILE
	root.add_child(reopened)
	reopened.hide()
	await process_frame
	check(reopened.get_profile() == saved, "重新打开恢复所保存的字体、抗锯齿及位置参数")
	reopened.queue_free()
	check(shell.display_mode_option.get_parent().visible, "字体调试保留窗口倍率菜单，可自行切换720p／1080p／2K")
	for mode: int in [shell.DisplayMode.WINDOW_1080P, shell.DisplayMode.WINDOW_2K, shell.DisplayMode.WINDOW_720P]:
		shell.apply_display_mode(mode)
		await create_timer(0.6).timeout
		check(lab.selected.viewport.size == Vector2i(61, 9) and shell.internal_viewport.size == Vector2i(1280, 720), "切换窗口仍保持9px字形和原游戏画布：" + str(mode))
	check(original_font.base_font.antialiasing == original_aa and original_font.base_font.oversampling == original_sampling, "所有实验字体独立复制，不污染正式黑体资源")
	check(shell.internal_viewport.size == Vector2i(1280, 720) and shell.internal_viewport.canvas_transform == original_canvas and shell.render_container.texture_filter == original_filter, "原游戏画布和窗口采样方案没有改变")
	await key_escape()
	await create_timer(0.6).timeout
	check(not shell.is_card_font_lab_open() and main.visible and main._escape_pause_menu.is_processing_input(), "真实Esc返回原游戏并恢复输入")
	check(main.owned_card_collection.capture_state() == collection, "字体调试不改变卡牌实例或阵容")
	shell.queue_free()
	await process_frame
	print("卡名字体调试：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
