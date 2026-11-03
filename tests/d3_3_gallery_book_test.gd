extends "res://tests/d3_3_gallery_test.gd"

const BOOK_DIR := "/private/tmp/project-card-d3-3-complete-book"
const BOOK_PREVIEWS := "res://docs/previews/d3_3_book_20261103"

func capture_book(title: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BOOK_PREVIEWS))
	var mode := "2k" if "2k" in OS.get_cmdline_user_args() else "720p"
	root.get_texture().get_image().save_png(BOOK_PREVIEWS.path_join(title + "_" + mode + ".png"))

func choose_option(option: OptionButton, index: int) -> void:
	await click(option)
	var popup := option.get_popup()
	check(popup.visible, "真实展开分类／筛选菜单：" + String(option.name))
	# 鼠标打开的原生PopupMenu初始焦点为-1；方向键先进入首项，不能假设Home受支持。
	for step: int in popup.item_count + 1:
		var focused := popup.get_focused_item()
		if focused == index: break
		await key(KEY_UP if focused > index else KEY_DOWN)
	await key(KEY_ENTER)
	await frames()
	check(option.selected == index and not popup.visible, "键盘真实选择下拉项：" + String(option.name))
	if option.selected != index or popup.visible: quit(1)

func query(gallery: Control, text: String) -> void:
	await click(gallery._search)
	gallery._search.clear()
	for character: String in text:
		for pressed: bool in [true, false]:
			var event := InputEventKey.new()
			event.unicode = character.unicode_at(0)
			event.pressed = pressed
			root.push_input(event, true)
			await process_frame
	await frames()
	check(gallery._search.text == text, "真实键盘输入搜索文字")

func richer_fixture(catalog: RefCounted) -> ProfileProgress:
	var progress := fixture(catalog)
	# 仅配置隔离测试档的开放范围，不把它冒充D3-4解锁流程。
	progress.profile.unlocks.packs = ["ash_ledger", "ironwall_inscription", "silvermoon_chapter", "twisted_vein", "labyrinth"]
	check(progress.start_run(), "收藏册大目录夹具继续真实新局")
	var collection := OwnedCardCollection.new()
	var cards: Array[OwnedCard] = []
	var choices: Array = []
	for id: String in ["musketeer", "militia", "recycling_robot", "silvermoon_priest", "crystal_shell_beetle"]:
		var owned := collection.create_card(load("res://resources/cards/" + id + ".tres"))
		owned.acquisition_source = {"kind": "pack", "name": CardPackRegistry.get_display_name(owned.card_data.pack_id)}
		owned.recruited_by = "ioann_warden"
		owned.lifetime_stats = {"damage_dealt": 245.5, "battles": 11}
		cards.append(owned)
		progress.note_discovery("cards", id)
		choices.append({"candidate_id": String(owned.instance_id), "slot": 0})
	check(progress.finish_run(cards, [], 20, "abandoned", 3, [], 2) and progress.show_selection() and progress.set_selection(choices) and progress.show_preview() and progress.confirm_collection(), "后续页及其他卡包的真实实例经正式流程入藏")
	return progress

func wait_gallery() -> Control:
	while shell.screen_transition.busy: await process_frame
	await frames()
	return shell._gallery_panel

func _run() -> void:
	create_timer(180).timeout.connect(func(): push_error("完整收藏册验证超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(BOOK_DIR)
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	var catalog := Catalog.new()
	var fresh := ProfileProgress.new()
	check(catalog.unlocked_packs(fresh.profile) == [&"ash_ledger"], "新档分类只出现灰烬，未开放分类没有菜单占位")
	check(catalog.count_total() == 130 and catalog.count_discovered(fresh.profile) == 0, "全册分母包含全部130种正式可入藏定义，不因锁包缩小")
	var humans := catalog.filtered_cards(fresh.profile, &"ash_ledger", CardData.RaceType.HUMAN)
	check(not humans.is_empty() and humans.all(func(card: CardData): return card.card_type == CardData.CardType.MINION and card.race_type == CardData.RaceType.HUMAN), "种族筛选只包含适用随从，不读取非随从的默认种族")
	check(catalog.filtered_cards(fresh.profile, &"ash_ledger", CardData.RaceType.HUMAN, CardData.CardType.EQUIPMENT).is_empty(), "互斥种族和类型条件不会泄漏或混入物品")
	check(catalog.filtered_cards(fresh.profile, &"ash_ledger", -1, -1, "火枪手").is_empty(), "未知卡名搜索不揭晓隐藏卡")
	check(catalog.filtered_cards(fresh.profile, &"ash_ledger", -1, -1, "乡邻").is_empty(), "未知效果搜索不揭晓隐藏卡")
	shell = SHELL.instantiate()
	shell.run_slots.directory = BOOK_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	var progress := richer_fixture(catalog)
	save_fixture(0, progress)
	save_fixture(1, ProfileProgress.new())
	var empty := ProfileProgress.new()
	empty.profile.unlocks.packs = []
	save_fixture(2, empty)
	var other1 := FileAccess.get_file_as_string(shell.run_slots.get_slot_path(1))
	var other2 := FileAccess.get_file_as_string(shell.run_slots.get_slot_path(2))
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K if "2k" in OS.get_cmdline_user_args() else shell.DisplayMode.WINDOW_720P)
	await frames()
	check(await shell.start_slot(0), "真实存档路由进入大目录档")
	var before: Dictionary = shell.slot_progress.capture_state()
	var disk := FileAccess.get_file_as_string(shell.run_slots.get_slot_path(0))
	await click(button("GalleryButton"))
	var gallery = await wait_gallery()
	check(gallery._pack_filter.item_count == 5 and gallery._pack_ids.size() == 5 and gallery._pack == &"ash_ledger", "已开放且有正式内容的五种分类进入菜单，默认灰烬")
	check(gallery.page_count() == 5 and gallery.page_index == 0 and gallery._previous.disabled and not gallery._next.disabled, "30种灰烬卡分为五张双页，首尾按钮状态准确")
	check(gallery._progress_label.text.contains("9 / 130") and gallery._progress_label.text.contains("6 / 30"), "本包与全册发现进度分别显示，不因分页改变")
	for control: Control in [gallery._pack_filter, gallery._race_filter, gallery._type_filter, gallery._search, gallery._previous, gallery._next, gallery._clear, gallery._page_label]:
		check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(control.get_global_rect()), "新浏览控件处于720p逻辑画布：" + String(control.name))
	await motion(Vector2(40, 110))
	await capture_book("01_complete_book")
	var first: CardView = gallery.views[String(gallery.shown_cards[0].id) + ":1"]
	await motion(first.get_global_rect().position + first.card_size * Vector2(0.8, 0.25))
	await create_timer(0.25).timeout
	var hover = shell.get_collection_hover_surface()
	check(hover.source == first and hover.visible, "翻页前真实悬停正常")
	await click(gallery._next)
	check(gallery.page_index == 1 and not is_instance_valid(first) and not hover.visible, "翻页释放旧卡和共享悬停，不残留透视画布")
	await key(KEY_PAGEDOWN)
	check(gallery.page_index == 2, "PageDown从第二张翻到第三张")
	await key(KEY_PAGEUP)
	check(gallery.page_index == 1, "PageUp返回上一张")
	await click(gallery._previous)
	check(gallery.page_index == 0, "上一页按钮回到首张")

	var all_ids: Dictionary = {}
	var page_nodes := [gallery.get_node("BookPage0").get_instance_id(), gallery.get_node("BookPage1").get_instance_id()]
	for pack_index: int in gallery._pack_ids.size():
		await choose_option(gallery._pack_filter, pack_index)
		var pack: StringName = gallery._pack_ids[pack_index]
		var expected: Array = catalog.visible_cards(shell.slot_progress.profile, pack)
		var visited: Array[String] = []
		check(gallery.page_index == 0, "切换分类回到第一页")
		for page: int in gallery.page_count():
			for card: CardData in gallery.shown_cards:
				check(card.pack_id == pack and not all_ids.has(String(card.id)), "分类分页无跨包混排或重复：" + String(card.id))
				all_ids[String(card.id)] = true
				visited.append(String(card.id))
			check(gallery.shown_cards.size() <= 6 and gallery._row_nodes.size() <= 24 and gallery.views.size() <= 24, "只绘制当前双页六种及固定三位，不创建全册渲染")
			if page + 1 < gallery.page_count(): await click(gallery._next)
		check(visited == expected.map(func(card: CardData): return String(card.id)), "完整遍历该包，保持品级降序与稳定ID次序")
		check(gallery._next.disabled and gallery.page_index + 1 == gallery.page_count(), "末页不继续翻出空页")
		if pack == &"ironwall_inscription":
			check(gallery.shown_cards.size() == 4, "34种目录末页仅四种，不补造两行卡")
			await capture_book("02_last_page")
	check(all_ids.size() == 130, "五个已开放目录共130种全部可达且无重复")
	check(page_nodes == [gallery.get_node("BookPage0").get_instance_id(), gallery.get_node("BookPage1").get_instance_id()], "全册翻页复用双页面板和表头")

	await choose_option(gallery._pack_filter, 0)
	await click(gallery._next)
	await choose_option(gallery._race_filter, CardData.RaceType.HUMAN + 1)
	check(gallery.page_index == 0 and gallery.filtered_cards.size() == humans.size(), "真实种族菜单刷新结果并回第一页")
	await choose_option(gallery._type_filter, CardData.CardType.EQUIPMENT + 1)
	check(gallery.shown_cards.is_empty() and gallery.page_count() == 0 and gallery._page_label.text == "第 0 / 0 页" and gallery._empty.visible and gallery._next.disabled and gallery._previous.disabled, "组合筛选空结果显示明确提示，两个翻页入口禁用")
	await capture_book("03_empty_filters")
	await click(gallery._clear)
	check(gallery.filtered_cards.size() == 30 and gallery.page_index == 0 and gallery._clear.disabled, "清除筛选恢复当前卡包，不改变分类")
	await choose_option(gallery._type_filter, CardData.CardType.EQUIPMENT + 1)
	check(gallery.filtered_cards.all(func(card: CardData): return card.card_type == CardData.CardType.EQUIPMENT), "真实类型筛选只保留物品")
	await capture_book("04_equipment_filter")
	await choose_option(gallery._pack_filter, 1)
	check(gallery._type_filter.selected == CardData.CardType.EQUIPMENT + 1 and gallery.filtered_cards.all(func(card: CardData): return card.pack_id == &"ironwall_inscription" and card.card_type == CardData.CardType.EQUIPMENT), "切换卡包保留筛选，并按新包重算")
	await click(gallery._clear)
	await choose_option(gallery._pack_filter, 0)
	await query(gallery, "火枪手")
	check(gallery.filtered_cards.size() == 1 and gallery.shown_cards[0].id == &"musketeer" and gallery.views.has("musketeer:1"), "已发现卡名搜索找到基础图鉴及同排真实实例")
	await capture_book("05_search")
	await click(gallery.views["musketeer:1"], MOUSE_BUTTON_RIGHT)
	await create_timer(0.9).timeout
	var inspection := gallery._inspection as Control
	check(is_instance_valid(inspection) and text_rows(inspection.find_child("CardDetails", true, false)).contains("245.5"), "筛选后右键检视仍读取该实例完整战绩")
	var page_before: int = gallery.page_index
	await key(KEY_PAGEDOWN)
	check(gallery.page_index == page_before and is_instance_valid(gallery._inspection), "检视期间PageDown不翻动后方收藏册")
	await key(KEY_ESCAPE)
	await wait_inspection_closed(gallery)
	await click(gallery._clear)
	await query(gallery, "乡邻")
	check(not gallery.filtered_cards.is_empty() and gallery.filtered_cards.all(func(card: CardData): return catalog.discovered(card, shell.slot_progress.profile)), "效果搜索只检查已发现定义，未知卡不因效果命中出现")
	await click(gallery._clear)
	var unknown: CardData
	for card: CardData in gallery.filtered_cards:
		if not catalog.discovered(card, shell.slot_progress.profile): unknown = card; break
	await query(gallery, unknown.display_name)
	check(gallery.shown_cards.is_empty(), "输入未知卡的精确名称仍不能找到其隐藏占位")
	await click(gallery._clear)
	await click(gallery._next)
	await click(gallery._next)
	await click(gallery.get_node("GalleryReturnButton"))
	await wait_gallery()
	check(not is_instance_valid(shell._gallery_panel) and shell._slot_progress_panel.visible and not hover.visible, "从后续页返回大厅释放页面与悬停")
	check(shell.slot_progress.capture_state() == before and FileAccess.get_file_as_string(shell.run_slots.get_slot_path(0)) == disk, "全目录、筛选、搜索、检视与翻页前后内存和磁盘字节一致")
	check(FileAccess.get_file_as_string(shell.run_slots.get_slot_path(1)) == other1 and FileAccess.get_file_as_string(shell.run_slots.get_slot_path(2)) == other2, "浏览大目录不写其他两档")

	shell.return_to_start_menu()
	await frames()
	check(await shell.start_slot(1), "切换新档")
	await click(button("GalleryButton"))
	gallery = await wait_gallery()
	check(gallery._pack_filter.item_count == 1 and gallery._pack_ids == [&"ash_ledger"] and gallery.views.is_empty() and gallery.page_count() == 5, "新档只展示本档开放的完整灰烬卡包，未借用全解锁档发现")
	await capture_book("06_locked_profile")
	await query(gallery, "火枪手")
	check(gallery.shown_cards.is_empty() and gallery._progress_label.text.contains("0 / 130"), "未知搜索为空但全册分母仍为130")
	shell._close_gallery()
	shell.return_to_start_menu()
	await frames()
	check(await shell.start_slot(2), "切换无开放卡包档")
	await click(button("GalleryButton"))
	gallery = await wait_gallery()
	check(gallery._pack_filter.disabled and gallery._pack_ids.is_empty() and gallery.shown_cards.is_empty() and gallery.page_count() == 0 and gallery._empty.visible, "没有开放卡包时分类禁用并显示空目录，不自动开放灰烬")
	await capture_book("07_empty_catalog")
	shell._close_gallery()
	shell.free()
	await frames()
	print("D3-3 complete book checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
