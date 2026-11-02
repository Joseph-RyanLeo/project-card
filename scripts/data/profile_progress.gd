class_name ProfileProgress
extends RefCounted

## 每档局外数据与本局待提交数据。磁盘仍由 RunSaveService 一次写入同一文件。
const VERSION := 1
const INITIAL_HERO := "ioann_warden" # 伊奥恩的存档稳定标识，不使用显示名称作键
const MAX_SELECTION := 8 # 每局最多入藏的单卡数量
const SLOTS_PER_KIND := 3 # 每种卡固定的收藏位置数
const Save = preload("res://scripts/data/run_save_service.gd")

var profile: Dictionary = {
	"created_at": 0, "legacy": false, "points": 0, "discoveries": {"cards": {}, "stickers": {}, "resources": {}},
	"tasks": {"tutorial": {"purchased": true, "completed": false}}, "unlocks": {"heroes": [INITIAL_HERO], "packs": ["ash_ledger"], "items": [], "routes": [], "growth": []},
	"collection": {}, "receipts": {}, "pack_choices_by_hero": {},
	"tutorial": {"actually_completed": false, "skipped": false, "reward_claimed": false, "skip_eligible_at_creation": false},
}
var run: Dictionary = {"id": "", "stage": "hub", "hero": INITIAL_HERO, "pending_discoveries": {"cards": {}, "stickers": {}, "resources": {}}, "tasks": {}, "exhausted_spells": {}, "candidates": {}, "selection": [], "read_tutorial_hints": []}


func _init() -> void:
	profile.created_at = int(Time.get_unix_time_from_system())


func capture_state() -> Dictionary:
	return {"version": VERSION, "profile": profile.duplicate(true), "run": run.duplicate(true)}


func restore_state(value: Dictionary) -> bool:
	if not _integer(value.get("version"), VERSION, VERSION) or not value.get("profile") is Dictionary or not value.get("run") is Dictionary:
		return false
	var p: Dictionary = value.profile
	var r: Dictionary = value.run.duplicate(true)
	# D3-1存档没有总结字段；只迁移缺省值，不推算旧局积分。
	if not r.has("summary"): r["summary"] = {}
	if not _valid_profile(p) or not _valid_run(r): return false
	if not r.summary.is_empty():
		var receipt := "run_end:" + String(r.id)
		if not _valid_summary(r.summary) or p.receipts.get(receipt, -1) != r.summary.total: return false
	var candidate := ProfileProgress.new()
	candidate.profile = p.duplicate(true)
	candidate.run = r.duplicate(true)
	if not candidate._selection_valid(r.selection): return false
	profile = candidate.profile
	profile.points = int(profile.points)
	run = candidate.run
	return true


func start_run(hero: String = INITIAL_HERO) -> bool:
	if run.stage != "hub" or not profile.unlocks.heroes.has(hero): return false
	var selected: Dictionary = {}
	for category: String in run.tasks:
		var id: String = run.tasks[category].id
		if profile.tasks.has(id) and not profile.tasks[id].completed:
			selected[category] = {"id": id, "progress": {}, "completed": false}
	run = ProfileProgress.new().run
	run.tasks = selected
	run.id = Crypto.new().generate_random_bytes(16).hex_encode()
	run.stage = "active"
	run.hero = hero
	return true


func note_discovery(category: String, id: String) -> bool:
	if not run.pending_discoveries.has(category) or id.is_empty() or run.stage != "active": return false
	run.pending_discoveries[category][id] = true
	return true


func commit_discoveries() -> void:
	for category: String in run.pending_discoveries:
		profile.discoveries[category].merge(run.pending_discoveries[category], true)
		run.pending_discoveries[category].clear()


func credit_once(receipt: String, amount: int) -> bool:
	if receipt.is_empty() or amount < 0 or profile.receipts.has(receipt) or amount > 9007199254740991 - int(profile.points): return false
	profile.points += amount
	profile.receipts[receipt] = amount
	return true


func purchase_task(id: String, price: int) -> bool:
	# 目标、价格及前置由后续任务目录提供；这里仅处理已确认购买的账务。
	if run.stage != "hub" or id.is_empty() or price < 0 or profile.points < price or profile.tasks.has(id): return false
	profile.points -= price
	profile.tasks[id] = {"purchased": true, "completed": false}
	return true


func select_tasks(main_id: String, side_id: String) -> bool:
	if run.stage != "hub" or main_id == side_id and not main_id.is_empty(): return false
	var chosen: Dictionary = {}
	for pair: Array in [["main", main_id], ["side", side_id]]:
		if pair[1].is_empty(): continue
		var task: Dictionary = profile.tasks.get(pair[1], {})
		if not task.get("purchased", false) or task.get("completed", false): return false
		chosen[pair[0]] = {"id": pair[1], "progress": {}, "completed": false}
	run.tasks = chosen
	return true


func complete_task(id: String, rewards: Dictionary) -> bool:
	if not profile.tasks.has(id) or profile.tasks[id].completed: return false
	for category: String in rewards:
		if not profile.unlocks.has(category) or not _string_array(rewards[category]): return false
	profile.tasks[id].completed = true
	for category: String in rewards:
		for key: String in rewards[category]:
			if not profile.unlocks[category].has(key): profile.unlocks[category].append(key)
	for task: Dictionary in run.tasks.values():
		if task.id == id: task.completed = true
	return true


func complete_tutorial(skipped: bool = false) -> bool:
	if profile.tutorial.reward_claimed or not profile.tasks.has("tutorial") or profile.tasks.tutorial.completed or (skipped and (not profile.tutorial.skip_eligible_at_creation or run.stage != "hub")): return false
	if not credit_once("tutorial_guidance", 1000): return false
	profile.tutorial.actually_completed = not skipped
	profile.tutorial.skipped = skipped
	profile.tutorial.reward_claimed = true
	return complete_task("tutorial", {"routes": ["eight_days"], "items": ["scraper"]})


func remember_pack_choices(hero: String, ids: Array) -> bool:
	if hero.is_empty() or ids.size() != 3 or not _string_array(ids) or _has_duplicates(ids): return false
	for id: String in ids:
		if not profile.unlocks.packs.has(id): return false
	profile.pack_choices_by_hero[hero] = ids.duplicate()
	return true


func remember_exhausted_spell(owned: OwnedCard) -> bool:
	if run.stage != "active" or owned == null or owned.card_data.is_derived or owned.card_data.card_type != CardData.CardType.SPELL or owned.spell_durability > 0: return false
	var encoded := _encode_card(owned)
	if encoded.is_empty(): return false
	run.exhausted_spells[String(owned.instance_id)] = encoded
	return true


func begin_collection(cards: Array[OwnedCard]) -> bool:
	if run.stage != "active" or run.id.is_empty(): return false
	var candidates: Dictionary = {}
	for owned: OwnedCard in cards:
		if owned.card_data.is_derived or owned.card_data.card_type == CardData.CardType.RESOURCE: continue
		var encoded := _encode_card(owned)
		if encoded.is_empty(): return false
		candidates[String(owned.instance_id)] = encoded
	for id: String in run.exhausted_spells:
		candidates[id] = run.exhausted_spells[id].duplicate(true)
	run.candidates = candidates
	run.selection = []
	run.stage = "selection"
	commit_discoveries()
	return true


func finish_run(cards: Array[OwnedCard], inventory: Array, gold: int, outcome: String, day: int, results: Array, protection: int) -> bool:
	if run.stage != "active": return run.get("summary", {}).get("outcome", "") == outcome
	if outcome not in ["cleared", "failed", "abandoned"]: return false
	var summary := preload("res://scripts/data/run_score_service.gd").calculate(cards, run.exhausted_spells, inventory, gold, outcome, day, results, protection)
	var eligible: bool = summary.eligible
	var receipt := "run_end:" + String(run.id)
	if profile.receipts.has(receipt) or int(summary.total) > 9007199254740991 - int(profile.points): return false
	if not begin_collection(cards): return false
	if not eligible: run.candidates.clear()
	credit_once(receipt, int(summary.total))
	run["summary"] = summary
	run.stage = "summary"
	return true


func show_selection() -> bool:
	if run.stage != "summary": return false
	run.stage = "selection"
	return true


func set_selection(choices: Array) -> bool:
	if run.stage != "selection" or not _selection_valid(choices): return false
	run.selection = choices.duplicate(true)
	return true


func show_preview() -> bool:
	if run.stage != "selection" or not _selection_valid(run.selection): return false
	run.stage = "preview"
	return true


func return_to_selection() -> bool:
	if run.stage != "preview": return false
	run.stage = "selection"
	return true


func confirm_collection() -> bool:
	if run.stage != "preview" or not _selection_valid(run.selection): return false
	var next: Dictionary = profile.collection.duplicate(true)
	for choice: Dictionary in run.selection:
		var card: Dictionary = run.candidates[choice.candidate_id].duplicate(true)
		var kind: String = card.card_id
		var definition := Save.new()._resolve_card_definition(kind, card.get("card_resource_path", ""), {})
		if definition.card_type == CardData.CardType.SPELL: card.spell_durability = int(definition.rarity) + 1
		var slots: Array = next.get(kind, [])
		if int(choice.slot) == slots.size(): slots.append(card)
		else: slots[int(choice.slot)] = card
		next[kind] = slots
	profile.collection = next
	run.candidates.clear()
	run.selection.clear()
	run.exhausted_spells.clear()
	run.stage = "hub"
	run.tasks.clear()
	return true


func _encode_card(owned: OwnedCard) -> Dictionary:
	var encoded := Save.new()._encode_collection_state({"cards": [owned.capture_state()]})
	if encoded.is_empty(): return {}
	var card: Dictionary = encoded.cards[0]
	card["archive_id"] = run.id + ":" + String(owned.instance_id)
	return card


func _selection_valid(choices: Variant) -> bool:
	if not choices is Array or choices.size() > MAX_SELECTION: return false
	var used: Dictionary = {}
	var targets: Dictionary = {}
	var counts: Dictionary = {}
	var replacements: Dictionary = {}
	for value: Variant in choices:
		if not value is Dictionary or not value.get("candidate_id") is String: return false
		var id: String = value.candidate_id
		if used.has(id) or not run.candidates.has(id) or not _integer(value.get("slot"), 0, SLOTS_PER_KIND - 1): return false
		var card: Dictionary = run.candidates[id]
		var kind: String = card.card_id
		for existing_slots: Array in profile.collection.values():
			for existing: Dictionary in existing_slots:
				if existing.archive_id == card.archive_id: return false
		var slots: Array = profile.collection.get(kind, [])
		var index := int(value.slot)
		var target := "%s:%d" % [kind, index]
		if targets.has(target): return false
		var expected := slots.size() + int(counts.get(kind, 0))
		if index < slots.size():
			if value.get("replacement_confirmed") != true or value.get("replaced_id", "") != slots[index].archive_id: return false
			replacements[kind] = true
		else:
			if index != expected or not String(value.get("replaced_id", "")).is_empty(): return false
			counts[kind] = int(counts.get(kind, 0)) + 1
		used[id] = true
		targets[target] = true
	for kind: String in replacements:
		if profile.collection[kind].size() + int(counts.get(kind, 0)) != SLOTS_PER_KIND: return false
	return true


func _valid_profile(p: Dictionary) -> bool:
	if not _integer(p.get("created_at"), 0, 9007199254740991) or not p.get("legacy") is bool: return false
	if not _integer(p.get("points"), 0, 9007199254740991): return false
	for key: String in ["tasks", "unlocks", "collection", "receipts", "pack_choices_by_hero", "tutorial"]:
		if not p.get(key) is Dictionary: return false
	if not _discovery_set(p.get("discoveries")): return false
	for category: String in ["heroes", "packs", "items", "routes", "growth"]:
		if not _string_array(p.unlocks.get(category)) or _has_duplicates(p.unlocks[category]): return false
	for id: Variant in p.tasks:
		if not id is String or id.is_empty() or not p.tasks[id] is Dictionary: return false
		var task: Dictionary = p.tasks[id]
		if task.get("purchased") != true or not task.get("completed") is bool: return false
	for amount: Variant in p.receipts.values():
		if not _integer(amount, 0, 9007199254740991): return false
	for ids: Variant in p.pack_choices_by_hero.values():
		if not _string_array(ids) or ids.size() != 3 or _has_duplicates(ids): return false
	for key: String in ["actually_completed", "skipped", "reward_claimed", "skip_eligible_at_creation"]:
		if not p.tutorial.get(key) is bool: return false
	var seen: Dictionary = {}
	for kind: Variant in p.collection:
		if not kind is String or not p.collection[kind] is Array or p.collection[kind].size() > SLOTS_PER_KIND: return false
		for card: Variant in p.collection[kind]:
			if not _valid_card(card) or card.card_id != kind or seen.has(card.archive_id): return false
			seen[card.archive_id] = true
	return true


func _valid_run(r: Dictionary) -> bool:
	if not r.get("selection") is Array: return false
	if not r.get("id") is String or not r.get("hero") is String or r.get("stage") not in ["hub", "active", "summary", "selection", "preview"]: return false
	if r.has("summary") and not r.summary is Dictionary: return false
	if r.stage == "summary":
		var summary: Dictionary = r.get("summary", {})
		if summary.get("outcome") not in ["cleared", "failed", "abandoned"] or not _integer(summary.get("total"), 0, 9007199254740991): return false
	if r.stage != "hub" and r.id.is_empty(): return false
	if not _discovery_set(r.get("pending_discoveries")) or not _string_array(r.get("read_tutorial_hints")): return false
	for key: String in ["tasks", "exhausted_spells", "candidates"]:
		if not r.get(key) is Dictionary: return false
	for category: String in ["exhausted_spells", "candidates"]:
		for id: Variant in r[category]:
			if not id is String or not _valid_card(r[category][id]) or r[category][id].instance_id != id or r[category][id].archive_id != r.id + ":" + id: return false
	if r.tasks.size() > 2: return false
	for key: Variant in r.tasks:
		if key not in ["main", "side"] or not r.tasks[key] is Dictionary: return false
		var task: Dictionary = r.tasks[key]
		if not task.get("id") is String or not task.get("progress") is Dictionary or not task.get("completed") is bool: return false
	if r.stage in ["active", "hub"] and (not r.candidates.is_empty() or not r.get("selection", []).is_empty()): return false
	return r.get("selection") is Array


func _valid_card(value: Variant) -> bool:
	if not value is Dictionary or not value.get("archive_id") is String or value.archive_id.is_empty(): return false
	var decoded := Save.new()._decode_collection_state({"cards": [value]}, {}, false, false, Save.SCHEMA_VERSION, false, false)
	if not decoded.get("success", false): return false
	var definition: CardData = decoded.state.cards[0].card_data
	return not definition.is_derived and definition.card_type != CardData.CardType.RESOURCE


func _valid_summary(summary: Dictionary) -> bool:
	if summary.get("outcome") not in ["cleared", "failed", "abandoned"] or not summary.get("eligible") is bool: return false
	for key: String in ["day", "gold", "base", "completed_days", "bosses", "protection", "multiplier_tenths", "total"]:
		if not _integer(summary.get(key), 0, 9007199254740991): return false
	if int(summary.multiplier_tenths) != 10 + int(summary.completed_days) + int(summary.bosses) * 5 + int(summary.protection) * 2: return false
	if summary.outcome != "cleared" and summary.protection != 0: return false
	if summary.total != (int(summary.base) * int(summary.multiplier_tenths)) / 10: return false
	if not summary.get("cards") is Array or not summary.get("toolbox") is Array: return false
	var base: int = int(summary.gold)
	for card: Variant in summary.cards:
		if not card is Dictionary or not card.get("parts") is Dictionary or not card.get("exhausted") is bool: return false
		for key: String in ["name", "card_id", "instance_id"]:
			if not card.get(key) is String: return false
		var total := 0
		for key: String in ["grade", "surface", "art", "stickers", "runes", "pattern"]:
			if not _integer(card.parts.get(key), 0, 9007199254740991): return false
			total += int(card.parts[key])
		if card.get("total") != total: return false
		if card.has("snapshot"):
			if not card.snapshot is Dictionary: return false
			var decoded := Save.new()._decode_collection_state({"cards": [card.snapshot]}, {}, false, false, Save.SCHEMA_VERSION, false, false)
			if not decoded.get("success", false) or String(card.snapshot.get("instance_id", "")) != card.instance_id or String(card.snapshot.get("card_id", "")) != card.card_id: return false
		base += total
	for item: Variant in summary.toolbox:
		if not item is Dictionary or not item.get("name") is String or not _integer(item.get("total"), 0, 9007199254740991): return false
		if item.has("sticker") and (not item.sticker is Dictionary or String(item.sticker.get("emblem_id", item.sticker.get("wound_id", ""))) != item.name): return false
		base += int(item.total)
	return summary.base == (base if summary.eligible else 0)


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum


static func _string_array(value: Variant) -> bool:
	if not value is Array: return false
	for item: Variant in value:
		if not item is String or item.is_empty(): return false
	return true


static func _has_duplicates(values: Array) -> bool:
	var seen: Dictionary = {}
	for value: Variant in values:
		if seen.has(value): return true
		seen[value] = true
	return false


static func _discovery_set(value: Variant) -> bool:
	if not value is Dictionary: return false
	for category: String in ["cards", "stickers", "resources"]:
		if not value.get(category) is Dictionary: return false
		for id: Variant in value[category]:
			if not id is String or id.is_empty() or value[category][id] != true: return false
	return true
