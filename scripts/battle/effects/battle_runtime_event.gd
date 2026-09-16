class_name BattleRuntimeEvent
extends RefCounted

## 固定逻辑时间轴上的一个事件；event_id/parent/root 构成可追踪因果链。

enum Kind {
	TRIGGER,
	SELECT_TARGETS,
	APPLY_OPERATION,
	EXPIRE,
	CONDITION_RECHECK,
	ACTION_AFTER,
	SOURCE_DEFEATED,
	BATTLE_END,
	CONTINUOUS_TICK,
}

enum Priority {
	PRE_APPLY = 100,
	TRIGGER = 200,
	SELECT_TARGETS = 250,
	EXECUTE = 300,
	POST_APPLY = 400,
	EXPIRE = 500,
}

var event_id: int = 0
var root_event_id: int = 0
var parent_event_id: int = 0
var logical_time_us: int = 0
var priority: int = Priority.TRIGGER
var stable_order: int = 0
var kind: Kind = Kind.TRIGGER
var trigger: int = -1
var effect_instance: BattleEffectInstance
var definition: BattleEffectDefinition
var source: BattleEffectOwnerRef
var target: BattleSquadState
var tags: Array[StringName] = []
var payload: Dictionary = {}
var cancelled: bool = false


func add_tag(tag: StringName) -> void:
	if tag != &"" and not tags.has(tag):
		tags.append(tag)


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


static func is_before(left: BattleRuntimeEvent, right: BattleRuntimeEvent) -> bool:
	if left.logical_time_us != right.logical_time_us:
		return left.logical_time_us < right.logical_time_us
	if left.priority != right.priority:
		return left.priority < right.priority
	return left.stable_order < right.stable_order
