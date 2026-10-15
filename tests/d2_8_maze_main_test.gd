extends SceneTree

const MAIN = preload("res://scenes/Main.tscn")
const Run = preload("res://scripts/data/short_maze_run_state.gd")
var assertions := 0
var failures := 0
var main: Control

func _initialize() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func _make_main(seed_value: int, path: String) -> Control:
	var instance: Control = MAIN.instantiate()
	instance.short_maze_enabled = true
	instance.run_save_path = path
	root.add_child(instance)
	instance.maze_controller.run.initialize(seed_value)
	return instance

func _select(id: String = "") -> bool:
	var maze: ShortMazeController = main.maze_controller
	for path: Dictionary in maze.run.paths:
		if id.is_empty() or path.path_id == id:
			return maze.select_path(path.path_id)
	return false

func _finish_events() -> void:
	var maze: ShortMazeController = main.maze_controller
	var before_shop: int = main.owned_card_collection.size()
	_expect(_select(), "选商人")
	var gift_count := 5 if maze.run.day == 2 else (8 if maze.run.day == 3 else 0)
	_expect(main.owned_card_collection.size() == before_shop + gift_count, "固定礼包购物前一次性入收藏")
	if gift_count > 0:
		var large_cards: Array[OwnedCard] = main.owned_card_collection.get_cards().slice(before_shop, before_shop + 5)
		var has_guarantee := false
		for card: OwnedCard in large_cards:
			if card.card_data.rarity >= CardData.Rarity.II: has_guarantee = true
		_expect(has_guarantee, "赠送大包仍保底II级以上")
	_expect(main.ordinary_shop_open, "商店真实打开")
	main._toggle_ordinary_shop()
	_expect(maze.run.round_index == 1, "离店进入免费轮")
	_expect(_select(), "选择免费事件")
	_expect(maze.complete_event(true), "免费事件发奖并保存")
	_expect(_select(), "选择付费事件")
	_expect(maze.complete_event(false), "付费事件可无成本放弃")
	_expect(_select(), "日末选择敌人")
	_expect(maze.can_start_battle(), "只有已选战斗可开战")

func _run() -> void:
	main = _make_main(1707, "/private/tmp/project-card-maze-e2e.json")
	await process_frame
	var maze: ShortMazeController = main.maze_controller
	_expect(main.owned_card_collection.size() == 5 and main.run_reward_state.gold == 0, "五卡零金币开局")
	_expect(main.celestial_indicators.items.is_empty(), "正式英雄不带开发场景日月星等库存")
	_expect(not main.start_battle(1, false), "初始天赋未选禁止战斗")
	_expect(maze.choose_talent("sentry_guard"), "一级天赋选择与存档")
	_expect(maze.stock.size() == 1 and maze.run.paths.size() == 3, "首日哨位仅产出一次")
	var first_snapshot := maze.capture_state()
	_expect(maze.validate_state(JSON.parse_string(JSON.stringify(first_snapshot))), "初始JSON存档有效")
	var rng_state := maze.run.rng.state
	maze.refresh()
	maze.refresh()
	_expect(maze.run.rng.state == rng_state and maze.stock.size() == 1, "刷新不重抽路径或哨位")
	var saved_path: String = main.run_save_path
	main.run_save_path = "/private/tmp/nonexistent-project-card-folder/failed.json"
	var old_paths: Array = maze.run.paths.duplicate(true)
	_expect(not _select(), "保存失败拒绝路径事务")
	_expect(maze.run.paths == old_paths and maze.run.step == Run.Step.CHOOSING, "失败还原路径与随机状态")
	main.run_save_path = saved_path
	# 使用真实OwnedCard永久成长构造战斗单元测试输入，不伪造Controller胜负。
	var strong: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	strong.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 100.0)
	strong.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300.0)
	main.front_row.add_squad(SquadData.from_owned_card(strong), 0)
	for day: int in range(1, 9):
		var before_count: int = main.owned_card_collection.size()
		_finish_events()
		var expected_packs := 5 if day == 2 else (8 if day == 3 else 0)
		_expect(main.owned_card_collection.size() >= before_count + expected_packs, "第%d天礼包数量" % day)
		if day == 2:
			var cards_after: int = main.owned_card_collection.size()
			_expect(main.save_run_to_path(saved_path) == OK and main.load_run_from_path(saved_path), "第二天实盘读档")
			_expect(main.owned_card_collection.size() == cards_after, "礼包读档不重发")
		if not maze.stock.is_empty():
			_expect(maze.deploy_sentry(String(maze.stock[0].instance_id), "front"), "哨位部署")
		var before_opening_gold: int = main.run_reward_state.gold
		var deployed_count: int = maze.deployed.size()
		_expect(main.start_battle(999, false), "第%d天真实开战" % day)
		if day == 7:
			_expect(main.run_reward_state.gold == before_opening_gold + deployed_count * 5, "点金仅开战按投入数发金币")
			_expect(main.restart_battle() and main.run_reward_state.gold == before_opening_gold, "点金收入中断回退")
			_expect(main.start_battle(7, false) and main.run_reward_state.gold == before_opening_gold + deployed_count * 5, "重试不积累点金")
			_expect(main.save_run_to_path(saved_path) == OK and main.load_run_from_path(saved_path), "点金战中实际磁盘保存／恢复")
			_expect(main.run_reward_state.gold == before_opening_gold and maze.deployed.size() == deployed_count, "读档点金与哨位均还原")
			_expect(main.start_battle(7, false) and main.run_reward_state.gold == before_opening_gold + deployed_count * 5, "读档再开战只加一份点金")
		var battle_seed: int = main.battle_controller.battle_seed
		_expect(battle_seed == int(maze.run.selected_path.battle_seed), "选择时种子锁定")
		if day == 1:
			_expect(main.save_run_to_path(saved_path) == OK, "战斗中保存")
			_expect(main.load_run_from_path(saved_path), "战斗中读档")
			_expect(maze.run.step == Run.Step.BATTLE_PREPARE and maze.deployed.size() == 1, "中断恢复哨位和战前步骤")
			_expect(main.start_battle(88, false) and main.battle_controller.battle_seed == battle_seed, "中断不换敌人／种子")
		var count := 0
		while main.battle_controller.current_result == main.BattleController.Result.NONE and count < 1200:
			main.battle_controller.resolve_next_batch()
			count += 1
		_expect(main.battle_controller.current_result == main.BattleController.Result.PLAYER_VICTORY, "第%d天真实战斗获胜" % day)
		# 演出不改变结算规则；主动推进真实已完成战斗的结算页面。
		main._show_battle_result(main.battle_controller.current_result)
		_expect(maze.run.step == Run.Step.BATTLE_RESULT and maze.deployed.is_empty(), "战后步骤与参战哨位消费")
		var gold: int = main.run_reward_state.gold
		var experience: int = maze.hero.experience
		_expect(main.settle_current_battle().get("success", false), "重复结算可读取既有结果")
		_expect(main.run_reward_state.gold == gold and maze.hero.experience == experience, "重复结算不发金币经验")
		if day == 6:
			_expect(maze.hero.level == 4 and not maze.continue_after_battle(), "四级待选先于跨日")
			_expect(maze.choose_talent("sentry_alchemy"), "四级点金与立即哨位")
		if day == 1:
			main.run_save_path = "/private/tmp/nonexistent-project-card-folder/failed.json"
			_expect(not maze.continue_after_battle() and maze.run.step == Run.Step.BATTLE_RESULT, "跨日保存失败退回战后")
			main.run_save_path = saved_path
		_expect(maze.continue_after_battle(), "第%d天战后继续" % day)
		await process_frame
	_expect(maze.run.step == Run.Step.ENDED and maze.hero.experience == 16, "八胜通关，总经验16")
	_expect(not main.start_battle(1, false), "结束后不允许第九战")
	_expect(main.load_run_from_path(saved_path) and maze.run.step == Run.Step.ENDED, "结束页实盘恢复")
	maze._restart_run()
	_expect(maze.run.day == 1 and maze.hero.level == 1 and maze.hero.pending_talent_levels == [1] and main.owned_card_collection.size() == 5 and main.run_reward_state.gold == 0, "新一局重置英雄、五卡与金币")
	_expect(main.settlement_journal.capture_state().is_empty() and maze.stock.is_empty() and maze.deployed.is_empty(), "新一局清理旧结算与指示物")
	_expect(main.load_run_from_path(saved_path) and maze.run.step == Run.Step.DAY_START, "新一局也有可恢复存档")
	main.queue_free()
	await process_frame
	# 不部署随从，真实战斗会判负：验证前两次继续，第三次结束。
	main = _make_main(3009, "/private/tmp/project-card-maze-loss-e2e.json")
	await process_frame
	maze = main.maze_controller
	maze.choose_talent("sentry_break")
	for day: int in range(1, 4):
		_finish_events()
		_expect(main.start_battle(1, false), "空阵实际战斗启动")
		_expect(main.battle_controller.current_result == main.BattleController.Result.PLAYER_DEFEAT, "空阵实际判负")
		main._show_battle_result(main.battle_controller.current_result)
		_expect(maze.hero.experience == day and int(maze.last_reward.gold) in range(1, 7) and maze.last_reward.drop.is_empty(), "失败经验与金币／无掉落")
		_expect(maze.continue_after_battle(), "普通失败继续入口")
	_expect(maze.run.step == Run.Step.ENDED and maze.run.battle_results.back().ending == "ordinary_loss", "第三败结束")
	main.queue_free()
	await process_frame
	print("D2-8 Main迷宫：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
