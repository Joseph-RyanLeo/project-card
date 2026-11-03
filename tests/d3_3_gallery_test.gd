extends "res://tests/d3_2_collection_review_test.gd"

const GALLERY_DIR := "/private/tmp/project-card-d3-3-gallery"
const GALLERY_PREVIEWS := "res://docs/previews/d3_3_20261103"
const Catalog = preload("res://scripts/data/gallery_catalog.gd")
const Unknown = preload("res://scripts/ui/gallery_unknown_card.gd")

func capture_gallery(title: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GALLERY_PREVIEWS))
	root.get_texture().get_image().save_png(GALLERY_PREVIEWS.path_join(title + ".png"))

func fixture(catalog: RefCounted) -> ProfileProgress:
	var progress := ProfileProgress.new()
	progress.start_run()
	var definitions: Array = catalog.visible_cards(progress.profile, &"ash_ledger").slice(0, 6)
	var collection := OwnedCardCollection.new()
	var cards: Array[OwnedCard] = []
	var choices: Array = []
	for index: int in [0, 0, 0, 1, 3, 5]:
		var card := collection.create_card(definitions[index])
		card.acquired_at = 1793664000
		card.acquisition_source = {"kind": "pack", "name": "灰烬证册"}
		card.recruited_by = "ioann_warden"
		if index == 0:
			card.surface_finish = cards.size() as CardAppearance.Surface
			card.permanent_growth = {"base_value": cards.size() + 1, "max_health": 3}
			card.lifetime_stats = {"damage_dealt": 123.5, "kills": 7, "battles": 9, "deaths": 2}
			card.rune_revealed.fill(true)
		cards.append(card)
		progress.note_discovery("cards", String(card.card_data.id))
	check(progress.finish_run(cards, [], 25, "abandoned", 3, [], 2) and progress.show_selection(), "以真实结算生成积分、发现和收藏候选")
	var used: Dictionary = {}
	for card: OwnedCard in cards:
		if card.card_data == definitions[5]: continue
		var id := String(card.card_data.id)
		var slot := int(used.get(id, 0))
		choices.append({"candidate_id": String(card.instance_id), "slot": slot})
		used[id] = slot + 1
	check(progress.set_selection(choices) and progress.show_preview() and progress.confirm_collection(), "正式入藏三份同种实例，另保留已发现未入藏卡")
	return progress

func save_fixture(index: int, progress: ProfileProgress) -> void:
	check(RunSaveService.new().save_checkpoint(shell.run_slots.get_slot_path(index), {"schema_version": RunSaveService.SCHEMA_VERSION, "profile_progress": progress.capture_state()}) == OK, "隔离临时档%d写入真实JSON" % (index + 1))

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("D3-3展览馆专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(GALLERY_DIR)
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	var catalog := Catalog.new()
	var new_profile := ProfileProgress.new()
	check(catalog.count_total(&"ash_ledger") == 30, "灰烬正式目录30种，扫描资源收录")
	check(catalog.cards.all(func(card: CardData): return card.pack_id != &"development_test" and not card.pack_id.is_empty() and not card.is_derived and card.card_type != CardData.CardType.RESOURCE), "开发演示、衍生、资源不混入可入藏卡册")
	check(catalog.visible_cards(new_profile.profile, &"ironwall_inscription").is_empty() and catalog.count_total(&"ironwall_inscription") > 0, "未解锁分类和占位隐藏，正式内容仍在总数")
	var unavailable := (load("res://resources/cards/militia.tres") as CardData).duplicate(true) as CardData
	unavailable.is_available = false
	var stopped_catalog := Catalog.new()
	stopped_catalog.cards = [unavailable]
	check(stopped_catalog.count_total(&"ash_ledger") == 1 and stopped_catalog.visible_cards(new_profile.profile, &"ash_ledger").is_empty(), "正式停用身份仍计分母，未发现不展示")
	new_profile.profile.discoveries.cards["militia"] = true
	check(stopped_catalog.visible_cards(new_profile.profile, &"ash_ledger").size() == 1, "正式停用且已发现保留图鉴")
	new_profile.profile.discoveries.cards.clear()
	new_profile.profile.collection["militia"] = [{"archive_id": "only-for-visibility"}]
	check(stopped_catalog.visible_cards(new_profile.profile, &"ash_ledger").size() == 1, "正式停用已有收藏保留显示资格")
	shell = SHELL.instantiate()
	shell.run_slots.directory = GALLERY_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	var seeded := fixture(catalog)
	save_fixture(0, seeded)
	save_fixture(1, ProfileProgress.new())
	var third := ProfileProgress.new()
	third.profile.unlocks.packs = ["ironwall_inscription"]
	save_fixture(2, third)
	var untouched_slot1 := FileAccess.get_file_as_string(shell.run_slots.get_slot_path(1))
	var untouched_slot2 := FileAccess.get_file_as_string(shell.run_slots.get_slot_path(2))
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K if "2k" in OS.get_cmdline_user_args() else shell.DisplayMode.WINDOW_720P)
	await frames()
	check(await shell.start_slot(0), "真实路由恢复入藏后的大厅")
	var before: Dictionary = shell.slot_progress.capture_state()
	var disk := FileAccess.get_file_as_string(shell.run_slots.get_slot_path(0))
	await click(button("GalleryButton"))
	while shell.screen_transition.busy: await process_frame
	await frames()
	var gallery = shell._gallery_panel
	check(gallery != null and gallery.visible and not shell._slot_progress_panel.visible, "大厅进入独立展览馆，隐藏大厅操作")
	check(gallery.shown_cards.size() == 6 and gallery.views.size() == 9, "首张双页六行，每种基础图鉴加三个固定实际收藏位")
	var unknown_count := 0
	for side: int in 2:
		var page: Control = gallery.get_node("BookPage%d" % side)
		check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(page.get_global_rect()), "双页%d在720p逻辑画布内" % side)
		for node: Node in page.get_children():
			if node.get_script() != Unknown: continue
			unknown_count += 1
			check(node.find_children("*", "CardView", true, false).is_empty() and node.find_children("*", "Label", true, false).is_empty() and node.tooltip_text.is_empty(), "未知卡不绑定可检视CardView或隐藏文字")
			await click(node, MOUSE_BUTTON_RIGHT)
			check(not is_instance_valid(gallery._inspection), "右键未知卡不泄漏详情")
	check(unknown_count == 2, "首版真实区分两种未知基础卡")
	var hint := Unknown.new()
	gallery.add_child(hint)
	hint.setup(load("res://resources/cards/fireman.tres"))
	var first_icon: Texture2D = hint.get_node("HintAction").texture
	await create_timer(Unknown.ACTION_SECONDS + 0.1).timeout
	check(hint.get_node("HintAction").texture != first_icon and hint._textures.size() == 2, "多行动方式暗示在左上轮换，不生成拥有实例")
	hint.free()
	var no_race := Unknown.new()
	gallery.add_child(no_race)
	var no_race_definition := (load("res://resources/cards/militia.tres") as CardData).duplicate(true) as CardData
	no_race_definition.race_type = CardData.RaceType.NONE
	no_race.setup(no_race_definition)
	check(no_race.get_node_or_null("HintIdentity") == null and no_race.get_node_or_null("HintAction") != null, "无种族字段留空，仍保留适用行动暗示")
	no_race.free()
	var id: String = gallery.shown_cards[0].id
	var base: CardView = gallery.views[id + ":base"]
	var first: CardView = gallery.views[id + ":1"]
	check(base.get_owned_card() == null and first.get_owned_card() != null, "基础图鉴不伪造拥有实例，收藏读取完整快照")
	check(first.get_owned_card().permanent_growth.base_value == 1 and first.get_owned_card().lifetime_stats.damage_dealt == 123.5, "成长与累计战绩从入藏快照恢复")
	for slot: int in 3:
		check(int(gallery.views[id + ":%d" % (slot + 1)].get_owned_card().surface_finish) == slot, "收藏位%d保持入藏顺序和外观" % (slot + 1))
	await motion(Vector2(40, 110))
	await capture_gallery("01_book_" + ("2k" if "2k" in OS.get_cmdline_user_args() else "720p"))
	await motion(first.get_global_rect().position + first.card_size * Vector2(0.8, 0.25))
	await create_timer(0.3).timeout
	var hover = shell.get_collection_hover_surface()
	check(hover.source == first and hover.read_only and hover.visible and first.modulate.a == 0 and hover.force.length() > 0.2, "真实鼠标悬停复用单份高精度透视画布")
	await capture_gallery("02_hover_" + ("2k" if "2k" in OS.get_cmdline_user_args() else "720p"))
	await click(first, MOUSE_BUTTON_RIGHT)
	check(is_instance_valid(gallery._inspection) and gallery._inspection.get_meta("opening"), "真实右键从原位动画进入只读检视")
	await create_timer(1.0).timeout
	var surface: InspectionCardSurface = gallery._inspection.get_node("CollectionInspectionSurface")
	check(surface.scale == Vector2(4, 4) and surface.card.get_owned_card() == first.get_owned_card(), "放大4倍仍绑定该收藏实例")
	var details: ScrollContainer = gallery._inspection.find_child("CardDetails", true, false)
	check(text_rows(details).contains("123.5") and text_rows(details).contains("灰烬证册") and text_rows(details).contains("永久成长"), "详情显示完整快照的来源、成长和累计战绩")
	await capture_gallery("03_inspection_" + ("2k" if "2k" in OS.get_cmdline_user_args() else "720p"))
	var card_state := first.get_owned_card().capture_state()
	await click(surface, MOUSE_BUTTON_LEFT)
	check(first.get_owned_card().capture_state() == card_state, "检视点击不刮符文、不修改实例")
	await key(KEY_ESCAPE)
	await wait_inspection_closed(gallery)
	check(gallery.visible and shell.slot_progress.run.stage == "hub", "Esc先缩回检视，仍留在展览馆")
	await click(base, MOUSE_BUTTON_RIGHT)
	await create_timer(0.9).timeout
	check(gallery._inspection.get_node("InspectionDetails/InspectionTabs").tab_count == 1, "基础图鉴不显示伪造实例积分或战绩")
	details = gallery._inspection.find_child("CardDetails", true, false)
	check(text_rows(details).contains("基础图鉴") and not text_rows(details).contains("获得与累计战绩"), "基础详情独立于本档具体实例状态")
	await click(gallery._inspection.get_node("CloseCollectionInspection"))
	await wait_inspection_closed(gallery)
	await key(KEY_ESCAPE)
	while shell.screen_transition.busy: await process_frame
	await frames()
	check(not is_instance_valid(shell._gallery_panel) and shell._slot_progress_panel.visible and not hover.visible, "Esc返回本档大厅，释放检视和悬停")
	check(shell.slot_progress.capture_state() == before and FileAccess.get_file_as_string(shell.run_slots.get_slot_path(0)) == disk, "全部浏览前后ProfileProgress及磁盘字节一致，不发分或改发现")
	await click(button("GalleryButton"))
	while shell.screen_transition.busy: await process_frame
	await frames()
	await click(shell._gallery_panel.get_node("GalleryReturnButton"))
	while shell.screen_transition.busy: await process_frame
	await frames()
	check(not is_instance_valid(shell._gallery_panel) and shell._slot_progress_panel.visible, "返回大厅按钮复用同一关闭流程")
	check(FileAccess.get_file_as_string(shell.run_slots.get_slot_path(1)) == untouched_slot1 and FileAccess.get_file_as_string(shell.run_slots.get_slot_path(2)) == untouched_slot2, "浏览第一档不写其他两档")
	shell.return_to_start_menu()
	await frames()
	check(await shell.start_slot(1), "切换第二档新档")
	untouched_slot1 = FileAccess.get_file_as_string(shell.run_slots.get_slot_path(1))
	await click(button("GalleryButton"))
	while shell.screen_transition.busy: await process_frame
	await frames()
	check(shell._gallery_panel.views.is_empty() and shell._gallery_panel.shown_cards.size() == 6, "第二档同一页全部未知且没有第一档收藏")
	await capture_gallery("04_new_profile")
	shell._close_gallery()
	check(FileAccess.get_file_as_string(shell.run_slots.get_slot_path(1)) == untouched_slot1, "第二档浏览前后磁盘字节一致")
	shell.return_to_start_menu()
	await frames()
	check(await shell.start_slot(2), "切换第三档不同开放卡包")
	await click(button("GalleryButton"))
	while shell.screen_transition.busy: await process_frame
	await frames()
	check(shell._gallery_panel.shown_cards.all(func(card: CardData): return card.pack_id == &"ironwall_inscription") and shell._gallery_panel.views.is_empty(), "第三档只展示本档开放卡包且不借用其他档发现")
	shell._close_gallery()
	check(FileAccess.get_file_as_string(shell.run_slots.get_slot_path(2)) == untouched_slot2, "第三档浏览前后磁盘字节一致")
	shell.free()
	await frames()
	# 在全新显示壳重新读取磁盘，确认不是沿用页面缓存。
	shell = SHELL.instantiate()
	shell.run_slots.directory = GALLERY_DIR
	root.add_child(shell)
	await frames()
	check(await shell.start_slot(0), "新显示壳恢复第一档")
	await click(button("GalleryButton"))
	while shell.screen_transition.busy: await process_frame
	await frames()
	check(shell._gallery_panel.views.size() == 9 and shell.slot_progress.capture_state() == before, "重建显示壳后恢复同一页发现、固定收藏位和余额")
	print("D3-3 gallery checks: %d, failures: %d" % [checks, failures])
	shell.free()
	await frames()
	quit(1 if failures else 0)
