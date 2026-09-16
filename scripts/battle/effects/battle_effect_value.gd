class_name BattleEffectValue
extends RefCounted

## 效果定义中的取值方式。解析后不再让执行器猜测 JSON 字段含义。

enum Kind {
	FIXED,
	HEALTH_FRACTION,
	READ_STAT,
	COUNT_SCALED,
	EFFECT_REF,
	ENUM_VALUE,
	FLAG,
	FORMULA,
}

const KIND_BY_NAME: Dictionary = {
	"fixed": Kind.FIXED,
	"health_fraction": Kind.HEALTH_FRACTION,
	"read_stat": Kind.READ_STAT,
	"count_scaled": Kind.COUNT_SCALED,
	"effect_ref": Kind.EFFECT_REF,
	"enum": Kind.ENUM_VALUE,
	"flag": Kind.FLAG,
	"formula": Kind.FORMULA,
}

var kind: Kind = Kind.FIXED
var amount: float = 0.0
var multiplier: float = 1.0
var per_count: float = 0.0
var max_count: int = -1
var stat: StringName = &""
var query: StringName = &""
var effect_id: StringName = &""
var enum_value: StringName = &""
var enabled: bool = false
var expression: String = ""


static func from_dictionary(data: Dictionary, path: String, errors: Array[String]) -> BattleEffectValue:
	var start_error_count := errors.size()
	var result := BattleEffectValue.new()
	var kind_name := String(data.get("kind", ""))
	if not KIND_BY_NAME.has(kind_name):
		errors.append("%s.kind 未知：%s" % [path, kind_name])
		return null
	result.kind = int(KIND_BY_NAME[kind_name]) as Kind
	match result.kind:
		Kind.FIXED, Kind.HEALTH_FRACTION:
			if not _is_number(data.get("amount")):
				errors.append("%s.amount 必须是数字" % path)
			else:
				result.amount = float(data["amount"])
		Kind.READ_STAT:
			result.stat = StringName(data.get("stat", ""))
			result.multiplier = float(data.get("multiplier", 1.0))
			if result.stat == &"":
				errors.append("%s.stat 不能为空" % path)
		Kind.COUNT_SCALED:
			result.query = StringName(data.get("query", ""))
			if result.query == &"" or not _is_number(data.get("per_count")):
				errors.append("%s 需要 query 与数字 per_count" % path)
			else:
				result.per_count = float(data["per_count"])
				result.max_count = int(data.get("max_count", -1))
		Kind.EFFECT_REF:
			result.effect_id = StringName(data.get("effect_id", ""))
			if result.effect_id == &"":
				errors.append("%s.effect_id 不能为空" % path)
		Kind.ENUM_VALUE:
			result.enum_value = StringName(data.get("value", ""))
			if result.enum_value == &"":
				errors.append("%s.value 不能为空" % path)
		Kind.FLAG:
			if typeof(data.get("enabled")) != TYPE_BOOL:
				errors.append("%s.enabled 必须是布尔值" % path)
			else:
				result.enabled = bool(data["enabled"])
		Kind.FORMULA:
			result.expression = String(data.get("expression", ""))
			if result.expression.is_empty():
				errors.append("%s.expression 不能为空" % path)
	return result if errors.size() == start_error_count else null


static func fixed(value: float) -> BattleEffectValue:
	var result := BattleEffectValue.new()
	result.kind = Kind.FIXED
	result.amount = value
	return result


static func _is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT]
