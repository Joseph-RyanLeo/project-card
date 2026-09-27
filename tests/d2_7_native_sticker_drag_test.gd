extends SceneTree

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
	root.size = Vector2i(1920, 1080)
	var display = load("res://scenes/GameDisplay.tscn").instantiate()
	root.add_child(display)
	await process_frame
	await process_frame
	var main = display.main_screen
	input_viewport = display.internal_viewport
	input_viewport.notify_mouse_entered()
	input_transform = display.render_container.get_global_transform_with_canvas()
	var source: CardView
	for slot: Control in main._get_collection_card_slots():
		var owned: OwnedCard = slot.get_meta("owned_card", null)
		if owned != null and owned.card_data.card_type == CardData.CardType.MINION:
			source = slot.get_child(0)
			break
	main._open_card_inspection(source.card_data, source.get_owned_card(), source)
	await create_timer(0.3).timeout
	input_transform = display.render_container.get_global_transform_with_canvas()
	var surface = main._inspection_surface
	check(main._inspection_overlay.size == Vector2(1280, 720), "实际显示壳使用1280×720逻辑画布")
	check(main.emblem_library._scroll.position.x + main.emblem_library._scroll.size.x <= main.emblem_library.size.x, "滚动区完整位于工作包内")
	check(main.emblem_library._scraper.position.x + main.emblem_library._scraper.size.x <= main.emblem_library.size.x, "刮刀固定工具位完整位于工作包内")
	var entry: Control = main.emblem_library._entries[0]
	await motion(entry.get_global_transform_with_canvas() * Vector2(7, 7))
	await button(true)
	await motion(pointer + Vector2(25, 5), true)
	check(input_viewport.gui_is_dragging(), "真实按下移动启动纹章拖拽")
	if input_viewport.gui_is_dragging():
		var target_canvas: Vector2 = surface.get_global_transform_with_canvas() * (surface.PADDING + Vector2(5, 46))
		await motion(target_canvas, true)
		await create_timer(0.2).timeout
		# 用固定点求逆投影的零点，确保落在倾斜后的真实槽中心。
		for iteration: int in 8:
			var local: Vector2 = surface.get_global_transform_with_canvas().affine_inverse() * pointer
			var error: Vector2 = Vector2(5, 46) - surface.card_point(local)
			await motion(pointer + error * surface.scale, true)
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			input_viewport.get_texture().get_image().save_png("/private/tmp/project-card-sticker-held.png")
		await button(false)
		check(not source.get_owned_card().emblem_slots[0].is_empty(), "倾斜中的卡牌接受原生拖拽粘贴")
	var scraper = main.emblem_library._scraper
	await motion(scraper.get_global_transform_with_canvas() * Vector2(20, 20))
	await button(true)
	await motion(pointer + Vector2(25, 2), true)
	check(input_viewport.gui_is_dragging(), "刮刀可真实长按拿起")
	if input_viewport.gui_is_dragging():
		var data: Dictionary = input_viewport.gui_get_drag_data()
		var target_canvas: Vector2 = surface.get_global_transform_with_canvas() * (surface.PADDING + Vector2(5, 46)) - data.tip_offset
		await motion(target_canvas, true)
		for iteration: int in 8:
			var local: Vector2 = surface.get_global_transform_with_canvas().affine_inverse() * pointer
			var error: Vector2 = Vector2(5, 46) - surface.card_point(surface._tool_point(local, data))
			await motion(pointer + error * surface.scale, true)
		check(not source.get_owned_card().emblem_slots[0].is_empty(), "刀头经过贴纸不会提前刮下")
		await button(false)
		check(source.get_owned_card().emblem_slots[0].is_empty(), "松开时刀头命中才能刮下纹章")
		check(main.emblem_library._returned.is_empty(), "长按刮下纹章后不返还工作包")
	await create_timer(0.22).timeout
	var rune_entry: Control = main.emblem_library._entries[3]
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
