extends SceneTree

## 真实收藏实例验证：双向翻页、尾页、动画中取消/筛选及隐藏符文。
const MAIN_SCENE = preload("res://scenes/Main.tscn")
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if value:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func run() -> void:
	root.size = Vector2i(1280, 720)
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	main.run_save_path = "/private/tmp/project-card-page-turn-test-save.json"
	main._battle_performance_trace_enabled = true
	await process_frame
	main.owned_card_collection = OwnedCardCollection.new()
	var definition := load("res://resources/cards/heavy_knight.tres") as CardData
	for index: int in 37:
		main.owned_card_collection.create_card(definition)
	main._sync_legacy_collection_cards()
	main.current_collection_page = 0
	main._build_collection_cards()
	await process_frame
	var originals: Array[Control] = main._get_collection_card_slots()
	check(main.turn_collection_page(1), "37 张实例可以向后翻页")
	check(main._battle_trace_page_turn_usec > 0, "诊断直接记录收藏翻页的同步构建耗时")
	main._record_battle_performance_frame(0.016)
	check(float(main._battle_trace_frame_samples.back().collection_page_turn_ms) > 0 and main._battle_trace_page_turn_usec == 0, "翻页耗时写入本帧并清空累计计数")
	var overlay: Control = main._page_turn_overlay
	var moving := overlay.get_node("MovingPage") as Control
	var old_layer := moving.get_node("CardLayer") as Control
	check(old_layer.get_child(0) == originals[6], "活动纸面复用真实旧卡，保持符文实例身份")
	var targets: Array[Control] = main._get_collection_card_slots()
	check(targets.size() == 12, "动画中查询得到目标页的 12 张真实卡")
	var target_card := targets[0].get_child(0) as CardView
	var first_cover := target_card.rune_row.get_child(0).get_node("RuneRevealCover")
	check(target_card.get_owned_card() == targets[0].get_meta("owned_card") and first_cover != null, "目标页仍绑定隐藏符文的原单卡实例与覆盖层")
	check(target_card.mouse_filter == Control.MOUSE_FILTER_IGNORE and not target_card._drag_enabled, "动画期间禁止检视与拖起目标卡")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-page-turn-reuse.png")
	await create_timer(main.PAGE_TURN_HALF_DURATION + 0.03).timeout
	check(moving.get_node("CardLayer").get_child(0) == targets[0], "纸面过中点继续复用同一张目标卡")
	check(target_card.rune_row.get_child(0).get_node("RuneRevealCover") == first_cover, "翻页中点没有重建或移除符文覆盖层")
	await create_timer(main.PAGE_TURN_HALF_DURATION + 0.08).timeout
	check(main.collection_card_row.visible and main.collection_card_row.get_child(0) == targets[0], "完成后归还同一目标卡到实时收藏")
	check(targets[0].position == main._collection_slot_position(0) and target_card._drag_enabled, "还原收藏位置与准备阶段拖拽")
	check(target_card.click_carry_requested.is_connected(main._on_click_carry_requested), "归还后点按携带信号仍然有效")
	check(main.turn_collection_page(0), "可以反向翻页")
	var reverse_target: Control = main._get_collection_card_slots()[0]
	main._clear_page_turn_overlay()
	check(not main.is_page_turning() and main.collection_card_row.get_child(0) == reverse_target, "中点前取消也归还正确目标页")
	check(main.turn_collection_page(3), "可以直接翻至只有一张卡的尾页")
	await create_timer(main.PAGE_TURN_HALF_DURATION + 0.03).timeout
	main._clear_page_turn_overlay()
	check(main._get_collection_card_slots().size() == 1 and main.collection_card_row.get_child_count() == 12, "中点后取消保留尾页实卡与空位置")
	check(main.turn_collection_page(0), "尾页可以翻回首页")
	main.toggle_card_type_filter(CardData.CardType.MINION)
	check(not main.is_page_turning() and main._get_collection_card_slots().size() == 12, "动画中切换筛选会先归还并清理旧纸面")
	await create_timer(main.PAGE_TURN_HALF_DURATION * 2 + 0.1).timeout
	check(main.collection_card_row.visible and main._get_collection_card_slots().size() == 12, "已取消的 Tween 不会再次破坏新收藏层")
	main.queue_free()
	await process_frame
	print("收藏翻页复用检查完成，失败数：", failures)
	quit(failures)
