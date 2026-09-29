extends SceneTree

const CardSlotLayout = preload("res://scripts/data/card_slot_layout.gd")

var failures := 0
var input_viewport: Viewport
var pointer := Vector2.ZERO
var input_transform := Transform2D.IDENTITY

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if value:
		print("PASS: " + message)
	else:
		failures += 1
		push_error(message)

func motion(point: Vector2, held := false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = input_transform * point
	event.global_position = event.position
	event.relative = (point - pointer) * input_transform.get_scale()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	pointer = point
	Input.warp_mouse(event.position)
	root.push_input(event, true)
	await process_frame

func button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = input_transform * pointer
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame


func _run() -> void:
	root.size = Vector2i(2560, 1440)
	var display = load("res://scenes/GameDisplay.tscn").instantiate()
	root.add_child(display)
	await process_frame
	await process_frame
	var main = display.main_screen
	main.emblem_library.return_sticker({"instance_id": &"native_torch", "emblem_id": &"火把"})
	main.emblem_library.return_sticker({"instance_id": &"native_light", "emblem_id": &"光贴纸", "element": CardData.ElementType.LIGHT})
	input_viewport = display.internal_viewport
	input_viewport.notify_mouse_entered()
	input_transform = display.render_container.get_global_transform_with_canvas()
	check(
		input_transform.get_scale().is_equal_approx(Vector2(2, 2)),
		"2K显示壳只把720p逻辑画布统一放大2×"
	)
	var source: CardView
	for slot: Control in main._get_collection_card_slots():
		var owned: OwnedCard = slot.get_meta("owned_card", null)
		if owned != null and owned.card_data.card_type == CardData.CardType.MINION:
			source = slot.get_child(0)
			break
	main._open_card_inspection(source.card_data, source.get_owned_card(), source)
	await create_timer(0.3).timeout
	check(
		main.emblem_library.scale == Vector2(4, 4)
		and main.emblem_library.get_global_rect().size == Vector2(780, 592)
		and main.emblem_library.position.x + 780.0 == 28.0,
		"原生检视默认收起4×工具箱，只露出28像素操作边缘"
	)
	main._toggle_inspection_library()
	await create_timer(0.3).timeout
	input_transform = display.render_container.get_global_transform_with_canvas()
	var surface = main._inspection_surface
	var owned := source.get_owned_card()
	var emblem_index := -1
	var emblem_local := Vector2.ZERO
	for slot_definition: Dictionary in CardSlotLayout.get_slot_definitions(source.card_data, owned):
		var index := int(slot_definition.storage_index)
		if (
			int(slot_definition.kind) == CardSlotLayout.Kind.EMBLEM
			and index >= 0
			and index < owned.emblem_slots.size()
			and owned.emblem_slots[index].is_empty()
		):
			emblem_index = index
			emblem_local = slot_definition.position + Vector2(7.0, 7.0)
			break
	check(emblem_index >= 0, "被检视卡牌存在真实空纹章槽供拖拽验收")
	check(main._inspection_overlay.size == Vector2(1280, 720), "实际显示壳使用1280×720逻辑画布")
	check(main.emblem_library._scroll.position.x + main.emblem_library._scroll.size.x <= main.emblem_library.size.x, "滚动区完整位于工作包内")
	check(main.emblem_library._scraper.position.x + main.emblem_library._scraper.size.x <= main.emblem_library.size.x, "刮刀固定工具位完整位于工作包内")
	check(
		main.emblem_library._grid.get_node("GridCells/Cell_0_0").position == Vector2(114, 16)
		and main.emblem_library._grid.get_node("GridCells/Cell_3_6").position == Vector2(165, 118),
		"真实画面工具箱格线从(114,16)按17像素步长排成4×7"
	)
	var light_state: Dictionary = main.emblem_library.get_inventory_item(&"native_light")
	var inventory_target := Vector2i(int(light_state.grid_x), int(light_state.grid_y))
	var inventory_grabs: Array[Vector2] = [Vector2(15.5, 15.5), Vector2(3, 27), Vector2(28, 3)]
	for grab: Vector2 in inventory_grabs:
		var light_entry := _entry_for_id(main, &"光贴纸")
		var inventory_drag: Dictionary = light_entry._build_drag_data(grab, false)
		var target_canvas: Vector2 = main.emblem_library._grid.get_global_transform_with_canvas() * (
			Vector2(114, 16) + Vector2(inventory_target) * 17.0
		)
		var target_pointer: Vector2 = target_canvas - (inventory_drag.placement_offset as Vector2)
		var target_local: Vector2 = main.emblem_library._grid.get_global_transform_with_canvas().affine_inverse() * target_pointer
		var accepted: bool = main.emblem_library._grid._can_drop_data(target_local, inventory_drag)
		check(
			accepted
			and main.emblem_library._grid._preview_cell == inventory_target
			and main.emblem_library._grid._drop_preview.visible,
			"原生放置回调用显式局部坐标，按元素抓取偏移高亮目标占格"
		)
		main.emblem_library._grid._drop_data(target_local, inventory_drag)
		light_state = main.emblem_library.get_inventory_item(&"native_light")
		check(
			light_state.get("grid_x") == inventory_target.x
			and light_state.get("grid_y") == inventory_target.y,
			"原生放置回调提交格与此前预览候选一致"
		)
	var light_entry := _entry_for_id(main, &"光贴纸")
	var light_drag: Dictionary = light_entry._build_drag_data(Vector2(15.5, 15.5), false)
	var torch_state: Dictionary = main.emblem_library.get_inventory_item(&"native_torch")
	var occupied_cell := Vector2i(int(torch_state.grid_x), int(torch_state.grid_y))
	var occupied_pointer: Vector2 = main.emblem_library._grid.get_global_transform_with_canvas() * (
		Vector2(114, 16) + Vector2(occupied_cell) * 17.0
	) - (light_drag.placement_offset as Vector2)
	var grid_transform: Transform2D = main.emblem_library._grid.get_global_transform_with_canvas()
	var occupied_local: Vector2 = grid_transform.affine_inverse() * occupied_pointer
	check(
		not main.emblem_library._grid._can_drop_data(occupied_local, light_drag)
		and main.emblem_library._grid._preview_cell == occupied_cell
		and main.emblem_library._grid._drop_preview.visible
		and main.emblem_library._grid._drop_preview.color.r > main.emblem_library._grid._drop_preview.color.g,
		"其他实例占用的候选格显示红色拒绝预览"
	)
	main.emblem_library._grid._drop_data(occupied_local, light_drag)
	light_state = main.emblem_library.get_inventory_item(&"native_light")
	check(
		light_state.get("grid_x") == inventory_target.x
		and light_state.get("grid_y") == inventory_target.y,
		"被占用格提交失败后贴纸仍在原位置"
	)
	var outside_pointer: Vector2 = grid_transform * (Vector2(114, 16) + Vector2(-20, 0)) - (
		light_drag.placement_offset as Vector2
	)
	var outside_local: Vector2 = grid_transform.affine_inverse() * outside_pointer
	check(
		not main.emblem_library._grid._can_drop_data(outside_local, light_drag)
		and not main.emblem_library._grid._drop_preview.visible
		and main.emblem_library._grid._preview_cell == Vector2i(-1, -1),
		"超出吸附区域时隐藏预览且不产生边缘伪候选"
	)
	var entry: Control = _entry_for_id(main, &"火把")
	await motion(entry.get_global_transform_with_canvas() * Vector2(7, 7))
	await button(true)
	await motion(pointer + Vector2(25, 5), true)
	check(input_viewport.gui_is_dragging(), "真实按下移动启动纹章拖拽")
	if input_viewport.gui_is_dragging():
		var target_canvas: Vector2 = surface.get_global_transform_with_canvas() * (surface.PADDING + emblem_local)
		await motion(target_canvas, true)
		await create_timer(0.2).timeout
		# 用固定点求逆投影的零点，确保落在倾斜后的真实槽中心。
		for iteration: int in 8:
			var local: Vector2 = surface.get_global_transform_with_canvas().affine_inverse() * pointer
			var error: Vector2 = emblem_local - surface.card_point(local)
			await motion(pointer + error * surface.scale, true)
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			input_viewport.get_texture().get_image().save_png("/private/tmp/project-card-sticker-held.png")
		await button(false)
		check(not owned.emblem_slots[emblem_index].is_empty(), "倾斜中的卡牌接受原生拖拽粘贴")
	var scraper = main.emblem_library._scraper
	await motion(scraper.get_global_transform_with_canvas() * Vector2(20, 20))
	await button(true)
	await motion(pointer + Vector2(25, 2), true)
	check(input_viewport.gui_is_dragging(), "刮刀可真实长按拿起")
	if input_viewport.gui_is_dragging():
		var data: Dictionary = input_viewport.gui_get_drag_data()
		var preview := data.get("drag_visual") as TextureRect
		check(
			data.get("preview_size") == scraper.size
			and data.get("preview_scale") == scraper.get_global_transform_with_canvas().get_scale()
			and is_instance_valid(preview)
			and preview.get_global_rect().size.is_equal_approx(scraper.get_global_rect().size),
			"原生刮刀预览沿用来源局部尺寸与单次来源缩放"
		)
		var target_canvas: Vector2 = surface.get_global_transform_with_canvas() * (surface.PADDING + emblem_local) - data.tip_offset
		await motion(target_canvas, true)
		for iteration: int in 8:
			var local: Vector2 = surface.get_global_transform_with_canvas().affine_inverse() * pointer
			var error: Vector2 = emblem_local - surface.card_point(surface._tool_point(local, data))
			await motion(pointer + error * surface.scale, true)
		check(not owned.emblem_slots[emblem_index].is_empty(), "刀头经过贴纸不会提前刮下")
		await button(false)
		check(owned.emblem_slots[emblem_index].is_empty(), "松开时刀头命中才能刮下纹章")
		check(main.emblem_library.get_inventory_item(&"native_torch").is_empty(), "长按刮下纹章后不返还工作包")
	await create_timer(0.22).timeout
	var rune_entry: Control = _entry_for_id(main, &"光贴纸")
	var rune_pickup := rune_entry.get_global_rect().get_center()
	await motion(rune_pickup)
	await button(true)
	await motion(rune_pickup + Vector2(24, 4), true)
	check(input_viewport.gui_is_dragging(), "长按元素贴纸会启动原生拖拽")
	if input_viewport.gui_is_dragging():
		var rune_data: Dictionary = input_viewport.gui_get_drag_data()
		var rune_local := Vector2(19, 119)
		var rune_target: Vector2 = surface.get_global_transform_with_canvas() * (surface.PADDING + rune_local)
		await motion(rune_target, true)
		for iteration: int in 8:
			var local: Vector2 = surface.get_global_transform_with_canvas().affine_inverse() * pointer
			var error: Vector2 = rune_local - surface.card_point(local)
			await motion(pointer + error * surface.scale, true)
		await button(false)
		var flight: Polygon2D = main._inspection_placement_visual
		var start_polygon := flight.polygon.duplicate() if flight != null else PackedVector2Array()
		check(
			source.get_owned_card().rune_stickers[0].get("emblem_id", &"") == &"光贴纸"
			and flight != null
			and main._inspection_placement_in_progress,
			"原生长按元素贴纸松手后只写入一次状态并交由动画节点接管"
		)
		await create_timer(0.08).timeout
		check(
			is_instance_valid(flight)
			and flight.polygon != start_polygon
			and main._inspection_placement_in_progress,
			"原生长按元素贴纸动画中间帧从保存的抓取变换连续飞入"
		)
		await create_timer(0.14).timeout
		check(
			not main._inspection_placement_in_progress
			and main._inspection_card_view.rune_row.get_child_count() > 0,
			"原生长按动画抵达后才将元素贴纸交给静态卡面显示"
		)
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		input_viewport.get_texture().get_image().save_png("/private/tmp/project-card-inspection-layout.png")
	main._close_card_inspection()
	display.queue_free()
	await process_frame
	print("Native sticker drag failures: ", failures)
	quit(1 if failures else 0)


func _entry_for_id(main, emblem_id: StringName) -> Control:
	for entry: Control in main.emblem_library._entries:
		if StringName(String(entry.definition.get("id", ""))) == emblem_id:
			return entry
	return null
