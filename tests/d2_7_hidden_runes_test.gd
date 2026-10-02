extends SceneTree

const OwnedCardScript = preload("res://scripts/data/owned_card.gd")
const ElementResolver = preload("res://scripts/battle/battle_element_resolver.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if value:
		print("PASS: " + message)
	else:
		failures += 1
		push_error(message)


func _run() -> void:
	var definition := (load("res://resources/cards/heavy_knight.tres") as CardData).duplicate(true) as CardData
	definition.runes = _runes([CardData.ElementType.WATER, CardData.ElementType.WATER, CardData.ElementType.WATER])
	var owned := OwnedCardScript.new() as OwnedCard
	owned.initialize(definition, &"hidden_rune_test", 0)
	var squad := SquadData.from_owned_card(owned)
	var slots := squad.get_visible_rune_slots()
	check(slots.size() == 3 and slots[0].element == -1 and bool(slots[0].hidden), "玩家未揭曉槽保留物理槽位並標記為隐藏断点")
	check(squad.get_rune_pattern_result().pattern_type == RunePatternResult.PatternType.CHAOS, "全部隐藏符文不组成牌型")
	check(squad.get_visible_rune_stat_bonus(&"max_health") == 0, "隐藏水符文不提供生命")
	owned.rune_revealed[0] = true
	owned.rune_revealed[2] = true
	var split_pattern := squad.get_rune_pattern_result()
	check(split_pattern.pattern_type == RunePatternResult.PatternType.CHAOS and split_pattern.get_element_count(CardData.ElementType.WATER) == 2, "水／隐藏／水保持槽位断点且不计隐藏元素")
	check(ElementResolver.get_element_groups(split_pattern).is_empty(), "隐藏断开的相同元素不会产生派生组")
	owned.rune_revealed[1] = true
	var triple_pattern := squad.get_rune_pattern_result()
	check(triple_pattern.pattern_type == RunePatternResult.PatternType.THREE_OF_A_KIND and triple_pattern.participating_indices == [0, 1, 2], "揭晓后相邻水符文恢复三条并保留正确索引")
	owned.rune_revealed[1] = false
	owned.set_rune_sticker(1, {"instance_id": "water_sticker", "emblem_id": "水贴纸", "element": CardData.ElementType.WATER})
	check(squad.get_visible_rune_stat_bonus(&"max_health") == 6 and not owned.rune_revealed[1], "元素贴纸直接生效但不改变底层揭晓状态")
	owned.set_rune_sticker(1, {})
	check(squad.get_visible_rune_stat_bonus(&"max_health") == 4 and not owned.rune_revealed[1], "移除元素贴纸后恢复已揭晓底层状态")
	print("D2-7 hidden rune failures: ", failures)
	quit(1 if failures else 0)


func _runes(values: Array[CardData.ElementType]) -> Array[CardData.ElementType]:
	return values
