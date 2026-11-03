extends "res://tests/d3_3_gallery_book_test.gd"

const REFERENCE_DIR := "/private/tmp/project-card-reference-book"
const REFERENCE_PREVIEWS := "res://docs/previews/d3_3_reference_20261103"

func capture_reference(title: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await motion(Vector2(30, 110))
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REFERENCE_PREVIEWS))
	root.get_texture().get_image().save_png(REFERENCE_PREVIEWS.path_join(title + ("_2k" if "2k" in OS.get_cmdline_user_args() else "_720p") + ".png"))

func select_section(gallery: Control, index: int) -> void:
	var rect: Rect2 = gallery._sections.get_tab_rect(index)
	var pos: Vector2 = gallery._sections.global_position + rect.get_center()
	await motion(pos)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = shell.render_container.get_global_transform() * pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await frames()
	check(gallery._sections.current_tab == index, "鼠标真实切换图鉴入口%d" % index)

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("资源贴纸预览验证超时"); quit(1))
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	var catalog := Catalog.new()
	var fresh := ProfileProgress.new()
	check(catalog.count_total() == 130 and catalog.resources.size() == 11 and catalog.stickers.size() == 70, "三个正式目录分别130张可收藏卡、11种资源、70种贴纸")
	check(catalog.visible_resources(fresh.profile).is_empty(), "未开放资源卡包没有占位")
	fresh.profile.unlocks.packs = ["twisted_vein"]
	check(catalog.visible_resources(fresh.profile).size() == 4, "共享的四种资源可经扭曲矿脉开放，不依赖迷宫主归属")
	check(catalog.visible_resources(fresh.profile, "金").is_empty(), "资源名称搜索不揭示未知条目")
	check(catalog.visible_stickers(fresh.profile, "emblem").is_empty() and catalog.visible_stickers(fresh.profile, "rune").is_empty(), "未开放纹章及元素贴纸不显示占位")
	check(catalog.visible_stickers(fresh.profile, "wound").size() == 29, "伤势独立分区，未发现保留原图剪影")
	var poison: Dictionary = catalog.visible_stickers(fresh.profile, "wound").filter(func(entry: Dictionary): return entry.id == &"中毒Ⅰ")[0]
	fresh.profile.discoveries.stickers.poison_1 = true
	check(catalog.sticker_discovered(poison, fresh.profile), "旧英文伤势发现ID映射到正式图鉴")
	var source := load("res://resources/cards/stargazer.tres") as CardData
	check(catalog.derived_for(source, fresh.profile).is_empty(), "未开放未发现生成源不可揭示预言")
	var progress := richer_fixture(catalog)
	check(progress.start_run(), "图鉴专项夹具开启正式新局")
	for id: StringName in catalog.DERIVED_SOURCES: progress.note_discovery("cards", String(id))
	progress.note_discovery("resources", "rainbow_gold_ore")
	progress.note_discovery("resources", "gear_scrap")
	for id: String in ["火把", "混沌贴纸", "poison_1"]: progress.note_discovery("stickers", id)
	progress.commit_discoveries()
	progress.run.stage = "hub"
	var item_ids: Array[String] = []
	for entry: Dictionary in catalog.stickers:
		if entry.category != "wound": item_ids.append(String(entry.id))
	progress.profile.tasks["reference_fixture"] = {"purchased": true, "completed": false}
	check(progress.complete_task("reference_fixture", {"items": item_ids}), "使用正式任务奖励接口配置隔离档贴纸开放范围")
	for id: StringName in catalog.DERIVED_SOURCES:
		var generated := catalog.derived_for(catalog.definitions[id], progress.profile)
		check(generated.size() == catalog.DERIVED_SOURCES[id].size(), "已发现生成源预览全部结果：" + String(id))
	check(not catalog.DERIVED_SOURCES.has(&"sentry_machine"), "警戒机械已取消废料遗愿，不恢复失效生成关系")
	check(catalog.visible_resources(progress.profile).size() == 11, "全开放资源包括两种衍生资源")
	for entry: Dictionary in catalog.stickers:
		check(catalog.sticker_texture(entry) != null, "正式贴纸原图存在：" + String(entry.id))
		check(not catalog.sticker_text(entry).contains("资料状态：") and not catalog.sticker_text(entry).contains("待确认："), "玩家详情排除审阅元数据：" + String(entry.id))
	shell = SHELL.instantiate()
	shell.run_slots.directory = REFERENCE_DIR
	DirAccess.make_dir_recursive_absolute(REFERENCE_DIR)
	for index: int in 3: save_fixture(index, progress if index == 0 else ProfileProgress.new())
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K if "2k" in OS.get_cmdline_user_args() else shell.DisplayMode.WINDOW_720P)
	await frames()
	check(await shell.start_slot(0), "经正式存档入口恢复资源贴纸档")
	await click(button("GalleryButton"))
	var gallery = await wait_gallery()
	var before: Dictionary = shell.slot_progress.capture_state()
	var disk := FileAccess.get_file_as_string(shell.run_slots.get_slot_path(0))
	var hint: Control
	for page: Control in gallery._pages:
		for node: Node in page.get_children():
			if node.get_script() == Unknown:
				hint = node
				check(node.get_node("HintRarityFrame").texture != null, "未知卡使用稀有度卡框原图")
				check(node.find_children("*", "Label", true, false).is_empty(), "未知卡不泄露名称数值")
	check(hint != null, "测试页包含暗卡")
	await capture_reference("01_unknown_frames")
	await select_section(gallery, 1)
	var reference: Control = gallery._reference
	check(reference.entries.size() == 11 and reference.views.size() == 2 and reference.page_count() == 1, "资源按四种一行，无实际收藏位，只有发现条目可检视")
	check(reference._counter.text.contains("2 / 11"), "资源发现计数独立于生成源预览")
	await capture_reference("02_resources")
	await motion(reference.views[0].get_global_rect().get_center())
	await click(reference.views[0].get_node("ReadOnlyHoverHit"), MOUSE_BUTTON_RIGHT)
	await create_timer(0.65).timeout
	check(is_instance_valid(reference._inspection), "资源原生卡面右键4倍检视")
	if not is_instance_valid(reference._inspection): quit(1); return
	await key(KEY_ESCAPE)
	await wait_inspection_closed(reference)
	check(is_instance_valid(shell._gallery_panel), "资源关闭检视仍停留图鉴")
	await select_section(gallery, 2)
	reference = gallery._reference
	check(reference.entries.size() == 34 and reference.page_count() == 2, "纹章区独立分页")
	check(reference.views.is_empty(), "贴纸目录不创建拥有实例卡面")
	for node: Node in reference._nodes:
		if node.name == "UnknownSticker":
			check(node.tooltip_text.is_empty() and node.find_children("*", "Label", true, false).is_empty(), "未知剪影不包含名称效果或提示")
			check(node.get_child(0).material is ShaderMaterial, "未知贴纸保留原图透明轮廓")
	await capture_reference("03_emblems")
	await click(reference._next)
	check(reference.page_index == 1, "贴纸下一页可达")
	await key(KEY_PAGEUP)
	check(reference.page_index == 0, "贴纸PageUp翻页")
	await choose_option(reference._category, 1)
	check(reference.entries.size() == 29, "切换伤势分区")
	await capture_reference("04_wounds")
	# 已发现条目在第二页，搜索走真实文字输入。
	await click(reference._search)
	reference._search.text = "中毒"
	reference._search.text_changed.emit(reference._search.text)
	check(reference.entries.size() == 1, "贴纸搜索仅命中已发现内容，包括旧别名")
	var tile: Control = reference._nodes[0]
	await click(tile, MOUSE_BUTTON_RIGHT)
	await frames()
	check(is_instance_valid(reference._inspection), "已发现贴纸真实右键详情")
	await capture_reference("05_sticker_details")
	await key(KEY_ESCAPE)
	await frames()
	check(not is_instance_valid(reference._inspection), "贴纸详情Esc只退一层")
	await choose_option(reference._category, 2)
	reference._search.clear()
	reference._search.text_changed.emit("")
	check(reference.entries.size() == 7, "元素贴纸独立七种")
	await capture_reference("06_runes")
	await select_section(gallery, 0)
	await choose_option(gallery._pack_filter, gallery._pack_ids.find(&"silvermoon_chapter"))
	await query(gallery, source.display_name)
	check(gallery.shown_cards.size() == 1, "已发现生成源可搜索定位")
	var view: CardView = gallery.views["stargazer:base"]
	await click(view.get_node("ReadOnlyHoverHit"), MOUSE_BUTTON_RIGHT)
	await create_timer(0.7).timeout
	var related := gallery._inspection.find_child("DerivedPreviewButton", true, false) as Button
	check(related != null, "生成源4倍详情有衍生入口")
	await click(related)
	check(is_instance_valid(gallery._derived_preview) and gallery._derived_preview.views.size() == 2, "打开两种预言基础版本，不要求预言已生成")
	await capture_reference("07_derived")
	var derived: Control = gallery._derived_preview
	await click(derived.views[0].get_node("ReadOnlyHoverHit"), MOUSE_BUTTON_RIGHT)
	await create_timer(0.65).timeout
	check(is_instance_valid(derived._inspection), "衍生结果可继续4倍检视")
	await capture_reference("08_derived_inspection")
	await key(KEY_ESCAPE)
	await wait_inspection_closed(derived)
	check(is_instance_valid(gallery._derived_preview), "嵌套Esc先关结果4倍检视")
	await key(KEY_ESCAPE)
	await frames()
	check(not is_instance_valid(gallery._derived_preview) and is_instance_valid(gallery._inspection), "再次Esc回到生成源检视")
	await key(KEY_ESCAPE)
	await wait_inspection_closed(gallery)
	await query(gallery, (catalog.definitions[&"moon_tears"] as CardData).display_name)
	view = gallery.views["moon_tears:base"]
	await click(view.get_node("ReadOnlyHoverHit"), MOUSE_BUTTON_RIGHT)
	await create_timer(0.7).timeout
	await click(gallery._inspection.find_child("DerivedPreviewButton", true, false))
	check(gallery._derived_preview.views.size() == 1 and gallery._derived_preview.views[0].card_data.id == &"moondew", "未发现月露仍可经已发现的生成源预览")
	await capture_reference("09_derived_resource")
	await key(KEY_ESCAPE)
	await frames()
	await key(KEY_ESCAPE)
	await wait_inspection_closed(gallery)
	await select_section(gallery, 1)
	reference = gallery._reference
	check(reference._counter.text.contains("2 / 11") and not catalog.resource_discovered(catalog.definitions[&"moondew"], gallery.progress.profile), "衍生资源预览不会揭晓独立资源图鉴")
	await select_section(gallery, 0)
	check(gallery.progress.capture_state() == before and FileAccess.get_file_as_string(shell.run_slots.get_slot_path(0)) == disk, "资源贴纸衍生全部浏览前后存档状态与磁盘字节完全相同")
	await key(KEY_ESCAPE)
	while shell.screen_transition.busy: await process_frame
	check(not is_instance_valid(shell._gallery_panel), "最后Esc正常返回大厅")
	shell.free()
	await frames()
	print("D3-3 reference book checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
