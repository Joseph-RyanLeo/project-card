extends SceneTree

const AudioServiceScript = preload("res://scripts/battle/battle_audio_service.gd")
const BattleControllerScript = preload("res://scripts/battle/battle_controller.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	if value:
		print("PASS: " + message)
	else:
		failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var audio = main.battle_audio_service
	_check(audio.get_loaded_source_count() == 9, "九个音效源全部进入独立音效服务")
	_check(main.battle_volume_slider.min_value == 0.0 and main.battle_volume_slider.max_value == 100.0, "音量滑条范围为0至100")
	var master_bus := AudioServer.get_bus_index("Master")
	audio.set_master_volume_percent(0.0)
	_check(AudioServer.is_bus_mute(master_bus), "音量0会静音主总线")
	audio.set_master_volume_percent(50.0)
	_check(not AudioServer.is_bus_mute(master_bus) and is_equal_approx(AudioServer.get_bus_volume_db(master_bus), linear_to_db(0.5)), "非零百分比按线性音量映射到分贝")
	audio.set_master_volume_percent(100.0)
	_check(is_zero_approx(AudioServer.get_bus_volume_db(master_bus)), "音量100对应主总线0 dB")
	var battle_random_a := RandomNumberGenerator.new()
	var battle_random_b := RandomNumberGenerator.new()
	battle_random_a.seed = 9341
	battle_random_b.seed = 9341
	audio.play_action_launch(CardData.ActionType.MELEE)
	audio.play_action_hit(CardData.ActionType.MELEE)
	audio.play_action_launch(CardData.ActionType.RANGED)
	audio.play_action_hit(CardData.ActionType.RANGED)
	audio.play_action_launch(CardData.ActionType.MAGIC)
	audio.play_action_hit(CardData.ActionType.MAGIC)
	audio.play_action_launch(CardData.ActionType.DEFENSE)
	audio.play_action_launch(CardData.ActionType.HEAL)
	audio.play_action_hit(CardData.ActionType.DEFENSE)
	_check(audio.get_play_count("melee_launch") == 1 and audio.get_play_count("melee_hit") == 1, "近战发起与命中分别只触发对应音效池")
	_check(audio.get_play_count("ranged_launch") == 1 and audio.get_play_count("ranged_hit") == 1, "远程变体共享发起池且命中使用独立池")
	_check(audio.get_play_count("magic_launch") == 1 and audio.get_play_count("magic_hit") == 1, "法术攻击发起与命中使用独立音效池")
	_check(audio.get_play_count("armor_launch") == 1 and audio.get_play_count("armor_hit") == 0, "防御只播放已提供的发起音效，治疗保持静音")
	_check(battle_random_a.randi() == battle_random_b.randi(), "播放多类音效不会推进战斗随机数序列")
	var views: Array[SquadView] = []
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_back_row, main.enemy_front_row]:
		for slot: BoardSlot in row.get_squads():
			if slot.card_view != null:
				var parent: Node = slot
				while parent != null and not (parent is SquadView):
					parent = parent.get_parent()
				if parent is SquadView:
					views.append(parent as SquadView)
	if views.size() >= 2:
		views[1].set_battle_result_statistics_suppressed(true)
	main._set_inspection_source_statistics_suppressed(true)
	var all_hidden := true
	for view: SquadView in views:
		all_hidden = all_hidden and view.is_battle_result_statistics_suppressed()
	_check(all_hidden, "检视打开时隐藏我方与敌方所有结算统计层")
	main._set_inspection_source_statistics_suppressed(false)
	_check(not views[0].is_battle_result_statistics_suppressed() and views[1].is_battle_result_statistics_suppressed(), "检视关闭后恢复每个小队原有遮挡状态")
	views[1].set_battle_result_statistics_suppressed(false)
	main.queue_free()
	await process_frame
	print("D2-12 wound audio runtime failures: ", failures)
	quit(1 if failures else 0)
