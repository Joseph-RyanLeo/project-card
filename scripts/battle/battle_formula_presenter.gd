class_name BattleFormulaPresenter
extends RefCounted

## Main 与战斗实验室共用面向玩家的公式说明；完整来源仍由诊断导出保存。


static func format_popup(formula: BattleFormulaData, event: BattleEffectEvent = null) -> String:
	var actual_integer := _actual_integer_amount(event, formula)
	var effect_name := formula.display_name if not formula.display_name.is_empty() else "效果"
	var lines: Array[String] = ["实际生效 %s 点%s" % [BattleLogEntry.format_number(actual_integer), effect_name]]
	var displayed_base := formula.base_value
	for term: Dictionary in formula.additive_terms:
		if String(term.get("name", "")) == "效果数值修正":
			displayed_base += float(term.get("value", 0.0))
	lines.append("基础数值  %s" % BattleLogEntry.format_number(displayed_base))
	_append_brief_sources(lines, formula.base_value_sources)
	_append_brief_sources(lines, formula.action_value_modifier_sources)
	var reinforcement := _term_value(formula, "强化")
	if not is_zero_approx(reinforcement):
		lines.append("强化  %s" % _signed_number(reinforcement))
		_append_brief_sources(lines, formula.reinforcement_modifier_sources)
	var immediate_delta := _term_value(formula, "即时行动数值修正")
	if not is_zero_approx(immediate_delta):
		var source_name := String(formula.immediate_action_source.get("source_card_name", "本次行动"))
		lines.append("%s  %s" % [source_name, _signed_number(immediate_delta)])
	if not is_equal_approx(formula.pattern_multiplier, 1.0):
		lines.append("牌型倍率  ×%s" % BattleLogEntry.format_number(formula.pattern_multiplier))
	if not is_equal_approx(formula.element_multiplier, 1.0):
		var target_label := event.log_qualifier if event != null and not event.log_qualifier.is_empty() else "主目标"
		lines.append("元素符文倍率  ×%s（%s）" % [BattleLogEntry.format_number(formula.element_multiplier), target_label])
	for term: Dictionary in formula.other_multipliers:
		var value := float(term.get("value", 1.0))
		if is_equal_approx(value, 1.0):
			continue
		var label := String(term.get("name", "其他倍率"))
		if label == "承伤修正" and value < 1.0:
			lines.append("减伤  %s%%" % BattleLogEntry.format_number((1.0 - value) * 100.0))
		else:
			lines.append("%s  ×%s" % [label, BattleLogEntry.format_number(value)])
	if not is_zero_approx(formula.final_flat_bonus):
		lines.append("固定加成  %s" % _signed_number(formula.final_flat_bonus))
		_append_brief_sources(lines, formula.final_flat_bonus_sources, false)
	lines.append("最终精确结果  %s" % BattleLogEntry.format_number(formula.exact_result))
	_append_fractional_carry(lines, formula, event)
	return "\n".join(lines)


static func _actual_integer_amount(event: BattleEffectEvent, formula: BattleFormulaData) -> float:
	if event == null:
		return formula.exact_result
	if event.missed:
		return 0.0
	if event.fractional_channel_snapshots.is_empty():
		return event.effective_amount
	var total := 0.0
	for snapshot: Dictionary in event.fractional_channel_snapshots:
		total += float(snapshot.get("committed_integer", 0.0))
	return total


static func _append_brief_sources(
	lines: Array[String],
	sources: Array[Dictionary],
	include_source_label: bool = true
) -> void:
	for source: Dictionary in sources:
		var contributions: Variant = source.get("contribution_sources", [])
		if contributions is Array and not (contributions as Array).is_empty():
			for contribution_value: Variant in contributions as Array:
				if not contribution_value is Dictionary:
					continue
				var contribution := contribution_value as Dictionary
				var contribution_name := String(contribution.get("source_card_name", ""))
				var contribution_source := String(contribution.get("source_name", ""))
				if not contribution_source.is_empty() and contribution_source != contribution_name:
					contribution_name += " · %s" % contribution_source
				if contribution_name.is_empty():
					continue
				lines.append("  · %s %s" % [contribution_name, _signed_number(float(contribution.get("amount", 0.0)))])
			continue
		var card_name := String(source.get("source_card_name", ""))
		var name := String(source.get("source_name", card_name)) if include_source_label else card_name
		if include_source_label and not name.is_empty() and not card_name.is_empty() and name != card_name:
			name += " · %s" % card_name
		if name.is_empty():
			continue
		var amount := float(source.get("amount", source.get("value", 0.0)))
		lines.append("  · %s %s" % [name, _signed_number(amount)])


static func _append_fractional_carry(
	lines: Array[String],
	formula: BattleFormulaData,
	event: BattleEffectEvent
) -> void:
	var carries: Array[String] = []
	if event != null:
		var latest_by_channel: Dictionary = {}
		for snapshot: Dictionary in event.fractional_channel_snapshots:
			latest_by_channel[String(snapshot.get("channel", ""))] = float(snapshot.get("new_remainder", 0.0))
		for channel: String in latest_by_channel:
			var remainder := float(latest_by_channel[channel])
			if is_zero_approx(remainder):
				continue
			var label := "护甲" if channel.contains("armor") else ("生命" if channel.contains("health") else channel)
			carries.append("%s %s" % [label, BattleLogEntry.format_number(remainder)])
	elif not is_zero_approx(formula.fractional_remainder):
		carries.append(BattleLogEntry.format_number(formula.fractional_remainder))
	if not carries.is_empty():
		lines.append("小数结转  %s" % "、".join(carries))


static func _term_value(formula: BattleFormulaData, name: String) -> float:
	for term: Dictionary in formula.additive_terms:
		if String(term.get("name", "")) == name:
			return float(term.get("value", 0.0))
	return 0.0


static func _signed_number(value: float) -> String:
	var formatted := BattleLogEntry.format_number(value)
	return ("+" if value > 0.0 else "") + formatted


static func measure_popup_size(
	popup_content: String,
	font: Font,
	font_size: int,
	minimum_width: float,
	maximum_width: float,
	maximum_height: float,
	content_padding: Vector2,
	available_viewport_size: Vector2 = Vector2.ZERO
) -> Vector2:
	var upper_width := maximum_width
	if available_viewport_size.x > 0.0:
		upper_width = minf(upper_width, maxf(available_viewport_size.x, 1.0))
	var content_width := 0.0
	for line: String in popup_content.split("\n"):
		content_width = maxf(
			content_width,
			font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		)
	var popup_width := clampf(
		content_width + content_padding.x,
		minf(minimum_width, upper_width),
		upper_width
	)
	var text_width := maxf(popup_width - content_padding.x, 1.0)
	var text_size := font.get_multiline_string_size(
		popup_content,
		HORIZONTAL_ALIGNMENT_LEFT,
		text_width,
		font_size
	)
	var popup_height := ceilf(text_size.y + content_padding.y)
	if available_viewport_size.y > 0.0:
		popup_height = minf(popup_height, available_viewport_size.y)
	return Vector2(popup_width, minf(popup_height, maximum_height))


static func place_popup(mouse: Vector2, viewport_size: Vector2, popup_size: Vector2, mouse_gap: float) -> Vector2:
	var above_y := mouse.y - popup_size.y - mouse_gap
	var below_y := mouse.y + mouse_gap
	var desired_y := below_y if above_y < 0.0 and below_y + popup_size.y <= viewport_size.y else above_y
	return Vector2(
		clampf(mouse.x - popup_size.x * 0.5, 0.0, maxf(viewport_size.x - popup_size.x, 0.0)),
		clampf(desired_y, 0.0, maxf(viewport_size.y - popup_size.y, 0.0))
	)
