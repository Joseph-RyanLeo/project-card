extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _run() -> void:
	var allowed: Array[CardData] = []
	for file: String in DirAccess.get_files_at("res://resources/cards"):
		if not file.ends_with(".tres"): continue
		var definition := load("res://resources/cards/" + file) as CardData
		if definition.is_available and not definition.is_derived and definition.pack_id in [&"ash_ledger", &"ironwall_inscription"] and definition.card_type == CardData.CardType.EQUIPMENT and definition.equipment_type == CardData.EquipmentType.RANGED_WEAPON and definition.rarity <= CardData.Rarity.II: allowed.append(definition)
	check(not allowed.is_empty(), "已实现的铁壁包存在合法远程武器供正向验证")
	var collection := OwnedCardCollection.new()
	collection.enabled_acquisition_packs = ["ash_ledger"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261105
	collection.create_card(load("res://resources/cards/gunsmith_master.tres"), rng)
	check(collection.size() == 1, "灰烬当前无合格远程武器时，不借用未开放包兜底")
	collection = OwnedCardCollection.new()
	collection.enabled_acquisition_packs = ["ash_ledger", "ironwall_inscription"]
	collection.create_card(load("res://resources/cards/gunsmith_master.tres"), rng)
	check(collection.size() == 2, "永久开放铁壁后，获得时正常赠送合法武器")
	check(collection.get_cards().all(func(card: OwnedCard): return card.card_data.pack_id in [&"ash_ledger", &"ironwall_inscription"]), "获得时赠卡严格留在本局启用范围")
	collection = OwnedCardCollection.new()
	collection.enabled_acquisition_packs = ["ash_ledger", "ironwall_inscription"]
	collection.create_card(load("res://resources/cards/gunsmith_master.tres"), rng, allowed)
	check(collection.size() == 1, "同包／后续未开任务包已预留全部合法唯一武器时不重复赠送")
	collection = OwnedCardCollection.new()
	collection.enabled_acquisition_packs = ["ash_ledger", "ironwall_inscription"]
	for definition: CardData in allowed: collection.create_card(definition, rng)
	var before := collection.size()
	collection.create_card(load("res://resources/cards/gunsmith_master.tres"), rng)
	check(collection.size() == before + 1, "实际持有全部合法武器时同样不重复赠送")
	print("D3-4 acquisition: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
