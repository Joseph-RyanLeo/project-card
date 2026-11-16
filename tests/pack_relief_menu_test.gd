extends "res://tests/card_pack_opening_test.gd"

const EffectSettings = preload("res://scripts/ui/pack_opening_effect_settings.gd")
const PackArt = preload("res://scripts/ui/pack_tear_art.gd")

## 通过真实 Esc 和菜单按钮验证主界面／稀有商店的进入、缩放和返回。
func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("卡包凹凸菜单验收超时"); quit(1))
	var settings_path := "/private/tmp/project-card-pack-relief-menu-%d.cfg" % OS.get_process_id()
	EffectSettings.load_saved(settings_path)
	EffectSettings.set_value("peel_lift", 18.0)
	EffectSettings.save()
	shell = DISPLAY.instantiate()
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = false
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(.7).timeout
	main = shell.main_screen
	var old_mode: int = main.process_mode
	var old_window_scale: Vector2i = root.content_scale_size
	var collection: Dictionary = main.owned_card_collection.capture_state()
	var reward: Dictionary = main.run_reward_state.capture_state()
	await open_from_menu()
	var preview: Control = shell._pack_effect_tuner
	check(is_instance_valid(preview) and preview.has_method("set_debug_view"), "Esc新入口打开卡包凹凸调试")
	if not is_instance_valid(preview): quit(1); return
	check(not main.visible and not main._escape_pause_menu.is_processing_input(), "调试时隔离原游戏画面与Esc")
	check(is_equal_approx(preview.lighting_controls.light_mouse_influence.slider.value, 80.0) and is_equal_approx(preview.lighting_controls.light_angle_degrees.slider.value, 60.0) and is_equal_approx(preview.lighting_controls.light_front.slider.value, 0.2) and is_equal_approx(preview.lighting_controls.light_brightness.slider.value, 0.95) and preview.lighting_controls.light_angle_degrees.slider.editable, "打开即使用60°／0.20／0.95倍／80%固定预设，方向仍可试调")
	check(root.content_scale_size == old_window_scale, "嵌入预览不改变窗口内容倍率")
	var bounds := Rect2(preview.position, preview.CANVAS_SIZE * preview.scale)
	check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(bounds), "完整预览与返回按钮位于游戏画布内")
	var rect: Rect2 = preview.body_slider.get_global_rect()
	await click(Vector2(rect.position.x + rect.size.x * .7, rect.get_center().y))
	check(preview.body_slider.value > 1.0 and is_equal_approx(preview.gold_slider.value, 0.45), "真实拖点袋身滑块不改变金纹强度")
	var body_value: float = preview.body_slider.value
	rect = preview.gold_slider.get_global_rect()
	await click(Vector2(rect.position.x + rect.size.x * .3, rect.get_center().y))
	check(not is_equal_approx(preview.gold_slider.value, 0.45) and is_equal_approx(preview.body_slider.value, body_value), "真实拖点金纹滑块不改变袋身强度")
	var gold_value: float = preview.gold_slider.value
	# 实际鼠标在面板上调参时，保留刚才选定的倾斜，不再把灯光和画面一起归零。
	for surface: InspectionCardSurface in [preview.original, preview.sample]:
		surface.force = Vector2(0.45, -0.2)
		surface.effect.set_shader_parameter("pointer_force", surface.force)
	var panel_point: Vector2 = preview.lighting_panel.get_global_rect().get_center()
	root.warp_mouse(Vector2i(shell.render_container.get_global_transform_with_canvas() * panel_point))
	await create_timer(.25).timeout
	check(preview.sample.force.is_equal_approx(Vector2(0.45, -0.2)), "鼠标进入调光面板时保留检视姿态")
	for field: Dictionary in preview.LIGHT_FIELDS:
		var slider: HSlider = preview.lighting_controls[field.key].slider
		var before: float = slider.value
		var before_image: Image = await capture_preview_card(preview)
		rect = slider.get_global_rect()
		check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(rect), "光源滑块完整显示：" + str(field.label))
		var fraction := .1 if field.key == "light_front" else .35
		await click(Vector2(rect.position.x + rect.size.x * fraction, rect.get_center().y))
		check(not is_equal_approx(slider.value, before) and is_equal_approx(float(preview.sample.effect.get_shader_parameter(field.key)), slider.value * float(field.scale)), "光源滑块真实点击立即更新材质：" + str(field.label))
		var after_image: Image = await capture_preview_card(preview)
		var visible_pixels := 0
		for y: int in range(before_image.get_height()):
			for x: int in range(before_image.get_width()):
				var delta := before_image.get_pixel(x, y) - after_image.get_pixel(x, y)
				if absf(delta.r) + absf(delta.g) + absf(delta.b) > 0.02: visible_pixels += 1
		check(visible_pixels > 100, "光源滑块真实操作在卡包上产生可见变化：%s %d像素" % [field.label, visible_pixels])
	preview.lighting_controls.light_mouse_influence.slider.value = 100.0
	check(not preview.lighting_controls.light_angle_degrees.slider.editable and preview.lighting_controls.light_angle_degrees.label.text.contains("鼠标接管"), "完全跟随时明确禁用无效的方向滑块")
	preview.lighting_controls.light_mouse_influence.slider.value = 50.0
	check(preview.lighting_controls.light_angle_degrees.slider.editable, "降低鼠标影响后方向恢复可调")
	check(is_equal_approx(preview.body_slider.value, body_value) and is_equal_approx(preview.gold_slider.value, gold_value), "四项光照调节保留两个凹凸滑块的数值")
	await click(preview.find_child("ResetReliefDefaults", true, false).get_global_rect().get_center())
	check(is_equal_approx(preview.body_slider.value, 0.15) and is_equal_approx(preview.gold_slider.value, 0.45) and is_equal_approx(preview.lighting_controls.light_mouse_influence.slider.value, 80.0) and is_equal_approx(preview.lighting_controls.light_angle_degrees.slider.value, 60.0) and is_equal_approx(preview.lighting_controls.light_front.slider.value, 0.2) and is_equal_approx(preview.lighting_controls.light_brightness.slider.value, 0.95), "恢复默认按钮重置凹凸和用户确认的四项光照预设")
	await RenderingServer.frame_post_draw
	shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-pack-relief-menu.png")
	check(preview.pack_selector.item_count == 6, "凹凸调试器可以切换大包与五种小包样式")
	preview.pack_selector.item_selected.emit(1)
	var gilded := preview.sample.effect as ShaderMaterial
	check(preview.sample.size == Vector2(115, 174) and gilded.get_shader_parameter("use_center_height") == true and gilded.get_shader_parameter("center_height_origin_px") == Vector2(37, 49), "选择镀金委托后使用正式小包与火漆坐标")
	await verify_gilded_trim(preview)
	preview.gold_slider.value = 1.0
	check(is_equal_approx(float(gilded.get_shader_parameter("center_height_strength")), 1.0) and is_equal_approx(preview.body_slider.value, 0.15), "火漆滑块独立于袋身")
	preview.set_debug_view(1)
	preview.pack_selector.item_selected.emit(2)
	check(preview.sample.effect.get_shader_parameter("use_center_height") == false and not preview.gold_slider.editable and preview.sample.effect.get_shader_parameter("debug_view") == 1, "普通小包关闭印记滑块并保留调试视图")
	preview.pack_selector.item_selected.emit(1)
	check(is_equal_approx(preview.gold_slider.value, 1.0), "切回镀金委托保留本次试调的火漆强度")
	preview.set_debug_view(0)
	preview.reset_defaults()
	check(is_equal_approx(preview.gold_slider.value, 0.15), "恢复默认还原火漆强度")
	preview.gold_slider.value = 0.35
	preview.body_slider.value = 0.25
	preview.lighting_controls.light_brightness.slider.value = 0.85
	var save := preview.find_child("SaveReliefSettings", true, false) as Button
	check(Rect2(0, 0, 1280, 720).encloses(save.get_global_rect()), "保存按钮完整位于画布内")
	await click(save.get_global_rect().get_center())
	var stored := ConfigFile.new()
	check(stored.load(settings_path) == OK and is_equal_approx(float(stored.get_value("relief", "center_height_strength", 0.0)), 0.35)
		and is_equal_approx(float(stored.get_value("opening", "peel_lift", 0.0)), 18.0), "实际点击保存写入火漆且保留既有开包设置")
	EffectSettings.save()
	EffectSettings.load_saved()
	var formal := PackArt.create_relief(Vector2(115, 174), PackArt.GILDED_WRAPPER)
	check(is_equal_approx(float(formal.get_shader_parameter("body_strength")), 0.25)
		and is_equal_approx(float(formal.get_shader_parameter("center_height_strength")), 0.35)
		and is_equal_approx(float(formal.get_shader_parameter("light_brightness")), 0.85), "原开包保存保留凹凸，正式材质读取保存后的袋身、火漆和光照")
	await key(KEY_ESCAPE)
	await create_timer(.65).timeout
	check(not shell.is_pack_effect_tuner_open() and main.visible and main.process_mode == old_mode, "Esc返回原界面并恢复处理模式")
	check(main._escape_pause_menu.is_processing_input() and not main._escape_pause_menu.is_menu_open(), "退出Esc不穿透重开暂停菜单")
	await open_from_menu()
	preview = shell._pack_effect_tuner
	check(is_equal_approx(preview.body_slider.value, 0.25) and is_equal_approx(preview.lighting_controls.light_brightness.slider.value, 0.85), "退出重进读取已保存的袋身与光照")
	preview.select_pack(1)
	check(is_equal_approx(preview.gold_slider.value, 0.35), "退出重进读取已保存的镀金委托火漆")
	await click(preview.find_child("CloseReliefPreview", true, false).get_global_rect().get_center())
	await create_timer(.65).timeout
	check(not shell.is_pack_effect_tuner_open() and main.visible, "返回按钮同样恢复来源界面")
	check(main.owned_card_collection.capture_state() == collection and main.run_reward_state.capture_state() == reward, "凹凸预览不修改收藏与金币")
	# 原调整器的入口和返回也经过同一显示壳，按真实转场完成事件验证。
	await key(KEY_ESCAPE)
	await open_tools_subpage()
	var old_entry := main._escape_pause_menu._tools.find_child("PackEffectTunerButton", true, false) as Button
	check(is_instance_valid(old_entry) and old_entry.is_visible_in_tree(), "原开包特效调整器入口保留")
	await click(old_entry.get_global_rect().get_center())
	if shell.screen_transition.busy: await shell.screen_transition.finished
	var old_tuner: Control = shell._pack_effect_tuner
	var effect_settings := preload("res://scripts/ui/pack_opening_effect_settings.gd")
	check(is_instance_valid(old_tuner) and old_tuner.controls.size() == effect_settings.FIELDS.size(), "原入口仍加载全部开包参数")
	if not is_instance_valid(old_tuner): quit(1); return
	var tabs := old_tuner.find_child("ParameterTabs", true, false) as TabContainer
	tabs.current_tab = 1
	await process_frame
	var old_slider: HSlider = old_tuner.controls.tear_shake_pixels.slider
	var old_value: float = old_slider.value
	rect = old_slider.get_global_rect()
	await click(Vector2(rect.position.x + rect.size.x * .75, rect.get_center().y))
	check(not is_equal_approx(old_slider.value, old_value) and is_equal_approx(old_tuner.controls.tear_shake_pixels.spin.value, old_slider.value), "转场完成后原滑块真实点击与数值框联动")
	await key(KEY_ESCAPE)
	if shell.screen_transition.busy: await shell.screen_transition.finished
	await process_frame
	check(not shell.is_pack_effect_tuner_open() and main.visible and main._escape_pause_menu.is_processing_input(), "原调整器转场完成后正常返回")
	check(shell.open_rare_shop(), "打开稀有商店以验证来源返回")
	await create_timer(.5).timeout
	var rare_shop: Control = shell._rare_shop
	main = rare_shop
	await open_from_menu()
	check(shell.is_pack_effect_tuner_open() and not rare_shop.visible, "稀有商店菜单也能打开凹凸调试")
	await key(KEY_ESCAPE)
	await create_timer(.65).timeout
	check(not shell.is_pack_effect_tuner_open() and rare_shop.visible and rare_shop._escape_pause_menu.is_processing_input(), "退出后返回同一稀有商店会话")
	shell.close_rare_shop()
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(settings_path)
	print("PACK RELIEF MENU failures: ", failures)
	quit(1 if failures else 0)

func open_from_menu() -> void:
	await key(KEY_ESCAPE)
	check(main._escape_pause_menu.is_menu_open(), "真实Esc打开暂停菜单")
	await open_tools_subpage()
	var entry := main._escape_pause_menu.find_child("PackReliefPreviewButton", true, false) as Button
	check(is_instance_valid(entry) and entry.is_visible_in_tree(), "开发工具页包含卡包凹凸调试按钮")
	if not is_instance_valid(entry): return
	check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(entry.get_global_rect()), "菜单入口位于画布内")
	await click(entry.get_global_rect().get_center())
	if shell.screen_transition.busy: await shell.screen_transition.finished

func open_tools_subpage() -> void:
	var button := main._escape_pause_menu.find_child("DeveloperToolsButton", true, false) as Button
	await click(button.get_global_rect().get_center())
	await process_frame

func capture_preview_card(preview: Control) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	return shell.internal_viewport.get_texture().get_image().get_region(Rect2i(preview.sample.get_global_rect()))

func verify_gilded_trim(preview: Control) -> void:
	var material: ShaderMaterial = preview.sample.effect
	preview.set_process(false)
	material.set_shader_parameter("use_3d", false)
	var metal := await capture_preview_card(preview)
	metal.save_png("/private/tmp/project-card-gilded-trim-preview.png")
	var controlled_parameters := {}
	for key: String in ["body_strength", "center_height_strength", "light_brightness", "pointer_force"]:
		controlled_parameters[key] = material.get_shader_parameter(key)
	material.set_shader_parameter("body_strength", 0.0)
	material.set_shader_parameter("center_height_strength", 0.0)
	material.set_shader_parameter("light_brightness", 1.0)
	material.set_shader_parameter("pointer_force", Vector2(-0.8, -0.1))
	metal = await capture_preview_card(preview)
	material.set_shader_parameter("pointer_force", Vector2(0.6, 0.4))
	var shifted := await capture_preview_card(preview)
	material.set_shader_parameter("extra_gold_color", Vector3(-1, -1, -1))
	var paper := await capture_preview_card(preview)
	var source := PackArt.GILDED_WRAPPER.get_image()
	var scale := Vector2(metal.get_size()) / Vector2(source.get_size())
	for point: Vector2i in [Vector2i(15, 23), Vector2i(57, 33), Vector2i(92, 25), Vector2i(22, 87), Vector2i(24, 145), Vector2i(94, 132)]:
		var target := Vector2i((Vector2(point) + Vector2(0.5, 0.5)) * scale)
		var base := paper.get_pixelv(target)
		var a := metal.get_pixelv(target)
		var b := shifted.get_pixelv(target)
		check(source.get_pixelv(point).is_equal_approx(Color("ffc03d")) and base.is_equal_approx(Color("ffc03d"))
			and minf(a.g, b.g) >= base.g and minf(a.b, b.b) >= base.b, "绿圈金纹保留原来的金橙底色 " + str(point))
	var moved_pixels := 0
	var peak_highlight := 0.0
	for y: int in source.get_height():
		for x: int in source.get_width():
			if not source.get_pixel(x, y).is_equal_approx(Color("ffc03d")): continue
			var target := Vector2i((Vector2(x, y) + Vector2(0.5, 0.5)) * scale)
			if absf(metal.get_pixelv(target).b - shifted.get_pixelv(target).b) > 0.025: moved_pixels += 1
			peak_highlight = maxf(peak_highlight, maxf(metal.get_pixelv(target).b, shifted.get_pixelv(target).b) - paper.get_pixelv(target).b)
	check(moved_pixels > 100, "金橙色纹路上仍有随鼠标移动的金属高光")
	check(peak_highlight > 0.30, "金纹高光峰值比上一版更强")
	for point: Vector2i in [Vector2i(30, 44), Vector2i(57, 69), Vector2i(50, 100), Vector2i(57, 8)]:
		var target := Vector2i((Vector2(point) + Vector2(0.5, 0.5)) * scale)
		check(shifted.get_pixelv(target) == paper.get_pixelv(target), "底纸、火漆、原锦缎和透明区不受新增遮罩影响 " + str(point))
	for key: String in controlled_parameters:
		material.set_shader_parameter(key, controlled_parameters[key])
	material.set_shader_parameter("extra_gold_color", PackArt.GILDED_TRIM_COLOR)
	material.set_shader_parameter("use_3d", true)
	preview.set_process(true)
