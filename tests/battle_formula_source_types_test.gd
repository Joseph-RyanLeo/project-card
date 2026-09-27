extends SceneTree

## 覆盖真实战斗公式与字典内普通 Array 来源数据的展示路径。

const BattleController = preload("res://scripts/battle/battle_controller.gd")
const BattleFormulaData = preload("res://scripts/battle/battle_formula_data.gd")
const BattleFormulaPresenter = preload("res://scripts/battle/battle_formula_presenter.gd")
const BattleRules = preload("res://scripts/battle/battle_rules.gd")
const SquadData = preload("res://scripts/data/squad_data.gd")
const PopupFont: Font = preload("res://assets/fonts/chill_7.ttf")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_real_attack_formula_and_target_copy()
	_test_dictionary_source_arrays_and_formula_details()
	_test_popup_placement_at_viewport_edges()
	_test_popup_font_measurement_at_low_resolution()
	if failures == 0:
		print("Battle formula source type checks passed.")
	else:
		push_error("Battle formula source type checks failed: %d" % failures)
	quit(failures)


func _test_real_attack_formula_and_target_copy() -> void:
	var attacker_card := load("res://resources/cards/militia.tres") as CardData
	var defender_card := load("res://resources/cards/heavy_knight.tres") as CardData
	var controller := BattleController.new()
	root.add_child(controller)
	controller.start_battle(
		[_entry(attacker_card, &"player_front")],
		[_entry(defender_card, &"enemy_front")],
		972401,
		false
	)
	var attacker := controller.player_states[0]
	var defender := controller.enemy_states[0]
	defender.current_armor = 8.0
	var actions := controller._select_base_actions([attacker], controller.get_all_states())
	var event := actions[0].get("base_event") as BattleEffectEvent if not actions.is_empty() else null
	if event == null:
		_check(false, "真实战斗产生普通攻击公式事件")
		controller.clear_battle()
		controller.free()
		return
	var pre_resolution_value := event.formula.calculate_result()
	var expected_multiplier := BattleRules.get_attack_type_multiplier(
		event.action_type,
		true
	)
	controller._apply_effect_event(event)
	var popup := BattleFormulaPresenter.format_popup(event.formula, event)
	_check(
		popup.contains("实际生效")
		and popup.contains("攻击类型（有护甲）")
		and not popup.contains("攻击类型规则")
		and is_equal_approx(event.exact_amount, pre_resolution_value * expected_multiplier)
		and is_equal_approx(event.formula.calculate_result(), event.exact_amount),
		"真实普通攻击弹窗显示简洁倍率与实际整数结算，不展开诊断来源"
	)
	var reflected_formula := event.formula.duplicate_for_target(attacker)
	var reflected_popup := BattleFormulaPresenter.format_popup(reflected_formula)
	_check(
		not reflected_popup.contains("攻击类型规则")
		and is_equal_approx(reflected_formula.calculate_result(), event.formula.calculate_result())
		and reflected_formula.target == attacker,
		"复制到另一目标的公式快照保留攻击来源且不改变结果"
	)
	controller.clear_battle()
	controller.free()


func _test_dictionary_source_arrays_and_formula_details() -> void:
	var attacker_card := load("res://resources/cards/militia.tres") as CardData
	var defender_card := load("res://resources/cards/heavy_knight.tres") as CardData
	var controller := BattleController.new()
	root.add_child(controller)
	controller.start_battle(
		[_entry(attacker_card, &"player_front")],
		[_entry(defender_card, &"enemy_front")],
		972402,
		false
	)
	var attacker := controller.player_states[0]
	var defender := controller.enemy_states[0]
	var regular_sources: Array = [{
		"source_name": "普通 Array 内的承伤规则",
		"source_status": "resolved",
		"value": 0.8,
	}]
	var armor_sources: Array = [{
		"source_name": "盾墙列兵",
		"source_card_name": "盾墙列兵",
		"source_status": "resolved",
		"value": 1.25,
	}]
	var multipliers: Array[Dictionary] = [
		{
			"name": "攻击类型（有护甲）",
			"value": 0.5,
			"sources": [{
				"source_name": "攻击类型规则",
				"source_status": "resolved",
			}],
		},
		{"name": "承伤修正", "value": 0.8, "sources": regular_sources},
		{
			"name": "获得护甲乘法修正",
			"value": 1.25,
			"sources": armor_sources,
		},
		{"name": "空来源修正", "value": 1.0, "sources": []},
	]
	var additions: Array[Dictionary] = [
		{"name": "强化", "value": 3.0},
		{"name": "即时行动数值修正", "value": 2.0},
	]
	var formula := BattleFormulaData.create(
		"测试伤害",
		CardData.ActionType.MELEE,
		10.0,
		2.0,
		1.5,
		attacker,
		defender,
		multipliers,
		additions,
		2.0
	)
	formula.reinforcement_modifier_sources.append({
		"source_card_name": "鼓手",
		"source_name": "回响强化",
		"amount": 3.0,
	})
	formula.immediate_action_source = {
		"source_card_name": "标枪散兵",
		"effect_id": "javelin_skirmisher.effect.01",
		"trigger_name": "突击",
		"source_status": "resolved",
	}
	formula.final_flat_bonus_sources.append({
		"source_card_name": "盾墙列兵",
		"source_name": "护甲获得固定加成",
		"amount": 2.0,
	})
	var original_value := formula.calculate_result()
	var popup := BattleFormulaPresenter.format_popup(formula)
	_check(
		popup.contains("攻击类型（有护甲）")
		and popup.contains("减伤  20%")
		and popup.contains("盾墙列兵")
		and popup.contains("鼓手")
		and popup.contains("标枪散兵")
		and not popup.contains("普通 Array 内的承伤规则")
		and not popup.contains("护甲获得固定加成")
		and popup.contains("+3")
		and popup.contains("+2")
		and is_equal_approx(original_value, 24.5)
		and is_equal_approx(formula.exact_result, original_value)
		and is_equal_approx(formula.calculate_result(), original_value),
		"简洁弹窗保留关键数值来源、不展开内层诊断描述且结果仍为24.5"
	)
	var copy := formula.duplicate_for_target(defender)
	var copy_popup := BattleFormulaPresenter.format_popup(copy)
	_check(
		copy_popup.contains("盾墙列兵")
		and not copy_popup.contains("普通 Array 内的承伤规则")
		and is_equal_approx(copy.calculate_result(), original_value),
		"公式复制后的嵌套普通来源数组仍可安全展示"
	)
	controller.clear_battle()
	controller.free()


func _test_popup_placement_at_viewport_edges() -> void:
	var viewport_size := Vector2(160.0, 100.0)
	var popup_size := Vector2(120.0, 90.0)
	var corners: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(160.0, 0.0),
		Vector2(0.0, 100.0),
		viewport_size,
	]
	var all_inside := true
	for mouse: Vector2 in corners:
		var position := BattleFormulaPresenter.place_popup(mouse, viewport_size, popup_size, 4.0)
		all_inside = all_inside and position.x >= 0.0 and position.y >= 0.0
		all_inside = all_inside and position.x + popup_size.x <= viewport_size.x
		all_inside = all_inside and position.y + popup_size.y <= viewport_size.y
	var top_edge_position := BattleFormulaPresenter.place_popup(Vector2(80.0, 0.0), viewport_size, popup_size, 4.0)
	_check(
		all_inside and is_equal_approx(top_edge_position.y, 4.0),
		"160×100 低分辨率视口的四角均完整容纳弹窗，顶部改放鼠标下方"
	)


func _test_popup_font_measurement_at_low_resolution() -> void:
	var content := "实际生效 5 点远程攻击\n基础数值 2\n  · 标枪散兵 +2\n强化 +5\n  · 标枪散兵 · 火腿面包 +3\n牌型倍率 ×1.2\n元素符文倍率 ×1.4（主目标）\n最终精确结果 8.4"
	var wide := BattleFormulaPresenter.measure_popup_size(
		content, PopupFont, 12, 210.0, 340.0, 300.0, Vector2(18.0, 18.0)
	)
	var narrow := BattleFormulaPresenter.measure_popup_size(
		content,
		PopupFont,
		12,
		210.0,
		340.0,
		90.0,
		Vector2(18.0, 18.0),
		Vector2(140.0, 90.0)
	)
	_check(
		wide.x <= 340.0 and wide.x >= 210.0
		and narrow.x == 140.0 and narrow.y <= 90.0 and narrow.y > 40.0,
		"弹窗使用项目实际字体测量长中文行，在低分辨率视口缩窄并预留滚动高度"
	)


func _entry(card: CardData, row_key: StringName) -> Dictionary:
	return {
		"squad_data": SquadData.from_card(card),
		"row_key": row_key,
		"formation_index": 0,
	}


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
