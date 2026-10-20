extends SceneTree

## 使用正式显示壳、真实输入、磁盘存档和奖励服务验证事件牌。
const DISPLAY = preload("res://scenes/GameDisplay.tscn")
const StoryService = preload("res://scripts/data/maze_story_event_service.gd")
const SAVE_PATH := "/private/tmp/project-card-event-cards-test.json"
var shell: Control
var main: Control
var maze: ShortMazeController
var assertions: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)


func _deal(id: String, gold: int = 30) -> int:
	for seed_value: int in range(1, 100):
		maze.new_run(seed_value)
		main.run_reward_state.gold = gold
		maze.choose_talent("sentry_guard")
		for index: int in maze.run.paths.size():
			if maze.run.paths[index].path_id == id:
				return index
	check(false, "在实际随机事件池中能抽到" + id)
	return -1


func _click(control: Control) -> void:
	var point: Vector2 = shell.render_container.get_global_transform_with_canvas() * control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame


func _capture(name_value: String) -> void:
	if "--capture-events" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var viewport: SubViewport = shell.get_node("RenderContainer/InternalViewport")
		viewport.get_texture().get_image().save_png("/private/tmp/project-card-event-" + name_value + ".png")


func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = SAVE_PATH
	root.add_child(shell)
	await process_frame
	maze = main.maze_controller
	var service := StoryService.new()
	check(service.load_config(), "飞书事件配置可加载")
	var prayer: Dictionary = service.config.events[0]
	var casino: Dictionary = service.config.events[1]
	check(service.can_appear(prayer, 0, 1, "ioann_warden"), "测试开关允许第一层伊奥恩抽祈愿")
	check(not service.can_appear(casino, 4, 1, "ioann_warden") and service.can_appear(casino, 5, 1, "ioann_warden"), "赌坊仍要求至少5金币")
	service.config.test_ignore_appearance_limits = false
	check(not service.can_appear(prayer, 0, 1, "ioann_warden") and service.can_appear(prayer, 0, 3, "other_hero"), "关闭测试开关恢复原始条件")
	var chosen_index := _deal("ioann_prayer")
	await create_timer(0.6).timeout
	check(chosen_index >= 0 and maze._event_table.cards.size() == 3, "实际牌桌发出三张候选")
	for card: EventCardView in maze._event_table.cards:
		check(not card.face_up and card.tooltip_text.is_empty(), "选中前不泄漏名称和事件详情")
	var paths := maze.run.paths.duplicate(true)
	var rng_state := maze.run.rng.state
	maze.refresh()
	maze.refresh()
	check(maze.run.paths == paths and maze.run.rng.state == rng_state, "刷新不重抽候选或消耗随机源")
	await process_frame
	await _capture("backs")
	var card: Button = maze._event_table.cards[chosen_index]
	await _click(card)
	await _click(card)
	await create_timer(0.75).timeout
	check(maze.run.selected_path.get("path_id") == "ioann_prayer" and maze.run.step == ShortMazeRunState.Step.EVENT, "真实点击翻牌、移位、确认事件")
	if maze.run.selected_path.is_empty():
		shell.queue_free()
		await process_frame
		quit(1)
		return
	var selected: EventCardView = maze._event_table.get_node("SelectedEventCard")
	check(selected.face_up and selected.position.x < maze._event_table.get_node("EventDescription").position.x, "正面牌在左，描述和操作在右")
	await _capture("prayer")
	check(maze.choose_story_option(0), "祈愿领取太阳")
	check(main.celestial_indicators.items.size() == 1 and main.celestial_indicators.items[0].kind == CelestialIndicator.Kind.SUN, "真实指示物进入共用库存")
	var reward_rng := maze.run.rng.state
	check(not maze.choose_story_option(0) and main.celestial_indicators.items.size() == 1, "重复选择不能重复领指示物")
	check(main.load_run_from_path(SAVE_PATH), "实际磁盘恢复事件结果")
	check(maze.run.selected_path.has("story_result") and maze.run.rng.state == reward_rng and main.celestial_indicators.items.size() == 1, "读档保留结果、随机流和指示物")
	check(maze.complete_event() and maze.run.get_round_kind() == "paid_event", "领取后继续到强化轮")
	check(maze.select_path(maze.run.paths[0].path_id), "强化轮仍使用三选一")
	check(is_instance_valid(maze._enhancement_slot), "右侧保留原有强化卡槽")
	var trainee: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	var trainee_id := trainee.instance_id
	check(maze.select_enhancement_card({"kind": &"card", "owned_card": trainee}), "右侧强化卡槽接收真实收藏卡")
	await process_frame
	await _capture("enhancement")
	var option: Dictionary = maze.run.selected_path.options[0]
	check(maze.apply_card_enhancement(0), "右侧强化选项提交永久成长")
	trainee = main.owned_card_collection.get_by_instance_id(trainee_id)
	for stat: String in ["base_value", "base_armor", "max_health"]:
		if option.has(stat):
			check(trainee.get_permanent_growth(StringName(stat)) == float(option[stat]), "强化永久写入原有单卡实例")
	check(maze.select_path(maze.run.paths[0].path_id) and not main.ordinary_shop_open, "商店牌先显示正面和右侧入口")
	maze.enter_selected_shop()
	check(main.ordinary_shop_open, "商店选项打开真实商店")
	main._toggle_ordinary_shop()
	check(maze.run.get_round_kind() == "battle" and maze.run.paths.size() == 3, "离店后发三张战斗牌")
	check(maze.select_path(maze.run.paths[0].path_id) and maze.can_start_battle(), "战斗牌选定后进入准备")
	await process_frame
	var before := maze.capture_state()
	check(maze.validate_state(JSON.parse_string(JSON.stringify(before))), "战斗准备快照仍有效")
	_deal("strange_casino")
	check(maze.select_path("strange_casino"), "赌坊已加入真实事件池")
	check(not maze.choose_story_option(2) and not maze.choose_story_option(3) and not maze.choose_story_option(4), "未实现选项拒绝执行")
	main.run_reward_state.gold = 2
	check(not maze.choose_story_option(0) and main.run_reward_state.gold == 2, "金币不足拒绝下注且不扣费")
	main.run_reward_state.gold = 30
	var previous_rng := maze.run.rng.state
	main.run_save_path = "/private/tmp/project-card-missing-directory/events.json"
	check(not maze.choose_story_option(1), "保存失败时下注整体回退")
	check(main.run_reward_state.gold == 30 and maze.run.rng.state == previous_rng and not maze.run.selected_path.has("story_result"), "回退金币、骰子随机源和领取标记")
	main.run_save_path = SAVE_PATH
	check(maze.choose_story_option(1), "普通骰子可执行")
	if not maze.run.selected_path.has("story_result"):
		shell.queue_free()
		await process_frame
		quit(1)
		return
	var result: Dictionary = maze.run.selected_path.story_result
	check(int(result.roll) in range(1, 7) and main.run_reward_state.gold == (80 if int(result.roll) == 6 else 21), "1d6按6点大奖，其余获得1金币，先扣10金币")
	check(main.load_run_from_path(SAVE_PATH), "骰子结果可实际读档")
	var restored_result: Dictionary = maze.run.selected_path.story_result
	check(int(restored_result.roll) == int(result.roll) and int(restored_result.outcome_index) == int(result.outcome_index) and int(restored_result.option_index) == 1, "读档不重掷骰子")
	await process_frame
	await _capture("casino-result")
	_deal("strange_casino")
	maze.select_path("strange_casino")
	var inventory_before: int = main.emblem_library.get_inventory_state().size()
	check(maze.choose_story_option(5) and main.run_reward_state.gold == 27, "3金币食物选项扣费一次")
	check(main.emblem_library.get_inventory_state().size() == inventory_before + 1, "随机食物进入真实贴纸库存")
	_deal("bone_tower")
	maze.select_path("bone_tower")
	check(not maze.choose_story_option(0) and maze.choose_story_option(1), "白骨塔未实现分支禁用，离开可执行")
	check(maze.complete_event(), "白骨塔离开正常推进")
	# 覆盖概率边界：使用真实随机源，不替换业务服务。
	var rng := RandomNumberGenerator.new()
	rng.seed = 751
	var wins := 0
	var sixes := 0
	for index: int in 6000:
		wins += 1 if int(service.draw_outcome(casino.options[0], rng).outcome_index) == 0 else 0
		sixes += 1 if int(service.draw_outcome(casino.options[1], rng).roll) == 6 else 0
	check(wins > 2800 and wins < 3200 and sixes > 850 and sixes < 1150, "固定种子大样本覆盖50%硬币和1/6骰子概率")
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(SAVE_PATH)
	print("事件牌：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
