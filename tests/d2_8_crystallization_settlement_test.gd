extends SceneTree

## 真实两天迷宫与战斗结算：晶体化账本写回、继续按钮、存档及防重复。
const DISPLAY := preload("res://scenes/GameDisplay.tscn")
var shell: Control
var main: Control
var assertions := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func advance_to_battle(maze: ShortMazeController) -> void:
	check(maze.select_path(maze.run.paths[0].path_id), "选择随机事件")
	check(maze.complete_event(false), "随机事件正常推进")
	check(maze.select_path(maze.run.paths[0].path_id), "选择强化事件")
	check(maze.complete_event(false), "跳过强化正常推进")
	check(maze.select_path(maze.run.paths[0].path_id), "进入商店")
	check(maze.leave_shop(), "正常离开商店")
	check(maze.select_path(maze.run.paths[0].path_id), "选择战斗")

func fight() -> void:
	var batches := 0
	while main.battle_controller.current_result == BattleController.Result.NONE and batches < 1200:
		main.battle_controller.resolve_next_batch()
		batches += 1
	# 等正式阵亡演出和结果信号完成，不手工指定胜负或调用结算界面。
	await create_timer(1.2).timeout
	check(main.battle_controller.current_result == BattleController.Result.PLAYER_VICTORY, "实际战斗获胜")
	check(main.current_phase == main.GamePhase.RESULT, "正式战斗结果进入结算界面")

func _run() -> void:
	create_timer(40).timeout.connect(func(): push_error("晶体化战后结算专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = true
	main.run_save_path = "/private/tmp/project-card-crystallization-settlement-save.json"
	root.add_child(shell)
	shell.apply_display_mode(1 if "1080p" in OS.get_cmdline_user_args() else 0)
	await create_timer(0.3).timeout
	var maze: ShortMazeController = main.maze_controller
	maze.new_run(1707)
	check(maze.choose_talent("sentry_guard"), "首日选择天赋")
	var attacker: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	# 固定强度只保证获胜，成长账本与战后写回使用正式流程。
	attacker.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 100)
	attacker.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300)
	main.front_row.add_squad(SquadData.from_owned_card(attacker), 0)
	advance_to_battle(maze)
	check(main.start_battle(1, false), "第一天正式开战")
	await fight()
	check(bool(main._last_battle_settlement_result.get("success", false)) and maze.hero.experience == 2 and main.continue_next_level_button.visible, "第一天结算成功、经验2、继续按钮可见")
	check(maze.continue_after_battle() and maze.run.day == 2, "进入第二天")
	var defender: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/shieldwall_private.tres"))
	var defender_id := defender.instance_id
	check(defender.set_wound_slot(0, {"wound_id": &"晶体化", "instance_id": "regression_crystallization", "temporary": false}), "真实拥有随从具有晶体化伤势")
	main.back_row.add_squad(SquadData.from_owned_card(defender), 0)
	advance_to_battle(maze)
	check(main.start_battle(2, false), "第二天正式开战")
	var state: BattleSquadState
	for candidate: BattleSquadState in main.battle_controller.player_states:
		if candidate.squad_data.get_vitals_source_instance() == defender:
			state = candidate
	check(state != null and state.has_unmasked_wound(&"晶体化"), "真实战斗注册晶体化")
	if state == null: quit(1); return
	# 用实际伤害入口两次打空护甲，触发伤势效果及真实永久成长账本。
	state.apply_damage_exact(state.current_armor)
	state.apply_damage_exact(state.current_armor)
	var entries: Array[Dictionary] = main.battle_controller.permanent_growth_ledger.get_entries()
	check(entries.size() == 4 and defender.crystallization_health_loss == 0, "两次护甲归零仅记录两组生命-1、护甲+1，未提前写回拥有实例")
	var empty_entries: Array[Dictionary] = []
	for invalid_amount: float in [0.0, 1.0, -0.5, INF]:
		var invalid: Dictionary = entries[0].duplicate()
		invalid.amount = invalid_amount
		var invalid_entries: Array[Dictionary] = [invalid]
		var validation: Dictionary = main.battle_settlement_service._validate_entries(main._battle_snapshot.battle_instance_id, invalid_entries, empty_entries, empty_entries, main.owned_card_collection)
		check(not bool(validation.get("success", false)), "晶体化拒绝零、正数、非整数和非有限生命变化")
	await fight()
	var loss := 0
	var armor_growth := 0.0
	for entry: Dictionary in main.battle_controller.permanent_growth_ledger.get_entries():
		if entry.get("owned_card_instance_id") != defender_id: continue
		if entry.stat == BattlePermanentGrowthLedger.STAT_CRYSTALLIZATION_HEALTH_LOSS:
			loss -= roundi(entry.amount)
		elif entry.stat == BattlePermanentGrowthLedger.STAT_BASE_ARMOR:
			armor_growth += float(entry.amount)
	defender = main.owned_card_collection.get_by_instance_id(defender_id)
	check(bool(main._last_battle_settlement_result.get("success", false)) and maze.run.step == ShortMazeRunState.Step.BATTLE_RESULT, "晶体化实际战后写回成功并进入迷宫结算")
	check(defender.crystallization_health_loss == loss and defender.get_permanent_growth(OwnedCard.STAT_MAX_HEALTH) == 0.0 and defender.get_permanent_growth(OwnedCard.STAT_BASE_ARMOR) == armor_growth, "负生命变化转为正损失量，护甲成长完整写回，不混入普通生命成长")
	check(maze.hero.experience == 4 and main.continue_next_level_button.is_visible_in_tree() and not main.continue_next_level_button.disabled, "第二天经验累加到4，下一天按钮可见可用")
	check(not main.battle_result_summary_label.text.contains("待写回"), "结算摘要不再显示待写回")
	var gold: int = main.run_reward_state.gold
	check(bool(main.settle_current_battle().get("success", false)) and defender.crystallization_health_loss == loss and defender.get_permanent_growth(OwnedCard.STAT_BASE_ARMOR) == armor_growth and maze.hero.experience == 4 and main.run_reward_state.gold == gold, "重复结算不重复扣生命、增护甲或发奖励")
	check(main.load_run_from_path(main.run_save_path), "晶体化结算存档可以读回")
	defender = main.owned_card_collection.get_by_instance_id(defender_id)
	check(defender.crystallization_health_loss == loss and defender.get_permanent_growth(OwnedCard.STAT_BASE_ARMOR) == armor_growth and maze.hero.experience == 4 and main.continue_next_level_button.visible, "读档保留成长、经验和继续按钮")
	main._on_continue_next_level_pressed()
	check(maze.run.day == 3 and maze.run.step == ShortMazeRunState.Step.CHOOSING and main.current_phase == main.GamePhase.PREPARE, "正式继续入口进入第三天")
	shell.queue_free()
	await process_frame
	print("晶体化战后结算：%d项断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
