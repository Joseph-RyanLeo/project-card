extends SceneTree

## 使用伙伴原始战前存档与日志中还原的真实弹道时序，覆盖固定帧率、倍速切换和暂停。
const DISPLAY := preload("res://scenes/GameDisplay.tscn")
const FIXTURE := "res://tests/fixtures/partner_freeze_20261013.json"
const SAVE_PATH := "/private/tmp/project-card-partner-freeze-replay.json"
const Profiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
var failures := 0
var assertions := 0
var shell: Control
var main: Control
func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("伙伴战斗重放超时"); quit(2))
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error(message)
func effect_signature(record: Dictionary) -> String:
	var events: Array = []
	for event: Dictionary in record.get("timeline", []):
		if event.record_type != "effect_event": continue
		events.append([
			roundi(float(event.logical_time_seconds) * 1000000.0),
			event.source.get("runtime_id", 0), event.target.get("runtime_id", 0),
			event.qualifier, event.amounts.event_exact_amount, event.amounts.effective_amount
		])
	return JSON.stringify(events).sha256_text()
func _run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = SAVE_PATH
	root.add_child(shell)
	await process_frame
	# 仅修改本测试进程的内存配置，不写user://攻击调整器文件。
	Profiles.get_profile(&"melee_attack") # 先完成正式配置入口的惰性初始化，随后覆盖本进程内存。
	for id: StringName in Profiles.PROFILE_IDS:
		Profiles._profiles[id] = Profiles.get_default_profile(id)
	for id: String in fixture.attack_timing_profiles:
		var timing: Dictionary = fixture.attack_timing_profiles[id]
		var profile := Profiles.get_default_profile(StringName(id))
		profile.duration = timing.duration
		profile.speed_variation_strength = timing.speed_variation_strength
		profile.trail_length = float(timing.trail_total) - float(profile.trail_softness)
		Profiles._profiles[StringName(id)] = profile
		for variant: int in 3:
			check(absf(BattleProjectileTiming.calculate_impact_delay(Profiles.get_profile(StringName(id)), variant) - float(timing.observed_impact_delays[variant])) < 0.00000001, "日志弹道时长等效还原：%s／%d" % [id, variant])
	var modes: Array[Dictionary] = [
		{"fps": 30.0, "speed": 3.0, "switch": true},
		{"fps": 60.0, "speed": 3.0, "switch": true},
		{"fps": 144.0, "speed": 3.0, "switch": true},
		{"fps": 60.0, "speed": 0.5},
		{"fps": 60.0, "speed": 1.0},
		{"fps": 60.0, "speed": 2.0},
		{"fps": 60.0, "speed": 3.0},
		{"fps": 60.0, "speed": 3.0, "pause": true},
	]
	var stress_modes := modes.duplicate(true)
	for mode: Dictionary in stress_modes: mode["stress"] = true
	modes.append_array(stress_modes)
	var expected_signatures: Dictionary = {}
	var expected_times: Dictionary = {}
	var battle: BattleController = main.battle_controller
	battle.use_projectile_timing = true
	for mode: Dictionary in modes:
		if mode.get("stress", false):
			for id: String in fixture.stress_timing_profiles:
				var timing: Dictionary = fixture.stress_timing_profiles[id]
				var profile := Profiles.get_profile(StringName(id))
				profile.duration = timing.duration
				profile.speed_variation_strength = timing.speed_variation_strength
				profile.trail_softness = maxf(float(profile.trail_softness), float(timing.trail_total) - 1.0)
				profile.trail_length = float(timing.trail_total) - float(profile.trail_softness)
				Profiles._profiles[StringName(id)] = profile
		check(RunSaveService.new().save_checkpoint(SAVE_PATH, fixture.checkpoint) == OK and main.load_run_from_path(SAVE_PATH), "原战前存档真实磁盘载入")
		check(main.maze_controller.run.day == 6 and main.start_battle(374911656, false), "第6天同阵容同种子开战")
		var frame := 0
		while battle.is_running() and frame < 10000:
			var speed: float = 0.5 if mode.get("switch", false) and frame < float(mode.fps) else float(mode.speed)
			if mode.get("pause", false) and frame == 90:
				main._on_battle_pause_button_pressed()
				var time_before := battle.elapsed_seconds
				var random_before := battle._random.state
				for paused_frame: int in 3: await process_frame
				check(is_equal_approx(battle.elapsed_seconds, time_before) and battle._random.state == random_before, "暂停不推进战斗、不改变随机状态")
				main._on_battle_pause_button_pressed()
			battle.advance_time(speed / float(mode.fps))
			frame += 1
		check(not battle.is_running() and frame < 10000 and battle.current_result == BattleController.Result.PLAYER_VICTORY, "伙伴卡死场次重放正常结束：%s" % mode)
		var signature := effect_signature(main._battle_diagnostic_recorder.get_record_copy())
		var profile_key := "stress" if mode.get("stress", false) else "recorded"
		if not expected_signatures.has(profile_key):
			expected_signatures[profile_key] = signature
			expected_times[profile_key] = battle.elapsed_seconds
		check(signature == expected_signatures[profile_key] and absf(battle.elapsed_seconds - float(expected_times[profile_key])) < 0.000001, "帧率／倍速／暂停不改变命中时刻、事件顺序及数值")
		print("重放 ",mode," 逻辑结束=",battle.elapsed_seconds," 帧数=",frame)
	# 新平衡改变选敌与触发顺序，不再要求复现旧版本的特定致命命中时刻。
	# 原故障的“0生命但alive仍为true”入口由battle_poison_lethal_scheduler_test直接覆盖。
	await process_frame
	shell.queue_free()
	await process_frame
	print("伙伴卡死重放：%d项，%d失败" % [assertions, failures])
	quit(failures)
