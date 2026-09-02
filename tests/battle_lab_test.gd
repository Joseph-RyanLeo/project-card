extends SceneTree

## 战斗实验室回归：验证配置不是另一套规则，而是能构造正式阵容并驱动 BattleController。

const LAB_SCENE: PackedScene = preload("res://scenes/tools/BattleLab.tscn")
const BattleLabScenario = preload("res://scripts/tools/battle_lab_scenario.gd")

var failures: int = 0
var test_root: Node


func _initialize() -> void:
	test_root = Node.new()
	get_root().add_child(test_root)
	_run.call_deferred()


func _run() -> void:
	_test_scenario_round_trip_and_formation()
	await _test_visual_lab_flow()
	if failures == 0:
		print("Battle lab checks passed.")
	else:
		push_error("Battle lab checks failed: %d" % failures)
	quit(failures)


func _test_scenario_round_trip_and_formation() -> void:
	var scenario: BattleLabScenario = BattleLabScenario.create_preset(&"light_water")
	_expect(scenario.validate().is_empty(), "内置实验预设可直接运行")
	var player_formation := scenario.build_player_formation()
	var enemy_formation := scenario.build_enemy_formation()
	var squad := player_formation[0]["squad_data"] as SquadData
	_expect(player_formation.size() == 1 and enemy_formation.size() == 3, "实验场景生成敌我正式 formation 输入")
	_expect(squad.get_visible_runes() == [CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.WATER, CardData.ElementType.WATER], "五个编辑槽生成完全相同顺序的合法可见符文堆叠")
	var restored: BattleLabScenario = BattleLabScenario.from_dictionary(scenario.to_dictionary())
	_expect(restored.to_dictionary() == scenario.to_dictionary(), "场景名称、阵容、种子与断言可以无损保存载入")


func _test_visual_lab_flow() -> void:
	var lab := LAB_SCENE.instantiate() as BattleLab
	test_root.add_child(lab)
	await process_frame
	_expect(lab.scenario != null and lab.battle_controller != null and lab._side_controls.size() == 2, "实验室建立双方编辑器与正式战斗控制器")
	var player_preview_row := lab.state_rows["player_back"] as HBoxContainer
	var enemy_preview_row := lab.state_rows["enemy_front"] as HBoxContainer
	var player_wrapper := player_preview_row.get_child(0) as Control
	var enemy_wrapper := enemy_preview_row.get_child(0) as Control
	_expect(player_preview_row.get_child_count() == 1 and enemy_preview_row.get_child_count() == 3, "未开始战斗时已经实时显示当前敌我配置卡堆")
	_expect(int(player_wrapper.get_meta("unscaled_squad_width")) == 159 and int(enemy_wrapper.get_meta("unscaled_squad_width")) == 99 and player_wrapper.custom_minimum_size.x > enemy_wrapper.custom_minimum_size.x, "单卡与展开双卡按正式99/159宽度比例显示")
	var preview_slot := player_wrapper.get_node("VirtualSquad") as BoardSlot
	_expect(preview_slot.get_squad_data().get_card_count() == 2 and preview_slot.get_primary_card_view().card_data.art_texture != null, "实时预览复用正式卡堆与卡面美术")
	var player_runes := (lab._side_controls["player"] as Dictionary)["runes"] as Array[OptionButton]
	player_runes[4].select(0)
	lab._on_editor_changed("player")
	player_wrapper = (lab.state_rows["player_back"] as HBoxContainer).get_child(0) as Control
	_expect(int(player_wrapper.get_meta("unscaled_squad_width")) == 129, "编辑第五枚符文后立即从展开双卡刷新为紧密双卡")
	player_runes[4].select(CardData.ElementType.WATER + 1)
	lab._on_editor_changed("player")
	lab._start_battle()
	lab._step_batch()
	_expect(lab.battle_controller.batch_count == 1 and not lab._log_entries.is_empty(), "单步批次推进正式分层结算并生成结构化日志")
	_expect(lab.trace_text.text.contains("[层0") and lab.trace_text.text.contains("[层1"), "分层轨迹显示基础层与元素层")
	var first_entry := lab._log_entries[0] as BattleLogEntry
	lab._on_log_meta_hover_started("formula:%d:0" % first_entry.group_id)
	_expect(lab.formula_popup.visible and lab.formula_popup_text.text.contains("牌型倍率"), "实验室日志整段结果可悬停查看公式")
	lab._on_log_meta_hover_ended("")
	lab._run_assertion()
	_expect(lab.report_text.text.contains("PASS"), "单场自动断言检查预期结果与状态边界")
	lab._run_combination_matrix()
	_expect(lab.report_text.text.contains("100 / 100 通过"), "批量矩阵覆盖五种行动、五种元素和二至五枚档位")
	lab.battle_controller.clear_battle()
	test_root.remove_child(lab)
	lab.free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
