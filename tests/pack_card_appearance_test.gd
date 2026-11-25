extends SceneTree

## 真实实例、正式交易与磁盘JSON验收；不使用mock，也不修改正式卡牌或用户存档。
const Appearance = preload("res://scripts/data/card_appearance.gd")
const MAIN := preload("res://scenes/Main.tscn")
const SAVE_PATH := "/private/tmp/project-card-pack-appearance-test.json"
const SAMPLES_PER_RARITY := 5000
const EXPECTED_SURFACES := [
	[75, 10, 5, 4, 2, 2, 2, 0],
	[62, 15, 8, 6, 3, 3, 3, 0],
	[50, 20, 10, 8, 4, 4, 4, 0],
	[40, 20, 15, 10, 5, 5, 5, 0],
	[40, 20, 15, 10, 5, 5, 5, 0],
]
var failures := 0
var assertions := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func rng_at(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func count_tickets(weights: Array[int]) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(weights.size())
	for ticket: int in range(1, 101):
		var outcome := Appearance.pick_ticket(weights, ticket)
		if outcome < 0: return []
		counts[outcome] += 1
	return counts


func test_rarity_distribution(definition: CardData) -> void:
	var combinations := {}
	for rarity: int in CardData.Rarity.size():
		var weights := Appearance.get_surface_weights(rarity as CardData.Rarity)
		var tier: String = ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ"][rarity]
		check(count_tickets(weights) == EXPECTED_SURFACES[rarity], tier + "级100个票位精确匹配确认权重")
		check(Appearance.pick_ticket(weights, 0) == -1 and Appearance.pick_ticket(weights, 101) == -1, tier + "级票位边界有效")
		var fixture := definition.duplicate() as CardData
		fixture.rarity = rarity as CardData.Rarity
		var collection := OwnedCardCollection.new()
		var rng := rng_at(20261121 + rarity)
		var surfaces: Array[int] = []
		surfaces.resize(Appearance.Surface.size())
		var arts: Array[int] = [0, 0, 0]
		for _index: int in SAMPLES_PER_RARITY:
			var card := collection.create_card(fixture, rng, [], true)
			surfaces[card.surface_finish] += 1
			arts[card.art_finish] += 1
			combinations[Vector2i(card.surface_finish, card.art_finish)] = true
		check(surfaces[Appearance.Surface.FROSTED] > 0 and surfaces[Appearance.Surface.FINGERPRINT] == 0, tier + "级实抽可获得磨砂闪，指纹闪为零")
		for index: int in surfaces.size():
			check(absf(surfaces[index] * 100.0 / SAMPLES_PER_RARITY - EXPECTED_SURFACES[rarity][index]) < 3.0, tier + "级卡面抽样：" + Appearance.SURFACE_LABELS[index])
		for index: int in arts.size():
			check(absf(arts[index] * 100.0 / SAMPLES_PER_RARITY - Appearance.ART_WEIGHTS[index]) < 3.0, tier + "级卡图抽样：" + Appearance.ART_LABELS[index])
		print("%s级开包卡面 %s，卡图 %s" % [tier, surfaces, arts])
	check(combinations.size() == 21, "实际抽样覆盖七种卡面与三种卡图的全部21种组合")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	check(count_tickets(Appearance.ART_WEIGHTS) == [90, 5, 5], "独立卡图权重为普通90、全息5、超框5")
	var definition := load("res://resources/cards/militia.tres") as CardData
	var bytes_before := FileAccess.get_file_as_bytes(definition.resource_path)
	test_rarity_distribution(definition)
	var ordinary_rng := rng_at(71)
	var pack_rng := rng_at(71)
	var ordinary := OwnedCardCollection.new()
	var pack := OwnedCardCollection.new()
	var plain := ordinary.create_card(definition, ordinary_rng)
	var special := pack.create_card(definition, pack_rng, [], true)
	check(ordinary_rng.state == pack_rng.state and plain.resolved_runes == special.resolved_runes and plain.slot_layout == special.slot_layout, "外观抽取不推进玩法随机流，不改变符文和槽位")
	check(not plain.has_special_appearance(), "非卡包获得的卡牌保持普通外观")
	special.surface_finish = Appearance.Surface.FROSTED
	special.art_finish = Appearance.Art.OVERFRAME
	var snapshot := pack.capture_state()
	special.surface_finish = Appearance.Surface.PLAIN
	check(pack.restore_state(snapshot) and pack.get_cards()[0] == special and special.surface_finish == Appearance.Surface.FROSTED and special.art_finish == Appearance.Art.OVERFRAME, "实例快照按原身份恢复磨砂闪与超框")
	var saves := RunSaveService.new()
	var encoded := saves._encode_collection_state(pack.capture_state())
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(encoded))
	file.close()
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	check(disk.cards[0].surface_finish == "frosted" and disk.cards[0].art_finish == "overframe", "磁盘使用稳定的磨砂闪与超框保存键")
	var registry := {definition.id: definition}
	var restored := saves._decode_collection_state(disk, registry)
	var resumed := OwnedCardCollection.new()
	check(restored.success and resumed.restore_state(restored.state) and resumed.get_cards()[0].surface_finish == special.surface_finish and resumed.get_cards()[0].art_finish == special.art_finish, "JSON读回保留每张卡的组合")
	disk.cards[0].erase("surface_finish")
	disk.cards[0].erase("art_finish")
	var legacy := saves._decode_collection_state(disk, registry)
	check(legacy.success and int(legacy.state.cards[0].surface_finish) == 0 and int(legacy.state.cards[0].art_finish) == 0, "旧存档缺少外观字段时按普通读取，不重抽")
	disk.cards[0]["surface_finish"] = "not_a_finish"
	check(not saves._decode_collection_state(disk, registry).success, "非法外观存档拒绝读取")
	await test_purchase()
	check(FileAccess.get_file_as_bytes(definition.resource_path) == bytes_before, "抽外观和读取存档不改写共享卡牌资源")
	DirAccess.remove_absolute(SAVE_PATH)
	print("开包罕贵度数据验收：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func test_purchase() -> void:
	var main = MAIN.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.run_reward_state.gold = 100
	var offer := {"kind": "card_pack", "pack_id": "ash_ledger", "size": "small", "price": 12, "cards": ["militia", "militia", "militia"], "offer_id": "appearance_test"}
	main.ordinary_shop_service.offers.assign([offer])
	var before: Dictionary = main.owned_card_collection.capture_state()
	var previous_rng: int = main.ordinary_shop_service.rng.state
	main.run_save_path = "/private/tmp/project-card-no-appearance-directory/state.json"
	var failed: Array[OwnedCard] = main._buy_shop_card_pack(0, offer)
	check(failed.is_empty() and main.run_reward_state.gold == 100 and main.owned_card_collection.get_cards().size() == before.cards.size() and main.ordinary_shop_service.rng.state == previous_rng and not offer.has("sold"), "真实购买存档失败时回滚卡牌、金币、报价和随机状态")
	check(main.owned_card_collection.capture_state().next_instance_sequence == before.next_instance_sequence, "回滚同时恢复单卡实例序号，重试外观可复现")
	var expected := OwnedCardCollection.new()
	expected.restore_state(before)
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.state = previous_rng
	var expected_appearances: Array[Vector2i] = []
	var definition := load("res://resources/cards/militia.tres") as CardData
	for _index: int in 3:
		var card := expected.create_card(definition, expected_rng, [definition, definition, definition], true)
		expected_appearances.append(Vector2i(card.surface_finish, card.art_finish))
	main.run_save_path = SAVE_PATH
	var acquired: Array[OwnedCard] = main._buy_shop_card_pack(0, offer)
	check(acquired.size() == 3 and main.run_reward_state.gold == 88 and bool(offer.get("sold", false)), "真实小包成功提交三张单卡")
	for index: int in acquired.size(): check(Vector2i(acquired[index].surface_finish, acquired[index].art_finish) == expected_appearances[index], "失败重试保持同一抽取结果：" + str(index))
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	for owned: OwnedCard in acquired:
		var matches := false
		for state: Dictionary in saved.collection.cards:
			if state.instance_id == String(owned.instance_id): matches = state.surface_finish == Appearance.SURFACE_KEYS[owned.surface_finish] and state.art_finish == Appearance.ART_KEYS[owned.art_finish]
		check(matches, "开包展示前两维外观已和收藏一起落盘：" + String(owned.instance_id))
	main.queue_free()
	await process_frame
	await process_frame
