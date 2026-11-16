extends "res://tests/d3_4_ui_test.gd"

## 真实菜单、滑块、卡面、磁盘合并保存；测试只写临时资源。
const DISPLAY = preload("res://scenes/GameDisplay.tscn")
const Settings = preload("res://scripts/ui/card_finish_settings.gd")
const Renderer = preload("res://scripts/ui/card_finish_preview.gd")
const Appearance = preload("res://scripts/data/card_appearance.gd")
const CARD = preload("res://scenes/ui/CardView.tscn")
const TEMP := "/private/tmp/project-card-texture-tuner"
var main


func snapshot() -> Image:
	await frames()
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func difference(a: Image, b: Image) -> int:
	var count := 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			var delta := a.get_pixel(x, y) - b.get_pixel(x, y)
			if absf(delta.r) + absf(delta.g) + absf(delta.b) > 0.03: count += 1
	return count


func right_click(control: Control) -> void:
	await click_at(control.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)


func click_at(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var at: Vector2 = shell.render_container.get_global_transform_with_canvas() * point
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await frames()


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("卡牌纹理调整器专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(TEMP)
	root.gui_embed_subwindows = true
	var shared: Resource = Renderer.SETTINGS
	var original := shared.duplicate(true)
	var resource_bytes := FileAccess.get_file_as_bytes(Settings.PATH)
	var card_bytes := FileAccess.get_file_as_bytes("res://resources/cards/militia.tres")
	var settings_path := TEMP.path_join("settings.tres")
	var fixture := Settings.new()
	fixture.foil_matte_strength = 0.9
	fixture.foil_matte_grain_size = 4
	fixture.foil_matte_density = 0.35
	check(ResourceSaver.save(fixture, settings_path) == OK, "建立保留旧磨砂值的隔离全局纹理资源")
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = TEMP.path_join("run.json")
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.6).timeout
	var rng_state: int = main.ordinary_shop_service.rng.state
	var card_count: int = main.owned_card_collection.size()
	main._escape_pause_menu.open_menu()
	await frames()
	await click_control(main._escape_pause_menu.find_child("DeveloperToolsButton", true, false))
	var entry: Button = main._escape_pause_menu.find_child("CardTextureTunerButton", true, false)
	check(entry != null and entry.is_visible_in_tree() and Rect2(0, 0, 1280, 720).encloses(entry.get_global_rect()), "独立纹理入口完整位于Esc开发工具页")
	await click_control(entry)
	while shell.screen_transition.busy: await process_frame
	var tuner: Control = shell._card_texture_tuner
	check(tuner != null and not main.visible and shell.is_card_texture_tuner_open(), "实际菜单打开独立调整器并隐藏原场景")
	if tuner == null: quit(1); return
	tuner.settings_path = settings_path
	tuner.reload_settings()
	await frames()
	check(tuner.controls.size() == Settings.FIELDS.size() and not tuner.controls.has("foil_matte_strength") and not tuner.controls.has("foil_matte_grain_size") and not tuner.controls.has("foil_matte_density") and tuner.previews.size() == 3 and not tuner.has_changes(), "所有全局参数与三张不同卡牌预览正常初始化")
	check(Rect2(0, 0, 1280, 720).encloses(tuner.save_button.get_global_rect()) and tuner.save_button.disabled, "保存按钮在画布内，初始没有伪造脏状态")
	for surface: InspectionCardSurface in tuner.previews:
		surface.set_process(false)
		surface.set_pointer_force(Vector2(0.6, -0.3))
	var probe_holder := Control.new()
	probe_holder.hide()
	root.add_child(probe_holder)
	var probes: Array[InspectionCardSurface] = []
	var types: Array[int] = []
	for path: String in tuner._paths:
		var definition: CardData = load(path)
		if definition.card_type in types: continue
		types.append(definition.card_type)
		var owned := OwnedCard.new()
		owned.initialize(definition, StringName("global_texture_probe_%d" % definition.card_type), 0)
		owned.surface_finish = Appearance.Surface.GOLD
		owned.art_finish = Appearance.Art.HOLOGRAPHIC
		var card: CardView = CARD.instantiate()
		card.set_card_data(definition)
		card.set_owned_card(owned)
		probe_holder.add_child(card)
		var surface := InspectionCardSurface.new()
		probe_holder.add_child(surface)
		surface.setup(card, Callable(), Callable())
		surface.set_process(false)
		probes.append(surface)
		if types.size() == 4: break
	check(types.size() == 4, "随从、物品、法术、资源均创建真实卡面探针")
	var before := await snapshot()
	tuner.sliders.stripe_spacing.value = 25
	tuner.controls.flash_offset.value = 0.25
	tuner.controls.stripe_width.value = 5
	tuner.controls.flash_intensity.value = 0.4
	tuner.controls.holographic_density.value = 47
	check(tuner.has_changes() and not tuner.save_button.disabled and tuner.controls.stripe_spacing.value == 25, "滑块与数值框同步，全部修改保留在同一份草稿")
	var draft_before: Resource = tuner.draft
	for index: int in tuner.previews.size():
		var source: InspectionCardSurface = tuner.previews[index]
		await right_click(source)
		var inspection: CardInspectionOverlay = tuner._inspection
		check(is_instance_valid(inspection) and shell.is_card_texture_tuner_open(), "三张预览各自能通过真实右键打开检视")
		if inspection == null: quit(1); return
		var large: InspectionCardSurface = inspection.get_node("TextureInspectionSurface")
		check(large.card.card_data == source.card.card_data and large.card.get_owned_card() == source.card.get_owned_card() and large.scale == Vector2(4, 4), "大卡保留所点卡牌和工艺，使用4倍正式检视表面")
		check(large.card._finish_controller.settings_source == draft_before and large.effect.get_shader_parameter("stripe_spacing") == 25 and large.effect.get_shader_parameter("flash_offset") == 0.25, "检视读取当前未保存草稿，不退回已保存纹理")
		check(Rect2(0, 0, 1280, 720).encloses(large.get_global_rect()), "放大卡面完整落在逻辑画布内")
		if index == 0:
			var at: Vector2 = shell.render_container.get_global_transform_with_canvas() * (large.global_position + large.size * large.scale * Vector2(0.2, 0.35))
			var move := InputEventMouseMotion.new()
			move.position = at
			move.global_position = at
			root.grab_focus()
			Input.warp_mouse(at)
			root.push_input(move, true)
			await create_timer(0.4).timeout
			check(large.force.length() > 0.3, "放大检视实际响应鼠标移动并改变反光方向")
			large.set_process(false)
			var before_live := await snapshot()
			var slider: HSlider = tuner.sliders.stripe_spacing
			await click_at(slider.get_global_rect().position + slider.size * Vector2(0.8, 0.5))
			check(tuner._inspection == inspection and tuner.draft.stripe_spacing > 30 and large.effect.get_shader_parameter("stripe_spacing") == tuner.draft.stripe_spacing, "放大时真实点击左侧滑块立即更新大卡，并保持检视打开")
			tuner.controls.flash_offset.value = 0.6
			check(large.card._finish_controller._background_material.get_shader_parameter("flash_offset") == 0.6 and large.card._finish_controller._frame_material.get_shader_parameter("flash_offset") == 0.6, "数值框修改实时同步大卡背景与卡框")
			var after_live := await snapshot()
			var large_rect := Rect2i(shell.render_container.get_global_transform_with_canvas() * large.get_global_rect())
			check(difference(before_live.get_region(large_rect), after_live.get_region(large_rect)) > 500, "真实GPU确认大卡纹路随调参实时改变")
			var scroll: ScrollContainer = tuner.sliders.foil_shade_strength.get_parent().get_parent().get_parent()
			scroll.scroll_vertical = 10000
			await frames()
			for field: String in ["foil_shade_strength"]:
				var live_slider: HSlider = tuner.sliders[field]
				var previous: float = tuner.draft.get(field)
				await click_at(live_slider.get_global_rect().position + live_slider.size * Vector2(0.4, 0.5))
				var material: ShaderMaterial = large.card._finish_controller._art_material
				check(tuner._inspection == inspection and not is_equal_approx(tuner.draft.get(field), previous) and is_equal_approx(material.get_shader_parameter(field), tuner.draft.get(field)), "滚动左侧并真实点击新增参数时，大卡实时更新：" + field)
			# 最终保留一组改动，继续覆盖关闭／保存／重载的同一真实流程。
			tuner.controls.foil_shade_strength.value = 0.65
			tuner.controls.stripe_spacing.value = 25
			tuner.controls.flash_offset.value = 0.25
			(await snapshot()).save_png("/private/tmp/project-card-texture-inspection.png")
			await right_click(large)
		elif index == 1: await key_escape()
		else: await click_control(inspection.get_node("CloseTextureInspection"))
		check(tuner._inspection == null and shell.is_card_texture_tuner_open() and tuner.draft == draft_before and tuner.has_changes() and tuner.controls.flash_offset.value == 0.25, "右键、Esc或关闭按钮只退出检视，草稿和调整器继续保留")
	for surface: InspectionCardSurface in tuner.previews:
		check(surface.effect.get_shader_parameter("stripe_spacing") == 25 and surface.effect.get_shader_parameter("flash_offset") == 0.25, "密度与位置实时应用于预览")
	for surface: InspectionCardSurface in probes:
		check(surface.effect.get_shader_parameter("stripe_spacing") == original.stripe_spacing, "保存前未修改真实卡面的全局参数")
	var after := await snapshot()
	var physical: Rect2 = shell.render_container.get_global_transform_with_canvas() * (tuner.previews[0].get_global_transform_with_canvas() * Rect2(Vector2.ZERO, tuner.previews[0].size))
	check(difference(before.get_region(Rect2i(physical)), after.get_region(Rect2i(physical))) > 500, "GPU预览实际改变闪纹，不只是更新数值控件")
	# 单独改变相位，不能靠同时调亮度／密度通过位置检查。
	var positioned := after.get_region(Rect2i(physical))
	tuner.controls.flash_offset.value = 0.5
	after = await snapshot()
	check(difference(positioned, after.get_region(Rect2i(physical))) > 500, "单独移动闪纹位置也能实际平移光带")
	tuner.controls.flash_offset.value = 0.25
	var latest := ResourceLoader.load(settings_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	latest.embossed_density = 56
	check(ResourceSaver.save(latest, settings_path) == OK, "模拟另一个工艺的实际磁盘修改")
	await click_control(tuner.save_button)
	var saved := ResourceLoader.load(settings_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(saved.stripe_spacing == 25 and saved.flash_offset == 0.25 and saved.holographic_density == 47 and saved.embossed_density == 56 and is_equal_approx(saved.foil_matte_strength, 0.9) and is_equal_approx(saved.foil_matte_grain_size, 4) and is_equal_approx(saved.foil_matte_density, 0.35) and is_equal_approx(saved.foil_shade_strength, 0.65), "保存更新明暗设置，保留旧磨砂值与其他未编辑工艺的外部改动")
	check(not tuner.has_changes() and tuner.status_label.text.contains("全体卡牌"), "保存成功后才清除草稿脏标记")
	for surface: InspectionCardSurface in probes:
		check(surface.effect.get_shader_parameter("stripe_spacing") == 25 and surface.effect.get_shader_parameter("flash_offset") == 0.25 and surface.card._finish_controller._art_material.get_shader_parameter("texture_density") == 47, "已有真实卡面及全息组合收到全局变更信号")
	# 新建卡面不经过调整器，也必须读取刚发布的共享参数。
	var next_owned := OwnedCard.new()
	next_owned.initialize(load("res://resources/cards/militia.tres"), &"new_texture_probe", 0)
	next_owned.surface_finish = Appearance.Surface.SILVER
	var next_card: CardView = CARD.instantiate()
	next_card.set_card_data(next_owned.card_data)
	next_card.set_owned_card(next_owned)
	probe_holder.add_child(next_card)
	check(next_card._finish_controller._frame_material.get_shader_parameter("flash_offset") == 0.25 and next_card._finish_controller._frame_material.get_shader_parameter("stripe_spacing") == 25, "后创建的收藏静置卡同样读取全局参数")
	tuner.controls.stripe_spacing.value = 39
	await click_control(tuner.reload_button)
	check(tuner.controls.stripe_spacing.value == 25 and is_equal_approx(tuner.controls.foil_shade_strength.value, 0.65) and not tuner.has_changes(), "重载丢弃未保存草稿并恢复明暗设置")
	var normal_path: String = tuner.settings_path
	tuner.controls.flash_offset.value = 0.4
	tuner.settings_path = TEMP.path_join("missing/settings.tres")
	var failed_save: bool = tuner.save_settings()
	check(not failed_save and tuner.has_changes() and shared.flash_offset == 0.25, "保存失败保留草稿，不向正式卡面发布失败改动")
	tuner.settings_path = normal_path
	tuner.reload_settings()
	var directory := "res://docs/previews/card_texture_tuner_20261106"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	(await snapshot()).save_png(directory.path_join("01_foil_global_controls.png"))
	tuner.style_selector.select(5)
	tuner.style_selector.item_selected.emit(5)
	await frames()
	check(tuner.tabs.current_tab == 3 and tuner.previews.all(func(surface: InspectionCardSurface): return bool(surface.effect.get_shader_parameter("use_fractured"))), "切换碎闪同时切到对应全局参数组")
	tuner.controls.fractured_density.value = 22
	check(tuner.previews.all(func(surface: InspectionCardSurface): return surface.effect.get_shader_parameter("finish_density") == 22), "三张不同卡牌同时预览碎闪纹理")
	(await snapshot()).save_png(directory.path_join("02_fractured_global_controls.png"))
	await key_escape()
	while shell.screen_transition.busy: await process_frame
	check(not shell.is_card_texture_tuner_open() and main.visible and shared.fractured_density == saved.fractured_density, "Esc返回并丢弃未保存纹理，不改变正式场景")
	check(main.ordinary_shop_service.rng.state == rng_state and main.owned_card_collection.size() == card_count, "预览、保存及退出不消费玩法随机流或添加卡牌")
	check(FileAccess.get_file_as_bytes(Settings.PATH) == resource_bytes and FileAccess.get_file_as_bytes("res://resources/cards/militia.tres") == card_bytes, "专项所有写盘均隔离，正式纹理与卡牌资料未被测试改写")
	shared.copy_values(original)
	shared.emit_changed()
	probe_holder.free()
	shell.free()
	print("Card texture tuner: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
