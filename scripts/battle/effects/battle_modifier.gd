class_name BattleModifier
extends RefCounted

## 一个可按来源移除的数值贡献。

enum Stat {
	ZEAL,
	ACTION_VALUE,
	MAX_HEALTH,
	BASE_ARMOR,
	TARGET_PRIORITY,
	ARMOR_GAIN,
	INCOMING_DAMAGE,
	REINFORCEMENT,
	MINIMUM_HEALTH,
}

enum Mode { ADD, MULTIPLY, SET_MINIMUM }

var modifier_id: int = 0
var source_instance_id: int = 0
var effect_id: StringName = &""
var source_runtime_id: int = 0
var stat: Stat = Stat.ZEAL
var mode: Mode = Mode.ADD
var value: float = 0.0
var created_order: int = 0
var active: bool = true
