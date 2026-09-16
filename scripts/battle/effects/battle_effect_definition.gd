class_name BattleEffectDefinition
extends RefCounted

## 一条已经通过校验的原子效果定义。
## 枚举负责拒绝拼写漂移，复杂参数则保留在各自的严格子对象中。

enum Trigger {
	CONTINUOUS,
	BATTLECRY,
	DEATHRATTLE,
	BATTLE_START_SPELL,
	ELAPSED_BATTLE_TIME,
	OTHER_ALLY_ACTION_AFTER,
	AFTER_BASIC_HEAL,
	ALLY_ABOUT_TO_BE_DESTROYED,
	ADJACENT_ALLY_DESTROYED,
	OTHER_ALLY_DESTROYED,
	BATTLE_WON,
	ECHO,
	ARMOR_GAIN_BEFORE_APPLY,
	SOURCE_ARMOR_GAINED,
	SOURCE_HEALTH_LOST_ACCUMULATED,
	EQUIPPED_UNIT_AFTER_BASIC_ACTION_DAMAGE,
}

enum Condition {
	ALWAYS,
	SOURCE_EFFECT_ACTIVE,
	TARGET_HAS_ARMOR,
	TARGET_IS_HUMAN,
	TARGET_IS_NON_ELF,
	NEIGHBOR_ACTIVE,
	HAS_GRANTED_EFFECT,
	PER_BATTLE_COUNT_BELOW_LIMIT,
	EVENT_ACTOR_IS_OTHER_ALLY,
	TARGET_HAS_ACTIVE_INJURY,
	DESTRUCTION_CAUSED_BY_HEALTH_REACHING_ZERO,
	DAMAGE_SOURCE_EXISTS,
	DEAD_UNIT_NOT_DERIVED,
	LEGAL_DEAD_TARGET,
	SUMMON_SPACE_AVAILABLE,
	EQUIPMENT_EQUIPPED,
	EQUIPPED_UNIT_ALIVE,
	SOURCE_EQUIPMENT_PARTICIPATED,
	NOT_SAME_EFFECT_GENERATED_GAIN,
	ACCUMULATED_HEALTH_LOSS_AT_LEAST_VALUE,
}

enum Target {
	SOURCE_COMBAT_UNIT,
	SOURCE_CARD_INSTANCE,
	SOURCE_DEAD_CARD,
	SOURCE_ACTIVE_RUNE,
	SOURCE_EQUIPMENT,
	ALL_FRIENDLY_COMBAT_UNITS,
	ADJACENT_FRIENDLY_UNITS,
	SAME_ROW_FRIENDLY_UNITS,
	SELF_AND_ADJACENT_HUMAN_UNITS,
	BACK_ROW_RANGED_ALLIES,
	DAMAGE_SOURCE,
	EQUIPPED_UNIT,
	EQUIPPED_UNIT_INJURIES,
	HEALED_TARGET_ACTIVE_INJURY,
	LATEST_DEAD_NONDERIVED_ALLY,
	FRIENDLY_ARMOR_GAIN_EVENTS,
	FRIENDLY_NEIGHBOR_EFFECTS,
	GRANTED_EFFECT_HOLDER,
	OWNING_PLAYER,
}

enum Operation {
	ADD_ATTRIBUTE,
	ADD_TARGET_PRIORITY,
	ADD_ACTION_MULTIPLIER,
	ADD_ZEAL,
	ADD_REINFORCEMENT,
	GAIN_ARMOR,
	GAIN_GOLD,
	DEAL_NON_ACTION_DAMAGE,
	PERMANENTLY_ADD_ARMOR,
	PERMANENTLY_ADD_BASE_VALUE,
	SET_ACTION_TYPE,
	SET_MINIMUM_HEALTH,
	IMMEDIATE_ACTION,
	REVIVE,
	MASK_INJURY,
	MASK_RUNE,
	GRANT_KEYWORD,
	GRANT_EFFECT,
	GRANT_RANDOM_CARD,
	MODIFY_EFFECT,
	FORBID_STACKING,
	CONSUME_EQUIPMENT,
}

enum OwnerKind {
	MINION_CARD_INSTANCE,
	SPELL_CARD_INSTANCE,
	EQUIPMENT_INSTANCE,
	AFFECTED_COMBAT_UNIT,
	SOURCE_COMBAT_UNIT,
	ACTION_PROVIDER_CARD,
	ARMOR_PROVIDER_CARD,
	DAMAGE_SOURCE,
	OWNING_PLAYER,
}

enum EndCondition {
	OPERATION_RESOLVED,
	DURATION_EXPIRED,
	SPECIFIED_ACTION_AFTER,
	SOURCE_DEATH,
	SOURCE_EFFECT_INVALID,
	CONDITION_INVALID,
	NEIGHBOR_INVALID,
	EQUIPMENT_UNEQUIPPED,
	EQUIPMENT_CONSUMED,
	BATTLE_END,
	RUN_END,
}

enum EndRelation { ANY, ALL }

const TRIGGER_BY_NAME: Dictionary = {
	"continuous": Trigger.CONTINUOUS,
	"battlecry": Trigger.BATTLECRY,
	"deathrattle": Trigger.DEATHRATTLE,
	"battle_start_spell": Trigger.BATTLE_START_SPELL,
	"elapsed_battle_time": Trigger.ELAPSED_BATTLE_TIME,
	"other_ally_action_after": Trigger.OTHER_ALLY_ACTION_AFTER,
	"after_basic_heal": Trigger.AFTER_BASIC_HEAL,
	"ally_about_to_be_destroyed": Trigger.ALLY_ABOUT_TO_BE_DESTROYED,
	"adjacent_ally_destroyed": Trigger.ADJACENT_ALLY_DESTROYED,
	"other_ally_destroyed": Trigger.OTHER_ALLY_DESTROYED,
	"battle_won": Trigger.BATTLE_WON,
	"echo": Trigger.ECHO,
	"armor_gain_before_apply": Trigger.ARMOR_GAIN_BEFORE_APPLY,
	"source_armor_gained": Trigger.SOURCE_ARMOR_GAINED,
	"source_health_lost_accumulated": Trigger.SOURCE_HEALTH_LOST_ACCUMULATED,
	"equipped_unit_after_basic_action_damage": Trigger.EQUIPPED_UNIT_AFTER_BASIC_ACTION_DAMAGE,
}

const CONDITION_BY_NAME: Dictionary = {
	"always": Condition.ALWAYS,
	"source_effect_active": Condition.SOURCE_EFFECT_ACTIVE,
	"target_has_armor": Condition.TARGET_HAS_ARMOR,
	"target_is_human": Condition.TARGET_IS_HUMAN,
	"target_is_non_elf": Condition.TARGET_IS_NON_ELF,
	"neighbor_active": Condition.NEIGHBOR_ACTIVE,
	"has_granted_effect": Condition.HAS_GRANTED_EFFECT,
	"per_battle_count_below_limit": Condition.PER_BATTLE_COUNT_BELOW_LIMIT,
	"event_actor_is_other_ally": Condition.EVENT_ACTOR_IS_OTHER_ALLY,
	"target_has_active_injury": Condition.TARGET_HAS_ACTIVE_INJURY,
	"destruction_caused_by_health_reaching_zero": Condition.DESTRUCTION_CAUSED_BY_HEALTH_REACHING_ZERO,
	"damage_source_exists": Condition.DAMAGE_SOURCE_EXISTS,
	"dead_unit_not_derived": Condition.DEAD_UNIT_NOT_DERIVED,
	"legal_dead_target": Condition.LEGAL_DEAD_TARGET,
	"summon_space_available": Condition.SUMMON_SPACE_AVAILABLE,
	"equipment_equipped": Condition.EQUIPMENT_EQUIPPED,
	"equipped_unit_alive": Condition.EQUIPPED_UNIT_ALIVE,
	"source_equipment_participated": Condition.SOURCE_EQUIPMENT_PARTICIPATED,
	"not_same_effect_generated_gain": Condition.NOT_SAME_EFFECT_GENERATED_GAIN,
	"accumulated_health_loss_at_least_value": Condition.ACCUMULATED_HEALTH_LOSS_AT_LEAST_VALUE,
}

const TARGET_BY_NAME: Dictionary = {
	"source_combat_unit": Target.SOURCE_COMBAT_UNIT,
	"source_card_instance": Target.SOURCE_CARD_INSTANCE,
	"source_dead_card": Target.SOURCE_DEAD_CARD,
	"source_active_rune": Target.SOURCE_ACTIVE_RUNE,
	"source_equipment": Target.SOURCE_EQUIPMENT,
	"all_friendly_combat_units": Target.ALL_FRIENDLY_COMBAT_UNITS,
	"adjacent_friendly_units": Target.ADJACENT_FRIENDLY_UNITS,
	"same_row_friendly_units": Target.SAME_ROW_FRIENDLY_UNITS,
	"self_and_adjacent_human_units": Target.SELF_AND_ADJACENT_HUMAN_UNITS,
	"back_row_ranged_allies": Target.BACK_ROW_RANGED_ALLIES,
	"damage_source": Target.DAMAGE_SOURCE,
	"equipped_unit": Target.EQUIPPED_UNIT,
	"equipped_unit_injuries": Target.EQUIPPED_UNIT_INJURIES,
	"healed_target_active_injury": Target.HEALED_TARGET_ACTIVE_INJURY,
	"latest_dead_nonderived_ally": Target.LATEST_DEAD_NONDERIVED_ALLY,
	"friendly_armor_gain_events": Target.FRIENDLY_ARMOR_GAIN_EVENTS,
	"friendly_neighbor_effects": Target.FRIENDLY_NEIGHBOR_EFFECTS,
	"granted_effect_holder": Target.GRANTED_EFFECT_HOLDER,
	"owning_player": Target.OWNING_PLAYER,
}

const OPERATION_BY_NAME: Dictionary = {
	"add_attribute": Operation.ADD_ATTRIBUTE,
	"add_target_priority": Operation.ADD_TARGET_PRIORITY,
	"add_action_multiplier": Operation.ADD_ACTION_MULTIPLIER,
	"add_zeal": Operation.ADD_ZEAL,
	"add_reinforcement": Operation.ADD_REINFORCEMENT,
	"gain_armor": Operation.GAIN_ARMOR,
	"gain_gold": Operation.GAIN_GOLD,
	"deal_non_action_damage": Operation.DEAL_NON_ACTION_DAMAGE,
	"permanently_add_armor": Operation.PERMANENTLY_ADD_ARMOR,
	"permanently_add_base_value": Operation.PERMANENTLY_ADD_BASE_VALUE,
	"set_action_type": Operation.SET_ACTION_TYPE,
	"set_minimum_health": Operation.SET_MINIMUM_HEALTH,
	"immediate_action": Operation.IMMEDIATE_ACTION,
	"revive": Operation.REVIVE,
	"mask_injury": Operation.MASK_INJURY,
	"mask_rune": Operation.MASK_RUNE,
	"grant_keyword": Operation.GRANT_KEYWORD,
	"grant_effect": Operation.GRANT_EFFECT,
	"grant_random_card": Operation.GRANT_RANDOM_CARD,
	"modify_effect": Operation.MODIFY_EFFECT,
	"forbid_stacking": Operation.FORBID_STACKING,
	"consume_equipment": Operation.CONSUME_EQUIPMENT,
}

const OWNER_BY_NAME: Dictionary = {
	"minion_card_instance": OwnerKind.MINION_CARD_INSTANCE,
	"spell_card_instance": OwnerKind.SPELL_CARD_INSTANCE,
	"equipment_instance": OwnerKind.EQUIPMENT_INSTANCE,
	"affected_combat_unit": OwnerKind.AFFECTED_COMBAT_UNIT,
	"source_combat_unit": OwnerKind.SOURCE_COMBAT_UNIT,
	"action_provider_card": OwnerKind.ACTION_PROVIDER_CARD,
	"armor_provider_card": OwnerKind.ARMOR_PROVIDER_CARD,
	"damage_source": OwnerKind.DAMAGE_SOURCE,
	"owning_player": OwnerKind.OWNING_PLAYER,
}

const END_CONDITION_BY_NAME: Dictionary = {
	"操作结算完成": EndCondition.OPERATION_RESOLVED,
	"持续时间到期": EndCondition.DURATION_EXPIRED,
	"指定行动后": EndCondition.SPECIFIED_ACTION_AFTER,
	"来源死亡": EndCondition.SOURCE_DEATH,
	"来源效果失效": EndCondition.SOURCE_EFFECT_INVALID,
	"条件不再满足": EndCondition.CONDITION_INVALID,
	"乡邻失效": EndCondition.NEIGHBOR_INVALID,
	"装备卸下": EndCondition.EQUIPMENT_UNEQUIPPED,
	"装备消耗": EndCondition.EQUIPMENT_CONSUMED,
	"战斗结束": EndCondition.BATTLE_END,
	"本局结束": EndCondition.RUN_END,
}

const END_RELATION_BY_NAME: Dictionary = {
	"任一满足": EndRelation.ANY,
	"全部满足": EndRelation.ALL,
}

var effect_id: StringName = &""
var effect_group: StringName = &""
var group_order: int = 0
var trigger: Trigger = Trigger.CONTINUOUS
var conditions: Array[int] = []
var target: Target = Target.SOURCE_COMBAT_UNIT
var operation: Operation = Operation.ADD_ATTRIBUTE
var value: BattleEffectValue
var duration: BattleEffectDuration
var stacking: BattleEffectStacking
var source_owner: OwnerKind = OwnerKind.MINION_CARD_INSTANCE
var result_owner: OwnerKind = OwnerKind.AFFECTED_COMBAT_UNIT
var end_conditions: Array[int] = []
var end_relation: EndRelation = EndRelation.ANY
var trigger_limit: BattleEffectTriggerLimit
var tags: Array[StringName] = []
var modifier: BattleEffectModifierSpec
var related_effects: Array[Dictionary] = []
var parameters: Dictionary = {}
var reading: String = ""


static func from_dictionary(data: Dictionary, path: String, errors: Array[String]) -> BattleEffectDefinition:
	var start_error_count := errors.size()
	var result := BattleEffectDefinition.new()
	result.effect_id = StringName(data.get("effect_id", ""))
	result.effect_group = StringName(data.get("effect_group", ""))
	result.group_order = int(data.get("group_order", 0))
	if result.effect_id == &"": errors.append("%s.effect_id 不能为空" % path)
	if result.effect_group == &"": errors.append("%s.effect_group 不能为空" % path)
	result.trigger = _parse_enum(TRIGGER_BY_NAME, data.get("trigger"), "%s.trigger" % path, errors) as Trigger
	result.target = _parse_enum(TARGET_BY_NAME, data.get("target"), "%s.target" % path, errors) as Target
	result.operation = _parse_enum(OPERATION_BY_NAME, data.get("operation"), "%s.operation" % path, errors) as Operation
	result.source_owner = _parse_enum(OWNER_BY_NAME, data.get("source_owner"), "%s.source_owner" % path, errors) as OwnerKind
	result.result_owner = _parse_enum(OWNER_BY_NAME, data.get("result_owner"), "%s.result_owner" % path, errors) as OwnerKind

	var raw_conditions: Variant = data.get("conditions")
	if typeof(raw_conditions) != TYPE_ARRAY or (raw_conditions as Array).is_empty():
		errors.append("%s.conditions 必须是非空数组" % path)
	else:
		for index: int in (raw_conditions as Array).size():
			result.conditions.append(_parse_enum(CONDITION_BY_NAME, raw_conditions[index], "%s.conditions[%d]" % [path, index], errors))

	var raw_end_conditions: Variant = data.get("end_conditions")
	if typeof(raw_end_conditions) != TYPE_ARRAY or (raw_end_conditions as Array).is_empty():
		errors.append("%s.end_conditions 必须是非空数组" % path)
	else:
		for index: int in (raw_end_conditions as Array).size():
			result.end_conditions.append(_parse_enum(END_CONDITION_BY_NAME, raw_end_conditions[index], "%s.end_conditions[%d]" % [path, index], errors))
	result.end_relation = _parse_enum(END_RELATION_BY_NAME, data.get("end_relation", "任一满足"), "%s.end_relation" % path, errors) as EndRelation

	if typeof(data.get("value")) != TYPE_DICTIONARY:
		errors.append("%s.value 必须是对象" % path)
	else:
		result.value = BattleEffectValue.from_dictionary(data["value"], "%s.value" % path, errors)
	if typeof(data.get("duration")) != TYPE_DICTIONARY:
		errors.append("%s.duration 必须是对象" % path)
	else:
		result.duration = BattleEffectDuration.from_dictionary(data["duration"], "%s.duration" % path, errors)
	if typeof(data.get("stacking")) != TYPE_DICTIONARY:
		errors.append("%s.stacking 必须是对象" % path)
	else:
		result.stacking = BattleEffectStacking.from_dictionary(data["stacking"], "%s.stacking" % path, errors)
	if typeof(data.get("trigger_limit")) != TYPE_DICTIONARY:
		errors.append("%s.trigger_limit 必须是对象" % path)
	else:
		result.trigger_limit = BattleEffectTriggerLimit.from_dictionary(data["trigger_limit"], "%s.trigger_limit" % path, errors)
	result.modifier = BattleEffectModifierSpec.from_variant(data.get("modifier"), "%s.modifier" % path, errors)

	for tag: Variant in data.get("tags", []):
		result.tags.append(StringName(tag))
	result.related_effects.assign((data.get("related_effects", []) as Array).duplicate(true))
	result.parameters = (data.get("parameters", {}) as Dictionary).duplicate(true)
	result.reading = String(data.get("reading", ""))
	return result if errors.size() == start_error_count else null


static func _parse_enum(mapping: Dictionary, raw_value: Variant, path: String, errors: Array[String]) -> int:
	var name := String(raw_value) if raw_value != null else ""
	if not mapping.has(name):
		errors.append("%s 未知：%s" % [path, name])
		return 0
	return int(mapping[name])
