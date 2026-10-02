extends SceneTree

const DISPLAY_SCENE = preload("res://scenes/GameDisplay.tscn")

var failures := 0
var input_viewport: Viewport
var input_transform := Transform2D.IDENTITY
var pointer := Vector2.ZERO


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


func pointer_for_blade_center(surface: InspectionCardSurface, data: Dictionary, card_point: Vector2) -> Vector2:
	var transform := surface.get_global_transform_with_canvas()
	var scale := transform.get_scale()
	var offset := (data.get("hit_rect_offset", Vector2.ZERO) as Vector2) / scale
	var hit_size := (data.get("hit_rect_size", Vector2.ZERO) as Vector2) / scale
	var blade_center_offset := offset + hit_size * 0.5
	var surface_point := surface.PADDING + card_point - blade_center_offset
	# 逐点求透视逆变换，让真实鼠标轨迹命中正在倾斜的卡面。
	for _iteration: int in 8:
		var sample_point := surface_point + blade_center_offset
		var projected := surface.card_point(sample_point)
		var error := card_point - projected
		if error.length() < 0.001:
			break
		var dx := surface.card_point(sample_point + Vector2.RIGHT) - projected
		var dy := surface.card_point(sample_point + Vector2.DOWN) - projected
		surface_point += Transform2D(dx, dy, Vector2.ZERO).affine_inverse() * error
	return transform * surface_point


func _run() -> void:
	root.size = Vector2i(2560, 1440)
	var display := DISPLAY_SCENE.instantiate()
	root.add_child(display)
	display.apply_display_mode(GameDisplay.DisplayMode.WINDOW_2K)
	for _frame: int in 4:
		await process_frame
	var main = display.main_screen
	main.scraper_count = 2
	main.emblem_library.set_scraper_count(2)
	input_viewport = display.internal_viewport
	input_viewport.notify_mouse_entered()
	input_transform = display.render_container.get_global_transform_with_canvas()
	check(input_transform.get_scale().is_equal_approx(Vector2(2, 2)), "2K输入落回1280×720游戏逻辑坐标")
	var owned: OwnedCard
	var source: CardView
	for slot: Control in main._get_collection_card_slots():
		var candidate: OwnedCard = slot.get_meta("owned_card", null)
		if candidate != null and candidate.card_data.card_type == CardData.CardType.MINION and CardData.ElementType.FIRE not in candidate.resolved_runes:
			for rune_index: int in candidate.rune_revealed.size():
				if not candidate.rune_revealed[rune_index] and candidate.rune_stickers[rune_index].is_empty():
					owned = candidate
					source = slot.get_child(0)
					break
		if owned != null:
			break
	check(owned != null, "场景提供带未揭晓符文的随从实例")
	if owned == null:
		quit(1)
		return
	main._open_card_inspection(owned.card_data, owned, source)
	await create_timer(0.3).timeout
	main._toggle_inspection_library()
	await create_timer(0.3).timeout
	input_transform = display.render_container.get_global_transform_with_canvas()
	var surface: InspectionCardSurface = main._inspection_surface
	surface.force = Vector2.ZERO
	var hidden_index := -1
	for index: int in owned.rune_revealed.size():
		if not owned.rune_revealed[index] and owned.rune_stickers[index].is_empty():
			hidden_index = index
			break
	var scraper: TextureRect = main.emblem_library._scraper
	var scraper_data: Dictionary = scraper._build_drag_data(scraper.blade_point, false)
	var unused_preview := scraper_data.get("drag_visual") as Control
	if is_instance_valid(unused_preview): unused_preview.free()
	scraper_data.erase("drag_visual")
	var cover_origin: Vector2 = main._inspection_card_view.rune_area_position + Vector2(
		hidden_index * (main._inspection_card_view.rune_slot_size.x + main._inspection_card_view.rune_spacing),
		0.0
	)
	var scraper_count_before: int = main.scraper_count
	var pointer_start: Vector2 = scraper.get_global_rect().get_center()
	await motion(pointer_start)
	await button(true)
	await button(false)
	await process_frame
	check(main._rune_scraper_mode, "2K真实点击工具图标进入显式刮刀行动模式")
	check(owned.get_rune_scraped_pixel_count(hidden_index) == 0 and main.scraper_count == scraper_count_before, "2K悬停和点击工具原位不会擦痕或消耗刮刀")
	var first_point := pointer_for_blade_center(surface, scraper_data, cover_origin + Vector2(11.5, 11.5))
	await motion(first_point)
	await process_frame
	check(owned.get_rune_scraped_pixel_count(hidden_index) == 0 and main.scraper_count == scraper_count_before, "2K刀头移动到卡面仍不自动刮擦")
	await button(true)
	await button(false)
	var first_sample_count := owned.get_rune_scraped_pixel_count(hidden_index)
	check(first_sample_count > 0 and main.scraper_count == scraper_count_before - 1 and not owned.rune_revealed[hidden_index], "2K首次真实擦除像素时立即只扣一把刀")
	var finished := false
	await button(true)
	for row: int in range(1, 23, 2):
		for column: int in range(1, 23, 2):
			var scrape_point := pointer_for_blade_center(surface, scraper_data, cover_origin + Vector2(column + 0.5, row + 0.5))
			await motion(scrape_point, true)
			if owned.rune_revealed[hidden_index]:
				finished = true
				break
		if finished:
			break
	await button(false)
	check(
		hidden_index >= 0
		and owned.rune_revealed[hidden_index]
		and main.scraper_count == scraper_count_before - 1,
		"2K刀头轨迹达到70%时提前揭晓并且同槽连续擦不重复扣刀"
	)
	var second_hidden_index := -1
	for index: int in owned.rune_revealed.size():
		if not owned.rune_revealed[index] and owned.rune_stickers[index].is_empty():
			second_hidden_index = index
			break
	if second_hidden_index >= 0:
		var second_origin: Vector2 = main._inspection_card_view.rune_area_position + Vector2(second_hidden_index * (main._inspection_card_view.rune_slot_size.x + main._inspection_card_view.rune_spacing), 0.0)
		# 原生59像素刮刀的刀头更宽；从边角轻刮，确保本项继续验收不足70%的付费槽。
		var second_point := pointer_for_blade_center(surface, scraper_data, second_origin + Vector2(4, 4))
		await motion(second_point)
		await button(true)
		await button(false)
		check(main.scraper_count == 0 and owned.get_rune_scraped_pixel_count(second_hidden_index) > 0, "2K最后一把刀付费后可在新槽产生痕迹")
		var paid_progress := owned.get_rune_scraped_pixel_count(second_hidden_index)
		var third_hidden_index := -1
		for index: int in owned.rune_revealed.size():
			if index != second_hidden_index and not owned.rune_revealed[index] and owned.rune_stickers[index].is_empty():
				third_hidden_index = index
				break
		if third_hidden_index >= 0:
			var third_origin: Vector2 = main._inspection_card_view.rune_area_position + Vector2(third_hidden_index * (main._inspection_card_view.rune_slot_size.x + main._inspection_card_view.rune_spacing), 0.0)
			var third_point := pointer_for_blade_center(surface, scraper_data, third_origin + Vector2(11.5, 11.5))
			await motion(third_point)
			await button(true)
			await button(false)
			check(owned.get_rune_scraped_pixel_count(third_hidden_index) == 0, "2K无刀时拒绝在另一个未付费槽留下痕迹")
		await motion(pointer_for_blade_center(surface, scraper_data, second_origin + Vector2(5, 4)))
		await button(true)
		await motion(pointer_for_blade_center(surface, scraper_data, second_origin + Vector2(6, 4)), true)
		await button(false)
		check(not owned.rune_revealed[second_hidden_index] and owned.get_rune_scraped_pixel_count(second_hidden_index) >= paid_progress, "2K库存为零仍可继续擦不足70%的已付费槽")
		main._finish_rune_scraper_mode()
		check(owned.rune_revealed[second_hidden_index], "2K退出模式时完整揭晓不足70%的已付费槽")
	main._close_card_inspection()
	await create_timer(0.3).timeout
	display.queue_free()
	await process_frame
	print("2K rune scrape failures: ", failures)
	quit(1 if failures else 0)
