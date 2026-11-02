extends "res://tests/d3_2_collection_review_test.gd"

const LAYOUT_DIR := "/private/tmp/project-card-collection-detail-layout"
const LAYOUT_PREVIEWS := "res://docs/previews/card_feedback_20261102"


func rows_separated(body: VBoxContainer) -> bool:
	var bottom := -INF
	for row: Label in body.get_children():
		var rect := row.get_global_rect()
		if rect.position.y < bottom - 0.5: return false
		bottom = rect.end.y
	return body.get_child_count() > 3


func inspect_row_layout(body: VBoxContainer, title: String) -> void:
	var separated := true
	for sample: int in 16:
		await process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
		separated = separated and rows_separated(body)
		await create_timer(0.035).timeout
	check(separated, title + "：动画中各行按高度排列，不互相覆盖")
	await create_timer(0.2).timeout
	check(rows_separated(body), title + "：动画结束仍保持分行")
	var scales_restored := true
	for row: Label in body.get_children(): scales_restored = scales_restored and row.scale.is_equal_approx(Vector2.ONE) and is_equal_approx(row.modulate.a, 1.0)
	check(scales_restored, title + "：最终原尺寸、完全可见")


func capture_layout(title: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LAYOUT_PREVIEWS))
	root.get_texture().get_image().save_png(LAYOUT_PREVIEWS.path_join(title + ".png"))


func body_uses_readable_font(body: VBoxContainer) -> bool:
	var readable := preload("res://scripts/ui/card_text_display_settings.gd").readable_font()
	for row: Label in body.get_children():
		if row.get_theme_font("font") != readable: return false
	return body.get_child_count() > 3


func request_close(inspection: Control, method: int) -> void:
	if method == 0:
		for pressed: bool in [true, false]:
			var event := InputEventKey.new()
			event.keycode = KEY_ESCAPE
			event.pressed = pressed
			root.push_input(event, true)
	else:
		var point := Vector2(1100, 650)
		if method == 2: point = inspection.get_node("CloseCollectionInspection").get_global_rect().get_center()
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = shell.render_container.get_global_transform_with_canvas() * point
			event.button_index = MOUSE_BUTTON_LEFT if method == 2 else MOUSE_BUTTON_RIGHT
			event.pressed = pressed
			root.push_input(event, true)


func verify_close(panel: Control, method: int) -> void:
	var inspection: Control = panel._inspection
	var surface: InspectionCardSurface = inspection.get_node("CollectionInspectionSurface")
	var start_scale := surface.scale
	var return_position: Vector2 = inspection.get_meta("return_position")
	var returned: Array = []
	request_close(inspection, method)
	check(panel._inspection == inspection and inspection.visible and inspection.get_meta("closing", false) and surface.scale == start_scale, "关闭入口%d开始动画，卡牌没有瞬间消失或跳变" % method)
	panel._inspection_tween.finished.connect(func(): returned.append([surface.position, surface.scale, surface.force, inspection.modulate.a]))
	await create_timer(0.07).timeout
	check(is_instance_valid(inspection) and surface.scale.x < start_scale.x and surface.scale.x > 1 and inspection.modulate.a < 1 and inspection.modulate.a > 0, "关闭过程中卡牌连续缩小、界面渐隐")
	if start_scale.x < 4:
		check(inspection.find_child("DetailRows", true, false).get_child_count() == 0, "放大途中取消后不再迟到创建详情")
	request_close(inspection, 0)
	check(shell.slot_progress.run.stage == "selection" and panel._inspection == inspection, "重复Esc仍由关闭中的检视消费，不退回主菜单")
	await capture_layout("10_closing_" + str(method))
	await wait_inspection_closed(panel)
	await frames()
	check(returned.size() == 1 and returned[0][0] == return_position and returned[0][1] == Vector2.ONE and returned[0][2] == Vector2.ZERO and returned[0][3] == 0.0, "关闭动画准确回到原位及1倍，回正并完全淡出")


func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("收藏详情排版专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(LAYOUT_DIR)
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = LAYOUT_DIR
	shell.run_slots.delete_slot(0)
	var progress := ProfileProgress.new()
	progress.start_run()
	var collection := OwnedCardCollection.new()
	var owned := collection.create_card(load("res://resources/cards/musketeer.tres"))
	owned.acquisition_source = {"kind": "event", "name": "这是用于验证卡牌获得来源长文字自动换行的测试记录。".repeat(4)}
	owned.recruited_by = "ioann_warden"
	owned.lifetime_stats = {"damage_dealt": 923.5, "healing_done": 123, "armor_granted": 77, "damage_taken": 138, "kills": 6, "battles": 3, "deaths": 1, "mining_successes": 12, "gold_generated": 35}
	check(progress.finish_run([owned], [], 0, "abandoned", 3, [], 2) and progress.show_selection(), "正式结算生成带多行历史的火枪手")
	check(RunSaveService.new().save_checkpoint(shell.run_slots.get_slot_path(0), {"schema_version": RunSaveService.SCHEMA_VERSION, "profile_progress": progress.capture_state()}) == OK, "临时隔离档保存候选")
	root.add_child(shell)
	check(await shell.start_slot(0), "真实路由恢复收藏界面")
	var panel = shell._slot_progress_panel
	var id: String = shell.slot_progress.run.candidates.keys()[0]
	var original: Dictionary = shell.slot_progress.run.candidates.duplicate(true)
	for mode: int in [shell.DisplayMode.WINDOW_720P, shell.DisplayMode.WINDOW_2K]:
		shell.apply_display_mode(mode)
		await frames()
		await click(panel._cells[id].view, MOUSE_BUTTON_RIGHT)
		var inspection: Control = panel._inspection
		while inspection.get_meta("opening"): await process_frame
		var body: VBoxContainer = inspection.find_child("DetailRows", true, false)
		var scroll: ScrollContainer = inspection.find_child("CardDetails", true, false)
		var tabs: TabBar = inspection.find_child("InspectionTabs", true, false)
		await inspect_row_layout(body, "详情页 " + str(mode))
		check(body_uses_readable_font(body), "卡牌详情所有正文行使用项目中文黑体")
		await capture_layout("08_details_separated_" + str(mode))
		var wrapped := false
		for row: Label in body.get_children():
			if row.text.begins_with("来源："): wrapped = row.size.y > row.get_theme_font("font").get_height(20) * 2
		check(wrapped, "长来源实际换行并占据多行高度")
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await frames()
		var last: Label = body.get_child(body.get_child_count() - 1)
		check(scroll.get_global_rect().encloses(last.get_global_rect()), "滚动后能完整看到最后一行累计战绩")
		await capture_layout("09_details_scrolled_" + str(mode))
		await click(tabs, MOUSE_BUTTON_LEFT)
		# 真实鼠标点击第二页签，检查实际信号和刷新后的布局。
		await motion(tabs.get_global_rect().position + Vector2(170, 20))
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = shell.render_container.get_global_transform_with_canvas() * (tabs.get_global_rect().position + Vector2(170, 20))
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			root.push_input(event, true)
			await process_frame
		check(tabs.current_tab == 1, "鼠标实际切换至积分构成")
		await inspect_row_layout(body, "积分页 " + str(mode))
		check(body_uses_readable_font(body), "积分构成所有正文行使用项目中文黑体")
		await capture_layout("11_score_readable_" + str(mode))
		# 在上一轮逐行动画尚未完成时切回、再切出，旧节点的动画应随释放停止。
		for index: int in [0, 1, 0, 1, 0]:
			tabs.current_tab = index
			await process_frame
		await inspect_row_layout(body, "快速切回详情 " + str(mode))
		check(scroll.scroll_vertical == 0, "切页回到正文顶部")
		await verify_close(panel, 0 if mode == shell.DisplayMode.WINDOW_720P else 2)
	# 在放大途中右键取消：原放大Tween必须停止，详情也不能迟到弹出。
	panel._inspect(id)
	var early: Control = panel._inspection
	await create_timer(0.08).timeout
	check(early.get_meta("opening") and early.find_child("DetailRows", true, false).get_child_count() == 0, "提前关闭前仍处于放大阶段")
	await verify_close(panel, 1)
	check(shell.slot_progress.run.candidates == original and shell.slot_progress.run.selection.is_empty(), "检视、滚动及切页不修改候选与选择")
	print("Collection detail layout checks: %d, failures: %d" % [checks, failures])
	shell.free()
	await frames()
	quit(1 if failures else 0)
