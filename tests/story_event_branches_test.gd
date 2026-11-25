extends "res://tests/event_cards_test.gd"

const BRANCH_SAVE := "/private/tmp/project-card-story-event-branches.json"


func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("事件分支回归超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = BRANCH_SAVE
	root.add_child(shell)
	await process_frame
	maze = main.maze_controller
	if "bounty-shop-only" in OS.get_cmdline_user_args():
		_test_bounty_shop_save()
		await _finish()
		return
	if "alchemist-only" in OS.get_cmdline_user_args():
		await _test_alchemist_potions()
		await _finish()
		return
	await _test_developer_event_panel()
	_test_last_supper_apple()
	_test_bone_tower()
	_test_whips_and_multipliers()
	_test_effect_stat_channels()
	_test_forbidden_and_dice()
	_test_forbidden_exchange()
	await _test_alchemist_potions()
	_test_casino_dependencies()
	_test_gilded_rewards()
	_test_gilded_battle_cards()
	_test_secret_missions_and_helmet_save()
	_test_nyx_road_selection()
	_test_legacy_edwin_runes()
	_test_ambush()
	_test_bounty_shop_save()
	_test_scrolls()
	await _finish()


func _finish() -> void:
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(BRANCH_SAVE)
	print("事件分支：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)


func _test_developer_event_panel() -> void:
	if _deal("fortuna_gift", 23) < 0: return
	check(main.save_run_to_path(BRANCH_SAVE) == OK, "保存正式对局供隔离回归")
	var original := FileAccess.get_file_as_string(BRANCH_SAVE)
	var base_paths := maze.run.paths.duplicate(true)
	var panel := main._developer_console as DeveloperConsole
	var session: RefCounted = main._developer_event_test
	panel.set_open(true)
	panel._event_query.text = "最后的晚餐"
	panel._event_query.text_changed.emit(panel._event_query.text)
	check(panel._events.item_count == 1, "F2可用中文名称从真实事件池搜索")
	panel._deal.pressed.emit()
	check(session.is_active() and maze.run.paths.all(func(path: Dictionary) -> bool: return path.path_id == "last_supper"), "按钮向正式牌桌发出指定事件")
	if not session.is_active(): return
	var table: Control = maze._event_table
	await _click(table._deck)
	if table.busy: await table.choices_ready
	await _click(table.cards[0])
	await create_timer(1.3).timeout
	check(session.can_retry() and maze.run.selected_path.get("path_id") == "last_supper", "真实翻牌选中事件并保存重试点")
	panel.set_open(true)
	panel._dice_option.select(1)
	panel._dice_option.item_selected.emit(1)
	panel._dice_point.select(10)
	panel._dice_point.item_selected.emit(10)
	panel._tabs.current_tab = 1
	var original_count: int = main.owned_card_collection.size()
	panel._data_query.text = "militia"
	panel._data_query.text_changed.emit("militia")
	panel._add.pressed.emit()
	check(main.owned_card_collection.size() == original_count + 1, "表单通过原加卡入口添加测试卡")
	panel._gold.text = "50"
	var apply_gold := panel.find_child("ApplyGold", true, false) as Button
	apply_gold.pressed.emit()
	check(main.run_reward_state.gold == 50, "表单可设定测试局金币")
	panel._data_kind.select(1)
	panel._data_kind.item_selected.emit(1)
	panel._data_query.text = "苹果"
	panel._data_query.text_changed.emit("苹果")
	check(panel._data_items.item_count >= 1, "局内调整可搜索贴纸")
	panel._add.pressed.emit()
	check(maze._story_stickers("苹果").size() == 1, "表单通过原库存入口加入苹果")
	panel.set_open(false)
	check(maze.choose_story_option(1) and int(maze.run.selected_path.story_result.roll) == 10, "指定选项按设置的10点走正式骰子结算")
	panel.set_open(true)
	panel._retry.pressed.emit()
	check(not maze.run.selected_path.has("story_result") and maze._story_stickers("苹果").is_empty() and main.run_reward_state.gold == 23 and main.owned_card_collection.size() == original_count, "一键重试恢复原选项、金币、收藏和库存")
	panel.set_open(true)
	panel._stop.pressed.emit()
	check(not session.is_active() and main.run_save_path == BRANCH_SAVE and maze.run.paths == base_paths and main.run_reward_state.gold == 23, "退出测试恢复原牌桌、金币和存档路径")
	check(FileAccess.get_file_as_string(BRANCH_SAVE) == original, "测试期间正式存档的文件内容保持原样")


func _test_last_supper_apple() -> void:
	var label := "吃随从偷藏的苹果"
	for source: String in ["无苹果", "工具箱", "卡牌"]:
		if _deal("last_supper") < 0: return
		var owner: OwnedCard = maze._story_minions()[0]
		var apple := {"instance_id": "last_supper_apple", "emblem_id": "苹果"}
		if source == "工具箱":
			check(maze._grant_emblem(apple.emblem_id, apple.instance_id), "工具箱可放入苹果夹具")
		elif source == "卡牌":
			owner.set_emblem_slot(0, apple)
		check(maze.select_path("last_supper"), "可进入最后的晚餐")
		if source == "无苹果":
			check(main.load_run_from_path(BRANCH_SAVE), "可读回尚未结算的最后的晚餐")
		var options: Array[Node] = maze._detail_body.find_children("*", "Button", true, false)
		var apple_button := options.filter(func(button: Button) -> bool: return button.text == label)
		if source == "无苹果":
			check(apple_button.is_empty(), "无苹果时普通界面隐藏吃苹果")
			maze.set_event_debug_details(true)
			options = maze._detail_body.find_children("*", "Button", true, false)
			apple_button = options.filter(func(button: Button) -> bool: return button.text == label)
		check(apple_button.size() == 1, "事件提供一个吃苹果选项")
		if apple_button.size() != 1: return
		var button := apple_button[0] as Button
		var can_eat := source != "无苹果"
		check(button.disabled == not can_eat, "苹果选项随持有状态更新：" + source)
		if not can_eat:
			check(button.tooltip_text.contains("需要纹章「苹果」"), "无苹果时显示缺少纹章的提示")
		var option_index := int(button.get_meta("story_option"))
		check(maze.choose_story_option(option_index) == can_eat, "结算与按钮使用相同的苹果条件：" + source)
		check(maze._story_stickers("苹果").is_empty(), "结算后苹果候选为空：" + source)
		maze.set_event_debug_details(false)


func _test_bone_tower() -> void:
	maze.story_events.config.appearance.bone_tower = {"floors": [1], "formal": true}
	_deal("bone_tower")
	main.profile_progress.run.enabled_unlocks.packs.append("twisted_vein")
	main.apply_run_unlocks()
	check(maze.select_path("bone_tower"), "白骨塔使用正式事件入口")
	var owner: OwnedCard = maze._story_minions()[0]
	maze.last_reward["damage_leaders"] = [String(owner.instance_id)]
	_set_weighted_roll(0.1, 0.55)
	check(maze.choose_story_option(0), "白骨塔伤势结果可提交")
	check(owner.wound_slots.any(func(wound: Dictionary) -> bool: return wound.get("wound_id") == "业火"), "给上一场伤害最高者施加业火")
	check(main.load_run_from_path(BRANCH_SAVE) and not maze.choose_story_option(0), "读档保留白骨塔结果，无法重复结算")


func _set_weighted_roll(low: float, high: float) -> void:
	var probe := RandomNumberGenerator.new()
	for index: int in range(1, 100):
		probe.seed = index
		var start := probe.state
		var roll := probe.randf()
		if roll >= low and roll < high:
			maze.run.rng.state = start
			return


func _test_whips_and_multipliers() -> void:
	var fight := BattleController.new()
	root.add_child(fight)
	var carrier := _fixture_owned("militia", "event_fixture_carrier", 30)
	var enemy := _fixture_owned("militia", "event_fixture_enemy", 30)
	var pain := _fixture_owned("pain_whip", "event_fixture_pain")
	var blood := _fixture_owned("blood_oath_whip", "event_fixture_blood")
	var team := SquadData.from_owned_card(carrier)
	team.equip_item(pain)
	fight.start_battle([{"squad_data": team, "row_key": &"player_front"}], [{"squad_data": SquadData.from_owned_card(enemy), "row_key": &"enemy_front"}], 8, false)
	var state := fight.player_states[0]
	var health := state.current_health
	var armor := state.current_armor
	fight._apply_wound_echo_effects(state)
	check(is_equal_approx(state.current_health, health - 2) and state.current_armor == armor and state.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 3, "苦痛之鞭先无视护甲自伤，再给强化")
	team.unequip_item()
	team.equip_item(blood)
	fight.start_battle([{"squad_data": team, "row_key": &"player_front"}], [{"squad_data": SquadData.from_owned_card(enemy), "row_key": &"enemy_front"}], 8, false)
	state = fight.player_states[0]
	check(fight.permanent_growth_ledger.get_amount_for_owned_card(carrier.instance_id, &"max_health") == -3, "血誓之鞭突击登记永久生命损失")
	check(state.current_health > state.get_max_health() and state.get_display_base_stats(state.get_active_rune_slots()).y == team.get_display_base_health(team.get_vitals_source(), 0) - 3, "血誓之鞭只降低基础和上限，白字即时更新")
	fight._apply_blood_oath_glory(state, fight.enemy_states[0])
	fight._apply_blood_oath_glory(state, fight.enemy_states[0])
	check(fight.permanent_growth_ledger.get_amount_for_owned_card(blood.instance_id, &"max_health") == 5 and fight.permanent_growth_ledger.get_amount_for_owned_card(blood.instance_id, &"base_value") == 2, "血誓之鞭荣耀只触发一次并归装备实例")
	team.unequip_item()
	team.equip_item(_fixture_owned("hellstone_fragment", "event_fixture_stone"))
	carrier.set_wound_slot(0, {"wound_id": "业火", "instance_id": "event_fixture_fire", "level": 1})
	fight.start_battle([{"squad_data": team, "row_key": &"player_front"}], [{"squad_data": SquadData.from_owned_card(enemy), "row_key": &"enemy_front"}], 8, false)
	state = fight.player_states[0]
	check(state.hellfire_multiplier() == 4 and state.get_max_health() == roundi(team.get_unconverted_max_health() * 0.5) and state.current_health == state.get_max_health(), "业火减半初始生命，和业石乘算")
	check(team.get_effective_max_health() == state.get_max_health() and state.get_display_base_stats(state.get_active_rune_slots()).y > state.get_max_health(), "单卡预览和战场都把业火减半归入红色生命差额")
	check(state.apply_damage_exact(1.0, fight.enemy_states[0], null, true).health_damage == 4.0, "业火和业石的直伤倍率只算一次")
	fight.free()


func _test_effect_stat_channels() -> void:
	var mage := _fixture_owned("spark_mage", "event_fixture_base_action")
	mage.rune_revealed.fill(false)
	mage.set_acquired_action_type(CardData.ActionType.MAGIC)
	mage.set_emblem_slot(0, {"emblem_id": &"面包", "instance_id": &"effect_stat_bread"})
	var team := SquadData.from_owned_card(mage)
	var moon := CelestialIndicator.new()
	moon.kind = CelestialIndicator.Kind.MOON
	moon.instance_id = &"effect_stat_moon"
	check(team.attach_indicator(moon, Vector2(30, 30), 0), "在测试小队附上月亮")
	var native_health := team.get_display_base_health(team.get_vitals_source(), 0)
	var native_armor := team.get_display_base_armor(team.get_vitals_source(), 0)
	check(team.get_effective_max_health() == native_health + 2 and team.get_effective_base_armor() == native_armor + 8, "面包和月亮加成只进入差额层")
	var fight := BattleController.new()
	root.add_child(fight)
	var formation: Array[Dictionary] = [{"squad_data": team, "row_key": &"player_front"}]
	var buffs: Array[Dictionary] = [{"stat": "growth", "base_value": 1, "target": "magic", "battles": -1}]
	fight.prepare_battle_preview(formation, [], 8, buffs)
	var state := fight.player_states[0]
	var new_base := state.get_display_base_stats(state.get_active_rune_slots()).x
	check(new_base == mage.card_data.base_value + 1 and state.get_action_base_value() == new_base, "已有存档格式的苦痛之遇直接进基础数值")
	state.runtime_base_action_multiplier = 2.0
	check(state.get_action_base_value() == new_base * 2, "苦痛之遇随基础数值乘法结算")
	var old_life := state.get_max_health()
	fight.silvermoon.permanent_health(state, 2, state, &"il_ancient_speaker")
	check(state.get_display_base_stats(state.get_active_rune_slots()).y == native_health + 2 and state.get_max_health() == old_life + 2 and state.current_health == old_life + 2, "古语者基础生命同步更新白字、上限与当前")
	fight.free()


func _test_forbidden_and_dice() -> void:
	var fight := BattleController.new()
	root.add_child(fight)
	var carrier := _fixture_owned("militia", "event_fixture_forbidden", 30)
	var enemy := _fixture_owned("militia", "event_fixture_target", 30)
	var potion := _fixture_owned("event_forbidden_large_0", "event_fixture_potion")
	carrier.set_emblem_slot(0, {"emblem_id": &"火把", "instance_id": &"event_fixture_torch"})
	var team := SquadData.from_owned_card(carrier)
	team.equip_item(potion)
	var old_count := carrier.wound_slots.size() + carrier.emblem_slots.size()
	var base_health := carrier.get_base_stat_with_permanent_growth(OwnedCard.STAT_MAX_HEALTH)
	var rules := {"rules": {"wound_event": {"wound_ids": ["中毒Ⅰ", "烧伤Ⅰ"]}}}
	fight.start_battle([{"squad_data": team, "row_key": &"player_front"}], [{"squad_data": SquadData.from_owned_card(enemy), "row_key": &"enemy_front"}], 7, false, &"event_test_potion", [], [], [], [], [], [], rules)
	var state := fight.player_states[0]
	var transformed := state.squad_data.get_effect_source_instance()
	check(transformed.has_forbidden_layout() and transformed.wound_slots.size() == old_count and transformed.emblem_slots.is_empty() and transformed.wound_slots.all(func(wound: Dictionary) -> bool: return wound.get("locked", false) and int(wound.level) == 1), "大型禁药把所有边缘状态槽转成不可清除的I级伤势")
	check(not state.has_targeting_keyword(&"dazzling"), "大型禁药移除原纹章在本场提供的关键词")
	check(transformed.get_base_stat_with_permanent_growth(OwnedCard.STAT_MAX_HEALTH) == (base_health + 2) * 2, "神力禁药先加生命再翻倍")
	var save := RunSaveService.new()
	var data := save._encode_collection_state({"cards": [transformed.capture_state()]})
	check(save._decode_collection_state(data, {&"militia": carrier.card_data}, false, false, RunSaveService.SCHEMA_VERSION, false, false).success, "转化后的实例槽位可正式编解码")
	team.unequip_item()
	team.equip_item(_fixture_owned("nyx_dice", "event_fixture_dice"))
	fight.start_battle([{"squad_data": team, "row_key": &"player_front"}], [{"squad_data": SquadData.from_owned_card(enemy), "row_key": &"enemy_front"}], 8, false)
	check(fight._roll_probability(fight.player_states[0], 2).total == 2, "战斗骰加2但不超骰面")
	var option := {"roll_sides": 2, "outcomes": [{"roll_values": [1]}, {"roll_values": [2]}]}
	check(maze.story_events.draw_outcome(option, maze.run.rng, 2).roll == 2, "事件骰加2且用封顶后的点数选分支")
	fight.free()


func _test_alchemist_potions() -> void:
	var expected := {
		1: Vector4i(1, -1, 0, 0), 2: Vector4i(0, 2, 0, 0),
		4: Vector4i(0, 0, 0, 1), 8: Vector4i(0, 0, 2, 0),
		3: Vector4i(1, 1, 0, 0), 5: Vector4i(1, -1, 0, 1),
		6: Vector4i(0, 2, 0, 1), 9: Vector4i(1, -1, 2, 0),
		10: Vector4i(0, 2, 2, 0), 12: Vector4i(0, 0, 2, 1),
		15: Vector4i(1, 1, 2, 1),
	}
	var view: CardView = main.CARD_VIEW_SCENE.instantiate()
	view.set_snapshot_mode(true)
	root.add_child(view)
	for mask: int in expected:
		var card: CardData = load("res://resources/cards/event_potion_%d.tres" % mask)
		var deltas: Vector4i = expected[mask]
		view.set_card_data(card)
		check(
			view.value_label.text == str(deltas.x) and view.health_label.text == str(deltas.y)
			and view.armor_label.text == str(deltas.z) and view.cooldown_label.text == ("+1" if deltas.w else "0")
			and view.cooldown_icon.position == CardView.EQUIPMENT_ZEAL_POSITION
			and card.effect_text == "突击：消耗并使装备者获得属性",
			"药剂%s显示正确数值、沿用热诚位置及采用统一描述" % card.display_name
		)
	view.free()
	if _deal("fortuna_gift") < 0: return
	check(maze.select_path("fortuna_gift") and maze.complete_event(false, true), "从随机事件进入炼金师所在的付费事件轮")
	maze.run.paths.clear()
	var alchemist: Dictionary = maze.content.paid_events.filter(func(path: Dictionary) -> bool: return path.path_id == "alchemist")[0]
	check(maze.run.set_paths([alchemist, alchemist, alchemist]) and maze.select_path("alchemist"), "通过正式选牌进入炼金师试用")
	var owner: OwnedCard = maze._story_minions()[0]
	var owner_id := owner.instance_id
	var before := _potion_growth(owner)
	var count: int = main.owned_card_collection.size()
	check(maze.select_enhancement_card({"kind": &"card", "owned_card": owner}) and maze.choose_story_option(0), "炼金师免费试用对选择的随从立即生效")
	var potion_id := String(maze.run.selected_path.get("story_result", {}).get("potion_id", ""))
	var mask := int(potion_id.trim_prefix("event_potion_"))
	check(mask in [1, 2, 4, 8] and _potion_growth(owner) - before == expected.get(mask), "试用的持久增量与实际展示的单项药剂一致")
	var previews := maze._event_table.find_child("EventRewardCards", false, false)
	var preview := previews.get_child(0).get_child(0) as CardView if previews != null else null
	check(preview != null and preview.card_data.id == StringName(potion_id) and main.owned_card_collection.size() == count, "试用结果展示实际药剂卡且没有额外领取")
	if "--capture-events" in OS.get_cmdline_user_args():
		await create_timer(0.5).timeout # 截图前等选中的随从回到原位
	await _capture("alchemist-sample")
	check(main.load_run_from_path(BRANCH_SAVE) and maze.run.selected_path.get("story_result", {}).get("potion_id") == potion_id and not maze.choose_story_option(0), "读档恢复原药剂且拒绝重复试用")
	owner = main.owned_card_collection.get_by_instance_id(owner_id)
	check(owner != null and _potion_growth(owner) - before == expected.get(mask), "读档保留随从的单次试用增量")
	var result: Dictionary = maze.run.selected_path.get("story_result", {})
	result.erase("potion_id")
	check(main.save_run_to_path(BRANCH_SAVE) == OK and main.load_run_from_path(BRANCH_SAVE) and not maze.choose_story_option(0), "没有展示字段的旧试用结果仍可读取且不会重复结算")


func _potion_growth(owner: OwnedCard) -> Vector4i:
	return Vector4i(
		roundi(owner.get_permanent_growth(OwnedCard.STAT_BASE_VALUE)),
		roundi(owner.get_permanent_growth(OwnedCard.STAT_MAX_HEALTH)),
		roundi(owner.get_permanent_growth(OwnedCard.STAT_BASE_ARMOR)),
		int(owner.progress_by_source.get(&"event_potion_zeal", 0))
	)


func _test_forbidden_exchange() -> void:
	_deal("fortuna_gift")
	check(maze.select_path("fortuna_gift") and maze.complete_event(false, true), "从随机事件进入禁药强化轮")
	var collection: OwnedCardCollection = main.owned_card_collection
	var owner: OwnedCard = maze._story_minions()[0]
	var expected_wounds := owner.wound_slots.size() + owner.emblem_slots.size()
	var materials: Array[OwnedCard] = []
	for card_id: String in ["militia", "war_drum_musician", "rune_engraver", "edwin_ash"]:
		materials.append(collection.create_card(load("res://resources/cards/%s.tres" % card_id), maze.run.rng))
	var alchemist: Dictionary = maze.content.paid_events.filter(func(path: Dictionary) -> bool: return path.path_id == "strange_alchemist")[0]
	maze.run.paths.clear()
	check(maze.run.set_paths([alchemist, alchemist, alchemist]) and maze.select_path("strange_alchemist"), "进入真实禁药交换界面")
	for material: OwnedCard in materials:
		var picker: OptionButton = maze._story_material_pickers[material.card_data.rarity]
		for index: int in range(1, picker.item_count):
			if picker.get_item_metadata(index) == String(material.instance_id):
				picker.select(index)
				break
	check(maze.choose_story_option(2), "四张不同品级随从可交换大型禁药")
	check(materials.all(func(card: OwnedCard) -> bool: return collection.get_by_instance_id(card.instance_id) == null), "交换只移除选中的四张实例")
	var potions := collection.get_cards().filter(func(card: OwnedCard) -> bool: return String(card.card_data.id).begins_with("event_forbidden_large_"))
	check(potions.size() == 1, "交换获得一瓶大型禁药")
	if potions.is_empty(): return
	var potion: OwnedCard = potions[0]
	owner.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 200)
	owner.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 80)
	var team := SquadData.from_owned_card(owner)
	team.equip_item(potion)
	main.front_row.add_squad(team, 0)
	check(maze.complete_event(true, true) and maze.run.get_round_kind() == "battle", "带大型禁药从首日付费事件进入日末战斗")
	check(maze.select_path(maze.run.paths[0].path_id) and main.start_battle(-1, false), "从真实开战入口触发大型禁药")
	_finish_test_battle()
	check(owner.has_forbidden_layout() and owner.wound_slots.size() == expected_wounds and collection.get_by_instance_id(potion.instance_id) == null, "正式结算写回转换后的伤势槽并消耗禁药")
	check(main.save_run_to_path(BRANCH_SAVE) == OK and main.load_run_from_path(BRANCH_SAVE) and main.owned_card_collection.get_by_instance_id(owner.instance_id).has_forbidden_layout(), "大型禁药的实战结果可存档恢复")


func _test_casino_dependencies() -> void:
	_deal("strange_casino", 53)
	check(maze.select_path("strange_casino") and not maze.choose_story_option(2), "赌坊作弊需要持有骰子")
	var collection: OwnedCardCollection = main.owned_card_collection
	var dice := collection.create_card(load("res://resources/cards/nyx_dice.tres"), maze.run.rng)
	check(not maze.choose_story_option(3), "镀金或纹章包未开放时老虎机整项不可执行")
	_set_weighted_roll(0.96, 1.0)
	check(maze.choose_story_option(2) and main.run_reward_state.gold == 15, "作弊失败先扣10，再向下取整扣除余款的三分之二")
	check(collection.get_by_instance_id(dice.instance_id) == dice, "作弊失败保留未装备的骰子")


func _test_gilded_rewards() -> void:
	if not main.profile_progress.profile.unlocks.packs.has("gilded_commission"): main.profile_progress.profile.unlocks.packs.append("gilded_commission")
	for id: String in ["strange_casino", "suspicious_merchant"]:
		_deal(id, 60)
		for pack: String in ["gilded_commission", "emblem_pack"]:
			if not main.profile_progress.run.enabled_unlocks.packs.has(pack): main.profile_progress.run.enabled_unlocks.packs.append(pack)
		if not main.profile_progress.run.enabled_unlocks.items.has("scraper"): main.profile_progress.run.enabled_unlocks.items.append("scraper")
		main.apply_run_unlocks()
		var collection: OwnedCardCollection = main.owned_card_collection
		var pool := maze._gilded_pack_pool()
		check(pool.size() == 24, "正式注册表提供全部二十四张镀金牌")
		check(main.ordinary_shop_service._eligible_cards(pool, collection.get_cards()).is_empty(), "专属镀金牌排除在普通候选之外")
		check(maze.select_path(id), "打开带镀金奖励的真实事件")
		var option := 3 if id == "strange_casino" else 0
		if id == "strange_casino":
			_set_weighted_roll(0.0, 0.1)
		else:
			_set_die_roll(maze.run.rng, 6, 6)
		check(maze.choose_story_option(option), "真实镀金奖励分支成功结算 " + id)
		if id == "suspicious_merchant":
			check(is_instance_valid(maze._story_roll) and not is_instance_valid(main._card_pack_opening), "可疑商人先展示骰子，再展示镀金卡包")
			if is_instance_valid(maze._story_roll): maze._story_roll.finished.emit()
		var opening: CardPackOpening = main._card_pack_opening
		var wrapper := opening.tear_art.source_viewport.get_child(0) as TextureRect if is_instance_valid(opening) else null
		check(wrapper != null and wrapper.texture.resource_path == "res://assets/card_ui/shop/gilded_commission_small.png" and wrapper.size == Vector2(115, 174), "事件奖励使用原尺寸镀金包装")
		if is_instance_valid(opening):
			var relief := opening.tear_art.material as ShaderMaterial
			check(relief.get_shader_parameter("body_height") == opening.TearArt.SMALL_BODY_HEIGHT and bool(relief.get_shader_parameter("use_center_height")) and relief.get_shader_parameter("center_height") == opening.TearArt.GILDED_SEAL_HEIGHT and relief.get_shader_parameter("center_height_origin_px") == Vector2(37, 49), "事件包装接入小包袋身与镀金火漆原尺寸高度图")
		var awarded := collection.get_cards().filter(func(card: OwnedCard) -> bool: return card.card_data.pack_id == &"gilded_commission")
		var ids := {}
		for card: OwnedCard in awarded:
			if card.card_data.rarity == CardData.Rarity.IV: ids[card.card_data.id] = true
		check(ids.size() == 3 and maze._gilded_pack_pool().size() == pool.size() - 3, "奖励发放三种不同IV牌，并立即按持有去重")
		check(is_instance_valid(opening) and opening.cards.size() == 3 and opening.cards.all(func(card: OwnedCard) -> bool: return awarded.has(card)), "开包展示的三张卡就是事件已发放的收藏实例")
		check(main.load_run_from_path(BRANCH_SAVE) and not maze.choose_story_option(option) and not is_instance_valid(main._card_pack_opening), "读档保留镀金奖励且不重复领取或开包")


func _set_die_roll(rng: RandomNumberGenerator, sides: int, face: int) -> void:
	var probe := RandomNumberGenerator.new()
	for seed_value: int in range(1, 200):
		probe.seed = seed_value
		var original := probe.state
		if probe.randi_range(1, sides) == face:
			rng.state = original
			return


func _test_gilded_battle_cards() -> void:
	var fight := BattleController.new()
	root.add_child(fight)
	var enemy := _fixture_owned("militia", "gilded_enemy", 60)
	var enemy_formation: Array[Dictionary] = [{"squad_data": SquadData.from_owned_card(enemy), "row_key": &"enemy_front"}]
	var roland := _fixture_owned("roland_falcon", "gilded_roland")
	var second := _fixture_owned("roland_falcon", "gilded_second_roland")
	var player: Array[Dictionary] = []
	for owned: OwnedCard in [roland, second]:
		player.append({"squad_data": SquadData.from_owned_card(owned), "row_key": &"player_front"})
	fight.start_battle(player, enemy_formation, 19, false)
	check(fight.player_states[0].get_action_base_value() == 9, "两个罗兰让混沌单位基础3变9，含自己")
	fight.player_states[1].grant_runtime_keyword(&"silenced", 123)
	check(fight.player_states[0].get_action_base_value() == 6, "罗兰被遮蔽后立即移除该来源")
	var seraphina := _fixture_owned("seraphina_starsinger", "gilded_seraphina")
	var other_singer := _fixture_owned("seraphina_starsinger", "gilded_other_singer")
	var recruiter := _fixture_owned("recruiter", "gilded_recruiter")
	player.clear()
	for owned: OwnedCard in [seraphina, recruiter, other_singer]:
		if owned.card_data.id == &"seraphina_starsinger": owned.progress_by_source[OwnedCard.SERAPHINA_PROGRESS] = 19 if owned == seraphina else 18
		player.append({"squad_data": SquadData.from_owned_card(owned), "row_key": &"player_front"})
	fight.start_battle(player, enemy_formation, 19, false)
	var changes := fight.owned_card_change_ledger.get_entries()
	check(changes.size() == 2 and changes.all(func(change: Dictionary) -> bool: return int(change.parameters.get("counter_value", 0)) == 20), "真实突击与额外突击都计入进度，同一卡只写回一次最终值")
	check(fight.run_reward_ledger.get_total(BattleRunRewardLedger.KIND_RANDOM_CARD_REQUEST, BattleSquadState.Side.PLAYER) == 2, "同场达标且两个相邻来源合计只重放一次突击")
	var whipper := _fixture_owned("militia", "gilded_whipper", 30)
	var whip_squad := SquadData.from_owned_card(whipper)
	whip_squad.equip_item(_fixture_owned("blood_oath_whip", "gilded_whip"))
	player[1]["squad_data"] = whip_squad
	fight.start_battle(player, enemy_formation, 19, false)
	check(fight.permanent_growth_ledger.get_amount_for_owned_card(whipper.instance_id, &"max_health") == -6, "塞拉菲娜可以重复相邻血誓之鞭的原生突击")
	seraphina.progress_by_source[OwnedCard.SERAPHINA_PROGRESS] = 19
	var edwin := _fixture_owned("edwin_ash", "gilded_edwin")
	player = [
		{"squad_data": SquadData.from_owned_card(seraphina), "row_key": &"player_front"},
		{"squad_data": SquadData.from_owned_card(edwin), "row_key": &"player_front"},
	]
	fight.start_battle(player, enemy_formation, 19, false)
	check(not fight.player_states[0].alive and seraphina.progress_by_source[OwnedCard.SERAPHINA_PROGRESS] == 20, "塞拉菲娜在突击开始时在场，即使被这次突击消灭仍计入")
	var hild := _fixture_owned("hild_allrounder", "gilded_hild")
	var hild_state := SquadData.from_owned_card(hild)
	player = [{"squad_data": hild_state, "row_key": &"player_front"}]
	fight.start_battle(player, enemy_formation, 19, false)
	check(fight.player_states[0].get_action_base_value() == 8 and fight.player_states[0].current_health == 7, "希尔德保留基础值8，混沌无参与元素加成")
	var teammate := _fixture_owned("militia", "gilded_hild_teammate")
	hild.resolved_runes.assign([CardData.ElementType.FIRE, CardData.ElementType.FIRE, CardData.ElementType.FIRE])
	teammate.resolved_runes.assign([CardData.ElementType.DARK, CardData.ElementType.DARK, CardData.ElementType.DARK])
	hild.rune_revealed.fill(true)
	teammate.rune_revealed.fill(true)
	var hild_squad := SquadData.from_cards([hild.get_battlefield_card(), teammate.get_battlefield_card()])
	hild_squad.bind_owned_card(hild.get_battlefield_card(), hild)
	hild_squad.bind_owned_card(teammate.get_battlefield_card(), teammate)
	hild_squad.bring_card_to_top(hild.get_battlefield_card())
	player = [{"squad_data": hild_squad, "row_key": &"player_front"}]
	fight.start_battle(player, enemy_formation, 19, false)
	var mixed := fight.player_states[0]
	check(mixed.get_rune_pattern_result().pattern_type == RunePatternResult.PatternType.FULL_HOUSE and mixed.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 2 and mixed.current_health == hild_squad.get_effective_max_health() + 2, "希尔德对自己的三相双鸣小队加2/2并同步当前生命")
	var balin := _fixture_owned("balin_ashslag", "gilded_balin")
	balin.set_wound_slot(0, {"wound_id": &"烧伤Ⅰ", "instance_id": &"balin_fixture_wound", "level": 1})
	player = [{"squad_data": SquadData.from_owned_card(balin), "row_key": &"player_front"}, {"squad_data": hild_state, "row_key": &"player_back"}]
	fight.start_battle(player, enemy_formation, 19, false, &"gilded_balin_test", [], [], [], [], [], [], {}, {"gallery_equipment_count": 3})
	var dwarf := fight.player_states[0]
	fight._death_wound_checked[dwarf.runtime_id] = true
	_set_die_roll(fight._random, 20, 20)
	dwarf.current_health = 0
	fight._finalize_batch()
	check(fight.run_reward_ledger.get_total(BattleRunRewardLedger.KIND_GOLD, BattleSquadState.Side.PLAYER) == 1 and fight.permanent_growth_ledger.get_amount_for_owned_card(balin.instance_id, &"max_health") == 1 and fight.permanent_growth_ledger.get_amount_for_owned_card(balin.instance_id, &"base_value") == 1, "巴林按3种图鉴装备投1次，20点累计低档")
	check(dwarf.squad_data.get_effect_source_instance().wound_slots[0].is_empty(), "巴林的20点额外治疗本小队可见伤势")
	check(fight.revive_state_at_original_position(dwarf, 3, false), "复活巴林")
	_set_die_roll(fight._random, 20, 20)
	dwarf.current_health = 0
	fight._finalize_batch()
	check(fight.run_reward_ledger.get_total(BattleRunRewardLedger.KIND_RANDOM_EMBLEM_INSTANCE, BattleSquadState.Side.PLAYER) == 2, "巴林再次阵亡可重触发遗愿和纹章奖励")
	fight.clear_battle()
	fight.free()


func _test_ambush() -> void:
	_deal("bounty_hunter")
	var owner: OwnedCard = maze._story_minions()[0]
	owner.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 200)
	owner.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 80)
	main.front_row.add_squad(SquadData.from_owned_card(owner), 0)
	check(maze.select_path("bounty_hunter"), "赏金猎人入场")
	_set_weighted_roll(0.0, 0.3)
	check(maze.choose_story_option(4) and maze.run.is_event_battle() and maze.run.battle_path().enemy_first, "逃跑失败准备敌方先突击的额外战斗")
	var seed_value := int(maze.run.battle_path().battle_seed)
	check(main.load_run_from_path(BRANCH_SAVE) and int(maze.run.battle_path().battle_seed) == seed_value and not main.enemy_front_row.get_squads().is_empty(), "读档恢复相同伏击遭遇")
	check(main.start_battle(-1, false), "通过真实开战入口进入伏击")
	_finish_test_battle()
	check(maze.run.step == ShortMazeRunState.Step.BATTLE_RESULT and maze.run.battle_results.back().get("extra", false), "正式结算标识额外战斗")
	check(maze.continue_after_battle(true) and maze.run.day == 1 and maze.run.round_index == 1 and maze.run.paths.size() == 3, "额外战斗后继续当天强化轮")
	check(main.load_run_from_path(BRANCH_SAVE), "当日继续的存档可恢复")


func _test_bounty_shop_save() -> void:
	if _deal("bounty_hunter", 100) < 0: return
	maze.run.skip_first_day_shop = false # 旧存档的首日商店仍需能读能继续
	var awarded: bool = maze.select_path("bounty_hunter") and maze.choose_story_option(0) and maze.story_shop_discount
	check(awarded, "走赏金猎人的正式交付分支获得商店八折")
	if not awarded: return
	var entered: bool = (
		maze.complete_event(true, true) and maze.select_path(maze.run.paths[0].path_id)
		and maze.complete_event(false, true) and maze.select_path(maze.run.paths[0].path_id)
	)
	check(entered, "沿真实事件事务进入八折商店")
	if not entered: return
	maze.enter_selected_shop()
	main._refresh_ordinary_shop()
	var shop: OrdinaryShopService = main.ordinary_shop_service
	check(shop.refresh_count == 1 and shop.offers.all(func(offer: Dictionary) -> bool:
		return offer.kind != "card_pack" or int(offer.price) == (14 if offer.size == "large" else 9)
	), "刷新后普通和定向卡包仍保留八折向下取整")
	var item := shop.offers.find_custom(func(offer: Dictionary): return offer.kind == "single_card" and offer.hidden)
	check(item >= 0, "商城提供可售的暗单")
	if item < 0: return
	var offer := shop.offers[item]
	var old_gold: int = main.run_reward_state.gold
	main._on_ordinary_shop_offer_pressed(item)
	check(offer.get("sold", false) and shop.reveal_by_offer.get(offer.offer_id) == offer.card_id and main.run_reward_state.gold == old_gold - int(offer.price), "按折后原价买入，保留已售和揭晓记录")
	# JSON 读取后整数变为浮点，比较磁盘表示以保留对每一项报价和随机数的核对。
	var expected: Dictionary = JSON.parse_string(JSON.stringify(shop.capture_state()))
	var same_shop := func() -> bool:
		return JSON.parse_string(JSON.stringify(shop.capture_state())) == expected
	var saved := RunSaveService.new()
	check(main.load_run_from_path(BRANCH_SAVE) and main.ordinary_shop_open and same_shop.call(), "八折商店正式购买后读档保留完整报价和随机流")
	var checkpoint: Dictionary = saved.load_checkpoint(BRANCH_SAVE).checkpoint
	checkpoint.ordinary_shop_state.erase("bounty_discount")
	checkpoint.short_maze.run.erase("skip_first_day_shop")
	check(saved.save_checkpoint(BRANCH_SAVE, checkpoint) == OK and main.load_run_from_path(BRANCH_SAVE) and same_shop.call(),
		"旧在店存档从赏金猎人状态识别折扣并保留原报价")
	check(maze.leave_shop(true) and not maze.story_shop_discount and maze.run.get_round_kind() == "battle", "读档后可正常离开商店并进入挑战轮")
	checkpoint = saved.load_checkpoint(BRANCH_SAVE).checkpoint
	checkpoint.ordinary_shop_state.erase("bounty_discount")
	check(saved.save_checkpoint(BRANCH_SAVE, checkpoint) == OK and main.load_run_from_path(BRANCH_SAVE) and same_shop.call(),
		"旧离店存档可读取留存的折扣商品，路线已进入挑战轮")


func _test_legacy_edwin_runes() -> void:
	var edwin := _fixture_owned("edwin_ash", "old_gilded_edwin")
	var old := edwin.capture_state()
	for field: String in ["rune_revealed", "rune_scrape_masks", "resolved_runes", "rune_stickers"]:
		old[field] = []
	var save := RunSaveService.new()
	var encoded := save._encode_collection_state({"cards": [old]})
	var decoded := save._decode_collection_state(encoded, {&"edwin_ash": edwin.card_data}, false, false, RunSaveService.SCHEMA_VERSION, false, false)
	check(decoded.success and decoded.state.cards[0].rune_revealed == [false, false, false], "旧埃德温零符文槽档案补出三个未揭晓槽")


func _test_scrolls() -> void:
	_deal("fortuna_gift")
	main.profile_progress.run.enabled_unlocks.packs.append("ironwall_inscription")
	main.apply_run_unlocks()
	check(maze.select_path("fortuna_gift") and maze.complete_event(false, true), "通过随机事件进入强化轮")
	var vending: Dictionary = maze.content.paid_events.filter(func(path: Dictionary) -> bool: return path.path_id == "quest_vending_machine")[0]
	maze.run.paths.clear()
	check(maze.run.set_paths([vending, vending, vending]) and maze.select_path("quest_vending_machine") and maze.choose_story_option(1), "贩卖车选择临时镖客，领取真卡和卷轴")
	var tray: CelestialIndicatorController = main.celestial_indicators
	var items := tray.items.filter(func(item: CelestialIndicator) -> bool: return item.kind == CelestialIndicator.Kind.MERCENARY)
	check(items.size() == 1 and main.owned_card_collection.find_first_by_definition(load("res://resources/cards/mobilization_machine.tres")) != null, "指示物库存保存卷轴，收藏拥有动员机兵")
	if items.is_empty(): return
	var item: CelestialIndicator = items[0]
	item.task_progress = 2
	var owner: OwnedCard = maze._story_minions()[0]
	owner.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 200)
	owner.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 80)
	var team := SquadData.from_owned_card(owner)
	team.attach_indicator(item, Vector2(15, 15), 1)
	var ledger: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/recruitment_ledger.tres"), maze.run.rng)
	team.equip_item(ledger)
	for kind: int in [CelestialIndicator.Kind.CLEANUP, CelestialIndicator.Kind.SUPPLIES]:
		var other := CelestialIndicator.new()
		other.kind = kind as CelestialIndicator.Kind
		other.instance_id = StringName("scroll_fixture_%d" % kind)
		tray.items.append(other)
		team.attach_indicator(other, Vector2(30, 15), kind + 1)
	main.front_row.add_squad(team, 0)
	var helper: OwnedCard = maze._story_minions()[1]
	main.front_row.add_squad(SquadData.from_owned_card(helper), 1)
	check(maze.complete_event(true, true) and maze.run.get_round_kind() == "battle", "带卷轴从首日付费事件进入日末战斗")
	check(maze.select_path(maze.run.paths[0].path_id) and main.start_battle(-1, false), "带卷轴通过正式开战")
	check(main.battle_controller.player_states[0].has_targeting_keyword(&"dazzling"), "临时镖客为佩戴小队提供耀眼")
	var combat: BattleController = main.battle_controller
	var actor := combat.player_states[0]
	var receiver := combat.player_states[1]
	combat.ironwall.add(receiver, BattleModifier.Stat.REINFORCEMENT, 1, &"fixture_support", actor)
	combat.ironwall.add(actor, BattleModifier.Stat.REINFORCEMENT, 1, &"fixture_self", actor)
	combat.ironwall.grant_temporary_emblem(receiver, actor)
	check(int(combat.task_scroll_buffs.get(&"scroll_fixture_3", 0)) == 2 and combat.task_scroll_supplies.get(&"scroll_fixture_5", []).size() == 1, "清扫垃圾只计实际友军增益，丰衣足食记录已发的临时贴纸")
	_finish_test_battle()
	check(combat.task_scroll_supplies.get(&"scroll_fixture_5", []).size() == 3, "丰衣足食只在实际发奖后计入征兵册抽到的两张牌")
	check(tray.items.size() == 2 and maze.last_reward.get("task_scrolls", []).size() == 1, "第三次存活自动完成并仅消耗对应卷轴")
	check(tray.items.any(func(scroll: CelestialIndicator) -> bool: return scroll.kind == CelestialIndicator.Kind.CLEANUP and scroll.task_progress >= 2), "其他卷轴进度随指示物保留")
	check(maze.run.step == ShortMazeRunState.Step.BATTLE_RESULT and main.save_run_to_path(BRANCH_SAVE) == OK and main.load_run_from_path(BRANCH_SAVE), "消耗后的指示物和战后记录可保存恢复")


func _finish_test_battle() -> void:
	for _index: int in 200:
		if main.battle_controller.current_result != BattleController.Result.NONE: break
		main.battle_controller.resolve_next_batch()
	check(main.battle_controller.current_result != BattleController.Result.NONE, "真实战斗完成")
	main.current_phase = main.GamePhase.RESULT
	var settled: Dictionary = main.settle_current_battle(false)
	check(settled.get("success", false), "真实战后事务成功")
	main._restore_battle_result_layout(not settled.get("success", false))


func _fixture_owned(card_id: String, instance_id: String, health: int = 0) -> OwnedCard:
	var result := OwnedCard.new()
	result.initialize(load("res://resources/cards/%s.tres" % card_id), StringName(instance_id), 0)
	result.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, health)
	return result

func _test_secret_missions_and_helmet_save() -> void:
	_deal("fortuna_gift")
	var registry: Dictionary = main._build_card_definition_registry()
	var collection: OwnedCardCollection = main.owned_card_collection
	var helmet := collection.create_card(registry[&"balin_helmet"])
	var item := collection.create_card(registry[&"secret_mission"])
	var wearer: OwnedCard = maze._story_minions()[0]
	var slot: BoardSlot = main.front_row.add_card(wearer.card_data, main.front_row.get_squad_count(), wearer)
	var squad := slot.get_squad_data()
	squad.equip_item(item)
	squad.equip_item(helmet, Vector2(15, 43))
	slot.set_squad_data(squad)
	check(slot.get_equipment_indicator(helmet) != null and slot.get_equipment_indicator(item) != null, "装备与头盔可分别显示指示物")
	item.progress_by_source[OwnedCard.TEMPORARY_EQUIPMENT] = 1
	slot.set_squad_data(squad)
	var card_view := preload("res://scenes/ui/CardView.tscn").instantiate() as CardView
	card_view.set_card_data(item.card_data)
	card_view.set_owned_card(item)
	root.add_child(card_view)
	var indicator_visual := slot.get_equipment_indicator(item).get("_indicator_visual") as TextureRect
	var tint := preload("res://scripts/ui/equipment_indicator_style.gd").TEMPORARY_EQUIPMENT_TINT
	check(card_view.card_frame.self_modulate == tint and indicator_visual.self_modulate == tint, "临时装备完整牌面和场上指示物都带蓝色滤镜")
	card_view.queue_free()
	item.progress_by_source.erase(OwnedCard.TEMPORARY_EQUIPMENT)
	slot.set_squad_data(squad)
	var locked := item.progress_by_source.duplicate(true)
	var id := item.instance_id
	var helmet_id := helmet.instance_id
	check(main.save_run_to_path(BRANCH_SAVE) == OK and main.load_run_from_path(BRANCH_SAVE), "头盔与锁定任务可存档并恢复")
	item = collection.get_by_instance_id(id)
	helmet = collection.get_by_instance_id(helmet_id)
	check(item != null and int(item.progress_by_source.get(OwnedCard.MISSION_GOAL, -1)) == int(locked[OwnedCard.MISSION_GOAL]) and int(item.progress_by_source.get(OwnedCard.MISSION_REWARD, -1)) == int(locked[OwnedCard.MISSION_REWARD]) and item.get_effect_text_for_row(&"front").contains("奖励"), "锁定目标、奖励、进度读档不重投，实例显示任务文案")
	check(main._is_owned_card_deployed(helmet) and main._is_owned_card_deployed(item), "两件装备读档后仍同时部署")
	item.progress_by_source[OwnedCard.MISSION_GOAL] = OwnedCard.MissionGoal.SCRAPERS
	item.progress_by_source[OwnedCard.MISSION_REWARD] = 0
	item.progress_by_source[OwnedCard.MISSION_PROGRESS] = 14
	var gold: int = main.run_reward_state.gold
	main.record_secret_mission_progress(OwnedCard.MissionGoal.SCRAPERS, collection.get_cards())
	maze.resolve_secret_missions()
	maze.resolve_secret_missions()
	check(main.run_reward_state.gold == gold + 50 and collection.get_by_instance_id(id) == null and main._is_owned_card_deployed(helmet), "普通奖励只结算一次，消耗任务但保留独立头盔")
	var locked_reward := collection.create_card(registry[&"secret_mission"])
	locked_reward.progress_by_source[OwnedCard.MISSION_GOAL] = OwnedCard.MissionGoal.PACKS
	locked_reward.progress_by_source[OwnedCard.MISSION_REWARD] = 8
	locked_reward.progress_by_source[OwnedCard.MISSION_PROGRESS] = 5
	main.profile_progress.run.enabled_unlocks.packs.erase("emblem_pack")
	main.ordinary_shop_service.config.sticker_unlocks = {"universal": false, "chaos": true}
	maze.resolve_secret_missions()
	var stickers: Array = main.emblem_library.get_inventory_state()
	check(collection.get_by_instance_id(locked_reward.instance_id) == null and stickers.any(func(sticker: Dictionary) -> bool: return sticker.get("emblem_id") == &"混沌贴纸") and not stickers.any(func(sticker: Dictionary) -> bool: return sticker.get("emblem_id") == &"万能贴纸"), "部分奖励未开放时只发可领的贴纸，任务照常消耗")

func _test_nyx_road_selection() -> void:
	_deal("fortuna_gift")
	var registry: Dictionary = main._build_card_definition_registry()
	var collection: OwnedCardCollection = main.owned_card_collection
	var nyx := collection.create_card(registry[&"nyx_contract_demon"])
	var index := maze._nyx_designated_road()
	check(index >= 0 and main.save_run_to_path(BRANCH_SAVE) == OK and main.load_run_from_path(BRANCH_SAVE) and maze._nyx_designated_road() == index, "指定道路在同轮读档后保持同一位置")
	var path := maze.run.paths[index].duplicate(true) as Dictionary
	for position: int in maze.run.paths.size():
		maze.run.paths[position] = path.duplicate(true)
	maze.run.paths[index]["name"] = "奈克斯指定道路测试"
	check(maze.select_path(path.path_id, index) and maze.run.selected_path.name == "奈克斯指定道路测试", "同名候选按实际点击位置选中相应道路")
	check(nyx.progress_by_source.get(OwnedCard.NYX_ROADS_PROGRESS, 0) == 1, "未部署的奈克斯选择指定道路后进度加一")
