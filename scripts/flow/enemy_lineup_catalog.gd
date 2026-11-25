class_name EnemyLineupCatalog
extends RefCounted

## 草稿与正式配置共用格式。正式地图只读取 res:// 中已经发布的配置。
const FORMAL_PATH := "res://data/tasks/enemy_lineups.json"
const DRAFT_PATH := "user://enemy_lineup_drafts.json"
const EXPORT_PATH := "user://enemy_lineups.json"
const ENCOUNTER_CHOICES := 3 # 正式地图每次发出的战斗路径数量
const MAX_LINEUPS := 5 # 一个关卡可以发布的最多阵容数
const PATH_PREFIX := "named_lineup_"


static func load_base_content() -> Dictionary:
	var content := read_document("res://data/demo2/short_maze_content.json")
	if content.is_empty(): return {}
	for path: String in ["res://data/tasks/tutorial_enemies.json", "res://data/tasks/second_floor_enemies.json"]:
		var additional := read_document(path)
		if additional.is_empty(): return {}
		content.enemies.append_array(additional.enemies)
	return content


static func read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func write_document(path: String, levels: Dictionary) -> Error:
	var temporary := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if temporary == null: return FileAccess.get_open_error()
	if not temporary.store_string(JSON.stringify({"version": 1, "levels": levels}, "\t", false)):
		return temporary.get_error()
	temporary.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))


static func level_key(day: int, tutorial: bool) -> String:
	return ("tutorial_" if tutorial else "maze_") + str(day)


static func level_name(day: int, tutorial: bool) -> String:
	return "%s%d-%d" % ["教程 " if tutorial else "", floori(float(day - 1) / ShortMazeRunState.DAYS) + 1, posmod(day - 1, ShortMazeRunState.DAYS) + 1]


static func base_paths(content: Dictionary, day: int, tutorial: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for enemy: Dictionary in content.get("enemies", []):
		if bool(enemy.get("tutorial", false)) == tutorial and day >= int(enemy.first_day) and day <= int(enemy.last_day):
			result.append(enemy.duplicate(true))
	return result


static func lineup_from_path(path: Dictionary, fallback_name: String) -> Dictionary:
	var lineup := {
		"id": String(path.get("lineup_id", path.get("path_id", ""))),
		"name": String(path.get("lineup_name", fallback_name)),
		"hint": String(path.get("hint", "阵容尚未配置。")),
		"front": path.get("front", []).duplicate(true),
		"back": path.get("back", []).duplicate(true),
		"spells": path.get("spells", []).duplicate(),
		"resources": path.get("resources", []).duplicate(),
	}
	if path.get("visual") is Dictionary: lineup["visual"] = path.visual.duplicate(true)
	return lineup


static func path_for(lineup: Dictionary, day: int, tutorial: bool) -> Dictionary:
	var path := {
		"kind": "battle", "path_id": PATH_PREFIX + level_key(day, tutorial) + "_" + String(lineup.id),
		"lineup_id": lineup.id, "lineup_name": lineup.name, "lineup_day": day, "tutorial": tutorial,
		"hint": lineup.hint, "front": lineup.get("front", []).duplicate(true), "back": lineup.get("back", []).duplicate(true),
		"spells": lineup.get("spells", []).duplicate(), "resources": lineup.get("resources", []).duplicate(),
	}
	if lineup.get("visual") is Dictionary: path["visual"] = lineup.visual.duplicate(true)
	return path


static func lineup_error(lineup: Dictionary, registry: Dictionary) -> String:
	for key: String in ["id", "name", "hint"]:
		if not lineup.get(key) is String or String(lineup[key]).strip_edges().is_empty(): return "请填写阵容名称和路线提示"
	if not String(lineup.id).is_valid_identifier(): return "阵容编号无效"
	if lineup.has("visual"):
		var visual: Variant = lineup.visual
		if not visual is Dictionary or not visual.get("encounter") is Dictionary or not visual.get("resources") is Array or not visual.get("blocked") is Array: return "可视化阵容数据无效"
		return ""
	for row: String in ["front", "back"]:
		if not lineup.get(row) is Array: return "缺少前排或后排"
		for entry: Variant in lineup[row]:
			var squad: Dictionary = {"cards": [entry]} if entry is String else entry if entry is Dictionary else {}
			var cards: Variant = squad.get("cards")
			if not cards is Array or cards.is_empty() or cards.size() > 3 or not _valid_cards(cards, registry, CardData.CardType.MINION): return "每个小队需配置 1～3 张随从"
			var top: Variant = squad.get("top", 0)
			if not (top is int or top is float) or not is_finite(float(top)) or int(top) != top or int(top) < 0 or int(top) >= cards.size(): return "顶牌必须是小队中的一张卡"
			if squad.get("layout", "expanded") not in ["compact", "expanded"]: return "无效的堆叠间距"
			if squad.has("equipment") and not _valid_cards([squad.equipment], registry, CardData.CardType.EQUIPMENT): return "小队装备无效"
			var wounds: Variant = squad.get("wounds", [])
			if not wounds is Array or not wounds.all(func(wound: Variant) -> bool: return wound is String): return "伤势格式无效"
	if lineup.front.is_empty() and lineup.back.is_empty(): return "至少配置一个敌方小队"
	if not _valid_cards(lineup.get("spells"), registry, CardData.CardType.SPELL): return "法术列表含无效卡牌"
	if not _valid_cards(lineup.get("resources"), registry, CardData.CardType.RESOURCE): return "资源列表含无效卡牌"
	return ""


static func _valid_cards(value: Variant, registry: Dictionary, kind: CardData.CardType) -> bool:
	if not value is Array: return false
	for id: Variant in value:
		if not id is String: return false
		var card := registry.get(StringName(id)) as CardData
		if card == null or card.card_type != kind: return false
	return true


static func rune_reveals(content: Dictionary, day: int, tutorial: bool) -> int:
	var floor_key := str(floori(float(day - 1) / ShortMazeRunState.DAYS) + 1)
	return 0 if tutorial else clampi(int(content.get("enemy_rune_reveals_by_floor", {}).get(floor_key, 1)), 0, 3)


static func emblem_count(content: Dictionary, day: int, tutorial: bool) -> int:
	var counts: Array = content.get("enemy_emblems_by_day", [])
	return 0 if tutorial or counts.is_empty() else maxi(int(counts[clampi(day - 1, 0, counts.size() - 1)]), 0)
