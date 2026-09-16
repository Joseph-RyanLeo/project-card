class_name BattleLabEffectLibrary
extends RefCounted

## 战斗实验室专用的 D2-3 效果测试卡库。
## 它只组合正式 BattleEffectDefinition，不复制任何效果结算规则。

const NONE: StringName = &"none"
const BATTLECRY_ZEAL: StringName = &"battlecry_zeal"
const ARMORED_SLOW: StringName = &"armored_slow"
const TIMED_ARMOR: StringName = &"timed_armor"
const ACTION_REINFORCEMENT: StringName = &"action_reinforcement"
const ALLY_REFRESH: StringName = &"ally_refresh"
const RANDOM_BANNER: StringName = &"random_banner"
const NONSTACKING_BANNER: StringName = &"nonstacking_banner"
const CAPPED_CHANT: StringName = &"capped_chant"

const PRESETS: Array[Dictionary] = [
	{"id": NONE, "name": "无 D2-3 效果", "description": "只测试基础行动与元素规则。"},
	{"id": BATTLECRY_ZEAL, "name": "战吼·热诚", "description": "战吼：自身获得4层热诚，持续5秒。"},
	{"id": ARMORED_SLOW, "name": "持续·重甲迟缓", "description": "持续：自身有护甲时热诚-4；失去护甲后撤销，恢复护甲后重新生效。"},
	{"id": TIMED_ARMOR, "name": "定时·整备护甲", "description": "战斗到3秒时：自身获得10点护甲，只触发一次。"},
	{"id": ACTION_REINFORCEMENT, "name": "战吼·蓄势", "description": "战吼：自身获得3点强化，在下一次普通行动结算后移除。"},
	{"id": ALLY_REFRESH, "name": "友军行动·刷新热诚", "description": "其他友军行动后：自身获得2层热诚，持续3秒；再次触发只刷新时间。"},
	{"id": RANDOM_BANNER, "name": "战吼·随机鼓舞", "description": "战吼：随机一名友军获得4层热诚，持续整场战斗。"},
	{"id": NONSTACKING_BANNER, "name": "持续·同名旗帜", "description": "持续：所有友军获得2层热诚；同名效果不叠加，最早来源退场后由下一来源接替。"},
	{"id": CAPPED_CHANT, "name": "友军行动·封顶战歌", "description": "其他友军行动后：自身获得2层热诚，可相加但本效果最多贡献6层。"},
]


static func get_option_index(preset_id: StringName) -> int:
	for index: int in PRESETS.size():
		if StringName(PRESETS[index]["id"]) == preset_id:
			return index
	return 0


static func get_preset_id(option_index: int) -> StringName:
	if option_index < 0 or option_index >= PRESETS.size():
		return NONE
	return StringName(PRESETS[option_index]["id"])


static func get_description(preset_id: StringName) -> String:
	return String(PRESETS[get_option_index(preset_id)]["description"])


static func create_definitions(preset_id: StringName) -> Array[BattleEffectDefinition]:
	var definitions: Array[BattleEffectDefinition] = []
	var data: Dictionary = {}
	match preset_id:
		BATTLECRY_ZEAL:
			data = _base_definition(
				"battle_lab.battlecry_zeal", "battlecry", ["always"], "source_combat_unit",
				"add_zeal", 4.0, {"kind": "seconds", "amount": 5.0}, {"kind": "additive"},
				{}, ["持续时间到期", "战斗结束"]
			)
		ARMORED_SLOW:
			data = _base_definition(
				"battle_lab.armored_slow", "continuous", ["source_effect_active", "target_has_armor"], "source_combat_unit",
				"add_zeal", -4.0, {"kind": "while_active"}, {"kind": "same_name_nonstacking"},
				{}, ["条件不再满足", "来源死亡", "战斗结束"]
			)
		TIMED_ARMOR:
			data = _base_definition(
				"battle_lab.timed_armor", "elapsed_battle_time", ["always"], "source_combat_unit",
				"gain_armor", 10.0, {"kind": "instant"}, {"kind": "not_applicable"},
				{"at_seconds": 3.0}, ["操作结算完成"]
			)
		ACTION_REINFORCEMENT:
			data = _base_definition(
				"battle_lab.action_reinforcement", "battlecry", ["always"], "source_combat_unit",
				"add_reinforcement", 3.0, {"kind": "until_consumed_by_action"}, {"kind": "additive"},
				{}, ["指定行动后", "战斗结束"]
			)
		ALLY_REFRESH:
			data = _base_definition(
				"battle_lab.ally_refresh", "other_ally_action_after", ["event_actor_is_other_ally"], "source_combat_unit",
				"add_zeal", 2.0, {"kind": "seconds", "amount": 3.0}, {"kind": "refresh"},
				{}, ["持续时间到期", "战斗结束"]
			)
		RANDOM_BANNER:
			data = _base_definition(
				"battle_lab.random_banner", "battlecry", ["always"], "all_friendly_combat_units",
				"add_zeal", 4.0, {"kind": "battle"}, {"kind": "independent_by_source"},
				{"selection": "random_one"}, ["战斗结束"]
			)
		NONSTACKING_BANNER:
			data = _base_definition(
				"battle_lab.nonstacking_banner", "continuous", ["source_effect_active"], "all_friendly_combat_units",
				"add_zeal", 2.0, {"kind": "while_active"}, {"kind": "same_name_nonstacking"},
				{}, ["条件不再满足", "来源死亡", "战斗结束"]
			)
		CAPPED_CHANT:
			data = _base_definition(
				"battle_lab.capped_chant", "other_ally_action_after", ["event_actor_is_other_ally"], "source_combat_unit",
				"add_zeal", 2.0, {"kind": "battle"}, {"kind": "capped_additive", "cap": 6.0},
				{}, ["战斗结束"]
			)
		_:
			return definitions
	var errors: Array[String] = []
	var definition := BattleEffectDefinition.from_dictionary(data, "battle_lab.%s" % preset_id, errors)
	if definition == null:
		for error: String in errors:
			push_error(error)
		return definitions
	definitions.append(definition)
	return definitions


static func _base_definition(
	effect_id: String,
	trigger: String,
	conditions: Array,
	target: String,
	operation: String,
	amount: float,
	duration: Dictionary,
	stacking: Dictionary,
	parameters: Dictionary,
	end_conditions: Array
) -> Dictionary:
	return {
		"effect_id": effect_id,
		"effect_group": "%s.group" % effect_id,
		"group_order": 1,
		"trigger": trigger,
		"conditions": conditions,
		"target": target,
		"operation": operation,
		"value": {"kind": "fixed", "amount": amount},
		"duration": duration,
		"stacking": stacking,
		"source_owner": "minion_card_instance",
		"result_owner": "affected_combat_unit",
		"end_conditions": end_conditions,
		"end_relation": "任一满足",
		"trigger_limit": {"scope": "continuous"},
		"tags": ["战斗实验室"],
		"related_effects": [],
		"modifier": null,
		"parameters": parameters,
		"reading": get_description_from_effect_id(effect_id),
	}


static func get_description_from_effect_id(effect_id: String) -> String:
	for preset: Dictionary in PRESETS:
		if effect_id.ends_with(String(preset["id"])):
			return String(preset["description"])
	return "战斗实验室效果"
