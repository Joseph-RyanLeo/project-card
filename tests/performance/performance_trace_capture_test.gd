extends SceneTree

## 使用真实主场景、真实100ms阻塞与F10输入验证采样，不替换业务函数。
const MAIN = preload("res://scenes/Main.tscn")
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func run() -> void:
	var old_flag := OS.get_environment("PROJECT_CARD_TRACE_BATTLE_PERFORMANCE")
	OS.set_environment("PROJECT_CARD_TRACE_BATTLE_PERFORMANCE", "1")
	root.size = Vector2i(1280, 720)
	var main := MAIN.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var began := Time.get_ticks_usec()
	while Time.get_ticks_usec() - began < 100000:
		pass
	await process_frame
	await process_frame
	var samples: Array = main._battle_trace_frame_samples
	var largest_wall := 0.0
	for sample: Dictionary in samples:
		largest_wall = maxf(largest_wall, float(sample.wall_frame_ms))
	check(largest_wall >= 95.0, "真实100ms主线程阻塞被独立帧间隔捕获")
	check(not samples.is_empty() and samples.back().has("phase") and samples.back().has("shop_open") and samples.back().has("native_drag_active"), "逐帧记录阶段、商店与原生拖动状态")
	# 使用正式战斗推进验证阶段计时，存档限定在本次测试的临时路径。
	var save_path := "/private/tmp/project-card-transition-trace-%d.json" % Time.get_ticks_usec()
	main.run_save_path = save_path
	var definition := load("res://resources/cards/heavy_knight.tres") as CardData
	var owned: OwnedCard = main.owned_card_collection.create_card(definition)
	main.front_row.add_card(definition, 0, owned)
	main.enemy_front_row.clear_squads()
	main.enemy_back_row.clear_squads()
	main.enemy_front_row.add_card(definition, 0)
	check(main.start_battle(719, false) and main._battle_trace_start_usec > 0, "真实开始战斗记录独立构建耗时")
	main.battle_controller.advance_time(300.0)
	var deadline := Time.get_ticks_msec() + 10000
	while main.current_phase == main.GamePhase.BATTLE and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	var recorded_result := false
	for sample: Dictionary in main._battle_trace_frame_samples:
		recorded_result = recorded_result or float(sample.battle_result_ms) > 0
	check(main.current_phase == main.GamePhase.RESULT and recorded_result, "真实战斗结束与结算写入独立处理耗时")
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	# 避免覆盖相同秒内已经存在的日志；只删除本次F10创建的文件。
	var relative_path := ""
	while true:
		var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		relative_path = "user://logs/battle-performance-%s.json" % stamp
		if not FileAccess.file_exists(relative_path):
			break
		await create_timer(0.1).timeout
	var key := InputEventKey.new()
	key.keycode = KEY_F10
	key.pressed = true
	root.push_input(key, true)
	await process_frame
	var file := FileAccess.open(relative_path, FileAccess.READ)
	check(file != null, "真实F10输入导出JSON")
	if file != null:
		var payload: Dictionary = JSON.parse_string(file.get_as_text())
		file.close()
		check(int(payload.get("sampling_version", 0)) == 2 and (payload.get("summary", {}) as Dictionary).has("wall_frame_ms"), "导出文件声明新版采样并保存真实帧间隔统计")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(relative_path))
	OS.set_environment("PROJECT_CARD_TRACE_BATTLE_PERFORMANCE", old_flag)
	main.queue_free()
	await process_frame
	print("Performance trace capture failures: ", failures)
	quit(1 if failures else 0)
