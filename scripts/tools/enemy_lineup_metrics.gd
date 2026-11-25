class_name EnemyLineupMetrics
extends RefCounted

const Encounter = preload("res://scripts/flow/enemy_encounter_builder.gd")
const Catalog = preload("res://scripts/flow/enemy_lineup_catalog.gd")


static func prepare(lineup: Dictionary, registry: Dictionary, content: Dictionary, day: int, tutorial: bool, seed_value: int) -> Dictionary:
	var error := Catalog.lineup_error(lineup, registry)
	if not error.is_empty(): return {"error": error}
	var path := Catalog.path_for(lineup, day, tutorial)
	path["battle_seed"] = seed_value
	var builder := Encounter.new()
	var snapshot := builder.build(path, registry, Catalog.rune_reveals(content, day, tutorial), Catalog.emblem_count(content, day, tutorial))
	if snapshot.is_empty(): return {"error": "阵容超出正式战场容量，或装备、伤势、法术组合无效"}
	var built := builder.restore(snapshot, registry)
	if built.is_empty(): return {"error": "无法构建阵容"}
	var board := ResourceBoardState.new()
	var resources: Array[OwnedCard] = []
	if not tutorial:
		if not Encounter.place_level_resources(path, registry, board): return {"error": "资源无法放进正式资源区"}
		resources = board.get_level_resource_cards("enemy")
	var formation: Array[Dictionary] = []
	for row: StringName in [&"enemy_front", &"enemy_back"]:
		var squads: Array = built.rows[row]
		for index: int in squads.size():
			formation.append({"squad_data": squads[index], "row_key": row, "formation_index": index})
	return {"formation": formation, "spells": built.spells, "resources": resources, "resource_board": board.capture_state()}


static func measure(prepared: Dictionary) -> Dictionary:
	var result := {
		"dps": 0.0, "healing": 0.0, "defense": 0.0, "health": 0, "armor": 0, "durability": 0,
		"front": 0, "back": 0, "emblems": 0, "visible_emblems": 0, "wounds": 0, "visible_wounds": 0,
		"wound_levels": 0, "runes": 0, "patterned": 0, "spell_count": 0,
		"patterns": {}, "spell_rarities": [0, 0, 0, 0, 0],
	}
	for entry: Dictionary in prepared.formation:
		var squad := entry.squad_data as SquadData
		var pattern := squad.get_rune_pattern_result()
		var amount := BattleRules.calculate_action_amount(squad.get_preview_action_value(), pattern.pattern_type)
		var rate := float(amount) / squad.get_preview_action_interval()
		match squad.get_effective_action_type():
			CardData.ActionType.HEAL: result.healing += rate
			CardData.ActionType.DEFENSE: result.defense += rate
			_: result.dps += rate
		var health := squad.get_effective_max_health()
		var armor := squad.get_effective_base_armor()
		result.health += health
		result.armor += armor
		result.durability += health + armor
		result["front" if entry.row_key == &"enemy_front" else "back"] += health + armor
		for definition: CardData in squad.horizontal_cards:
			var owned := squad.get_owned_card(definition)
			if owned == null: continue
			result.emblems += owned.emblem_slots.size() - owned.emblem_slots.count({})
			result.wounds += owned.wound_slots.size() - owned.wound_slots.count({})
			result.visible_emblems += squad.get_visible_emblem_slot_indices(definition, true).size()
		var visible_wounds := squad.get_visible_wound_slots(true)
		result.visible_wounds += visible_wounds.size()
		for slot: Dictionary in visible_wounds:
			result.wound_levels += int(squad.get_owned_card(slot.card).wound_slots[slot.slot_index].get("level", 1))
		result.runes += pattern.visible_runes.size()
		if pattern.pattern_type != RunePatternResult.PatternType.CHAOS: result.patterned += 1
		var label := pattern.get_pattern_name()
		result.patterns[label] = result.patterns.get(label, 0) + 1
	for spell: OwnedCard in prepared.spells:
		result.spell_count += 1
		result.spell_rarities[spell.card_data.rarity] += 1
	return result
