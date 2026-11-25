extends SceneTree

const SCENE = preload("res://scenes/tools/CardArtTuner.tscn")
const BATTLE_FURY = preload("res://resources/cards/battle_fury.tres")
const FLAT_CARD = preload("res://resources/cards/ember_squire.tres")
const FIXTURE_PATH := "/private/tmp/project-card-layer-depth-editor.tres"
var checks := 0
var failures := 0
var tuner: CardArtTuner


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _spin(index: int) -> SpinBox:
	return tuner.depth_rows.get_child(index).get_node("DepthValue") as SpinBox


func _click_depth_tab() -> void:
	var tabs := tuner.edit_tabs
	var point := tabs.get_global_transform_with_canvas() * tabs.get_tab_rect(1).get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _run() -> void:
	create_timer(15.0).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280, 720)
	tuner = SCENE.instantiate()
	root.add_child(tuner)
	await process_frame
	tuner.card_data = FLAT_CARD
	_check(tuner.edit_tabs.is_tab_disabled(1) and not tuner.depth_page.visible, "无拆层的卡牌禁用景深页")
	var original_bytes := FileAccess.get_file_as_bytes(BATTLE_FURY.resource_path)
	var fixture := BATTLE_FURY.duplicate() as CardData
	fixture.inspection_art_depths = {}
	_check(ResourceSaver.save(fixture, FIXTURE_PATH) == OK, "独立临时卡牌保存成功")
	var source := ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as CardData
	var original_fixture_bytes := FileAccess.get_file_as_bytes(FIXTURE_PATH)
	tuner.card_data = source
	await _click_depth_tab()
	_check(not tuner.edit_tabs.is_tab_disabled(1) and tuner.depth_page.visible and not tuner.card_field_page.visible, "图层页独立显示，保留卡牌选择")
	_check(tuner.finish_selector.get_selected_id() == CardFinishPreview.Finish.HOLOGRAPHIC and tuner.use_3d_check.button_pressed and tuner.use_flash_check.button_pressed, "打开子页自动启用全息3D预览")
	_check(tuner.depth_rows.get_child_count() == 5 and tuner.depth_rows.get_child(2).get_child(0).text == "头盔", "背景与四层素材各自有名称和控件")
	var viewport_rect := (tuner.depth_rows.get_parent() as ScrollContainer).get_global_rect()
	_check(viewport_rect.encloses(_spin(4).get_global_rect()), "五层素材在720p同屏可见")
	_check(is_equal_approx(_spin(0).value, 2.4) and is_equal_approx(_spin(1).value, 1.62), "没有覆盖值时显示原工艺的默认景深")
	var slider := tuner.depth_rows.get_child(1).get_child(1) as HSlider
	slider.value = 2.10
	await process_frame
	await process_frame
	var finish := tuner._finish_preview
	var base := -CardFinishPreview.SETTINGS.holographic_depth * CardFinishPreview.DEPTH_DISTANCE_SCALE
	_check(is_equal_approx(_spin(1).value, 2.1) and is_equal_approx(finish._art_planes[0].material.get_shader_parameter("layer_depth"), base * 2.1), "滑杆、数字框及该图层的真实预览材质同步")
	_check(is_equal_approx(finish._art_planes[1].material.get_shader_parameter("layer_depth"), base * source.get_default_inspection_layer_depth(2)), "调一个图层时其余投影深度不变")
	_check(source.inspection_art_depths.is_empty() and FileAccess.get_file_as_bytes(FIXTURE_PATH) == original_fixture_bytes, "草稿不污染共享资源或磁盘")
	tuner.card_data = FLAT_CARD
	_check(tuner.edit_tabs.current_tab == 0 and not tuner.depth_page.visible, "切到平面卡回到资料页")
	tuner.card_data = source
	tuner.edit_tabs.current_tab = 1
	_check(is_equal_approx(_spin(1).value, 2.1), "切回原卡保留尚未保存的数值")
	var background_key := source.get_inspection_layer_key(0)
	var edited_key := source.get_inspection_layer_key(1)
	var external := ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as CardData
	external.inspection_art_depths[background_key] = 2.8
	ResourceSaver.save(external, FIXTURE_PATH)
	tuner.save_button.pressed.emit()
	var saved := ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as CardData
	_check(is_equal_approx(saved.inspection_art_depths[edited_key], 2.1) and is_equal_approx(saved.inspection_art_depths[background_key], 2.8), "保存合并当前图层编辑和磁盘上其他图层的新数值")
	_check(is_equal_approx(_spin(0).value, 2.8) and is_equal_approx(finish._background_material.get_shader_parameter("layer_depth"), base * 2.8), "保存后从正式值刷新背景控件和材质")
	tuner.reset_layer_depths_button.pressed.emit()
	_check(is_equal_approx(_spin(1).value, 1.62) and tuner._has_unsaved_changes(source), "恢复默认只改草稿")
	tuner.reload_button.pressed.emit()
	_check(is_equal_approx(_spin(1).value, 2.1) and not tuner._has_unsaved_changes(source), "重新载入可放弃默认值草稿")
	tuner.reset_layer_depths_button.pressed.emit()
	tuner.save_button.pressed.emit()
	saved = ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(saved.inspection_art_depths.is_empty(), "保存默认值删除图层倍率覆盖")
	_check(FileAccess.get_file_as_bytes(BATTLE_FURY.resource_path) == original_bytes, "正式法术资源未被测试写入")
	if "--capture" in OS.get_cmdline_user_args():
		tuner.search_input.text = "战斗怒火"
		tuner.search_input.text_changed.emit(tuner.search_input.text)
		await process_frame
		tuner.set_process(false)
		tuner._preview_effect_material.set_shader_parameter("pointer_force", Vector2(0.65, -0.45))
		finish.update_pointer(Vector2(0.65, -0.45))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-layer-depth-panel.png")
	tuner.queue_free()
	await process_frame
	DirAccess.remove_absolute(FIXTURE_PATH)
	print("卡面图层景深：%d项断言，%d失败" % [checks, failures])
	quit(1 if failures else 0)
