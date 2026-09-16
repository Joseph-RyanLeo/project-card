class_name BattleEffectDuration
extends RefCounted

## 效果保持多久；具体结束原因由运行实例记录。

enum Kind {
	INSTANT,
	SECONDS,
	UNTIL_ACTION,
	WHILE_ACTIVE,
	BATTLE,
	CURRENT_RUN_PERMANENT,
}

const KIND_BY_NAME: Dictionary = {
	"instant": Kind.INSTANT,
	"seconds": Kind.SECONDS,
	"until_consumed_by_action": Kind.UNTIL_ACTION,
	"while_active": Kind.WHILE_ACTIVE,
	"battle": Kind.BATTLE,
	"current_run_permanent": Kind.CURRENT_RUN_PERMANENT,
}

var kind: Kind = Kind.INSTANT
var seconds: float = 0.0


static func from_dictionary(data: Dictionary, path: String, errors: Array[String]) -> BattleEffectDuration:
	var kind_name := String(data.get("kind", ""))
	if not KIND_BY_NAME.has(kind_name):
		errors.append("%s.kind 未知：%s" % [path, kind_name])
		return null
	var result := BattleEffectDuration.new()
	result.kind = int(KIND_BY_NAME[kind_name]) as Kind
	if result.kind == Kind.SECONDS:
		if typeof(data.get("amount")) not in [TYPE_INT, TYPE_FLOAT] or float(data["amount"]) <= 0.0:
			errors.append("%s.amount 必须是正数" % path)
			return null
		result.seconds = float(data["amount"])
	return result


static func seconds_duration(value: float) -> BattleEffectDuration:
	var result := BattleEffectDuration.new()
	result.kind = Kind.SECONDS
	result.seconds = value
	return result
