extends SceneTree
const MAIN = preload("res://scenes/Main.tscn")
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

func _select() -> void:
	var maze: ShortMazeController = main.maze_controller
	_expect(maze.select_path(maze.run.paths[0].path_id), "选择路径")

func _prepare_day() -> void:
	var maze: ShortMazeController = main.maze_controller
	_select()
	main._toggle_ordinary_shop()
	_select()
	maze.complete_event(true)
	_select()
	maze.complete_event(false)
	_select()

func _finish_battle() -> void:
	var count := 0
	while main.battle_controller.current_result == main.BattleController.Result.NONE and count < 2000:
		main.battle_controller.resolve_next_batch()
		count += 1
	_expect(main.battle_controller.current_result == main.BattleController.Result.PLAYER_VICTORY, "真实战斗胜利")
	main._show_battle_result(main.battle_controller.current_result)

func _run() -> void:
	main = MAIN.instantiate()
	main.short_maze_enabled = true
	main.run_save_path = "/private/tmp/project-card-maze-hero-rewards.json"
	root.add_child(main)
	await process_frame
	var maze: ShortMazeController = main.maze_controller
	maze.new_run(80084)
	maze.choose_talent("sentry_spell")
	var strong: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	strong.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 100.0)
	strong.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300.0)
	main.front_row.add_squad(SquadData.from_owned_card(strong), 0)
	for day: int in range(1, 7):
		_prepare_day()
		if not maze.stock.is_empty():
			maze.deploy_sentry(String(maze.stock[0].instance_id), "front")
		_zero_resource_board()
		var count_before: int = main.owned_card_collection.size()
		_expect(main.start_battle(1, false), "咒实际开战")
		var spells: Array[String] = main.battle_controller.hero_runtime.spell_awards.duplicate()
		_expect(spells.size() == 1 and main.owned_card_collection.size() == count_before, "咒先记战斗奖励，不提前入收藏")
		_finish_battle()
		_expect(main.owned_card_collection.size() == count_before + spells.size(), "咒正常战后真实发卡")
		for id: String in spells:
			var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/%s.tres" % id))
			_expect(owned != null and owned.spell_durability == int(owned.card_data.rarity) + 1, "咒法术按品级初始化耐久")
		var after: int = main.owned_card_collection.size()
		main.settle_current_battle()
		_expect(main.owned_card_collection.size() == after, "咒重复结算不重复发卡")
		if day == 6:
			_expect(maze.choose_talent("sentry_fortify"), "真实六胜到4级选择坚固")
		maze.continue_after_battle()
		await process_frame
	_prepare_day()
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	# 七个独立防御随从是受测输入；生命永久成长用于确保可完成真实战斗。
	for index: int in 7:
		var owned: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/shieldwall_private.tres"), maze.run.rng)
		owned.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300.0)
		main.front_row.add_squad(SquadData.from_owned_card(owned), index)
	_expect(main.start_battle(1, false) and main.battle_controller.hero_runtime.fortify_eligible, "七个独立前排防御符合任务")
	_finish_battle()
	_expect(maze.fortify_complete, "赢得真实战斗后提交坚固任务")
	_expect(main.save_run_to_path(main.run_save_path) == OK and main.load_run_from_path(main.run_save_path), "坚固任务实盘恢复")
	_expect(maze.fortify_complete and maze.hero.has_talent("sentry_fortify"), "任务完成不丢失")
	_expect(maze.continue_after_battle(), "任务完成后可继续第八天")
	_expect(maze.deploy_sentry(String(maze.stock[0].instance_id), "front") and int(maze.deployed[0].capacity) == 19, "坚固完成后4级新部署容量5+4+10")
	main.queue_free()
	await process_frame
	print("D2-8 天赋发奖与任务：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)


func _zero_resource_board() -> void:
	# 通过真实资源生成器寻找0／0资源的合法输入；不开采就不会混入其他发卡奖励。
	for seed_value: int in range(1, 1000):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var board := ResourceBoardState.new()
		board.initialize_level(main.resource_board_state.level_id, rng)
		var result: Dictionary = board.generate_level_resources(main._get_resource_definitions(), rng)
		if bool(result.get("success", false)) and board.get_level_resource_cards("player").is_empty() and board.get_level_resource_cards("enemy").is_empty():
			main.resource_board_state = board
			main._refresh_resource_preparation_trays()
			return
	_expect(false, "找到真实零资源战场输入")
