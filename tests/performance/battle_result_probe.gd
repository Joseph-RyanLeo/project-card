extends SceneTree

## 真实结算入口分段测量，固定收藏、阵容和资源板，不跳过保存或显示。
const MAIN := preload("res://scenes/Main.tscn")
const PROFILE := preload("res://tests/performance/battle_result_profiled_main.gd")
var failures := 0
var outputs: Array[Dictionary] = []

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("结算测量超时"); quit(2))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for count: int in [3, 7]:
		for repeat: int in 3:
			await _measure_result(count, repeat)
	var path := "/private/tmp/project-card-battle-result.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): path = arg.trim_prefix("--output=")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"显示服务": DisplayServer.get_name(), "结果": outputs, "失败": failures}, "\t"))
	file.close()
	print("结算报告：", path, "，失败：", failures)
	quit(failures)

func _measure_result(count: int, repeat: int) -> void:
	var main := MAIN.instantiate()
	main.set_script(PROFILE)
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-result-probe-save.json"
	root.add_child(main)
	await process_frame
	await process_frame
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]: row.clear_squads()
	for owned: OwnedCard in main.owned_card_collection.get_cards(): main.owned_card_collection.remove_by_instance_id(owned.instance_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 251025
	for index: int in 72:
		main.owned_card_collection.create_card(load("res://resources/cards/militia.tres"), rng)
	var expected_rows: Array = []
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]:
		var expected: Array[StringName] = []
		for index: int in count:
			var owned: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/moon_dancer.tres"), rng)
			row.add_squad(SquadData.from_owned_card(owned), index)
			expected.append(owned.instance_id)
		expected_rows.append(expected)
	main.start_new_resource_level(&"result_probe", rng)
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	check(main.start_battle(251025, false), "固定阵容开战")
	var battle: BattleController = main.battle_controller
	battle.set_process(false)
	for frame: int in 80: battle.advance_time(1.0 / 60.0)
	check(battle.current_result == BattleController.Result.NONE, "分段测量前战斗仍进行")
	check(battle.silvermoon.swap(battle.player_states[0], battle.player_states[count]), "结算前真实跨排交换")
	battle.player_states[0].record_damage_dealt(CardData.ActionType.MELEE, 17.0)
	battle.current_result = BattleController.Result.PLAYER_VICTORY
	await process_frame
	await process_frame
	main.result_profile.clear()
	var began := Time.get_ticks_usec()
	main._show_battle_result(BattleController.Result.PLAYER_VICTORY)
	var cpu_ms := (Time.get_ticks_usec() - began) / 1000.0
	await process_frame
	var frame_ms := (Time.get_ticks_usec() - began) / 1000.0
	check(main._last_battle_settlement_result.get("status") == BattleSettlementService.STATUS_COMMITTED, "正式结算提交")
	var rows: Array = [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]
	for row_index: int in rows.size():
		var actual: Array[StringName] = []
		for slot: BoardSlot in rows[row_index].get_squads(): actual.append(slot.get_squad_data().get_effect_source_instance().instance_id)
		check(actual == expected_rows[row_index], "恢复战前阵容与实例身份")
	check(main.front_row.get_squads()[0].get_battle_result_statistics().damage_dealt >= 17.0, "交换后统计仍映射本人")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(main.run_save_path))
	outputs.append({"每排小队": count, "重复": repeat, "同步CPU_ms": cpu_ms, "结算所在帧_ms": frame_ms, "分段": main.result_profile.duplicate(true), "持久状态": saved})
	battle.clear_battle()
	main.queue_free()
	await process_frame
	await process_frame
