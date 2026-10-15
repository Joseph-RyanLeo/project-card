extends "res://tests/d2_7_shop_presentation_test.gd"

const Art = preload("res://scripts/ui/sticker_pack_art.gd")
const Opening = preload("res://scripts/ui/sticker_pack_opening.gd")
const SAMPLE = [
	{"id": "火把"}, {"id": "长剑"}, {"id": "面包"},
	{"id": "光贴纸", "target": "rune"}, {"id": "盾牌Ⅰ"},
]


func _run() -> void:
	create_timer(50.0).timeout.connect(func(): push_error("贴纸包验收超时"); quit(1))
	await _check_art()
	await _check_inspection_resolution()
	shell = DISPLAY.instantiate()
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = false
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if OS.get_cmdline_user_args().has("2k") else DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(0.7).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-sticker-opening-save.json"
	main.run_reward_state.gold = 1000
	main.ordinary_shop_service.rng.seed = 12
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	var index := -1
	for i: int in main.ordinary_shop_service.offers.size():
		if main.ordinary_shop_service.offers[i].kind == "sticker_pack": index = i; break
	check(index >= 0, "真实商店含贴纸包")
	if index < 0: quit(1); return
	var offer: Dictionary = main.ordinary_shop_service.offers[index]
	var rng_before: int = main.ordinary_shop_service.rng.state
	await click(_tile(index).get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await create_timer(0.35).timeout
	var preview_art: Art = main._inspection_surface.viewport.get_node("InspectionPackArt")
	check(preview_art.sheet == null, "未购买的检视不会展示隐藏的五枚贴纸")
	check(not main._inspection_surface.effect.get_shader_parameter("use_flash"), "贴纸包关闭整面扫光")
	# 从商品位置放大的Tween会产生微小浮点误差；纹理尺寸按最近整数像素比较。
	check(main._inspection_surface.viewport.size == Vector2i((main._inspection_surface.size * 4.0).round()), "贴纸包检视按4倍分辨率合成动态效果")
	check((preview_art.upper.material as ShaderMaterial).get_shader_parameter("use_foil") and (preview_art.lower.material as ShaderMaterial).get_shader_parameter("use_foil"), "上下封皮独立启用金边反光")
	await capture("sticker-gold-inspection")
	await key(KEY_ESCAPE)
	await create_timer(0.3).timeout
	check(main.ordinary_shop_service.rng.state == rng_before and main.run_reward_state.gold == 1000, "检视不改变玩法随机数和金币")
	main.run_save_path = "/private/tmp/project-card-sticker-missing-dir/save.json"
	main._on_ordinary_shop_offer_pressed(index)
	check(not is_instance_valid(main._inspection_overlay) and not offer.get("sold", false) and main.run_reward_state.gold == 1000, "存档失败不播放贴纸包演出或扣款")
	main.run_save_path = "/private/tmp/project-card-sticker-opening-save.json"
	var bag_before: int = main.emblem_library.get_inventory_state().size()
	await click(_tile(index).get_global_rect().get_center())
	await create_timer(0.35).timeout
	var sequence: Opening = main._sticker_pack_opening
	check(sequence != null and sequence.phase == Opening.Phase.SEALED, "购买后同一包装放大并等待揭封皮")
	if sequence == null: quit(1); return
	check(main.emblem_library.get_inventory_state().size() == bag_before + 5 and main.run_reward_state.gold == 985, "播放之前交易已提交，只入库五枚并扣款一次")
	check(FileAccess.file_exists(main.run_save_path), "贴纸包交易先保存")
	var after_purchase_rng: int = main.ordinary_shop_service.rng.state
	var surface: InspectionCardSurface = sequence.surface
	check(surface.viewport.size == Vector2i((surface.size * 4.0).round()) and surface.size.is_equal_approx(sequence.art.size + Art.FLIP_PADDING * 2.0), "提高翻皮采样密度不改变表面逻辑尺寸")
	# 使用检视正向投影产生屏幕按下点，再由演出的逆投影还原到封皮原图。
	await move(surface.card_canvas_point(Art.UPPER_POSITION + Vector2(45, 80)))
	await create_timer(0.25).timeout
	var press := surface.card_canvas_point(Art.UPPER_POSITION + Vector2(45, 80))
	_button(press, true)
	await move(surface.card_canvas_point(Art.UPPER_POSITION + Vector2(45, 45)))
	await create_timer(0.08).timeout
	var partial := sequence.progress
	_button(surface.card_canvas_point(Art.UPPER_POSITION + Vector2(45, 45)), false)
	check(partial > 0.25 and partial < 0.9, "4倍倾斜检视中向上拖动只揭开部分封皮")
	await capture("sticker-partial-peel")
	# 横向拖得很远也只能偏转到角度上限，不因横向位移额外推进揭开。
	_button(surface.card_canvas_point(Art.UPPER_POSITION + Vector2(45, 45)), true)
	await move(surface.card_canvas_point(Art.UPPER_POSITION + Vector2(145, 45)))
	await create_timer(0.6).timeout
	check(sequence.peel_angle <= Opening.MAX_PEEL_ANGLE and sequence.peel_angle > Opening.MAX_PEEL_ANGLE - 0.5, "向右展开限制为最大25度")
	check(absf(sequence.progress - partial) < 0.03, "水平移动不额外推进开包")
	await capture("sticker-flip-right")
	await move(surface.card_canvas_point(Art.UPPER_POSITION + Vector2(-55, 45)))
	await create_timer(0.6).timeout
	check(sequence.peel_angle >= -Opening.MAX_PEEL_ANGLE and sequence.peel_angle < -Opening.MAX_PEEL_ANGLE + 0.5, "向左展开限制为最大25度")
	await capture("sticker-flip-left")
	_button(surface.card_canvas_point(Art.UPPER_POSITION + Vector2(-55, 45)), false)
	await move(surface.card_canvas_point(Art.UPPER_POSITION + Vector2(45, 45)))
	await create_timer(0.15).timeout
	_button(surface.card_canvas_point(Art.UPPER_POSITION + Vector2(45, 45)), true)
	await move(surface.card_canvas_point(Art.UPPER_POSITION + Vector2(45, -45)))
	_button(surface.card_canvas_point(Art.UPPER_POSITION + Vector2(45, -45)), false)
	await create_timer(1.25).timeout
	check(sequence.phase == Opening.Phase.REVEALED, "继续向上拖动后完整揭开并抽出整张贴纸")
	check(main._inspection_surface == sequence.surface and sequence.surface.viewport.get_node("StickerSheet").get_child_count() == 6, "抽出的底纸包含同包五枚真实贴纸")
	check(not sequence.surface.effect.get_shader_parameter("use_flash"), "抽出的贴纸不带封皮金边扫光")
	check(main.ordinary_shop_service.rng.state == after_purchase_rng and main.emblem_library.get_inventory_state().size() == bag_before + 5, "揭开和抽纸不重抽、不重复入库")
	await capture("sticker-sheet-revealed")
	await click(sequence.surface.get_global_rect().get_center())
	await create_timer(6.0).timeout
	check(sequence.phase == Opening.Phase.EMPTY_REVEALED and sequence.surface.viewport.get_node("StickerSheet").get_child_count() == 1, "依次剥离并入箱后只留下空底纸供检视")
	await click(sequence.surface.get_global_rect().get_center())
	await create_timer(0.3).timeout
	check(not is_instance_valid(main._inspection_overlay) and main._sticker_pack_opening == null and main.ordinary_shop_open, "收起贴纸后回店，清理演出和检视")
	check(main.run_reward_state.gold == 985, "动画结束不再次扣款")
	# 再直接展示同一份已确定内容，检查自动揭开与提前强制清理。
	main._open_shop_pack_inspection(offer, null, true)
	await create_timer(0.3).timeout
	sequence = main._sticker_pack_opening
	await click(main._inspection_surface.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await create_timer(0.25).timeout
	check(sequence.progress > 0.0 and sequence.phase == Opening.Phase.PEELING, "右键会自动推进卷曲")
	main._close_card_inspection(true)
	await create_timer(0.6).timeout
	check(main._sticker_pack_opening == null and not is_instance_valid(main._inspection_overlay), "强制关闭会停止回调并清理包装")
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Sticker pack opening failures: ", failures)
	quit(1 if failures else 0)


func move(point: Vector2) -> void:
	Input.warp_mouse(shell.render_container.get_global_transform_with_canvas() * point)
	await super.move(point)


func _button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _check_art() -> void:
	var art := Art.new()
	for style: int in 4:
		var sheet := art.create_sheet(SAMPLE, style)
		check(sheet.get_child_count() == 6 and sheet.size == Vector2(95, 109), "底纸%d含五枚贴纸且保持原生尺寸" % style)
		for index: int in 5:
			var icon := sheet.get_node("Sticker_%d" % index) as TextureRect
			var center := icon.position + icon.size * 0.5
			check(center.distance_to(Art.DOT_CENTERS[style][index]) <= 0.71 and icon.texture != null, "底纸%d第%d枚贴纸居中对齐白点" % [style, index])
			check(absf(icon.rotation_degrees) <= Art.STICKER_ROTATION_LIMIT and icon.pivot_offset == icon.size * 0.5, "底纸贴纸在±45度内绕自身中心旋转")
		sheet.free()
	if DisplayServer.get_name() == "headless": art.free(); return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(299, 411)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(art)
	art.position = Art.FLIP_PADDING
	await process_frame
	await RenderingServer.frame_post_draw
	var flat := viewport.get_texture().get_image()
	for layer: TextureRect in [art.lower, art.upper]:
		(layer.material as ShaderMaterial).set_shader_parameter("use_foil", true)
		(layer.material as ShaderMaterial).set_shader_parameter("pointer_force", Vector2(-0.8, 0.2))
	await RenderingServer.frame_post_draw
	var left := viewport.get_texture().get_image()
	for layer: TextureRect in [art.lower, art.upper]:
		(layer.material as ShaderMaterial).set_shader_parameter("pointer_force", Vector2(0.8, -0.2))
	await RenderingServer.frame_post_draw
	var right := viewport.get_texture().get_image()
	var nongold_changes := 0
	var gold_changes := 0
	for y: int in flat.get_height():
		for x: int in flat.get_width():
			var original := flat.get_pixel(x, y)
			var gold := original.a > 0.9 and Vector3(original.r, original.g, original.b).distance_to(Vector3(192, 152, 82) / 255.0) < 0.02
			var changed := left.get_pixel(x, y) != right.get_pixel(x, y)
			if changed:
				if gold: gold_changes += 1
				else: nongold_changes += 1
	check(gold_changes > 100 and nongold_changes == 0, "真实渲染中鼠标反光只改变金色像素，棕色及透明像素不变")
	art.configure_flip()
	art.set_peel_progress(0.55)
	await RenderingServer.frame_post_draw
	var peeled := viewport.get_texture().get_image()
	check(peeled.get_data() != right.get_data(), "卷曲着色器在真实渲染中改变上封皮")
	var back_pixels := 0
	for y: int in 36:
		for x: int in 91:
			var color := peeled.get_pixel(100 + 4 + x, 150 + 1 + y)
			if Vector3(color.r, color.g, color.b).distance_to(Vector3(0.39, 0.20, 0.14)) < 0.025: back_pixels += 1
	check(back_pixels > 1500, "中段翻页有大面积展开背面，而非只剩狭窄卷边或小舌片")
	for direction: int in [-1, 1]:
		art.set_peel_angle(float(direction) * Opening.MAX_PEEL_ANGLE)
		for progress_value: float in [0.25, 0.55, 0.75]:
			art.set_peel_progress(progress_value)
			await RenderingServer.frame_post_draw
			var frame := viewport.get_texture().get_image()
			frame.save_png("/private/tmp/project-card-flip-%s-%s.png" % [direction, progress_value])
			check(frame.get_used_rect().position.y > 0 and frame.get_used_rect().end.x < viewport.size.x, "偏转%d度、进度%.2f的完整翻皮没有碰到画布边界" % [direction * Opening.MAX_PEEL_ANGLE, progress_value])
	art.set_peel_angle(0.0)
	var lower_unchanged := true
	for x: int in 99:
		if peeled.get_pixel(100 + x, 150 + 104) != right.get_pixel(100 + x, 150 + 104): lower_unchanged = false
	check(lower_unchanged, "揭开上半封皮时下半封皮保持完整")
	viewport.queue_free()
	await process_frame


func _check_inspection_resolution() -> void:
	if DisplayServer.get_name() == "headless": return
	var host := Control.new()
	root.add_child(host)
	var edge_changes: Array[int] = []
	for sampling: int in [1, 4]:
		var art := Art.new()
		host.add_child(art)
		var surface := InspectionCardSurface.new()
		host.add_child(surface)
		surface.setup_art(art, Art.FLIP_PADDING, float(sampling))
		art.configure_inspection(surface)
		art.configure_flip()
		art.get_node("PackBase").hide()
		art.lower.hide()
		surface.set_process(false)
		surface.scale = Vector2(4, 4)
		art.set_peel_angle(25.0)
		art.set_peel_progress(0.65)
		await process_frame
		await RenderingServer.frame_post_draw
		var folded := surface.viewport.get_texture().get_image()
		var changes := 0
		var previous_edge := -1
		# 比较同一姿态、同一段连续折线的真实GPU轮廓，4倍采样应产生更多细小台阶。
		for x: int in range(20 * sampling, 70 * sampling):
			var edge := -1
			for y: int in range(210 * sampling - 1, 150 * sampling - 1, -1):
				if folded.get_pixel(104 * sampling + x, y).a > 0.9:
					edge = y
					break
			if previous_edge >= 0 and edge >= 0 and edge != previous_edge: changes += 1
			previous_edge = edge
		edge_changes.append(changes)
		if sampling == 4:
			art.set_peel_progress(0.0)
			await RenderingServer.frame_post_draw
			var sealed := surface.viewport.get_texture().get_image()
			var source := Art.UPPER.get_image()
			var fine_gold := false
			var flat_brown := true
			for y: int in source.get_height():
				for x: int in source.get_width():
					var original := source.get_pixel(x, y)
					if original.a < 0.9: continue
					var first := sealed.get_pixel((104 + x) * 4, (151 + y) * 4)
					var last := sealed.get_pixel((104 + x) * 4 + 3, (151 + y) * 4 + 3)
					var gold := Vector3(original.r, original.g, original.b).distance_to(Vector3(192, 152, 82) / 255.0) < 0.02
					if gold:
						if first != last: fine_gold = true
					else:
						if first != last or Vector3(first.r, first.g, first.b).distance_to(Vector3(original.r, original.g, original.b)) > 0.02: flat_brown = false
			check(fine_gold, "金边高光能在单个原图像素内部连续变化，不再整格放大")
			check(flat_brown, "提高动态效果分辨率仍保持原图棕色像素清晰且颜色不变")
		surface.queue_free()
		await process_frame
	check(edge_changes[1] > edge_changes[0] * 2.5 and edge_changes[1] > 60, "4倍采样的真实斜折线精度高于1倍折线放大")
	host.queue_free()
	await process_frame
