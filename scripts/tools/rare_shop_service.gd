extends "res://scripts/data/ordinary_shop_service.gd"

## 仅供开包实验室使用；普通商店配置、生成规则和持有资格保持各自原实现。
const PACKS := [
	{"pack_id": "ash_ledger", "display_name": "大普通卡包", "guarantee": CardData.Rarity.II},
	{"pack_id": "silvermoon_chapter", "display_name": "大传奇卡包", "guarantee": CardData.Rarity.IV},
]

func load_config() -> bool:
	if not super.load_config(): return false
	config.card_pack_prices.large = 0
	config.refresh = {"initial_price": 0, "price_increment": 0}
	config.action_procurement.enabled = false
	config.scraper.always_available = false
	config.tear_service.always_available = false
	return true

func _eligible_cards(definitions: Array[CardData], _owned_cards: Array, additionally_used: Dictionary = {}) -> Array[CardData]:
	# 测试收藏可重复获得IV，保证反复刷新后仍能测试传奇包；此服务只在实验室实例中使用。
	return super._eligible_cards(definitions, [], additionally_used)

func refresh(card_definitions: Array[CardData], owned_cards: Array, _sticker_definitions: Array[Dictionary], _held_stickers: Array[Dictionary]) -> bool:
	var next_rng := _copy_rng(rng)
	var candidates := _eligible_cards(card_definitions, owned_cards)
	var next_offers: Array[Dictionary] = []
	for specification: Dictionary in PACKS:
		var common: Array[CardData] = []
		var guaranteed: Array[CardData] = []
		for definition: CardData in candidates:
			if String(definition.pack_id) != specification.pack_id: continue
			if definition.rarity == CardData.Rarity.I: common.append(definition)
			if definition.rarity == specification.guarantee: guaranteed.append(definition)
		if common.is_empty() or guaranteed.is_empty(): return false
		var chosen: Array[CardData] = []
		var picked_unique := {}
		var counts := count_owned_cards(owned_cards)
		for draw: int in 5:
			var remaining := _eligible_cards(common if draw < 4 else guaranteed, [], picked_unique)
			var selected := draw_card_candidate(remaining, next_rng, counts)
			if selected == null: return false
			chosen.append(selected)
			counts[selected.id] = int(counts.get(selected.id, 0)) + 1
			if selected.is_unique_while_owned(): picked_unique[selected.id] = true
		next_offers.append({"kind": "card_pack", "pack_id": specification.pack_id, "size": "large", "price": 0,
			"display_name": specification.display_name, "cards": _card_ids(chosen), "offer_id": "rare_test_%d" % next_offers.size()})
	rng.state = next_rng.state
	offers = next_offers
	reveal_by_offer.clear()
	return true
