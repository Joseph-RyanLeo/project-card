extends "res://tests/d3_2_collection_input_test.gd"

const REVIEW_DIR := "/private/tmp/project-card-summary-pictures"
const REVIEW_PREVIEWS := "res://docs/previews/summary_review_20261102"

func picture_shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REVIEW_PREVIEWS))
	root.get_texture().get_image().save_png(REVIEW_PREVIEWS.path_join(label + ".png"))

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("图片积分及比较专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(REVIEW_DIR)
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = REVIEW_DIR
	shell.run_slots.delete_slot(0)
	var progress := ProfileProgress.new()
	var collection := OwnedCardCollection.new()
	progress.start_run()
	var old: Array[OwnedCard] = []
	for index: int in 3: old.append(collection.create_card(load("res://resources/cards/musketeer.tres")))
	progress.begin_collection(old)
	var choices: Array = []
	for index: int in 3: choices.append({"candidate_id": String(old[index].instance_id), "slot": index})
	check(progress.set_selection(choices) and progress.show_preview() and progress.confirm_collection() and progress.start_run(), "真实建立固定三个收藏位后开始下一局")
	var cards: Array[OwnedCard] = []
	for name: String in ["musketeer", "town_priest", "shieldwall_private", "moon_hawk", "musketeer", "militia", "field_medic", "gunsmith_master", "musketeer", "formation_infantry", "beer_mug", "crystallized_remains"]:
		cards.append(collection.create_card(load("res://resources/cards/" + name + ".tres")))
	cards[0].surface_finish = CardAppearance.Surface.FRACTURED
	cards[0].art_finish = CardAppearance.Art.OVERFRAME
	var stickers: Array = [{"instance_id": "summary_torch", "emblem_id": "火把"}, {"instance_id": "summary_fire", "emblem_id": "火贴纸", "element_sticker": true, "element": 0}, {"instance_id": "summary_wound", "wound_id": "中毒Ⅰ", "kind": "wound"}]
	check(progress.finish_run(cards, stickers, 39, "abandoned", 4, [], 2), "真实积分总结冻结卡牌、工具箱贴纸与金币")
	var original := progress.capture_state()
	check(progress.run.summary.cards[0].snapshot.surface_finish == "fractured" and progress.run.summary.toolbox[1].sticker.emblem_id == "火贴纸", "总结保存真实单卡外观及具体贴纸快照")
	var damaged := original.duplicate(true)
	damaged.run.summary.cards[0].snapshot.card_id = "militia"
	check(not ProfileProgress.new().restore_state(damaged), "身份不符的图片快照拒绝恢复")
	var legacy := original.duplicate(true)
	for card: Dictionary in legacy.run.summary.cards: card.erase("snapshot")
	for item: Dictionary in legacy.run.summary.toolbox: item.erase("sticker")
	check(ProfileProgress.new().restore_state(legacy), "旧总结缺少新增图片快照仍能恢复")
	check(RunSaveService.new().save_checkpoint(shell.run_slots.get_slot_path(0), {"schema_version": RunSaveService.SCHEMA_VERSION, "profile_progress": original}) == OK, "图片总结写入正式隔离JSON")
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_720P)
	check(await shell.start_slot(0), "真实恢复图片总结")
	while shell.screen_transition.busy: await process_frame
	await frames()
	var panel: Control = shell._slot_progress_panel
	var balance: int = shell.slot_progress.profile.points
	var before_browsing: Dictionary = shell.slot_progress.capture_state()
	await click(button("ScoreDetailsButton"))
	check(panel._details.visible, "真实点击展开图片积分明细")
	var grid: GridContainer = panel.find_child("ScoreImageGrid", true, false)
	check(grid != null and grid.columns == 2 and grid.get_child_count() == cards.size() + stickers.size() + 1, "得分详情为图片网格，包含每张卡、每枚工具箱贴纸和金币")
	var first: CardView = grid.find_child("ScoreCard_" + String(cards[0].instance_id), true, false)
	check(first != null and first.is_snapshot_mode() and first.get_owned_card().surface_finish == CardAppearance.Surface.FRACTURED and first.get_owned_card().art_finish == CardAppearance.Art.OVERFRAME, "总结实际绘制原实例工艺的只读卡面")
	await picture_shot("01_summary_cards")
	for index: int in 18: await wheel(panel._details.get_global_rect().get_center())
	check(panel._details.scroll_vertical > 300, "真实滚轮切换浏览后续图片明细")
	var rune_picture: Control = grid.get_child(cards.size() + 1).find_child("ScoreStickerImage", true, false)
	check(rune_picture != null and rune_picture.texture == RuneStickerStyle.get_texture_by_id(&"火贴纸"), "工具箱积分使用实际火贴纸图片")
	for index: int in 80:
		if panel._details.get_global_rect().encloses(rune_picture.get_global_rect()): break
		await wheel(panel._details.get_global_rect().get_center())
	check(panel._details.get_global_rect().encloses(rune_picture.get_global_rect()), "滚轮实际浏览到工具箱贴纸图片")
	await picture_shot("02_summary_toolbox")
	check(shell.slot_progress.profile.points == balance and shell.slot_progress.capture_state() == before_browsing, "浏览图片明细不改积分、冻结状态或重复入账")
	await click(button("SummaryCollectionButton"))
	panel = shell._slot_progress_panel
	var id := String(cards[0].instance_id)
	for mode: int in [shell.DisplayMode.WINDOW_720P, shell.DisplayMode.WINDOW_2K]:
		shell.apply_display_mode(mode)
		await frames()
		await click(panel._cells[id].view)
		var comparison: Control = panel.find_child("CollectionComparison", true, false)
		check(comparison != null and comparison.get_viewport() == shell.internal_viewport and comparison.size == Vector2(1280, 720), "比较界面使用完整逻辑画布，随窗口缩放")
		var body: Control = comparison.get_node("ComparisonBody")
		var views: Array[Node] = body.find_children("ComparisonCard*", "Control", false, false)
		check(views.size() == 4, "候选与固定三个收藏位同时显示")
		var sizes_correct := true
		for view: CardView in views:
			var physical: Rect2 = shell.render_container.get_global_transform_with_canvas() * view.get_global_rect()
			sizes_correct = sizes_correct and view.scale == Vector2(2, 2) and is_equal_approx(physical.size.x, 198 * shell.render_container.scale.x)
		check(sizes_correct, "四张卡都是实际逻辑2倍，2K时实际宽396像素")
		check(comparison.find_child("ToggleCard*", true, false) == null and comparison.find_child("ReplaceSlot1Button", true, false) != null, "移除含糊的翻面按钮，保留明确替换入口")
		await picture_shot("03_comparison_" + str(mode))
		await click(comparison.get_node("CloseComparisonButton"))
		await frames()
	check(shell.slot_progress.profile.points == balance and shell.slot_progress.run.selection.is_empty(), "关闭比较不保存替换或改动积分")
	print("Summary picture comparison checks: %d, failures: %d" % [checks, failures])
	shell.free()
	await frames()
	quit(1 if failures else 0)
