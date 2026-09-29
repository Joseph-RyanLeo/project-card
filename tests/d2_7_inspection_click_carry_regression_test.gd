extends SceneTree

const MainScript = preload("res://scripts/main.gd")
const StickerInventory = preload("res://scripts/data/emblem_sticker_inventory.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main: MainScript = load("res://scenes/Main.tscn").instantiate() as MainScript
	root.add_child(main)
	await process_frame
	await process_frame
	main.emblem_library.return_sticker({"instance_id": &"click_torch", "emblem_id": &"火把"})
	main.emblem_library.return_sticker({"instance_id": &"click_sword", "emblem_id": &"长剑"})
	main.emblem_library.return_sticker({"instance_id": &"click_light", "emblem_id": &"光贴纸", "element": CardData.ElementType.LIGHT})
	main.emblem_library.return_sticker({"instance_id": &"click_toast", "emblem_id": &"烤面包"})
	main.emblem_library.return_sticker({"instance_id": &"click_coin_a", "emblem_id": &"金币"})
	main.emblem_library.return_sticker({"instance_id": &"click_coin_b", "emblem_id": &"金币"})
	main._on_developer_console_command_submitted("wound add 中毒Ⅰ")
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
	main._toggle_inspection_library()
	await create_timer(0.3).timeout
	main._inspection_surface.set_process(false)
	main._inspection_surface.force = Vector2.ZERO
	var first_coin_entry := _entry_for_id(main, &"金币") as EmblemLibraryEntry
	var first_coin_state: Dictionary = main.emblem_library.get_inventory_item(&"click_coin_a")
	var second_coin_state_before: Dictionary = main.emblem_library.get_inventory_item(&"click_coin_b")
	var first_coin_cell := Vector2i(int(first_coin_state.grid_x), int(first_coin_state.grid_y))
	var first_coin_target := Vector2i(0, 5)
	var first_coin_target_global := _inventory_cell_center_global(main, first_coin_target)
	await _click(first_coin_entry.get_global_rect().get_center())
	_expect(
		main._click_carry_data.get("kind") == &"emblem_library"
		and is_instance_valid(main._click_carry_preview)
		and main._click_carry_preview.get_parent() == main._inspection_carry_layer,
		"检视工作包单击会进入携带状态并将预览挂入前景图层"
	)
	await _move_mouse(first_coin_target_global)
	var carry_preview_matches_source := false
	if is_instance_valid(main._click_carry_preview):
		carry_preview_matches_source = is_equal_approx(
			main._click_carry_preview.get_global_rect().size.x,
			first_coin_entry.get_node("Icon").get_global_rect().size.x
		)
	_expect(
		carry_preview_matches_source,
		"移动鼠标时点击携带预览与工作包图标保持同一缩放"
	)
	await _click(first_coin_target_global)
	_expect(
		main._click_carry_data.is_empty()
		and main._click_carry_preview == null
		and main.emblem_library.get_inventory_item(&"click_coin_a").get("grid_x") == first_coin_target.x
		and main.emblem_library.get_inventory_item(&"click_coin_a").get("grid_y") == first_coin_target.y
		and main.emblem_library.get_inventory_item(&"click_coin_b").get("grid_x") == second_coin_state_before.grid_x
		and main.emblem_library.get_inventory_item(&"click_coin_b").get("grid_y") == second_coin_state_before.grid_y
		and first_coin_cell != first_coin_target,
		"单击选中再单击空格只移动所选金币实例，另一枚同名实例仍独立存在"
	)
	var second_coin_entry := _entry_for_instance_id(main, &"click_coin_b") as EmblemLibraryEntry
	var second_coin_target := Vector2i(1, 5)
	await _click(second_coin_entry.get_global_rect().get_center())
	await _click(_inventory_cell_center_global(main, second_coin_target))
	_expect(
		main.emblem_library.get_inventory_item(&"click_coin_b").get("grid_x") == second_coin_target.x
		and main.emblem_library.get_inventory_item(&"click_coin_b").get("grid_y") == second_coin_target.y
		and main.emblem_library.get_inventory_item(&"click_coin_a").get("grid_x") == first_coin_target.x,
		"第二次点击移动另一枚同名金币时不串改第一枚实例"
	)
	var element_entry := _entry_for_instance_id(main, &"click_light") as EmblemLibraryEntry
	var grid: Control = main.emblem_library._grid
	_expect(
		element_entry.size == Vector2(31, 31)
		and element_entry._icon.size == Vector2(27, 27)
		and element_entry._icon.position == Vector2(2, 2),
		"元素贴纸占31×31像素格，27×27图案居中并留2像素内边距"
	)
	var corner_grabs: Array[Vector2] = [Vector2(15.5, 15.5), Vector2(3, 27), Vector2(28, 3)]
	var light_state: Dictionary = main.emblem_library.get_inventory_item(&"click_light")
	var target_cell := Vector2i(int(light_state.grid_x), int(light_state.grid_y))
	for row: int in StickerInventory.ROW_COUNT - 1:
		for column: int in StickerInventory.COLUMN_COUNT - 1:
			var candidate := Vector2i(column, row)
			if candidate != target_cell and main.emblem_library.can_move_sticker(&"click_light", candidate):
				target_cell = candidate
				break
		if target_cell != Vector2i(int(light_state.grid_x), int(light_state.grid_y)):
			break
	for index: int in corner_grabs.size():
		_expect(
			main.emblem_library.can_move_sticker(&"click_light", target_cell),
			"三个元素贴纸抓取点共用的回归目标格可容纳完整2×2格"
		)
		element_entry = _entry_for_instance_id(main, &"click_light") as EmblemLibraryEntry
		var grab := corner_grabs[index]
		var drag_data := element_entry._build_drag_data(grab, false)
		var target_origin := grid.get_global_transform_with_canvas() * (
			Vector2(114, 16) + Vector2(target_cell) * 17.0
		)
		var drop_pointer: Vector2 = target_origin - (drag_data.placement_offset as Vector2)
		await _click(element_entry.get_global_transform_with_canvas() * grab)
		await _move_mouse(drop_pointer)
		_expect(
			main.emblem_library._grid._preview_cell == target_cell
			and main.emblem_library._grid._drop_preview.visible,
			"中心、左下角或右上角抓取时，元素预览按贴纸占格锚点高亮相同候选格"
		)
		await _click(drop_pointer)
		var moved_light: Dictionary = main.emblem_library.get_inventory_item(&"click_light")
		_expect(
			moved_light.get("grid_x") == target_cell.x
			and moved_light.get("grid_y") == target_cell.y,
			"点击携带提交格与该抓取锚点的预览格完全一致"
		)
	var gap_target := Vector2i(-1, -1)
	for row: int in StickerInventory.ROW_COUNT - 2:
		for column: int in StickerInventory.COLUMN_COUNT - 2:
			var candidate := Vector2i(column + 1, row + 1)
			if main.emblem_library.can_move_sticker(&"click_light", candidate):
				gap_target = Vector2i(column, row)
				break
		if gap_target.x >= 0:
			break
	if gap_target.x >= 0:
		var gap_entry := _entry_for_instance_id(main, &"click_light") as EmblemLibraryEntry
		var gap_drag := gap_entry._build_drag_data(Vector2(15.5, 15.5), false)
		var gap_anchor := grid.get_global_transform_with_canvas() * (
			Vector2(114, 16) + Vector2(gap_target) * 17.0 + Vector2(15.5, 15.5)
		)
		var gap_pointer: Vector2 = gap_anchor - (gap_drag.placement_offset as Vector2)
		var snapped_gap_cell := gap_target + Vector2i.ONE
		await _click(gap_entry.get_global_transform_with_canvas() * Vector2(15.5, 15.5))
		await _move_mouse(gap_pointer)
		_expect(
			main.emblem_library._grid._preview_cell == snapped_gap_cell
			and main.emblem_library._grid._drop_preview.visible,
			"跨过两轴各3像素间隙时，最近格候选连续切换且不会出现无效预览"
		)
		await _click(gap_pointer)
		var gap_moved: Dictionary = main.emblem_library.get_inventory_item(&"click_light")
		_expect(
			gap_moved.get("grid_x") == snapped_gap_cell.x
			and gap_moved.get("grid_y") == snapped_gap_cell.y,
			"格间隙候选高亮与最终提交位置一致"
		)
	var scraper: Control = main.emblem_library._scraper
	var blank := Vector2(380, 600)

	await _click(scraper.get_global_rect().get_center())
	_expect(
		main._click_carry_data.get("kind") == &"sticker_scraper"
		and main._click_carry_data.get("source_type") == &"inspection_library"
		and is_equal_approx(
			main._click_carry_preview.get_global_rect().size.x,
			scraper.get_global_rect().size.x
		)
		and is_equal_approx(
			main._click_carry_preview.get_global_rect().size.y,
			scraper.get_global_rect().size.y
		),
		"真实点击刮刀携带预览与来源图标保持相同屏幕尺寸"
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
	var wound_entry: EmblemLibraryEntry
	for entry: EmblemLibraryEntry in main.emblem_library._entries:
		if String(entry.definition.get("status_kind", "emblem")) == "wound":
			wound_entry = entry
			break
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

	var emblem_state: Dictionary = main.emblem_library.get_inventory_item(&"click_torch")
	var emblem_definition := _inventory_definition(main, &"火把", emblem_state)
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
		and main.emblem_library.get_inventory_item(&"click_torch").is_empty()
		and main._click_carry_data.is_empty(),
		"真实点击落在已贴纹章时只刮除一次且不返还工作包"
	)

	var emblem_entry: Control = _entry_for_id(main, &"长剑")
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
	var emblem_polygon_changed := false
	for frame: int in 12:
		await process_frame
		if is_instance_valid(emblem_flight) and emblem_flight.polygon != emblem_start_polygon:
			emblem_polygon_changed = true
			break
	_expect(
		emblem_polygon_changed
		and main._inspection_placement_in_progress,
		"普通纹章动画中间帧从真实携带四角连续移动"
	)
	for frame: int in 20:
		if not main._inspection_placement_in_progress:
			break
		await process_frame
	_expect(
		not main._inspection_placement_in_progress
		and main._inspection_card_view.get_node("StatusSlotLayer").get_child_count() == 2,
		"普通纹章到达槽位后才交接给静态卡面"
	)

	var rune_entry: Control = _entry_for_id(main, &"光贴纸")
	var native_rune_data: Dictionary = rune_entry._build_drag_data(rune_entry.size * 0.5, false)
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
	var rune_polygon_changed := false
	for frame: int in 12:
		await process_frame
		if is_instance_valid(rune_flight) and rune_flight.polygon != rune_start_polygon:
			rune_polygon_changed = true
			break
	_expect(
		rune_polygon_changed
		and rune_flight.texture.get_size() == Vector2(27, 27),
		"元素贴纸飞入中间帧持续改变四角且仍使用原生纹理"
	)
	for frame: int in 20:
		if not main._inspection_placement_in_progress:
			break
		await process_frame
	_expect(
		not main._inspection_placement_in_progress
		and main._inspection_card_view.rune_row.get_child_count() > 0,
		"元素贴纸抵达符文槽后再刷新卡面"
	)
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
	rune_entry = _entry_for_id(main, &"光贴纸")
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
		and _has_returned_item(main.emblem_library.get_inventory_state(), &"returned_long_drag_rune"),
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
		and not _has_returned_item(main.emblem_library.get_inventory_state(), &"returned_long_drag_rune"),
		"长按拖放提交时将元素贴纸写入第二个空符文位并同步从背包移除"
	)
	await create_timer(0.24).timeout
	_expect(
		not main._inspection_placement_in_progress
		and owned.emblem_slots == emblems_before_long_drag
		and not _has_returned_item(main.emblem_library.get_inventory_state(), &"returned_long_drag_rune"),
		"长按拖放动画完成后保持已提交的消耗状态，纹章仍留在原槽"
	)
	if is_instance_valid(long_drag_visual):
		long_drag_visual.queue_free()

	var toast_entry := _entry_for_id(main, &"烤面包") as EmblemLibraryEntry
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
	main._toggle_inspection_library()
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


func _move_mouse(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, true)
	await process_frame


func _inventory_cell_center_global(main: MainScript, cell: Vector2i) -> Vector2:
	var grid: Control = main.emblem_library.get_node("Scroll/Grid")
	var local_point := Vector2(114.0, 16.0) + Vector2(cell) * 17.0 + Vector2(7.0, 7.0)
	return grid.get_global_transform_with_canvas() * local_point


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


func _entry_for_id(main: MainScript, emblem_id: StringName) -> Control:
	for entry: Control in main.emblem_library._entries:
		if StringName(String(entry.definition.get("id", ""))) == emblem_id:
			return entry
	return null


func _entry_for_instance_id(main: MainScript, instance_id: StringName) -> Control:
	for entry: Control in main.emblem_library._entries:
		var state: Dictionary = entry.definition.get("returned_state", {})
		if StringName(String(state.get("instance_id", ""))) == instance_id:
			return entry
	return null


func _inventory_definition(main: MainScript, emblem_id: StringName, state: Dictionary) -> Dictionary:
	for definition: Dictionary in main.emblem_library.get_definitions():
		if StringName(String(definition.get("id", ""))) == emblem_id:
			var result := definition.duplicate(true)
			result["returned_state"] = state.duplicate(true)
			return result
	return {}
