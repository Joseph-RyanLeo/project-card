extends "res://tests/service_interaction_revision_20261020_test.gd"

## 复用正式显示壳、真实鼠标、OwnedCard、工具箱与磁盘交易，验证单笔撤销。
const SAVE := "/private/tmp/project-card-shop-card-undo.json"

func place(owned: OwnedCard) -> void:
	_show_owned(owned)
	main._select_shop_service_card({"kind": &"card", "owned_card": owned})
	await create_timer(0.55).timeout

func click_point(point: Vector2) -> void:
	await _motion(point)
	await _mouse(point, true)
	await _mouse(point, false)

func inventory_entry(id: StringName) -> EmblemLibraryEntry:
	for entry: EmblemLibraryEntry in main.emblem_library._entries:
		if StringName(String(entry.definition.returned_state.instance_id)) == id: return entry
	return null

func wait_fusion(stage: StringName) -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while is_instance_valid(main._emblem_fusion_overlay) and main._emblem_fusion_overlay.stage != stage and Time.get_ticks_msec() < deadline: await process_frame
	check(is_instance_valid(main._emblem_fusion_overlay) and main._emblem_fusion_overlay.stage == stage, "实际合成演出进入" + String(stage))

func wait_fusion_end() -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while is_instance_valid(main._emblem_fusion_overlay) and Time.get_ticks_msec() < deadline: await process_frame
	check(not is_instance_valid(main._emblem_fusion_overlay), "实际合成演出完成或取消")

func verify_immediate_use() -> void:
	main._emblem_recipe_discovery.save_path = "/private/tmp/project-card-undo-immediate-fusion.json"
	for mode: String in ["emblem", "rune", "fusion"]:
		var source := _service_card("immediate_" + mode)
		await place(source)
		var extracted: Array[Dictionary] = [main._tearable_stickers(source)[0], main._tearable_stickers(source)[4]]
		await _click(main._shop_board_view._sticker_host.get_child(0))
		await _click(main._shop_board_view._sticker_host.get_child(4))
		await _click(main._shop_board_view._service_action)
		var gold_after: int = main.run_reward_state.gold
		var target: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"), main.ordinary_shop_service.rng)
		if mode == "fusion": target.set_emblem_slot(0, {"instance_id": "use_target_sword", "emblem_id": "长剑"})
		main._open_card_inspection(target.card_data, target)
		await create_timer(0.35).timeout
		if not main._inspection_library_expanded:
			main._toggle_inspection_library()
			await create_timer(0.35).timeout
		var used := StringName(String(extracted[1 if mode == "rune" else 0].instance_id))
		check(inventory_entry(used).drag_enabled and not main._shop_service_undo.is_empty(), "检视另一张卡时提取结果立即可用，尚未消费仍保留撤销")
		await _click(inventory_entry(used))
		check(not main._click_carry_data.is_empty() and not main._shop_service_undo.is_empty(), "拿起提取贴纸不提前结束撤销")
		await click_point(main._inspection_surface.card_canvas_point(Vector2(50, 50)))
		main._cancel_click_carry()
		await create_timer(0.35).timeout
		check(not main._shop_service_undo.is_empty(), "非法粘贴及取消携带均保留撤销")
		check(main.emblem_library.move_sticker(used, Vector2i(2, 5)) and not main._shop_service_undo.is_empty(), "整理提取贴纸的工具箱格位仍保留撤销")
		var local_point: Vector2 = main._get_emblem_slot_rect(0).get_center()
		if mode == "rune": local_point = main._inspection_card_view.rune_area_position + main._inspection_card_view.rune_slot_size * 0.5
		await _click(inventory_entry(used))
		await click_point(main._inspection_surface.card_canvas_point(local_point))
		if mode == "fusion":
			await wait_fusion(&"awaiting")
			check(not main._shop_service_undo.is_empty(), "查看合成公式时尚未消耗，仍可撤销提取")
			await _click(main._emblem_fusion_overlay._cancel)
			await wait_fusion_end()
			check(not main._shop_service_undo.is_empty() and not main.emblem_library.get_inventory_item(used).is_empty(), "取消实际合成返还材料并保留撤销")
			await _click(inventory_entry(used))
			await click_point(main._inspection_surface.card_canvas_point(local_point))
			await wait_fusion(&"awaiting")
			await _click(main._emblem_fusion_overlay._confirm)
			check(target.emblem_slots[0].get("emblem_id") == &"火焰剑", "确认实际合成将提取材料用于产物")
			await wait_fusion_end()
		else:
			await create_timer(0.45).timeout
			var attached: Dictionary = target.rune_stickers[0] if mode == "rune" else target.emblem_slots[0]
			check(StringName(String(attached.get("instance_id", ""))) == used, "真实点击将提取实例粘贴到另一张卡")
		check(main._shop_service_undo.is_empty() and main.emblem_library.get_inventory_item(used).is_empty() and main._shop_board_view._service_action.text == "出售", "成功使用任一提取贴纸即结束整笔撤销并同步按钮")
		main._undo_shop_card_service()
		check(main.run_reward_state.gold == gold_after and main.owned_card_collection.get_by_instance_id(source.instance_id) == null, "使用后不能撤销来复制原卡或返还金币")
		for state: Dictionary in extracted:
			if StringName(String(state.instance_id)) != used:
				check(main.emblem_library.consume_returned(state), "同笔未使用的其他提取贴纸仍可正常使用")
		main._close_card_inspection(true)
	DirAccess.remove_absolute(main._emblem_recipe_discovery.save_path)

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("服务撤销验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.6).timeout
	main.run_reward_state.gold = 1000
	main._generate_ordinary_shop(false)
	main._toggle_ordinary_shop()
	await create_timer(0.6).timeout
	main._open_shop_card_services()
	var action: Button = main._shop_board_view._service_action
	var original := _service_card("undo_sale")
	await place(original)
	var original_state := original.capture_state()
	var original_index: int = main.owned_card_collection.get_cards().find(original)
	var value: int = main._shop_card_sale_price(original)
	var gold: int = main.run_reward_state.gold
	await _click(action)
	check(action.text == "撤销" and not action.disabled and main.owned_card_collection.get_by_instance_id(original.instance_id) == null and main.run_reward_state.gold == gold + value, "真实点击出售后按钮变为可用撤销，金币与卡牌已成交")
	check(main._shop_board_view._amount.text == "-%d" % value, "出售撤销显示将扣回的金币")
	var other: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"), main.ordinary_shop_service.rng)
	other.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 9)
	main.front_row.add_squad(SquadData.from_owned_card(other), 0)
	main.emblem_library.receive_stickers([{"instance_id": "unrelated_undo", "emblem_id": "火把", "kind": "emblem", "element_sticker": false}])
	var other_state := other.capture_state()
	var inventory: Array = main.emblem_library.get_inventory_state()
	var rng: int = main.ordinary_shop_service.rng.state
	await capture("service-undo-sale")
	await _click(action)
	check(main.owned_card_collection.get_by_instance_id(original.instance_id) == original and original.capture_state() == original_state, "撤销返回同一个原卡实例，保留成长、伤势、符文和全部贴纸")
	check(main.owned_card_collection.get_cards().find(original) == original_index and main.run_reward_state.gold == gold, "原卡回到收藏原次序且收回售卡所得")
	check(main._shop_service_slot._selected_card == original and action.text == "出售" and main._shop_service_undo.is_empty(), "撤销后原卡重回服务槽，可重新选择操作")
	check(other.capture_state() == other_state and main._is_owned_card_deployed(other) and main.emblem_library.get_inventory_state() == inventory and main.ordinary_shop_service.rng.state == rng, "撤销不回滚其他卡、新库存、部署或随机流")
	main._undo_shop_card_service()
	check(main.run_reward_state.gold == gold and main.owned_card_collection.get_by_instance_id(original.instance_id) == original, "已撤销的操作不能再次返还或重复结算")
	for count: int in [1, 2, 3]:
		await place(original)
		var states: Array[Dictionary] = main._tearable_stickers(original)
		var before_card := original.capture_state()
		var before_inventory: Array = main.emblem_library.get_inventory_state()
		gold = main.run_reward_state.gold
		for index: int in count: await _click(main._shop_board_view._sticker_host.get_child(index))
		await _click(action)
		var price: int = [2, 5, 10][count - 1]
		check(action.text == "撤销" and main.run_reward_state.gold == gold - price and main.emblem_library.get_inventory_state().size() == before_inventory.size() + count, "提取%d枚后可撤销，费用与返还贴纸一致" % count)
		check(main._shop_board_view._amount.text == "+%d" % price, "提取撤销显示退还费用")
		main._open_toolbox_inspection()
		await create_timer(0.35).timeout
		for index: int in count:
			var id := StringName(String(states[index].instance_id))
			check(not main.emblem_library.get_inventory_item(id).is_empty(), "提取结果立即进入真实工具箱")
			for entry: EmblemLibraryEntry in main.emblem_library._entries:
				if String(entry.definition.returned_state.instance_id) == String(id):
					check(entry.drag_enabled and entry.self_modulate.a == 1 and not "提取结果暂存" in entry.tooltip_text, "提取结果立即可携带与拖动，不再锁定或压暗")
		if count == 1:
			var unrelated: Dictionary = main.emblem_library.get_inventory_item(&"unrelated_undo")
			check(main.emblem_library.consume_returned(unrelated) and action.text == "撤销" and not main._shop_service_undo.is_empty(), "使用其他库存实例不会结束本笔提取的撤销")
			check(main.emblem_library.return_sticker(unrelated), "归还验收用其他贴纸，保留原库存布局")
		main.emblem_library.set_fusion_busy(true)
		main.emblem_library.set_fusion_busy(false)
		check(main.emblem_library._entries.any(func(entry: EmblemLibraryEntry): return String(entry.definition.returned_state.instance_id) == "unrelated_undo" and entry.drag_enabled), "其他工具箱贴纸仍可正常使用")
		main._close_toolbox_inspection(false)
		if count == 3:
			main.run_save_path = "/private/tmp/project-card-absent-undo-dir/run.json"
			await _click(action)
			check(action.text == "撤销" and main._shop_service_undo.stickers.size() == count and main.run_reward_state.gold == gold - price and main.owned_card_collection.get_by_instance_id(original.instance_id) == null, "提取撤销保存失败仍保留原成交、全部贴纸及重试入口")
			main.run_save_path = SAVE
		await _click(action)
		check(main.owned_card_collection.get_by_instance_id(original.instance_id) == original and original.capture_state() == before_card and main.run_reward_state.gold == gold, "撤销提取%d枚完整还原原卡并退费" % count)
		check(main.emblem_library.get_inventory_state() == before_inventory, "撤销仅收回本次提取贴纸，无重复实例")
		await create_timer(0.55).timeout
	await verify_immediate_use()
	await place(original)
	# 真实写盘失败时保留成交结果及撤销入口，随后可以重试。
	await _click(action)
	gold = main.run_reward_state.gold
	main.run_save_path = "/private/tmp/project-card-absent-undo-dir/run.json"
	await _click(action)
	check(main.owned_card_collection.get_by_instance_id(original.instance_id) == null and main.run_reward_state.gold == gold and action.text == "撤销", "撤销写盘失败不复制卡或金币，保留重试入口")
	main.run_save_path = SAVE
	await _click(action)
	check(main.owned_card_collection.get_by_instance_id(original.instance_id) == original and main._shop_service_undo.is_empty(), "修复写盘路径后可完成同笔撤销")
	await create_timer(0.55).timeout
	await _click(action)
	main._select_shop_service_card({"kind": &"card", "owned_card": null})
	check(action.text == "撤销", "不合法的新卡投放不取消撤销机会")
	await place(other)
	check(action.text == "出售" and main._shop_service_undo.is_empty() and main.owned_card_collection.get_by_instance_id(original.instance_id) == null, "放入新卡结束上一笔撤销机会")
	await _click(action)
	await _click(main._shop_board_view.get_node("ShoppingTab"))
	await _click(main._shop_board_view.get_node("CardServicesTab"))
	check(main._shop_service_undo.is_empty() and action.text == "出售" and action.disabled and main.owned_card_collection.get_by_instance_id(other.instance_id) == null, "离开再进入服务页不会恢复旧撤销")
	var next: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/shieldwall_private.tres"), main.ordinary_shop_service.rng)
	await place(next)
	await _click(action)
	var fusion: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"), main.ordinary_shop_service.rng)
	main._select_exchange_card({"kind": &"card", "owned_card": fusion}, 0)
	check(main._shop_service_undo.is_empty() and action.text == "出售" and action.disabled, "同页融合槽放入新卡也结束旧撤销且同步按钮")
	main._shop_exchange_slots[0].return_card()
	await create_timer(0.2).timeout
	var fill: Array[Dictionary] = []
	for index: int in 27:
		fill.append({"instance_id": "undo_full_%d" % index, "emblem_id": "火把", "kind": "emblem", "element_sticker": false})
	check(main.emblem_library.receive_stickers(fill), "填满28格工具箱以验收临时提取结果")
	var full_card := _service_card("undo_full")
	await place(full_card)
	var full_inventory: Array = main.emblem_library.get_inventory_state()
	var full_state := full_card.capture_state()
	for index: int in [4, 5, 6]: await _click(main._shop_board_view._sticker_host.get_child(index))
	await _click(action)
	check(main.emblem_library.has_dropped_stickers() and main._shop_service_undo.stickers.size() == 3, "工具箱满后提取结果进入临时区域并仍可撤销")
	await _click(action)
	check(main.emblem_library.get_inventory_state() == full_inventory and full_card.capture_state() == full_state and not main.emblem_library.has_dropped_stickers(), "撤销临时结果还原原卡并精确回收三枚元素，无残留或重复")
	var emperor: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/augustus_ironwall.tres"))
	if emperor == null: emperor = main.owned_card_collection.create_card(load("res://resources/cards/augustus_ironwall.tres"), main.ordinary_shop_service.rng)
	var companions: Array[OwnedCard] = []
	for owned: OwnedCard in main.owned_card_collection.get_cards():
		if owned.companion_source_id == emperor.instance_id: companions.append(owned)
	check(companions.size() == 2, "奥古斯都拥有两张真实绑定阵型法术")
	await place(emperor)
	await _click(action)
	check(companions.all(func(owned: OwnedCard): return main.owned_card_collection.get_by_instance_id(owned.instance_id) == null), "出售源卡沿用原绑定衍生卡一同离开规则")
	await _click(action)
	check(main.owned_card_collection.get_by_instance_id(emperor.instance_id) == emperor and companions.all(func(owned: OwnedCard): return main.owned_card_collection.get_by_instance_id(owned.instance_id) == owned), "撤销按原实例同时返还源卡及其两张绑定卡")
	for boundary: String in ["new_card", "shopping_tab"]:
		var unlock_card := _service_card("unlock_" + boundary)
		await place(unlock_card)
		var selected_state: Dictionary = main._tearable_stickers(unlock_card)[0]
		await _click(main._shop_board_view._sticker_host.get_child(0))
		await _click(action)
		check(not main._shop_service_undo.is_empty(), "尚未使用提取结果时仍可撤销")
		if boundary == "new_card":
			await place(fusion)
		else:
			await _click(main._shop_board_view.get_node("ShoppingTab"))
			await _click(main._shop_board_view.get_node("CardServicesTab"))
		check(main._shop_service_undo.is_empty() and main.emblem_library.consume_returned(selected_state), "新卡入槽或离开服务页结束撤销，提取贴纸保持可用")
	var quick := _service_card("undo_quick")
	_show_owned(quick)
	main._select_shop_service_card({"kind": &"card", "owned_card": quick})
	await process_frame
	await _click(action)
	await _click(action)
	await create_timer(0.6).timeout
	check(main._shop_service_slot._selected_card == quick and main._shop_board_view._sticker_host.get_children().all(func(button: Control): return button.position.is_equal_approx(main._shop_board_view.STICKER_CENTERS[button.get_index()] - Vector2(16, 16))), "快速出售再撤销不会让旧贴纸飞行动画干扰新卡面")
	await place(fusion)
	await _click(action)
	check(not main._shop_service_undo.is_empty() and main.owned_card_collection.get_by_instance_id(fusion.instance_id) == null, "读档前确有刚成交且可撤销的交易")
	check(main.load_run_from_path(SAVE) and main._shop_service_undo.is_empty() and main.owned_card_collection.get_by_instance_id(fusion.instance_id) == null, "成交存档可读取且不携带上个界面的临时撤销")
	DirAccess.remove_absolute(SAVE)
	shell.queue_free()
	await process_frame
	print("Shop card service undo: ", assertions, " checks, ", failures, " failures")
	quit(1 if failures else 0)
