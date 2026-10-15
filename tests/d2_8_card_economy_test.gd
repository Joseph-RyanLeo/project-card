extends SceneTree

## 真实卡牌资源、确定随机种子与分布检查；不替换正式抽取逻辑。
var assertions := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("经济抽取专项超时"); quit(1))
	var service := OrdinaryShopService.new()
	check(service.initialize(51005), "读取正式经济配置")
	var a: CardData = load("res://resources/cards/musketeer.tres")
	var b: CardData = load("res://resources/cards/town_priest.tres")
	var higher: CardData = load("res://resources/cards/shieldwall_private.tres")
	var collection := OwnedCardCollection.new()
	for index: int in 3: collection.create_card(a, service.rng)
	var counts := service.count_owned_cards(collection.get_cards())
	check(service.card_name_weight(a, counts) == 20 and service.card_name_weight(b, counts) == 100, "三张同名才降至原权重20%，未持有卡保持原权重")
	var pool: Array[CardData] = [a, b]
	var draws := RandomNumberGenerator.new()
	draws.seed = 10005
	var repeated := 0
	for index: int in 6000:
		if service.draw_card_candidate(pool, draws, counts) == a: repeated += 1
	check(repeated > 850 and repeated < 1150, "真实6000次抽取同品级同名卡占比约1/6，而非排除或50%")
	var tier_pool: Array[CardData] = [a, higher]
	var low := 0
	for index: int in 5000:
		if service._draw_by_rarity_weights(tier_pool, draws, CardData.Rarity.I, counts) == a: low += 1
	check(low > 3750 and low < 4150, "降权只作用于同品级种类，不改变I:II的75:20权重")
	collection.remove_by_instance_id(collection.get_cards()[0].instance_id)
	check(service.card_name_weight(a, service.count_owned_cards(collection.get_cards())) == 100, "出售或置换降到两张后恢复原权重")
	var doubles := 0
	for index: int in 5000:
		var pack := service.draw_card_pack(pool, false, 2, draws, collection.get_cards())
		if pack.cards[0] == a and pack.cards[1] == a: doubles += 1
	check(doubles > 325 and doubles < 500, "同包第一抽凑满三张后，第二抽已降权，双抽同名约1/12")
	# 正式主场景只用于取得当前开放卡池；商品、保存验证仍使用真实服务。
	var main: Control = preload("res://scenes/Main.tscn").instantiate()
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-economy-unit.json"
	root.add_child(main)
	await process_frame
	var catalog: Array[CardData] = main._get_shop_card_definitions()
	check(service.refresh(catalog, collection.get_cards(), main._get_shop_sticker_definitions(), []), "正式卡池生成普通和定向商品")
	var registry: Dictionary = main._build_card_definition_registry()
	var card_ids: Array[String] = []
	for definition: CardData in registry.values(): card_ids.append(String(definition.id))
	check(service.validate_saved_state(service.capture_state(), card_ids, [], catalog), "新定向商品通过正式存档校验")
	for action: int in CardData.ActionType.size():
		var directed := service.offers.filter(func(offer: Dictionary): return int(offer.get("procurement_action", -1)) == action)
		check(directed.size() == 3, "每种行动提供一小包、一明牌、一暗牌")
		for offer: Dictionary in directed:
			if offer.kind == "card_pack":
				check(offer.cards.size() == 3 and offer.price == 12 and offer.size == "small", "定向小包沿用3张12金币")
				check(offer.cards.all(func(id: String): return service.supports_action(registry[StringName(id)], action)), "定向小包全部来自对应行动的随从候选")
			else:
				var definition: CardData = registry[StringName(offer.card_id)]
				check(service.supports_action(definition, action) and offer.resolved_action_type == action, "定向单卡匹配公开的行动方式")
				if offer.hidden: check(offer.hint == "action_type" and offer.price == 8, "暗单公开对应行动，沿用8金币")
	var saved := JSON.parse_string(JSON.stringify(service.capture_state())) as Dictionary
	var restored := OrdinaryShopService.new()
	check(restored.initialize(0, saved) and JSON.parse_string(JSON.stringify(restored.capture_state())) == saved, "JSON往返保留报价、方向、真实内容与随机状态，不重抽")
	var bad := saved.duplicate(true)
	for offer: Dictionary in bad.offers:
		if offer.has("procurement_action"):
			offer.procurement_action = 99
			break
	check(not service.validate_saved_state(bad, card_ids, [], catalog), "非法定向方式被拒绝")
	# 用正式资源的独立定义副本验证多行动获取，不修改共享资源。
	var multiple := a.duplicate(false) as CardData
	multiple.acquisition_action_types.assign([CardData.ActionType.MELEE, CardData.ActionType.RANGED])
	check(service.supports_action(multiple, CardData.ActionType.RANGED) and not service.supports_action(multiple, CardData.ActionType.HEAL), "多行动卡只进入其支持的方向")
	var preview := main._create_shop_preview_owned(multiple, {"instance_seed": "51005", "resolved_action_type": CardData.ActionType.RANGED}) as OwnedCard
	check(preview.resolved_action_type == CardData.ActionType.RANGED and SquadData.from_owned_card(preview).get_effective_action_type() == CardData.ActionType.RANGED, "定向预览与小队实际行动一致")
	main.queue_free()
	await process_frame
	print("卡牌经济抽取：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
