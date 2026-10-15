extends SceneTree

## 使用真实主场景与正式资源复现战后延迟刷新、随机奖励池和敌方纹章。
const MAIN := preload("res://scenes/Main.tscn")
const Builder := preload("res://scripts/flow/enemy_encounter_builder.gd")
var failures := 0
var assertions := 0

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("后续回归超时"); quit(2))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func deploy(main, row: BattlefieldRow, id: String, player: bool = true) -> OwnedCard:
	var definition: CardData = load("res://resources/cards/%s.tres" % id)
	var card: OwnedCard = main.owned_card_collection.create_card(definition) if player else OwnedCard.new()
	if not player: card.initialize(definition, StringName("npc:%s" % id), 0)
	row.add_squad(SquadData.from_owned_card(card), row.get_squad_count())
	return card

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main := MAIN.instantiate()
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-silvermoon-followup-save.json"
	root.add_child(main)
	await process_frame
	await process_frame
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]: row.clear_squads()
	var dancer := deploy(main, main.front_row, "moon_dancer")
	var guard := deploy(main, main.back_row, "twilight_guard")
	var bell: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/dancer_handbell.tres"))
	main.front_row.get_squads()[0].get_squad_data().equip_item(bell)
	deploy(main, main.enemy_front_row, "baggage_muleteer", false)
	check(main.start_battle(21010, false), "真实主场景开始战斗")
	var c: BattleController = main.battle_controller
	c.set_process(false)
	var a: BattleSquadState = c.player_states[0]
	var b: BattleSquadState = c.player_states[1]
	check(c.silvermoon.swap(a, b), "带装备舞者跨排交换")
	check(c.has_effective_dazzling(b), "守卫换入前排获得耀眼")
	for index: int in 20:
		check(c.choose_base_target(c.enemy_states[0], c.player_states, CardData.ActionType.MELEE) == b, "敌军主攻击优先前排守卫")
	c.silvermoon.swap(a, b)
	check(not c.has_effective_dazzling(b), "后排守卫不保留前排耀眼")
	c.silvermoon.swap(a, b)
	a.record_damage_dealt(CardData.ActionType.MELEE, 17)
	b.battle_armor_granted = 6
	main.current_phase = main.GamePhase.RESULT
	main._restore_battle_result_layout()
	main._queue_battle_display_refresh()
	await process_frame
	await process_frame
	check(main.front_row.get_squads()[0].get_squad_data().get_effect_source_instance() == dancer, "延迟刷新后舞者仍在战前原位")
	check(main.back_row.get_squads()[0].get_squad_data().get_effect_source_instance() == guard, "延迟刷新不复制舞者到守卫槽")
	check(main.front_row.get_squads()[0].get_battle_result_statistics().damage_dealt == 17, "跨排舞者伤害17映射到自身")
	check(main.back_row.get_squads()[0].get_battle_result_statistics().armor_granted == 6, "守卫给予护甲6映射到自身")
	var growth_entries: Array[Dictionary] = [{"side": 0, "stat": &"max_health", "amount": 2.0, "owner_runtime_id": 1, "card_index": 0, "card_data": dancer.card_data}]
	var reward_entries: Array[Dictionary] = []
	var summary: String = main._format_battle_result_summary(growth_entries, reward_entries, true)
	check(summary.contains("生命 +2"), "永久生命成长进入结算摘要")
	var registry: Dictionary = main._build_card_definition_registry()
	main.ordinary_shop_service.config.allowed_pack_ids = ["silvermoon_chapter"]
	main.run_reward_state.pending_random_card_requests.assign([{"amount": 100, "parameters": {"card_type": "minion", "rarity": "I"}}])
	var before: int = main.owned_card_collection.size()
	check(main._resolve_pending_random_cards().success, "通用奖励真实抽取100张")
	check(main.owned_card_collection.get_cards().slice(before).all(func(card: OwnedCard) -> bool: return card.card_data.pack_id == &"silvermoon_chapter"), "通用奖励不泄漏敌方扭曲矿脉卡池")
	var path := {"battle_seed": 9010, "front": [{"cards": ["guard_remains", "crystal_shell_beetle"]}], "back": ["mine_lamp_wisp"]}
	for count: int in 4:
		var builder := Builder.new()
		var generated := builder.build(path, registry, 1, count)
		check(not generated.is_empty(), "生成敌方%d枚纹章阵容" % count)
		check(JSON.stringify(generated) == JSON.stringify(builder.build(path, registry, 1, count)), "相同种子纹章完全一致")
		var restored := builder.restore(generated, registry)
		for row: StringName in [&"enemy_front", &"enemy_back"]:
			for squad: SquadData in restored.rows[row]:
				for member: CardData in squad.horizontal_cards:
					var card := squad.get_owned_card(member)
					check(card.emblem_slots.filter(func(slot: Dictionary) -> bool: return not slot.is_empty()).size() == mini(count, card.emblem_slots.size()), "逐单卡填纹章且受槽位限制")
					check(card.emblem_slots.all(func(slot: Dictionary) -> bool: return slot.is_empty() or slot.emblem_id in EmblemLibraryData.get_basic_emblem_ids()), "仅I级纹章")
	var maze := ShortMazeController.new()
	maze.content = JSON.parse_string(FileAccess.get_file_as_string("res://data/demo2/short_maze_content.json"))
	for day: int in range(1, 9):
		maze.run.day = day
		check(maze._enemy_emblem_count() == (day - 1) / 2, "第%d天纹章递增配置" % day)
	maze.free()
	c.clear_battle()
	for file: String in ["事件强化复制", "贴纸强化复制"]:
		var save_path := "res://docs/validation/repaired-saves-20261010/%s-去除重复部署.json" % file
		var service := RunSaveService.new()
		var loaded := service.load_checkpoint(save_path)
		var collection := OwnedCardCollection.new()
		var restored := service.restore_checkpoint(loaded.checkpoint, collection, RunRewardState.new(), RunSettlementJournal.new(), registry, true)
		check(restored.success, "用户%s存档去重复后通过正式解码验证" % file)
	main.queue_free()
	await process_frame
	await process_frame
	print("银月后续回归：%d条断言，%d失败" % [assertions, failures])
	quit(1 if failures > 0 else 0)
