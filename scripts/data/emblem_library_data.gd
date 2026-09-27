class_name EmblemLibraryData
extends RefCounted

## 开发用纹章与伤势目录。
## CSV 导入的描述仅用于资料提示；是否实现仍以已确认的玩法规则和运行逻辑为准。

const CardDataScript = preload("res://scripts/data/card_data.gd")
const StatusIndicatorStyleScript = preload("res://scripts/ui/status_indicator_style.gd")
const CATALOG_PATH := "res://data/emblem_wound_catalog.json"

static var _catalog: Array[Dictionary] = []
static var _catalog_loaded := false

const RUNE_ELEMENT_BY_ID: Dictionary = {
	&"暗贴纸": CardDataScript.ElementType.DARK,
	&"火贴纸": CardDataScript.ElementType.FIRE,
	&"水贴纸": CardDataScript.ElementType.WATER,
	&"光贴纸": CardDataScript.ElementType.LIGHT,
	&"木贴纸": CardDataScript.ElementType.WOOD,
	&"混沌贴纸": -1,
	&"万能贴纸": -2,
}

## 已确认的无条件静态属性变化。此表只描述属性，不从面向玩家的描述文本推导规则。
const STATIC_MODIFIERS: Dictionary = {
	&"长剑": {&"base_value": 1},
	&"面包": {&"max_health": 2},
	&"改造": {&"max_health": -1, &"base_armor": 2},
	&"盾牌Ⅰ": {&"base_armor": 2},
	&"盾牌Ⅱ": {&"base_armor": 4},
	&"盾牌Ⅲ": {&"base_armor": 4},
	&"火腿面包": {&"max_health": 4},
	&"苹果派": {&"max_health": 3},
	&"烤面包": {&"max_health": 5},
	&"名剑": {&"base_value": 2},
	&"羽毛Ⅰ": {&"zeal": 2},
	&"羽毛Ⅱ": {&"zeal": 3},
	&"奶酪面包": {&"max_health": 4},
	&"三明治": {&"max_health": 5},
	&"树": {&"max_health": 5},
}

# 战斗纹章效果用结构化定义登记；数值不会从卡面或悬停文案解析。
const BATTLE_EFFECTS: Dictionary = {
	&"火把": {"keyword": &"dazzling"},
	&"斗篷": {"keyword": &"emblem_shadow", "shadow_duration": 15.0, "release_shadow_on_action": true, "release_shadow_on_damage": true}, # 影蔽持续15秒；行动或实际受伤提前解除
	&"火腿": {"reinforcement": 2},
	&"烤火腿": {"reinforcement": 3},
	&"火腿面包": {"reinforcement": 3},
	&"奶酪": {"rush_charge": 0.5},
	&"奶酪面包": {"rush_charge": 1.0},
	&"三明治": {"adjacent_reinforcement": 5, "adjacent_rush_charge": 0.5},
	&"苹果": {"heal_interval": 3.0, "heal_amount": 1.0},
	&"苹果派": {"heal_interval": 2.0, "heal_amount": 1.0},
	&"烤苹果": {"heal_interval": 3.0, "heal_amount": 2.0},
	&"金苹果": {"armor_interval": 3.0, "armor_amount": 2.0},
	&"改造": {"runtime_race": CardDataScript.RaceType.CONSTRUCT},
	&"四叶草Ⅰ": {"echo_roll_sides": 4, "echo_success_roll": 4, "echo_reinforcement": 1},
	&"四叶草Ⅱ": {"echo_roll_sides": 4, "echo_success_roll": 4, "echo_reinforcement": 2},
	&"四叶草Ⅲ": {"echo_roll_sides": 4, "echo_success_roll": 4, "echo_reinforcement": 2, "lethal_coin_save": true},
	&"盾牌Ⅲ": {"melee_immunity_once": true},
	&"刺盾": {"thorns_base": 2.0, "thorns_armor_ratio": 0.1},
	&"火焰剑": {"keyword": &"dazzling", "rush_convert_rightmost_rune": true},
	&"天选之子": {"advantage_dice": true},
	&"金币": {"last_wish_gold": 1},
	&"金币袋": {"last_wish_gold": 2},
	&"宝藏": {"last_wish_gold": 3, "last_wish_random_basic_emblem": true},
	&"宝石": {"score_bonus": 100},
	&"名剑": {"base_value": 2, "attack_armor_break": 1},
	&"种子": {"seed_progress": true},
	&"树": {"adjacent_protection": 1},
}

# 伤势触发也使用结构化定义；它们只在显现伤势槽注册到本场运行时。
const WOUND_BATTLE_EFFECTS: Dictionary = {
	&"脑死亡": {"rush_reinforcement": 8, "echo_sleep_duration": 15.0}, # 回响休眠15秒
	&"brain_death": {"rush_reinforcement": 8, "echo_sleep_duration": 15.0}, # 兼容稳定ID；回响休眠15秒
	&"光血": {"keyword": &"dazzling"},
	&"骨折Ⅰ": {"armor_gain_penalty": 1, "fracture_battles": 3},
	&"骨折Ⅱ": {"armor_gain_penalty": 2, "fracture_battles": 2},
	&"尸毒Ⅰ": {"corpse_poison_tier": 1},
	&"尸毒Ⅱ": {"corpse_poison_tier": 2, "corpse_adjacent_damage": 10},
	&"晶体化": {"crystallization": true},
	&"魔痕Ⅰ": {"spell_damage": 1, "spell_reinforcement": 1},
	&"魔痕Ⅱ": {"spell_damage": 2, "spell_reinforcement": 2},
	&"魔痕Ⅲ": {"spell_damage": 3, "spell_reinforcement": 3, "spell_stun_every": 5, "spell_stun_duration": 3.0},
	&"厄运缠身": {"disadvantage_dice": true},
	&"贪婪": {"lock_base_value": 1, "gold_reinforcement_bonus": 5},
}

## 伤势中数值明确且可直接汇总的常驻属性层；独立触发副效果由各自运行时处理。
const WOUND_STATIC_MODIFIERS: Dictionary = {
	&"脑震荡": {&"zeal": -6},
	&"内伤Ⅰ": {&"zeal": -2},
	&"内伤Ⅱ": {&"zeal": -4, &"base_value": -1},
	&"内伤Ⅲ": {&"base_value": -2},
	&"骨折Ⅰ": {&"base_value": -1},
	&"骨折Ⅱ": {&"base_value": -2},
	&"冻僵": {&"zeal": -4},
	&"烧伤Ⅰ": {&"zeal": 1},
	&"烧伤Ⅱ": {&"zeal": 2},
	&"撕裂Ⅰ": {&"zeal": 2},
	&"撕裂Ⅱ": {&"zeal": 3},
	&"撕裂Ⅲ": {&"zeal": 4},
	&"混乱": {&"base_value": 2},
	&"尸毒Ⅱ": {&"base_value": 2, &"max_health": 5},
	&"尸毒Ⅰ": {&"max_health": 3},
}

const DEFINITIONS: Array[Dictionary] = [
	{"id": &"火把", "name": "火把", "rarity": CardDataScript.Rarity.I},
	{"id": &"长剑", "name": "长剑", "rarity": CardDataScript.Rarity.I},
	{"id": &"面包", "name": "面包", "rarity": CardDataScript.Rarity.I},
	{"id": &"光贴纸", "name": "光贴纸", "rarity": CardDataScript.Rarity.II, "target": "rune"},
	{"id": &"暗贴纸", "name": "暗贴纸", "rarity": CardDataScript.Rarity.II, "target": "rune"},
	{"id": &"水贴纸", "name": "水贴纸", "rarity": CardDataScript.Rarity.II, "target": "rune"},
	{"id": &"火贴纸", "name": "火贴纸", "rarity": CardDataScript.Rarity.II, "target": "rune"},
	{"id": &"木贴纸", "name": "木贴纸", "rarity": CardDataScript.Rarity.II, "target": "rune"},
	{"id": &"混沌贴纸", "name": "混沌贴纸", "rarity": CardDataScript.Rarity.III, "target": "rune"},
	{"id": &"万能贴纸", "name": "万能贴纸", "rarity": CardDataScript.Rarity.III, "target": "rune"},
	{"id": &"改造", "name": "改造", "rarity": CardDataScript.Rarity.II},
	{"id": &"斗篷", "name": "斗篷", "rarity": CardDataScript.Rarity.I},
	{"id": &"四叶草Ⅰ", "name": "四叶草Ⅰ", "rarity": CardDataScript.Rarity.I},
	{"id": &"四叶草Ⅱ", "name": "四叶草Ⅱ", "rarity": CardDataScript.Rarity.V},
	{"id": &"四叶草Ⅲ", "name": "四叶草Ⅲ", "rarity": CardDataScript.Rarity.V},
	{"id": &"盾牌Ⅰ", "name": "盾牌Ⅰ", "rarity": CardDataScript.Rarity.I},
	{"id": &"盾牌Ⅱ", "name": "盾牌Ⅱ", "rarity": CardDataScript.Rarity.V},
	{"id": &"盾牌Ⅲ", "name": "盾牌Ⅲ", "rarity": CardDataScript.Rarity.V},
	{"id": &"火腿面包", "name": "火腿面包", "rarity": CardDataScript.Rarity.V},
	{"id": &"火腿", "name": "火腿", "rarity": CardDataScript.Rarity.I},
	{"id": &"苹果", "name": "苹果", "rarity": CardDataScript.Rarity.I},
	{"id": &"苹果派", "name": "苹果派", "rarity": CardDataScript.Rarity.V},
	{"id": &"烤面包", "name": "烤面包", "rarity": CardDataScript.Rarity.V},
	{"id": &"烤火腿", "name": "烤火腿", "rarity": CardDataScript.Rarity.V},
	{"id": &"烤苹果", "name": "烤苹果", "rarity": CardDataScript.Rarity.V},
	{"id": &"刺盾", "name": "刺盾", "rarity": CardDataScript.Rarity.V},
	{"id": &"火焰剑", "name": "火焰剑", "rarity": CardDataScript.Rarity.V},
	{"id": &"天选之子", "name": "天选之子", "rarity": CardDataScript.Rarity.III, "asset_name": "天选之人"},
	{"id": &"金币", "name": "金币", "rarity": CardDataScript.Rarity.I},
	{"id": &"金币袋", "name": "金币袋", "rarity": CardDataScript.Rarity.V},
	{"id": &"宝石", "name": "宝石", "rarity": CardDataScript.Rarity.II},
	{"id": &"宝藏", "name": "宝藏", "rarity": CardDataScript.Rarity.V},
	{"id": &"名剑", "name": "名剑", "rarity": CardDataScript.Rarity.V},
	{"id": &"羽毛Ⅰ", "name": "羽毛Ⅰ", "rarity": CardDataScript.Rarity.I},
	{"id": &"羽毛Ⅱ", "name": "羽毛Ⅱ", "rarity": CardDataScript.Rarity.V},
	{"id": &"奶酪", "name": "奶酪", "rarity": CardDataScript.Rarity.I},
	{"id": &"奶酪面包", "name": "奶酪面包", "rarity": CardDataScript.Rarity.V},
	{"id": &"三明治", "name": "三明治", "rarity": CardDataScript.Rarity.V},
	{"id": &"金苹果", "name": "金苹果", "rarity": CardDataScript.Rarity.V},
	{"id": &"种子", "name": "种子", "rarity": CardDataScript.Rarity.II},
	{"id": &"树", "name": "树", "rarity": CardDataScript.Rarity.V},
]


static func get_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(DEFINITIONS)
	return result


static func get_wound_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _get_catalog():
		if entry.get("类别", "") != "伤势":
			continue
		result.append({
			"id": StringName(entry.get("名称", "")),
			"name": String(entry.get("名称", "")),
			"effect_hint": String(entry.get("规范描述", "")),
			"review_status": String(entry.get("审阅状态", "")),
			"open_questions": String(entry.get("待确认事项", "")),
		})
	return result


static func get_rune_element(rune_id: StringName) -> int:
	return int(RUNE_ELEMENT_BY_ID.get(rune_id, -1))


static func get_static_modifier(emblem_id: StringName, stat: StringName) -> int:
	var modifiers: Dictionary = STATIC_MODIFIERS.get(emblem_id, {})
	return int(modifiers.get(stat, 0))


static func get_score_contribution(emblem_id: StringName) -> int:
	return int((BATTLE_EFFECTS.get(emblem_id, {}) as Dictionary).get("score_bonus", 0))


static func get_basic_emblem_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for definition: Dictionary in DEFINITIONS:
		if int(definition.get("rarity", -1)) == CardDataScript.Rarity.I and definition.get("target", "") != "rune":
			result.append(definition.get("id", &"") as StringName)
	return result


static func get_wound_static_modifier(wound_id: StringName, stat: StringName) -> int:
	var modifiers: Dictionary = WOUND_STATIC_MODIFIERS.get(wound_id, {})
	return int(modifiers.get(stat, 0))


static func get_tooltip(emblem_id: StringName) -> String:
	var display_name := ""
	for definition: Dictionary in DEFINITIONS:
		if definition.get("id", &"") == emblem_id:
			display_name = str(definition.get("name", emblem_id))
			break
	if display_name.is_empty():
		return "未知纹章"
	if emblem_id == &"混沌贴纸":
		return "混沌贴纸\n贴上及每日首次翻牌前随机变为木／水／火／光／暗之一。参与牌型时，每枚本场首次触发一次全队奖励：木使全队每张随从永久基础护甲+2并补当前护甲；水使永久基础生命值+2并补当前生命；火使永久基础数值+1；光获得4金币；暗从全队未遮挡的非空伤势槽中随机移除一处。不会额外增加牌型倍率。"
	var entry := _find_catalog_entry(display_name, "纹章")
	if entry.is_empty():
		return display_name + "\n本地尚未导入效果提示"
	return _format_catalog_hint(entry)


static func get_wound_tooltip(wound_id: StringName) -> String:
	var display_name := String(StatusIndicatorStyleScript.ALIASES.get(wound_id, String(wound_id)))
	var entry := _find_catalog_entry(display_name, "伤势")
	if entry.is_empty():
		return display_name + "\n本地尚未导入伤势提示"
	return _format_catalog_hint(entry)


static func _format_catalog_hint(entry: Dictionary) -> String:
	var text := String(entry.get("名称", "")) + "\n" + String(entry.get("规范描述", "暂无描述"))
	var review_status := String(entry.get("审阅状态", ""))
	if not review_status.is_empty():
		text += "\n资料状态：" + review_status
	var open_questions := String(entry.get("待确认事项", ""))
	if not open_questions.is_empty():
		text += "\n待确认：" + open_questions
	return text


static func _find_catalog_entry(display_name: String, category: String) -> Dictionary:
	for entry: Dictionary in _get_catalog():
		if entry.get("名称", "") == display_name and entry.get("类别", "") == category:
			return entry
	return {}


static func _get_catalog() -> Array[Dictionary]:
	if _catalog_loaded:
		return _catalog
	_catalog_loaded = true
	if not FileAccess.file_exists(CATALOG_PATH):
		return _catalog
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return _catalog
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		for value: Variant in parsed:
			if value is Dictionary:
				_catalog.append(value)
	return _catalog
