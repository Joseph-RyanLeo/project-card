extends SceneTree

## 在实际渲染器中检查五种工艺、图标法线投影、视差和恢复，并输出对照图。
const SCENE := preload("res://scenes/tools/CardArtTuner.tscn")
const CARD_PATH := "res://resources/cards/militia.tres"
const CAPTURE_RECT := Rect2i(40, 104, 540, 616) # 完整4倍卡面及工艺标题的截图范围
var tuner: CardArtTuner
var failures := 0
var assertions := 0

func _initialize() -> void: _run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func point(force: Vector2) -> void:
	tuner._preview_effect_material.set_shader_parameter("pointer_force", force)
	tuner._finish_preview.update_pointer(force)

func select_finish(index: int) -> void:
	tuner.finish_selector.select(index)
	tuner.finish_selector.item_selected.emit(index)

func capture() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	return root.get_texture().get_image()

func capture_inner() -> Image:
	# 直接读当前验收的内层画布；GPU完成后再读回，避免拿到尚未完成的帧。
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	return tuner.preview_viewport.get_texture().get_image()

func difference(a: Image, b: Image, region: Rect2i) -> int:
	var count := 0
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			var delta := a.get_pixel(x, y) - b.get_pixel(x, y)
			if absf(delta.r) + absf(delta.g) + absf(delta.b) + absf(delta.a) > 0.02: count += 1
	return count

func _run() -> void:
	root.size = Vector2i(1280, 720)
	tuner = SCENE.instantiate()
	root.add_child(tuner)
	await process_frame
	await process_frame
	tuner.set_process(false)
	tuner.card_data = load(CARD_PATH)
	await process_frame
	tuner.use_3d_check.button_pressed = false
	var bytes_before := FileAccess.get_file_as_bytes(CARD_PATH)
	check(tuner.finish_selector.item_count == 6 and tuner.finish_selector.get_item_text(0) == "普通卡", "普通卡与五种工艺都可切换")
	tuner.use_flash_check.button_pressed = false
	point(Vector2(0.65, -0.35))
	var reference: Image = await capture()
	tuner.use_flash_check.button_pressed = true
	var grid := Image.create(CAPTURE_RECT.size.x * 3, CAPTURE_RECT.size.y * 2, false, Image.FORMAT_RGBA8)
	var caption := tuner.get_node("CenterContainer/Workspace/PreviewCaption") as Label
	var art_rect := Rect2i(132, 196, 280, 300) # 只比较立绘区域，排除状态栏和标题变化
	for finish: int in range(6):
		select_finish(finish)
		caption.text = CardFinishPreview.LABELS[finish] + " · 同卡同角度"
		point(Vector2(0.65, -0.35))
		var shot: Image = await capture()
		check(shot.get_size() == Vector2i(1280, 720), "真实渲染截图尺寸")
		if finish == CardFinishPreview.Finish.PLAIN:
			check(not bool(tuner._preview_effect_material.get_shader_parameter("use_flash")), "普通卡不叠加扫光")
			check(difference(reference, shot, Rect2i(60, 136, 420, 560)) == 0, "普通卡与关闭材质的原始卡面一致")
		else:
			check(difference(reference, shot, art_rect) > 100, "工艺画面与关闭材质时有可见区别：" + caption.text)
		if finish in [CardFinishPreview.Finish.HOLOGRAPHIC, CardFinishPreview.Finish.EMBOSSED]:
			var title_origin := tuner.preview_display.position + (tuner.preview_card.position + tuner.preview_card.title_area_position) * 4.0
			# 名字框右侧是透明斜角，不能把其后插画算作文字；按真实字体宽度比较字形。
			var label := tuner.preview_card.name_label
			var glyph_width := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			var glyph_origin := title_origin + Vector2((tuner.preview_card.title_area_size.x - glyph_width) * 2.0, 0)
			var title_rect := Rect2i(Vector2i(glyph_origin), Vector2i(glyph_width * 4.0, 32))
			check(difference(reference, shot, title_rect) == 0, "卡名不受立绘材质染色")
			check(tuner.preview_viewport.size == Vector2i(tuner.preview_display.size * 4.0), "动态材质用高分辨率采样，保持显示尺寸")
		check(tuner.preview_card.card_data != tuner.card_data, "工艺不污染共享卡牌定义")
		for material: ShaderMaterial in tuner._finish_preview._badge_materials.values():
			check(bool(material.get_shader_parameter("relief_enabled")) == (finish != CardFinishPreview.Finish.PLAIN), "仅闪卡起启用图标法线与投影")
		grid.blit_rect(shot, CAPTURE_RECT, Vector2i((finish % 3) * CAPTURE_RECT.size.x, floori(float(finish) / 3.0) * CAPTURE_RECT.size.y))
		shot.save_png("/private/tmp/project-card-finish-%d.png" % finish)
	check(grid.save_png("/private/tmp/project-card-five-finishes.png") == OK, "输出普通卡与五种工艺对照")
	# 同一片材质在不同鼠标方向下改变反光，但回到原方向必须得到同一画面。
	for finish: int in [CardFinishPreview.Finish.HOLOGRAPHIC, CardFinishPreview.Finish.EMBOSSED, CardFinishPreview.Finish.FRACTURED]:
		select_finish(finish)
		point(Vector2(-0.8, 0.3))
		var left: Image = await capture()
		point(Vector2(0.8, -0.3))
		var right: Image = await capture()
		check(difference(left, right, art_rect) > 100, "角度改变材质或纵深：" + CardFinishPreview.LABELS[finish])
		point(Vector2(-0.8, 0.3))
		var restored: Image = await capture()
		check(difference(left, restored, art_rect) == 0, "材质固定在卡面，回到原角度完全恢复")
	select_finish(CardFinishPreview.Finish.HOLOGRAPHIC)
	point(Vector2(0.8, -0.3))
	tuner.use_3d_check.button_pressed = true
	tuner.finish_depth_spin.value = 0.0
	var flat: Image = await capture()
	tuner.finish_depth_spin.value = 5.0
	var deep: Image = await capture()
	check(difference(flat, deep, art_rect) > 100, "景深参数确实改变人物与背景关系")
	await test_holographic_perspective()
	await test_full_card_fractured()
	tuner.use_3d_check.button_pressed = false
	select_finish(CardFinishPreview.Finish.OVERFRAME)
	var clip := tuner.preview_card.get_node("OverframeArtClip") as Control
	check(clip.visible and clip.clip_contents and clip.position == Vector2(3, 3), "超框有独立外轮廓裁切")
	check(clip.z_index > tuner.preview_card.card_frame.z_index and clip.z_index < tuner.preview_card.card_name_frame.z_index, "超框遮挡顺序保护卡名与属性")
	var overframe_art := clip.get_child(0) as TextureRect
	check(overframe_art.scale == Vector2.ONE and overframe_art.size == tuner.preview_card.art_texture.size, "超框立绘保持原尺寸")
	check(overframe_art.position + clip.position == tuner.preview_card.art_panel.position + tuner.preview_card.art_texture.position, "超框不改变原立绘取景位置")
	check(clip.position.y + clip.size.y > tuner.preview_card.rune_area_position.y + tuner.preview_card.rune_area_size.y, "超框允许延伸到完整符文板块")
	check(tuner.preview_card.bottom_panel.z_index + tuner.preview_card.rune_row.z_index > clip.z_index, "符文绘制在超框人物上方")
	await test_overframe_runes()
	tuner.use_flash_check.button_pressed = false
	check(not clip.visible and tuner.preview_card.art_texture.visible, "关闭材质恢复原人物层")
	tuner.use_flash_check.button_pressed = true
	select_finish(CardFinishPreview.Finish.FOIL)
	tuner.use_flash_check.button_pressed = false
	point(Vector2(0.65, -0.35))
	var reset: Image = await capture()
	check(difference(reference, reset, art_rect) == 0, "关闭材质后原画精确恢复")
	tuner.use_flash_check.button_pressed = true
	# Window 的 get_mouse_position 读取真实指针，单独 push_input 不会改变它。
	# 复用既有图形验收的 warp_mouse 流程，验证完整鼠标跟随链路。
	select_finish(CardFinishPreview.Finish.HOLOGRAPHIC)
	tuner.use_3d_check.button_pressed = true
	tuner.set_process(true)
	var mouse := InputEventMouseMotion.new()
	mouse.position = tuner.preview_display.position + tuner.preview_display.size * tuner.preview_display.scale * Vector2(0.85, 0.5)
	mouse.global_position = mouse.position
	root.warp_mouse(mouse.position)
	root.notify_mouse_entered()
	root.push_input(mouse, true)
	await create_timer(0.3).timeout
	check(tuner._preview_pointer_force.x > 0.3, "真实鼠标事件驱动卡牌倾斜与材质；方向=%s，本地位置=%s" % [tuner._preview_pointer_force, tuner.preview_display.get_local_mouse_position()])
	check(tuner._finish_preview._art_material.get_shader_parameter("pointer_force") == tuner._preview_pointer_force, "人物视差与外层倾斜共用平滑鼠标方向")
	tuner.set_process(false)
	tuner.use_3d_check.button_pressed = false
	# 使用真实法线资源验证专用贴图接入，无须写入正式卡牌。
	var normal_image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	normal_image.fill(Color(0.7, 0.45, 0.95))
	var custom := tuner.card_data.duplicate() as CardData
	custom.art_normal_texture = ImageTexture.create_from_image(normal_image)
	tuner.card_data = custom
	await process_frame
	select_finish(CardFinishPreview.Finish.EMBOSSED)
	var dedicated: Image = await capture()
	check(tuner._finish_preview.get_description().contains("专用法线"), "专用法线贴图已接入")
	check(difference(reference, dedicated, art_rect) > 100, "专用法线实际改变画面")
	await test_badge_relief()
	await test_holographic_background_corners()
	var empty := CardData.new()
	empty.id = &"finish_no_art_probe"
	empty.display_name = "暂缺卡图"
	tuner.card_data = empty
	await process_frame
	for finish: int in range(6):
		select_finish(finish)
		await process_frame
		check(not clip.visible, "缺图卡不会残留超框人物")
	check(FileAccess.get_file_as_bytes(CARD_PATH) == bytes_before, "所有工艺预览保持正式卡牌文件不变")
	tuner.queue_free()
	await process_frame
	print("五种卡面工艺GPU验收：%d条断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)


func test_holographic_perspective() -> void:
	var art := tuner._finish_preview._art_material
	var background := tuner._finish_preview._background_material
	for material: ShaderMaterial in [art, background]:
		check(material.get_shader_parameter("max_tilt_degrees") == tuner._preview_effect_material.get_shader_parameter("max_tilt_degrees"), "前后层与卡框共用倾角")
		check(material.get_shader_parameter("fov") == tuner._preview_effect_material.get_shader_parameter("fov"), "前后层与卡框共用相机视野")
	check(float(background.get_shader_parameter("layer_depth")) < float(art.get_shader_parameter("layer_depth")) and float(art.get_shader_parameter("layer_depth")) < 0.0, "从前到后依次为卡框、人物、背景")
	var art_rect := Rect2i(132, 196, 280, 300)
	point(Vector2.ZERO)
	# 单独检查人物原取景；背景为避免露空可按景深预留固定边缘。
	tuner.finish_depth_spin.value = 0.0
	tuner.preview_card.art_background.hide()
	var center_flat := await capture()
	tuner.finish_depth_spin.value = 5.0
	tuner.preview_card.art_background.hide()
	var center_deep := await capture()
	check(difference(center_flat, center_deep, art_rect) == 0, "正面姿态改变景深不放大人物、不改变取景")
	tuner.preview_card.art_background.show()
	point(Vector2(0.8, -0.7))
	var tilted := await capture()
	art.set_shader_parameter("layer_depth", 0.0)
	var art_flat := await capture()
	background.set_shader_parameter("layer_depth", 0.0)
	var both_flat := await capture()
	check(difference(tilted, art_flat, art_rect) > 100, "同一倾角下，人物在卡框内部形成独立深度投影")
	check(difference(art_flat, both_flat, art_rect) > 100, "同一倾角下，背景后退形成独立深度投影")
	tuner._finish_preview.refresh()
	# 关闭3D时三层同时停止旋转，不能残留独立的反向倾斜／鼠标平移。
	tuner.use_3d_check.button_pressed = false
	tuner.finish_depth_spin.value = 0.0
	var no_3d_flat := await capture()
	tuner.finish_depth_spin.value = 5.0
	var no_3d_deep := await capture()
	check(difference(no_3d_flat, no_3d_deep, art_rect) == 0, "关闭3D后内外层同时停止深度投影")
	tuner.use_3d_check.button_pressed = true
	# 真实GPU校准：不透明正式背景分别作为前后平面，测量深度位移的方向与大小。
	var probe := TextureRect.new()
	var calibration := tuner.preview_card.art_background.texture.get_image()
	# 原素材四角自带透明像素；校准平面去掉alpha，只检查投影是否额外露空。
	calibration.convert(Image.FORMAT_RGB8)
	# 校准图中心加入固定大小标记，测量背景图案本身的缩放，而非只检查窗口尺寸。
	calibration.fill_rect(Rect2i(calibration.get_size() / 2 - Vector2i(8, 8), Vector2i(16, 16)), Color.MAGENTA)
	probe.texture = ImageTexture.create_from_image(calibration)
	probe.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	probe.stretch_mode = TextureRect.STRETCH_SCALE
	probe.position = Vector2(24, 24)
	probe.size = Vector2(80, 80)
	var material := art.duplicate() as ShaderMaterial
	material.set_shader_parameter("card_finish", -1)
	material.set_shader_parameter("card_origin", Vector2.ZERO)
	material.set_shader_parameter("layer_size", probe.size)
	material.set_shader_parameter("layer_origin", probe.position)
	probe.material = material
	tuner.preview_viewport.add_child(probe)
	tuner.preview_card.hide()
	for force: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		material.set_shader_parameter("pointer_force", force)
		var centers: Array[Vector2] = []
		for plane_depth: float in [0.0, -50.0, -50.0 * CardFinishPreview.BACKGROUND_DEPTH_RATIO]:
			material.set_shader_parameter("layer_depth", plane_depth)
			var image := await capture_inner()
			centers.append(opaque_bounds_center(image))
		var art_travel := (centers[1] - centers[0]).dot(force)
		var background_travel := (centers[2] - centers[0]).dot(force)
		check(art_travel < -12.0 and background_travel < art_travel - 4.0, "鼠标%s：人物相对卡框反向偏移，背景反向更多；%.1f／%.1f" % [force, art_travel, background_travel])
	# 背景窗口始终铺满，并让透明卡背显出任何实际采样越界。
	material.set_shader_parameter("background_layer", true)
	material.set_shader_parameter("layer_depth", -50.0 * CardFinishPreview.BACKGROUND_DEPTH_RATIO)
	material.set_shader_parameter("use_3d", false)
	var original_background := await capture_inner()
	var original_marker := color_marker_bounds(original_background)
	material.set_shader_parameter("use_3d", true)
	var marker_sizes: Array[Vector2i] = []
	for force: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO]:
		material.set_shader_parameter("pointer_force", force)
		var image := await capture_inner()
		var holes := 0
		for y: int in range(97, 415):
			for x: int in range(97, 415):
				if image.get_pixel(x, y).a < 0.99: holes += 1
		check(holes == 0, "背景最大深度与倾角无透明接缝：%s（%d处）" % [force, holes])
		var marker := color_marker_bounds(image)
		check(marker.size.x > 20 and marker.size.y > 20, "背景校准标记实际可见")
		marker_sizes.append(marker.size)
		check(absi(marker.size.x - original_marker.size.x) <= 1 and absi(marker.size.y - original_marker.size.y) <= 1, "全息背景与原图保持同倍率：" + str(force))
	var smallest := marker_sizes[0]
	var largest := marker_sizes[0]
	for size: Vector2i in marker_sizes:
		smallest = smallest.min(size)
		largest = largest.max(size)
	check(largest.x - smallest.x <= 1 and largest.y - smallest.y <= 1, "鼠标移动时背景图案大小保持不变，允许1个显示像素的取整差：" + str(marker_sizes))
	probe.queue_free()
	tuner.preview_card.show()
	tuner.finish_depth_spin.value = 2.5
	tuner._finish_preview.refresh()
	# 输出三个真实姿态，供观察人物、卡框与背景作为同一整体转动。
	var strip := Image.create(CAPTURE_RECT.size.x * 3, CAPTURE_RECT.size.y, false, Image.FORMAT_RGBA8)
	var caption := tuner.get_node("CenterContainer/Workspace/PreviewCaption") as Label
	var poses := [Vector2(-0.9, -0.45), Vector2.ZERO, Vector2(0.9, 0.45)]
	for index: int in poses.size():
		caption.text = ["全息 · 左侧倾斜", "全息 · 正面", "全息 · 右侧倾斜"][index]
		point(poses[index])
		var shot := await capture()
		strip.blit_rect(shot, CAPTURE_RECT, Vector2i(index * CAPTURE_RECT.size.x, 0))
	check(strip.save_png("/private/tmp/project-card-holo-window-depth.png") == OK, "输出卡框、人物、背景从近到远的三个姿态")
	point(Vector2(0.65, -0.35))
	await capture()


func test_full_card_fractured() -> void:
	tuner.use_3d_check.button_pressed = false
	select_finish(CardFinishPreview.Finish.FRACTURED)
	point(Vector2(0.65, -0.35))
	tuner.finish_strength_spin.value = 0.0
	var flat := await capture()
	tuner.finish_strength_spin.value = 0.75
	var fractured := await capture()
	var origin := tuner.preview_display.position + tuner.preview_card.position * 4.0
	for entry: Array in [["卡框", Rect2i(2, 35, 6, 50)], ["卡名", Rect2i(24, 7, 50, 8)], ["符文板块", Rect2i(10, 109, 79, 24)], ["生命图标", Rect2i(86, 88, 15, 20)]]:
		var native: Rect2i = entry[1]
		var region := Rect2i(Vector2i(origin) + native.position * 4, native.size * 4)
		check(difference(flat, fractured, region) > 10, "整卡碎闪实际覆盖：" + String(entry[0]))
	check(bool(tuner._preview_effect_material.get_shader_parameter("use_fractured")), "碎闪由合成后的整卡材质处理")
	tuner.use_flash_check.button_pressed = false
	check(not bool(tuner._preview_effect_material.get_shader_parameter("use_fractured")), "关闭材质时整卡碎闪也关闭")
	tuner.use_flash_check.button_pressed = true
	select_finish(CardFinishPreview.Finish.HOLOGRAPHIC)
	point(Vector2(0.65, -0.35))



func opaque_bounds_center(image: Image) -> Vector2:
	var low := Vector2i(image.get_size())
	var high := Vector2i(-1, -1)
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > 0.99:
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
	return Vector2(low + high) * 0.5


func color_marker_bounds(image: Image) -> Rect2i:
	var low := image.get_size()
	var high := Vector2i(-1, -1)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var color := image.get_pixel(x, y)
			if color.r > 0.95 and color.b > 0.95 and color.g < 0.05:
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
	return Rect2i(low, (high - low + Vector2i.ONE).max(Vector2i.ZERO))


func test_overframe_runes() -> void:
	select_finish(CardFinishPreview.Finish.PLAIN)
	var original := await capture_inner()
	select_finish(CardFinishPreview.Finish.OVERFRAME)
	var overframe := await capture_inner()
	var changed := 0
	var sampled := 0
	for slot: Node in tuner.preview_card.rune_row.get_children():
		for child: Node in slot.get_children():
			if not child is TextureRect: continue
			var icon := child as TextureRect
			if not icon.visible or icon.texture == null: continue
			var mask := icon.texture.get_image()
			var transform := icon.get_global_transform_with_canvas()
			for y: int in mask.get_height():
				for x: int in mask.get_width():
					if mask.get_pixel(x, y).a < 0.99: continue
					var pixel := Vector2i(transform * (Vector2(x, y) + Vector2(0.5, 0.5)))
					sampled += 1
					if original.get_pixelv(pixel) != overframe.get_pixelv(pixel): changed += 1
	check(sampled > 100 and changed == 0, "实际GPU画面中，超框人物不遮挡任何不透明符文像素")


func test_holographic_background_corners() -> void:
	tuner.card_data = load("res://resources/cards/ember_squire.tres")
	await process_frame
	select_finish(CardFinishPreview.Finish.HOLOGRAPHIC)
	tuner.use_3d_check.button_pressed = true
	tuner.finish_depth_spin.value = 5.0
	var source := CardView.DEFAULT_ART_BACKGROUND_TEXTURE
	var original := source.get_image()
	var preview_texture := tuner.preview_card.art_background.texture
	var prepared := preview_texture.get_image()
	var original_holes := 0
	var remaining_holes := 0
	var changed_opaque := 0
	for y: int in original.get_height():
		for x: int in original.get_width():
			var before := original.get_pixel(x, y)
			var after := prepared.get_pixel(x, y)
			if before.a < 0.99: original_holes += 1
			elif before != after: changed_opaque += 1
			if after.a < 0.99: remaining_holes += 1
	check(original_holes > 0, "直接使用带透明四角的正式背景，不去除原素材alpha")
	check(remaining_holes == 0 and changed_opaque == 0 and prepared.get_size() == original.get_size(), "全息显示副本补齐透明角，原图不透明像素和尺寸保持原样")
	var probe := TextureRect.new()
	probe.texture = preview_texture
	probe.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	probe.stretch_mode = TextureRect.STRETCH_SCALE
	probe.position = Vector2(24, 24)
	probe.size = Vector2(79, 95)
	var material := tuner._finish_preview._background_material.duplicate() as ShaderMaterial
	material.set_shader_parameter("layer_origin", probe.position)
	material.set_shader_parameter("card_origin", Vector2.ZERO)
	material.set_shader_parameter("layer_size", probe.size)
	material.set_shader_parameter("effect_strength", 0.0)
	probe.material = material
	tuner.preview_viewport.add_child(probe)
	tuner.preview_card.hide()
	for force: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO]:
		material.set_shader_parameter("pointer_force", force)
		var shot := await capture_inner()
		var holes := 0
		for y: int in range(97, 475):
			for x: int in range(97, 411):
				if shot.get_pixel(x, y).a < 0.99: holes += 1
		check(holes == 0, "正式背景在极限视差和正面姿态下不露透明黑角：%s（%d处）" % [force, holes])
	probe.queue_free()
	tuner.preview_card.show()
	select_finish(CardFinishPreview.Finish.PLAIN)
	check(tuner.preview_card.art_background.texture == source, "普通卡继续使用原始背景素材")
	select_finish(CardFinishPreview.Finish.HOLOGRAPHIC)
	check(tuner.preview_card.art_background.texture == preview_texture, "切回全息复用背景显示副本")
	tuner.finish_depth_spin.value = 2.5
	point(Vector2(0.9, 0.45))
	var caption := tuner.get_node("CenterContainer/Workspace/PreviewCaption") as Label
	caption.text = "全息 · 透明四角修正"
	var corrected := await capture()
	corrected.save_png("/private/tmp/project-card-holo-corners-corrected.png")
	check(source.get_image().get_data() == original.get_data(), "补角不修改原始背景资源")



func test_badge_relief() -> void:
	tuner.card_data = load(CARD_PATH)
	await process_frame
	select_finish(CardFinishPreview.Finish.EMBOSSED)
	point(Vector2(0.65, -0.35))
	var materials := tuner._finish_preview._badge_materials
	for material: ShaderMaterial in materials.values(): material.set_shader_parameter("relief_enabled", false)
	var flat := await capture_inner()
	for material: ShaderMaterial in materials.values(): material.set_shader_parameter("relief_enabled", true)
	var raised := await capture_inner()
	for badge: TextureRect in materials:
		var origin := badge.get_global_transform_with_canvas() * Vector2.ZERO
		var rect := Rect2i(Vector2i(origin) - Vector2i(12, 12), Vector2i((badge.size + Vector2(6, 6)) * 4.0))
		rect = rect.intersection(Rect2i(Vector2i.ZERO, raised.get_size()))
		var shadow_pixels := 0
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				if raised.get_pixel(x, y).a > flat.get_pixel(x, y).a + 0.02: shadow_pixels += 1
		check(difference(flat, raised, rect) > 10, "图标实际显示法线明暗：" + badge.name)
		# 种族位于不透明卡面内，alpha不会增加；外悬的行动、生命、护甲需有真实投影。
		if badge in [tuner.preview_card.action_icon, tuner.preview_card.health_icon, tuner.preview_card.armor_icon]:
			check(shadow_pixels > 0, "图标轮廓外产生投影：" + badge.name)
	point(Vector2(-0.65, 0.35))
	var reversed := await capture_inner()
	check(difference(raised, reversed, Rect2i(0, 0, raised.get_width(), 180)) > 10, "图标反光和阴影随鼠标方向变化")
	for action: int in range(5):
		var definition := (load(CARD_PATH) as CardData).duplicate() as CardData
		definition.action_type = action as CardData.ActionType
		tuner.card_data = definition
		await process_frame
		await capture()
		var action_image := (materials[tuner.preview_card.action_icon].get_shader_parameter("badge_texture") as Texture2D).get_image()
		check(action_image.get_data() == tuner.preview_card.action_icon.texture.get_image().get_data(), "五种行动分别使用自己的原图生成法线：" + str(action))
	# 检查不同图集来源，确认材质获得的是独立裁切图，而非整个图集。
	for path: String in ["res://resources/cards/field_beer_machine.tres", "res://resources/cards/sentry_pistol.tres", "res://resources/cards/damage_fireball.tres"]:
		tuner.card_data = load(path)
		await process_frame
		for badge: TextureRect in materials:
			if not badge.visible or badge.texture == null: continue
			var extracted := materials[badge].get_shader_parameter("badge_texture") as Texture2D
			check(extracted != null and extracted.get_size() == badge.texture.get_size(), "图标图集裁切尺寸正确：" + badge.name)
