extends SceneTree

## 正式控制器和主场景回归：疲劳边界、持续效果失效、采矿纹章与诊断体积。
const MAIN := preload("res://scenes/Main.tscn")
const Serializer := preload("res://scripts/battle/battle_diagnostic_serializer.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func owned(id: String, instance_id: String) -> OwnedCard:
	var result := OwnedCard.new()
	result.initialize(load("res://resources/cards/%s.tres" % id).duplicate(), StringName(instance_id), 0)
	result.rune_revealed.fill(false)
	return result

func controller(player: Array[String], enemy: Array[String]) -> BattleController:
	var battle := BattleController.new()
	root.add_child(battle)
	var player_formation: Array[Dictionary] = []
	var enemy_formation: Array[Dictionary] = []
	var formations: Array = [player_formation, enemy_formation]
	for side: int in 2:
		var ids: Array[String] = player if side == 0 else enemy
		for index: int in ids.size():
			var card := owned(ids[index], "fatigue_test:%d:%d" % [side, index])
			formations[side].append({"squad_data": SquadData.from_owned_card(card), "row_key": &"player_front" if side == 0 else &"enemy_front", "formation_index": index})
	battle.start_battle(formations[0], formations[1], 7041, false)
	return battle

func release(battle: BattleController) -> void:
	battle.clear_battle()
	battle.free()

func _run() -> void:
	_test_boundaries()
	_test_continuous_inputs()
	_test_npc_emblem()
	await _test_fatigue_frame_rates()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint="):
			await _test_partner_replay(arg.trim_prefix("--checkpoint="))
	print("疲劳性能回归：%d 项检查，%d 项失败" % [checks, failures])
	quit(failures)

func _test_boundaries() -> void:
	var battle := controller(["shieldwall_private"], ["shieldwall_private"])
	for tick: int in range(30, 37):
		battle.elapsed_seconds = float(tick) - 0.000000000001
		battle._next_fatigue_damage_seconds = float(tick)
		var events := battle._prepare_fatigue_events(battle.get_all_states())
		var expected := 1 + (tick - 30) / 2
		check(events.size() == 2 and events[0].exact_amount == expected and events[1].exact_amount == expected, "%d秒前浮点误差仍按计划时刻结算%d点" % [tick, expected])
		check(battle._next_fatigue_damage_seconds == tick + 1, "每轮只消耗一次风暴时刻")
	battle.player_states[0].moon_shadowed = true
	battle.elapsed_seconds = 37.0
	battle._next_fatigue_damage_seconds = 37.0
	check(battle._prepare_fatigue_events(battle.get_all_states()).size() == 1, "放逐单位仍免疫风暴")
	release(battle)

func _test_continuous_inputs() -> void:
	var battle := controller(["anvil_margaret", "shieldwall_private"], ["shieldwall_private"])
	var target := battle.player_states[1]
	var runtime := battle.effect_runtime
	runtime.recheck_continuous_conditions()
	runtime.process_due(0.0)
	runtime.recheck_continuous_conditions()
	runtime.process_due(0.0)
	check(target.get_zeal_layers() == -4, "铁砧对有甲友军的持续修正已生效")
	var trace_count := runtime.traces.size()
	for _index: int in 100:
		target.current_health -= 0.001
		check(runtime.recheck_continuous_conditions() == null, "未跨越条件边界的生命变化不重复排整场效果")
		runtime.process_due(0.0)
	check(runtime.traces.size() == trace_count, "重复复检不再制造追踪事件")
	target.current_armor = 0.0
	runtime.recheck_continuous_conditions()
	runtime.process_due(0.0)
	check(target.get_zeal_layers() == 0, "同刻破甲立即撤销有甲条件效果")
	target.current_armor = 2.0
	runtime.recheck_continuous_conditions()
	runtime.process_due(0.0)
	check(target.get_zeal_layers() == -4, "条件恢复立即重新安装且不重复叠加")
	battle.player_states[0].current_health = 0.0
	battle._finalize_batch()
	check(target.get_zeal_layers() == 0, "来源死亡立即清理持续效果")
	release(battle)

func _test_npc_emblem() -> void:
	var battle := controller(["shieldwall_private"], ["shieldwall_private"])
	var definitions: Array[Dictionary] = BattleController.EmblemLibraryData.get_definitions()
	var definition: Dictionary = {}
	for item: Dictionary in definitions:
		if String(item.id) == "盾牌Ⅰ": definition = item
	check(not definition.is_empty() and battle.attach_npc_emblem(definition, &"fatigue_test:npc_emblem"), "NPC纹章奖励使用现有可见槽接口完成安装")
	var slots := battle.enemy_states[0].squad_data.get_effect_source_instance().emblem_slots
	check(slots.any(func(slot: Dictionary): return slot.get("instance_id") == &"fatigue_test:npc_emblem"), "纹章确实写入敌方拥有卡的槽位")
	release(battle)

func _test_fatigue_frame_rates() -> void:
	for delta: float in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0]:
		var battle := controller(["shieldwall_private"], ["shieldwall_private"])
		for state: BattleSquadState in battle.get_all_states(): state.current_health = 99.0
		var ticks: Array[float] = []
		battle.effect_resolved.connect(func(event: BattleEffectEvent):
			if event.log_qualifier == "疲劳风暴" and event.target == battle.player_states[0]: ticks.append(event.exact_amount))
		while battle.elapsed_seconds < 36.01 and battle.is_running(): battle.advance_time(delta)
		check(ticks == [1.0, 1.0, 2.0, 2.0, 3.0, 3.0, 4.0], "不同帧率都得到1、1、2、2、3、3、4的疲劳序列")
		release(battle)
		await process_frame

func _test_partner_replay(path: String) -> void:
	var outcomes: Array = []
	for full_trace: bool in [false, true]:
		var main = MAIN.instantiate()
		main.short_maze_enabled = true
		main.run_save_path = "/private/tmp/project-card-fatigue-regression-%s.json" % full_trace
		root.add_child(main)
		await process_frame
		await process_frame
		check(main.load_run_from_path(path), "伙伴战前存档在独立文件中恢复")
		main.battle_controller.effect_runtime.full_trace_enabled = full_trace
		check(main.start_battle(463294128, false), "真实主场景重新开始伙伴战斗")
		var battle: BattleController = main.battle_controller
		var began := Time.get_ticks_usec()
		var samples: Array[float] = []
		for _index: int in 1500:
			if not battle.is_running(): break
			var fatigue := battle.elapsed_seconds >= 29.9
			var frame_began := Time.get_ticks_usec()
			battle.advance_time(1.0 / 30.0)
			await process_frame
			if fatigue: samples.append(float(Time.get_ticks_usec() - frame_began) / 1000.0)
		check(not battle.is_running() and battle.current_result == BattleController.Result.PLAYER_VICTORY, "疲劳战斗能结束且仍为胜利")
		for _index: int in 120: await process_frame
		check(main.current_phase == main.GamePhase.RESULT and main.battle_result_panel.visible and main._active_battle_departures == 0, "退场动画结束后正常进入结算")
		var record: Dictionary = main._battle_diagnostic_recorder.get_record_copy()
		var signature: Array = []
		for event: Dictionary in record.timeline:
			if event.record_type == "effect_event": signature.append([roundi(float(event.logical_time_seconds) * 1000000), event.source.get("runtime_id", 0), event.target.get("runtime_id", 0), event.qualifier, event.amounts.event_exact_amount, event.amounts.effective_amount])
		outcomes.append([battle.elapsed_seconds, battle._random.state, signature])
		var bytes := Serializer.to_json(Serializer.build_document(record)).to_utf8_buffer().size()
		if not full_trace:
			check(bytes < 8 * 1024 * 1024, "默认伙伴战斗JSON小于8MiB并保留完整行动公式")
		samples.sort()
		print("REPLAY full_trace=%s elapsed=%.3f events=%d traces=%d bytes=%d fatigue_p95_ms=%.3f fatigue_max_ms=%.3f wall_ms=%.3f" % [full_trace, battle.elapsed_seconds, int(record.capture_status.event_count), int(record.capture_status.effect_trace_count), bytes, samples[int(samples.size() * 0.95)], samples.back(), float(Time.get_ticks_usec() - began) / 1000.0])
		if not full_trace:
			check(record.capture_status.trace_detail == "changes_and_failures" and not record.capture_status.filtered_trace_counts.is_empty(), "精简追踪明确标注模式和过滤计数")
		main.queue_free()
		await process_frame
	check(outcomes[0] == outcomes[1], "精简和完整追踪的伤害顺序、时间、随机终态完全一致")
