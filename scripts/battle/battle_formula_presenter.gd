class_name BattleFormulaPresenter
extends RefCounted

## Main 与战斗实验室共用的公式文本和尺寸计算，避免两套调试界面逐渐显示不同内容。


static func format_popup(formula: BattleFormulaData) -> String:
	var lines: Array[String] = [
		"%s 点%s" % [BattleLogEntry.format_number(formula.exact_result), formula.display_name],
		"────────────────────",
		"基础数值  %s" % BattleLogEntry.format_number(formula.base_value),
	]
	if formula.additive_terms.is_empty():
		lines.append("装备等前置加成  0（入口保留）")
	else:
		for term: Dictionary in formula.additive_terms:
			lines.append("%s  %s" % [term.get("name", "前置加成"), BattleLogEntry.format_number(float(term.get("value", 0.0)))])
	lines.append("牌型倍率  ×%s" % BattleLogEntry.format_number(formula.pattern_multiplier))
	lines.append("元素倍率  ×%s" % BattleLogEntry.format_number(formula.element_multiplier))
	if formula.other_multipliers.is_empty():
		lines.append("其他倍率  ×1")
	else:
		for term: Dictionary in formula.other_multipliers:
			lines.append("%s  ×%s" % [term.get("name", "其他倍率"), BattleLogEntry.format_number(float(term.get("value", 1.0)))])
	lines.append("最终固定加成  %s" % BattleLogEntry.format_number(formula.final_flat_bonus))
	lines.append("精确结果  %s" % BattleLogEntry.format_number(formula.exact_result))
	lines.append("本次进入小数累计  %s" % BattleLogEntry.format_number(formula.fractional_remainder))
	return "\n".join(lines)


static func measure_popup_size(popup_content: String, font: Font, font_size: int, minimum_width: float, maximum_width: float, maximum_height: float, content_padding: Vector2) -> Vector2:
	var content_width := 0.0
	var line_widths: Array[float] = []
	for line: String in popup_content.split("\n"):
		var line_width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		line_widths.append(line_width)
		content_width = maxf(content_width, line_width)
	var popup_width := clampf(ceilf(content_width + content_padding.x), minimum_width, maximum_width)
	var available_content_width := maxf(popup_width - content_padding.x, 1.0)
	var visual_line_count := 0
	for line_width: float in line_widths:
		visual_line_count += maxi(ceili(line_width / available_content_width), 1)
	visual_line_count = maxi(visual_line_count, 1)
	var popup_height := float(visual_line_count) * font.get_height(font_size) + content_padding.y
	return Vector2(popup_width, minf(ceilf(popup_height), maximum_height))
