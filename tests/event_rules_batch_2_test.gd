extends "res://tests/event_cards_test.gd"

const LEGACY_PATH := "res://data/events/story_options_before_batch_2.json"
const PAPER = preload("res://assets/ui/shop_event_20261020/event_outcome_paper.png")


func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("事件规则专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	var folder := "/private/tmp/project-card-batch2-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(folder)
	shell.run_slots.directory = folder
	main.run_save_path = folder.path_join("run.json")
	root.add_child(shell)
	await process_frame
	maze = main.maze_controller
	_test_odds_and_backs()
	await _test_preview_and_discovery()
	_test_demon_growth_and_old_options()
	_test_shrine()
	_test_route()
	print("第二批事件规则：%d 项，失败 %d" % [assertions, failures])
	quit(1 if failures else 0)


func _definition(id: String) -> Dictionary:
	for event: Dictionary in maze.content.free_events + maze.content.paid_events:
		if event.path_id == id: return event.duplicate(true)
	return {}


func _begin_story(event: Dictionary) -> bool:
	maze.new_run(77)
	main.run_reward_state.gold = 100
	maze.choose_talent("sentry_guard")
	event.kind = "free_event"
	maze.run.paths.clear()
	return maze.run.set_paths([event, event, event]) and maze.select_path(event.path_id)


func _button_for(index: int) -> Button:
	for button: Button in maze._detail_body.find_children("*", "Button", true, false):
		if button.get_meta("story_option", -1) == index: return button
	return null


func _test_odds_and_backs() -> void:
	var service := maze.story_events
	check([0.0, 0.2, 0.4, 0.6, 0.8, 0.999999, 1.0].map(service.probability_tier) ==
		["极小概率", "小概率", "中概率", "高概率", "极大概率", "极大概率", "必定"], "只有百分之百显示必定")
	var fortuna: Dictionary = _definition("fortuna_gift").options[0]
	check(service.outcome_probabilities(fortuna) == [0.1, 0.1, 0.8]
		and service.outcome_probabilities(fortuna, 2) == [0.3, 0.1, 0.6], "正式福尔图纳概率按骰面重新计算")
	var tutorial: Dictionary = _definition("tutorial_fortuna_0").options[0]
	check(service.outcome_probabilities(tutorial) == [0.0, 0.0, 1.0], "教程按自己的骰面上限计算")
	var demon := _definition("demon_apprentices")
	for index: int in [0, 2]:
		var option: Dictionary = demon.options[index]
		check(service.outcome_probabilities(option) == [0.375, 0.625]
			and service.outcome_probabilities(option, 2) == [0.625, 0.375], "恶魔学步两项共享 d8 实际判定")
		for roll: int in range(1, 9):
			check(service.draw_outcome(option, RandomNumberGenerator.new(), 0, roll).outcome_index == (0 if roll >= 6 else 1), "恶魔学步骰点 %d" % roll)
	var card_ids := func(paths: Array[Dictionary]) -> Array:
		return TarotBacks.pick_for_round(paths, "77:1:0").map(func(back: Dictionary): return back.id)
	for ids: Array in [["demon_apprentices", "last_supper", "old_shrine"], ["slave_trader", "slave_trader", "slave_trader"], ["tutorial_fortuna_0", "tutorial_fortuna_1", "tutorial_fortuna_2"]]:
		var paths: Array[Dictionary] = []
		for id: String in ids: paths.append(_definition(id))
		var actual: Array = card_ids.call(paths)
		check(actual[0] != actual[1] and actual[0] != actual[2] and actual[1] != actual[2] and actual == card_ids.call(paths),
			"同轮塔罗底图去重，补位和教程也按同一个发牌键复现")


func _test_preview_and_discovery() -> void:
	var event := _definition("fortuna_gift")
	if not _begin_story(event):
		check(false, "正式福尔图纳选牌")
		return
	var button := _button_for(0)
	check(button != null and button.tooltip_text == "极小概率 · ？\n极小概率 · ？\n极大概率 · ？", "所有未知分支只露概率档和问号")
	if button == null: return
	var paper := button._make_custom_tooltip(button.tooltip_text) as PanelContainer
	paper.position = Vector2(800, 320)
	main.add_child(paper)
	await process_frame
	await process_frame
	var style := paper.get_theme_stylebox("panel") as StyleBoxTexture
	var label := paper.get_node("OutcomeText") as RichTextLabel
	check(paper.custom_minimum_size == PAPER.get_size() and paper.size.y > PAPER.get_height()
		and style.texture == PAPER and style.get_texture_margin(SIDE_LEFT) == 17
		and label.get_parsed_text().count("？") == 3, "多行纸条用原图作为最小尺寸并保留折角")
	paper.free()
	if DisplayServer.get_name() != "headless":
		await _capture_hover(button)
	_set_roll(10, 10)
	check(maze.choose_story_option(0), "实际选中并结算福尔图纳十点分支")
	check(main.load_run_from_path(main.run_save_path), "结算后可以从磁盘重读")
	var discoveries: Dictionary = main.profile_progress.profile.discoveries.event_outcomes
	check(discoveries.has("fortuna_gift:0:0") and not discoveries.has("fortuna_gift:0:2"), "同一存档只记实际结算的分支")
	check(_begin_story(event) and _button_for(0).tooltip_text.count("？") == 2, "新一局保留旧局的单个已发现结果")
	check(ProfileProgress.new().profile.discoveries.event_outcomes.is_empty(), "其他存档不继承已发现结果")
	check(_begin_story(_definition("old_shrine")), "进入有付费入口的神龛")
	main.run_reward_state.gold = 0
	maze.refresh()
	check(_button_for(0) == null and not maze.choose_story_option(0), "金币不足时隐藏付费选项且禁止直接结算")
	var toggle := main._developer_console.find_child("ShowEventDebugDetails", true, false) as CheckButton
	toggle.button_pressed = true
	button = _button_for(0)
	check(button != null and button.disabled and button.tooltip_text.contains("金币")
		and button.tooltip_text.contains("%"), "开发开关显示禁用选项、原因和精确概率")
	if DisplayServer.get_name() != "headless" and button != null:
		await _capture_hover(button, "debug")
	toggle.button_pressed = false


func _capture_hover(button: Button, suffix: String = "player") -> void:
	maze._event_table.show_detail_immediately()
	await process_frame
	await process_frame
	var point: Vector2 = shell.render_container.get_global_transform_with_canvas() * button.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	move.global_position = point
	root.push_input(move, true)
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/project-card-event-paper-%s.png" % suffix)


func _set_roll(sides: int, point: int) -> void:
	var probe := RandomNumberGenerator.new()
	for seed_value: int in range(1, 300):
		probe.seed = seed_value
		var state := probe.state
		if probe.randi_range(1, sides) == point:
			maze.run.rng.state = state
			return


func _test_demon_growth_and_old_options() -> void:
	var demon := _definition("demon_apprentices")
	if not _begin_story(demon):
		check(false, "恶魔学步选牌")
		return
	var owner: OwnedCard = maze._story_minions()[0]
	var team := SquadData.from_owned_card(owner)
	var before_value := team.get_preview_action_value()
	var before_health := team.get_effective_max_health()
	main.front_row.add_squad(team, 0)
	_set_roll(8, 8)
	check(maze.choose_story_option(2) and int(maze.run.selected_path.story_result.roll) == 8, "加入他们成功提交真实 d8 结果")
	check(team.get_preview_action_value() == before_value + 1 and team.get_effective_max_health() == before_health + 2
		and owner.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == 0
		and owner.get_permanent_growth(OwnedCard.STAT_MAX_HEALTH) == 0, "绿字数值和生命进入实际小队属性，白字基础值保持")
	var owner_id := owner.instance_id
	check(main.load_run_from_path(main.run_save_path), "带绿字永久成长的事件存档可重读")
	owner = main.owned_card_collection.get_by_instance_id(owner_id)
	check(owner != null and owner.get_permanent_growth(OwnedCard.STAT_BONUS_VALUE) == 1
		and owner.get_permanent_growth(OwnedCard.STAT_BONUS_MAX_HEALTH) == 2, "读回普通数值和最大生命两种绿字成长")
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_PATH))
	for index: String in legacy.demon_apprentices:
		demon.options[int(index)] = legacy.demon_apprentices[index]
	check(_begin_story(demon) and main.load_run_from_path(main.run_save_path)
		and not maze.run.selected_path.options[2].has("roll_sides"), "更新前已发出的恶魔学步保留旧规则并照常读取")
	check(maze.choose_story_option(2) and not maze.run.selected_path.story_result.has("roll")
		and main.load_run_from_path(main.run_save_path), "旧选项可继续结算、保存、再读取")


func _test_shrine() -> void:
	var event := _definition("old_shrine")
	if not _begin_story(event):
		check(false, "破旧的神龛选牌")
		return
	var index := 3
	check(_button_for(index) == null and not maze.choose_story_option(index), "无合格雕刻者时入口隐藏和结算拦截一致")
	for id: String in ["balin_ashslag", "ironhand_arno"]:
		main.owned_card_collection.create_card(load("res://resources/cards/%s.tres" % id))
	maze.refresh()
	var button := _button_for(index)
	check(button != null and not button.disabled and maze.choose_story_option(index), "两名新雕刻者均可开启原神像路径")
	if not maze.run.selected_path.has("story_result"): return
	var saved: Dictionary = maze.run.selected_path.story_result.duplicate(true)
	var chosen: OwnedCard = main.owned_card_collection.get_by_instance_id(StringName(saved.sculptor_instance_id))
	check(chosen != null and saved.text.contains(chosen.card_data.display_name) and saved.sculptor == String(chosen.card_data.id)
		and maze.story_buffs.back().stat == "equipment_growth", "文案固定实际抽出的实例并保留原装备增益")
	check(main.load_run_from_path(main.run_save_path)
		and maze.run.selected_path.get("story_result") == JSON.parse_string(JSON.stringify(saved)), "雕刻人选、文案及结果读档固定")


func _test_route() -> void:
	maze.new_run(77)
	maze.choose_talent("sentry_guard")
	var original_backs: Array[Dictionary] = maze._event_table._choice_backs.duplicate()
	check(main.load_run_from_path(main.run_save_path) and maze._event_table._choice_backs == original_backs,
		"通过正式存档恢复同一轮牌背的底图和朝向")
	for round_kind: String in ["free_event", "paid_event"]:
		check(maze.run.get_round_kind() == round_kind and maze.select_path(maze.run.paths[0].path_id) and maze.complete_event(false, true),
			"普通新局完成第一天的 " + round_kind)
	check(maze.run.get_round_kind() == "battle" and not main.ordinary_shop_open and main.load_run_from_path(main.run_save_path)
		and maze.run.get_round_kind() == "battle", "普通新局首日第三个行动就是战斗，存档保持")
	for fixture: String in ["旧局", "教程", "第二天"]:
		var run := ShortMazeRunState.new()
		run.initialize(1, fixture == "第二天")
		if fixture == "第二天": run.day = 2
		run.daily_pack_rewards = false
		run.round_index = 1
		run.step = ShortMazeRunState.Step.EVENT
		check(run.complete_event() and run.get_round_kind() == "shop", fixture + "保留商店轮")
