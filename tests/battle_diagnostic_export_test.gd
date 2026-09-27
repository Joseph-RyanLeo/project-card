extends SceneTree

## 战斗诊断导出的端到端检查：使用真实 Main、卡牌资源与 BattleController。

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const BattleController = preload("res://scripts/battle/battle_controller.gd")
const BattleDiagnosticSerializer = preload("res://scripts/battle/battle_diagnostic_serializer.gd")

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.front_row.clear_squads()
	main.front_row.add_squad(SquadData.from_card(load("res://resources/cards/militia.tres")), 0)
	main.front_row.add_squad(SquadData.from_card(load("res://resources/cards/militia_commander.tres")), 1)
	await process_frame
	_expect(main.export_battle_data_button.disabled, "准备阶段禁用导出按钮")
	var player: Array[Dictionary] = main._build_battle_formation(main.front_row, &"player_front")
	var enemy: Array[Dictionary] = main._build_battle_formation(main.enemy_front_row, &"enemy_front")
	enemy.append_array(main._build_battle_formation(main.enemy_back_row, &"enemy_back"))
	var unobserved := BattleController.new()
	root.add_child(unobserved)
	unobserved.use_projectile_timing = false
	main.battle_controller.use_projectile_timing = false
	unobserved.start_battle(player, enemy, 71428, false)
	main.start_battle(71428, false)
	var iterations := 0
	while (unobserved.is_running() or main.battle_controller.is_running()) and iterations < 600:
		unobserved.advance_time(0.25)
		main.battle_controller.advance_time(0.25)
		iterations += 1
		await process_frame
	_expect(iterations < 600, "固定种子战斗在限定推进步数内结束")
	_expect(
		unobserved.current_result == main.battle_controller.current_result,
		"打开采集器不会改变固定种子的战斗胜负结果"
	)
	_expect(main._battle_diagnostic_recorder.is_complete, "战斗结束时采集记录完整冻结")
	_expect(not main.export_battle_data_button.disabled, "完整记录就绪后启用导出按钮")
	var first_record: Dictionary = main._battle_diagnostic_recorder.get_record_copy()
	var first_document := BattleDiagnosticSerializer.build_document(first_record)
	var second_document := BattleDiagnosticSerializer.build_document(
		main._battle_diagnostic_recorder.get_record_copy()
	)
	_expect(first_document.get("battle") == second_document.get("battle"), "同一场战斗重复构建导出文档时战斗数据稳定")
	var status: Dictionary = first_record.get("capture_status", {})
	var timeline: Array = first_record.get("timeline", [])
	_expect(
		int(status.get("event_count", 0)) > 0
		and int(status.get("effect_trace_count", 0)) > 0
		and timeline.size() >= int(status.get("event_count", 0))
		and not bool(status.get("truncated", true)),
		"无界诊断时间线保留实际事件、效果追踪且标记未截断"
	)
	_expect(
		timeline.size() > main.BATTLE_LOG_MAX_ENTRIES
		and main._battle_log_entries.size() <= main.BATTLE_LOG_MAX_ENTRIES,
		"诊断时间线条目超过 UI 日志上限时仍完整保留"
	)
	var formula_found := false
	for item: Dictionary in timeline:
		if item.get("record_type") != "effect_event":
			continue
		var formula: Dictionary = item.get("formula", {})
		if bool(formula.get("available", false)):
			formula_found = formula.has("action_value_modifier_sources") and formula.has("reinforcement_modifier_sources")
			if formula_found:
				break
	_expect(formula_found, "公式事件记录行动值与增援修正的来源字段")
	var export_path := "/private/tmp/project-card-battle-export-test.json"
	var second_export_path := "/private/tmp/project-card-battle-export-test-second.json"
	var save_result: Dictionary = BattleDiagnosticSerializer.save_to_path(first_record, export_path)
	_expect(bool(save_result.get("success", false)), "诊断 JSON 可写入文件系统")
	var second_save_result: Dictionary = BattleDiagnosticSerializer.save_to_path(
		main._battle_diagnostic_recorder.get_record_copy(),
		second_export_path
	)
	_expect(bool(second_save_result.get("success", false)), "同一战斗可再次导出到独立文件")
	if bool(save_result.get("success", false)):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(export_path))
		_expect(parsed is Dictionary, "导出文件可重新解析为 JSON 对象")
		if parsed is Dictionary:
			_expect(int(parsed.get("schema_version", -1)) == 1, "JSON 文档具有明确 schema_version")
			var parsed_battle: Dictionary = parsed.get("battle", {})
			var parsed_timeline: Array = parsed_battle.get("timeline", [])
			_expect(
				int(parsed_battle.get("battle_seed", -1)) == int(first_record.get("battle_seed", -2))
				and parsed_timeline.size() == timeline.size()
				and bool(parsed_battle.get("capture_status", {}).get("complete", false)),
				"JSON 往返保留种子、完整状态和全部时间线条目"
			)
		if bool(second_save_result.get("success", false)):
			var parsed_second: Variant = JSON.parse_string(FileAccess.get_file_as_string(second_export_path))
			_expect(
				parsed_second is Dictionary
				and JSON.stringify((parsed as Dictionary).get("battle", {}), "", true, true)
					== JSON.stringify((parsed_second as Dictionary).get("battle", {}), "", true, true),
				"同一场战斗分别写入两个文件时 battle 内容稳定一致"
			)
		main.export_battle_data_button.pressed.emit()
	_expect(main.battle_diagnostic_file_dialog.visible, "导出按钮打开系统保存文件对话框")
	if is_instance_valid(main.battle_diagnostic_file_dialog):
		main.battle_diagnostic_file_dialog.file_selected.emit(export_path)
		_expect(
			FileAccess.file_exists(export_path)
			and main.battle_export_status_label.text.begins_with("已保存"),
			"保存路径确认后通过界面回调完成导出并显示结果"
		)
	main.queue_free()
	unobserved.queue_free()
	await process_frame
	if _failures == 0:
		print("Battle diagnostic export checks passed.")
	else:
		push_error("Battle diagnostic export checks failed: %d" % _failures)
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)
