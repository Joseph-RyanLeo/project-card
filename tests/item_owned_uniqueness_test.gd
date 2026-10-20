extends SceneTree

## 正式卡牌、抽取器、战斗奖励与Main交易入口；物品沿用IV的同名持有规则。
var failures := 0
var assertions := 0
var catalog: Array[CardData] = []
var shop := OrdinaryShopService.new()
var rng := RandomNumberGenerator.new()


func _initialize() -> void: _run.call_deferred()


func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error(label)
	else: print("PASS: ", label)


func _run() -> void:
	shop.load_config()
	rng.seed = 1016
	for filename: String in ResourceLoader.list_directory("res://resources/cards"):
		if filename.get_extension() == "tres": catalog.append(load("res://resources/cards/" + filename))
	_test_packs_and_collection()
	_test_acquisition_gift()
	_test_battle_rewards()
	await _test_main()
	print("Item ownership: %d checks, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func _test_packs_and_collection() -> void:
	var item: CardData = preload("res://resources/cards/coarse_bandage.tres")
	for rarity: int in CardData.Rarity.size():
		var copy: CardData = item.duplicate()
		copy.rarity = rarity
		check(copy.is_unique_while_owned(), "物品%s级均为同名持有唯一" % copy.get_rarity_name())
	var minion: CardData = preload("res://resources/cards/musketeer.tres")
	check(not minion.is_unique_while_owned(), "低级随从仍允许同名重复")
	var iv: CardData = minion.duplicate()
	iv.rarity = CardData.Rarity.IV
	check(iv.is_unique_while_owned(), "原IV级卡持有限制保留")
	var collection := OwnedCardCollection.new()
	var held := collection.create_card(item.duplicate(), rng)
	check(not shop._eligible_cards(catalog, collection.get_cards()).has(item), "不同Resource引用的同名物品按稳定id排除")
	var host := collection.create_card(minion, rng)
	var squad := SquadData.from_owned_card(host)
	check(squad.equip_item(held) and not shop._eligible_cards(catalog, collection.get_cards()).has(item), "装备在小队上的物品仍计入持有")
	squad.unequip_item()
	collection.remove_by_instance_id(held.instance_id)
	check(shop._eligible_cards(catalog, collection.get_cards()).has(item), "永久移除物品后恢复抽取资格")
	var unique := true
	for index: int in 120:
		var pack := shop.draw_card_pack(catalog, true, 5, rng)
		if not pack.success:
			unique = false
			break
		var seen := {}
		for card: CardData in pack.cards:
			if card.is_unique_while_owned() and seen.has(card.id): unique = false
			seen[card.id] = true
	check(unique, "120个正式大包内同名物品与IV均不重复")
	var state := rng.state
	var impossible := shop.draw_card_pack([item], false, 3, rng)
	check(not impossible.success and rng.state == state, "物品种类不足时不突破唯一限制，失败保留随机状态")
	var repeated := shop.draw_card_pack([minion], false, 3, rng)
	check(repeated.success and repeated.cards.size() == 3, "相同低级随从仍可在同包抽出三张")
	# 旧存档的重复物品保留实例，之后的候选仍排除该名称。
	collection.create_card(item, rng)
	collection.create_card(item, rng)
	var restored := OwnedCardCollection.new()
	check(restored.restore_state(collection.capture_state()) and restored.size() == collection.size() and not shop._eligible_cards(catalog, restored.get_cards()).has(item), "旧重复物品可恢复，后续同名获取继续被排除")


func _test_acquisition_gift() -> void:
	var collection := OwnedCardCollection.new()
	var weapons: Array[CardData] = []
	for card: CardData in catalog:
		if card.is_available and not card.is_derived and card.get_effective_faction() != CardFaction.Id.LABYRINTH and card.card_type == CardData.CardType.EQUIPMENT and card.equipment_type == CardData.EquipmentType.RANGED_WEAPON and card.rarity <= CardData.Rarity.II: weapons.append(card)
	check(not weapons.is_empty(), "使用真实枪械大师远程物品候选")
	if weapons.is_empty(): return
	for index: int in range(1, weapons.size()): collection.create_card(weapons[index], rng)
	var before := collection.size()
	collection.create_card(preload("res://resources/cards/gunsmith_master.tres"), rng, [weapons[0]])
	check(collection.size() == before + 1, "枪械大师不重复赠送同包尚未创建的预留物品")
	collection.create_card(preload("res://resources/cards/gunsmith_master.tres"), rng)
	check(collection.size() == before + 3 and shop.count_owned_cards(collection.get_cards()).get(weapons[0].id) == 1, "未预留时赠送唯一未持有武器")
	collection.create_card(preload("res://resources/cards/gunsmith_master.tres"), rng)
	check(collection.size() == before + 4, "全部候选武器均已持有时不再赠送重复物品")


func _test_battle_rewards() -> void:
	var controller := BattleController.new()
	root.add_child(controller)
	var item: CardData = preload("res://resources/cards/coarse_bandage.tres")
	controller._reward_card_catalog.assign([item])
	controller._player_owned_card_ids[item.id] = 1
	check(controller._random_equipment_definition(CardData.Rarity.I) == null, "资源物品奖励排除已经持有的I级物品")
	check(controller._random_equipment_definition(CardData.Rarity.I, BattleSquadState.Side.ENEMY) == item, "敌方独立持有资格不受玩家已有同名物品影响")
	controller._player_owned_card_ids.clear()
	check(controller._random_equipment_definition(CardData.Rarity.I) == item, "尚未持有的I级物品可以作为奖励")
	var actor := BattleSquadState.new()
	actor.initialize(SquadData.from_card(preload("res://resources/cards/musketeer.tres")), BattleSquadState.Side.PLAYER, &"player_front", 0)
	var owner := BattleEffectOwnerRef.for_state(actor, BattleEffectDefinition.OwnerKind.OWNING_PLAYER)
	controller._record_resource_card_award(owner, item, &"unique_reward", actor, 0)
	controller._record_resource_card_award(owner, item, &"unique_reward_again", actor, 1)
	check(controller.run_reward_ledger.get_entries().size() == 1 and controller._random_equipment_definition(CardData.Rarity.I) == null, "同场未结算奖励也占用资格，后续掉落不重复")
	controller.free()


func _test_main() -> void:
	var main := preload("res://scenes/Main.tscn").instantiate()
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-item-unique-save.json"
	root.add_child(main)
	await process_frame
	main.run_reward_state.gold = 100
	var pool := shop._eligible_cards(catalog, main.owned_card_collection.get_cards())
	var item: CardData
	for card: CardData in pool:
		if card.card_type == CardData.CardType.EQUIPMENT and card.rarity < CardData.Rarity.IV:
			item = card
			break
	check(item != null, "找到主流程中未持有的真实物品")
	if item != null:
		var price: int = main.ordinary_shop_service.config.visible_card_prices[item.get_rarity_name()]
		var offer := {"kind": "single_card", "offer_id": "unique_item", "card_id": String(item.id), "price": price, "instance_seed": "1016", "hidden": false}
		main.ordinary_shop_service.offers.assign([offer])
		main._buy_shop_single_card(0, offer)
		var after_gold: int = main.run_reward_state.gold
		check(shop.count_owned_cards(main.owned_card_collection.get_cards()).get(item.id) == 1 and after_gold == 100 - price, "正式商店首次购买物品正常扣费并入库")
		main._buy_shop_single_card(0, offer)
		check(main.run_reward_state.gold == after_gold and shop.count_owned_cards(main.owned_card_collection.get_cards()).get(item.id) == 1, "旧报价再购买同名物品被拒绝，不扣费")
		var duplicate_pack := {"cards": [String(item.id), String(item.id), String(item.id)], "pack_id": String(item.pack_id), "size": "small"}
		var legacy_offer := duplicate_pack.duplicate(true)
		legacy_offer.merge({"kind": "card_pack", "offer_id": "legacy_items", "price": int(shop.config.card_pack_prices.small)})
		check(shop.validate_saved_state({"offers": [legacy_offer]}, [], [], catalog), "旧存档重复物品报价仍可读取，交易时才按新规则重验")
		check(not main._can_buy_shop_card_pack(duplicate_pack), "购买前重验拒绝重复物品包")
		var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(item)
		main.owned_card_collection.remove_by_instance_id(owned.instance_id)
		check(not main._can_buy_shop_card_pack(duplicate_pack), "未持有时仍拒绝同包两张相同物品")
		offer.erase("sold")
		main._buy_shop_single_card(0, offer)
		check(main.run_reward_state.gold == after_gold - price, "移除原物品后再次购买同名成功")
	var before: Dictionary = shop.count_owned_cards(main.owned_card_collection.get_cards())
	for index: int in 2:
		main.run_reward_state.enqueue_random_card_request({"entry_id": StringName("unique_items_%d" % index), "amount": 2, "parameters": {"card_type": "equipment"}})
	var result: Dictionary = main._resolve_pending_random_cards()
	var after: Dictionary = shop.count_owned_cards(main.owned_card_collection.get_cards())
	var unique: bool = result.success and result.cards.size() == 4
	for id: StringName in after:
		if after[id] != before.get(id, 0): unique = unique and after[id] == 1
	check(unique, "多个真实物品奖励请求同批解析四张，已持有与待领取均去重")
	check(main.save_run_to_path(main.run_save_path) == OK and main.load_run_from_path(main.run_save_path), "新增物品规则不阻断正常存档读写")
	DirAccess.remove_absolute(main.run_save_path)
	main.queue_free()
	await process_frame
