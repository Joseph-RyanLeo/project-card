extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
const MainScript := preload("res://scripts/main.gd")
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main := MAIN.instantiate() as MainScript
	main.short_maze_enabled = true
	main.run_save_path = "/private/tmp/project-card-console-preview-save.json"
	root.add_child(main)
	await process_frame
	await process_frame
	var console := main._developer_console as DeveloperConsole
	console.set_open(true)
	var maze := main.maze_controller
	var rng_state := maze.run.rng.state
	var cards := main.owned_card_collection.capture_state()
	var paths := maze.run.paths.duplicate(true)
	_search(console._event_query, "suspicious_merchant")
	var details := console._event_details.get_parsed_text()
	_check("巨大行囊" in details and "买吧（金币-20）" in details, "剧情事件显示开场和选项")
	_check("1d6=6" in details and "镀金委托卡包" in details, "剧情事件显示点数和对应奖励")
	await process_frame
	_check(console._event_details.get_content_height() > console._event_details.size.y and console._event_details.scroll_active, "长事件详情在独立区域滚动")
	_check(console.get_global_rect().encloses(console._stop.get_global_rect()), "事件详情不会挤出右侧测试操作")
	await _capture("events")
	_search(console._event_query, "vital_training")
	details = console._event_details.get_parsed_text()
	_check("免费：+2生命" in details and "8金币" in details, "强化事件显示免费和付费选项")
	_search(console._event_query, "loose_coins")
	_check("获得3金币" in console._event_details.get_parsed_text(), "简单奖励事件显示实际奖励")
	_search(console._event_query, "not_found")
	_check(console._deal.disabled and "没有匹配" in console._event_details.get_parsed_text(), "事件搜索无结果时清掉旧详情")
	console._tabs.current_tab = 1
	_search(console._data_query, "anvil_margaret")
	await process_frame
	var preview := console._card_preview
	_check(is_instance_valid(preview) and preview.card.card_data.id == &"anvil_margaret", "使用所选真实卡牌创建示例")
	var owned := preview.card.get_owned_card()
	_select(console._surface, CardAppearance.Surface.FROSTED)
	_select(console._art, CardAppearance.Art.OVERFRAME)
	_check(preview.card.get_owned_card() == owned and owned.surface_finish == CardAppearance.Surface.FROSTED and owned.art_finish == CardAppearance.Art.OVERFRAME, "双下拉框即时更新同一张卡面")
	_check("磨砂闪／超框" in console._card_preview_caption.text and preview.card._finish_controller.surface_finish == CardAppearance.Surface.FROSTED, "预览标题和正式工艺渲染同步")
	_check(console.get_global_rect().encloses(preview.get_global_rect()) and preview.scale == Vector2.ONE * console.CARD_PREVIEW_SCALE, "卡面按示例倍率完整显示在面板内")
	await _capture("cards")
	if DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args():
		_check(preview.viewport.get_texture().get_image().get_used_rect().has_area(), "预览子视口实际绘制卡面")
	_search(console._data_query, "militia")
	_check(preview.card.card_data.id == &"militia" and preview.card.get_owned_card().art_finish == CardAppearance.Art.OVERFRAME, "切换卡牌保留已选外观")
	_search(console._data_query, "not_found")
	_check(not preview.visible and console._add.disabled, "无结果时清掉旧卡面")
	_select(console._data_kind, 1)
	_search(console._data_query, "")
	_check(not console._add.disabled and not console._card_preview_column.visible, "选中贴纸后仍可添加，但不显示卡面示例")
	await _check_spell_light(console, main)
	_check(maze.run.rng.state == rng_state and main.owned_card_collection.capture_state() == cards and maze.run.paths == paths, "详情和预览不改变收藏、正式随机流或事件")
	_check_tutorial_manual_card(console, main)
	root.remove_child(main)
	main.free()
	print("Developer console previews: %d failures" % failures)
	quit(failures)


func _check_tutorial_manual_card(console: DeveloperConsole, main: MainScript) -> void:
	main.profile_progress.run.tasks["main"] = {"id": "tutorial", "progress": {}, "completed": false}
	main._bind_profile_collection()
	var collection := main.owned_card_collection
	var pick := preload("res://resources/cards/ghost_pick.tres") as CardData
	_check(collection.create_card(pick) == null, "营救铁匠教程的常规卡牌获取仍过滤开采装备")
	console._tabs.current_tab = 1
	_select(console._data_kind, 0)
	_search(console._data_query, "幽魂矿镐")
	console._add.pressed.emit()
	var owned := collection.find_first_by_definition(pick)
	_check(owned != null and collection.exclude_resource_related_cards and "已加入真实收藏并保存" in console._feedback.text, "F2 可在营救铁匠教程中手动加入并保存幽魂矿镐")
	var saved := main.run_save_service.load_checkpoint(main.run_save_path)
	var saved_cards: Array = saved.get("checkpoint", {}).get("collection", {}).get("cards", [])
	_check(saved_cards.any(func(card: Dictionary) -> bool: return card.card_id == "ghost_pick"), "教程存档包含 F2 加入的幽魂矿镐实例")
	var count := collection.size()
	main._on_developer_console_command_submitted("card add ghost_pick")
	_check(collection.size() == count, "F2 手动添加仍遵守幽魂矿镐的唯一持有限制")


func _check_spell_light(console: DeveloperConsole, main: MainScript) -> void:
	console.open_spell_light_preview()
	var settings := main.spell_header_light_settings
	settings.reset_defaults()
	await create_timer(0.20).timeout
	var tray := console._spell_light_tray
	var preview_material: ShaderMaterial = tray._header_materials[0]
	_check(console.visible and tray.is_visible_in_tree() and console.get_global_rect().encloses(tray.get_global_rect()), "法术光效入口打开完整的令牌准备栏预览")
	_check(is_equal_approx(preview_material.get_shader_parameter("brightness_gain"), 0.75), "默认提亮保留原光效增幅")
	console._spell_light_controls["brightness"].value = 30.0
	var saturation_entry := console._spell_light_controls["saturation"].get_parent().get_child(2) as SpinBox
	saturation_entry.value = 25.0
	console._spell_light_controls["release_strength"].value = 150.0
	console._spell_light_controls["fade_seconds"].value = 0.65
	for target: Control in [tray, main.spell_preparation_tray, main.enemy_spell_preparation_tray]:
		for material: ShaderMaterial in target._header_materials:
			_check(
				is_equal_approx(material.get_shader_parameter("brightness_gain"), 1.20)
				and is_equal_approx(material.get_shader_parameter("saturation_gain"), 1.0)
				and is_equal_approx(material.get_shader_parameter("release_strength"), 1.5),
				"滑条和手动数值同步更新预览及双方准备栏"
			)
	console._spell_light_add.pressed.emit()
	await create_timer(0.22).timeout
	_check(tray._header_token_counts == [2, 2, 3] and is_equal_approx(preview_material.get_shader_parameter("charge"), 0.4), "放入测试令牌增加且只增加选中列的光效")
	console._spell_light_release.pressed.emit()
	await create_timer(0.64).timeout
	_check(tray._header_token_counts == [1, 2, 3] and float(preview_material.get_shader_parameter("release_glow")) > 0.0, "释放消耗一枚测试令牌并使用延长后的淡出")
	await create_timer(0.54).timeout
	_check(preview_material.get_shader_parameter("release_glow") == 0.0, "释放光效按所设时长淡出")
	console._spell_light_remove.pressed.emit()
	_check(tray._header_token_counts == [0, 2, 3] and console._spell_light_release.disabled, "移走最后一枚令牌后不可继续释放")
	var path := "/private/tmp/project-card-spell-light-settings-test.cfg"
	var reloaded := SpellHeaderLightSettings.new()
	_check(settings.save(path) == OK, "开发面板参数可单独保存")
	reloaded.load_saved(path)
	_check(is_equal_approx(reloaded.get_value("fade_seconds"), 0.65) and reloaded.get_value("brightness") == 30.0, "保存的法术光效参数可在启动时重载")
	DirAccess.remove_absolute(path)
	console._reset_spell_light_settings()
	_check(is_equal_approx(saturation_entry.value, 15.0) and is_equal_approx(settings.get_value("fade_seconds"), 0.20), "恢复默认同步滑条和数字输入")
	await _capture("spell-light")


func _search(field: LineEdit, query: String) -> void:
	field.text = query
	field.text_changed.emit(query)


func _select(choice: OptionButton, index: int) -> void:
	choice.select(index)
	choice.item_selected.emit(index)


func _capture(page: String) -> void:
	if DisplayServer.get_name() == "headless" or "--capture" not in OS.get_cmdline_user_args(): return
	await create_timer(0.12).timeout
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("/private/tmp/project-card-console-preview-" + page + ".png") == OK, "截图：" + page)


func _check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error("FAIL: " + message)
