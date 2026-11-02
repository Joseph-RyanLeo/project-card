class_name RunScoreService
extends RefCounted

## 只读计分：读取完整实例，不读取堆叠后的可见面，也不修改卡牌。
const Library = preload("res://scripts/data/emblem_library_data.gd")
const Inventory = preload("res://scripts/data/emblem_sticker_inventory.gd")
const Save = preload("res://scripts/data/run_save_service.gd")
const GRADE := [10, 20, 40, 80, 160]
const SURFACE := [0, 5, 10, 20, 30, 40]
const ART := [0, 40, 40]
const EMBLEM := {0: 5, 1: 10, 2: 20, 4: 15}


static func sticker_score(sticker: Dictionary) -> int:
	if sticker.is_empty(): return 0
	if sticker.has("wound_id"): return 5
	var id := StringName(sticker.get("emblem_id", ""))
	for definition: Dictionary in Library.DEFINITIONS:
		if definition.id == id:
			return int(EMBLEM.get(int(definition.rarity), 0)) + Library.get_score_contribution(id)
	return 0


static func card_score(card: OwnedCard) -> Dictionary:
	var parts := {"grade": GRADE[int(card.card_data.rarity)], "surface": SURFACE[int(card.surface_finish)], "art": ART[int(card.art_finish)], "stickers": 0, "runes": 0, "pattern": 0}
	for slots: Array in [card.emblem_slots, card.wound_slots, card.rune_stickers]:
		for sticker: Dictionary in slots: parts.stickers += sticker_score(sticker)
	# 单张小队复用既有覆盖后元素及万能贴纸判型；不会引入其他卡的遮挡。
	var squad := SquadData.from_owned_card(card)
	var slots := squad.get_visible_rune_slots()
	for slot: Dictionary in slots:
		if not slot.hidden: parts.runes += 3
	var pattern := squad.get_rune_pattern_result()
	if pattern.pattern_type == RunePatternResult.PatternType.THREE_OF_A_KIND: parts.pattern = 20
	elif pattern.pattern_type == RunePatternResult.PatternType.PAIR: parts.pattern = 10
	var total := 0
	for amount: int in parts.values(): total += amount
	return {"instance_id": String(card.instance_id), "card_id": String(card.card_data.id), "name": card.card_data.display_name, "parts": parts, "total": total}


static func calculate(cards: Array[OwnedCard], exhausted: Dictionary, inventory: Array, gold: int, outcome: String, day: int, results: Array, protection: int) -> Dictionary:
	var eligible := outcome != "abandoned" or day >= 3
	var all_cards: Dictionary = {}
	for card: OwnedCard in cards:
		if not card.card_data.is_derived: all_cards[String(card.instance_id)] = card
	for id: String in exhausted:
		if all_cards.has(id): continue
		var decoded := Save.new()._decode_collection_state({"cards": [exhausted[id]]}, {}, false, false, Save.SCHEMA_VERSION, false, false)
		if decoded.get("success", false):
			var card := OwnedCard.new()
			card.restore_state(decoded.state.cards[0])
			all_cards[id] = card
	var entries: Array[Dictionary] = []
	var base := 0
	for card: OwnedCard in all_cards.values():
		var entry := card_score(card)
		entry["exhausted"] = exhausted.has(String(card.instance_id))
		var encoded := Save.new()._encode_collection_state({"cards": [card.capture_state()]})
		entry["snapshot"] = encoded.cards[0] if not encoded.is_empty() else {}
		entries.append(entry)
		base += int(entry.total)
	var toolbox: Array[Dictionary] = []
	for sticker: Dictionary in inventory:
		if Inventory.is_dropped(sticker): continue
		var score := sticker_score(sticker)
		toolbox.append({"name": String(sticker.get("emblem_id", sticker.get("wound_id", ""))), "total": score, "sticker": sticker.duplicate(true)})
		base += score
	base += gold
	var completed := 0
	var bosses := 0
	for result: Dictionary in results:
		if result.get("ending", "") in ["boss_loss", "ordinary_loss"] or (outcome == "failed" and int(result.day) == day): continue
		completed += 1
		# 第28天是已确认的额外四天半层终点；这里只支持计分语义，不生成路线内容。
		if result.get("won", false) and (int(result.day) % 8 == 0 or (int(result.day) == 28 and outcome == "cleared")): bosses += 1
	# 用十分之一的整数保存倍率，最后一次整除，避免1.2的浮点误差。
	var multiplier_tenths := 10 + completed + bosses * 5 + (protection * 2 if outcome == "cleared" else 0)
	return {"outcome": outcome, "day": day, "eligible": eligible, "cards": entries, "toolbox": toolbox, "gold": gold, "base": base if eligible else 0, "completed_days": completed, "bosses": bosses, "protection": protection if outcome == "cleared" else 0, "multiplier_tenths": multiplier_tenths, "total": (base * multiplier_tenths) / 10 if eligible else 0}
