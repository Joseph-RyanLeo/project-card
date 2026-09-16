class_name BattleEffectModifierSpec
extends RefCounted

## 对其他效果的修改规则；filter 保留结构化筛选参数，不解释自然语言。

enum Mode { NONE, ADD_VALUE, MULTIPLY_VALUE, EXTRA_EXECUTION }

const MODE_BY_NAME: Dictionary = {
	"add_value": Mode.ADD_VALUE,
	"multiply_value": Mode.MULTIPLY_VALUE,
	"extra_execution": Mode.EXTRA_EXECUTION,
}

var mode: Mode = Mode.NONE
var amount: float = 0.0
var recursive: bool = false
var filter: Dictionary = {}


static func from_variant(value: Variant, path: String, errors: Array[String]) -> BattleEffectModifierSpec:
	var result := BattleEffectModifierSpec.new()
	if value == null:
		return result
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s 必须是对象或 null" % path)
		return null
	var data := value as Dictionary
	var mode_name := String(data.get("mode", ""))
	if not MODE_BY_NAME.has(mode_name):
		errors.append("%s.mode 未知：%s" % [path, mode_name])
		return null
	result.mode = int(MODE_BY_NAME[mode_name]) as Mode
	if typeof(data.get("amount")) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s.amount 必须是数字" % path)
		return null
	result.amount = float(data["amount"])
	result.recursive = bool(data.get("recursive", false))
	result.filter = (data.get("filter", {}) as Dictionary).duplicate(true)
	return result
