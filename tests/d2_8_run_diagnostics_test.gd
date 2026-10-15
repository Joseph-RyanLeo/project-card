extends SceneTree

## 用伙伴存档副本与真实场景检查诊断持久化、堆叠差异、跨日和Esc入口。
const MAIN = preload("res://scenes/Main.tscn")
const RECORDER = preload("res://scripts/data/run_diagnostic_recorder.gd")
const SAVE := "/private/tmp/project-card-diagnostics-test-save.json"
const EXPORT := "/private/tmp/project-card-diagnostics-test-export.json"
const FIXTURE := "/private/tmp/project-card-partner-fixture.json"
var assertions := 0
var failures := 0
var main: Control


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)


func click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func open_export() -> void:
	main._on_escape_pause_menu_requested()
	await process_frame
	var button := main._escape_pause_menu.find_child("ExportRunDiagnosticsButton", true, false) as Button
	check(button != null and button.is_visible_in_tree(), "Esc菜单中存在可见的诊断导出入口")
	await click(button.get_global_rect().get_center())
	check(main._run_diagnostic_dialog != null and main._run_diagnostic_dialog.visible, "真实点击Esc菜单按钮打开保存对话框")
	main._run_diagnostic_dialog.hide()
	main._close_escape_pause_menu()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for path: String in [SAVE, SAVE + ".bak", SAVE + ".diagnostics.jsonl", SAVE + ".diagnostics.jsonl.previous", SAVE + ".diagnostics.jsonl.battle.json"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var original := FileAccess.get_file_as_bytes(FIXTURE)
	main = MAIN.instantiate()
	main.short_maze_enabled = true
	main.run_save_path = SAVE
	root.add_child(main)
	await process_frame
	await process_frame
	check(main.load_run_from_path(FIXTURE), "伙伴第7天存档副本成功加载")
	check(main.owned_card_collection.size() == 33, "加载全部33张实例")
	var infantry: OwnedCard = main.owned_card_collection.get_by_instance_id(&"run_card_000013")
	var priest: OwnedCard = main.owned_card_collection.get_by_instance_id(&"run_card_000003")
	check(infantry != null and priest != null and not main._is_owned_card_deployed(infantry), "伙伴步兵实例存在但未部署")
	await open_export()
	var slot: BoardSlot = main.back_row.get_squads()[3]
	var squad := SquadData.from_cards([priest.card_data, infantry.card_data], SquadData.TwoCardLayout.COMPACT)
	squad.bind_owned_card(priest.card_data, priest)
	check(main._transfer_drop_intent({"kind": &"card", "source_type": &"collection", "card_data": infantry.card_data, "owned_card": infantry, "drop_intent": {"operation": &"merge_card", "target_slot": slot, "result_squad": squad, "card_index": 1}}, main.back_row), "使用正式落点提交入口堆叠牧师和步兵")
	await process_frame
	await process_frame
	var events: Array = main._run_diagnostics.events
	var has_stack_change := false
	for event: Dictionary in events:
		var rows: Dictionary = event.changes.get("rows", {})
		if rows.has("after") and JSON.stringify(rows.after).contains("run_card_000013"):
			has_stack_change = true
	check(has_stack_change, "日志记录步兵进入堆叠的前后阵容")
	# 真实OwnedCard状态变化作为采集器的单位测试输入，不替代任何游戏服务。
	infantry.rune_revealed[0] = true
	main._refresh_owned_card_status_visuals(infantry)
	await process_frame
	check(main._run_diagnostics.events.back().changes.get("cards", {}).has("run_card_000013"), "符文状态变化按实例记录")
	var reloaded = RECORDER.new()
	reloaded.initialize(SAVE + ".diagnostics.jsonl")
	check(reloaded.events.size() == main._run_diagnostics.events.size(), "新采集器从磁盘保留近期记录")
	check(reloaded.events.back().changes.cards.run_card_000013.after.rune_revealed[0], "重启后仍保留符文变化")
	var maze: ShortMazeController = main.maze_controller
	while maze.run.round_index < 3:
		check(maze.select_path(maze.run.paths[0].path_id), "正常选择第7天事件")
		check(maze.complete_event(false), "事件流程正常推进")
	check(maze.select_path(maze.run.paths[0].path_id), "选择真实战斗")
	var attacker: OwnedCard = main.owned_card_collection.get_by_instance_id(&"run_card_000022")
	attacker.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 100)
	attacker.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300)
	main.front_row.add_squad(SquadData.from_owned_card(attacker), 0)
	check(main.start_battle(77, false), "真实战斗开场")
	await open_export()
	var batches := 0
	while main.battle_controller.current_result == BattleController.Result.NONE and batches < 1200:
		main.battle_controller.resolve_next_batch()
		batches += 1
	await create_timer(1.0).timeout
	check(main.battle_controller.current_result == BattleController.Result.PLAYER_VICTORY, "真实战斗获胜")
	check(main.current_phase == main.GamePhase.RESULT, "阵亡演出完成后实际结算")
	if not maze.hero.pending_talent_levels.is_empty(): check(maze.choose_talent("sentry_alchemy"), "升级天赋正常选择")
	check(maze.continue_after_battle() and maze.run.day == 8, "实际进入下一天")
	await process_frame
	await open_export()
	var state: Dictionary = main._capture_run_diagnostic_state()
	var save_bytes := FileAccess.get_file_as_bytes(SAVE)
	main._run_diagnostic_dialog.file_selected.emit(EXPORT)
	check(FileAccess.file_exists(EXPORT), "从文件对话框选择路径导出JSON")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPORT))
	check(document.kind == "project_card_run_diagnostics" and document.metadata.version == "0.2.83", "导出类型和版本明确")
	check(document.current_state.maze.run.day == 8 and document.saved_checkpoint.short_maze.run.day == 8, "跨日后包含当前状态和最近存档")
	check(document.last_completed_battle.battle != null and not document.last_completed_battle.battle.is_empty(), "准备阶段仍可导出上一场完整战斗")
	check(not document.engine_logs.is_empty(), "导出包含引擎日志")
	check(main._capture_run_diagnostic_state() == state and FileAccess.get_file_as_bytes(SAVE) == save_bytes, "导出不修改游戏状态或本局存档")
	check(FileAccess.get_file_as_bytes(FIXTURE) == original, "伙伴存档副本未被修改")
	main._save_run_diagnostic_file(SAVE)
	check(FileAccess.get_file_as_bytes(SAVE) == save_bytes, "拒绝诊断文件覆盖本局存档")
	check(not infantry.rune_revealed.is_empty() and infantry.rune_revealed[0], "战后和跨日保留步兵揭晓状态")
	check(main._is_owned_card_deployed(infantry), "牧师与步兵的堆叠在真实战后和跨日仍保留")
	var measure_start := Time.get_ticks_usec()
	for _i: int in 100: main._capture_run_diagnostic_state()
	print("诊断状态采集平均微秒：", (Time.get_ticks_usec() - measure_start) / 100)
	var restored = RECORDER.new()
	restored.initialize(SAVE + ".diagnostics.jsonl")
	check(restored.build_document({}, SAVE).last_completed_battle.battle != null, "重启后上一场战斗仍能读回")
	var unit_path := "/private/tmp/project-card-diagnostics-recorder-unit.jsonl"
	for path: String in [unit_path, unit_path + ".previous"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var unit = RECORDER.new()
	unit.initialize(unit_path)
	for i: int in range(605): unit.observe("unit", {"cards": {}, "value": i})
	check(unit.events.size() == 600 and unit.events.front().changes.value.after == 5, "内存近期事件上限600条")
	unit.observe("loss_before", {"cards": {"step": {"rune_revealed": [true]}}, "rows": {"back": ["priest", "step"]}})
	unit.observe("loss_after", {"cards": {"step": {"rune_revealed": [false]}}, "rows": {"back": ["priest"]}})
	check(unit.events.back().changes.rows.before.back == ["priest", "step"] and unit.events.back().changes.rows.after.back == ["priest"], "丢失堆叠时保留前后成员证据")
	check(unit.events.back().changes.cards.step.before.rune_revealed == [true] and unit.events.back().changes.cards.step.after.rune_revealed == [false], "符文回退时保留前后状态证据")
	var file := FileAccess.open(unit_path, FileAccess.WRITE)
	file.store_buffer(" ".repeat(4 * 1024 * 1024).to_utf8_buffer())
	file.close()
	unit.observe("rotation", {"cards": {}, "value": 606})
	check(FileAccess.file_exists(unit_path + ".previous") and FileAccess.get_file_as_string(unit_path).contains("rotation"), "自动日志达到容量上限时轮转")
	main.queue_free()
	await process_frame
	await process_frame
	print("近期诊断日志专项：", assertions, "项断言，失败", failures)
	quit(1 if failures else 0)
