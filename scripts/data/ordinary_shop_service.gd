class_name OrdinaryShopService
extends RefCounted

const HIDDEN_HINTS: Array[String] = ["rarity", "action_type", "race", "card_type", "spell_trigger_kind", "spell_type", "equipment_type", "resource_type"]

## 普通商店的候选筛选、报价生成和开包抽取。价格/权重均来自Demo JSON配置。

# 仅用于读取本次平衡前已生成的商品；新卡池始终读取当前CardData。
const PREVIOUS_CARD_RULES := {
	&"moonlight_treant": {"action_type": CardData.ActionType.HEAL},
	&"ironheart_pendant": {"rarity": CardData.Rarity.III},
}
const CONFIG_PATH := "res://data/demo2/ordinary_shop_config.json"
const CardPackRegistryScript = preload("res://scripts/data/card_pack_registry.gd")

var config: Dictionary = {}
var rng := RandomNumberGenerator.new()
var refresh_count: int = 0
var offers: Array[Dictionary] = []
var reveal_by_offer: Dictionary = {}


func load_config() -> bool:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false
	config = parsed as Dictionary
	return not config.is_empty()


func initialize(seed_value: int, saved_state: Dictionary = {}) -> bool:
	if config.is_empty() and not load_config():
		return false
	if not validate_saved_state(saved_state):
		return false
	rng.seed = seed_value
	refresh_count = int(saved_state.get("refresh_count", 0))
	if saved_state.has("rng_seed"):
		rng.seed = int(String(saved_state["rng_seed"]))
	if saved_state.has("rng_state"):
		rng.state = int(String(saved_state["rng_state"]))
	offers.assign((saved_state.get("offers", []) as Array).duplicate(true))
	reveal_by_offer = (saved_state.get("reveals", {}) as Dictionary).duplicate(true)
	return true


func validate_saved_state(
	saved_state: Dictionary,
	card_ids: Array[String] = [],
	sticker_ids: Array[String] = [],
	card_definitions: Array[CardData] = []
) -> bool:
	if saved_state.is_empty():
		return true
	var count_value: Variant = saved_state.get("refresh_count", 0)
	var offers_value: Variant = saved_state.get("offers", [])
	var reveals_value: Variant = saved_state.get("reveals", {})
	if not _is_nonnegative_integer(count_value) or not offers_value is Array or not reveals_value is Dictionary:
		return false
	if saved_state.has("rng_state") != saved_state.has("rng_seed"):
		return false
	if saved_state.has("rng_state"):
		var state_value: Variant = saved_state["rng_state"]
		if not _is_decimal_integer(state_value):
			return false
		if int(String(state_value)) == 0:
			return false
	if saved_state.has("rng_seed"):
		var seed_value: Variant = saved_state["rng_seed"]
		if not _is_decimal_integer(seed_value):
			return false
	var seen_offer_ids: Dictionary = {}
	var cards_by_id: Dictionary = {}
	for definition: CardData in card_definitions:
		if definition != null:
			cards_by_id[String(definition.id)] = definition
	for value: Variant in offers_value:
		if not value is Dictionary:
			return false
		var offer := value as Dictionary
		var offer_id := String(offer.get("offer_id", ""))
		var kind := String(offer.get("kind", ""))
		if offer_id.is_empty() or seen_offer_ids.has(offer_id) or not _is_nonnegative_integer(offer.get("price", 0)):
			return false
		if offer.has("sold") and not offer["sold"] is bool:
			return false
		seen_offer_ids[offer_id] = true
		var procurement_action := -1
		if offer.has("procurement_action"):
			if not _is_nonnegative_integer(offer.procurement_action) or int(offer.procurement_action) >= CardData.ActionType.size() or kind not in ["card_pack", "single_card"]:
				return false
			procurement_action = int(offer.procurement_action)
		match kind:
			"card_pack":
				var size := String(offer.get("size", ""))
				if procurement_action >= 0 and size != "small": return false
				var expected_count := int((config.get("card_pack_sizes", {}) as Dictionary).get(size, 0))
				var cards: Variant = offer.get("cards", null)
				if expected_count <= 0 or not cards is Array or cards.size() != expected_count or int(offer.get("price", -1)) != int((config.get("card_pack_prices", {}) as Dictionary).get(size, -2)):
					return false
				for card_id_value: Variant in cards:
					if not card_id_value is String or (not card_ids.is_empty() and not card_ids.has(String(card_id_value))):
						return false
				var pack_definitions: Array[CardData] = []
				var seen_iv: Dictionary = {}
				for card_id_value: Variant in cards:
					var definition := _definition_for_saved_offer(cards_by_id.get(String(card_id_value)) as CardData, offer)
					if definition != null:
						if procurement_action >= 0 and not supports_action(definition, procurement_action): return false
						if procurement_action < 0 and definition.pack_id != StringName(offer.get("pack_id", "ash_ledger")): return false
						pack_definitions.append(definition)
						if definition.rarity == CardData.Rarity.IV:
							if seen_iv.has(definition.id):
								return false
							seen_iv[definition.id] = true
				if not card_definitions.is_empty() and (pack_definitions.size() != expected_count or (size == "large" and not _contains_rarity_at_least(pack_definitions, _configured_minimum_pack_rarity()))):
					return false
			"sticker_pack":
				var stickers: Variant = offer.get("stickers", null)
				var sticker_config := config.get("sticker_pack", {}) as Dictionary
				var expected_stickers := int(sticker_config.get("sticker_count", 0))
				if not stickers is Array or expected_stickers <= 0 or stickers.size() != expected_stickers or int(offer.get("price", -1)) != int(sticker_config.get("price", -2)):
					return false
				for sticker_value: Variant in stickers:
					if not sticker_value is Dictionary or String((sticker_value as Dictionary).get("id", "")).is_empty() or String((sticker_value as Dictionary).get("target", "emblem")) not in ["emblem", "rune"] or (not sticker_ids.is_empty() and not sticker_ids.has(String((sticker_value as Dictionary).get("id", "")))):
						return false
			"single_card":
				var card_id := String(offer.get("card_id", ""))
				if card_id.is_empty() or (not card_ids.is_empty() and not card_ids.has(card_id)) or not offer.get("hidden", false) is bool or not _is_decimal_integer(offer.get("instance_seed", null)):
					return false
				var hidden := bool(offer.get("hidden", false))
				var hint := String(offer.get("hint", ""))
				if (hidden and hint not in HIDDEN_HINTS) or (not hidden and not hint.is_empty()):
					return false
				if not card_definitions.is_empty():
					var definition := _definition_for_saved_offer(cards_by_id.get(card_id) as CardData, offer)
					if definition == null:
						return false
					if procurement_action >= 0 and (not supports_action(definition, procurement_action) or int(offer.get("resolved_action_type", -1)) != procurement_action or (hidden and hint != "action_type")): return false
					var expected_price := int((config.get("visible_card_prices", {}) as Dictionary).get(_rarity_key(definition.rarity), 0))
					var expected_hint_value := ""
					if hidden:
						if not _hint_applies_to_card(definition, hint):
							return false
						if hint == "action_type":
							var action_value := int(offer.get("resolved_action_type", -1))
							var valid_actions: Array = definition.acquisition_action_types if not definition.acquisition_action_types.is_empty() else [definition.action_type]
							if not valid_actions.has(action_value):
								return false
							expected_hint_value = CardData.get_action_type_name_for(action_value as CardData.ActionType)
						else:
							expected_hint_value = _hint_value(definition, hint)
						expected_price = int((config.get("hidden_card_rarity_hint_prices", {}) as Dictionary).get(_rarity_key(definition.rarity), 0)) if hint == "rarity" else int(config.get("hidden_card_other_hint_price", 0))
					if String(offer.get("hint_value", "")) != expected_hint_value:
						return false
					if int(offer.get("price", -1)) != expected_price:
						return false
				if not hidden and offer.has("resolved_action_type") and procurement_action < 0:
					return false
			"scraper":
				if int(offer.get("price", -1)) != int((config.get("scraper", {}) as Dictionary).get("price", 2)):
					return false
			"tear_service":
				if offer.has("price"):
					return false
			_:
				return false
	for offer_id_value: Variant in reveals_value:
		var offer_id := String(offer_id_value)
		var card_id := String(reveals_value[offer_id_value])
		if not seen_offer_ids.has(offer_id) or card_id.is_empty() or (not card_ids.is_empty() and not card_ids.has(card_id)):
			return false
		var referenced_offer: Dictionary
		for offer: Dictionary in offers_value:
			if String(offer.get("offer_id", "")) == offer_id:
				referenced_offer = offer
				break
		if referenced_offer.get("kind") != "single_card" or not bool(referenced_offer.get("hidden", false)) or not bool(referenced_offer.get("sold", false)) or String(referenced_offer.get("card_id", "")) != card_id:
			return false
	return true


func _is_decimal_integer(value: Variant) -> bool:
	return (value is String and String(value).is_valid_int()) or value is int


func _definition_for_saved_offer(definition: CardData, offer: Dictionary) -> CardData:
	if definition == null: return null
	var previous: Dictionary = PREVIOUS_CARD_RULES.get(definition.id, {})
	if previous.is_empty(): return definition
	var result := definition
	var saved_action := int(offer.get("procurement_action", offer.get("resolved_action_type", -1)))
	if previous.has("action_type") and saved_action == int(previous.action_type) and not supports_action(definition, saved_action):
		result = definition.duplicate() as CardData
		result.action_type = previous.action_type as CardData.ActionType
	if previous.has("rarity") and offer.get("kind") == "single_card":
		var old_rarity := int(previous.rarity)
		var hidden := bool(offer.get("hidden", false))
		var old_quote := int((config.get("visible_card_prices", {}) as Dictionary).get(_rarity_key(old_rarity), -1))
		var old_rarity_hint: bool = hidden and offer.get("hint") == "rarity" and offer.get("hint_value") == _rarity_key(old_rarity)
		if old_rarity_hint or (not hidden and int(offer.get("price", -1)) == old_quote):
			if result == definition: result = definition.duplicate() as CardData
			result.rarity = old_rarity as CardData.Rarity
	return result


func _is_nonnegative_integer(value: Variant) -> bool:
	if not (value is int or value is float) or not is_finite(float(value)):
		return false
	return float(value) >= 0.0 and float(value) == floor(float(value))


func capture_state() -> Dictionary:
	return {
		"rng_seed": str(rng.seed),
		"rng_state": str(rng.state),
		"refresh_count": refresh_count,
		"offers": offers.duplicate(true),
		"reveals": reveal_by_offer.duplicate(true),
	}


func refresh_price() -> int:
	var refresh_config := config.get("refresh", {}) as Dictionary
	return int(refresh_config.get("initial_price", 1)) * int(refresh_config.get("price_multiplier", 2)) ** refresh_count


func refresh(card_definitions: Array[CardData], owned_cards: Array, sticker_definitions: Array[Dictionary], held_stickers: Array[Dictionary]) -> bool:
	var next_rng := _copy_rng(rng)
	var candidates := _eligible_cards(card_definitions, owned_cards)
	var sticker_candidates := _eligible_stickers(sticker_definitions, held_stickers, [])
	var next_offers: Array[Dictionary] = []
	var weights := config.get("temporary_offer_weights", {}) as Dictionary
	var count := _weighted_key(weights.get("card_pack_count", {}), next_rng)
	if count < 0:
		return false
	var themed_pools: Dictionary = {}
	for card: CardData in candidates:
		if not themed_pools.has(card.pack_id): themed_pools[card.pack_id] = []
		(themed_pools[card.pack_id] as Array).append(card)
	var size_weights := weights.get("card_pack_size", {}) as Dictionary
	for _index: int in count:
		var size_key := _weighted_string(size_weights, next_rng)
		var is_large := size_key == "large"
		var count_in_pack := int((config.get("card_pack_sizes", {}) as Dictionary).get(size_key, 0))
		if themed_pools.is_empty(): return false
		var themes: Array = themed_pools.keys()
		if is_large:
			themes = themes.filter(func(id: StringName) -> bool:
				var themed: Array[CardData] = []
				themed.assign(themed_pools[id])
				return _contains_rarity_at_least(themed, _configured_minimum_pack_rarity())
			)
		if themes.is_empty(): return false
		var pack_id: StringName = themes[next_rng.randi_range(0, themes.size() - 1)]
		var pool: Array[CardData] = []
		pool.assign(themed_pools[pack_id])
		var generated := draw_card_pack(pool, is_large, count_in_pack, next_rng, owned_cards)
		if not bool(generated.get("success", false)):
			return false
		next_offers.append({"kind": "card_pack", "pack_id": String(pack_id), "size": size_key, "price": int((config.get("card_pack_prices", {}) as Dictionary).get(size_key, 0)), "cards": _card_ids(generated.cards), "offer_id": "card_%d" % next_offers.size()})
	var sticker_count := _weighted_key(weights.get("sticker_pack_count", {}), next_rng)
	if sticker_count < 0 or (sticker_count > 0 and sticker_candidates.is_empty()):
		return false
	for _index: int in sticker_count:
		var pack_cards: Array[Dictionary] = []
		for _draw: int in int((config.get("sticker_pack", {}) as Dictionary).get("sticker_count", 5)):
			var sticker := _draw_sticker(sticker_candidates, next_rng)
			if sticker.is_empty():
				return false
			pack_cards.append(sticker)
			if String(sticker.get("id", "")) == "万能贴纸":
				sticker_candidates = _eligible_stickers(sticker_definitions, held_stickers, pack_cards)
		next_offers.append({"kind": "sticker_pack", "price": int((config.get("sticker_pack", {}) as Dictionary).get("price", 15)), "stickers": pack_cards, "offer_id": "sticker_%d" % next_offers.size()})
	if not candidates.is_empty():
		var single_weights := weights.get("single_card_count", {}) as Dictionary
		var has_single := _weighted_key(single_weights, next_rng) > 0
		if has_single:
			var visibility := _weighted_string(weights.get("single_card_visibility", {}), next_rng)
			var hidden := visibility == "hidden"
			var definition: CardData = draw_card_candidate(candidates, next_rng, count_owned_cards(owned_cards))
			var hint := ""
			var hint_value := ""
			var resolved_action_type := -1
			var price := int((config.get("visible_card_prices", {}) as Dictionary).get(_rarity_key(definition.rarity), 0))
			if hidden:
				var hint_result := _choose_valid_hint(candidates, weights.get("hidden_card_hint", {}), next_rng)
				if hint_result.is_empty():
					return false
				hint = String(hint_result.get("hint", ""))
				var matching: Array[CardData] = hint_result.get("matching", []) as Array[CardData]
				if matching.is_empty():
					return false
				definition = draw_card_candidate(matching, next_rng, count_owned_cards(owned_cards))
				if hint == "action_type":
					var action_options: Array = definition.acquisition_action_types if not definition.acquisition_action_types.is_empty() else [definition.action_type]
					resolved_action_type = int(action_options[next_rng.randi_range(0, action_options.size() - 1)])
					hint_value = CardData.get_action_type_name_for(resolved_action_type as CardData.ActionType)
				else:
					hint_value = _hint_value(definition, hint)
				if hint == "rarity":
					price = int((config.get("hidden_card_rarity_hint_prices", {}) as Dictionary).get(_rarity_key(definition.rarity), 0))
				else:
					price = int(config.get("hidden_card_other_hint_price", 8))
			var single_offer := {"kind": "single_card", "card_id": String(definition.id), "price": price, "hidden": hidden, "hint": hint, "hint_value": hint_value, "offer_id": "single_%d" % next_offers.size(), "instance_seed": str(next_rng.randi())}
			if resolved_action_type >= 0:
				single_offer["resolved_action_type"] = resolved_action_type
			next_offers.append(single_offer)
	if bool(config.get("action_procurement", {}).get("enabled", false)):
		_append_action_procurement(next_offers, candidates, owned_cards, next_rng)
	# 两项常驻服务独立生成且刷新不会移除；不消耗另一条随机流。
	if bool((config.get("scraper", {}) as Dictionary).get("always_available", true)):
		next_offers.append({"kind": "scraper", "price": int((config.get("scraper", {}) as Dictionary).get("price", 2)), "offer_id": "scraper"})
	if bool((config.get("tear_service", {}) as Dictionary).get("always_available", true)):
		next_offers.append({"kind": "tear_service", "offer_id": "tear"})
	rng.state = next_rng.state
	offers = next_offers
	reveal_by_offer.clear()
	return true


func count_owned_cards(owned_cards: Array) -> Dictionary:
	var counts: Dictionary = {}
	for owned: OwnedCard in owned_cards:
		if owned != null and owned.card_data != null:
			counts[owned.card_data.id] = int(counts.get(owned.card_data.id, 0)) + 1
	return counts


func card_name_weight(definition: CardData, held_counts: Dictionary) -> int:
	var settings: Dictionary = config.get("duplicate_card_weight", {})
	return int(settings.get("reduced_weight", 20)) if int(held_counts.get(definition.id, 0)) >= int(settings.get("threshold", 3)) else int(settings.get("normal_weight", 100))


func draw_card_candidate(candidates: Array[CardData], source_rng: RandomNumberGenerator, held_counts: Dictionary = {}) -> CardData:
	var total := 0
	for definition: CardData in candidates:
		total += card_name_weight(definition, held_counts)
	if total <= 0: return null
	var roll := source_rng.randi_range(1, total)
	for definition: CardData in candidates:
		roll -= card_name_weight(definition, held_counts)
		if roll <= 0: return definition
	return null


func supports_action(definition: CardData, action: int) -> bool:
	if definition == null or definition.card_type != CardData.CardType.MINION: return false
	return definition.acquisition_action_types.has(action) if not definition.acquisition_action_types.is_empty() else int(definition.action_type) == action


func _append_action_procurement(next_offers: Array[Dictionary], candidates: Array[CardData], owned_cards: Array, source_rng: RandomNumberGenerator) -> void:
	var counts := count_owned_cards(owned_cards)
	for action: int in CardData.ActionType.size():
		var pool: Array[CardData] = []
		for definition: CardData in candidates:
			if supports_action(definition, action): pool.append(definition)
		if pool.is_empty(): continue
		var pack := draw_card_pack(pool, false, int(config.card_pack_sizes.small), source_rng, owned_cards)
		if not pack.success: continue
		next_offers.append({"kind": "card_pack", "size": "small", "procurement_action": action, "price": int(config.card_pack_prices.small), "cards": _card_ids(pack.cards), "offer_id": "action_%d_pack" % action})
		for hidden: bool in [false, true]:
			var definition := draw_card_candidate(pool, source_rng, counts)
			var price := int(config.hidden_card_other_hint_price) if hidden else int(config.visible_card_prices[_rarity_key(definition.rarity)])
			next_offers.append({"kind": "single_card", "card_id": String(definition.id), "procurement_action": action, "resolved_action_type": action, "price": price, "hidden": hidden, "hint": "action_type" if hidden else "", "hint_value": CardData.get_action_type_name_for(action as CardData.ActionType) if hidden else "", "offer_id": "action_%d_%s" % [action, "hidden" if hidden else "visible"], "instance_seed": str(source_rng.randi())})


func draw_card_pack(card_definitions: Array[CardData], is_large: bool, draw_count: int, source_rng: RandomNumberGenerator = null, owned_cards: Array = []) -> Dictionary:
	var active_rng := _copy_rng(source_rng if source_rng != null else rng)
	if draw_count <= 0:
		return {"success": false, "reason": "invalid_pack_size"}
	var picks: Array[CardData] = []
	var picked_iv: Dictionary = {}
	var held_counts := count_owned_cards(owned_cards)
	var minimum_rarity := _configured_minimum_pack_rarity()
	if minimum_rarity < CardData.Rarity.I or minimum_rarity > CardData.Rarity.V:
		return {"success": false, "reason": "invalid_guarantee_rarity"}
	for draw_index: int in draw_count:
		var eligible := _eligible_cards(card_definitions, owned_cards, picked_iv)
		var guarantee := is_large and draw_index == draw_count - 1 and not _contains_rarity_at_least(picks, minimum_rarity)
		var selected := _draw_by_rarity_weights(eligible, active_rng, minimum_rarity if guarantee else CardData.Rarity.I, held_counts)
		if selected == null:
			return {"success": false, "reason": "no_valid_candidate"}
		picks.append(selected)
		held_counts[selected.id] = int(held_counts.get(selected.id, 0)) + 1
		if selected.rarity == CardData.Rarity.IV:
			picked_iv[selected.id] = true
	if source_rng == null:
		rng.state = active_rng.state
	else:
		source_rng.state = active_rng.state
	return {"success": true, "cards": picks}


func _eligible_cards(definitions: Array[CardData], owned_cards: Array, additionally_used: Dictionary = {}) -> Array[CardData]:
	var eligible: Array[CardData] = []
	var held_iv: Dictionary = additionally_used.duplicate(true)
	for owned_value: Variant in owned_cards:
		var owned: Object = owned_value as Object
		if owned != null and owned.get("card_data") is CardData:
			var owned_definition := owned.get("card_data") as CardData
			if owned_definition.rarity == CardData.Rarity.IV:
				held_iv[owned_definition.id] = true
	var allowed: Array = config.get("allowed_pack_ids", []) as Array
	var excluded: Array = config.get("excluded_pack_ids", []) as Array
	for definition: CardData in definitions:
		if definition == null or not definition.is_available or definition.is_derived:
			continue
		var pack_allowed := false
		var pack_excluded := false
		for pack: Variant in allowed:
			if CardPackRegistryScript.belongs_to_pack(definition, StringName(String(pack))): pack_allowed = true
		for pack: Variant in excluded:
			if CardPackRegistryScript.belongs_to_pack(definition, StringName(String(pack))): pack_excluded = true
		if not pack_allowed or pack_excluded:
			continue
		if definition.rarity == CardData.Rarity.V:
			continue
		if definition.rarity == CardData.Rarity.IV and held_iv.has(definition.id):
			continue
		eligible.append(definition)
	return eligible


func _draw_by_rarity_weights(candidates: Array[CardData], source_rng: RandomNumberGenerator, minimum_rarity: int = CardData.Rarity.I, held_counts: Dictionary = {}) -> CardData:
	var weighted := get_effective_card_tier_weights(candidates, minimum_rarity)
	var total := int(weighted.get("total", 0))
	if total <= 0:
		return null
	var roll := source_rng.randi_range(1, total)
	for tier: Dictionary in weighted.get("tiers", []) as Array:
		roll -= int(tier.weight)
		if roll <= 0:
			var pool := tier.pool as Array[CardData]
			return draw_card_candidate(pool, source_rng, held_counts)
	return null


func get_effective_card_tier_weights(candidates: Array[CardData], minimum_rarity: int = CardData.Rarity.I) -> Dictionary:
	var tiers: Array[Dictionary] = []
	var total := 0
	var weights := config.get("card_rarity_weights", {}) as Dictionary
	for rarity: int in range(CardData.Rarity.size()):
		if rarity < minimum_rarity:
			continue
		var pool: Array[CardData] = []
		for definition: CardData in candidates:
			if definition.rarity == rarity:
				pool.append(definition)
		var weight := int(weights.get(_rarity_key(rarity), 0)) if not pool.is_empty() else 0
		if weight > 0:
			total += weight
			tiers.append({"rarity": rarity, "weight": weight, "pool": pool})
	return {"total": total, "tiers": tiers}


func _eligible_stickers(definitions: Array[Dictionary], held: Array[Dictionary], pack_picks: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var weights := config.get("sticker_rarity_weights", {}) as Dictionary
	var unlocks := config.get("sticker_unlocks", {}) as Dictionary
	var universal_held := false
	for item: Dictionary in held + pack_picks:
		if String(item.get("id", item.get("emblem_id", ""))) == "万能贴纸":
			universal_held = true
	for definition: Dictionary in definitions:
		var id := String(definition.get("id", ""))
		var rarity := int(definition.get("rarity", -1))
		if rarity < 0 or rarity >= CardData.Rarity.V or int(weights.get(_rarity_key(rarity), 0)) <= 0:
			continue
		if id == "万能贴纸" and universal_held:
			continue
		if definition.get("target", "emblem") == "rune" and not _is_unlocked_rune_sticker(id, unlocks):
			continue
		result.append(definition.duplicate(true))
	return result


func _draw_sticker(candidates: Array[Dictionary], source_rng: RandomNumberGenerator) -> Dictionary:
	var tiers: Array[Dictionary] = []
	var weights := config.get("sticker_rarity_weights", {}) as Dictionary
	var total := 0
	for rarity: int in range(CardData.Rarity.V):
		var pool: Array[Dictionary] = []
		for definition: Dictionary in candidates:
			if int(definition.get("rarity", -1)) == rarity:
				pool.append(definition)
		var weight := int(weights.get(_rarity_key(rarity), 0)) if not pool.is_empty() else 0
		if weight > 0:
			total += weight
			tiers.append({"weight": weight, "pool": pool})
	if total == 0:
		return {}
	var roll := source_rng.randi_range(1, total)
	for tier: Dictionary in tiers:
		roll -= int(tier.weight)
		if roll <= 0:
			var pool := tier.pool as Array[Dictionary]
			return pool[source_rng.randi_range(0, pool.size() - 1)].duplicate(true)
	return {}


func _choose_valid_hint(candidates: Array[CardData], hint_weights: Dictionary, source_rng: RandomNumberGenerator) -> Dictionary:
	var valid: Array[String] = []
	for hint: String in HIDDEN_HINTS:
		for definition: CardData in candidates:
			if _hint_applies_to_card(definition, hint):
				valid.append(hint)
				break
	var total := 0
	for hint: String in valid:
		total += int(hint_weights.get(hint, 0))
	if total <= 0:
		return {}
	var roll := source_rng.randi_range(1, total)
	for hint: String in valid:
		roll -= int(hint_weights.get(hint, 0))
		if roll <= 0:
			var matching := _candidates_for_hint(candidates, hint)
			if matching.is_empty():
				return {}
			return {"hint": hint, "matching": matching}
	return {}


func _candidates_for_hint(candidates: Array[CardData], hint: String) -> Array[CardData]:
	var matching: Array[CardData] = []
	for definition: CardData in candidates:
		if _hint_applies_to_card(definition, hint):
			matching.append(definition)
	return matching


func _hint_applies_to_card(definition: CardData, hint: String) -> bool:
	match hint:
		"rarity": return true
		"race": return definition.card_type == CardData.CardType.MINION
		"action_type": return definition.card_type == CardData.CardType.MINION
		"card_type": return true
		"spell_trigger_kind": return definition.card_type == CardData.CardType.SPELL and definition.spell_trigger_kind != CardData.SpellTriggerKind.UNASSIGNED
		"spell_type": return definition.card_type == CardData.CardType.SPELL
		"equipment_type": return definition.card_type == CardData.CardType.EQUIPMENT
		"resource_type": return definition.card_type == CardData.CardType.RESOURCE
	return false


func _configured_minimum_pack_rarity() -> int:
	var key := String((config.get("large_pack_guarantee_minimum_rarity", "II")))
	return ["I", "II", "III", "IV", "V"].find(key)


func _hint_value(definition: CardData, hint: String) -> String:
	match hint:
		"rarity": return _rarity_key(definition.rarity)
		"action_type": return CardData.get_action_type_name_for(definition.action_type)
		"race": return ["人类", "精灵", "矮人", "构装", "元素", "亡灵", "恶魔", "野兽", "植物"][definition.race_type]
		"card_type": return ["随从", "装备", "法术", "资源"][definition.card_type]
		"spell_trigger_kind": return ["未分配", "即时", "条件", "准备"][definition.spell_trigger_kind]
		"spell_type": return definition.get_spell_type_name()
		"equipment_type": return definition.get_equipment_type_name()
		"resource_type": return definition.get_resource_type_name()
	return ""


func _is_unlocked_rune_sticker(id: String, unlocks: Dictionary) -> bool:
	var element_keys := {"水贴纸": "water", "木贴纸": "wood", "火贴纸": "fire", "光贴纸": "light", "暗贴纸": "dark", "万能贴纸": "universal", "混沌贴纸": "chaos"}
	return bool(unlocks.get(element_keys.get(id, ""), false))


func _contains_rarity_at_least(cards: Array[CardData], rarity: int) -> bool:
	for card: CardData in cards:
		if int(card.rarity) >= rarity:
			return true
	return false


func _weighted_key(weights: Dictionary, source_rng: RandomNumberGenerator) -> int:
	var total := 0
	var entries: Array[Dictionary] = []
	for key: Variant in weights:
		var weight := maxi(int(weights[key]), 0)
		if weight > 0:
			total += weight
			entries.append({"key": String(key), "weight": weight})
	if total <= 0:
		return -1
	var roll := source_rng.randi_range(1, total)
	for entry: Dictionary in entries:
		roll -= int(entry.weight)
		if roll <= 0:
			return int(entry.key)
	return -1


func _weighted_string(weights: Dictionary, source_rng: RandomNumberGenerator) -> String:
	var total := 0
	for key: Variant in weights:
		total += maxi(int(weights[key]), 0)
	if total <= 0:
		return ""
	var roll := source_rng.randi_range(1, total)
	for key: Variant in weights:
		roll -= maxi(int(weights[key]), 0)
		if roll <= 0:
			return String(key)
	return ""


func _copy_rng(source: RandomNumberGenerator) -> RandomNumberGenerator:
	var copy := RandomNumberGenerator.new()
	copy.seed = source.seed
	copy.state = source.state
	return copy


func _rarity_key(rarity: int) -> String:
	return ["I", "II", "III", "IV", "V"][clampi(rarity, 0, 4)]


func _card_ids(cards: Array[CardData]) -> Array[String]:
	var result: Array[String] = []
	for card: CardData in cards:
		result.append(String(card.id))
	return result
