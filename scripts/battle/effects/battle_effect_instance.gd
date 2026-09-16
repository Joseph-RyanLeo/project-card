class_name BattleEffectInstance
extends RefCounted

## 一条定义在某次战斗中的实际运行实例。

enum EndReason {
	NONE,
	INSTANT_RESOLVED,
	DURATION_EXPIRED,
	ACTION_CONSUMED,
	SOURCE_DEFEATED,
	CONDITION_INVALID,
	BATTLE_ENDED,
	REPLACED,
}

var instance_id: int = 0
var definition: BattleEffectDefinition
var source: BattleEffectOwnerRef
var result_owner: BattleEffectOwnerRef
var target: BattleSquadState
var started_at_us: int = 0
var expires_at_us: int = -1
var active: bool = true
var suppressed: bool = false
var applied_value: float = 0.0
var execution_count: int = 0
var end_reason: EndReason = EndReason.NONE
var end_satisfied: Dictionary = {}
var payload: Dictionary = {}


func stack_key() -> String:
	if definition == null:
		return ""
	var target_id := target.runtime_id if target != null else 0
	return "%s:%d" % [definition.effect_id, target_id]


func source_stack_key() -> String:
	var source_key := source.stable_key() if source != null else "0"
	return "%s:%s" % [stack_key(), source_key]


func is_source_alive() -> bool:
	return source != null and source.is_alive()
