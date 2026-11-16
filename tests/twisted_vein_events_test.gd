extends "res://tests/event_cards_test.gd"

const Mining = preload("res://scripts/flow/twisted_vein_event_runtime.gd")
const MINE_SAVE := "/private/tmp/project-card-twisted-events-test.json"


func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("矿脉事件专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = MINE_SAVE
	root.add_child(shell)
	await process_frame
	maze = main.maze_controller
	_test_first_event()
	_test_camp()
	_test_lamp_and_river()
	_test_collapse()
	_test_mining()
	_test_bottle()
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(MINE_SAVE)
	print("扭曲矿脉事件：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)


func _new_run() -> void:
	if not main.profile_progress.profile.unlocks.packs.has("twisted_vein"):
		main.profile_progress.profile.unlocks.packs.append("twisted_vein")
	maze.new_run(1201)
	maze.choose_talent("sentry_guard")


func _event(id: String) -> Dictionary:
	for candidate: Dictionary in maze.content.free_events + maze.content.paid_events:
		if candidate.path_id == id: return candidate.duplicate(true)
	return {}


func _select_event(id: String) -> bool:
	var event := _event(id)
	event.kind = maze.run.get_round_kind()
	maze.run.paths.clear()
	return maze.run.set_paths([event, event, event]) and maze.select_path(id)


func _die(sides: int, face: int) -> void:
	for seed_value: int in range(100):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		if probe.randi_range(1, sides) == face:
			maze.run.rng.seed = seed_value
			return


func _finish_dice() -> void:
	if is_instance_valid(maze._story_roll): maze._story_roll.finished.emit()


func _create_card(id: String) -> OwnedCard:
	return main.owned_card_collection.create_card(load("res://resources/cards/%s.tres" % id), maze.run.rng)


func _deploy() -> OwnedCard:
	var owner: OwnedCard = maze._story_minions()[0]
	main.front_row.add_squad(SquadData.from_owned_card(owner), 0)
	return owner


func _test_first_event() -> void:
	_new_run()
	check(maze.run.paths.size() == 3 and maze.run.paths.all(func(path: Dictionary) -> bool: return path.path_id == "so_close"), "普通第一天三张牌都指向一步之遥")
	check(maze.select_path("so_close") and maze.choose_story_option(0) and maze._story_owned("mining_pick").size() == 1, "固定事件可以领取实际矿镐")
	var original_appearance: Dictionary = maze.story_events.config.appearance.duplicate(true)
	for event: Dictionary in maze.content.free_events + maze.content.paid_events:
		if event.get("reward") == "story" and not event.get("tutorial", false) and event.path_id != "fortuna_gift":
			maze.story_events.config.appearance[event.path_id]["pending"] = true
	check(maze.complete_event(true, true) and maze.run.paths.size() == 3 and maze.run.paths.all(func(path: Dictionary) -> bool: return path.path_id == "fortuna_gift" and path.kind == "paid_event"), "第二个事件位可从原随机池抽牌")
	check(main.load_run_from_path(MINE_SAVE), "第二事件位保存原随机事件可恢复")
	maze.story_events.config.appearance = original_appearance
	var fixed := _event("fortuna_gift")
	fixed.path_id = "test_other_fixed"
	fixed["fixed_day"] = 1
	fixed["fixed_round"] = 0
	maze.content.free_events.append(fixed)
	_new_run()
	check(not maze.run.paths.is_empty() and maze.run.paths[0].path_id == "test_other_fixed", "其他固定事件占用第一位")
	check(maze.select_path("test_other_fixed") and maze.complete_event(false, true) and maze.run.paths.size() == 3 and maze.run.paths.all(func(path: Dictionary) -> bool: return path.path_id == "so_close"), "一步之遥在同日顺延一位")
	maze.content.free_events.pop_back()


func _test_camp() -> void:
	_new_run()
	check(_select_event("bald_and_beard") and maze.choose_story_option(0), "攻击亡灵矿工进入实际额外战斗入口")
	check(maze.run.is_event_battle() and maze.run.battle_path().front == ["rusted_pickhand", "rusted_pickhand"], "额外战斗加载两名锈蚀镐手")
	check(main.load_run_from_path(MINE_SAVE) and Mining.can_appear(maze, "repair_mining_camp"), "战斗结算前已保存自修路线")
	_new_run()
	check(Mining.can_appear(maze, "repair_mining_camp") and not Mining.can_appear(maze, "bald_and_beard"), "跨局继续自修路线")
	for repair: int in range(1, 6):
		if repair > 1: _new_run()
		main.run_reward_state.gold = 10
		check(_select_event("repair_mining_camp") and maze.choose_story_option(0) and main.run_reward_state.gold == 0 and int(main.profile_progress.profile.twisted_camp.repairs) == repair, "逐次提交修缮且只扣一次金币")
	_new_run()
	check(_select_event("quiet_mining_camp") and maze.choose_story_option(0) and maze.story_buffs[0].get("floor") == 1, "自修完工后可以领取限层增益")
	check(not Mining.can_appear(maze, "quiet_mining_camp"), "同局本层领取一次")
	main.profile_progress.profile.erase("twisted_camp")
	_new_run()
	check(_select_event("bald_and_beard") and maze.choose_story_option(1), "交谈开启合作线")
	for id: String in ["长剑", "种子", "树"]:
		_new_run()
		check(maze._grant_emblem(id, "camp_test:" + id) and _select_event("undead_friends"), "捐赠界面读取工具箱纹章")
		if not is_instance_valid(maze._camp_donation_picker) or maze._camp_donation_picker.item_count < 2: continue
		maze._camp_donation_picker.select(1)
		check(maze.choose_story_option(0) and maze._story_stickers(id).is_empty(), "捐赠消耗实际选中的纹章")
	_new_run()
	var gold: int = main.run_reward_state.gold
	check(_select_event("lively_mining_camp") and maze.choose_story_option(0) and main.run_reward_state.gold == gold + 3 and maze.story_buffs.size() == 2, "合作营地领取 V 级纹章金币和限层战斗加成")


func _test_lamp_and_river() -> void:
	_new_run()
	check(_select_event("magical_mine_lamp"), "神奇矿灯可打开")
	_die(8, 5)
	check(maze.choose_story_option(0) and maze._story_owned("mine_lamp_wisp").size() == 1, "d8达到5点发放矿灯鬼火")
	_finish_dice()
	_new_run()
	var excluded: OwnedCard = maze._story_minions()[0]
	excluded.set_wound_slot(0, {"wound_id": "光血", "instance_id": "camp_test_light", "level": 1})
	check(_select_event("magical_mine_lamp"), "矿灯可测试失败结果")
	_die(8, 4)
	check(maze.choose_story_option(0), "d8低于5点分配光血")
	_finish_dice()
	var count := 0
	for card: OwnedCard in maze._story_minions():
		for wound: Dictionary in card.wound_slots:
			if wound.get("wound_id") == "光血": count += 1
	check(count == 3 and excluded.wound_slots[1].is_empty(), "光血分给两名不同且没有光血的随从")
	_new_run()
	var target: OwnedCard = maze._story_minions()[0]
	target.set_rune_sticker(0, {"emblem_id": "水贴纸", "instance_id": "river_water", "element": CardData.ElementType.WATER})
	target.set_rune_sticker(1, {"emblem_id": "万能贴纸", "instance_id": "river_wild", "element": -2})
	check(Mining.river_outcome(target) == 0, "万能贴纸补足水木组合")
	check(_select_event("underground_river") and maze.select_enhancement_card({"kind": &"card", "owned_card": target}) and maze.choose_story_option(0), "可从暗河真实卡槽结算符文组合")
	check(target.get_permanent_growth(OwnedCard.STAT_MAX_HEALTH) == 1 and target.get_permanent_growth(OwnedCard.STAT_BASE_ARMOR) == 1, "暗河水木成长永久入账")


func _test_collapse() -> void:
	_new_run()
	check(_select_event("mine_collapse") and not maze.choose_story_option(1), "防具不足时阻止选择")
	for index: int in 3: _create_card("dwarven_mining_helmet")
	_die(10, 10)
	check(maze.choose_story_option(1) and maze._story_owned("dwarven_mining_helmet").size() == 2, "三件防具满足门槛，1d10的10点损失一件")
	_finish_dice()
	_new_run()
	check(_select_event("mine_collapse") and maze.choose_story_option(4) and maze.story_buffs[0].value == 2, "无条件躲避排入下场开场眩晕2秒")
	_new_run()
	_create_card("ember_empty_bottle")
	check(_select_event("mine_collapse") and maze.choose_story_option(3) and maze.run.selected_path.story_result.guaranteed and not is_instance_valid(maze._story_roll), "持有余烬空瓶直接祈祷成功")


func _test_mining() -> void:
	_new_run()
	_create_card("doorboard")
	_deploy()
	check(_select_event("high_risk_mining") and not maze.choose_story_option(0) and not maze.choose_story_option(5), "缺真实熊群阵容时保留安全分支")
	# 使用已经合法的测试遭遇验证潜行和奖励事务，无需在正式数据中添加熊群占位卡。
	maze.story_events.config.encounters["high_risk_mining"] = maze.story_events.config.encounters.bald_and_beard
	var collection: OwnedCardCollection = main.owned_card_collection
	var before := collection.size()
	_die(10, 2)
	check(maze.choose_story_option(0) and maze.run.selected_path.mining_progress.cards.size() == 3 and collection.size() == before, "成功潜行只暂存三张 I 级矿物")
	_finish_dice()
	check(main.load_run_from_path(MINE_SAVE) and maze.run.selected_path.mining_progress.stage == 1, "潜行进度从实际存档恢复")
	check(maze.choose_story_option(7) and main.owned_card_collection.size() == before + 6, "门板接手只补剩余矿物并兑现已有矿物")
	_new_run()
	_deploy()
	check(_select_event("high_risk_mining"), "四轮潜行测试入场")
	for index: int in 4:
		_die(10, 1)
		check(maze.choose_story_option(index), "潜行成功阶段 %d" % (index + 1))
		_finish_dice()
	check(maze.run.selected_path.has("story_result") and not maze.run.selected_path.has("mining_progress") and maze._story_owned("rainbow_gold_ore").size() == 2, "四次成功自动撤退，缺 IV 级时 III 级可重复")
	_new_run()
	var owner := _deploy()
	owner.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 200)
	owner.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 80)
	check(_select_event("high_risk_mining"), "失败转战斗测试入场")
	_die(10, 1)
	check(maze.choose_story_option(0), "首次潜行成功")
	_finish_dice()
	_die(10, 10)
	check(maze.choose_story_option(1) and maze.run.is_event_battle() and not maze.run.selected_path.has("mining_progress"), "潜行失败丢弃暂存矿物并转战斗")
	_finish_dice()
	check(main.start_battle(-1, false), "可启动潜行失败触发的额外战斗")
	for index: int in 200:
		if main.battle_controller.current_result != BattleController.Result.NONE: break
		main.battle_controller.resolve_next_batch()
	main.current_phase = main.GamePhase.RESULT
	var settled: Dictionary = main.settle_current_battle(false)
	check(settled.get("success", false) and maze.last_reward.get("mining_cards") == 7, "额外战斗胜利发满七张矿物")
	check(maze.continue_after_battle(true) and maze.run.round_index == 1, "首次额外战斗回到当天第二事件位")
	main.profile_progress.profile.erase("twisted_camp")
	check(_select_event("bald_and_beard") and maze.choose_story_option(0), "第二事件位仍可触发额外战斗")
	check(main.load_run_from_path(MINE_SAVE) and maze.run.is_event_battle(), "同一天的第二场额外战斗可保存恢复")
	maze.story_events.config.encounters.erase("high_risk_mining")


func _test_bottle() -> void:
	_new_run()
	var wearer := _deploy()
	var enemy := _create_card("militia")
	var bottle := _create_card("ember_empty_bottle")
	var squad := SquadData.from_owned_card(wearer)
	squad.equip_item(bottle)
	var fight := BattleController.new()
	root.add_child(fight)
	var player_rows: Array[Dictionary] = [{"squad_data": squad, "row_key": &"player_front"}]
	var enemy_rows: Array[Dictionary] = [{"squad_data": SquadData.from_owned_card(enemy), "row_key": &"enemy_front"}]
	fight.start_battle(player_rows, enemy_rows, 1, false)
	var state := fight.player_states[0]
	state.current_health = 1.0
	var armor: float = state.current_armor
	check(state.apply_damage_exact(999.0).total == 0.0 and state.current_armor == armor and state.current_health == state.get_max_health(), "余烬空瓶阻止整次致命伤害并回满")
	var current := state.squad_data.get_effect_source_instance()
	check(fight.permanent_growth_ledger.get_amount_for_owned_card(wearer.instance_id, &"base_value") == 4 and fight.owned_card_change_ledger.get_entries().size() == 1, "余烬空瓶成长及使用次数进入现有结算账本")
	check(state.apply_damage_exact(999.0).total > 0 and state.current_health <= 0.0, "同一装备者已用过时再次承受致命伤害")
	wearer.progress_by_source[&"ember_empty_bottle_used"] = current.progress_by_source[&"ember_empty_bottle_used"]
	fight.start_battle(player_rows, enemy_rows, 2, false)
	check(fight.player_states[0].apply_damage_exact(999.0).total > 0, "装备者的使用记录跨场生效")
	fight.free()
