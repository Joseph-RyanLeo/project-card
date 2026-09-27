extends SceneTree

const MainScript = preload("res://scripts/main.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main: MainScript = load("res://scenes/Main.tscn").instantiate() as MainScript
	root.add_child(main)
	await process_frame
	await process_frame
	var owned: OwnedCard
	var source: CardView
	for slot: Control in main._get_collection_card_slots():
		var candidate := slot.get_meta("owned_card", null) as OwnedCard
		if (
			candidate != null
			and candidate.card_data.card_type == CardData.CardType.MINION
			and candidate.card_data.runes.size() >= 2
		):
			owned = candidate
			source = slot.get_child(0) as CardView
			break
	main._open_card_inspection(owned.card_data, owned, source)
	await create_timer(0.3).timeout
	main._inspection_surface.set_process(false)
	main._inspection_surface.force = Vector2.ZERO
	var scraper: Control = main.emblem_library._scraper
	var blank: Vector2 = main._inspection_overlay.size - Vector2(12, 56)

	await _click(scraper.get_global_rect().get_center())
	_expect(
		main._click_carry_data.get("kind") == &"sticker_scraper"
		and main._click_carry_data.get("source_type") == &"inspection_library",
		"真实点击刮刀会建立带显式来源类型的检视携带数据"
	)
	await _click(blank)
	_expect(
		main._click_carry_data.is_empty()
		and main._click_carry_preview == null
		and owned.emblem_slots.all(func(slot: Dictionary) -> bool: return slot.is_empty())
		and owned.rune_stickers.all(func(slot: Dictionary) -> bool: return slot.is_empty()),
		"点击空白无效区安全结束携带且不误删状态"
	)

	await _click(scraper.get_global_rect().get_center())
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	root.push_input(escape, true)
	await process_frame
	_expect(main._click_carry_data.is_empty() and main._click_carry_preview == null, "Esc取消会清理刮刀预览与携带状态")
	var wound_entry: EmblemLibraryEntry = main.wound_library._entries[0]
	await _click(wound_entry.get_global_rect().get_center())
	_expect(
		main._click_carry_data.get("status_kind") == "wound"
		and main._click_carry_preview is TextureRect,
		"伤势点击携带使用检视贴纸预览，不进入装备预览状态"
	)
	var wound_target := main._inspection_surface.get_global_transform_with_canvas() * (
		main._inspection_surface.PADDING + _status_slot_center(owned, CardSlotLayout.Kind.WOUND, 0)
	)
	await _click(wound_target)
	_expect(
		not owned.wound_slots[0].is_empty()
		and main._click_carry_data.is_empty()
		and main._click_carry_preview == null,
		"伤势松手后只提交伤势并安全清理贴纸预览"
	)
	await create_timer(0.24).timeout

	var emblem_definition: Dictionary = main.emblem_library.get_definitions()[0]
	var emblem_data := {
		"kind": &"emblem_library",
		"emblem_id": emblem_definition.id,
		"definition": emblem_definition,
	}
	var first_emblem_position := _status_slot_center(owned, CardSlotLayout.Kind.EMBLEM, 0)
	_expect(
		main._drop_emblem_on_inspection_card(main._inspection_card_view, first_emblem_position, emblem_data),
		"建立真实刮刀回归用的已贴纹章"
	)
	await _click(scraper.get_global_rect().get_center())
	var carry_data: Dictionary = main._click_carry_data.duplicate(true)
	var target_global: Vector2 = (
		main._inspection_surface.get_global_transform_with_canvas()
		* (main._inspection_surface.PADDING + first_emblem_position)
		- (carry_data.get("tip_offset", Vector2.ZERO) as Vector2)
	)
	await _click(target_global)
	_expect(
		owned.emblem_slots[0].is_empty()
		and main.emblem_library._returned.is_empty()
		and main._click_carry_data.is_empty(),
		"真实点击落在已贴纹章时只刮除一次且不返还工作包"
	)

	var emblem_entry: Control = main.emblem_library._entries[0]
	await _click(emblem_entry.get_global_rect().get_center())
	await _click(blank)
	_expect(
		owned.emblem_slots[0].is_empty()
		and not main._inspection_placement_in_progress
		and main._click_carry_data.is_empty(),
		"普通纹章落到非法区域会取消且不写入卡牌"
	)
	await _click(emblem_entry.get_global_rect().get_center())
	var empty_emblem_slot := first_emblem_position
	var emblem_target := main._inspection_surface.get_global_transform_with_canvas() * (
		main._inspection_surface.PADDING + empty_emblem_slot
	)
	await _click(emblem_target)
	var emblem_flight: Polygon2D = main._inspection_placement_visual
	var emblem_start_polygon := emblem_flight.polygon.duplicate()
	_expect(
		not owned.emblem_slots[0].is_empty()
		and main._inspection_placement_in_progress
		and emblem_flight != null
		and main._inspection_card_view.get_node("StatusSlotLayer").get_child_count() == 1,
		"点击普通纹章只提交一次数据，静态卡面暂不刷新并由飞入节点接管显示"
	)
	await create_timer(0.08).timeout
	_expect(
		is_instance_valid(emblem_flight)
		and emblem_flight.polygon != emblem_start_polygon
		and main._inspection_placement_in_progress,
		"普通纹章动画中间帧从真实携带四角连续移动"
	)
	await create_timer(0.14).timeout
	_expect(
		not main._inspection_placement_in_progress
		and main._inspection_card_view.get_node("StatusSlotLayer").get_child_count() == 2,
		"普通纹章到达槽位后才交接给静态卡面"
	)

	var rune_entry: Control = main.emblem_library._entries[3]
	await _click(rune_entry.get_global_rect().get_center())
	var rune_target := main._inspection_surface.get_global_transform_with_canvas() * (
		main._inspection_surface.PADDING + Vector2(19, 119)
	)
	await _click(rune_target)
	var rune_flight: Polygon2D = main._inspection_placement_visual
	var rune_start_polygon := rune_flight.polygon.duplicate()
	_expect(
		owned.rune_stickers[0].get("emblem_id", &"") == &"光贴纸"
		and main._inspection_placement_in_progress
		and rune_flight != null
		and rune_flight.texture.get_size() == Vector2(27, 27),
		"点击元素贴纸以原生27×27图像开始飞入，没有压缩成格子尺寸"
	)
	await create_timer(0.08).timeout
	_expect(
		is_instance_valid(rune_flight)
		and rune_flight.polygon != rune_start_polygon,
		"元素贴纸飞入中间帧持续改变四角且仍使用原生纹理"
	)
	await create_timer(0.14).timeout
	_expect(
		not main._inspection_placement_in_progress
		and main._inspection_card_view.rune_row.get_child_count() > 0,
		"元素贴纸抵达符文槽后再刷新卡面"
	)
	var native_rune_data: Dictionary = rune_entry._build_drag_data(rune_entry.size * 0.5, false)
	var emblems_before_long_drag := owned.emblem_slots.duplicate(true)
	var returned_rune_state := {
		"instance_id": &"returned_long_drag_rune",
		"emblem_id": native_rune_data.emblem_id,
		"element": int(CardData.ElementType.WATER),
		"temporary": false,
	}
	main.emblem_library.return_sticker(returned_rune_state)
	var returned_rune_definition: Dictionary = native_rune_data.definition.duplicate(true)
	returned_rune_definition["returned_state"] = returned_rune_state
	native_rune_data["definition"] = returned_rune_definition
	var drag_origin: Vector2 = rune_entry.get_global_transform_with_canvas() * (rune_entry.size * 0.5)
	var long_drag_visual := main._create_click_carry_preview(native_rune_data, drag_origin)
	native_rune_data["drag_visual"] = long_drag_visual
	var occupied_rune_global: Vector2 = main._inspection_surface.get_global_transform_with_canvas() * (
		main._inspection_surface.PADDING
		+ main._inspection_card_view.rune_area_position
		+ main._inspection_card_view.rune_slot_size * 0.5
	)
	_expect(
		not main._inspection_surface.drop_global(occupied_rune_global, native_rune_data)
		and not main._inspection_placement_in_progress
		and _has_returned_item(main.emblem_library._returned, &"returned_long_drag_rune"),
		"真实检视卡牌投放入口返回占用位失败，且不消耗返还贴纸"
	)
	var second_rune_position: Vector2 = main._inspection_card_view.rune_area_position + Vector2(
		main._inspection_card_view.rune_slot_size.x + main._inspection_card_view.rune_spacing,
		0
	)
	var second_rune_global: Vector2 = main._inspection_surface.get_global_transform_with_canvas() * (
		main._inspection_surface.PADDING + second_rune_position + main._inspection_card_view.rune_slot_size * 0.5
	)
	_expect(
		main._inspection_surface.drop_global(second_rune_global, native_rune_data)
		and not owned.rune_stickers[1].is_empty()
		and main._inspection_placement_in_progress
		and _has_returned_item(main.emblem_library._returned, &"returned_long_drag_rune"),
		"长按拖放的卡面释放路径把元素贴纸写入第二个空符文位"
	)
	await create_timer(0.24).timeout
	_expect(
		not main._inspection_placement_in_progress
		and owned.emblem_slots == emblems_before_long_drag
		and not _has_returned_item(main.emblem_library._returned, &"returned_long_drag_rune"),
		"长按拖放成功动画完成后才消耗返还贴纸，纹章仍留在原槽"
	)
	if is_instance_valid(long_drag_visual):
		long_drag_visual.queue_free()

	var toast_entry: EmblemLibraryEntry
	for entry: EmblemLibraryEntry in main.emblem_library._entries:
		if entry.definition.get("id") == &"烤面包":
			toast_entry = entry
			break
	_expect(toast_entry != null, "纹章工作包包含烤面包")
	if toast_entry == null:
		main.queue_free()
		await process_frame
		quit(1)
		return
	var toast_origin := toast_entry.get_global_rect().get_center()
	main._on_click_carry_requested(
		toast_entry._build_drag_data(toast_entry.size * 0.5, false),
		toast_origin
	)
	var second_emblem_position := _status_slot_center(owned, CardSlotLayout.Kind.EMBLEM, 1)
	var second_emblem_target := main._inspection_surface.get_global_transform_with_canvas() * (
		main._inspection_surface.PADDING + second_emblem_position
	)
	await _click(second_emblem_target)
	_expect(
		owned.emblem_slots[1].get("emblem_id", &"") == &"烤面包"
		and main._inspection_placement_in_progress
		and is_instance_valid(main._inspection_placement_visual),
		"右侧烤面包纹章粘贴后安全结束携带并启动飞入"
	)
	main._close_card_inspection(true)
	_expect(
		not main._inspection_placement_in_progress
		and main._inspection_placement_visual == null
		and main._inspection_overlay == null
		and owned.emblem_slots[1].get("emblem_id", &"") == &"烤面包",
		"动画中立即关闭检视会交接已提交状态并清掉动画节点与悬空引用"
	)
	main._open_card_inspection(owned.card_data, owned, source)
	await create_timer(0.3).timeout
	main._inspection_surface.set_process(false)

	await _click(scraper.get_global_rect().get_center())
	main._close_card_inspection(true)
	await process_frame
	_expect(main._click_carry_data.is_empty() and main._click_carry_preview == null, "携带中关闭检视会取消并清理，不执行来源强转")
	await _click(scraper.get_global_rect().get_center())
	_expect(main._click_carry_data.is_empty(), "关闭检视后不能残留或重复拾取旧刮刀数据")

	main.queue_free()
	await process_frame
	print("Inspection click-carry regression failures: ", failures)
	quit(1 if failures else 0)


func _click(position: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.position = position
	down.global_position = position
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	root.push_input(down, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.position = position
	up.global_position = position
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	root.push_input(up, true)
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _status_slot_center(owned: OwnedCard, kind: int, storage_index: int) -> Vector2:
	for definition: Dictionary in CardSlotLayout.get_slot_definitions(owned.card_data, owned):
		if int(definition.kind) == kind and int(definition.storage_index) == storage_index:
			return definition.position + Vector2(7, 7)
	return Vector2(-100, -100)


func _has_returned_item(items: Array[Dictionary], instance_id: StringName) -> bool:
	for item: Dictionary in items:
		if item.get("instance_id") == instance_id:
			return true
	return false
