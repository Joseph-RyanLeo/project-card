class_name TaskCatalog
extends RefCounted

## 目录负责资格与奖励，原文负责展示；积分仍只存放在ProfileProgress。
const PATH := "res://data/tasks/d3_4_tasks.json"
const RUNE_TEACHING_PATH := "res://data/tasks/rune_teaching.json"
const RUNE_TEACHING_PREFIX := "rune_pattern:"
const RUNE_TEACHING_IDS := {
	RunePatternResult.PatternType.CHAOS: "chaos",
	RunePatternResult.PatternType.PAIR: "pair",
	RunePatternResult.PatternType.THREE_OF_A_KIND: "three_of_a_kind",
	RunePatternResult.PatternType.TWO_PAIR: "two_pair",
	RunePatternResult.PatternType.SAME_ELEMENT_TWO_PAIR: "same_element_two_pair",
	RunePatternResult.PatternType.FULL_HOUSE: "full_house",
	RunePatternResult.PatternType.FOUR_OF_A_KIND: "four_of_a_kind",
	RunePatternResult.PatternType.FIVE_OF_A_KIND: "five_of_a_kind",
	RunePatternResult.PatternType.STRAIGHT: "straight",
}
const RETIRED_TEACHING_KEYS := ["tutorial:step:event_choice", "tutorial:step:squad_patterns"]
static var _tasks: Dictionary = {}
static var _tutorial_hints: Dictionary = {}
static var _rune_teaching: Dictionary = {}

static func tutorial_hint(id: String) -> Dictionary:
	if _tutorial_hints.is_empty():
		_tutorial_hints = JSON.parse_string(FileAccess.get_file_as_string("res://data/tasks/tutorial_hints.json"))
	return _tutorial_hints.get(id, {}).duplicate(true)


static func teaching_archive(hint: Dictionary) -> String:
	return "%s\n%s" % [hint.title, hint.instruction]


static func teaching_entries() -> Array[Dictionary]:
	# 与操作教学共用正文，避免回看和实际提示分别维护两份规则。
	tutorial_hint("")
	var result: Array[Dictionary] = []
	for id: String in _tutorial_hints:
		var hint := tutorial_hint(id)
		if not String(hint.get("instruction", "")).is_empty():
			result.append({"key": "tutorial:step:" + id, "title": hint.title, "text": hint.instruction})
	var emblem := teaching_hint("supply_first:emblems")
	result.append({"key": "supply_first:emblems", "title": emblem.title, "text": emblem.instruction})
	for pattern: RunePatternResult.PatternType in RUNE_TEACHING_IDS:
		var key := rune_teaching_key(pattern)
		var hint := teaching_hint(key)
		result.append({"key": key, "title": hint.title, "text": hint.instruction, "table": _rune_teaching.element_table, "featured_columns": hint.featured_columns})
	return result


static func rune_teaching_key(pattern: RunePatternResult.PatternType) -> String:
	return RUNE_TEACHING_PREFIX + RUNE_TEACHING_IDS[pattern]


static func story_key(task: String, day: int, chapter: String) -> String:
	if task == "deep_survey": return task + ":" + chapter
	if task in ["ironwall_support", "temple_boon"]: return "%s:floor:%d" % [task, 1 if day < 9 else 2]
	if task == "supply_first": return task + (":opening" if chapter == "supplies" else ":emblems")
	return task + ":opening"


static func teaching_hint(key: String) -> Dictionary:
	if key.begins_with("tutorial:step:"): return tutorial_hint(key.trim_prefix("tutorial:step:"))
	if key.begins_with(RUNE_TEACHING_PREFIX):
		if _rune_teaching.is_empty():
			_rune_teaching = JSON.parse_string(FileAccess.get_file_as_string(RUNE_TEACHING_PATH))
		var id := key.trim_prefix(RUNE_TEACHING_PREFIX)
		if not _rune_teaching.patterns.has(id): return {}
		var hint: Dictionary = _rune_teaching.patterns[id].duplicate(true)
		var result := RunePatternResult.new()
		result.pattern_type = RUNE_TEACHING_IDS.find_key(id)
		hint["title"] = "符文牌型：" + result.get_pattern_name()
		return hint
	if key == "supply_first:emblems":
		return {"title": "纹章的使用", "dialogue": [], "instruction": "右键检视随从，展开工具箱后，把纹章拖到可用的纹章槽上。", "anchor": "none", "placement": "top_left", "panel_width": 300}
	if key == "supply_first:opening":
		var hint := story_hint("后勤机器人：“哔……哔……铁壁关的先行补给已送达，后续的增员已经在路上。”\n伊奥恩：“铁壁关那帮人总算没全忘了这儿。”")
		hint.lock_dialogue = true
		return hint
	if key == "supply_first:open_pack":
		return {"title": "纹章包", "dialogue": [], "instruction": "点击桌上的纹章包，领取试用纹章。", "anchor": "initial_pack", "highlight_only": true}
	return {}


static func legacy_teaching_keys(key: String) -> Array:
	if not teaching_hint(key).is_empty(): return [key]
	var parts := key.split(":")
	if parts.size() != 4: return []
	if parts[0] == "supply_first" and parts[3] == "day": return ["supply_first:emblems"]
	if parts[0] != "tutorial": return []
	if parts[3] == "supplies": return ["tutorial:step:supplies"]
	var days := {"1": ["event_revealed", "event_reward", "shop_route", "shop_entered", "deploy", "battle_ready", "first_victory"], "2": ["smith", "scraper_inspection", "formation"], "3": ["squad_intro", "squad_formed"], "4": ["attack_intro", "attack_observed"]}
	return days.get(parts[1], []).map(func(id: String): return "tutorial:step:" + id)


static func legacy_story_keys(key: String) -> Array:
	var parts := key.split(":")
	if parts.size() != 4: return [key]
	if parts[0] == "tutorial": return legacy_teaching_keys(key)
	return [story_key(parts[0], int(parts[1]), parts[3])]


static func story_hint(text: String) -> Dictionary:
	# 其他任务仍保留来源对白格式；只拆展示角色，不解释或改写任务数值。
	var dialogue: Array[Dictionary] = []
	var narrative: Array[String] = []
	for line: String in text.split("\n", false):
		var parts := line.split("：", true, 1)
		if parts.size() == 2 and (parts[0].begins_with("伊奥恩") or parts[0] in ["主角", "玛格丽特", "后勤机器人", "埃德温·尘灰", "伊尔", "矮人起哄"]):
			dialogue.append({"speaker": parts[0], "text": parts[1].strip_edges().trim_prefix("“").trim_suffix("”")})
		else: narrative.append(line)
	return {"title": "任务剧情", "dialogue": dialogue, "story_text": "\n".join(narrative), "instruction": "", "anchor": "event"}

static func all() -> Dictionary:
	if _tasks.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		for task: Dictionary in data.tasks: _tasks[task.id] = task
	return _tasks.duplicate(true)

static func get_task(id: String) -> Dictionary:
	return all().get(id, {})

static func available(progress: ProfileProgress, id: String) -> bool:
	var task := get_task(id)
	if task.is_empty() or not task.implemented: return false
	return String(task.requires).is_empty() or progress.profile.tasks.get(task.requires, {}).get("completed", false)

static func visible_tasks(progress: ProfileProgress) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in all():
		if available(progress, id): result.append(get_task(id))
	return result

static func rewards_for(id: String) -> Dictionary:
	var rewards: Dictionary = get_task(id).get("rewards", {}).duplicate(true)
	if id == "supply_first":
		rewards.items = []
		for emblem: Dictionary in EmblemLibraryData.DEFINITIONS:
			if int(emblem.rarity) < CardData.Rarity.V and emblem.get("target", "emblem") != "rune": rewards.items.append(String(emblem.id))
	if id == "witch_cauldron":
		for recipe: Dictionary in EmblemFusionRecipes.RECIPES:
			var result_id := String(recipe.result)
			if not rewards.items.has(result_id): rewards.items.append(result_id)
	return rewards

static func selected(progress: ProfileProgress, category: String) -> String:
	return progress.run.tasks.get(category, {}).get("id", "")


static func progress_text(id: String) -> String:
	# 来源里的制作备注留在原始字段；玩家页面只展示对白与可执行的提示。
	var value: String = get_task(id).get("source", {}).get("进程描述", "")
	value = value.replace("（获得纹章包 ×1。首次打开时可增加一个简短的纹章用途提示）", "获得纹章包 ×1。\n纹章可从工具箱粘贴到随从的纹章槽，在卡牌检视中操作。")
	value = value.replace("（教学弹窗：基础战斗\n建议以实际战斗界面配合箭头，依次介绍：\n如何部署随从，组成出战队伍。\n如何开始战斗，以及战斗中的行动如何执行。\n如何判断敌我状态，以及胜利和失败条件。）", "基础战斗：从收藏将随从拖入前排或后排，组成队伍。准备好后点击开始战斗；随从按冷却自动行动。观察生命、护甲与战斗结果，再决定下一步。")
	value = value.replace("（介绍近战远程攻击的特效）", "观察近战与远程的攻击表现：近战接近目标挥击，远程会发射弹道；命中后结算伤害。")
	return value
