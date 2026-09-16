class_name BattleEffectStacking
extends RefCounted

## 多个运行实例作用于同一目标时的合并方式。

enum Kind {
	ADDITIVE,
	SAME_NAME_NONSTACKING,
	INDEPENDENT_BY_SOURCE,
	REFRESH,
	CAPPED_ADDITIVE,
	NOT_APPLICABLE,
}

const KIND_BY_NAME: Dictionary = {
	"additive": Kind.ADDITIVE,
	"same_name_nonstacking": Kind.SAME_NAME_NONSTACKING,
	"independent_by_source": Kind.INDEPENDENT_BY_SOURCE,
	"refresh": Kind.REFRESH,
	"capped_additive": Kind.CAPPED_ADDITIVE,
	"not_applicable": Kind.NOT_APPLICABLE,
}

var kind: Kind = Kind.NOT_APPLICABLE
var cap: float = INF


static func from_dictionary(data: Dictionary, path: String, errors: Array[String]) -> BattleEffectStacking:
	var kind_name := String(data.get("kind", ""))
	if not KIND_BY_NAME.has(kind_name):
		errors.append("%s.kind 未知：%s" % [path, kind_name])
		return null
	var result := BattleEffectStacking.new()
	result.kind = int(KIND_BY_NAME[kind_name]) as Kind
	if result.kind == Kind.CAPPED_ADDITIVE:
		if typeof(data.get("cap")) not in [TYPE_INT, TYPE_FLOAT] or float(data["cap"]) < 0.0:
			errors.append("%s.cap 必须是非负数" % path)
			return null
		result.cap = float(data["cap"])
	return result
