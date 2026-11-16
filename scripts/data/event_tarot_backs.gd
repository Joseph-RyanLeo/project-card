extends RefCounted

## 事件编号绑定三个固定牌背。只决定展示，不消费本局随机数。
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
	if not _loaded: _load_assignments()
	var path_id := String(path.get("path_id", ""))
	var cards: Array = _assignments.get(path_id, [])
	if cards.is_empty() and path.get("tutorial", false):
		# 教程复制同一事件成三个候选，福尔图纳沿用正式版的牌背组。
		var split := path_id.rfind("_")
		if split >= 0 and path_id.substr(split + 1) in ["0", "1", "2"]:
			var base_id := path_id.left(split)
			cards = _assignments.get("fortuna_gift" if base_id == "tutorial_fortuna" else base_id, [])
	if cards.is_empty(): return {}
	var index := posmod(("%s:%s" % [deal_key, path_id]).hash(), cards.size())
	var entry := String(cards[index])
	return {
		"texture": load(ART_DIRECTORY + entry.trim_suffix("_reversed") + ".png") as Texture2D,
		"reversed": entry.ends_with("_reversed"),
	}


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
