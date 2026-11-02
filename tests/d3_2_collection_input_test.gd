extends "res://tests/d3_2_flow_test.gd"

const INPUT_DIR := "/private/tmp/project-card-d3-2-collection-input"
const INPUT_PREVIEWS := "res://docs/previews/d3_2_input_20261102"

func screenshot(title: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(INPUT_PREVIEWS))
	root.get_texture().get_image().save_png(INPUT_PREVIEWS.path_join(title + ".png"))

func motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * at
	root.push_input(event, true)
	await frames()

func wheel(at: Vector2, down: bool = true) -> void:
	await motion(at)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = shell.render_container.get_global_transform_with_canvas() * at
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await frames()

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("收藏输入专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(INPUT_DIR)
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = INPUT_DIR
	shell.run_slots.delete_slot(0)
	var progress := ProfileProgress.new()
	progress.start_run()
	var collection := OwnedCardCollection.new()
	var cards: Array[OwnedCard] = []
	var names := ["musketeer", "town_priest", "militia", "shieldwall_private", "elegy_poet", "star_chant_apprentice", "spark_mage", "formation_infantry", "field_medic", "fireman"]
	for index: int in 90:
		var card := collection.create_card(load("res://resources/cards/" + names[index % names.size()] + ".tres"))
		if index == 1:
			card.acquisition_source = {"kind": "event", "name": "检视测试事件"}
			card.recruited_by = "ioann_warden"
			card.lifetime_stats = {"damage_dealt": 123.5, "battles": 7}
		cards.append(card)
	progress.begin_collection(cards)
	check(RunSaveService.new().save_checkpoint(shell.run_slots.get_slot_path(0), {"schema_version": RunSaveService.SCHEMA_VERSION, "profile_progress": progress.capture_state()}) == OK, "90张正式卡候选写入临时档")
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K if "2k" in OS.get_cmdline_user_args() else shell.DisplayMode.WINDOW_720P)
	await frames()
	check(await shell.start_slot(0), "真实显示壳恢复90张候选")
	await frames()
	var panel = shell._slot_progress_panel
	var ids: Array = shell.slot_progress.run.candidates.keys()
	var original: Dictionary = shell.slot_progress.run.candidates.duplicate(true)
	check(panel._cells.size() == 90 and panel.find_child("PreviousCandidatesButton", true, false) == null and panel.find_child("NextCandidatesButton", true, false) == null, "所有候选连续排列，删除翻页按钮")
	var first = panel._cells[ids[0]]
	check(first.view.scale == Vector2.ONE and first.view.card_size == Vector2(99, 136), "静止卡面原生99×136，逻辑1倍，无1.12缩放")
	await motion(first.view.get_global_rect().position + first.view.card_size * Vector2(0.8, 0.3))
	await create_timer(0.25).timeout
	var hover = shell.get_collection_hover_surface()

	check(hover.visible and hover.read_only and hover.source == first.view and hover.force.distance_to(Vector2(0.6, -0.4)) < 0.15, "真实鼠标悬停复用检视透视倾斜")
	check(first.view.modulate.a == 0 and hover.render_scale >= 4 and hover.mouse_filter == Control.MOUSE_FILTER_IGNORE, "高分辨率倾斜显示保留原卡命中且不遮挡输入")
	await screenshot("01_hover_" + ("2k" if "2k" in OS.get_cmdline_user_args() else "720p"))
	await click(first.view)
	check(shell.slot_progress.run.selection.size() == 1 and first.selected and first.halo.is_processing(), "直接点卡即选中，启用环绕像素光效")
	var cell_identity: int = first.get_instance_id()
	check(panel._cells[ids[0]].get_instance_id() == cell_identity, "选中只刷新标记，不重建90张卡")
	await screenshot("02_selected")
	await click(first.view)
	check(shell.slot_progress.run.selection.is_empty() and not first.selected and not first.halo.is_processing(), "再次点卡取消选择和环绕效果")
	for i: int in 12: await wheel(Vector2(800, 450))
	check(panel._scroll.scroll_vertical > 300, "真实滚轮可连续浏览后续行")
	var scroll_value: int = panel._scroll.scroll_vertical
	await screenshot("03_scrolled")
	# 找到当前完整露出的卡，选择后滚动位置不能被重置。
	var visible_id: String = ""
	for id: String in ids:
		if panel._scroll.get_global_rect().encloses(panel._cells[id].view.get_global_rect()): visible_id = id; break
	check(not visible_id.is_empty(), "滚动后存在完整可操作卡牌")
	await click(panel._cells[visible_id].view)
	check(panel._scroll.scroll_vertical == scroll_value and shell.slot_progress.run.selection.size() == 1, "滚动后点选保留位置且能命中真实卡")
	await click(panel._cells[visible_id].view)
	panel._scroll.scroll_vertical = 0
	await frames()
	var target = panel._cells[ids[1]]
	await click(target.view, MOUSE_BUTTON_RIGHT)
	var inspection: Control = panel.find_child("CollectionInspection", true, false)
	check(inspection != null and inspection.visible and shell.slot_progress.run.selection.is_empty(), "右键只打开检视，不选择卡")
	var surface: InspectionCardSurface = inspection.find_child("CollectionInspectionSurface", true, false)
	check(surface.scale.x < 4.0 and inspection.get_meta("opening"), "右键从原位开始放大，没有直接跳到4倍")
	await create_timer(0.4).timeout
	check(surface.scale == Vector2(4, 4) and surface.card.get_owned_card().instance_id == StringName(ids[1]) and surface.render_scale >= 4, "右键大卡为4倍，绑定同一只读候选状态")
	var details: ScrollContainer = inspection.find_child("CardDetails", true, false)
	var text: String = "\n".join(Array(details.get_child(0).get_children()).map(func(row: Node): return row.text))
	var right: Control = inspection.find_child("InspectionDetails", true, false)
	check(right.position.x > surface.position.x + surface.size.x * 4 and text.contains("检视测试事件") and text.contains("123.5") and text.contains("卡牌效果"), "详细效果、来源和累计战绩位于大卡右侧")
	await screenshot("04_inspection")
	var tabs: TabBar = inspection.find_child("InspectionTabs", true, false)
	tabs.current_tab = 1
	await create_timer(0.3).timeout
	check(shell.slot_progress.run.candidates == original, "翻看效果与悬停不改候选数据")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await wait_inspection_closed(panel)
	check(not is_instance_valid(panel._inspection) and shell.slot_progress != null and shell.slot_progress.run.stage == "selection", "检视Esc仅关闭大卡，不退回主菜单")
	var disk := FileAccess.get_file_as_string(shell.run_slots.get_slot_path(0))
	DirAccess.make_dir_absolute(shell.run_slots.get_slot_path(0) + ".tmp")
	await click(first.view)
	check(shell.slot_progress.run.selection.is_empty() and not first.selected and FileAccess.get_file_as_string(shell.run_slots.get_slot_path(0)) == disk, "选择保存失败时数据、标记和磁盘均保持原样")
	DirAccess.remove_absolute(shell.run_slots.get_slot_path(0) + ".tmp")
	if is_instance_valid(shell._persistence_dialog): shell._persistence_dialog.hide()
	for index: int in 8:
		panel._scroll.scroll_vertical = 0
		await click(panel._cells[ids[index]].view)
	check(shell.slot_progress.run.selection.size() == 8, "直接点卡可选满8张")
	await click(panel._cells[ids[8]].view)
	check(shell.slot_progress.run.selection.size() == 8 and not panel._cells[ids[8]].selected, "第9张不越过上限，不显示假选中效果")
	await motion(Vector2(360, 140))
	await create_timer(0.4).timeout
	check(not hover.visible and first.view.modulate.a == 1.0, "移开后回正并归还静止卡，悬停画布不残留")
	check(shell.slot_progress.run.candidates == original, "全程候选完整状态只读")
	print("D3-2 collection input checks: %d, failures: %d" % [checks, failures])
	shell.free()
	await frames()
	quit(1 if failures else 0)
