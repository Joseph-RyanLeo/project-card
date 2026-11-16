extends RefCounted

const PotionRules = preload("res://scripts/data/event_potion_rules.gd")
const MINING_COUNTS := [3, 2, 1, 1]
const DONATION_RARITIES := [CardData.Rarity.I, CardData.Rarity.II, CardData.Rarity.III, CardData.Rarity.V]
const CLOVERS := ["四叶草Ⅰ", "四叶草Ⅱ", "四叶草Ⅲ"]


static func can_appear(maze: Node, event_id: String) -> bool:
	if event_id not in ["bald_and_beard", "repair_mining_camp", "undead_friends", "quiet_mining_camp", "lively_mining_camp"]:
		return true
	var camp := _camp(maze)
	var rested: bool = maze._main.profile_progress.run.get("twisted_camp_rested", false)
	match event_id:
		"bald_and_beard": return camp.get("route", "") == ""
		"repair_mining_camp": return camp.get("route") == "self" and int(camp.repairs) < 5
		"undead_friends": return camp.get("route") == "friends" and camp.donations.size() < 3
		"quiet_mining_camp": return camp.get("route") == "self" and int(camp.repairs) == 5 and not rested
		"lively_mining_camp": return camp.get("route") == "friends" and camp.donations.size() == 3 and not rested
	return true


static func option_is_visible(event: Dictionary, option: Dictionary) -> bool:
	var stage := int(event.get("mining_progress", {}).get("stage", 0))
	if option.has("mining_stage"): return int(option.mining_stage) == stage
	if option.get("mining_withdraw", false): return stage > 0
	if option.get("initial_mining_only", false): return stage == 0
	return true


static func blocked_reason(maze: Node, option: Dictionary) -> String:
	var event: Dictionary = maze.run.selected_path
	if not option_is_visible(event, option): return "当前不能选择此步骤"
	if option.has("minimum_armor") and _armor(maze).size() < int(option.minimum_armor): return "需要至少 3 张防具"
	if option.get("mine_prayer", false) and maze._story_owned("ember_empty_bottle").is_empty():
		if not CLOVERS.any(func(id: String) -> bool: return not maze._story_stickers(id).is_empty()):
			return "需要余烬空瓶或四叶草纹章"
	if option.get("camp_donation", false) and _selected_donation(maze).is_empty(): return "请选择一枚未使用的纹章"
	return ""


static func donations(maze: Node) -> Array[Dictionary]:
	var rarities := {}
	for definition: Dictionary in EmblemLibraryData.get_definitions():
		if definition.get("target", "") != "rune" and int(definition.rarity) in DONATION_RARITIES:
			rarities[String(definition.id)] = int(definition.rarity)
	var candidates: Array[Dictionary] = []
	for item: Dictionary in maze._main.emblem_library.get_inventory_state():
		var id := String(item.get("emblem_id", ""))
		if rarities.has(id): candidates.append({"instance_id": item.instance_id, "emblem_id": id, "rarity": rarities[id], "item": item})
	return candidates


static func _selected_donation(maze: Node) -> Dictionary:
	var picker: OptionButton = maze._camp_donation_picker
	if not is_instance_valid(picker) or picker.selected < 1: return {}
	var id := String(picker.get_item_metadata(picker.selected))
	for candidate: Dictionary in donations(maze):
		if candidate.instance_id == id: return candidate
	return {}


static func _camp(maze: Node) -> Dictionary:
	return maze._main.profile_progress.profile.get("twisted_camp", {})


static func _apply_camp(maze: Node, event: Dictionary, action: String, result: Dictionary) -> bool:
	if not can_appear(maze, event.path_id): return false
	var profile: Dictionary = maze._main.profile_progress.profile
	if not profile.has("twisted_camp"): profile["twisted_camp"] = {"route": "", "repairs": 0, "donations": []}
	var camp: Dictionary = profile.twisted_camp
	match action:
		"attack": camp.route = "self"
		"cooperate": camp.route = "friends"
		"repair":
			camp.repairs = int(camp.repairs) + 1
			result["effect_text"] = "修缮进度 %d／5。" % int(camp.repairs)
			if int(camp.repairs) == 5: result.effect_text += " 冷清的营地已解锁。"
		"donate":
			var selected := _selected_donation(maze)
			if selected.is_empty() or not maze._main.emblem_library.consume_returned(selected.item): return false
			camp.donations.append(int(selected.rarity))
			result["effect_text"] = "已捐赠%s，合作修缮进度 %d／3。" % [selected.emblem_id, camp.donations.size()]
			if camp.donations.size() == 3: result.effect_text += " 热闹的营地已解锁。"
		"rest":
			maze._main.profile_progress.run["twisted_camp_rested"] = true
			var value := 1
			var health := 2
			var armor := 0
			var gold := 0
			for rarity: int in camp.donations:
				match rarity:
					CardData.Rarity.I: armor += 1
					CardData.Rarity.II: health += 1
					CardData.Rarity.III: value += 1
					CardData.Rarity.V: gold += 3
			maze._queue_story_buff({"stat": "growth", "base_value": value, "max_health": health, "scope": "floor", "battles": -1}, null)
			if armor > 0: maze._queue_story_buff({"stat": "base_armor", "value": armor, "scope": "floor", "battles": -1}, null)
			maze._main.run_reward_state.add_gold(gold)
			result["effect_text"] = "本层战斗友方随从数值 +%d，生命 +%d，护甲 +%d。获得 %d 金币。" % [value, health, armor, gold]
		_: return false
	return true


static func _armor(maze: Node) -> Array[OwnedCard]:
	var cards: Array[OwnedCard] = maze._main.owned_card_collection.get_cards()
	return cards.filter(func(card: OwnedCard) -> bool:
		return card.card_data.card_type == CardData.CardType.EQUIPMENT and card.card_data.equipment_type == CardData.EquipmentType.ARMOR)


static func apply(maze: Node, event: Dictionary, effect: Dictionary, target: OwnedCard, result: Dictionary, receipt: String, source: Dictionary) -> bool:
	match String(effect.kind):
		"mining_camp": return _apply_camp(maze, event, effect.action, result)
		"mine_resources":
			var cards := _draw_cards(maze, -1, int(effect.count))
			if not _grant_cards(maze, cards, source): return false
			result["effect_text"] = "获得 %d 张扭曲矿脉资源卡。" % cards.size()
			if result.has("lost_card"): result.effect_text += " 失去%s。" % result.lost_card
			if result.has("lost_tree"): result.effect_text += " 失去一枚树纹章。"
		"lose_random_armor":
			var candidates := _armor(maze)
			if candidates.is_empty(): return false
			var removed := candidates[maze.run.rng.randi_range(0, candidates.size() - 1)]
			result["lost_card"] = removed.card_data.display_name
			maze._main._remove_owned_instance_from_rows(removed.instance_id)
			if maze._main.owned_card_collection.remove_by_instance_id(removed.instance_id) == null: return false
		"lose_tree":
			if not maze._consume_story_sticker("树"): return false
			result["lost_tree"] = true
		"mining_lamp_wounds":
			var candidates: Array[OwnedCard] = maze._story_minions()
			candidates = candidates.filter(func(card: OwnedCard) -> bool:
				return card.wound_slots.find({}) >= 0 and not card.wound_slots.any(func(wound: Dictionary) -> bool: return wound.get("wound_id") == "光血"))
			var names: Array[String] = []
			for index: int in mini(2, candidates.size()):
				var card: OwnedCard = candidates.pop_at(maze.run.rng.randi_range(0, candidates.size() - 1))
				var targets: Array[OwnedCard] = [card]
				maze._apply_story_wounds({"kind": "wound", "wound": "光血"}, targets, "%s:%d" % [receipt, index])
				names.append(card.card_data.display_name)
			result["effect_text"] = "光血未能附着。" if names.is_empty() else "%s获得光血伤势。" % "、".join(names)
		"underground_river": _apply_river(maze, event, target, result)
		"mining_sneak", "mining_withdraw", "mining_doorboard":
			return _apply_mining(maze, event, effect, result, source)
		_: return false
	return true


static func river_outcome(card: OwnedCard) -> int:
	var counts := {}
	var wild := 0
	for index: int in card.rune_revealed.size():
		var sticker := card.rune_stickers[index]
		if sticker.get("emblem_id") == "万能贴纸": wild += 1
		elif card.rune_revealed[index] or not sticker.is_empty():
			var element := card.get_effective_rune(index)
			counts[element] = int(counts.get(element, 0)) + 1
	var water := int(counts.get(CardData.ElementType.WATER, 0))
	var wood := int(counts.get(CardData.ElementType.WOOD, 0))
	if maxi(1 - water, 0) + maxi(1 - wood, 0) <= wild: return 0
	if int(counts.get(CardData.ElementType.FIRE, 0)) + wild >= 3: return 1
	if int(counts.get(CardData.ElementType.LIGHT, 0)) + wild >= 2: return 2
	if wood + wild >= 3: return 3
	if water + wild >= 3: return 4
	return 5


static func _apply_river(maze: Node, event: Dictionary, target: OwnedCard, result: Dictionary) -> void:
	var index := river_outcome(target)
	var outcome: Dictionary = event.rune_outcomes[index]
	result["text"] = String(outcome.text).replace("*选择的随从*", target.card_data.display_name)
	result["effect_text"] = outcome.effect_text
	match index:
		0:
			target.progress_by_source[PotionRules.PERMANENT_ZEAL] = int(target.progress_by_source.get(PotionRules.PERMANENT_ZEAL, 0)) + 1
			target.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 1)
			target.apply_permanent_growth(OwnedCard.STAT_BASE_ARMOR, 1)
		1: target.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 2)
		2: maze._queue_story_buff({"stat": "dazzling", "target": "selected", "expire_without_participation": true}, target)
		3:
			target.apply_permanent_growth(OwnedCard.STAT_BASE_ARMOR, 8)
			maze._queue_story_buff({"stat": "zeal", "value": -2}, null)
		4:
			target.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 6)
			maze._queue_story_buff({"stat": "sleep", "value": 5}, null)
			maze._queue_story_buff({"stat": "opening_damage", "value": 2}, null)
		5: maze._queue_story_buff({"stat": "sleep", "value": 5, "target": "selected", "expire_without_participation": true}, target)


static func _resource_pool(registry: Dictionary, tier: int) -> Array[CardData]:
	var pool: Array[CardData] = []
	for card: CardData in registry.values():
		if card.card_type != CardData.CardType.RESOURCE or not card.is_available or card.is_derived or not CardPackRegistry.belongs_to_pack(card, &"twisted_vein"): continue
		if tier == -1 or (card.resource_type == CardData.ResourceType.MINERAL and int(card.rarity) <= tier):
			pool.append(card)
	if tier < 0 or pool.is_empty(): return pool
	var best := 0
	for card: CardData in pool: best = maxi(best, int(card.rarity))
	return pool.filter(func(card: CardData) -> bool: return int(card.rarity) == best)


static func _draw_cards(maze: Node, tier: int, count: int) -> Array[String]:
	var pool := _resource_pool(maze._main._build_card_definition_registry(), tier)
	var ids: Array[String] = []
	if not pool.is_empty():
		for index: int in count:
			ids.append(String(pool[maze.run.rng.randi_range(0, pool.size() - 1)].id))
	return ids


static func _grant_cards(maze: Node, ids: Array[String], source: Dictionary) -> bool:
	var registry: Dictionary = maze._main._build_card_definition_registry()
	var reserved: Array[CardData] = []
	for id: String in ids:
		if maze._main.owned_card_collection.create_card(registry.get(StringName(id)), maze.run.rng, reserved, false, source) == null: return false
	return true


static func _apply_mining(maze: Node, event: Dictionary, effect: Dictionary, result: Dictionary, source: Dictionary) -> bool:
	var progress: Dictionary = event.get("mining_progress", {})
	var stage := int(progress.get("stage", 0))
	var cards: Array[String] = []
	cards.assign(progress.get("cards", []))
	if effect.kind == "mining_sneak":
		cards.append_array(_draw_cards(maze, stage, MINING_COUNTS[stage]))
		if stage < MINING_COUNTS.size() - 1:
			event["mining_progress"] = {"stage": stage + 1, "cards": cards, "roll": result.roll}
			result["mining_continues"] = true
			return true
	elif effect.kind == "mining_doorboard":
		for tier: int in range(stage, CardData.Rarity.IV):
			cards.append_array(_draw_cards(maze, tier, MINING_COUNTS[tier]))
	if not _grant_cards(maze, cards, source): return false
	event.erase("mining_progress")
	result["effect_text"] = ("第四次潜行成功，队伍自动撤退。" if effect.kind == "mining_sneak" else "") + "带回 %d 张矿物卡。" % cards.size()
	return true


static func valid_progress(maze: Node, path: Dictionary) -> bool:
	var progress: Variant = path.mining_progress
	if not progress is Dictionary or path.has("story_result") or path.has("event_battle"): return false
	if not maze.run._whole_number(progress.get("stage")) or int(progress.stage) not in [1, 2, 3]: return false
	if not progress.get("cards") is Array: return false
	var stage := int(progress.stage)
	if not maze.story_events.valid_result(path, {"option_index": stage - 1, "outcome_index": 0, "roll": progress.get("roll")}): return false
	var registry: Dictionary = maze._main._build_card_definition_registry()
	var count := 0
	for tier: int in stage:
		var pool := _resource_pool(registry, tier)
		if pool.is_empty(): continue
		for index: int in MINING_COUNTS[tier]:
			if count >= progress.cards.size() or not progress.cards[count] is String: return false
			if registry.get(StringName(progress.cards[count])) not in pool: return false
			count += 1
	return count == progress.cards.size()


static func grant_full_mining_reward(maze: Node) -> int:
	var cards: Array[String] = []
	for tier: int in MINING_COUNTS.size():
		cards.append_array(_draw_cards(maze, tier, MINING_COUNTS[tier]))
	var source := {"kind": "event", "event_id": "high_risk_mining", "name": "高危开采"}
	return cards.size() if _grant_cards(maze, cards, source) else 0
