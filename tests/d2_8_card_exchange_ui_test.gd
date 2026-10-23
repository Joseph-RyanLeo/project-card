extends SceneTree

## 正式显示壳与真实鼠标输入验证定向采购、三卡置换和存档事务。
const DISPLAY = preload("res://scenes/GameDisplay.tscn")
var shell: Control
var main: Control
var assertions := 0
var failures := 0
var pointer := Vector2.ZERO

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func motion(point: Vector2, held: bool = false) -> void:
	var outer: Vector2 = shell.render_container.get_global_transform_with_canvas() * point
	var event := InputEventMouseMotion.new()
	event.position = outer
	event.global_position = outer
	event.relative = outer - pointer
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	pointer = outer
	Input.warp_mouse(outer)
	root.push_input(event, true)
	await process_frame

func button(point: Vector2, pressed: bool, index: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * point
	event.global_position = event.position
	event.button_index = index
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and index == MOUSE_BUTTON_LEFT else 0
	Input.warp_mouse(event.position)
	root.push_input(event, true)
	await process_frame

func click(point: Vector2, index: int = MOUSE_BUTTON_LEFT) -> void:
	await motion(point)
	await button(point, true, index)
	await button(point, false, index)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/project-card-economy-%s.png" % label)

func show_page_for(owned: OwnedCard) -> void:
	var displayed: Array = main.get_displayed_collection_cards()
	for index: int in displayed.size():
		if main._get_owned_card_for_collection_index(displayed, index) == owned:
			main.current_collection_page = index / main.COLLECTION_SLOTS_PER_PAGE
			main._build_collection_cards()
			return

func add_materials(rarity: int) -> Array[OwnedCard]:
	var candidates: Array[CardData] = []
	for card: CardData in main._get_shop_card_definitions():
		if card.card_type == CardData.CardType.MINION and int(card.rarity) == rarity and not card.is_derived and card.is_available: candidates.append(card)
	var result: Array[OwnedCard] = []
	for index: int in 3: result.append(main.owned_card_collection.create_card(candidates[index % candidates.size()], main.ordinary_shop_service.rng))
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	return result

func select_materials(materials: Array[OwnedCard]) -> void:
	for index: int in materials.size():
		show_page_for(materials[index])
		main._shop_exchange_slots[index]._drop_data(Vector2.ZERO, {"kind": &"card", "owned_card": materials[index]})

func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("采购置换专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-economy-ui-save.json"
	root.add_child(shell)
	shell.apply_display_mode(0)
	await create_timer(0.35).timeout
	main.run_reward_state.gold = 200
	main._toggle_ordinary_shop()
	await create_timer(0.4).timeout
	await click(main._shop_procurement_button.get_global_rect().get_center())
	check(main._shop_procurement_action == CardData.ActionType.MELEE and main._shop_action_filters.is_visible_in_tree() and main._shop_action_filters.get_child_count() == 5, "真实点击定向采购显示五种行动页")
	var heal_tab: Button = main._shop_action_filters.get_child(CardData.ActionType.HEAL)
	await click(heal_tab.get_global_rect().get_center())
	check(main._shop_procurement_action == CardData.ActionType.HEAL, "真实点击治疗页切换货源")
	var pack_index := -1
	var single_indices: Array[int] = []
	for index: int in main.ordinary_shop_service.offers.size():
		var offer: Dictionary = main.ordinary_shop_service.offers[index]
		if int(offer.get("procurement_action", -1)) != CardData.ActionType.HEAL: continue
		if offer.kind == "card_pack": pack_index = index
		elif offer.kind == "single_card": single_indices.append(index)
	var art: Control = main._shop_offer_art(pack_index)
	check(art != null and art.get_node("ActionIcon").texture == load("res://assets/actions/action_heal.png") and art.get_node("ActionIcon").size == Vector2(75, 84), "定向治疗小包使用原素材3倍图标与小包外形")
	await capture("procurement")
	var tile: Control = main.ordinary_shop_offer_list.find_child("ShopOffer_%d" % pack_index, true, false)
	await click(tile._visual.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await create_timer(0.3).timeout
	check(is_instance_valid(main._inspection_overlay) and main._inspection_read_only and main._inspection_overlay.get_node("InspectionPackName").text == "治疗定向小包", "真实右键定向包装只读检视，名称正确")
	main._close_card_inspection(true)
	await process_frame
	var before_count: int = main.owned_card_collection.size()
	var before_gold: int = main.run_reward_state.gold
	main._on_ordinary_shop_offer_pressed(pack_index)
	await create_timer(1.8).timeout
	check(main.owned_card_collection.size() == before_count + 3 and main.run_reward_state.gold == before_gold - 12 and main.ordinary_shop_service.offers[pack_index].sold, "正式开包只扣12金币，增加3张并标为售出")
	var all: Array = main.owned_card_collection.get_cards()
	check(all.slice(all.size() - 3).all(func(card: OwnedCard): return card.resolved_action_type == CardData.ActionType.HEAL), "实际获取的三张卡行动方向为治疗")
	for index: int in single_indices:
		var offer: Dictionary = main.ordinary_shop_service.offers[index]
		before_count = main.owned_card_collection.size()
		main._on_ordinary_shop_offer_pressed(index)
		check(main.owned_card_collection.size() == before_count + 1 and main.owned_card_collection.get_cards().back().resolved_action_type == CardData.ActionType.HEAL, "明单与暗单实际购买方向一致")
	main._close_shop_card_services()
	main.set_world_view(main.WorldView.COLLECTION, false)
	var materials := add_materials(CardData.Rarity.I)
	main._open_shop_exchange()
	await process_frame
	check(main._shop_exchange_slots.size() == 3 and main._shop_exchange_slots.all(func(slot: Control): return slot._empty_outline.visible), "置换显示三个真实空槽")
	show_page_for(materials[0])
	await process_frame
	var original_slot: Control = main._find_collection_slot_for_owned_card(materials[0])
	var original: CardView = original_slot.get_child(0)
	await click(original.get_global_rect().get_center())
	await click(main._shop_exchange_slots[0].get_global_rect().get_center())
	check(main._shop_exchange_slots[0]._card_view == original and main._find_collection_slot_for_owned_card(materials[0]) == null and not original.is_snapshot_mode(), "实际单击携带放入置换槽，原卡面移入且来源为空")
	check(not main._shop_exchange_slots[1]._can_drop_data(Vector2.ZERO, {"kind": &"card", "owned_card": materials[0]}), "不能把同一实例重复放入两个材料槽")
	var higher: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/shieldwall_private.tres"))
	check(main._shop_exchange_slots[1]._can_drop_data(Vector2.ZERO, {"kind": &"card", "owned_card": higher}), "不同品级可入槽，确认时再检查融合资格")
	main._sync_legacy_collection_cards()
	var initial_page: int = main.current_collection_page
	var other_page: int = (initial_page + 1) % main.get_collection_spread_count()
	check(other_page != initial_page, "真实收藏有多页供翻页验证")
	main.turn_collection_page(other_page)
	await create_timer(0.4).timeout
	check(main._shop_exchange_slots[0]._card_view == original and is_instance_valid(original) and original.get_owned_card() == materials[0], "翻到其他收藏页仍保持同一个槽内卡面")
	main.turn_collection_page(initial_page)
	await create_timer(0.4).timeout
	original_slot = main._find_collection_slot_for_owned_card(materials[0])
	check(original_slot == null and main._shop_exchange_slots[0]._card_view == original, "翻回来源页不留空位，真实卡仍在槽内")
	var source: Vector2 = original.get_global_rect().get_center()
	await motion(source)
	await button(source, true)
	await motion(source + Vector2(35, 3), true)
	check(shell.internal_viewport.gui_is_dragging(), "置换槽内卡面支持原生长按拖动")
	await motion(Vector2(1000, 620), true)
	await button(Vector2(1000, 620), false)
	await create_timer(0.2).timeout
	check(main._shop_exchange_ids[0].is_empty() and main._find_collection_slot_for_owned_card(materials[0]) != null, "原生拖回收藏清空材料槽且保留原实例")
	# 新产物不继承材料的贴纸和成长，战场上的装备归还收藏。
	materials[0].apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 8)
	materials[0].set_emblem_slot(0, {"instance_id": &"economy_material_bread", "emblem_id": &"面包", "temporary": false})
	var equipment: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/coarse_bandage.tres"))
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	var squad := SquadData.from_owned_card(materials[0])
	check(squad.equip_item(equipment), "材料实际装备物品")
	main.front_row.add_squad(squad, 0)
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	select_materials(materials)
	await process_frame
	before_count = main.owned_card_collection.size()
	before_gold = main.run_reward_state.gold
	check(not main._shop_exchange_confirm.disabled and main._shop_exchange_slots.all(func(slot: Control): return slot._card_view != null), "三张全部显示才可确认，未提前消耗材料")
	await capture("exchange-ready")
	await click(main._shop_exchange_confirm.get_global_rect().get_center())
	await process_frame
	var awarded: OwnedCard = main.owned_card_collection.get_cards().back()
	check(main.owned_card_collection.size() == before_count - 2 and main.run_reward_state.gold == before_gold and awarded.card_data.rarity == CardData.Rarity.II, "真实确认按钮免费消耗三张I级，获得一张II级")
	check(materials.all(func(card: OwnedCard): return main.owned_card_collection.get_by_instance_id(card.instance_id) == null) and awarded.permanent_growth.is_empty() and awarded.emblem_slots.all(func(state: Dictionary): return state.is_empty()) and awarded.is_new, "材料实例消耗，产物是全新实例，不继承成长与贴纸")
	check(main.front_row.get_squads().is_empty() and main.owned_card_collection.get_by_instance_id(equipment.instance_id) == equipment and not main._is_owned_card_deployed(equipment), "材料宿主撤场，装备实际实例归还收藏")
	check(main.emblem_library.get_inventory_item(&"economy_material_bread").is_empty(), "材料贴纸随卡消耗，没有额外返还")
	check(main._shop_exchange_confirm.disabled and main._shop_exchange_slots.all(func(slot: Control): return slot._card_view == null), "成功后清空三槽并禁止重复确认")
	main._execute_shop_exchange()
	check(main.owned_card_collection.size() == before_count - 2, "重复执行不再产卡")
	var awarded_id := awarded.instance_id
	var rng_after: int = main.ordinary_shop_service.rng.state
	check(main.load_run_from_path(main.run_save_path) and main.owned_card_collection.get_by_instance_id(awarded_id) != null and main.ordinary_shop_service.rng.state == rng_after, "真实磁盘读回保存结果与随机流，不重抽产物")
	main.ordinary_shop_open = true
	main.ordinary_shop_panel.visible = true
	main._open_shop_exchange()
	materials = add_materials(CardData.Rarity.II)
	select_materials(materials)
	var exchange_started := Time.get_ticks_usec()
	main._execute_shop_exchange()
	print("置换确认CPU耗时：%.3f毫秒" % ((Time.get_ticks_usec() - exchange_started) / 1000.0))
	check(main.owned_card_collection.get_cards().back().card_data.rarity == CardData.Rarity.III, "II级三卡可置换III级")
	# 初始调试收藏可能已含所有IV随从；实际出售一张，恢复其合法获得资格。
	for owned: OwnedCard in main.owned_card_collection.get_cards():
		if owned.card_data.card_type == CardData.CardType.MINION and owned.card_data.rarity == CardData.Rarity.IV and owned.card_data.is_available and String(owned.card_data.pack_id) in main.ordinary_shop_service.config.allowed_pack_ids:
			main._execute_shop_sale(owned.instance_id, main._shop_card_sale_price(owned))
			break
	materials = add_materials(CardData.Rarity.III)
	select_materials(materials)
	check(not main._exchange_candidates().is_empty(), "出售已持有IV随从后重新获得该卡的置换资格")
	var ids: Array = materials.map(func(card: OwnedCard): return card.instance_id)
	var snapshots: Array = materials.map(func(card: OwnedCard): return card.capture_state())
	var rng_before: int = main.ordinary_shop_service.rng.state
	before_count = main.owned_card_collection.size()
	var disk_before := FileAccess.get_file_as_string(main.run_save_path)
	var save_path: String = main.run_save_path
	main.run_save_path = "/private/tmp/project-card-missing-economy-parent/run.json"
	main._execute_shop_exchange()
	check(main.owned_card_collection.size() == before_count and main.ordinary_shop_service.rng.state == rng_before and main._shop_exchange_ids == ids, "保存失败回退全部材料、槽内选择与随机流")
	check(main._shop_exchange_slots.all(func(slot: Control): return slot._card_view != null) and FileAccess.get_file_as_string(save_path) == disk_before, "失败后重新显示三张原卡，既有磁盘存档保持不变")
	for index: int in ids.size(): check(main.owned_card_collection.get_by_instance_id(ids[index]).capture_state() == snapshots[index], "失败恢复材料的完整实例状态")
	main.run_save_path = save_path
	main._execute_shop_exchange()
	awarded = main.owned_card_collection.get_cards().back()
	check(awarded.card_data.rarity == CardData.Rarity.IV, "III级三卡可置换IV级")
	main._open_shop_exchange()
	check(not main._shop_exchange_slots[0]._can_drop_data(Vector2.ZERO, {"kind": &"card", "owned_card": awarded}), "IV级不能作为置换材料")
	# 当前持有全部IV随从后，III级材料没有合法产物，确认禁用且不吞卡。
	for definition: CardData in main._get_shop_card_definitions():
		if definition.card_type == CardData.CardType.MINION and definition.rarity == CardData.Rarity.IV and definition.is_available and not definition.is_derived and main.owned_card_collection.find_first_by_definition(definition) == null: main.owned_card_collection.create_card(definition)
	materials = add_materials(CardData.Rarity.III)
	select_materials(materials)
	before_count = main.owned_card_collection.size()
	rng_before = main.ordinary_shop_service.rng.state
	check(main._exchange_candidates().is_empty() and main._shop_exchange_confirm.disabled, "全部IV已持有时遵守持有去重，不能换出重复IV")
	main._execute_shop_exchange()
	check(main.owned_card_collection.size() == before_count and main.ordinary_shop_service.rng.state == rng_before, "无产物时不消耗材料或随机数")
	main._close_shop_card_services()
	check(main._shop_exchange_ids.all(func(id: StringName): return id.is_empty()) and main._shop_exchange_slots.all(func(slot: Control): return slot._card_view == null), "返回商品自动归还三张材料，清空暂存")
	main._open_shop_exchange()
	var stacked := SquadData.from_owned_card(materials[0])
	check(stacked.insert_card(materials[1].get_battlefield_card(), 1) and stacked.bind_owned_card(materials[1].get_battlefield_card(), materials[1]), "使用真实材料创建双卡小队")
	main.front_row.add_squad(stacked, 0)
	check(not main._shop_exchange_slots[0]._can_drop_data(Vector2.ZERO, {"kind": &"card", "owned_card": materials[0]}), "未拆开的堆叠成员不能作为置换材料")
	main.front_row.clear_squads()
	select_materials(materials)
	main._toggle_ordinary_shop()
	await create_timer(0.3).timeout
	check(not main.ordinary_shop_open and main._shop_exchange_slots.all(func(slot: Control): return slot._card_view == null) and materials.all(func(card: OwnedCard): return main.owned_card_collection.get_by_instance_id(card.instance_id) != null), "离开商店归还材料，没有消耗卡牌")
	await capture("exchange-closed")
	main._toggle_ordinary_shop()
	await create_timer(0.4).timeout
	main._open_shop_exchange()
	select_materials(materials)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await process_frame
	check(main._escape_pause_menu.is_menu_open(), "三槽填满时Esc仍可打开正式暂停菜单")
	main._escape_pause_menu.restore_requested.emit()
	await create_timer(0.2).timeout
	check(not main.ordinary_shop_open and main._shop_exchange_ids.all(func(id: StringName): return id.is_empty()) and main._shop_exchange_slots.all(func(slot: Control): return slot._card_view == null), "Esc还原关闭置换并释放三槽，不残留失效卡面")
	main._escape_pause_menu.close_menu()
	shell.queue_free()
	await process_frame
	print("定向采购与置换界面：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
