extends "res://tests/service_origin_revision_20261021_test.gd"

func _run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("装备收藏复用检查超时"); quit(2))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-equipment-collection-reuse.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.5).timeout
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	main.owned_card_collection = OwnedCardCollection.new()
	var first: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
	var second: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/shieldwall_private.tres"))
	var item: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/tower_shield.tres"))
	var other: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/field_beer_machine.tres"))
	for owned: OwnedCard in [first, second, item, other]: owned.is_new = false
	other.rune_revealed.assign([false, true, false])
	other.resolved_runes.assign([CardData.ElementType.FIRE, CardData.ElementType.WATER, CardData.ElementType.WOOD])
	for index: int in 68:
		main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
	var first_slot: BoardSlot = main.back_row.add_squad(SquadData.from_owned_card(first), 0)
	var second_slot: BoardSlot = main.back_row.add_squad(SquadData.from_owned_card(second), 1)
	main._sync_legacy_collection_cards()
	main.current_collection_page = 0
	main._build_collection_cards()
	main.set_world_view(main.WorldView.COLLECTION, false)
	await create_timer(0.3).timeout
	var other_slot: Control = main._find_collection_slot_for_owned_card(other)
	var other_view: CardView = other_slot.get_child(0)
	var other_cover: Node = other_view.rune_row.get_child(0).get_node("RuneRevealCover")
	var original_state := other.capture_state()
	var source_slot: Control = main._find_collection_slot_for_owned_card(item)
	await native_pick(source_slot.get_child(0))
	var drop_point: Vector2 = first_slot.get_card_views()[0].get_global_transform_with_canvas() * Vector2(45, 60)
	await _motion(drop_point, true)
	await create_timer(0.2).timeout
	await _mouse(drop_point, false)
	await create_timer(0.4).timeout
	check(first_slot.get_squad_data().get_equipped_item() == item, "真实鼠标松手将原物品实例绑定到随从")
	check(main._find_collection_slot_for_owned_card(other) == other_slot and other_slot.get_child(0) == other_view, "装备提交后未变化的收藏槽与卡面不重建")
	check(other_view.rune_row.get_child(0).get_node("RuneRevealCover") == other_cover, "未变化卡保留同一未揭晓符文覆盖层")
	check(other.capture_state() == original_state and not other_view._is_display_rune_known(0) and other_view._is_display_rune_known(1), "复用不会改变实例或泄露隐藏符文")
	var item_ghost: Control = main._find_collection_slot_for_owned_card(item)
	check(item_ghost.get_meta("is_deployed_ghost", false) and not item_ghost.get_child(0)._drag_enabled, "发生部署变化的装备收藏位仍切换为不可拖动虚影")
	check(other_view._drag_enabled and other_view.click_carry_requested.is_connected(main._on_click_carry_requested), "复用卡牌保留原拖动与点击携带连接")
	var indicator: Control = first_slot.get_equipment_indicator()
	var start := indicator.get_global_rect().get_center()
	await _motion(start)
	await _mouse(start, true)
	await _motion(start + Vector2(30, 4), true)
	check(shell.internal_viewport.gui_is_dragging(), "真实装备指示物能从战场再次拖起")
	drop_point = second_slot.get_card_views()[0].get_global_transform_with_canvas() * Vector2(45, 60)
	await _motion(drop_point, true)
	await _mouse(drop_point, false)
	await create_timer(0.4).timeout
	check(first_slot.get_squad_data().get_equipped_item() == null and second_slot.get_squad_data().get_equipped_item() == item, "装备跨小队移动仍保持唯一实例归属")
	check(main._find_collection_slot_for_owned_card(item) == item_ghost and main._find_collection_slot_for_owned_card(other) == other_slot, "部署状态未改变时，装备虚影与其他收藏卡都复用")
	shell.queue_free()
	await process_frame
	print("装备收藏复用：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
