extends "res://tests/d2_7_shop_presentation_test.gd"

const SAVE_PATH = "/private/tmp/project-card-card-acquisition-test.json"


func _run() -> void:
	create_timer(25.0).timeout.connect(func(): push_error("入藏演出测试超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = SAVE_PATH
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_720P)
	await process_frame
	_test_corner_badges()
	await _test_hidden_purchase()
	await _test_sequential_awards()
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(SAVE_PATH)
	DirAccess.remove_absolute(SAVE_PATH + ".bak")
	print("卡牌入藏测试失败数：", failures)
	quit(1 if failures else 0)


func _test_corner_badges() -> void:
	var face := CARD.instantiate() as CardView
	var hidden := SHOP_CARD.instantiate() as ShopCardView
	root.add_child(face)
	root.add_child(hidden)
	var definition := CardData.new()
	var rarity_hint := {"hint": "rarity"}
	for rarity: int in CardData.Rarity.size():
		definition.rarity = rarity as CardData.Rarity
		definition.card_type = CardData.CardType.MINION
		for action: int in CardData.ActionType.size():
			definition.action_type = action as CardData.ActionType
			check(_corner_badge_matches(face, hidden, definition, rarity_hint, action), "五类随从轮播角标与真卡像素对齐 %s/%s" % [CardData.Rarity.keys()[rarity], CardData.ActionType.keys()[action]])
		definition.card_type = CardData.CardType.SPELL
		for trigger: int in CardData.SpellTriggerKind.size():
			definition.spell_trigger_kind = trigger as CardData.SpellTriggerKind
			check(_corner_badge_matches(face, hidden, definition, {"hint": "spell_trigger_kind"}, rarity), "法术角标与真卡像素对齐 %s/%s" % [CardData.Rarity.keys()[rarity], CardData.SpellTriggerKind.keys()[trigger]])
		definition.card_type = CardData.CardType.EQUIPMENT
		for direction: int in [1, -1]:
			definition.equipment_action_delta = direction
			check(_corner_badge_matches(face, hidden, definition, rarity_hint, 0 if direction == 1 else 1), "装备增减箭头与真卡像素对齐 %s/%d" % [CardData.Rarity.keys()[rarity], direction])
		definition.card_type = CardData.CardType.RESOURCE
		check(_corner_badge_matches(face, hidden, definition, rarity_hint, 0), "资源角标与真卡像素对齐 %s" % CardData.Rarity.keys()[rarity])
	hidden.free()
	face.free()


func _corner_badge_matches(face: CardView, hidden: ShopCardView, definition: CardData, offer: Dictionary, frame: int) -> bool:
	face.set_card_data(definition)
	hidden.configure_hidden(ShopCard.public_definition(definition, offer, frame), offer)
	var native := face.action_icon.texture.get_image()
	var actual := hidden.action_icon.texture.get_image()
	native.convert(Image.FORMAT_RGBA8)
	actual.convert(Image.FORMAT_RGBA8)
	var origin := Vector2i(face.action_icon.position - hidden.action_icon.position)
	var expected := Image.create(actual.get_width(), actual.get_height(), false, Image.FORMAT_RGBA8)
	expected.blit_rect(native, Rect2i(Vector2i.ZERO, native.get_size()), origin)
	return actual.get_data() == expected.get_data() and face.action_icon.size == Vector2(native.get_size())


func _test_hidden_purchase() -> void:
	var service: OrdinaryShopService = main.ordinary_shop_service
	service.config.temporary_offer_weights.single_card_count = {"1": 1}
	service.config.temporary_offer_weights.single_card_visibility = {"hidden": 1}
	service.config.temporary_offer_weights.hidden_card_hint = {"action_type": 1}
	main.run_reward_state.gold = 1000
	main._toggle_ordinary_shop()
	await create_timer(0.6).timeout
	var index := -1
	for i: int in service.offers.size():
		if service.offers[i].get("kind") == "single_card": index = i; break
	check(index >= 0 and bool(service.offers[index].get("hidden", false)), "真实商店生成暗牌")
	if index < 0: return
	var start_gold: int = main.run_reward_state.gold
	var count: int = main.owned_card_collection.size()
	var price := int(service.offers[index].price)
	var offer_id := String(service.offers[index].offer_id)
	main.run_save_path = SAVE_PATH + "/invalid.json"
	main._on_ordinary_shop_offer_pressed(index)
	check(not is_instance_valid(main._card_acquisition) and main.owned_card_collection.size() == count and main.run_reward_state.gold == start_gold and not service.offers[index].get("sold", false), "保存失败回滚扣款、真实实例和售出状态")
	main.run_save_path = SAVE_PATH
	main._on_search_text_changed("排除所有卡牌的搜索条件")
	main._on_ordinary_shop_offer_pressed(index)
	var presentation: Control = main._card_acquisition
	check(is_instance_valid(presentation) and FileAccess.file_exists(SAVE_PATH), "先提交保存再开始暗牌揭晓")
	if not is_instance_valid(presentation): return
	var acquired: OwnedCard = presentation._entries[0].owned
	var id := acquired.instance_id
	var preview := presentation._card as Control
	var visual := preview.get_child(0) as CardSnapshotVisual
	check(visual.get_source_card_view() is ShopCardView and visual.get_source_card_view().card_data.id != acquired.card_data.id, "入场从未揭晓的公开卡面放大")
	var reveal: Tween = presentation._animation
	reveal.pause()
	reveal.custom_step(presentation.ENLARGE_SECONDS + presentation.WHITEN_SECONDS * 0.55)
	var amount := float(presentation.white_material(preview).get_shader_parameter("white_amount"))
	check(preview.scale.is_equal_approx(Vector2.ONE * 4.0) and presentation._dim.modulate.a > 0.99 and amount > 0.0 and amount < 1.0, "使用检视倍率，暗幕和白色剪影均渐变")
	var public_face := visual.get_source_card_view() as CardView
	var badge_before := public_face.action_icon.position + Vector2(public_face.action_icon.texture.get_image().get_used_rect().position)
	reveal.custom_step(presentation.WHITEN_SECONDS + presentation.REVEAL_SECONDS * 0.4)
	var revealed_source := (presentation._card.get_child(0) as CardSnapshotVisual).get_source_card_view() as CardView
	check(presentation._card != preview and revealed_source.get_owned_card() == acquired, "剪影换入本次保存的真实卡实例")
	var badge_after := revealed_source.action_icon.position + Vector2(revealed_source.action_icon.texture.get_image().get_used_rect().position)
	check(badge_before == badge_after and presentation._card.position == preview.position, "真实暗牌换面时，已公开的角标保持同一坐标")
	await capture("dark-card-revealed")
	reveal.play()
	await _accelerate()
	check(presentation._click_speed.speed > 1.0, "真实左键连点加快揭晓和后续入藏")
	await presentation.finished
	var slot: Control = main._find_collection_slot_for_owned_card(acquired)
	check(main.current_world_view == main.WorldView.COLLECTION and main.search_query.is_empty() and is_instance_valid(slot) and slot.visible, "从上半移到收藏并清除遮住目标的搜索，卡落到实际实例卡位")
	check(main.run_reward_state.gold == start_gold - price and main.owned_card_collection.size() == count + 1, "快速点击只扣款和发卡一次")
	check(main.load_run_from_path(SAVE_PATH), "演出结束后读回同一购买存档")
	check(main.owned_card_collection.get_by_instance_id(id) != null and main.owned_card_collection.size() == count + 1 and main.run_reward_state.gold == start_gold - price and service.reveal_by_offer.has(offer_id) and service.offers[index].sold and not is_instance_valid(main._card_acquisition), "读档保留单次购买的实例、金币、报价和已售记录")


func _test_sequential_awards() -> void:
	var filler := load("res://resources/cards/militia.tres") as CardData
	for i: int in 26: main.owned_card_collection.create_card(filler)
	var previous: Array[OwnedCard] = main.owned_card_collection.get_cards()
	var first: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/armorsmith.tres"))
	var last: OwnedCard = main.owned_card_collection.create_card(filler)
	var ids: Array[StringName] = [first.instance_id, last.instance_id]
	var count: int = main.owned_card_collection.size()
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	main._set_recent_bookmark(true)
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	check(main.save_run_to_path(SAVE_PATH) == OK, "两张同批直接奖卡可以先作为真实实例保存")
	main._play_card_acquisitions(main._new_card_acquisition_entries(previous))
	var presentation: Control = main._card_acquisition
	check(presentation._entries.size() == 2 and presentation._entries[0].owned == first, "逐张入藏按真实获得顺序排队")
	await _accelerate()
	var saw_page_turn := false
	while is_instance_valid(main._card_acquisition):
		if main.is_page_turning() and not saw_page_turn:
			saw_page_turn = true
			check(presentation._card.z_index + presentation.z_index > main._get_canvas_draw_z(main._page_turn_overlay), "卷页在检视卡后方")
		await process_frame
	var slot: Control = main._find_collection_slot_for_owned_card(last)
	check(saw_page_turn and not main.collection_bookmark_active and main.current_collection_page > 0 and is_instance_valid(slot) and slot.get_meta("owned_card") == last and slot.visible, "离开近期页并停在最后一张的跨页，同名卡按实例落位")
	main.current_collection_page = 0
	main._build_collection_cards()
	var replay: Array[Dictionary] = [{"owned": last}]
	main._play_card_acquisitions(replay)
	while not main.is_page_turning() and is_instance_valid(main._card_acquisition): await process_frame
	check(main.is_page_turning() and main.load_run_from_path(SAVE_PATH) and not is_instance_valid(main._card_acquisition) and not main.is_page_turning(), "翻页中重读时清理演出，不重新发奖")
	check(main.owned_card_collection.size() == count and ids.all(func(id: StringName) -> bool: return main.owned_card_collection.get_by_instance_id(id) != null), "恢复后每张奖励只保留一份")


func _accelerate() -> void:
	for i: int in 6: await click(Vector2(630, 365))
