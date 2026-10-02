extends SceneTree

const Service = preload("res://scripts/data/ordinary_shop_service.gd")
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)


func _run() -> void:
	var definitions: Array[CardData] = []
	for filename: String in DirAccess.open("res://resources/cards").get_files():
		if filename.ends_with(".tres"):
			definitions.append(load("res://resources/cards/" + filename) as CardData)
	var service := Service.new()
	service.load_config()
	var weights: Dictionary = service.config.temporary_offer_weights.hidden_card_hint
	check(weights.size() == 8 and weights.values().all(func(value: Variant): return int(value) == 1), "运行配置八类提示权重相同")
	var ordinary := service._eligible_cards(definitions, [])
	check(ordinary.all(func(card: CardData): return card.pack_id == &"ash_ledger"), "加入资源提示不改变首批灰烬证册卡池")
	for hint: String in weights:
		var candidates := service._candidates_for_hint(definitions, hint)
		check(not candidates.is_empty(), "真实资源有合法提示候选：" + hint)
		if candidates.is_empty():
			continue
		var card: CardData = candidates[0]
		var test_service := Service.new()
		test_service.load_config()
		test_service.initialize(4281)
		# 通过服务原有配置生成一件指定提示商品；资源定义仍读取正式 .tres，不修改生产卡池。
		test_service.config.allowed_pack_ids = [String(card.pack_id)]
		test_service.config.excluded_pack_ids = []
		var fixture_weights: Dictionary = test_service.config.temporary_offer_weights
		fixture_weights.card_pack_count = {"0": 1}
		fixture_weights.sticker_pack_count = {"0": 1}
		fixture_weights.single_card_count = {"1": 1}
		fixture_weights.single_card_visibility = {"hidden": 1}
		fixture_weights.hidden_card_hint = {hint: 1}
		var cards: Array[CardData] = [card]
		check(test_service.refresh(cards, [], [], []), "完整商品生成接受提示：" + hint)
		var singles := test_service.offers.filter(func(offer: Dictionary): return offer.kind == "single_card")
		if singles.is_empty():
			check(false, "缺少提示商品：" + hint)
			continue
		var offer: Dictionary = singles[0]
		check(offer.hint == hint and not String(offer.hint_value).is_empty() and (hint == "rarity" or int(offer.price) == int(service.config.hidden_card_other_hint_price)), "提示有真实内容，新非品级提示沿用8金币：" + hint)
		var state := JSON.parse_string(JSON.stringify(test_service.capture_state())) as Dictionary
		var ids: Array[String] = [String(card.id)]
		check(test_service.validate_saved_state(state, ids, [], cards), "提示商品经JSON保存后通过真实定义校验：" + hint)
		if hint in ["spell_trigger_kind", "spell_type", "equipment_type", "resource_type"]:
			var unrelated := definitions.filter(func(other: CardData): return other.card_type != card.card_type)
			check(test_service._candidates_for_hint(unrelated, hint).is_empty(), "种类提示排除不适用的大类：" + hint)
	print("D2-7 shop hint failures: ", failures)
	quit(1 if failures else 0)
