extends "res://tests/d3_4_ui_test.gd"

## 短路径验证纵深落包与卡牌透明留白处的真实像素亮度。
const VISUAL_DIR := "/private/tmp/project-card-pack-depth-test"
const ArrivalSettings = preload("res://scripts/ui/pack_opening_effect_settings.gd")
const Arrival = preload("res://scripts/ui/pack_arrival_animation.gd")
var main
var _motion_previews: Dictionary = {}


func capture_depth(label: String, defer_save: bool = false) -> void:
	await RenderingServer.frame_post_draw
	var preview := root.get_texture().get_image()
	if defer_save:
		_motion_previews[label] = preview
		return
	var directory := "res://docs/previews/d3_4_20261106"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	preview.save_png(directory.path_join(label + ".png"))


func _run() -> void:
	create_timer(35).timeout.connect(func(): push_error("纵深与暗幕专项超时"); quit(1))
	ArrivalSettings.load_saved("/private/tmp/project-card-arrival-defaults.cfg")
	ArrivalSettings.reset_defaults()
	var values := ArrivalSettings.get_values()
	DirAccess.make_dir_recursive_absolute(VISUAL_DIR)
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = VISUAL_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await frames()
	check(await shell.start_slot(0), "创建隔离档")
	check(shell.slot_progress.select_catalog_tasks("tutorial", ""), "隔离档正式选择M1")
	# 走玩家实际使用的完整黑场／加载／淡入流程，不重播入场动画绕开黑场。
	shell.change_screen.call_deferred(shell.start_new_slot_run.bind(true), true)
	while not is_instance_valid(shell.main_screen) or not shell.main_screen.startup_complete: await process_frame
	main = shell.main_screen
	var maze = main.maze_controller
	var button: TextureButton = maze._initial_pack_button
	check(shell.screen_transition.busy and not maze._initial_pack_drop.is_running(), "完整加载黑幕内暂停落包，不提前播放")
	var covered_pose := button.position
	maze.refresh()
	await frames()
	check(button.position == covered_pose and maze._initial_pack_drop.get_total_elapsed_time() == 0.0 and button.scale.x == values.arrival_start_scale, "黑场期间刷新和等待不消耗左侧初始姿态")
	var impacts: Array[Control] = []
	maze._initial_pack_prompt.child_entered_tree.connect(func(child: Node):
		if child.get_script() == preload("res://scripts/ui/event_landing_dust.gd"): impacts.append(child))
	await shell.screen_transition.finished
	var visible_started := Time.get_ticks_usec()
	check(button.scale.x > values.arrival_start_scale - 0.1 and maze._initial_pack_drop.get_total_elapsed_time() < 0.05, "玩家首个可见画面才从近处大尺寸开始")
	var start_center := button.get_global_transform_with_canvas() * (button.size * 0.5)
	check(start_center.distance_to(Arrival.point(values, "start")) < 2 and button.rotation < 0, "首个可见画面的卡包就位于左侧")
	check(start_center.x < 300 and absf(rad_to_deg(button.rotation)) >= 45, "入场位置更偏左且侧飞倾角明显增大")
	check(button.material == null, "取消透视着色器，包装只保留平面旋转与等比缩放")
	await capture_depth("05_pack_depth_near", true)
	await create_timer(0.32).timeout
	check(button.scale.x > 1 and button.scale.x < values.arrival_start_scale, "落下过程中持续从大变小")
	var mid_center := button.get_global_transform_with_canvas() * (button.size * 0.5)
	check(mid_center.x > start_center.x and mid_center.y < start_center.y and button.disabled, "从左侧沿参考低弧线先略抬起再落下，途中不可误触")
	check(is_equal_approx(button.scale.x, button.scale.y) and impacts.is_empty(), "下降保持包装比例，未着地前不播放烟尘")
	await capture_depth("06_pack_depth_mid", true)
	await maze._initial_pack_prompt.child_entered_tree
	check(Time.get_ticks_usec() - visible_started >= int((Arrival.timing(values).x - 0.08) * 1000000), "首次着地发生在黑幕退出后的完整下落时间之后")
	check(impacts.size() == 1 and button.scale.is_equal_approx(Vector2.ONE), "首次着地复用事件牌烟尘，包装不压扁")
	check(button.material == null and absf(rad_to_deg(button.rotation)) >= 20, "1倍着地保留平面倾角，没有透视侧倾")
	var contact_center := Arrival.point(values, "contact")
	check(contact_center.x < 300 and contact_center.y > 290 and contact_center.y < 320, "着地点对应参考图左侧弧线转为滑行的位置")
	check(Vector2(640, 360).distance_to(contact_center) >= 180, "着地后保留至少180逻辑像素的清晰滑行距离")
	check((impacts[0].position + impacts[0].EFFECT_SIZE * 0.5).distance_to(contact_center) < 1, "首次落地特效准确跟随偏左的着地点")
	var impact_preview: Image
	var speeds: Array[float] = []
	var previous_x := button.position.x
	var previous_time: float = maze._initial_pack_drop.get_total_elapsed_time()
	for index: int in 3:
		await create_timer(0.05).timeout
		var elapsed: float = maze._initial_pack_drop.get_total_elapsed_time()
		speeds.append((button.position.x - previous_x) / (elapsed - previous_time) if elapsed > previous_time else 0.0)
		previous_x = button.position.x
		previous_time = elapsed
		# 包装以中心为支点；在同一父画布坐标内核对斜向轨迹。
		var center := button.position + button.size * 0.5
		var fraction := (center.x - contact_center.x) / (640.0 - contact_center.x)
		var route := contact_center.lerp(Vector2(640, 360), fraction)
		check(center.distance_to(route) < 0.01 and center.x <= 640.001 and center.y <= 360.001 and button.scale.is_equal_approx(Vector2.ONE), "沿参考箭头斜向右下滑到中心，不跳起、变形或越过目标：%s / %s / %s" % [center, route, button.scale])
		if index == 0:
			await RenderingServer.frame_post_draw
			impact_preview = root.get_texture().get_image()
	check(speeds[0] > speeds[2] and speeds[0] >= speeds[1] and speeds[1] >= speeds[2] and speeds[2] >= 0, "实际逐段速度减至零，先快后慢：%s" % [speeds])
	if maze._initial_pack_drop.is_running(): await maze._initial_pack_drop.finished
	# 动画取样结束后再编码PNG，避免存图阻塞帧使短滑行提前结束。
	impact_preview.save_png("res://docs/previews/d3_4_20261106/08_pack_first_contact.png")
	check(button.scale == Vector2.ONE and is_zero_approx(button.rotation) and not button.disabled and button.get_global_rect().get_center().distance_to(Vector2(640, 360)) < 1, "减速滑行后回正并精确停在中央")
	check(impacts.size() == 1, "滑行不重复播放首次着地特效")
	check(button.material == null, "滑到中央后仍为原始平面包装，无透视残留")
	for label: String in _motion_previews:
		_motion_previews[label].save_png("res://docs/previews/d3_4_20261106/" + label + ".png")
	await capture_depth("07_pack_depth_landed")
	await click_control(button)
	check(is_instance_valid(main._card_pack_opening) and not maze._panel.visible, "缩放后的卡包可正常点击开包，背景不切天赋")
	main._card_pack_opening.auto_tear()
	await create_timer(1.1).timeout
	var hint: Control = main.get_node_or_null("TaskHint")
	check(hint != null and hint.speech_only and not hint.panel.visible, "撕开后仍只显示英雄气泡")
	if hint == null: shell.free(); quit(1); return
	check(hint.speech.text_label.text == hint.content.dialogue[0].text and not hint.speech.text_label.text.contains(hint.content.dialogue[1].text), "第一个气泡只呈现第一句，不拼接第二句")
	var card: InspectionCardSurface = main._inspection_surface
	check(hint.z_index < main._inspection_overlay.z_index + card.z_index and not main._inspection_dim.visible, "对白暗幕在实际卡面后方，不再挖整张检视矩形")
	var rect: Rect2 = maze._hint_control_rect(card)
	var samples: Array[Vector2] = [Vector2(rect.position.x + 2, rect.get_center().y), Vector2(rect.end.x - 2, rect.get_center().y), Vector2(rect.get_center().x, rect.position.y + 2)]
	await RenderingServer.frame_post_draw
	var shaded := root.get_texture().get_image()
	var dims: Array[ColorRect] = []
	for child: Node in hint._surface.get_children():
		if child is ColorRect:
			dims.append(child)
			child.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var unshaded := root.get_texture().get_image()
	for dim: ColorRect in dims: dim.show()
	for point: Vector2 in samples:
		var pixel := Vector2i(shell.render_container.get_global_transform_with_canvas() * point)
		var before := shaded.get_pixelv(pixel).get_luminance()
		var after := unshaded.get_pixelv(pixel).get_luminance()
		check(after > 0.02 and before < after * 0.95, "实际卡牌透明留白背景保持压暗：%s" % point)
	var hero: Rect2 = maze._hint_control_rect(main.player_avatar_button)
	check(dims.all(func(dim: ColorRect): return not dim.get_rect().intersects(hero)), "英雄区域继续排除压暗")
	var revealed: int = hint.speech.text_label.visible_characters
	await click_control(card)
	check(main._card_pack_opening.current_index == 1 and main.get_node_or_null("TaskHint") == hint and hint.speech.is_visible_in_tree(), "点击首张卡正常收卡，伊奥恩继续说话")
	check(not main._inspection_dim.visible and hint.speech.text_label.visible_characters > revealed, "首张收起后对白继续逐字显示，明暗保持不变")
	await click_control(main._inspection_surface)
	check(main._card_pack_opening.current_index == 2 and main.get_node_or_null("TaskHint") == hint and not main._inspection_dim.visible, "再次收卡仍不打断对白或改变亮度")
	if is_instance_valid(hint.speech._text_reveal) and hint.speech._text_reveal.is_running(): await hint.speech._text_reveal.finished
	await process_frame
	await capture_depth("04_after_tear_dialogue")
	check(main.get_node_or_null("TaskHint") == hint and hint._hero_line_index == 0 and not main._inspection_dim.visible, "第一句显示完后保留阅读时间和亮度")
	await create_timer(hint.STORY_READ_SECONDS + 0.2).timeout
	check(main.get_node_or_null("TaskHint") == hint and hint._hero_line_index == 1 and hint.speech.text_label.text == hint.content.dialogue[1].text and not main._inspection_dim.visible, "第一句读完后原气泡切换第二句，亮度持续不变")
	check(not main.profile_progress.run.read_story_nodes.has("tutorial:step:supplies"), "第二句尚未读完时不提前提交整段剧情已阅")
	if hint.speech._text_reveal.is_running(): await hint.speech._text_reveal.finished
	await capture_depth("09_second_hero_line")
	await create_timer(hint.STORY_READ_SECONDS + 0.2).timeout
	check(main.get_node_or_null("TaskHint") == null and main.profile_progress.run.read_story_nodes.has("tutorial:step:supplies") and main._inspection_dim.visible, "对白自然结束后保存已阅并恢复检视暗幕")
	shell.free()
	print("Pack depth visual: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
