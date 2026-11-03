extends RefCounted

## 从正式卡包身份收录目录；可用性只影响停用牌显示，不能替代正式／测试身份。
const Packs = preload("res://scripts/data/card_pack_registry.gd")
static var _cached_definitions: Array[CardData] = []
var resources: Array[CardData] = []
var definitions: Dictionary = {}
var stickers: Array[Dictionary] = []
# 只描述检视关联；实际生成仍由各卡包运行时负责。警戒机械已取消废料遗愿，不登记旧关联。
const DERIVED_SOURCES := {
	&"augustus_ironwall": ["skirmish_formation", "rally_formation"],
	&"bomb_apprentice": ["booby_mine"], &"sapper_shovel": ["booby_mine"],
	&"stargazer": ["victory_prophecy", "failure_prophecy"],
	&"starlight_weaver": ["moondew"], &"moon_tears": ["moondew"],
}
var cards: Array[CardData] = []

func _init() -> void:
	if _cached_definitions.is_empty():
		for file: String in DirAccess.get_files_at("res://resources/cards"):
			if not file.ends_with(".tres"): continue
			var card := load("res://resources/cards/" + file) as CardData
			if card != null and Packs.PACKS.has(card.pack_id): _cached_definitions.append(card)
	for card: CardData in _cached_definitions:
		if definitions.has(card.id): continue
		definitions[card.id] = card
		if card.card_type == CardData.CardType.RESOURCE: resources.append(card)
		elif not card.is_derived: cards.append(card)
	resources.sort_custom(_rarity_order)
	for definition: Dictionary in EmblemLibraryData.get_definitions():
		var entry := definition.duplicate()
		entry.category = "rune" if entry.get("target", "") == "rune" else "emblem"
		stickers.append(entry)
	for definition: Dictionary in EmblemLibraryData.get_wound_definitions():
		var entry := definition.duplicate()
		entry.category = "wound"
		entry.rarity = -1
		stickers.append(entry)
	stickers.sort_custom(func(a: Dictionary, b: Dictionary):
		if a.category != b.category: return a.category < b.category
		if a.rarity != b.rarity: return a.rarity > b.rarity
		return String(a.id) < String(b.id))
	cards.sort_custom(func(a: CardData, b: CardData):
		if a.pack_id != b.pack_id: return String(a.pack_id) < String(b.pack_id)
		if a.rarity != b.rarity: return a.rarity > b.rarity
		return String(a.id) < String(b.id))

func discovered(card: CardData, profile: Dictionary) -> bool:
	return profile.discoveries.cards.has(String(card.id))

func visible_cards(profile: Dictionary, pack: StringName) -> Array[CardData]:
	var result: Array[CardData] = []
	if not profile.unlocks.packs.has(String(pack)): return result
	for card: CardData in cards:
		if card.pack_id != pack: continue
		if card.is_available or discovered(card, profile) or not profile.collection.get(String(card.id), []).is_empty(): result.append(card)
	return result

func unlocked_packs(profile: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	for pack: StringName in Packs.PACKS:
		if profile.unlocks.packs.has(String(pack)) and count_total(pack) > 0: result.append(pack)
	return result

func filtered_cards(profile: Dictionary, pack: StringName, race: int = -1, type: int = -1, query: String = "") -> Array[CardData]:
	var result: Array[CardData] = []
	var search := query.strip_edges().to_lower()
	for card: CardData in visible_cards(profile, pack):
		if type >= 0 and int(card.card_type) != type: continue
		# 非随从的默认race_type不是适用种族；不能因默认值被筛入“人类”。
		if race >= 0 and (card.card_type != CardData.CardType.MINION or int(card.race_type) != race): continue
		if not search.is_empty():
			if not discovered(card, profile): continue
			var text := card.display_name + " " + card.get_effect_text_for_row(&"player_front") + " " + card.get_effect_text_for_row(&"player_back")
			if not text.to_lower().contains(search): continue
		result.append(card)
	return result

func count_discovered(profile: Dictionary, pack: StringName = &"") -> int:
	return cards.filter(func(card: CardData): return (pack.is_empty() or card.pack_id == pack) and discovered(card, profile)).size()

func count_total(pack: StringName = &"") -> int:
	return cards.filter(func(card: CardData): return pack.is_empty() or card.pack_id == pack).size()

func _rarity_order(a: CardData, b: CardData) -> bool:
	return a.rarity > b.rarity if a.rarity != b.rarity else String(a.id) < String(b.id)

func pack_open(card: CardData, profile: Dictionary) -> bool:
	for pack: String in profile.unlocks.packs:
		if Packs.belongs_to_pack(card, StringName(pack)): return true
	return false

func resource_discovered(card: CardData, profile: Dictionary) -> bool:
	return profile.discoveries.resources.has(String(card.id))

func visible_resources(profile: Dictionary, query: String = "") -> Array[CardData]:
	var result: Array[CardData] = []
	for card: CardData in resources:
		if not pack_open(card, profile): continue
		if not card.is_available and not resource_discovered(card, profile): continue
		if not query.strip_edges().is_empty():
			if not resource_discovered(card, profile): continue
			if not (card.display_name + card.get_effect_text_for_row(&"player_front")).to_lower().contains(query.strip_edges().to_lower()): continue
		result.append(card)
	return result

func sticker_id(id: Variant) -> String:
	return String(StatusIndicatorStyle.ALIASES.get(StringName(id), String(id)))

func sticker_discovered(entry: Dictionary, profile: Dictionary) -> bool:
	for id: String in profile.discoveries.stickers:
		if sticker_id(id) == sticker_id(entry.id): return true
	return false

func sticker_open(entry: Dictionary, profile: Dictionary) -> bool:
	if entry.category == "wound": return true
	for id: String in profile.unlocks.items:
		if sticker_id(id) == sticker_id(entry.id): return true
	return false

func visible_stickers(profile: Dictionary, category: String, query: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in stickers:
		if entry.category != category or not sticker_open(entry, profile): continue
		if not query.strip_edges().is_empty():
			if not sticker_discovered(entry, profile) or not sticker_text(entry).to_lower().contains(query.strip_edges().to_lower()): continue
		result.append(entry)
	return result

func sticker_texture(entry: Dictionary) -> Texture2D:
	if entry.category == "rune": return RuneStickerStyle.get_texture_by_id(entry.id)
	return StatusIndicatorStyle.get_texture(preload("res://scripts/data/card_slot_layout.gd").Kind.WOUND if entry.category == "wound" else preload("res://scripts/data/card_slot_layout.gd").Kind.EMBLEM, entry.id)

func sticker_text(entry: Dictionary) -> String:
	var text := EmblemLibraryData.get_wound_tooltip(entry.id) if entry.category == "wound" else EmblemLibraryData.get_tooltip(entry.id)
	return text.split("\n资料状态：")[0].split("\n待确认：")[0]

func derived_for(source: CardData, profile: Dictionary) -> Array[CardData]:
	var result: Array[CardData] = []
	if not pack_open(source, profile) or not discovered(source, profile): return result
	for id: String in DERIVED_SOURCES.get(source.id, []):
		var card := definitions.get(StringName(id)) as CardData
		if card != null and card.is_derived: result.append(card)
	return result
