extends "res://tests/card_font_lab_test.gd"

const CARD_PREFS := "/private/tmp/project-card-font-apply-settings.cfg"
const LAB_PREFS := "/private/tmp/project-card-font-apply-lab.cfg"
const CardScene := preload("res://scenes/ui/CardView.tscn")


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("卡名字体应用专项超时"); quit(1))
	Settings._name_profile = {}
	Settings._applied_name_font = null
	Settings.set_mode(self, Settings.Mode.CARD, false)
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-font-apply-run.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_720P)
	await create_timer(0.6).timeout
	var saved_collection: Dictionary = main.owned_card_collection.capture_state()
	var body_font: Font = Settings.readable_font()
	var names := {}
	for view: Node in get_nodes_in_group(&"card_views"):
		if view.card_data != null: names[view.get_instance_id()] = view.card_data.display_name
	await key_escape()
	await _click(main._escape_pause_menu.find_child("CardFontLabButton", true, false))
	await create_timer(0.7).timeout
	var lab: Control = shell._card_font_lab
	lab.profile_path = LAB_PREFS
	lab.card_settings_path = CARD_PREFS
	var profile: Dictionary = lab.DEFAULTS.duplicate()
	profile.font = 2
	profile.aa = 0
	profile["size"] = 10
	profile.oversampling = 1
	profile.subpixel = 0
	profile.hint = 0
	profile.offset = 1
	profile.text = "重返战场"
	lab.apply_profile(profile)
	await process_frame
	var preview: Image
	if DisplayServer.get_name() != "headless":
		await shot()
		preview = lab.selected.viewport.get_texture().get_image()
	var apply := lab.find_child("ApplyFontToCards", true, false) as Button
	check(apply != null and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(apply.get_global_rect()), "调试器包含完整可点击的应用到卡牌按钮")
	await _click(apply)
	await create_timer(0.7).timeout
	check(not shell.is_card_font_lab_open() and main.visible and main._escape_pause_menu.is_processing_input(), "真实点击应用后自动返回来源游戏并恢复输入")
	check(not Settings.is_popup_mode(), "应用字体保留原卡牌／弹窗显示模式")
	var active := Settings.get_name_profile()
	check(active.font == 2 and active.aa == 0 and active.offset == 1 and active["size"] == 10, "应用字体、抗锯齿、上下偏移和字号")
	check(not active.has("text") and not active.has("zoom") and not active.has("grid"), "调试样本文字和放大镜参数不进入正式卡名设置")
	for view: Node in get_nodes_in_group(&"card_views"):
		if view.card_data == null: continue
		var font: FontFile = view.name_label.get_theme_font("font")
		check(font.antialiasing == TextServer.FONT_ANTIALIASING_NONE and font.oversampling == 1 and font.hinting == TextServer.HINTING_NONE, "现有卡面同步采样与抗锯齿：" + view.card_data.display_name)
		check(view.name_clip.position == Vector2(21, 6) and view.name_clip.size == Vector2(61, 9) and view.name_clip.clip_contents and view.card_name_frame.position == Vector2(0, 4) and view.card_name_frame.size == Vector2(83, 13), "83×13名称牌内卡名下移1px，继续固定61×9px并裁切")
		check(view.name_label.text == names.get(view.get_instance_id(), view.card_data.display_name), "应用参数不替换真实卡名")
	check(Settings.readable_font() == body_font and body_font.base_font.oversampling == 4, "正文与弹窗字体资源不受卡名应用影响")
	var config := ConfigFile.new()
	check(config.load(CARD_PREFS) == OK and config.get_value("cards", "name_font_profile", {}) == active, "已应用参数独立持久保存")
	Settings.load_settings(CARD_PREFS)
	check(Settings.get_name_profile() == active and not Settings.is_popup_mode(), "重新载入偏好恢复应用参数及原显示模式")
	var view := CardScene.instantiate() as CardView
	view.set_card_data(load("res://resources/cards/return_to_battlefield.tres"))
	main.add_child(view)
	view.position = Vector2(570, 330)
	check(view.name_clip.size == Vector2(61, 9) and view.name_label.get_theme_font_size("font_size") == 10, "重新加载后新建卡面直接使用已应用字体与9px区域")
	check(view.name_label.position == Vector2(0, floorf((9.0 - view.name_label.size.y) * 0.5) + 1), "新卡名与调试器使用相同的上下微调")
	if DisplayServer.get_name() != "headless":
		var image := await shot()
		image.save_png("/private/tmp/project-card-font-applied-game.png")
		# 保留真实CardView的名字节点，隔离其他图层后核对原生9px字形。
		for child: Node in view.get_children():
			if child is CanvasItem and child != view.top_row: child.hide()
		for child: Node in view.top_row.get_children():
			if child is CanvasItem and child != view.name_clip: child.hide()
		var native := SubViewport.new()
		native.size = Vector2i(61, 9)
		native.disable_3d = true
		native.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(native)
		var paper := ColorRect.new()
		paper.size = Vector2(61, 9)
		paper.color = lab_color()
		native.add_child(paper)
		view.reparent(native)
		view.pivot_offset = Vector2.ZERO
		view.position = -view.title_area_position
		view.scale = Vector2.ONE
		await shot()
		preview.save_png("/private/tmp/project-card-font-apply-preview.png")
		native.get_texture().get_image().save_png("/private/tmp/project-card-font-apply-card.png")
		check(native.get_texture().get_image().get_data() == preview.get_data(), "真实卡面9px字形逐像素等于调试器当前预览")
		native.queue_free()
	else:
		view.queue_free()
	Settings.set_mode(self, Settings.Mode.POPUP, false)
	var extra := CardScene.instantiate() as CardView
	var long_name := (load("res://resources/cards/return_to_battlefield.tres") as CardData).duplicate() as CardData
	long_name.display_name = "测试这个很长很长的卡牌名字"
	extra.set_card_data(long_name)
	main.add_child(extra)
	check(extra.name_label.get_theme_font_size("font_size") < 10 and extra.name_clip.size == Vector2(61, 9), "切换显示模式后保留应用参数，长名缩字仍限制在9px高")
	profile.fit = false
	check(Settings.apply_name_profile(self, profile, CARD_PREFS) == OK and extra.name_label.get_theme_font_size("font_size") == 10, "关闭长名缩字时真实卡面按调试字号裁切")
	check(main.owned_card_collection.capture_state() == saved_collection and shell.internal_viewport.size == Vector2i(1280, 720) and shell.internal_viewport.canvas_transform == Transform2D.IDENTITY, "应用只改卡名显示，不改实例数据和游戏渲染方案")
	shell.queue_free()
	await process_frame
	print("卡名字体应用：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)


func lab_color() -> Color:
	return load("res://scripts/tools/card_font_lab.gd").PAPER
