class_name BattleEffectTraceEntry
extends RefCounted

## 机器可比较、同时可直接阅读的效果运行日志。

var logical_time_us: int = 0
var event_id: int = 0
var root_event_id: int = 0
var parent_event_id: int = 0
var effect_id: StringName = &""
var effect_group: StringName = &""
var source_runtime_id: int = 0
var target_runtime_id: int = 0
var phase: StringName = &""
var result: StringName = &""
var detail: String = ""


func stable_signature() -> String:
	return "%d|%d|%d|%d|%s|%d|%d|%s|%s|%s" % [
		logical_time_us, event_id, root_event_id, parent_event_id, effect_id,
		source_runtime_id, target_runtime_id, phase, result, detail,
	]


func to_text() -> String:
	return "[t=%.3f e=%d root=%d parent=%d] %s %s：%s%s" % [
		BattleEventQueue.us_to_seconds(logical_time_us), event_id, root_event_id,
		parent_event_id, effect_id, phase, result,
		"（%s）" % detail if not detail.is_empty() else "",
	]
