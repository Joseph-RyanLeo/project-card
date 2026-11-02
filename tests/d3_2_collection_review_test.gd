extends "res://tests/d3_2_collection_input_test.gd"

const REVIEW_DIR := "/private/tmp/project-card-collection-review"
const REVIEW_PREVIEWS := "res://docs/previews/card_feedback_20261102"

func capture_review(title: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REVIEW_PREVIEWS))
	root.get_texture().get_image().save_png(REVIEW_PREVIEWS.path_join(title + ".png"))

func text_rows(details: Control) -> String:
	return "\n".join(Array(details.get_child(0).get_children()).map(func(row: Node): return row.text))

func key(code: Key, viewport: Viewport = root) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		viewport.push_input(event, true)
		await process_frame
	await frames()

func choose_first_filter(filter: OptionButton) -> void:
	await click(filter)
	var popup := filter.get_popup()
	check(popup.visible, "下拉候选菜单实际打开")
	filter.select(1)
	filter.item_selected.emit(1)
	popup.hide()
	await frames()

func reset_filter(filter: OptionButton) -> void:
	await click(filter)
	var popup := filter.get_popup()
	filter.select(0)
	filter.item_selected.emit(0)
	popup.hide()
	await frames()

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("收藏检视修正专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(REVIEW_DIR)
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = REVIEW_DIR
	shell.run_slots.delete_slot(0)
	var progress := ProfileProgress.new()
	progress.start_run()
	var collection := OwnedCardCollection.new()
	var cards: Array[OwnedCard] = []
	for name: String in ["musketeer", "militia", "town_priest", "damage_fireball", "glacial_crossbow", "battle_fury", "bloodrage_elixir", "field_medic", "moon_hawk", "spark_mage", "beer_mug"]:
		var card := collection.create_card(load("res://resources/cards/" + name + ".tres"))
		cards.append(card)
	check(progress.finish_run(cards, [], 5, "abandoned", 3, [{"day": 1, "won": true, "ending": ""}, {"day": 2, "won": true, "ending": ""}], 2) and progress.show_selection(), "以正式结算生成跨品级与行动方式候选")
	check(RunSaveService.new().save_checkpoint(shell.run_slots.get_slot_path(0), {"schema_version": RunSaveService.SCHEMA_VERSION, "profile_progress": progress.capture_state()}) == OK, "真实临时JSON保存候选与已入账积分")
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_720P)
	await frames()
	check(await shell.start_slot(0), "真实路由恢复收藏")
	var panel = shell._slot_progress_panel
	var ids: Array = shell.slot_progress.run.candidates.keys()
	var original: Dictionary = shell.slot_progress.run.candidates.duplicate(true)
	var balance: int = shell.slot_progress.profile.points
	var first = panel._cells[ids[0]]
	await click(first.view)
	await motion(first.view.get_global_rect().position + first.view.card_size * Vector2(0.8, 0.25))
	await create_timer(0.3).timeout
	var hover = shell.get_collection_hover_surface()
	check(first.halo.get_parent() == first.view and first.view.modulate.a == 0 and hover._selection_halo.get_parent() == hover.card and hover._selection_halo.selected, "选中金光合入当前倾斜卡面，原位不残留平面金框")
	var left: Vector2 = hover.card_canvas_point(Vector2(-5, -5))
	var right: Vector2 = hover.card_canvas_point(Vector2(104, -5))
	check(absf(left.y - right.y) > 1.0, "金光上边缘与卡面一起经过透视变换")
	await capture_review("04_tilted_selection")
	await choose_first_filter(panel._rarity_filter)
	check(panel._rarity_filter.selected == 1 and not panel._visible_ids().is_empty(), "真实下拉选择I级筛选")
	for id: String in panel._visible_ids(): check(panel._cells[id].view.card_data.rarity == CardData.Rarity.I, "品级筛选不显示其他品级")
	await choose_first_filter(panel._action_filter)
	check(panel._action_filter.selected == 1, "真实下拉选择近战行动")
	for id: String in panel._visible_ids():
		check(panel._cells[id].view.card_data.card_type == CardData.CardType.MINION and panel._cells[id].view.get_owned_card().resolved_action_type == CardData.ActionType.MELEE, "行动筛选使用实例行动方式，并排除非随从")
	check(shell.slot_progress.run.selection.size() == 1, "筛选隐藏卡牌不清空已选结果")
	panel._search.grab_focus()
	panel._search.text = "火球"
	panel._search.text_changed.emit(panel._search.text)
	await frames()
	check(panel._visible_ids().is_empty() and panel._book.get_node("EmptyCandidates").visible, "搜索与品级、行动筛选组合，无结果时明确显示")
	await reset_filter(panel._rarity_filter)
	await reset_filter(panel._action_filter)
	await frames()
	check(panel._visible_ids().size() == 1, "清除下拉限制后搜索可找到法术")
	var fire_id: String = panel._visible_ids()[0]
	check(panel._cells[fire_id].view.card_data.id == &"damage_fireball", "搜索实际匹配卡名与效果")
	await capture_review("05_filters_search")
	await click(panel._cells[fire_id].view, MOUSE_BUTTON_RIGHT)
	var inspection: Control = panel._inspection
	var surface: InspectionCardSurface = inspection.find_child("CollectionInspectionSurface", true, false)
	var details: ScrollContainer = inspection.find_child("CardDetails", true, false)
	var title: Label = inspection.find_child("InspectionDetails", true, false).get_child(0)
	check(inspection.get_meta("opening") and surface.scale.x < 4 and title.modulate.a == 0, "检视先执行卡片放大，详情未提前显示")
	while inspection.get_meta("opening"): await process_frame
	check(not inspection.get_meta("opening") and surface.scale == Vector2(4, 4), "平滑放大后准确到4倍")
	await create_timer(0.22).timeout
	var rows: Array[Node] = details.get_child(0).get_children()
	check(rows.size() > 3 and rows[0].modulate.a > rows[-1].modulate.a, "大卡到位后详情逐行跳出，行间出现时间不同")
	var dim: ColorRect = inspection.find_child("InspectionDim", true, false)
	check(dim.color.a > 0.5 and dim.color.a < 0.8, "蒙版变暗而非全黑背景")
	await create_timer(0.8).timeout
	check(inspection.find_child("ToggleCard_0", true, false) == null, "移除用途不明确的卡面/效果按钮")
	await capture_review("06_animated_details")
	var tabs: TabBar = inspection.find_child("InspectionTabs", true, false)
	tabs.current_tab = 1
	await create_timer(0.8).timeout
	var score := RunScoreService.card_score(panel._cells[fire_id].view.get_owned_card())
	var score_text := text_rows(details)
	check(score_text.contains("单卡基础积分：%d" % score.total) and score_text.contains("品级：%d" % score.parts.grade) and score_text.contains("本局倍率：1.2"), "积分页复用正式计分器，显示单卡基础分、组成及本局倍率")
	check(score_text.contains("统一向下取整") and shell.slot_progress.profile.points == balance, "查看积分构成不重复发分或逐卡另行取整")
	await capture_review("07_score_details")
	await key(KEY_ESCAPE)
	await wait_inspection_closed(panel)
	check(not is_instance_valid(panel._inspection) and shell.slot_progress.run.stage == "selection", "Esc关闭详情，不退出收藏")
	panel._search.clear()
	panel._search.text_changed.emit("")
	await frames()
	await click(first.view, MOUSE_BUTTON_RIGHT)
	check(panel._inspection.get_meta("opening"), "再次检视仍从放大过渡开始")
	await key(KEY_ESCAPE)
	await create_timer(0.5).timeout
	check(not is_instance_valid(panel._inspection), "动画途中关闭不会迟到弹出详情")
	check(shell.slot_progress.run.candidates == original and shell.slot_progress.run.selection.size() == 1, "筛选、动画、详情和积分全程不改候选或选择")
	print("D3-2 collection review checks: %d, failures: %d" % [checks, failures])
	shell.free()
	await frames()
	quit(1 if failures else 0)
