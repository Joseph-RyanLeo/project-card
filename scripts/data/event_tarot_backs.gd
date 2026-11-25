extends RefCounted

## 同轮按事件偏好分配不同底图。牌序与发牌键来自存档，分配不消费本局随机数。
const ASSIGNMENTS_PATH := "res://data/events/tarot_back_assignments.json"
const ART_DIRECTORY := "res://assets/events/tarot/"
const CARD_IDS := [
	"fool", "magician", "high_priestess", "empress", "emperor", "hierophant", "lovers",
	"chariot", "strength", "hermit", "wheel_of_fortune", "justice", "hanged_man",
	"death", "temperance", "devil", "tower", "star", "moon", "sun", "judgement", "world",
]

static var _assignments: Dictionary
static var _loaded := false


static func pick(path: Dictionary, deal_key: String) -> Dictionary:
	return pick_for_round([path], deal_key)[0]


static func pick_for_round(paths: Array[Dictionary], deal_key: String) -> Array[Dictionary]:
	if not _loaded: _load_assignments()
	var options: Array[Array] = []
	for path: Dictionary in paths:
		options.append(_preferred_cards(path, deal_key))
	var selected: Array[String] = []
	selected.resize(paths.size())
	if not _assign_round(options, selected, {}, 0):
		# 同一事件补位三次时，其绑定中可能含同一底图的正逆位。
		for index: int in paths.size():
			if options[index] != [""]:
				options[index].append_array(_rotated(CARD_IDS, ("%s:%d" % [deal_key, index]).hash()))
		_assign_round(options, selected, {}, 0)
	var result: Array[Dictionary] = []
	for entry: String in selected:
		var id := entry.trim_suffix("_reversed")
		result.append({} if entry.is_empty() else {
			"id": id, "texture": load(ART_DIRECTORY + id + ".png") as Texture2D,
			"reversed": entry.ends_with("_reversed"),
		})
	return result


static func _preferred_cards(path: Dictionary, deal_key: String) -> Array:
	if path.get("kind") in ["shop", "battle"]: return [""]
	var path_id := String(path.get("path_id", ""))
	var cards: Array = _assignments.get(path_id, [])
	if cards.is_empty() and path.get("tutorial", false):
		# 教程复制同一事件成三个候选，福尔图纳沿用正式版的牌背组。
		var split := path_id.rfind("_")
		if split >= 0 and path_id.substr(split + 1) in ["0", "1", "2"]:
			var base_id := path_id.left(split)
			cards = _assignments.get("fortuna_gift" if base_id == "tutorial_fortuna" else base_id, [])
	return _rotated(CARD_IDS if cards.is_empty() else cards, ("%s:%s" % [deal_key, path_id]).hash())


static func _rotated(cards: Array, seed_value: int) -> Array:
	var index := posmod(seed_value, cards.size())
	return cards.slice(index) + cards.slice(0, index)


static func _assign_round(options: Array[Array], selected: Array[String], used: Dictionary, index: int) -> bool:
	if index == options.size(): return true
	for entry: String in options[index]:
		var id := entry.trim_suffix("_reversed")
		if used.has(id): continue
		selected[index] = entry
		if not id.is_empty(): used[id] = true
		if _assign_round(options, selected, used, index + 1): return true
		used.erase(id)
	return false


static func _load_assignments() -> void:
	_loaded = true
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(ASSIGNMENTS_PATH))
	if not source is Dictionary:
		push_error("塔罗牌背配置须按事件编号填写。")
		return
	for event_id: String in source:
		var cards: Variant = source[event_id]
		if not cards is Array or cards.size() != 3:
			push_error("事件 %s 须绑定三张塔罗牌背。" % event_id)
			continue
		if not cards.all(func(card: Variant) -> bool: return card is String and card.trim_suffix("_reversed") in CARD_IDS) or cards[0] == cards[1] or cards[0] == cards[2] or cards[1] == cards[2]:
			push_error("事件 %s 须绑定三个不同的有效牌面，正逆位分别计入。" % event_id)
			continue
		_assignments[event_id] = cards
