extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
const Builder := preload("res://scripts/flow/enemy_encounter_builder.gd")
const SAVE_PATH := "/private/tmp/project-card-debug-test.json"
var main: Control
var failures := 0
var assertions := 0

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("专项超时"); quit(2))
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func same_json(a: Variant, b: Variant) -> bool:
	# JSON把整数读作浮点数；先统一磁盘类型，再比较实际值。
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))


func key(code: Key, unicode: int = 0) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.unicode = unicode
		event.pressed = pressed
		root.push_input(event)
		await process_frame

func new_main() -> void:
	main = MAIN.instantiate()
	main.short_maze_enabled = true
	main.run_save_path = SAVE_PATH
	root.add_child(main)
	await process_frame
	await process_frame

func command(text: String) -> void:
	main._on_developer_console_command_submitted(text)

func _run() -> void:
	root.size = Vector2i(1280,720)
	await new_main()
	await key(KEY_F2)
	check(main._developer_console.visible and main._developer_console._command_input.has_focus(), "F2真实输入打开并聚焦控制台")
	var before: int = main.owned_card_collection.size()
	for ch: String in "card add crystal_shell_beetle 3": await key(KEY_NONE, ch.unicode_at(0))
	await key(KEY_ENTER)
	check(main.owned_card_collection.size() == before + 3, "键盘提交ID和数量生成3张真实收藏实例")
	command("card add 晶壳虫 x2")
	check(main.owned_card_collection.size() == before + 5, "中文名称和x数量")
	command("card add mine_collapse")
	command("card add ghost_pick")
	command("card add 彩金矿 2")
	check(main.owned_card_collection.size() == before + 9, "法术、装备、资源均生成正式实例")
	var known_state: Dictionary = main.owned_card_collection.capture_state()
	for invalid: String in ["card add nonexistent", "card add 晶壳虫 0", "card add 晶壳虫 -1", "card add 晶壳虫 1.5", "card add 晶壳虫 x", "card add 晶壳虫 101"]: command(invalid)
	check(main.owned_card_collection.capture_state() == known_state, "未知卡及非法数量不更改收藏")
	check("找不到卡牌" in main._developer_console._output.get_parsed_text(), "未知卡反馈")
	command("card list twisted_vein")
	check("crystal_shell_beetle" in main._developer_console._output.get_parsed_text(), "卡包筛选显示名称及ID")
	check("mining_pick" in main._developer_console._output.get_parsed_text() and "rainbow_gold_ore" in main._developer_console._output.get_parsed_text(), "矿脉卡包筛选包含共用卡牌定义")
	check(main.load_run_from_path(SAVE_PATH) and main.owned_card_collection.size() == before + 9, "真实存档读回所有加卡")
	var rng_state: int = main.maze_controller.run.rng.state
	var cards_state: Dictionary = main.owned_card_collection.capture_state()
	main.run_save_path = "/private/tmp/project-card-no-such-folder/debug.json"
	command("card add 晶壳虫 2")
	check(main.owned_card_collection.capture_state() == cards_state and main.maze_controller.run.rng.state == rng_state, "保存失败回退收藏、序号和随机流")
	main.run_save_path = SAVE_PATH
	await key(KEY_F2)
	var registry: Dictionary = main._build_card_definition_registry()
	var content: Dictionary = main.maze_controller.content
	var covered: Dictionary = {}
	var elements: Dictionary = {}
	var stacks := 0
	for definition: Dictionary in content.enemies:
		var path := definition.duplicate(true)
		path["battle_seed"] = 47007
		var snapshot := Builder.new().build(path, registry, 1)
		check(not snapshot.is_empty(), "生成合法遭遇：" + path.path_id)
		if snapshot.is_empty(): continue
		check(snapshot == Builder.new().build(path, registry, 1), "同种子实例完全重现：" + path.path_id)
		var restored := Builder.new().restore(JSON.parse_string(JSON.stringify(snapshot)), registry)
		check(not restored.is_empty(), "JSON还原遭遇：" + path.path_id)
		if restored.is_empty(): continue
		for row_key: StringName in [&"enemy_front", &"enemy_back"]:
			var units := 0
			for squad: SquadData in restored.rows[row_key]:
				units += squad.get_unit_count()
				check(squad.is_valid(), "合法堆叠及装备")
				if squad.get_card_count() > 1: stacks += 1
				for member: CardData in squad.horizontal_cards:
					var owned := squad.get_owned_card(member)
					covered[String(member.id)] = true
					check(owned != null and owned.rune_revealed.count(true) == 1, "第一层每卡揭晓1槽")
					for element: int in owned.resolved_runes: elements[element] = true
					if member.id == &"greedy_acolyte": check(squad.get_card_count() == 1, "贪婪信徒始终单卡")
					if member.id == &"crystal_shell_beetle": check(owned.resolved_action_type in [CardData.ActionType.MELEE, CardData.ActionType.DEFENSE], "晶壳虫实例固定合法行动")
				if squad.get_equipped_item() != null: covered[String(squad.get_equipped_item().card_data.id)] = true
			check(units <= 21, "敌排容量不超过正式21单元")
		for spell: OwnedCard in restored.spells: covered[String(spell.card_data.id)] = true
		for id: String in path.resources:
			covered[id] = true
			check(registry[StringName(id)].card_type == CardData.CardType.RESOURCE, "资源配置只包含资源")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/demo2/twisted_vein_manifest.json"))
	check(manifest.cards.all(func(card: Dictionary): return covered.has(card.id)), "12组遭遇覆盖全部36张矿脉卡")
	check(stacks > 0 and elements.size() == 5, "部分合法堆叠且元素池包含五元素")
	var sample: Dictionary = content.enemies[0].duplicate(true)
	sample["battle_seed"] = 47007
	for reveals: int in [0,2,3]:
		var restored := Builder.new().restore(Builder.new().build(sample, registry, reveals), registry)
		for squad: SquadData in restored.rows.enemy_front:
			for card: CardData in squad.horizontal_cards: check(squad.get_owned_card(card).rune_revealed.count(true) == reveals, "揭晓数量配置：%d" % reveals)
	# 构造合法的第四天战前状态作为e2e输入，实际路径生成、选择、保存与战斗都走生产入口。
	var maze: ShortMazeController = main.maze_controller
	maze.new_run(47007)
	maze.choose_talent("sentry_guard")
	maze.run.day = 4
	maze.run.round_index = 3
	maze.run.step = maze.RunState.Step.CHOOSING
	maze.run.paths.clear()
	maze.run.claimed_pack_days.assign([2,3])
	maze.run.battle_results.assign([{"day":1,"won":true,"ending":""},{"day":2,"won":true,"ending":""},{"day":3,"won":true,"ending":""}])
	maze._generate_paths()
	var player_count: int = main.owned_card_collection.size()
	check(maze.select_path("enemy_4_0"), "真实Main选择含堆叠、装备、法术、资源的矿脉路径")
	if DisplayServer.get_name() != "headless":
		main.set_world_view(main.WorldView.BATTLEFIELDS, false)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/private/tmp/project-card-debug-encounter.png") == OK, "保存真实敌方遭遇画面")
	var encounter_snapshot: Dictionary = maze.run.selected_path.encounter_state.duplicate(true)
	var board_before: Dictionary = main.resource_board_state.capture_state()
	check(main.owned_card_collection.size() == player_count, "敌方卡不泄漏到玩家收藏")
	check(maze.get_enemy_prepared_spells().size() == 1, "Main敌方准备法术来源")
	check(main.enemy_back_row.get_squads()[0].get_squad_data().get_equipped_item() != null, "Main显示正式装备位")
	check(main.load_run_from_path(SAVE_PATH), "敌方实例与装备真实存档读回")
	maze = main.maze_controller
	check(same_json(maze.run.selected_path.encounter_state, encounter_snapshot) and same_json(main.resource_board_state.capture_state(), board_before), "读档不重抽符文／行动／资源形状和位置")
	var original_equipment: OwnedCard = main.enemy_back_row.get_squads()[0].get_squad_data().get_equipped_item()
	var member: OwnedCard = main.owned_card_collection.get_cards()[1]
	main.front_row.add_squad(SquadData.from_owned_card(member), 0)
	check(main.start_battle(-1,false), "真实Main带敌方准备法术开战")
	check(main.battle_controller._enemy_prepared_spell_instances.size() == 1, "实际控制器接收敌方法术")
	var runtime_equipment: OwnedCard = null
	for state: BattleSquadState in main.battle_controller.enemy_states:
		var item := state.squad_data.get_equipped_item()
		if item != null and item.instance_id == original_equipment.instance_id: runtime_equipment = item
	check(runtime_equipment != null and runtime_equipment != original_equipment, "NPC装备战斗副本不污染战前实例")
	main.battle_controller.advance_time(0.05)
	check(main.battle_controller.current_result == BattleController.Result.NONE, "在未结算时验证中断重开")
	check(main.restart_battle(), "真实重开回准备")
	check(same_json(maze.run.selected_path.encounter_state, encounter_snapshot) and same_json(main.resource_board_state.capture_state(), board_before), "重开保留完整敌方实例与资源")
	check(main.enemy_back_row.get_squads()[0].get_squad_data().get_equipped_item() != null, "重开保留NPC装备")
	main.queue_free()
	await process_frame
	print("矿脉后续调试：%d条断言，%d失败" % [assertions,failures])
	quit(1 if failures else 0)
