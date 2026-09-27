extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var owned: OwnedCard
	var source: CardView
	for slot: Control in main._get_collection_card_slots():
		var candidate: OwnedCard = slot.get_meta("owned_card", null)
		if candidate != null and candidate.card_data.card_type == CardData.CardType.MINION and candidate.card_data.runes.size() == 3:
			owned = candidate
			source = slot.get_child(0)
			break
	check(main.emblem_library.position.x + main.emblem_library.size.x < 175, "常规工作包右边界不进入收藏书页")
	main._open_card_inspection(owned.card_data, owned, source)
	await process_frame
	var surface = main._inspection_surface
	var first_scale: Vector2 = surface.scale
	await create_timer(0.3).timeout
	check(not first_scale.is_equal_approx(surface.scale), "打开检视逐渐放大而非瞬移")
	check(surface.scale == Vector2(4, 4), "整卡合成显示达到4倍原生尺寸")
	check((surface.position + surface.size * 2).is_equal_approx(main._inspection_overlay.size * 0.5), "检视卡牌精确居中")
	check(main.emblem_library.position.x + main.emblem_library.size.x * main.emblem_library.scale.x < surface.position.x, "工作包不挡住居中卡牌")
	check(main._inspection_carry_layer.get_parent() == main._inspection_overlay and main._inspection_carry_layer.z_index <= 4096, "检视携带预览使用前景层且z-index合法")
	var visible_pattern_labels_hidden := true
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_back_row, main.enemy_front_row]:
		for slot: BoardSlot in row.get_squads():
			visible_pattern_labels_hidden = visible_pattern_labels_hidden and not slot.pattern_label.visible
	check(visible_pattern_labels_hidden, "打开检视时临时隐藏四排小队牌型标签")
	surface.force = Vector2.ZERO
	check(surface.card_point(surface.PADDING + Vector2(5, 46)).distance_to(Vector2(5, 46)) < 0.01, "无倾斜时逆投影准确落在卡面槽位")
	var defs: Array[Dictionary] = main.emblem_library.get_definitions()
	var emblem := {"kind": &"emblem_library", "emblem_id": defs[0].id, "definition": defs[0]}
	check(main._drop_emblem_on_inspection_card(main._inspection_card_view, Vector2(5, 46), emblem), "普通纹章可真实粘贴")
	var scraper := {"kind": &"sticker_scraper"}
	check(main._can_drop_emblem_on_inspection_card(main._inspection_card_view, Vector2(5, 46), scraper), "刮刀可命中已贴纹章")
	check(not owned.emblem_slots[0].is_empty(), "拖过只检查、不提前刮除")
	check(main._drop_emblem_on_inspection_card(main._inspection_card_view, Vector2(5, 46), scraper), "松手刮下纹章")
	check(owned.emblem_slots[0].is_empty() and main.emblem_library._returned.is_empty(), "刮下实例被移除且不会返还工作包")
	check(not main._can_drop_emblem_on_inspection_card(main._inspection_card_view, Vector2(5, 62), scraper), "伤势槽不接受刮刀")
	var rune := {"kind": &"emblem_library", "emblem_id": defs[3].id, "definition": defs[3]}
	var original := owned.card_data.runes[0]
	var revealed := owned.rune_revealed[0]
	var slot_definitions: Array[Dictionary] = CardSlotLayout.get_slot_definitions(owned.card_data, owned)
	var wound_position := Vector2.ZERO
	var emblem_position := Vector2.ZERO
	for slot_definition: Dictionary in slot_definitions:
		if int(slot_definition.kind) == CardSlotLayout.Kind.WOUND and wound_position == Vector2.ZERO:
			wound_position = slot_definition.position + Vector2(7, 7)
		elif int(slot_definition.kind) == CardSlotLayout.Kind.EMBLEM and emblem_position == Vector2.ZERO:
			emblem_position = slot_definition.position + Vector2(7, 7)
	check(not main._can_drop_emblem_on_inspection_card(main._inspection_card_view, wound_position, rune), "元素贴纸不能投到伤势槽")
	check(not main._can_drop_emblem_on_inspection_card(main._inspection_card_view, wound_position, {"kind": &"emblem_library", "emblem_id": defs[0].id, "definition": defs[0]}), "纹章不能投到伤势槽")
	var wound_definition: Dictionary = main.wound_library.get_definitions()[0]
	var wound_item := {"kind": &"emblem_library", "status_kind": "wound", "wound_id": wound_definition.id, "definition": wound_definition}
	check(not main._can_drop_emblem_on_inspection_card(main._inspection_card_view, emblem_position, wound_item), "伤势不能投到纹章槽")
	var original_emblems := owned.emblem_slots.duplicate(true)
	var original_wounds := owned.wound_slots.duplicate(true)
	for slot_index: int in owned.emblem_slots.size():
		if owned.emblem_slots[slot_index].is_empty():
			owned.set_emblem_slot(slot_index, {"instance_id": StringName("test_emblem_%d" % slot_index), "emblem_id": defs[0].id, "temporary": false})
	var full_emblems := owned.emblem_slots.duplicate(true)
	var rune_landing: Dictionary = main._get_inspection_drop_preview(main._inspection_card_view, Vector2(19, 119), rune)
	var expected_rune_landing: Vector2 = main._inspection_card_view.rune_area_position + (main._inspection_card_view.rune_slot_size - Vector2(27, 27)) * 0.5
	check(main._can_drop_emblem_on_inspection_card(main._inspection_card_view, Vector2(19, 119), rune) and rune_landing.position.is_equal_approx(expected_rune_landing), "纹章槽全部占用时，空符文位仍可投放元素贴纸且虚影指向符文区")
	check(main._drop_emblem_on_inspection_card(main._inspection_card_view, Vector2(19, 119), rune), "符文贴纸可以贴到元素槽")
	check(owned.get_effective_rune(0) == CardData.ElementType.LIGHT and owned.card_data.runes[0] == original, "符文替换只更新实例、不改底层原符文")
	check(owned.emblem_slots == full_emblems and owned.wound_slots == original_wounds, "符文贴纸不会占用纹章槽或伤势槽")
	check(not main._can_drop_emblem_on_inspection_card(main._inspection_card_view, Vector2(19, 119), rune) and not main._drop_emblem_on_inspection_card(main._inspection_card_view, Vector2(19, 119), rune), "同一位置不能覆盖已有符文贴纸")
	owned.emblem_slots.assign(original_emblems)
	var wound_index: int = main._find_empty_wound_slot_at(wound_position)
	check(main._drop_emblem_on_inspection_card(main._inspection_card_view, wound_position, wound_item) and wound_index >= 0 and not owned.wound_slots[wound_index].is_empty() and owned.emblem_slots == original_emblems, "伤势只写入伤势槽，不写入纹章槽")
	check(not main._can_drop_emblem_on_inspection_card(main._inspection_card_view, wound_position, wound_item), "已占用的伤势槽拒绝再次投放")
	owned.wound_slots.assign(original_wounds)
	check(main.save_run_to_path("/private/tmp/project-card-sticker-save.json") == OK, "后贴符文进入JSON保存")
	check(FileAccess.get_file_as_string("/private/tmp/project-card-sticker-save.json").contains("rune_stickers"), "存档含独立符文贴纸字段")
	check(main._drop_emblem_on_inspection_card(main._inspection_card_view, Vector2(19, 119), scraper), "刮刀可刮符文贴纸")
	check(owned.get_effective_rune(0) == original and owned.rune_revealed[0] == revealed, "刮下恢复底层符文及原揭晓状态")
	check(main.emblem_library._returned.is_empty(), "刮下符文贴纸也不会返还工作包")
	check(not main._can_drop_emblem_on_inspection_card(main._inspection_card_view, Vector2(19, 119), scraper), "原生符文不可刮除")
	check(RuneStickerStyle.get_texture_by_id(&"万能贴纸").get_size() == Vector2(27, 27), "七符文素材保持原生27像素")
	check(RuneStickerStyle.get_animation(0).size() == 14, "GIF保留全部14帧")
	if "--capture" in OS.get_cmdline_user_args():
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-inspection-new.png")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await create_timer(0.3, true).timeout
	check(main._inspection_overlay == null and not paused, "Viewport 分发 Escape 可关闭检视并恢复暂停状态")
	var pattern_labels_restored := true
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_back_row, main.enemy_front_row]:
		for slot: BoardSlot in row.get_squads():
			pattern_labels_restored = pattern_labels_restored and slot.pattern_label.visible
	check(pattern_labels_restored, "关闭检视后恢复小队牌型标签")
	var settlement_slot: BoardSlot = main.front_row.get_squads()[0] if not main.front_row.get_squads().is_empty() else null
	if settlement_slot != null and not settlement_slot.is_empty():
		settlement_slot.show_battle_result_statistics({"damage_dealt": 2.0}, false, CardData.ActionType.MELEE)
		var settlement_view := settlement_slot.card_view
		var settlement_owned := settlement_slot.get_squad_data().get_owned_card(settlement_view.card_data)
		main._open_card_inspection(settlement_view.card_data, settlement_owned, settlement_view)
		await process_frame
		check(not settlement_slot._battle_result_overlay.visible, "结算统计在大卡检视打开时显式隐藏")
		main._close_card_inspection(true)
		check(settlement_slot._battle_result_overlay.visible, "关闭检视后恢复结算统计")
	if not main._is_owned_card_deployed(owned):
		main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
		await process_frame
	var battle_started: bool = main.start_battle(2026, true)
	await process_frame
	if battle_started and not main.battle_controller.player_states.is_empty():
		var tree: SceneTree = main.get_tree()
		var battle_state: BattleSquadState = main.battle_controller.player_states[0]
		var battle_owned: OwnedCard = battle_state.squad_data.get_owned_card(battle_state.squad_data.get_effect_source())
		tree.paused = true
		main._open_card_inspection(battle_owned.card_data, battle_owned)
		var battle_time_before_inspection: float = main.battle_controller.elapsed_seconds
		await create_timer(0.15, true).timeout
		check(tree.paused and is_equal_approx(main.battle_controller.elapsed_seconds, battle_time_before_inspection), "真实战斗检视暂停战斗时间，并保留打开前的手动暂停状态")
		var close_click := InputEventMouseButton.new()
		close_click.button_index = MOUSE_BUTTON_RIGHT
		close_click.pressed = true
		close_click.position = Vector2(640, 360)
		root.push_input(close_click, true)
		await create_timer(0.3, true).timeout
		check(main._inspection_overlay == null and tree.paused, "Viewport 分发右键可关闭战斗检视并恢复手动暂停状态")
		tree.paused = false
	main.queue_free()
	await process_frame
	print("Inspection interaction failures: ", failures)
	quit(1 if failures else 0)
