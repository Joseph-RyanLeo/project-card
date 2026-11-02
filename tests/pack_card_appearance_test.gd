extends SceneTree

## 真实实例、正式交易与磁盘JSON验收；不使用mock，也不修改正式卡牌或用户存档。
const Appearance = preload("res://scripts/data/card_appearance.gd")
const MAIN := preload("res://scenes/Main.tscn")
const SAVE_PATH := "/private/tmp/project-card-pack-appearance-test.json"
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

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for weights: Array[int] in [Appearance.SURFACE_WEIGHTS, Appearance.ART_WEIGHTS]:
		var counts: Array[int] = []
		counts.resize(weights.size())
		for ticket: int in range(1, 101): counts[Appearance.pick_ticket(weights, ticket)] += 1
		check(counts == weights, "100个等概率票位精确对应权重：" + str(counts))
	check(Appearance.pick_ticket(Appearance.SURFACE_WEIGHTS, 0) == -1 and Appearance.pick_ticket(Appearance.SURFACE_WEIGHTS, 101) == -1, "权重边界不会误分配")
	var definition := load("res://resources/cards/militia.tres") as CardData
	var bytes_before := FileAccess.get_file_as_bytes(definition.resource_path)
	var collection := OwnedCardCollection.new()
	var rng := rng_at(20261027)
	var surfaces: Array[int] = [0, 0, 0, 0, 0, 0]
	var arts: Array[int] = [0, 0, 0]
	var combinations := {}
	for _index: int in 5000:
		var card := collection.create_card(definition, rng, [], true)
		surfaces[card.surface_finish] += 1
		arts[card.art_finish] += 1
		combinations["%d:%d" % [card.surface_finish, card.art_finish]] = true
	check(combinations.size() == 18, "两维独立抽取能形成全部18种组合")
	for index: int in surfaces.size(): check(absf(surfaces[index] / 50.0 - Appearance.SURFACE_WEIGHTS[index]) < 3.0, "实际实例的卡面抽样分布：" + Appearance.SURFACE_LABELS[index])
	for index: int in arts.size(): check(absf(arts[index] / 50.0 - Appearance.ART_WEIGHTS[index]) < 3.0, "实际实例的卡图抽样分布：" + Appearance.ART_LABELS[index])
	print("5000张卡面统计：", surfaces, "；卡图统计：", arts)
	var ordinary_rng := rng_at(71)
	var pack_rng := rng_at(71)
	var ordinary := OwnedCardCollection.new()
	var pack := OwnedCardCollection.new()
	var plain := ordinary.create_card(definition, ordinary_rng)
	var special := pack.create_card(definition, pack_rng, [], true)
	check(ordinary_rng.state == pack_rng.state and plain.resolved_runes == special.resolved_runes and plain.slot_layout == special.slot_layout, "外观抽取不推进玩法随机流，不改变符文和槽位")
	check(not plain.has_special_appearance(), "非卡包获得的卡牌保持普通外观")
	special.surface_finish = Appearance.Surface.FRACTURED
	special.art_finish = Appearance.Art.OVERFRAME
	var snapshot := pack.capture_state()
	special.surface_finish = Appearance.Surface.PLAIN
	check(pack.restore_state(snapshot) and pack.get_cards()[0] == special and special.surface_finish == Appearance.Surface.FRACTURED and special.art_finish == Appearance.Art.OVERFRAME, "实例快照按原身份恢复两维外观")
	var saves := RunSaveService.new()
	var encoded := saves._encode_collection_state(pack.capture_state())
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(encoded))
	file.close()
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	check(disk.cards[0].surface_finish == "fractured" and disk.cards[0].art_finish == "overframe", "磁盘使用稳定的工艺保存键")
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
