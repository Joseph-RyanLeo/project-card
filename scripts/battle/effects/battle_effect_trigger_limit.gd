class_name BattleEffectTriggerLimit
extends RefCounted

## 次数限制单独成对象，便于多个原子步骤共享同一 counter_key。

enum Scope { EVENT, BATTLE, GROUP_BATTLE, SETTLEMENT, CONTINUOUS }

const SCOPE_BY_NAME: Dictionary = {
	"event": Scope.EVENT,
	"battle": Scope.BATTLE,
	"group_battle": Scope.GROUP_BATTLE,
	"settlement": Scope.SETTLEMENT,
	"continuous": Scope.CONTINUOUS,
}

var scope: Scope = Scope.EVENT
var count: int = 1
var counter_key: StringName = &""
var reset_on_reentry: bool = false


static func from_dictionary(data: Dictionary, path: String, errors: Array[String]) -> BattleEffectTriggerLimit:
	var scope_name := String(data.get("scope", ""))
	if not SCOPE_BY_NAME.has(scope_name):
		errors.append("%s.scope 未知：%s" % [path, scope_name])
		return null
	var result := BattleEffectTriggerLimit.new()
	result.scope = int(SCOPE_BY_NAME[scope_name]) as Scope
	result.count = int(data.get("count", 1))
	result.counter_key = StringName(data.get("counter_key", ""))
	result.reset_on_reentry = bool(data.get("reset_on_reentry", false))
	if result.scope != Scope.CONTINUOUS and result.count <= 0:
		errors.append("%s.count 必须大于 0" % path)
		return null
	return result
