class_name BattleLogEntry
extends RefCounted

## 同一次行动或持续结算的结构化日志组。

var group_id: int = 0
var timestamp: float = 0.0
var source: BattleSquadState
var events: Array[BattleEffectEvent] = []


func add_event(event: BattleEffectEvent) -> void:
	if event != null:
		events.append(event)
		if source == null:
			source = event.source


func get_formula(index: int) -> BattleFormulaData:
	if index < 0 or index >= events.size():
		return null
	return events[index].formula


func to_bbcode() -> String:
	if events.is_empty():
		return ""
	var clauses: Array[String] = []
	for index: int in events.size():
		var event := events[index]
		if event.effect_kind == BattleEffectEvent.EffectKind.PLACEHOLDER:
			clauses.append(_placeholder_clause(event))
			continue
		var verb := "造成了" if event.effect_kind == BattleEffectEvent.EffectKind.DAMAGE else "提供了"
		var qualifier := "%s" % event.log_qualifier if not event.log_qualifier.is_empty() else ""
		var value := format_number(event.exact_amount)
		clauses.append("对%s%s[url=formula:%d:%d]%s点%s%s[/url]" % [
			_format_state_name(event.target), verb, group_id, index, value,
			qualifier, event.formula.display_name if event.formula != null else "效果",
		])
	var prefix := _format_state_name(source) if source != null else (events[0].log_qualifier if not events[0].log_qualifier.is_empty() else "系统")
	return "%s%s" % [prefix, "，同时".join(clauses)]


static func format_number(value: float) -> String:
	var result := String.num(value, 2)
	while result.contains(".") and result.ends_with("0"):
		result = result.left(-1)
	if result.ends_with("."):
		result = result.left(-1)
	return result


static func _format_state_name(state: BattleSquadState) -> String:
	if state == null or state.get_effect_source() == null:
		return "未知目标"
	var side_name := "我方" if state.side == BattleSquadState.Side.PLAYER else "敌方"
	var result := "%s%s" % [side_name, state.get_effect_source().display_name]
	if state.squad_data != null and state.squad_data.get_card_count() > 1:
		result += "的小队"
	return result


static func _placeholder_clause(event: BattleEffectEvent) -> String:
	return "对%s%s" % [_format_state_name(event.target), event.log_qualifier]
