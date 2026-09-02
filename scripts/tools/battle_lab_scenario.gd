class_name BattleLabScenario
extends Resource

## 战斗实验室的一份可保存输入快照。
## 这里只描述阵容与预期结果；真正结算仍交给正式 BattleController。

const SIDE_SLOT_COUNT: int = 4 # 实验室每一方最多同时配置的小队数量
const MAX_VISIBLE_RUNES: int = 5 # 当前牌型系统允许进入结算的最大可见符文数
const ACTION_VISUAL_TEMPLATES: Array[CardData] = [
	preload("res://resources/cards/ember_squire.tres"),
	preload("res://resources/cards/tide_archer.tres"),
	preload("res://resources/cards/spark_mage.tres"),
	preload("res://resources/cards/town_priest.tres"),
	preload("res://resources/cards/shieldwall_private.tres"),
] # 五种行动方式各复用一张正式卡牌的美术字段，实验室不再显示空白占位卡面

var scenario_name: String = "自定义场景"
var random_seed: int = 12345
var speed_multiplier: float = 1.0
var max_batches: int = 80
var expected_result: int = -1
var player_squads: Array[Dictionary] = []
var enemy_squads: Array[Dictionary] = []


static func create_default() -> BattleLabScenario:
	return create_preset(&"light_water")


static func create_preset(preset_id: StringName) -> BattleLabScenario:
	var scenario := BattleLabScenario.new()
	scenario.player_squads = _empty_side("我方")
	scenario.enemy_squads = _empty_side("敌方")
	match preset_id:
		&"wood_fire":
			scenario.scenario_name = "2木＋2火跨排持续"
			scenario.player_squads[0] = _squad_spec("木火近战", true, "front", 0, CardData.ActionType.MELEE, 10, 1.8, 120, 0, [CardData.ElementType.WOOD, CardData.ElementType.WOOD, CardData.ElementType.FIRE, CardData.ElementType.FIRE])
			scenario.enemy_squads[0] = _squad_spec("敌方前排", true, "front", 0, CardData.ActionType.MELEE, 7, 2.4, 160, 10, [])
			scenario.enemy_squads[1] = _squad_spec("敌方后排", true, "back", 0, CardData.ActionType.RANGED, 7, 2.4, 160, 0, [])
		&"fire_heal":
			scenario.scenario_name = "五火持续治疗"
			scenario.player_squads[0] = _squad_spec("五火治疗者", true, "back", 0, CardData.ActionType.HEAL, 8, 1.5, 100, 0, [CardData.ElementType.FIRE, CardData.ElementType.FIRE, CardData.ElementType.FIRE, CardData.ElementType.FIRE, CardData.ElementType.FIRE])
			scenario.player_squads[1] = _squad_spec("受击友军", true, "front", 0, CardData.ActionType.MELEE, 5, 2.5, 140, 0, [])
			scenario.enemy_squads[0] = _squad_spec("压测敌人", true, "front", 0, CardData.ActionType.MELEE, 16, 1.0, 220, 0, [])
		&"water_boundary":
			scenario.scenario_name = "五水邻接边界"
			scenario.player_squads[0] = _squad_spec("五水射手", true, "front", 0, CardData.ActionType.RANGED, 10, 2.0, 120, 0, [CardData.ElementType.WATER, CardData.ElementType.WATER, CardData.ElementType.WATER, CardData.ElementType.WATER, CardData.ElementType.WATER])
			for index: int in SIDE_SLOT_COUNT:
				scenario.enemy_squads[index] = _squad_spec("水扩散目标%d" % (index + 1), true, "front", index, CardData.ActionType.DEFENSE, 2, 3.0, 140, 0, [])
		&"light_targets":
			scenario.scenario_name = "五光目标不足"
			scenario.player_squads[0] = _squad_spec("五光法师", true, "back", 0, CardData.ActionType.MAGIC, 10, 2.0, 120, 0, [CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.LIGHT])
			for index: int in 3:
				scenario.enemy_squads[index] = _squad_spec("折射目标%d" % (index + 1), true, "front", index, CardData.ActionType.MELEE, 6, 2.5, 150, 0, [])
		_:
			scenario.scenario_name = "3光＋2水分层折射"
			scenario.player_squads[0] = _squad_spec("光水射手", true, "back", 0, CardData.ActionType.RANGED, 10, 2.0, 120, 0, [CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.WATER, CardData.ElementType.WATER])
			for index: int in 3:
				scenario.enemy_squads[index] = _squad_spec("分层目标%d" % (index + 1), true, "front", index, CardData.ActionType.MELEE, 6, 2.6, 150, 5, [])
	return scenario


func duplicate_scenario() -> BattleLabScenario:
	return from_dictionary(to_dictionary())


func validate() -> Array[String]:
	var errors: Array[String] = []
	_validate_side(player_squads, "我方", errors)
	_validate_side(enemy_squads, "敌方", errors)
	if not _has_enabled_squad(player_squads):
		errors.append("我方至少需要启用一个小队")
	if not _has_enabled_squad(enemy_squads):
		errors.append("敌方至少需要启用一个小队")
	if max_batches <= 0:
		errors.append("最大批次数必须大于 0")
	return errors


func build_player_formation() -> Array[Dictionary]:
	return _build_formation(player_squads, "player")


func build_enemy_formation() -> Array[Dictionary]:
	return _build_formation(enemy_squads, "enemy")


func to_dictionary() -> Dictionary:
	return {
		"version": 1,
		"scenario_name": scenario_name,
		"random_seed": random_seed,
		"speed_multiplier": speed_multiplier,
		"max_batches": max_batches,
		"expected_result": expected_result,
		"player_squads": player_squads.duplicate(true),
		"enemy_squads": enemy_squads.duplicate(true),
	}


static func from_dictionary(data: Dictionary) -> BattleLabScenario:
	var scenario := BattleLabScenario.new()
	scenario.scenario_name = String(data.get("scenario_name", "载入场景"))
	scenario.random_seed = int(data.get("random_seed", 12345))
	scenario.speed_multiplier = clampf(float(data.get("speed_multiplier", 1.0)), 1.0, 3.0)
	scenario.max_batches = maxi(int(data.get("max_batches", 80)), 1)
	scenario.expected_result = int(data.get("expected_result", -1))
	scenario.player_squads = _normalize_side(data.get("player_squads", []), "我方")
	scenario.enemy_squads = _normalize_side(data.get("enemy_squads", []), "敌方")
	return scenario


static func _build_formation(specs: Array[Dictionary], side_prefix: String) -> Array[Dictionary]:
	var formation: Array[Dictionary] = []
	for slot_index: int in specs.size():
		var spec := specs[slot_index]
		if not bool(spec.get("enabled", false)):
			continue
		var row_suffix := "back" if String(spec.get("row", "front")) == "back" else "front"
		formation.append({
			"squad_data": _build_squad(spec, "%s_%d" % [side_prefix, slot_index]),
			"row_key": StringName("%s_%s" % [side_prefix, row_suffix]),
			"formation_index": int(spec.get("position", slot_index)),
		})
	return formation


static func _build_squad(spec: Dictionary, stable_id: String) -> SquadData:
	var runes: Array[CardData.ElementType] = []
	for value: Variant in spec.get("runes", []):
		var element := int(value)
		if element >= 0 and element < CardData.ElementType.size() and runes.size() < MAX_VISIBLE_RUNES:
			runes.append(element as CardData.ElementType)
	var left := _build_card(spec, "%s_left" % stable_id)
	if runes.size() <= 3:
		left.runes.assign(runes)
		return SquadData.from_card(left)
	left.runes.assign([runes[0], runes[1], runes[2]])
	var right := _build_card(spec, "%s_right" % stable_id)
	if runes.size() == 4:
		right.runes.assign([runes[3], runes[3], runes[3]])
		return SquadData.from_cards([left, right], SquadData.TwoCardLayout.COMPACT)
	right.runes.assign([runes[3], runes[3], runes[4]])
	return SquadData.from_cards([left, right], SquadData.TwoCardLayout.EXPANDED)


static func _build_card(spec: Dictionary, stable_id: String) -> CardData:
	var card := CardData.new()
	card.id = StringName(stable_id)
	card.display_name = String(spec.get("name", "实验小队"))
	card.action_type = clampi(int(spec.get("action", CardData.ActionType.MELEE)), 0, CardData.ActionType.size() - 1) as CardData.ActionType
	var visual_template := ACTION_VISUAL_TEMPLATES[card.action_type]
	card.background_texture = visual_template.background_texture
	card.art_texture = visual_template.art_texture
	card.art_normal_texture = visual_template.art_normal_texture
	card.art_offset = visual_template.art_offset
	card.race_type = visual_template.race_type
	card.rarity = visual_template.rarity
	card.base_value = int(spec.get("base_value", 10))
	card.cooldown_seconds = float(spec.get("cooldown", 2.0))
	card.max_health = int(spec.get("health", 100))
	card.armor = int(spec.get("armor", 0))
	return card


static func _validate_side(specs: Array[Dictionary], side_name: String, errors: Array[String]) -> void:
	var occupied: Dictionary = {}
	for index: int in specs.size():
		var spec := specs[index]
		if not bool(spec.get("enabled", false)):
			continue
		var row := String(spec.get("row", "front"))
		var position := int(spec.get("position", index))
		var key := "%s:%d" % [row, position]
		if occupied.has(key):
			errors.append("%s第 %d、%d 个小队占用了同一排同一位置" % [side_name, int(occupied[key]) + 1, index + 1])
		else:
			occupied[key] = index


static func _has_enabled_squad(specs: Array[Dictionary]) -> bool:
	for spec: Dictionary in specs:
		if bool(spec.get("enabled", false)):
			return true
	return false


static func _empty_side(side_name: String) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	for index: int in SIDE_SLOT_COUNT:
		specs.append(_squad_spec("%s小队%d" % [side_name, index + 1], false, "front", index, CardData.ActionType.MELEE, 10, 2.0, 100, 0, []))
	return specs


static func _normalize_side(raw_specs: Variant, side_name: String) -> Array[Dictionary]:
	var result := _empty_side(side_name)
	if raw_specs is Array:
		for index: int in mini((raw_specs as Array).size(), SIDE_SLOT_COUNT):
			var raw: Variant = (raw_specs as Array)[index]
			if raw is Dictionary:
				result[index].merge((raw as Dictionary).duplicate(true), true)
	return result


static func _squad_spec(name_value: String, enabled: bool, row: String, position: int, action: int, base_value: int, cooldown: float, health: int, armor: int, runes: Array) -> Dictionary:
	return {
		"name": name_value,
		"enabled": enabled,
		"row": row,
		"position": position,
		"action": action,
		"base_value": base_value,
		"cooldown": cooldown,
		"health": health,
		"armor": armor,
		"runes": runes.duplicate(),
	}
