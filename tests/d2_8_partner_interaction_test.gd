extends SceneTree

const MainScene = preload("res://scenes/Main.tscn")
var assertions: int = 0
var failures: int = 0
var main: Control
var pointer := Vector2.ZERO

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func motion(point: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - pointer
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	pointer = point
	root.push_input(event, true)
	await process_frame

func button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = pointer
	event.global_position = pointer
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)
	await process_frame

func blade_pointer(card_point: Vector2) -> Vector2:
	var surface: InspectionCardSurface = main._inspection_surface
	var data: Dictionary = main._rune_scraper_drag_data
	var transform := surface.get_global_transform_with_canvas()
	var scale := transform.get_scale()
	var blade_center := (data.get("hit_rect_offset", Vector2.ZERO) as Vector2) / scale + (data.get("hit_rect_size", Vector2.ZERO) as Vector2) / scale * 0.5
	var point := surface.PADDING + card_point - blade_center
	for iteration: int in 8:
		var sample := point + blade_center
		var error := card_point - surface.card_point(sample)
		if error.length() < 0.001:
			break
		var dx := surface.card_point(sample + Vector2.RIGHT) - surface.card_point(sample)
		var dy := surface.card_point(sample + Vector2.DOWN) - surface.card_point(sample)
		point += Transform2D(dx, dy, Vector2.ZERO).affine_inverse() * error
	return transform * point

func _run() -> void:
	root.size = Vector2i(1280, 720)
	main = MainScene.instantiate()
	main.run_save_path = "/private/tmp/project-card-partner-interaction.json"
	root.add_child(main)
	await process_frame
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	main.owned_card_collection = OwnedCardCollection.new()
	var owned: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/militia.tres"))
	owned.resolved_runes.assign([CardData.ElementType.WATER, CardData.ElementType.WOOD, CardData.ElementType.FIRE])
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	main.scraper_count = 3
	main.emblem_library.set_scraper_count(3)
	main._open_card_inspection(owned.card_data, owned)
	await create_timer(0.35).timeout
	if not main._inspection_library_expanded:
		main._toggle_inspection_library()
		await create_timer(0.35).timeout
	main._toggle_rune_scraper_mode()
	check(main._rune_scraper_mode, "进入真实刮刀模式")
	var card: CardView = main._inspection_card_view
	var origin := card.rune_area_position
	await motion(blade_pointer(origin + Vector2(5, 5)))
	await button(true)
	check(main._rune_scrape_locked_index == 0 and main.scraper_count == 2, "首次按下刮符文锁定第一槽且扣一把刀")
	await motion(blade_pointer(origin + Vector2(card.rune_slot_size.x + card.rune_spacing + 5, 5)), true)
	check(owned.get_rune_scraped_pixel_count(1) == 0 and main.scraper_count == 2, "按住跨槽不刮第二枚且不另扣刀")
	await button(false)
	check(main._rune_scrape_locked_index == -1, "松手后解除槽位锁定")
	await button(true)
	check(main._rune_scrape_locked_index == 1 and owned.get_rune_scraped_pixel_count(1) > 0 and main.scraper_count == 1, "重新按下才能刮第二枚")
	await button(false)
	main._finish_rune_scraper_mode()
	check(owned.rune_revealed[0] and owned.rune_revealed[1] and not owned.rune_revealed[2], "退出模式只揭晓本次付费槽")
	check(card.health_label.text.to_int() == owned.card_data.max_health + 2 and card.armor_label.text.to_int() == owned.card_data.armor + 3, "检视卡显示已刮水木符文的实时数值")
	var emblem := {"instance_id": &"partner_bread", "emblem_id": &"面包", "temporary": false}
	check(main.emblem_library.return_sticker(emblem), "把真实面包贴纸加入工具箱")
	var drop_data := {"kind": &"emblem_library", "emblem_id": &"面包", "definition": {"id": &"面包", "returned_state": emblem, "target": "emblem"}}
	var slot: Dictionary
	for candidate: Dictionary in CardSlotLayout.get_slot_definitions(owned.card_data, owned):
		if candidate.kind == CardSlotLayout.Kind.EMBLEM:
			slot = candidate
			break
	var old_health: int = card.health_label.text.to_int()
	check(main._drop_emblem_on_inspection_card(card, slot.position + Vector2(7, 7), drop_data), "把真实面包贴纸放进合法纹章槽")
	check(card.health_label.text.to_int() > old_health and not card._stat_pulse_tweens.is_empty(), "粘贴纹章后动态数值与放大缩回动画生效")
	main._close_card_inspection(true)

	# 收藏原生拖放字典含独立实例身份，真实落点和事务共用现有堆叠入口。
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	var second: OwnedCard = main.owned_card_collection.create_card(owned.card_data)
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	var first_slot: BoardSlot = main.front_row.add_card(owned.card_data, 0, owned)
	await process_frame
	var source_slot: Control = main._find_collection_slot_for_owned_card(second)
	var source_view: CardView = source_slot.get_child(0)
	var drag_data: Dictionary = source_view._build_drag_data(Vector2(50, 68))
	check(drag_data.card_data != first_slot.get_squad_data().get_action_source(), "同名收藏拖放携带另一队员的独立引用")
	var existing: SquadData = first_slot.get_squad_data()
	var result := existing.duplicate_squad()
	check(result.insert_card(drag_data.card_data, 1) and result.bind_owned_card(drag_data.card_data, second), "同名卡预览小队可合法构建")
	drag_data["drop_intent"] = {"operation": &"merge_card", "target_slot": first_slot, "result_squad": result, "card_index": 1}
	check(main._transfer_drop_intent(drag_data, main.front_row), "真实同名拖放事务成功")
	check(first_slot.get_squad_data().get_card_count() == 2 and first_slot.get_squad_data().get_vitals_source_instance() == second, "真实小队保留两个同名独立实例")
	main.ordinary_shop_open = true
	var before_gold: int = main.run_reward_state.gold
	main._execute_shop_sale(second.instance_id, main._shop_card_sale_price(second))
	check(main.owned_card_collection.get_by_instance_id(second.instance_id) != null and main.run_reward_state.gold == before_gold, "出售服务拒绝未拆队的成员")
	var member := first_slot.get_squad_data().get_card_data_for_owned_instance(second.instance_id)
	main.front_row.remove_card_from_squad(first_slot, member)
	var price: int = main._shop_card_sale_price(second)
	main._execute_shop_sale(second.instance_id, price)
	check(main.owned_card_collection.get_by_instance_id(second.instance_id) == null and main.run_reward_state.gold == before_gold + price, "拆队后出售只移除目标实例并发放金币")
	check(main.owned_card_collection.get_by_instance_id(owned.instance_id) == owned, "出售同名卡不移除另一实例")
	main.queue_free()
	await process_frame
	print("合作伙伴交互反馈专项：%d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
