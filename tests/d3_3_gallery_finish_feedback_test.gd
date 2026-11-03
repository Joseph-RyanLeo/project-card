extends "res://tests/d3_3_gallery_test.gd"

const FEEDBACK_DIR := "/private/tmp/project-card-gallery-finish-feedback"
const PREVIEW_DIR := "res://docs/previews/d3_3_finish_feedback_20261103"
const SETTINGS_SCRIPT = preload("res://scripts/ui/card_finish_settings.gd")
const SETTINGS_PATH := FEEDBACK_DIR + "/card_finish_settings.tres"
const TUNER = preload("res://scenes/tools/CardArtTuner.tscn")

func capture_feedback(title: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIR))
	root.get_texture().get_image().save_png(PREVIEW_DIR.path_join(title + ".png"))

func choose_finish(tuner: CardArtTuner, index: int) -> void:
	tuner.finish_selector.select(index)
	tuner.finish_selector.item_selected.emit(index)
	await frames()

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("图鉴与碎闪反馈验证超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(FEEDBACK_DIR)
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	var project_settings := FileAccess.get_file_as_bytes(SETTINGS_SCRIPT.PATH)
	var edited_card := FileAccess.get_file_as_bytes("res://resources/cards/ember_squire.tres")
	check(CardFinishPreview.SETTINGS.fractured_density == 15.0, "项目碎闪纹理已经设为15")
	shell = SHELL.instantiate()
	shell.run_slots.directory = FEEDBACK_DIR
	shell.run_slots.delete_slot(0)
	var progress := fixture(Catalog.new())
	save_fixture(0, progress)
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_720P)
	await frames()
	check(await shell.start_slot(0), "从隔离存档打开真实大厅")
	await click(button("GalleryButton"))
	while shell.screen_transition.busy: await process_frame
	await frames()
	var gallery = shell._gallery_panel
	var id: String = gallery.shown_cards[0].id
	var base: CardView = gallery.views[id + ":base"]
	var state: Dictionary = shell.slot_progress.capture_state()
	# 先碰没有OwnedCard的基础图鉴，覆盖从未显示过特殊卡的共享画布初始化路径。
	await motion(base.get_global_rect().position + base.card_size * Vector2(0.8, 0.25))
	await create_timer(0.3).timeout
	var hover = shell.get_collection_hover_surface()
	check(hover.source == base and hover.card.get_owned_card() == null and hover.force.length() > 0.2, "基础图鉴仍透视倾斜，不创建拥有实例")
	check(hover.effect.get_shader_parameter("use_flash") == false and hover.effect.get_shader_parameter("use_fractured") == false, "第一次悬停基础图鉴就关闭扫光与碎闪")
	check(hover.card._finish_controller.surface_finish == CardAppearance.Surface.PLAIN and hover.card._finish_controller.art_finish == CardAppearance.Art.PLAIN, "基础图鉴材质明确重置为普通卡面和普通卡图")
	for material: ShaderMaterial in hover.card._finish_controller._badge_materials.values(): check(material.get_shader_parameter("relief_enabled") == false, "普通基础卡没有图标浮雕光泽")
	if DisplayServer.get_name() != "headless":
		hover.set_process(false)
		hover.set_pointer_force(Vector2(0.7, -0.4))
		await RenderingServer.frame_post_draw
		var plain: Image = hover.viewport.get_texture().get_image()
		# 同一张合成纹理交给相同投影，故意开启旧金光作为GPU反例。
		var shader: ShaderMaterial = hover.effect
		shader.set_shader_parameter("use_flash", true)
		await capture_feedback("01_old_flash_counterexample")
		var old: Image = root.get_texture().get_image()
		shader.set_shader_parameter("use_flash", false)
		await capture_feedback("02_plain_base_fixed")
		var fixed: Image = root.get_texture().get_image()
		check(old.get_data() != fixed.get_data() and plain.get_data() == hover.viewport.get_texture().get_image().get_data(), "真实GPU确认区别来自外层错误扫光，卡内像素内容未变")
		hover.set_process(true)
	await motion(gallery.views[id + ":3"].get_global_rect().get_center())
	await create_timer(0.25).timeout
	check(hover.effect.get_shader_parameter("use_flash") == true, "真实金闪收藏仍保持扫光")
	await motion(base.get_global_rect().get_center())
	await create_timer(0.25).timeout
	check(hover.effect.get_shader_parameter("use_flash") == false and hover.effect.get_shader_parameter("use_fractured") == false, "特殊收藏切回基础图鉴时不残留材质")
	await click(base, MOUSE_BUTTON_RIGHT)
	await create_timer(0.8).timeout
	var surface: InspectionCardSurface = gallery._inspection.get_node("CollectionInspectionSurface")
	check(surface.effect.get_shader_parameter("use_flash") == false and surface.card.get_owned_card() == null, "新建4倍基础图鉴检视同样是普通材质")
	await capture_feedback("03_plain_base_inspection")
	await key(KEY_ESCAPE)
	await wait_inspection_closed(gallery)
	check(shell.slot_progress.capture_state() == state, "检查与检视不改变发现和收藏")
	shell._close_gallery()
	shell.hide()
	var settings := SETTINGS_SCRIPT.new()
	settings.fractured_density = 32
	check(ResourceSaver.save(settings, SETTINGS_PATH) == OK, "建立原纹理32的隔离工艺文件")
	var tuner := TUNER.instantiate() as CardArtTuner
	tuner.finish_settings_path = SETTINGS_PATH
	root.add_child(tuner)
	await frames()
	tuner.card_data = load("res://resources/cards/anvil_margaret.tres")
	for action: Button in [tuner.save_finish_button, tuner.reload_finish_button]:
		check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(action.get_global_rect()), "工艺保存入口在720p画布内")
		for control: Control in [tuner.use_3d_check, tuner.use_flash_check, tuner.finish_selector, tuner.flash_type_selector, tuner.save_button]:
			check(not action.get_global_rect().intersects(control.get_global_rect()), "全局工艺按钮不遮挡原材质／卡牌控件")
	await choose_finish(tuner, CardFinishPreview.Finish.FRACTURED)
	check(tuner.finish_density_spin.value == 32, "调整器读取保存的工艺值，不只读取场景默认值")
	tuner.finish_density_spin.value = 15
	check(tuner._preview_effect_material.get_shader_parameter("finish_density") == 15 and tuner._has_finish_changes() and not tuner.save_finish_button.disabled, "碎闪纹理15立即预览，并明确标记尚未保存")
	await choose_finish(tuner, CardFinishPreview.Finish.HOLOGRAPHIC)
	check(tuner.finish_density_spin.value == 32, "全息和碎闪的纹理值分别保留，不互相串改")
	tuner.finish_strength_spin.value = 0.9
	await choose_finish(tuner, CardFinishPreview.Finish.FRACTURED)
	check(tuner.finish_density_spin.value == 15, "切换工艺后碎闪草稿仍为15")
	var latest := ResourceLoader.load(SETTINGS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	latest.embossed_density = 47
	check(ResourceSaver.save(latest, SETTINGS_PATH) == OK, "另一个工艺的磁盘修改作为真实合并检查")
	await click(tuner.save_finish_button)
	var saved := ResourceLoader.load(SETTINGS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(saved.fractured_density == 15 and is_equal_approx(saved.holographic_strength, 0.9) and saved.embossed_density == 47, "真实保存按钮写入改动工艺，同时保留其他工艺的磁盘值")
	check(not tuner._has_finish_changes() and tuner.status_label.text.contains("已保存全局工艺参数"), "保存成功才清除工艺脏标记并提示成功")
	await capture_feedback("04_fractured_saved")
	tuner.finish_density_spin.value = 23
	await click(tuner.reload_finish_button)
	check(tuner.finish_density_spin.value == 15 and not tuner._has_finish_changes(), "重载工艺配置放弃未保存的23，恢复真实磁盘15")
	tuner.free()
	tuner = TUNER.instantiate() as CardArtTuner
	tuner.finish_settings_path = SETTINGS_PATH
	root.add_child(tuner)
	await frames()
	await choose_finish(tuner, CardFinishPreview.Finish.FRACTURED)
	check(tuner.finish_density_spin.value == 15, "重新创建开发工具仍读回15")
	# 真实OwnedCard不经过调整器，直接检查正式CardView→InspectionCardSurface链路。
	var owned := OwnedCardCollection.new().create_card(load("res://resources/cards/militia.tres"))
	owned.surface_finish = CardAppearance.Surface.FRACTURED
	owned.art_finish = CardAppearance.Art.HOLOGRAPHIC
	var view := (load("res://scenes/ui/CardView.tscn") as PackedScene).instantiate() as CardView
	view.set_snapshot_mode(true)
	view.set_card_data(owned.card_data)
	view.set_owned_card(owned)
	root.add_child(view)
	var actual := InspectionCardSurface.new()
	root.add_child(actual)
	actual.setup(view, Callable(), Callable())
	check(actual.effect.get_shader_parameter("use_fractured") == true and actual.effect.get_shader_parameter("finish_density") == 15, "实际碎闪卡读取项目全局纹理15")
	check(view._finish_controller._art_material.get_shader_parameter("texture_density") == 32, "碎闪与全息组合时，两维纹理密度互不覆盖")
	actual.free()
	tuner.free()
	check(FileAccess.get_file_as_bytes(SETTINGS_SCRIPT.PATH) == project_settings and FileAccess.get_file_as_bytes("res://resources/cards/ember_squire.tres") == edited_card, "所有保存测试隔离，项目设置与用户原有余烬侍从改动未被测试改写")
	shell.free()
	await frames()
	print("Gallery finish feedback checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
