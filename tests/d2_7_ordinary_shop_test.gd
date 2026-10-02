extends SceneTree

const MainScript = preload("res://scripts/main.gd")
const OrdinaryShopServiceScript = preload("res://scripts/data/ordinary_shop_service.gd")
const RunSaveService = preload("res://scripts/data/run_save_service.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_test_real_card_pools_and_guarantees()
	_test_real_sticker_pool_and_uniqueness()
	_test_instance_acquisition_state()
	_test_service_rng_and_state_roundtrip()
	await _test_main_transactions_and_save()
	print("D2-7 ordinary shop failures: ", failures)
	quit(1 if failures else 0)


func _new_service(seed_value: int) -> Variant:
	var service: Variant = OrdinaryShopServiceScript.new()
	service.load_config()
	service.initialize(seed_value)
	return service


func _real_card_definitions() -> Array[CardData]:
	var result: Array[CardData] = []
	var directory := DirAccess.open("res://resources/cards")
	if directory == null:
		return result
	for filename: String in directory.get_files():
		if filename.get_extension() != "tres":
			continue
		var definition := load("res://resources/cards/%s" % filename) as CardData
		if definition != null and not definition.id.is_empty():
			result.append(definition)
	return result


func _test_real_card_pools_and_guarantees() -> void:
	var service: Variant = _new_service(72401)
	var definitions := _real_card_definitions()
	var eligible: Array[CardData] = service._eligible_cards(definitions, [])
	var counts := [0, 0, 0, 0, 0]
	for card: CardData in eligible:
		counts[int(card.rarity)] += 1
		_expect(card.pack_id == &"ash_ledger" and not card.is_derived and card.is_available, "普通卡池只包含可用、非衍生灰烬证册卡牌")
	_expect(counts == [10, 10, 6, 3, 0], "当前真实卡池I至V档候选数为10/10/6/3/0")
	var no_iv: Array[CardData] = []
	for card: CardData in eligible:
		if card.rarity <= CardData.Rarity.III:
			no_iv.append(card)
	var weights: Dictionary = service.get_effective_card_tier_weights(no_iv)
	_expect(int(weights.total) == 99, "IV与V档为空时非空权重重新归一为99")
	var observed_weights: Array[int] = []
	for tier: Dictionary in weights.tiers:
		observed_weights.append(int(tier.weight))
	_expect(observed_weights == [75, 20, 4], "空档重分配保留其余档原始75/20/4比例")
	var rng := RandomNumberGenerator.new()
	rng.seed = 78014
	var pack: Dictionary = service.draw_card_pack(eligible, true, 5, rng)
	var cards := pack.get("cards", []) as Array[CardData]
	var guaranteed := bool(pack.get("success", false)) and cards.size() == 5
	var acquired_iv: Dictionary = {}
	for card: CardData in cards:
		guaranteed = guaranteed and card.rarity >= CardData.Rarity.I
		if card.rarity >= CardData.Rarity.II:
			guaranteed = guaranteed and card.rarity >= CardData.Rarity.II
		if card.rarity == CardData.Rarity.IV:
			guaranteed = guaranteed and not acquired_iv.has(card.id)
			acquired_iv[card.id] = true
	var got_ii_plus := false
	for card: CardData in cards:
		got_ii_plus = got_ii_plus or card.rarity >= CardData.Rarity.II
	_expect(guaranteed and got_ii_plus, "真实五张大包恰好发五张且至少一张II级以上，同包IV不重复")
	var held_iv: Array[OwnedCard] = []
	for card: CardData in eligible:
		if card.rarity != CardData.Rarity.IV:
			continue
		var owned := OwnedCard.new()
		owned.initialize(card, StringName("held_%s" % card.id), held_iv.size())
		held_iv.append(owned)
	var without_held_iv: Array[CardData] = service._eligible_cards(definitions, held_iv)
	_expect(without_held_iv.filter(func(card: CardData) -> bool: return card.rarity == CardData.Rarity.IV).is_empty(), "收藏中的IV卡牌从所有普通候选池排除")
	var only_common: Array[CardData] = []
	for card: CardData in eligible:
		if card.rarity == CardData.Rarity.I:
			only_common.append(card)
	var failure_rng := RandomNumberGenerator.new()
	failure_rng.seed = 9917
	var before_state := failure_rng.state
	var impossible: Dictionary = service.draw_card_pack(only_common, true, 5, failure_rng)
	_expect(not bool(impossible.get("success", false)) and failure_rng.state == before_state, "大包保底无合法II级以上候选时失败且随机状态不变")


func _test_real_sticker_pool_and_uniqueness() -> void:
	var service: Variant = _new_service(72402)
	var definitions := EmblemLibraryData.get_definitions()
	var empty_states: Array[Dictionary] = []
	var candidates: Array[Dictionary] = service._eligible_stickers(definitions, empty_states, empty_states)
	var expected_rune_ids := ["水贴纸", "木贴纸", "火贴纸", "光贴纸", "暗贴纸", "万能贴纸", "混沌贴纸"]
	var found: Dictionary = {}
	for definition: Dictionary in candidates:
		if definition.get("target", "") == "rune":
			found[String(definition.id)] = true
	for id: String in expected_rune_ids:
		_expect(found.has(id), "本Demo当前开放元素贴纸候选：%s" % id)
	var held_universal: Array[Dictionary] = [{"emblem_id": &"万能贴纸"}]
	var with_universal: Array[Dictionary] = service._eligible_stickers(definitions, held_universal, empty_states)
	var universal_present := false
	for definition: Dictionary in with_universal:
		universal_present = universal_present or String(definition.get("id", "")) == "万能贴纸"
	_expect(not universal_present, "万能贴纸已在卡牌或背包持有时从贴纸池排除")
	var tiers := {0: 0, 1: 0, 2: 0}
	for definition: Dictionary in candidates:
		var rarity := int(definition.get("rarity", -1))
		if rarity >= 0 and rarity <= 2:
			tiers[rarity] = int(tiers[rarity]) + 1
	_expect(int((service.config.sticker_rarity_weights as Dictionary).get("I", 0)) == 85 and int((service.config.sticker_rarity_weights as Dictionary).get("II", 0)) == 13 and int((service.config.sticker_rarity_weights as Dictionary).get("III", 0)) == 2, "贴纸品级权重来自可调配置85/13/2")
	_expect(int(tiers[0]) > 0 and int(tiers[1]) >= 5 and int(tiers[2]) >= 2, "真实贴纸定义按品级均匀抽样池含普通与全部元素类型")
	var hint_minion := CardData.new()
	hint_minion.card_type = CardData.CardType.MINION
	var hint_equipment := CardData.new()
	hint_equipment.card_type = CardData.CardType.EQUIPMENT
	var hint_spell := CardData.new()
	hint_spell.card_type = CardData.CardType.SPELL
	var hint_cards: Array[CardData] = [hint_minion, hint_equipment, hint_spell]
	_expect(service._candidates_for_hint(hint_cards, "race").size() == 1 and service._candidates_for_hint(hint_cards, "action_type").size() == 1, "暗牌种族和行动提示只读取随从的真实属性")


func _test_instance_acquisition_state() -> void:
	var definition := CardData.new()
	definition.id = &"test_multi_action_instance"
	definition.card_type = CardData.CardType.MINION
	definition.runes = [CardData.ElementType.FIRE, CardData.ElementType.WATER, CardData.ElementType.WOOD]
	definition.acquisition_action_types = [CardData.ActionType.RANGED, CardData.ActionType.MAGIC]
	var first_rng := RandomNumberGenerator.new()
	first_rng.seed = 91824
	var first := OwnedCard.new()
	first.initialize(definition, &"test_owned_first", 1, first_rng)
	var saved_state := first.capture_state()
	var second_rng := RandomNumberGenerator.new()
	second_rng.seed = 91824
	var second := OwnedCard.new()
	second.initialize(definition, &"test_owned_second", 1, second_rng)
	var restored := OwnedCard.new()
	var restore_ok: bool = restored.restore_state(saved_state)
	var legacy_owned := OwnedCard.new()
	legacy_owned.initialize(definition, &"test_owned_legacy", 2)
	_expect(first.resolved_action_type in [CardData.ActionType.RANGED, CardData.ActionType.MAGIC] and first.resolved_action_type == second.resolved_action_type and first.resolved_runes == second.resolved_runes and restore_ok and restored.resolved_runes == first.resolved_runes and restored.resolved_action_type == first.resolved_action_type, "获得时确定的行动方式与随机符文只保存在OwnedCard并经存档往返固定")
	_expect(legacy_owned.resolved_runes == definition.runes, "未传入获得随机流的旧式实例沿用定义符文")
	_expect(definition.runes == [CardData.ElementType.FIRE, CardData.ElementType.WATER, CardData.ElementType.WOOD], "生成实例不会改写共享卡牌定义上的符文数组")


func _test_service_rng_and_state_roundtrip() -> void:
	var service: Variant = _new_service(72403)
	var definitions := _real_card_definitions()
	var sticker_definitions := EmblemLibraryData.get_definitions()
	var empty_owned: Array[OwnedCard] = []
	var empty_states: Array[Dictionary] = []
	var generated: bool = service.refresh(definitions, empty_owned, sticker_definitions, empty_states)
	_expect(generated and service.offers.size() >= 5, "真实卡牌/贴纸定义生成商品与两项常驻服务")
	var encoded := JSON.stringify(service.capture_state())
	var restored: Variant = _new_service(1)
	var restored_state := JSON.parse_string(encoded) as Dictionary
	var initialized: bool = restored.initialize(1, restored_state)
	var actual_state: Dictionary = restored.capture_state()
	_expect(
		initialized
		and actual_state.get("rng_state", "") == restored_state.get("rng_state", "")
		and actual_state.get("rng_seed", "") == restored_state.get("rng_seed", "")
		and int(actual_state.get("refresh_count", -1)) == int(restored_state.get("refresh_count", -2))
		and JSON.stringify(actual_state.get("offers", [])) == JSON.stringify(restored_state.get("offers", []))
		and JSON.stringify(actual_state.get("reveals", {})) == JSON.stringify(restored_state.get("reveals", {})),
		"JSON往返逐字保留随机数状态、种子、报价与揭晓信息"
	)
	var first_next: bool = service.refresh(definitions, empty_owned, sticker_definitions, empty_states)
	var second_next: bool = restored.refresh(definitions, empty_owned, sticker_definitions, empty_states)
	_expect(first_next and second_next and JSON.stringify(service.offers) == JSON.stringify(restored.offers) and service.capture_state().rng_state == restored.capture_state().rng_state, "读档后继续生成的下一组商品与随机状态逐项一致")
	var damaged := restored_state.duplicate(true)
	damaged["offers"] = "not an array"
	_expect(not restored.validate_saved_state(damaged), "损坏的商店状态在主状态恢复前被拒绝")
	_expect(int((service.config.scraper as Dictionary).get("starting_count", -1)) == 0, "Demo刮刀起始数量按本阶段确认值为0")
	service.refresh_count = 0
	_expect(service.refresh_price() == 1, "新商店第一次刷新费用为1金币")
	service.refresh_count = 1
	_expect(service.refresh_price() == 2, "同一商店第二次刷新费用翻倍")
	service.refresh_count = 2
	_expect(service.refresh_price() == 4, "同一商店第三次刷新费用继续翻倍")
	service.refresh_count = 3
	_expect(service.refresh_price() == 8, "同一商店第四次刷新费用继续翻倍")


func _test_main_transactions_and_save() -> void:
	var main := load("res://scenes/Main.tscn").instantiate() as MainScript
	var test_save_path := "/private/tmp/project-card-d2-7-transaction-slot.json"
	main.run_save_path = test_save_path
	root.add_child(main)
	for _frame: int in 4:
		await process_frame
	main.ordinary_shop_entry_button.emit_signal("pressed")
	var service: Variant = main.ordinary_shop_service
	_expect(main.ordinary_shop_panel.visible and not service.offers.is_empty(), "主场景准备阶段商店按钮通过真实信号打开报价面板")
	var before_insufficient_refresh := JSON.stringify(service.capture_state())
	main.run_reward_state.gold = 0
	main._refresh_ordinary_shop()
	_expect(JSON.stringify(service.capture_state()) == before_insufficient_refresh and main.run_reward_state.gold == 0, "金币不足时刷新不替换报价、不消耗随机状态或扣款")
	service.refresh_count = 3
	main.debug_new_shop_button.emit_signal("pressed")
	_expect(service.refresh_count == 0 and not service.offers.is_empty() and FileAccess.file_exists(test_save_path), "调试入口创建新商店后重置刷新费用并保存新报价")
	var pack_index := -1
	var sticker_index := -1
	for index: int in service.offers.size():
		var offer: Dictionary = service.offers[index]
		if pack_index < 0 and offer.get("kind") == "card_pack":
			pack_index = index
		if sticker_index < 0 and offer.get("kind") == "sticker_pack":
			sticker_index = index
	var before_collection := main.owned_card_collection.capture_state()
	var before_gold := main.run_reward_state.gold
	var before_rng: int = service.rng.state
	var before_next := int(main.owned_card_collection.capture_state().next_instance_sequence)
	main._on_ordinary_shop_offer_pressed(pack_index)
	_expect(main.owned_card_collection.capture_state() == before_collection and main.run_reward_state.gold == before_gold and service.rng.state == before_rng and int(main.owned_card_collection.capture_state().next_instance_sequence) == before_next, "金币不足时卡包购买不改变金币、卡牌实例序号或商店随机状态")
	var pack_offer: Dictionary = service.offers[pack_index]
	var pack_size := int((service.config.get("card_pack_sizes", {}) as Dictionary).get(pack_offer.get("size", "small"), 0))
	var pack_price := int(pack_offer.get("price", 0))
	main.run_reward_state.gold = 100
	var equipment_definition: CardData
	var host_definition: CardData
	var spell_definition: CardData
	for definition: CardData in main._get_shop_card_definitions():
		if definition.card_type == CardData.CardType.EQUIPMENT and equipment_definition == null:
			equipment_definition = definition
		elif definition.card_type == CardData.CardType.MINION and host_definition == null:
			host_definition = definition
		elif definition.card_type == CardData.CardType.SPELL and spell_definition == null:
			spell_definition = definition
	var held_equipment := main.owned_card_collection.create_card(equipment_definition, service.rng) if equipment_definition != null else null
	var equipment_host := main.owned_card_collection.create_card(host_definition, service.rng) if host_definition != null else null
	var equipment_squad := SquadData.from_owned_card(equipment_host) if equipment_host != null else null
	var equipment_slot: BoardSlot
	if equipment_squad != null and held_equipment != null and equipment_squad.equip_item(held_equipment):
		equipment_slot = main.front_row.add_squad(equipment_squad, main.front_row.get_squad_count())
	var prepared_spell := main.owned_card_collection.create_card(spell_definition, service.rng) if spell_definition != null else null
	if prepared_spell != null:
		main.prepared_spell_instance_ids.append(prepared_spell.instance_id)
	_expect(equipment_slot != null and prepared_spell != null, "准备卡包交易时已有装备小队与准备中法术")
	var cards_before_pack := main.owned_card_collection.get_cards().size()
	main._on_ordinary_shop_offer_pressed(pack_index)
	var latest_cards := main.owned_card_collection.get_cards()
	var gained_rarities: Array[int] = []
	for index: int in range(cards_before_pack, latest_cards.size()):
		gained_rarities.append(int(latest_cards[index].card_data.rarity))
	var large_guarantee: bool = pack_offer.get("size") != "large"
	if not large_guarantee:
		for rarity: int in gained_rarities:
			large_guarantee = large_guarantee or rarity >= CardData.Rarity.II
	_expect(latest_cards.size() == cards_before_pack + pack_size and main.run_reward_state.gold == 100 - pack_price and large_guarantee and bool(service.offers[pack_index].get("sold", false)), "成功购买真实卡包按价格扣款、准确发卡并满足大包保底")
	_expect(main.owned_card_collection.get_by_instance_id(held_equipment.instance_id) == held_equipment and equipment_slot.get_squad_data().get_equipped_item() == held_equipment and main.owned_card_collection.get_by_instance_id(prepared_spell.instance_id) == prepared_spell and main.prepared_spell_instance_ids.has(prepared_spell.instance_id), "开包保留已有装备实例、装备引用与准备中法术")
	_expect(main._shop_pack_opening, "成功交易后进入不可重复提交的开包动画")
	await create_timer(1.1).timeout # 等待已提交交易的放大、停留与溶解完成后再测试下一交易
	if sticker_index >= 0:
		var full_inventory: Array[Dictionary] = []
		for item: int in main.emblem_library.get_inventory_capacity():
			full_inventory.append({"instance_id": "capacity_%02d" % item, "emblem_id": &"火把", "element_sticker": false})
		main.emblem_library.restore_inventory_state(full_inventory)
		var before_bag: Array[Dictionary] = main.emblem_library.get_inventory_state()
		main.run_reward_state.gold = 100
		var before_capacity_gold := main.run_reward_state.gold
		var before_capacity_rng: int = service.rng.state
		var before_capacity_next := int(main.owned_card_collection.capture_state().next_instance_sequence)
		main._on_ordinary_shop_offer_pressed(sticker_index)
		_expect(main.emblem_library.get_inventory_state() == before_bag and main.run_reward_state.gold == before_capacity_gold and service.rng.state == before_capacity_rng and int(main.owned_card_collection.capture_state().next_instance_sequence) == before_capacity_next and not bool(service.offers[sticker_index].get("sold", false)), "金币充足但工具箱满载时购买失败且金币、库存、实例序号、随机状态和报价均不变")
		main.emblem_library.restore_inventory_state([])
		var before_sticker_count: int = main.emblem_library.get_inventory_state().size()
		var sticker_price: int = int(service.offers[sticker_index].get("price", 0))
		main._on_ordinary_shop_offer_pressed(sticker_index)
		_expect(main.emblem_library.get_inventory_state().size() == before_sticker_count + int(service.config.sticker_pack.sticker_count) and main.run_reward_state.gold == 100 - sticker_price and bool(service.offers[sticker_index].get("sold", false)), "成功购买贴纸包精确收入五枚独立实例并按报价扣款")
	await create_timer(1.1).timeout # 贴纸包动画结束后再生成单卡报价
	var offer_weights: Dictionary = service.config.get("temporary_offer_weights", {})
	offer_weights["single_card_count"] = {"1": 1}
	offer_weights["single_card_visibility"] = {"hidden": 1}
	offer_weights["hidden_card_hint"] = {"action_type": 1}
	service.config["temporary_offer_weights"] = offer_weights
	_expect(main._generate_ordinary_shop(false), "以配置分布生成暗单卡验收报价")
	var hidden_index := _find_offer(service.offers, "single_card")
	var hidden_offer: Dictionary = service.offers[hidden_index] if hidden_index >= 0 else {}
	var hidden_card_id := String(hidden_offer.get("card_id", ""))
	var hidden_action_type := int(hidden_offer.get("resolved_action_type", -1))
	main.run_reward_state.gold = 100
	var hidden_cards_before := main.owned_card_collection.get_cards().size()
	if hidden_index >= 0:
		main._on_ordinary_shop_offer_pressed(hidden_index)
	var hidden_owned: OwnedCard = main.owned_card_collection.get_cards().back() if main.owned_card_collection.get_cards().size() > hidden_cards_before else null
	_expect(hidden_offer.get("hint") == "action_type" and not hidden_card_id.is_empty() and hidden_owned != null and String(hidden_owned.card_data.id) == hidden_card_id and hidden_owned.resolved_action_type == hidden_action_type and bool(service.offers[hidden_index].get("sold", false)) and service.reveal_by_offer.get(String(hidden_offer.get("offer_id", ""))) == hidden_card_id, "暗牌购买揭晓具体定义且行动提示与真正获得的实例行动方式一致")
	_expect(not _shop_list_contains_offer_index(main.ordinary_shop_offer_list, hidden_index), "购买后的商品从可购买报价列表移除")
	offer_weights["single_card_visibility"] = {"visible": 1}
	service.config["temporary_offer_weights"] = offer_weights
	_expect(main._generate_ordinary_shop(false), "以配置分布生成明单卡验收报价")
	var visible_index := _find_offer(service.offers, "single_card")
	var visible_offer: Dictionary = service.offers[visible_index] if visible_index >= 0 else {}
	if visible_index >= 0:
		main._preview_shop_single_card(visible_index)
		await process_frame
	var read_only_preview := visible_index >= 0 and is_instance_valid(main._inspection_overlay) and main._inspection_read_only and not main._inspection_has_library_toolbox
	var preview_owned: OwnedCard = main._inspection_owned_card if read_only_preview else null
	var preview_action := preview_owned.resolved_action_type if preview_owned != null else -1
	var preview_runes: Array[int] = []
	var preview_layout: Array[int] = []
	if preview_owned != null:
		preview_runes.assign(preview_owned.resolved_runes)
		preview_layout.assign(preview_owned.slot_layout)
	var hidden_preview_runes_stay_hidden := preview_owned != null
	if preview_owned != null:
		for rune_index: int in preview_owned.rune_revealed.size():
			if preview_owned.rune_revealed[rune_index] or not preview_owned.rune_stickers[rune_index].is_empty():
				continue
			var rune_slot := main._inspection_card_view.rune_row.get_child(rune_index) as Control
			var rune_icon := rune_slot.get_child(0) as TextureRect if rune_slot.get_child_count() > 0 else null
			var cover := rune_slot.get_node_or_null("RuneRevealCover") as TextureRect
			hidden_preview_runes_stay_hidden = hidden_preview_runes_stay_hidden and rune_icon != null and cover != null and rune_icon.tooltip_text.is_empty() and preview_owned.get_rune_scraped_pixel_count(rune_index) == 0
	var scraper_drag := {"kind": &"sticker_scraper"}
	var preview_rejects_tools := read_only_preview and main._resolve_inspection_drop_target(main._inspection_card_view, Vector2.ZERO, scraper_drag).is_empty()
	_expect(read_only_preview and preview_rejects_tools and hidden_preview_runes_stay_hidden, "明单卡只读预览隐藏未揭符文且不开放刮刀或贴纸拖放")
	if is_instance_valid(main._inspection_overlay):
		main._close_card_inspection(true)
	var visible_cards_before := main.owned_card_collection.get_cards().size()
	if visible_index >= 0:
		main._on_ordinary_shop_offer_pressed(visible_index)
	var purchased_visible_card: OwnedCard = main.owned_card_collection.get_cards().back() if main.owned_card_collection.get_cards().size() > visible_cards_before else null
	_expect(purchased_visible_card != null and purchased_visible_card.resolved_action_type == preview_action and purchased_visible_card.resolved_runes == preview_runes and purchased_visible_card.slot_layout == preview_layout, "明单预览与实购复用同一随机行动方式、符文和槽位实例结果")
	var scraper_index := -1
	for index: int in service.offers.size():
		if service.offers[index].get("kind") == "scraper":
			scraper_index = index
	var scraper_gold_before := main.run_reward_state.gold
	var scraper_count_before := main.scraper_count
	main._on_ordinary_shop_offer_pressed(scraper_index)
	main._on_ordinary_shop_offer_pressed(scraper_index)
	_expect(main.scraper_count == scraper_count_before + 2 and main.run_reward_state.gold == scraper_gold_before - 4, "固定2金币刮刀商品可连续无限购买")
	await _test_tear_confirmation_and_equipment_return(main)
	await _test_shop_sale(main)
	var temp_save := "/private/tmp/project-card-d2-7-roundtrip.json"
	main.run_reward_state.gold = 7
	var expected_scraper_count := main.scraper_count
	var acquisition_states: Dictionary = {}
	for owned: OwnedCard in main.owned_card_collection.get_cards():
		acquisition_states[String(owned.instance_id)] = {"runes": owned.resolved_runes.duplicate(), "action": owned.resolved_action_type}
	var save_error := main.save_run_to_path(temp_save)
	main.run_reward_state.gold = 0
	var load_ok := main.load_run_from_path(temp_save)
	_expect(save_error == OK and load_ok and main.run_reward_state.gold == 7 and main.scraper_count == expected_scraper_count, "真实主流程单槽存档保存并恢复金币、商店和刮刀数量")
	var acquisition_states_restored := true
	for owned: OwnedCard in main.owned_card_collection.get_cards():
		var expected: Dictionary = acquisition_states.get(String(owned.instance_id), {})
		if expected.is_empty() or JSON.stringify(expected.runes) != JSON.stringify(owned.resolved_runes) or int(expected.action) != owned.resolved_action_type:
			acquisition_states_restored = false
	_expect(acquisition_states_restored, "卡包中每张实例的随机符文与行动方式跨磁盘存档保持")
	var before_damaged_load_collection := main.owned_card_collection.capture_state()
	var before_damaged_load_gold: int = main.run_reward_state.gold
	var before_damaged_load_shop := JSON.stringify(main.ordinary_shop_service.capture_state())
	var checkpoint_file := FileAccess.open(temp_save, FileAccess.READ)
	var damaged_checkpoint := JSON.parse_string(checkpoint_file.get_as_text()) as Dictionary
	checkpoint_file.close()
	(damaged_checkpoint["ordinary_shop_state"] as Dictionary)["offers"] = "corrupted"
	var damaged_path := "/private/tmp/project-card-d2-7-corrupt-save.json"
	var damaged_file := FileAccess.open(damaged_path, FileAccess.WRITE)
	damaged_file.store_string(JSON.stringify(damaged_checkpoint))
	damaged_file.close()
	_expect(not main.load_run_from_path(damaged_path) and main.owned_card_collection.capture_state() == before_damaged_load_collection and main.run_reward_state.gold == before_damaged_load_gold and JSON.stringify(main.ordinary_shop_service.capture_state()) == before_damaged_load_shop, "坏商店存档在恢复前被拒绝且原卡牌、金币与商店状态不变")
	DirAccess.remove_absolute(damaged_path)
	var before_request_count := main.owned_card_collection.get_cards().size()
	_expect(main.run_reward_state.enqueue_random_card_request({"entry_id": &"test_random_card_bad_filter", "amount": 1, "parameters": {"card_type": "resource", "pack_id": "missing_theme"}}), "登记一个无候选筛选请求用于失败保持验证")
	var preserved_rng: int = main.ordinary_shop_service.rng.state
	main._claim_pending_random_cards()
	_expect(main.run_reward_state.pending_random_card_requests.size() == 1 and main.owned_card_collection.get_cards().size() == before_request_count and main.ordinary_shop_service.rng.state == preserved_rng, "无合法随机卡候选时原请求和随机状态保持不变")
	main.run_reward_state.pending_random_card_requests.clear()
	_expect(main.run_reward_state.enqueue_random_card_request({"entry_id": &"test_labyrinth_resource", "amount": 1, "parameters": {"card_type": "resource", "pack_id": "labyrinth", "rarity": "II"}}), "登记一个主题、类型与品级均受限的随机卡请求")
	main._claim_pending_random_cards()
	var resolved_request: OwnedCard = main.owned_card_collection.get_cards().back() if main.owned_card_collection.get_cards().size() > before_request_count else null
	_expect(resolved_request != null and resolved_request.card_data.card_type == CardData.CardType.RESOURCE and String(resolved_request.card_data.pack_id) == "labyrinth" and resolved_request.card_data.rarity == CardData.Rarity.II and main.run_reward_state.pending_random_card_requests.is_empty(), "随机卡按请求参数抽取迷宫II级资源，不受商店卡包主题过滤且只领取一次")
	var failure_path := "/private/tmp/project-card-d2-7-save-failure.json"
	_expect(main.save_run_to_path(failure_path) == OK, "为保存失败回滚测试写入旧档")
	var old_file := FileAccess.get_file_as_string(failure_path)
	var blocker_path := failure_path + ".bak"
	DirAccess.make_dir_recursive_absolute(blocker_path)
	var blocker_file := FileAccess.open(blocker_path.path_join("keep"), FileAccess.WRITE)
	blocker_file.store_string("prevent backup removal")
	blocker_file.close()
	var rollback_index := -1
	for index: int in service.offers.size():
		if service.offers[index].get("kind") == "card_pack" and not bool(service.offers[index].get("sold", false)) and main._can_buy_shop_card_pack(service.offers[index]):
			rollback_index = index
			break
	main.run_save_path = failure_path
	main.run_reward_state.gold = 100
	var before_failed_collection := main.owned_card_collection.capture_state()
	var before_failed_gold: int = main.run_reward_state.gold
	var before_failed_rng: int = service.rng.state
	var before_failed_offer := JSON.stringify(service.offers[rollback_index]) if rollback_index >= 0 else ""
	if rollback_index >= 0:
		main._buy_shop_card_pack(rollback_index, service.offers[rollback_index])
	_expect(rollback_index >= 0 and main.owned_card_collection.capture_state() == before_failed_collection and main.run_reward_state.gold == before_failed_gold and service.rng.state == before_failed_rng and JSON.stringify(service.offers[rollback_index]) == before_failed_offer and FileAccess.get_file_as_string(failure_path) == old_file, "写入/原子替换失败时交易回滚、旧档字节保持且商品未售出")
	DirAccess.remove_absolute(blocker_path.path_join("keep"))
	DirAccess.remove_absolute(blocker_path)
	DirAccess.remove_absolute(failure_path)
	DirAccess.remove_absolute(temp_save)
	DirAccess.remove_absolute(test_save_path)
	main.free()
	await process_frame
	await process_frame


func _test_tear_confirmation_and_equipment_return(main: MainScript) -> void:
	main.emblem_library.restore_inventory_state([])
	var owned: OwnedCard
	for candidate: OwnedCard in main.owned_card_collection.get_cards():
		if candidate.card_data.card_type == CardData.CardType.MINION and candidate.emblem_slots.size() >= 2 and candidate.rune_stickers.size() > 0:
			owned = candidate
			break
	if owned == null:
		_expect(false, "找到真实带有足够槽位的卡牌以验证撕卡服务")
		return
	var selected := {"instance_id": &"tear_selected", "emblem_id": &"火把", "element_sticker": false}
	var destroyed := {"instance_id": &"tear_destroyed", "emblem_id": &"长剑", "element_sticker": false}
	var rune_destroyed := {"instance_id": &"tear_rune_destroyed", "emblem_id": &"光贴纸", "element_sticker": true, "element": 3}
	_expect(owned.set_emblem_slot(0, selected) and owned.set_emblem_slot(1, destroyed) and owned.set_rune_sticker(0, rune_destroyed), "撕卡验收卡牌附着真实普通贴纸与元素贴纸")
	var squad := SquadData.from_owned_card(owned)
	var equipment_definition: CardData
	for definition: CardData in main._get_shop_card_definitions():
		if definition.card_type == CardData.CardType.EQUIPMENT:
			equipment_definition = definition
			break
	var equipment := main.owned_card_collection.create_card(equipment_definition, main.ordinary_shop_service.rng) if equipment_definition != null else null
	var row_slot: BoardSlot
	if equipment != null and squad.equip_item(equipment):
		row_slot = main.front_row.add_squad(squad, main.front_row.get_squad_count())
	_expect(equipment != null and row_slot != null and row_slot.get_squad_data().get_equipped_item() == equipment, "测试卡牌宿主携带真实收藏装备")
	var same_name_owned := main.owned_card_collection.create_card(owned.card_data, main.ordinary_shop_service.rng)
	var same_name_squad := SquadData.from_owned_card(same_name_owned)
	var same_name_slot := main.back_row.add_squad(same_name_squad, main.back_row.get_squad_count())
	_expect(same_name_slot != null and same_name_slot.get_squad_data().get_card_data_for_owned_instance(same_name_owned.instance_id) == owned.card_data, "同名卡以另一个OwnedCard实例部署到另一小队")
	main.run_reward_state.gold = 20
	var card_picker := OptionButton.new()
	card_picker.add_item(owned.card_data.display_name)
	card_picker.set_item_metadata(0, String(owned.instance_id))
	var pickers: Array[OptionButton] = []
	for index: int in 3:
		var picker := OptionButton.new()
		picker.add_item("不返还")
		picker.set_item_metadata(0, "")
		if index == 0:
			picker.add_item("火把")
			picker.set_item_metadata(1, "tear_selected")
			picker.select(1)
		pickers.append(picker)
	main._shop_tear_dialog = ConfirmationDialog.new()
	main.ordinary_shop_layer.add_child(main._shop_tear_dialog)
	main._confirm_shop_tear_selection(card_picker, pickers, [owned])
	var confirm := main.ordinary_shop_layer.get_children().filter(func(node: Node) -> bool: return node is ConfirmationDialog and (node as ConfirmationDialog).title == "确认撕卡")
	var exact_confirmation := not confirm.is_empty() and (confirm[0] as ConfirmationDialog).dialog_text.contains("火把") and (confirm[0] as ConfirmationDialog).dialog_text.contains("长剑") and (confirm[0] as ConfirmationDialog).dialog_text.contains("光贴纸") and (confirm[0] as ConfirmationDialog).dialog_text.contains("2金币")
	_expect(exact_confirmation, "二次确认列出卡牌、返还贴纸、销毁贴纸和精确费用")
	if exact_confirmation:
		(confirm[0] as ConfirmationDialog).emit_signal("confirmed")
		await process_frame
	_expect(main.owned_card_collection.get_by_instance_id(owned.instance_id) == null and main.emblem_library.get_inventory_item(&"tear_selected").size() > 0, "确认后销毁宿主卡并只将选择贴纸返还工具箱")
	_expect(main.owned_card_collection.get_by_instance_id(equipment.instance_id) == equipment, "撕卡宿主携带的装备实例仍留在收藏且保有唯一资格")
	_expect(main.owned_card_collection.get_by_instance_id(same_name_owned.instance_id) == same_name_owned and same_name_slot.get_squad_data().get_card_data_for_owned_instance(same_name_owned.instance_id) == owned.card_data, "撕卡仅移除所选OwnedCard，不拆除另一队同名卡或误返装备")
	if is_instance_valid(card_picker):
		card_picker.free()
	for picker: OptionButton in pickers:
		if is_instance_valid(picker):
			picker.free()
	if is_instance_valid(main._shop_tear_dialog):
		main._shop_tear_dialog.queue_free()


func _test_shop_sale(main: MainScript) -> void:
	var definition: CardData
	for candidate: CardData in main._get_shop_card_definitions():
		if candidate.card_type == CardData.CardType.MINION and candidate.runes.size() > 0:
			definition = candidate
			break
	if definition == null:
		_expect(false, "找到有符文的随从定义以验证出售")
		return
	var owned := main.owned_card_collection.create_card(definition, main.ordinary_shop_service.rng)
	var sibling_definition: CardData
	for candidate: CardData in main._get_shop_card_definitions():
		if candidate.card_type == CardData.CardType.MINION and candidate != definition:
			sibling_definition = candidate
			break
	var sibling := main.owned_card_collection.create_card(sibling_definition, main.ordinary_shop_service.rng) if sibling_definition != null else null
	var squad := SquadData.from_cards([definition, sibling_definition]) if sibling != null else null
	var squad_slot: BoardSlot
	if squad != null:
		squad.bind_owned_card(definition, owned)
		squad.bind_owned_card(sibling_definition, sibling)
		squad_slot = main.front_row.add_squad(squad, main.front_row.get_squad_count())
	var gold_before_rejected_sale: int = main.run_reward_state.gold
	main._confirm_shop_sale(owned.instance_id)
	var rejected_dialog := main.ordinary_shop_layer.get_children().filter(func(node: Node) -> bool: return node is ConfirmationDialog and (node as ConfirmationDialog).title == "确认出售卡牌")
	_expect(squad_slot != null and rejected_dialog.is_empty() and main.owned_card_collection.get_by_instance_id(owned.instance_id) == owned and main.run_reward_state.gold == gold_before_rejected_sale, "多成员小队的成员不能出售且不弹出确认框")
	main._remove_owned_instance_from_rows(owned.instance_id)
	main._remove_owned_instance_from_rows(sibling.instance_id)
	main.owned_card_collection.remove_by_instance_id(sibling.instance_id)
	var attached := {"instance_id": &"sale_sticker", "emblem_id": &"火把", "element_sticker": false}
	owned.set_emblem_slot(0, attached)
	owned.rune_revealed[0] = true
	var wound_penalty := 0
	if not owned.wound_slots.is_empty():
		owned.wound_slots[0] = {"instance_id": &"sale_wound", "wound_id": &"裂伤", "level": 1}
		wound_penalty = 1
	var sale_config := main.ordinary_shop_service.config.get("card_sale", {}) as Dictionary
	var base_prices := sale_config.get("base_prices", {}) as Dictionary
	var rarity_key: String = ["I", "II", "III", "IV", "V"][int(definition.rarity)]
	var expected_price := int(base_prices[rarity_key]) + 1 + 1 - wound_penalty
	_expect(main._shop_card_sale_price(owned) == expected_price, "出售价格包含基础价、贴纸、揭晓符文和伤势修正")
	main.run_reward_state.gold = 6
	main._confirm_shop_sale(owned.instance_id)
	var confirmations := main.ordinary_shop_layer.get_children().filter(func(node: Node) -> bool: return node is ConfirmationDialog and (node as ConfirmationDialog).title == "确认出售卡牌")
	_expect(not confirmations.is_empty() and (confirmations[0] as ConfirmationDialog).dialog_text.contains(str(expected_price)), "出售确认显示计算后的卖价")
	if not confirmations.is_empty():
		(confirmations[0] as ConfirmationDialog).emit_signal("canceled")
		await process_frame
		await process_frame
	_expect(main.owned_card_collection.get_by_instance_id(owned.instance_id) == owned and main.run_reward_state.gold == 6, "取消出售确认后保留卡牌与金币")
	main._confirm_shop_sale(owned.instance_id)
	confirmations = main.ordinary_shop_layer.get_children().filter(func(node: Node) -> bool: return node is ConfirmationDialog and (node as ConfirmationDialog).title == "确认出售卡牌")
	if not confirmations.is_empty():
		(confirmations[0] as ConfirmationDialog).emit_signal("confirmed")
		await process_frame
	_expect(main.owned_card_collection.get_by_instance_id(owned.instance_id) == null and main.run_reward_state.gold == 6 + expected_price, "确认出售后销毁卡牌并按报价增加金币")
	var equipment_definition: CardData
	var equipment_host_definition: CardData
	for candidate: CardData in main._get_shop_card_definitions():
		if candidate.card_type == CardData.CardType.EQUIPMENT and equipment_definition == null:
			equipment_definition = candidate
		elif candidate.card_type == CardData.CardType.MINION and equipment_host_definition == null:
			equipment_host_definition = candidate
	var equipment := main.owned_card_collection.create_card(equipment_definition, main.ordinary_shop_service.rng) if equipment_definition != null else null
	var host := main.owned_card_collection.create_card(equipment_host_definition, main.ordinary_shop_service.rng) if equipment_host_definition != null else null
	var host_squad := SquadData.from_owned_card(host) if host != null else null
	var host_slot: BoardSlot
	if host_squad != null and equipment != null and host_squad.equip_item(equipment):
		host_slot = main.back_row.add_squad(host_squad, main.back_row.get_squad_count())
	var equipment_price: int = main._shop_card_sale_price(equipment) if equipment != null else 0
	if host_slot != null:
		main._execute_shop_sale(equipment.instance_id, equipment_price)
	_expect(host_slot != null and main.owned_card_collection.get_by_instance_id(equipment.instance_id) == null and host_slot.get_squad_data().get_equipped_item() == null, "出售装备后从宿主小队解除装备实例引用")
	if host != null:
		main._remove_owned_instance_from_rows(host.instance_id)
		main.owned_card_collection.remove_by_instance_id(host.instance_id)


func _find_offer(offers: Array[Dictionary], kind: String) -> int:
	for index: int in offers.size():
		if offers[index].get("kind") == kind:
			return index
	return -1


func _shop_list_contains_offer_index(container: Node, offer_index: int) -> bool:
	for child: Node in container.get_children():
		if child.has_meta("shop_offer_index") and int(child.get_meta("shop_offer_index")) == offer_index:
			return true
		if child is Container and _shop_list_contains_offer_index(child, offer_index):
			return true
	return false
