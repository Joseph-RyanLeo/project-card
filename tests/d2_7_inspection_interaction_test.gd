extends SceneTree

const StickerInventory = preload("res://scripts/data/emblem_sticker_inventory.gd")
const MainScript = preload("res://scripts/main.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)


func _pointer_for_blade_center(surface: InspectionCardSurface, data: Dictionary, card_point: Vector2) -> Vector2:
	var transform := surface.get_global_transform_with_canvas()
	var scale := transform.get_scale()
	var offset := (data.get("hit_rect_offset", Vector2.ZERO) as Vector2) / scale
	var hit_size := (data.get("hit_rect_size", Vector2.ZERO) as Vector2) / scale
	var blade_center_offset := offset + hit_size * 0.5
	var surface_point := surface.PADDING + card_point - blade_center_offset
	# 倾斜是透视投影；在当前点迭代求逆，不能用左上角的仿射近似定位整张卡。
	for _iteration: int in 8:
		var sample_point := surface_point + blade_center_offset
		var projected := surface.card_point(sample_point)
		var error := card_point - projected
		if error.length() < 0.001:
			break
		var dx := surface.card_point(sample_point + Vector2.RIGHT) - projected
		var dy := surface.card_point(sample_point + Vector2.DOWN) - projected
		surface_point += Transform2D(dx, dy, Vector2.ZERO).affine_inverse() * error
	return transform * surface_point


func _push_motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)
	await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.run_save_path = "/private/tmp/project-card-d2-7-gold-command-test.json"
	var original_gold: int = main.run_reward_state.gold
	main._on_developer_console_command_submitted("设置金币数 9007199254740991")
	check(main.run_reward_state.gold == 9007199254740991, "中文金币命令接受可精确保存的最大非负整数")
	var max_gold_checkpoint: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(main.run_save_path))
	check(int(max_gold_checkpoint.get("reward_state", {}).get("gold", -1)) == 9007199254740991, "最大金币数写入JSON仍保持精确")
	for invalid_gold: String in ["9007199254740992", "9223372036854775808", "-1", "1.5", "abc"]:
		main._on_developer_console_command_submitted("gold set " + invalid_gold)
		check(main.run_reward_state.gold == 9007199254740991, "非法金币输入%s不会更改余额" % invalid_gold)
	main._on_developer_console_command_submitted("gold set 0")
	check(main.run_reward_state.gold == 0, "英文金币命令接受零")
	main._on_developer_console_command_submitted("gold set %d" % original_gold)
	main.scraper_count = 4
	main.emblem_library.set_scraper_count(main.scraper_count)
	main.emblem_library.return_sticker({"instance_id": &"interaction_torch", "emblem_id": &"火把"})
	main.emblem_library.return_sticker({"instance_id": &"interaction_light", "emblem_id": &"光贴纸", "element": CardData.ElementType.LIGHT})
	main._on_developer_console_command_submitted("wound add 中毒Ⅰ")
	var owned: OwnedCard
	var source: CardView
	for slot: Control in main._get_collection_card_slots():
		var candidate: OwnedCard = slot.get_meta("owned_card", null)
		if candidate != null and candidate.card_data.card_type == CardData.CardType.MINION and candidate.card_data.runes.size() == 3 and CardData.ElementType.FIRE not in candidate.resolved_runes:
			owned = candidate
			source = slot.get_child(0)
			break
	check(main.emblem_library.position.x + main.emblem_library.size.x < 216, "横放工具箱常规状态沿用收藏书左侧边界")
	main._open_card_inspection(owned.card_data, owned, source)
	await process_frame
	var hidden_rune_index := -1
	var scrapers_before_reveal: int = main.scraper_count
	for rune_index: int in owned.rune_revealed.size():
		if not owned.rune_revealed[rune_index] and owned.rune_stickers[rune_index].is_empty() and owned.get_effective_rune(rune_index) != CardData.ElementType.FIRE:
			hidden_rune_index = rune_index
			break
	var surface = main._inspection_surface
	var first_scale: Vector2 = surface.scale
	await create_timer(0.3).timeout
	main._toggle_inspection_library()
	await create_timer(0.3).timeout
	check(not first_scale.is_equal_approx(surface.scale), "打开检视逐渐放大而非瞬移")
	check(surface.scale == Vector2(4, 4), "整卡合成显示达到4倍原生尺寸")
	check(surface.position.is_equal_approx(main._inspection_card_position(true)), "检视卡牌展开时按可见卡框目标位置让位")
	check(main.emblem_library.position.x + main.emblem_library.size.x * main.emblem_library.scale.x == 812.0, "展开工具箱右侧边界按固定4×尺寸定位")
	check(main._inspection_carry_layer.get_parent() == main._inspection_overlay and main._inspection_carry_layer.z_index <= 4096, "检视携带预览使用前景层且z-index合法")
	var visible_pattern_labels_hidden := true
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_back_row, main.enemy_front_row]:
		for slot: BoardSlot in row.get_squads():
			visible_pattern_labels_hidden = visible_pattern_labels_hidden and not slot.pattern_label.visible
	check(visible_pattern_labels_hidden, "打开检视时临时隐藏四排小队牌型标签")
	surface.force = Vector2.ZERO
	check(surface.card_point(surface.PADDING + Vector2(5, 46)).distance_to(Vector2(5, 46)) < 0.01, "无倾斜时逆投影准确落在卡面槽位")
	var cover_slot: Control = main._inspection_card_view.rune_row.get_child(hidden_rune_index)
	var rune_under_cover := cover_slot.get_child(0) as TextureRect
	var rarity_cover := cover_slot.get_child(1) as TextureRect
	var actual_element := owned.get_effective_rune(hidden_rune_index)
	check(
		rune_under_cover.texture == main._inspection_card_view._get_rune_texture(actual_element)
		and rune_under_cover.tooltip_text.is_empty()
		and rarity_cover.texture.resource_path == "res://assets/card_ui/rune_covers/rarity_%s.png" % ["i", "ii", "iii", "iv", "v"][int(owned.card_data.rarity)],
		"真实非火元素绘在对应品级遮罩下且未揭晓时不暴露提示"
	)
	var battle_masked_indices: Array[int] = [hidden_rune_index]
	main._inspection_card_view.set_battle_masked_runes(battle_masked_indices)
	var battle_masked_slot: Control = main._inspection_card_view.rune_row.get_child(hidden_rune_index)
	check(
		battle_masked_slot.get_child_count() == 1
		and not (battle_masked_slot.get_child(0) as TextureRect).visible,
		"战斗遮蔽符文不会被未知符文覆盖层重新显露"
	)
	main._inspection_card_view.clear_battle_masked_runes()
	cover_slot = main._inspection_card_view.rune_row.get_child(hidden_rune_index)
	rune_under_cover = cover_slot.get_child(0) as TextureRect
	rarity_cover = cover_slot.get_child(1) as TextureRect
	var initial_emblem_position := _first_empty_emblem_position(owned)
	var initial_emblem_index: int = main._find_empty_emblem_slot_at(initial_emblem_position)
	var torch_state: Dictionary = main.emblem_library.get_inventory_item(&"interaction_torch")
	var torch_definition := _inventory_definition(main, &"火把", torch_state)
	var emblem := {"kind": &"emblem_library", "emblem_id": &"火把", "definition": torch_definition}
	check(main._drop_emblem_on_inspection_card(main._inspection_card_view, initial_emblem_position, emblem), "普通纹章可真实粘贴")
	check(initial_emblem_index >= 0 and not owned.emblem_slots[initial_emblem_index].is_empty(), "粘贴后纹章保存在对应实例槽")
	var scraper_control: TextureRect = main.emblem_library._scraper
	var scraper_data: Dictionary = scraper_control._build_drag_data(scraper_control.blade_point, false)
	await _click(scraper_control.get_global_rect().get_center())
	var emblem_pointer := _pointer_for_blade_center(main._inspection_surface, scraper_data, initial_emblem_position + Vector2(8, 8))
	await _click(emblem_pointer)
	check(owned.emblem_slots[initial_emblem_index].is_empty() and main.emblem_library.get_inventory_item(&"interaction_torch").is_empty(), "真实点击刀头移除纹章且不返还工作包")
	check(main.scraper_count == scrapers_before_reveal - 1, "移除纹章只消耗一把刮刀")
	var rune_state: Dictionary = main.emblem_library.get_inventory_item(&"interaction_light")
	var rune_definition := _inventory_definition(main, &"光贴纸", rune_state)
	var rune := {"kind": &"emblem_library", "emblem_id": &"光贴纸", "definition": rune_definition}
	var original := owned.get_effective_rune(0)
	var shared_definition_rune := owned.card_data.runes[0]
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
	check(not main._can_drop_emblem_on_inspection_card(main._inspection_card_view, wound_position, {"kind": &"emblem_library", "emblem_id": &"火把", "definition": _inventory_definition(main, &"火把", {})}), "纹章不能投到伤势槽")
	var wound_entry: EmblemLibraryEntry
	for entry: EmblemLibraryEntry in main.emblem_library._entries:
		if String(entry.definition.get("status_kind", "emblem")) == "wound":
			wound_entry = entry
			break
	var wound_item := wound_entry._build_drag_data(wound_entry.size * 0.5, false) if wound_entry != null else {}
	var wound_state: Dictionary = (wound_item.get("definition", {}) as Dictionary).get("returned_state", {})
	check(not wound_state.is_empty(), "控制台伤势条目绑定真实库存实例")
	check(not main._can_drop_emblem_on_inspection_card(main._inspection_card_view, emblem_position, wound_item), "伤势不能投到纹章槽")
	var original_emblems := owned.emblem_slots.duplicate(true)
	var original_wounds := owned.wound_slots.duplicate(true)
	for slot_index: int in owned.emblem_slots.size():
		if owned.emblem_slots[slot_index].is_empty():
			owned.set_emblem_slot(slot_index, {"instance_id": StringName("test_emblem_%d" % slot_index), "emblem_id": &"火把", "temporary": false})
	var full_emblems := owned.emblem_slots.duplicate(true)
	var rune_landing: Dictionary = main._get_inspection_drop_preview(main._inspection_card_view, Vector2(19, 119), rune)
	var expected_rune_landing: Vector2 = main._inspection_card_view.rune_area_position + (main._inspection_card_view.rune_slot_size - Vector2(27, 27)) * 0.5
	check(main._can_drop_emblem_on_inspection_card(main._inspection_card_view, Vector2(19, 119), rune) and rune_landing.position.is_equal_approx(expected_rune_landing), "纹章槽全部占用时，空符文位仍可投放元素贴纸且虚影指向符文区")
	check(main._drop_emblem_on_inspection_card(main._inspection_card_view, Vector2(19, 119), rune), "符文贴纸可以贴到元素槽")
	check(owned.get_effective_rune(0) == CardData.ElementType.LIGHT and owned.card_data.runes[0] == shared_definition_rune, "符文替换只更新实例、不改底层原符文")
	check(owned.emblem_slots == full_emblems and owned.wound_slots == original_wounds, "符文贴纸不会占用纹章槽或伤势槽")
	check(not main._can_drop_emblem_on_inspection_card(main._inspection_card_view, Vector2(19, 119), rune) and not main._drop_emblem_on_inspection_card(main._inspection_card_view, Vector2(19, 119), rune), "同一位置不能覆盖已有符文贴纸")
	owned.emblem_slots.assign(original_emblems)
	var wound_index: int = main._find_empty_wound_slot_at(wound_position)
	check(main._drop_emblem_on_inspection_card(main._inspection_card_view, wound_position, wound_item) and wound_index >= 0 and not owned.wound_slots[wound_index].is_empty() and owned.emblem_slots == original_emblems, "伤势只写入伤势槽，不写入纹章槽")
	check(main.emblem_library.get_inventory_item(StringName(String(wound_state.instance_id))).is_empty(), "伤势粘贴后从同一工具箱移除真实实例")
	var scrapers_before_wound: int = main.scraper_count
	var wound_pointer := _pointer_for_blade_center(main._inspection_surface, scraper_data, wound_position + Vector2(8, 8))
	await _click(wound_pointer)
	check(owned.wound_slots[wound_index].is_empty() and main.scraper_count == scrapers_before_wound - 1, "真实刀头点击移除伤势并消耗一把刮刀")
	check(not main._can_drop_emblem_on_inspection_card(main._inspection_card_view, wound_position, wound_item), "已占用的伤势槽拒绝再次投放")
	owned.wound_slots.assign(original_wounds)
	main._on_developer_console_command_submitted("wound add 中毒Ⅰ")
	var saved_wound: Dictionary = main.emblem_library.get_inventory_state().back()
	check(main.save_run_to_path("/private/tmp/project-card-sticker-save.json") == OK, "后贴符文进入JSON保存")
	check(FileAccess.get_file_as_string("/private/tmp/project-card-sticker-save.json").contains("rune_stickers"), "存档含独立符文贴纸字段")
	var loaded_checkpoint: Dictionary = main.run_save_service.load_checkpoint("/private/tmp/project-card-sticker-save.json").checkpoint
	var loaded_bag: Dictionary = loaded_checkpoint.get("developer_sticker_bag", {})
	var round_trip := StickerInventory.new()
	var round_trip_ok: bool = round_trip.restore(loaded_bag.get("items", []))
	var restored_wound: Dictionary = round_trip.get_item(StringName(String(saved_wound.get("instance_id", ""))))
	check(
		round_trip_ok
		and restored_wound.get("kind") == "wound"
		and restored_wound.get("wound_id") == saved_wound.get("wound_id")
		and restored_wound.get("level") == saved_wound.get("level")
		and restored_wound.get("grid_x") == saved_wound.get("grid_x")
		and restored_wound.get("grid_y") == saved_wound.get("grid_y"),
		"JSON保存再读取保留伤势实例身份、类型、等级与占格坐标"
	)
	var rune_center: Vector2 = main._inspection_card_view.rune_area_position + main._inspection_card_view.rune_slot_size * 0.5
	await _click(scraper_control.get_global_rect().get_center())
	var rune_pointer := _pointer_for_blade_center(main._inspection_surface, scraper_data, rune_center)
	await _click(rune_pointer)
	check(owned.get_effective_rune(0) == original and owned.rune_revealed[0] == revealed, "真实刀头移除符文贴纸后恢复底层符文及揭晓状态")
	check(main.emblem_library.get_inventory_item(&"interaction_light").is_empty(), "刮下符文贴纸也不会返还工作包")
	var exit_scraper := InputEventKey.new()
	exit_scraper.keycode = KEY_ESCAPE
	exit_scraper.pressed = true
	root.push_input(exit_scraper, true)
	await process_frame
	check(not main._rune_scraper_mode, "Esc退出刮刀模式后恢复检视键盘操作")
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
	var remembered_expanded: bool = main._last_minion_inspection_library_expanded
	check(remembered_expanded, "关闭随从检视时记住工具箱展开状态")
	var original_library_parent: Node = main.emblem_library.get_parent()
	var original_library_position: Vector2 = main.emblem_library.position
	var original_library_scale: Vector2 = main.emblem_library.scale
	var spell_owned: OwnedCard
	for candidate: OwnedCard in main.owned_card_collection.get_cards():
		if candidate.card_data.card_type == CardData.CardType.SPELL:
			spell_owned = candidate
			break
	if spell_owned != null:
		main._open_card_inspection(spell_owned.card_data, spell_owned)
		await create_timer(0.3).timeout
		check(
			not main._inspection_has_library_toolbox
			and main._inspection_library_toggle == null
			and main.emblem_library.get_parent() == original_library_parent
			and main.emblem_library.position == original_library_position
			and main.emblem_library.scale == original_library_scale,
			"法术检视不重挂、不缩放、不移动工具箱，也不创建收展按钮"
		)
		main._close_card_inspection(true)
		check(
			main._last_minion_inspection_library_expanded == remembered_expanded,
			"关闭法术检视不会覆盖随从检视的展开记忆"
		)
		main._open_card_inspection(owned.card_data, owned)
		await process_frame
		check(main._inspection_library_expanded, "法术检视后打开随从仍沿用此前展开状态")
		main._toggle_inspection_library()
		await create_timer(0.3).timeout
		main._close_card_inspection(true)
		check(not main._last_minion_inspection_library_expanded, "关闭收起状态的随从检视会记住收起")
		main._open_card_inspection(spell_owned.card_data, spell_owned)
		await process_frame
		main._close_card_inspection(true)
		main._open_card_inspection(owned.card_data, owned)
		await process_frame
		check(not main._inspection_library_expanded, "连续非随从检视后，下一张随从仍沿用收起状态")
		main._close_card_inspection(true)
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
	main._set_battle_target_priority_display_enabled(true)
	if not main._is_owned_card_deployed(owned):
		main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	await process_frame
	await process_frame
	main._refresh_preparation_effect_preview()
	await process_frame
	var prepared_priority_slot: BoardSlot
	for candidate_slot: BoardSlot in main.front_row.get_squads():
		if candidate_slot.get_squad_data().get_owned_card(owned.card_data) == owned:
			prepared_priority_slot = candidate_slot
			break
	var prepared_priority_weight := -1
	for state: BattleSquadState in main.battle_controller.player_states:
		if state.squad_data.get_owned_card(owned.card_data) == owned:
			prepared_priority_weight = main.battle_controller.get_effective_target_weight(state)
			break
	check(
		prepared_priority_slot != null
		and prepared_priority_slot.target_priority_badge.visible
		and prepared_priority_slot.target_priority_badge.text == str(prepared_priority_weight)
		and prepared_priority_weight >= 0,
		"准备阶段部署及预览重建后显示小队级有效受击优先级"
	)
	if prepared_priority_slot != null and "--capture-priority" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-target-priority.png")
	var battle_started: bool = main.start_battle(2026, true)
	await process_frame
	if battle_started and not main.battle_controller.player_states.is_empty():
		var priority_state: BattleSquadState = main.battle_controller.player_states[0]
		var priority_slot := main._battle_state_slots[priority_state] as BoardSlot
		var priority_view: CardView = priority_slot.get_card_view(priority_state.squad_data.get_action_source())
		check(
			priority_slot.target_priority_badge.visible
			and priority_slot.target_priority_badge.text == str(
				main.battle_controller.get_effective_target_weight(priority_state)
			),
			"进入真实战斗后小队标签显示控制器计算的有效受击权重"
		)
		main._set_battle_target_priority_display_enabled(false)
		check(not priority_slot.target_priority_badge.visible, "关闭开关立即隐藏小队受击优先级标签")
		if priority_view != null:
			priority_view._mouse_hovered = true
			priority_view._refresh_priority_label()
			check(priority_view.priority_label.visible, "关闭常驻显示后仍能通过悬停查看卡牌优先级")
			priority_view._mouse_hovered = false
			priority_view._refresh_priority_label()
		var tree: SceneTree = main.get_tree()
		var battle_state: BattleSquadState = main.battle_controller.player_states[0]
		var battle_owned: OwnedCard = battle_state.squad_data.get_owned_card(battle_state.squad_data.get_effect_source())
		tree.paused = true
		main._open_card_inspection(battle_owned.card_data, battle_owned)
		var battle_time_before_inspection: float = main.battle_controller.elapsed_seconds
		await create_timer(0.15, true).timeout
		check(tree.paused and is_equal_approx(main.battle_controller.elapsed_seconds, battle_time_before_inspection), "真实战斗检视暂停战斗时间，并保留打开前的手动暂停状态")
		await _click(main._inspection_library_toggle.get_global_rect().get_center())
		await create_timer(0.3, true).timeout
		check(tree.paused and main._inspection_library_expanded, "战斗暂停检视时露边控件仍能展开工具箱")
		await _click(main._inspection_library_toggle.get_global_rect().get_center())
		await create_timer(0.3, true).timeout
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


func _inventory_definition(main, emblem_id: StringName, state: Dictionary) -> Dictionary:
	for definition: Dictionary in main.emblem_library.get_definitions():
		if StringName(String(definition.get("id", ""))) == emblem_id:
			var result := definition.duplicate(true)
			result["returned_state"] = state.duplicate(true)
			return result
	return {}


func _first_empty_emblem_position(owned: OwnedCard) -> Vector2:
	for definition: Dictionary in CardSlotLayout.get_slot_definitions(owned.card_data, owned):
		if int(definition.get("kind", -1)) != CardSlotLayout.Kind.EMBLEM:
			continue
		var index := int(definition.get("storage_index", -1))
		if index >= 0 and index < owned.emblem_slots.size() and owned.emblem_slots[index].is_empty():
			return definition.get("position", Vector2.ZERO) + Vector2(7.0, 7.0)
	return Vector2.INF


func _click(position: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.position = position
	down.global_position = position
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	root.push_input(down, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.position = position
	up.global_position = position
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	root.push_input(up, true)
	await process_frame
