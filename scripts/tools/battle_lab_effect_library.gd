class_name BattleLabEffectLibrary
extends RefCounted

## 战斗实验室专用的 D2-3 效果测试卡库。
## 它只组合正式 BattleEffectDefinition，不复制任何效果结算规则。

const EFFECT_DATA_PATH: String = "res://data/demo2/ash_ledger_effect_samples.json"

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
	{"id": &"old_wolf_kaspar", "name": "灰烬·“老狼”卡斯帕", "description": "真实效果：友方乡邻效果额外触发一次。"},
	{"id": &"anvil_margaret", "name": "灰烬·“铁砧”玛格丽特", "description": "真实效果：友军获得护甲×2；有护甲时热诚-4。"},
	{"id": &"heavy_knight", "name": "灰烬·重装骑士", "description": "真实效果：战吼获得等同于当前护甲的强化。"},
	{"id": &"mudleg_brothers", "name": "灰烬·泥腿三兄弟", "description": "真实效果：无法堆叠；亡语遮蔽符文并重新入场。复活依赖仍未实现。"},
	{"id": &"rune_engraver", "name": "灰烬·符文刻匠", "description": "真实效果：有护甲的友军行动倍率+0.1。"},
	{"id": &"militia_commander", "name": "灰烬·民兵指挥官", "description": "真实效果：友方人类按相邻人类数量获得生命。"},
	{"id": &"recruiter", "name": "灰烬·征召官", "description": "真实效果：战吼随机获得随从。加卡系统依赖仍未实现。"},
	{"id": &"diplomat", "name": "灰烬·外交官", "description": "真实效果：所有非精灵友军数值+1。"},
	{"id": &"berserker_vanguard", "name": "灰烬·狂战先锋", "description": "真实效果：累计损失生命后永久成长。永久写回依赖仍未实现。"},
	{"id": &"shieldwall_private", "name": "灰烬·盾墙列兵", "description": "真实效果：乡邻生效时，每次获得护甲额外+1。"},
	{"id": &"fireman", "name": "灰烬·伙夫", "description": "真实效果：战吼按双方生效火符文增加本场生命。"},
	{"id": &"field_medic", "name": "灰烬·随军医者", "description": "真实效果：治疗后遮蔽目标伤势5秒。伤势依赖仍未实现。"},
	{"id": &"war_drum_musician", "name": "灰烬·战鼓乐师", "description": "真实效果：回响使同排友军获得强化1。"},
	{"id": &"timid_infantry", "name": "灰烬·胆怯的步兵", "description": "真实效果：其他友军行动后获得强化1，本效果最多累计5。"},
	{"id": &"armorsmith", "name": "灰烬·铸甲师", "description": "真实效果：相邻友军被消灭后永久护甲+1。永久写回依赖仍未实现。"},
	{"id": &"baggage_muleteer", "name": "灰烬·辎重驮夫", "description": "真实效果：战吼获得金币，乡邻额外获得金币。金币依赖仍未实现。"},
	{"id": &"militia", "name": "灰烬·民兵", "description": "真实效果：乡邻使自身和相邻人类小队本场数值+1。"},
	{"id": &"javelin_skirmisher", "name": "灰烬·标枪散兵", "description": "真实效果：战吼执行数值+2的远程行动，发射后转为近战。"},
	{"id": &"musketeer", "name": "灰烬·火枪手", "description": "真实效果：乡邻使自身受击优先级-3。"},
	{"id": &"elegy_poet", "name": "灰烬·悲歌诗人", "description": "真实效果：非衍生友军死亡后，本场数值与护甲成长。"},
]

static var _real_catalog: BattleEffectCatalog


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
			var catalog := _get_real_catalog()
			if catalog == null or not catalog.is_valid():
				return definitions
			var effect_ids: Array = catalog.card_effect_ids.get(preset_id, [])
			for effect_id: StringName in effect_ids:
				var real_definition := catalog.get_definition(effect_id)
				if real_definition != null:
					definitions.append(real_definition)
			return definitions
	var errors: Array[String] = []
	var definition := BattleEffectDefinition.from_dictionary(data, "battle_lab.%s" % preset_id, errors)
	if definition == null:
		for error: String in errors:
			push_error(error)
		return definitions
	definitions.append(definition)
	return definitions


static func _get_real_catalog() -> BattleEffectCatalog:
	if _real_catalog == null:
		_real_catalog = BattleEffectCatalog.load_from_file(EFFECT_DATA_PATH)
		if not _real_catalog.is_valid():
			for error: String in _real_catalog.errors:
				push_error(error)
	return _real_catalog


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
