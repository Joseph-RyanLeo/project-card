extends "res://tests/card_foil_pointer_light_test.gd"

const TUNER = preload("res://scripts/tools/card_texture_tuner.gd")
const OUTPUT := "/private/tmp/project-card-film/preview"


func pointer(surface: InspectionCardSurface, value: Vector2) -> void:
	surface.set_process(false)
	surface.effect.set_shader_parameter("use_3d", false)
	surface.set_pointer_force(value)


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("实验闪卡专项超时"); quit(1))
	root.size = Vector2i(1280, 900)
	root.gui_embed_subwindows = true
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	DirAccess.make_dir_recursive_absolute("/private/tmp/project-card-film")
	var shared: Resource = CardFinishPreview.SETTINGS
	var original := shared.duplicate(true)
	var bytes := FileAccess.get_file_as_bytes(Settings.PATH)
	var fixture := Settings.new()
	var path := "/private/tmp/project-card-film/settings.tres"
	check(ResourceSaver.save(fixture, path) == OK, "试验使用隔离配置")
	var tuner := TUNER.new()
	tuner.settings_path = path
	tuner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(tuner)
	await process_frame
	check(tuner.style_selector.item_count == 8 and tuner.tabs.get_tab_count() == 6, "新增两种具名工艺和独立调参页")
	var militia := tuner._paths.find("res://resources/cards/militia.tres")
	tuner.card_selector.select(militia)
	var all_poses := Image.create(540 * 3, 688 * 2, false, Image.FORMAT_RGBA8)
	for index: int in [6, 7]:
		tuner.style_selector.select(index)
		tuner._select_style(index)
		await process_frame
		var kind := index - 5
		var key := "frosted" if kind == 1 else "fingerprint"
		check(tuner.tabs.current_tab == index - 2, "工艺选项与参数页同步")
		check(tuner.previews.all(func(s: InspectionCardSurface): return int(s.card._finish_controller._art_material.get_shader_parameter("film_kind")) == kind and s.render_scale == 4), "三张真实卡牌使用新工艺和4倍合成")
		var surface: InspectionCardSurface = tuner.previews[0]
		var renderer = surface.card._finish_controller
		var pose_images: Array[Image] = []
		for pose: Vector2 in [Vector2(-0.75, -0.3), Vector2.ZERO, Vector2(0.8, 0.35)]:
			pointer(surface, pose)
			pose_images.append(await shot(surface))
		var lit: Image = pose_images[2]
		check(pose_images[0].get_data() != lit.get_data(), "左右检视有不同的实际GPU反光")
		check((await shot(surface)).get_data() == lit.get_data(), "静止纹理不随时间跳动")
		for column: int in 3: all_poses.blit_rect(pose_images[column], Rect2i(Vector2i.ZERO, lit.get_size()), Vector2i(column * 540, (kind - 1) * 688))
		tuner.controls[key + "_strength"].value = 0
		var unlit := await shot(surface)
		var changed := compare(unlit, lit, surface.card, surface)
		check((changed.role_changed == 0 if kind == 1 else changed.role_changed > 500) and changed.background > 50 and changed.frame > 10 and changed.title == 0, "磨砂只处理背景与框，指纹另处理人物，文字均保持原样")
		if kind == 1:
			var white_pixels := 0
			var tinted_pixels := 0
			for y: int in range(30, 80):
				for x: int in [1, 2]:
					var at := Vector2i((Vector2(x, y) + surface.card.position) * surface.render_scale)
					var delta := lit.get_pixelv(at) - unlit.get_pixelv(at)
					if delta.r + delta.g + delta.b < 0.03: continue
					white_pixels += 1
					if absf(delta.r - delta.g) > 0.009 or absf(delta.g - delta.b) > 0.009: tinted_pixels += 1
			check(white_pixels > 10 and tinted_pixels == 0, "磨砂新增的GPU反光为白色")
		tuner.controls[key + "_strength"].value = fixture.get(key + "_strength")
		# 固定鼠标位置，只改变最近有效方向。旧薄膜即使移动光带也过不了此检查。
		pointer(surface, Vector2.ZERO)
		var directions: Array[Image] = []
		for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN]:
			for material: ShaderMaterial in [renderer._art_material, renderer._background_material, renderer._frame_material]:
				material.set_shader_parameter("flash_direction_force", direction)
			directions.append(await shot(surface))
		check(directions[0].get_data() != directions[1].get_data(), "仅转动反光方向就会改变实际薄膜画面")
		tuner.controls[key + "_density"].value = 60
		check((await shot(surface)).get_data() != lit.get_data(), "颗粒／曲纹密度即时改变实际画面")
		tuner.controls[key + "_density"].value = fixture.get(key + "_density")
		# 原生右键事件走预览区回调，放大后仍允许左侧参数刷新。
		var event := InputEventMouseButton.new()
		event.position = surface.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = true
		root.push_input(event, true)
		await process_frame
		await process_frame
		check(is_instance_valid(tuner._inspection), "新工艺右键可以放大检视")
		if is_instance_valid(tuner._inspection):
			var large: InspectionCardSurface = tuner._inspection.get_node("TextureInspectionSurface")
			pointer(large, Vector2(0.8, 0.35))
			var before := await shot(large)
			tuner.controls[key + "_strength"].value = 0.15
			check((await shot(large)).get_data() != before.get_data(), "大卡无需关闭便实时响应左侧参数")
			tuner.controls[key + "_strength"].value = fixture.get(key + "_strength")
			await shot(large)
			(await root.get_texture().get_image()).save_png(OUTPUT.path_join("%02d_%s_inspection.png" % [kind, key]))
			tuner._close_inspection()
		for item: InspectionCardSurface in tuner.previews: pointer(item, Vector2(0.65, -0.35))
		await shot(surface)
		root.get_texture().get_image().save_png(OUTPUT.path_join("%02d_%s_controls.png" % [kind, key]))
	all_poses.save_png(OUTPUT.path_join("03_pointer_comparison.png"))
	tuner.style_selector.select(5)
	tuner._select_style(5)
	await process_frame
	var fractured: InspectionCardSurface = tuner.previews[0]
	pointer(fractured, Vector2(0.65, -0.35))
	check(is_equal_approx(tuner.sliders.fractured_brightness.value, 0.55), "碎闪明度滑块采用降低后的55%默认值")
	tuner.sliders.fractured_brightness.value = 1.0
	var original_brightness := await shot(fractured)
	tuner.sliders.fractured_brightness.value = 0.35
	var reduced_brightness := await shot(fractured)
	var dimmer := 0
	var brighter := 0
	for y: int in range(70, original_brightness.get_height() - 70, 4):
		for x: int in range(70, original_brightness.get_width() - 70, 4):
			var delta := reduced_brightness.get_pixel(x, y) - original_brightness.get_pixel(x, y)
			var difference := delta.r + delta.g + delta.b
			if difference < -0.01: dimmer += 1
			elif difference > 0.01: brighter += 1
	check(dimmer > 100 and brighter == 0, "降低碎闪明度实际减少亮像素，未照亮原本较暗的部分")
	original_brightness.save_png(OUTPUT.path_join("04_fractured_original_brightness.png"))
	reduced_brightness.save_png(OUTPUT.path_join("05_fractured_reduced_brightness.png"))
	# 晶片在合成表面的外层绘制，从窗口截取卡面才能测到颜色。
	var bounds := Rect2i(fractured.get_global_rect())
	tuner.sliders.fractured_saturation.value = 0.0
	await shot(fractured)
	var neutral_shards := root.get_texture().get_image().get_region(bounds)
	tuner.sliders.fractured_saturation.value = 0.85
	await shot(fractured)
	var vivid_shards := root.get_texture().get_image().get_region(bounds)
	check(neutral_shards.get_data() != vivid_shards.get_data(), "饱和度滑块改变晶片颜色")
	tuner.sliders.fractured_hue_degrees.value = 45.0
	await shot(fractured)
	var rotated_shards := root.get_texture().get_image().get_region(bounds)
	check(rotated_shards.get_data() != vivid_shards.get_data(), "色相滑块单独改变晶片颜色")
	# 保存到临时磁盘，再检查已存在和新创建的正式卡面是否同时采用参数。
	var external_card: CardView = CARD.instantiate()
	var owned := OwnedCard.new()
	owned.initialize(load("res://resources/cards/militia.tres"), &"film_shared_probe", 0)
	owned.surface_finish = CardAppearance.Surface.FINGERPRINT
	external_card.set_card_data(owned.card_data)
	external_card.set_owned_card(owned)
	root.add_child(external_card)
	external_card.hide()
	tuner.controls.frosted_strength.value = 0.3
	tuner.controls.fingerprint_strength.value = 0.35
	tuner.controls.fingerprint_angle.value = 28
	check(tuner.save_settings(), "实验参数走现有合并保存流程")
	var saved: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(is_equal_approx(saved.fractured_brightness, 0.35), "碎闪明度随其他参数一起保存并读回")
	check(is_equal_approx(saved.fractured_saturation, 0.85) and saved.fractured_hue_degrees == 45.0, "碎闪饱和度和色相分别保存并读回")
	check(is_equal_approx(saved.frosted_strength, 0.3) and is_equal_approx(saved.fingerprint_strength, 0.35) and saved.fingerprint_angle == 28, "两种工艺的参数真实写盘并读回")
	check(is_equal_approx(external_card._finish_controller._art_material.get_shader_parameter("film_strength"), 0.35), "保存后已存在的正式卡面立即更新")
	var later: CardView = CARD.instantiate()
	later.set_card_data(owned.card_data)
	later.set_owned_card(owned)
	root.add_child(later)
	check(is_equal_approx(later._finish_controller._art_material.get_shader_parameter("film_angle"), 28), "保存后新卡自动读取同一组参数")
	shared.copy_values(original)
	shared.emit_changed()
	external_card.free()
	later.free()
	check(CardAppearance.is_valid(CardAppearance.Surface.FROSTED, 0) and CardAppearance.is_valid(CardAppearance.Surface.FINGERPRINT, 0), "新工艺有稳定有效的实例编号")
	var tickets := []
	for ticket: int in range(1, 101): tickets.append(CardAppearance.pick_ticket(CardAppearance.SURFACE_WEIGHTS, ticket))
	check(tickets.count(0) == 40 and tickets.count(5) == 5 and tickets.count(6) == 0 and tickets.count(7) == 0, "实验工艺不改变现有开包概率")
	check(FileAccess.get_file_as_bytes(Settings.PATH) == bytes, "未覆盖用户全局配置")
	tuner.free()
	await process_frame
	await process_frame
	print("Experimental card films GPU/UI: %d checks, %d failures" % [checks, failures])
	quit.call_deferred(1 if failures else 0)
