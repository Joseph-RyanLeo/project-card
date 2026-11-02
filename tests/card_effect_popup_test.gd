extends "res://tests/shop_event_materials_20261020_test.gd"

const Settings = preload("res://scripts/ui/card_text_display_settings.gd")
const CardScene = preload("res://scenes/ui/CardView.tscn")


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("卡牌文字弹窗专项超时"); quit(1))
	# 本专项验证默认字体，不能继承玩家在字体调试器中应用的本机参数。
	Settings.load_settings("/private/tmp/project-card-effect-popup-default-font.cfg")
	Settings.set_mode(self, Settings.Mode.CARD, false)
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-effect-popup-test.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_1080P)
	await create_timer(0.5).timeout
	main.set_world_view(main.WorldView.COLLECTION, false)
	var definition: CardData = load("res://resources/cards/militia.tres")
	var owned: OwnedCard = main.owned_card_collection.create_card(definition)
	var view := _show_owned(owned)
	await process_frame
	check(view.name_clip.size == Vector2(61, 9), "名字可用区域为61×9px")
	await _motion(view.get_global_rect().get_center())
	await create_timer(0.55).timeout
	check(view.showing_effect and view._hover_effect_active, "默认卡牌显示保留原悬停效果")
	await _motion(Vector2(1270, 700))
	await create_timer(0.3).timeout
	var menu: EscapePauseMenu = main._escape_pause_menu
	menu.open_menu()
	var option := menu.find_child("CardTextDisplayMode", true, false) as OptionButton
	check(option != null and option.item_count == 2 and option.selected == 0, "Esc提供卡牌显示和弹窗显示")
	# 通过共用设置入口切换，测试不写玩家本机偏好文件。
	Settings.set_mode(self, Settings.Mode.POPUP, false)
	check(option.selected == 1, "模式同步到Esc控件")
	menu.close_menu()
	check(Settings.readable_font().has_char("灰".unicode_at(0)) and Settings.readable_font().has_char("烬".unicode_at(0)), "项目内黑体独立包含中文字符")
	check(view.name_label.get_theme_font("font") == Settings.readable_font() and view.name_label.get_theme_font_size("font_size") == 9, "短卡名使用顶满高度的9px黑体，不因行高缩小")
	check(Settings.readable_font().variation_opentype.get(TextServerManager.get_primary_interface().name_to_tag("weight")) == 500.0, "黑体字重使用真正的OpenType字重轴")
	await _motion(view.get_global_rect().get_center())
	await create_timer(0.55).timeout
	var popup = get_first_node_in_group(&"card_effect_popup")
	check(popup != null and popup.panel.visible and popup.source == view, "真实收藏悬停打开唯一弹窗")
	if popup == null: quit(1); return
	check(popup.get_viewport() == root and popup.get_viewport() != shell.internal_viewport, "弹窗在实际窗口分辨率绘制")
	check(not view.showing_effect and not view.effect_text_label.visible and is_equal_approx(view.rune_row.modulate.a, 1), "弹窗模式不渐隐符文或叠加卡面效果")
	check(popup.title.text == definition.display_name and popup.body.text.replace("\n", "").replace(" ", "") == view.get_effect_popup_text().replace("\n", "").replace(" ", ""), "弹窗完整使用当前实例的名字与效果")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-effect-popup-short.png")
	var short_width: float = popup.panel.size.x
	var sample := definition.duplicate(true) as CardData
	sample.effect_text = "行动时对目标造成伤害，为相邻友军增加护甲，随后恢复生命并永久提高行动值；在前排获得热诚，在后排为小队提供额外护盾。"
	var sample_view := CardScene.instantiate() as CardView
	sample_view.set_card_data(sample)
	main.add_child(sample_view)
	sample_view.position = Vector2(600, 480)
	sample_view.show_effect_popup()
	await process_frame
	check(popup.panel.size.x > short_width and popup.body.get_line_count() <= 3, "长描述向两侧扩宽，正文最多三行")
	check(popup.body.text.replace("\n", "").replace(" ", "") == sample.effect_text, "长描述没有省略或裁掉第四行")
	check(absf(popup.panel.get_global_rect().get_center().x - shell.render_container.scale.x * sample_view.get_global_rect().get_center().x) < 2, "弹窗围绕卡面中心向两侧扩展")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-effect-popup-long.png")
	# 所有正式卡的正文均做实际字体排版，防止个别长效果被三行上限截断。
	var files := DirAccess.get_files_at("res://resources/cards")
	for file: String in files:
		if not file.ends_with(".tres"): continue
		var data := load("res://resources/cards/" + file) as CardData
		if data == null: continue
		sample_view.set_card_data(data)
		sample_view.show_effect_popup()
		check(popup.body.text.count("\n") < 3 and popup.body.text.replace("\n", "").replace(" ", "") == sample_view.get_effect_popup_text().replace("\r", "").replace("\n", "").replace(" ", ""), "正式卡完整三行：" + data.display_name)
	sample_view.set_card_data(sample)
	for point: Vector2 in [Vector2(0, 0), Vector2(1180, 0), Vector2(0, 584), Vector2(1180, 584)]:
		sample_view.position = point
		sample_view.show_effect_popup()
		await process_frame
		check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(popup.panel.get_global_rect()), "窗口边缘自动避让：" + str(point))
	sample_view.hide()
	await process_frame
	check(not popup.panel.visible, "来源隐藏时收起弹窗")
	sample_view.show()
	sample_view.show_effect_popup()
	menu.open_menu()
	await process_frame
	check(not popup.panel.visible, "Esc打开立即收起弹窗")
	check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(menu.find_child("PauseMenuPanel", true, false).get_global_rect()), "增加显示模式后Esc菜单仍完整落在720p画布内")
	menu.close_menu()
	for display_mode: int in [shell.DisplayMode.WINDOW_720P, shell.DisplayMode.WINDOW_2K, shell.DisplayMode.WINDOW_1080P]:
		shell.apply_display_mode(display_mode)
		await create_timer(0.6).timeout
		sample_view.position = Vector2(600, 480)
		sample_view.show_effect_popup()
		await process_frame
		check(popup.body.get_theme_font_size("font_size") == roundi(16 * shell.render_container.scale.x) and Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(popup.panel.get_global_rect()), "窗口倍率变化后重排字体和位置：" + str(display_mode))
	await _motion(Vector2(1270, 700))
	await _motion(view.get_global_rect().get_center())
	await create_timer(0.55).timeout
	await _mouse(view.get_global_rect().get_center(), true)
	check(not popup.panel.visible, "按下鼠标开始交互立即收起弹窗")
	await _mouse(view.get_global_rect().get_center(), false)
	main._cancel_click_carry()
	# 右键放大仍能读到短效果，不会因卡面底栏隐藏而丢失入口。
	main._open_card_inspection(view.card_data, owned, view)
	await create_timer(0.35).timeout
	check(is_instance_valid(main._inspection_overlay.get_node_or_null("InspectionEffectSideBox")) and not main._inspection_display_mode_button.visible, "弹窗模式右键检视保留黑体效果说明，隐藏失效的翻面按钮")
	check(main._inspection_surface.render_scale >= 4, "放大检视的黑体卡名使用4倍字形合成")
	main._close_card_inspection(true)
	await create_timer(0.35).timeout
	Settings.set_mode(self, Settings.Mode.CARD, false)
	check(view.name_label.get_theme_font("font") == CardView.CARD_TEXT_FONT, "切回卡牌显示恢复像素字体")
	sample_view.queue_free()
	shell.queue_free()
	await process_frame
	await process_frame
	check(not popup.panel.visible, "来源场景释放后无残留弹窗")
	popup.queue_free()
	await process_frame
	print("卡牌弹窗专项：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
