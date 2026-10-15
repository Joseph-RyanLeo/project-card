extends SceneTree

## 正式Main场景，28张随从、真实元素弹道、真实交换与诊断写盘。
const MAIN := preload("res://scenes/Main.tscn")
const PROFILE := preload("res://tests/performance/battle_load_profiled_main.gd")
const CONTROLLER_PROFILE := preload("res://tests/performance/battle_load_profiled_controller.gd")
const SAMPLE_FRAMES := 240 # 每种负载采集四秒逻辑时间，共240帧
var failures := 0
var outputs: Array[Dictionary] = []

func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): push_error("战斗负载测量超时"); quit(2))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for movement: bool in [false, true]:
		await _measure_load(movement)
	check(outputs.size() == 2, "两种负载均完成采样")
	var output_path := "/private/tmp/project-card-battle-load.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output_path = arg.trim_prefix("--output=")
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"环境": Engine.get_version_info(), "显示服务": DisplayServer.get_name(), "负载": outputs, "失败": failures}, "\t"))
	file.close()
	print("负载报告：", output_path, "，失败：", failures)
	quit(failures)

func _measure_load(movement: bool) -> void:
	var main := MAIN.instantiate()
	main.set_script(PROFILE)
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-load-%s-%d.json" % [str(movement), Time.get_ticks_usec()]
	root.add_child(main)
	await process_frame
	await process_frame
	main.battle_controller.set_script(CONTROLLER_PROFILE)
	main.battle_controller.use_projectile_timing = true
	var rows: Array[BattlefieldRow] = [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]
	for row: BattlefieldRow in rows: row.clear_squads()
	var instance_rng := RandomNumberGenerator.new()
	instance_rng.seed = 210100
	var ids := ["moon_dancer", "moon_singer", "twilight_guard", "starmoon_leopard", "darkmoon_archer", "moon_hawk", "shadowstep_assassin"]
	for row_index: int in rows.size():
		for index: int in 7:
			var definition: CardData = load("res://resources/cards/%s.tres" % ids[index]).duplicate()
			definition.cooldown_seconds = 0.5
			definition.max_health = 99
			definition.armor = 99
			definition.base_value = 1
			var owned: OwnedCard = main.owned_card_collection.create_card(definition, instance_rng) if row_index < 2 else OwnedCard.new()
			if row_index >= 2: owned.initialize(definition, StringName("load_npc:%d:%d" % [row_index, index]), index, instance_rng)
			owned.resolved_runes.assign([CardData.ElementType.DARK, CardData.ElementType.DARK, CardData.ElementType.DARK])
			owned.rune_revealed.fill(true)
			var squad := SquadData.from_owned_card(owned)
			if movement and "--handbells" in OS.get_cmdline_user_args() and index in [0, 1]:
				var bell: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/dancer_handbell.tres"), instance_rng) if row_index < 2 else OwnedCard.new()
				if row_index >= 2: bell.initialize(load("res://resources/cards/dancer_handbell.tres"), StringName("load_bell:%d:%d" % [row_index, index]), index, instance_rng)
				squad.equip_item(bell)
			rows[row_index].add_squad(squad, index)
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	check(main.start_battle(210101, false), "正式负载阵容开战")
	var battle: BattleController = main.battle_controller
	battle.set_process(false)
	var initial_signature: Array = []
	for state: BattleSquadState in battle.get_all_states():
		state.current_health = 10000.0
		initial_signature.append([state.runtime_id, state.row_key, state.get_effective_action_type(), state.remaining_cooldown, state.get_active_runes(), state.get_effect_source().content_effect])
	var initial_random := str(battle._random.state)

	for frame: int in 10:
		battle.advance_time(1.0 / 60.0)
		await process_frame
	main.load_profile.clear()
	battle.load_profile.clear()
	var samples: Array[float] = []
	var advances: Array[float] = []
	var peak_effects := 0
	var swaps := 0
	for frame: int in SAMPLE_FRAMES:
		var began := Time.get_ticks_usec()
		if movement and frame % 6 == 0:
			for index: int in 4:
				var side: Array[BattleSquadState] = battle.player_states if index % 2 == 0 else battle.enemy_states
				if battle.silvermoon.swap(side[(frame / 6 + index) % 7], side[7 + (frame / 6 + index * 2) % 7]): swaps += 1

		var advance_began := Time.get_ticks_usec()
		battle.advance_time(1.0 / 60.0)
		advances.append(float(Time.get_ticks_usec() - advance_began) / 1000.0)
		await process_frame
		samples.append(float(Time.get_ticks_usec() - began) / 1000.0)
		if movement and frame == 120 and DisplayServer.get_name() != "headless":
			for arg: String in OS.get_cmdline_user_args():
				if arg.begins_with("--snapshot="): root.get_texture().get_image().save_png(arg.trim_prefix("--snapshot="))
		peak_effects = maxi(peak_effects, main.battle_effect_layer.get_child_count())
	check(battle.current_result == BattleController.Result.NONE, "压力场次采样期间未提前结束")
	var record: Dictionary = main._battle_diagnostic_recorder.get_record_copy()
	var signature: Array = []
	for event: Dictionary in record.get("timeline", []):
		if event.record_type == "effect_event": signature.append([event.logical_time_seconds, event.source.get("runtime_id", 0), event.target.get("runtime_id", 0), event.qualifier, event.amounts.event_exact_amount, event.amounts.effective_amount])
	samples.sort()
	advances.sort()
	var result := {"带手铃": "--handbells" in OS.get_cmdline_user_args(), "场景": "弹道加换位" if movement else "弹道密集", "采样帧数": SAMPLE_FRAMES, "换位次数": swaps, "弹道次数": main.load_profile.get("弹道创建", {}).get("calls", 0), "效果节点峰值": peak_effects, "帧中位_ms": samples[samples.size() / 2], "帧p95_ms": samples[int(samples.size() * 0.95)], "帧最大_ms": samples.back(), "规则p95_ms": advances[int(advances.size() * 0.95)], "路径计时": main.load_profile.duplicate(true), "规则路径": battle.load_profile.duplicate(true), "规则指纹": JSON.stringify(signature).sha256_text(), "随机终态": str(battle._random.state)}
	print(JSON.stringify(result))
	result["起始随机"] = initial_random
	result["起始规则"] = initial_signature
	result["规则时间轴"] = signature
	outputs.append(result)
	battle.clear_battle()
	main.queue_free()
	await process_frame
	await process_frame
