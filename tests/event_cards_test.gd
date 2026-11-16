extends SceneTree

## 使用正式显示壳、真实输入、磁盘存档和奖励服务验证事件牌。
const DISPLAY = preload("res://scenes/GameDisplay.tscn")
const StoryService = preload("res://scripts/data/maze_story_event_service.gd")
const TarotBacks = preload("res://scripts/data/event_tarot_backs.gd")
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
	# 沿用旧事件名的界面专项显式开启其夹具，正式事件专项仍测试新池。
	if get_script().resource_path != "res://tests/event_cards_test.gd" and id in ["loose_coins", "ioann_prayer"]:
		maze.story_events.config.appearance[id] = {"floors": [1], "formal": true}
		for path: Dictionary in maze.content.paid_events:
			if path.get("reward") == "story": maze.story_events.config.appearance[path.path_id].pending = true
	for seed_value: int in range(1, 100):
		maze.new_run(seed_value)
		# 随机池专项从固定首轮之后开始取样。固定事件另有独立回归。
		if id != "so_close": maze.seen_events.append("so_close")
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
	create_timer(45).timeout.connect(func(): push_error("事件卡片专项超时"); quit(1))
	if DisplayServer.get_name() != "headless": await _test_native_tarot_back()
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
	check(not service.can_appear(prayer, 0, 1, "ioann_warden") and service.can_appear(prayer, 0, 3, "other_hero"), "正式祈愿限制第三层且排除伊奥恩")
	check(not service.can_appear(casino, 4, 1, "ioann_warden") and service.can_appear(casino, 5, 1, "ioann_warden"), "赌坊仍要求至少5金币")
	check(service.can_appear({"path_id": "fortuna_gift"}, 0, 4, "ioann_warden"), "正式福尔图纳可以在额外半层出现")
	# 保留祈愿、白骨塔原有界面回归，只对本测试实例放开出现条件。
	maze.story_events.config.appearance.ioann_prayer = {"floors": [1], "formal": true}
	maze.story_events.config.appearance.bone_tower = {"floors": [1], "formal": true}
	var chosen_index := _deal("ioann_prayer")
	await create_timer(0.6).timeout
	await _click(maze._event_table._deck)
	if maze._event_table.busy: await maze._event_table.choices_ready
	check(chosen_index >= 0 and maze._event_table.cards.size() == 3, "实际牌桌发出三张候选")
	if chosen_index < 0 or maze._event_table.cards.size() != 3:
		quit(1)
		return
	for card: EventCardView in maze._event_table.cards:
		check(not card.face_up and card.tooltip_text.is_empty(), "选中前不泄漏名称和事件详情")
	var tarot: Texture2D = maze._event_table.cards[chosen_index].tarot_back
	check(tarot != null and tarot.resource_path.get_file().get_basename() in ["sun", "star", "moon"], "正式候选显示事件配置的塔罗牌背")
	check(maze._event_table.find_child("EventHint*", true, false) == null, "三选一不再附带旧文字暗示")
	var deck_top: EventCardView = maze._event_table.find_child("DeckTopCard", true, false)
	check(deck_top.tarot_back == maze._event_table.cards[0].tarot_back, "中央牌堆与首张候选使用相同牌背")
	if deck_top.tarot_back != null:
		var deck_art := deck_top.get_parent().get_child(0) as TextureRect
		check(deck_art.texture is AtlasTexture and deck_art.position.y == EventCardView.CARD_SIZE.y, "中央牌堆的旧顶牌只留下下方叠牌厚度")
	var paths := maze.run.paths.duplicate(true)
	var rng_state := maze.run.rng.state
	maze.refresh()
	maze.refresh()
	check(maze.run.paths == paths and maze.run.rng.state == rng_state, "刷新不重抽候选或消耗随机源")
	check(maze._event_table.cards[chosen_index].tarot_back == tarot, "同一轮刷新保留塔罗牌背")
	await process_frame
	await _capture("backs")
	check(main.save_run_to_path(SAVE_PATH) == OK and main.load_run_from_path(SAVE_PATH), "可保存并恢复已发牌的轮次")
	await create_timer(0.6).timeout
	if maze._event_table.cards.is_empty():
		await _click(maze._event_table._deck)
		if maze._event_table.busy: await maze._event_table.choices_ready
	check(maze._event_table.cards[chosen_index].tarot_back == tarot, "读档重建候选后仍显示相同塔罗牌背")
	var card: Button = maze._event_table.cards[chosen_index]
	await _click(card)
	await create_timer(1.6).timeout
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
	for path: Dictionary in maze.content.paid_events:
		if path.get("reward") == "story" and path.path_id != "roaming_smith":
			maze.story_events.config.appearance[path.path_id].pending = true
	check(maze.complete_event() and maze.run.get_round_kind() == "paid_event", "领取后继续到强化轮")
	var smith: Dictionary = maze.content.paid_events.filter(func(path: Dictionary) -> bool: return path.path_id == "roaming_smith")[0]
	maze.run.paths.clear()
	check(maze.run.set_paths([smith, smith, smith]) and maze.select_path("roaming_smith"), "第二个事件位可以打开锤游匠人的强化槽")
	check(is_instance_valid(maze._enhancement_slot), "右侧保留原有强化卡槽")
	var trainee: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	var trainee_id := trainee.instance_id
	check(maze.select_enhancement_card({"kind": &"card", "owned_card": trainee}), "右侧强化卡槽接收真实收藏卡")
	await process_frame
	await _capture("enhancement")
	var armor_before := trainee.get_permanent_growth(OwnedCard.STAT_BASE_ARMOR)
	check(maze.choose_story_option(0), "锤游匠人从右侧卡槽给指定随从强化")
	trainee = main.owned_card_collection.get_by_instance_id(trainee_id)
	check(trainee.get_permanent_growth(OwnedCard.STAT_BASE_ARMOR) == armor_before + 2, "强化永久写入原有单卡实例")
	check(maze.complete_event(true, true), "读完强化结果后进入商店轮")
	check(maze.select_path(maze.run.paths[0].path_id) and main.ordinary_shop_open, "选择商店牌后打开真实商店")
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
	check(is_instance_valid(maze._story_roll) and maze._story_roll._result == int(result.roll), "普通骰子也播放已提交点数")
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
	_deal("fortuna_gift")
	check(maze.select_path("fortuna_gift"), "正式福尔图纳可从事件池选择")
	if maze.run.selected_path.get("path_id") == "fortuna_gift":
		var owned_before: int = main.owned_card_collection.size()
		var gold_before: int = main.run_reward_state.gold
		var fortune_rng := RandomNumberGenerator.new()
		for seed_value: int in range(1, 100):
			fortune_rng.seed = seed_value
			var state := fortune_rng.state
			if fortune_rng.randi_range(1, 10) == 10:
				maze.run.rng.state = state
				break
		check(maze.choose_story_option(0), "正式福尔图纳可提交10点奖励")
		check(maze.run.selected_path.story_result.roll == 10 and main.run_reward_state.gold == gold_before + 15 and main.owned_card_collection.size() >= owned_before + 8, "正式10点发15金币和一大一小两包")
		check(main.load_run_from_path(SAVE_PATH) and maze.run.selected_path.story_result.roll == 10 and not maze.choose_story_option(0), "读档保留福尔图纳点数，拒绝重复开奖")
	var repeated := ShortMazeRunState.new()
	repeated.initialize(2)
	repeated.commit_day_start()
	var only_event: Dictionary = maze.content.free_events.filter(func(path: Dictionary) -> bool: return path.path_id == "fortuna_gift")[0]
	check(repeated.set_paths([only_event, only_event, only_event]) and repeated.restore_state(repeated.capture_state()), "合格事件仅一种时允许三张重复并可恢复")
	var slave_backs := {}
	for seed_value: int in 64:
		var back := TarotBacks.pick({"path_id": "slave_trader"}, str(seed_value))
		slave_backs["%s:%s" % [back.texture.resource_path.get_file(), back.reversed]] = true
	check(slave_backs.has("devil.png:false") and slave_backs.has("devil.png:true") and slave_backs.has("strength.png:false"), "奴隶贩子牌背包含恶魔正逆与力量正位")
	_deal("bounty_hunter")
	check(maze.select_path("bounty_hunter"), "赏金猎人从正式候选进入事件")
	var wanted := maze._story_locked_target(0)
	if wanted != null:
		var wanted_id := wanted.instance_id
		var cost: int = main._shop_card_sale_price(wanted) + 5
		check(main.load_run_from_path(SAVE_PATH) and maze._story_locked_target(0).instance_id == wanted_id, "赏金目标读档不重选")
		check(maze.choose_story_option(2) and main.run_reward_state.gold == 30 - cost and main.owned_card_collection.get_by_instance_id(wanted_id) != null, "贿赂只扣售价加5金币，保留目标")
	else:
		check(false, "赏金目标必须为仍拥有的随从实例")
	check(maze.complete_event(true, true), "赏金分支结算后进入当日强化轮")
	var alchemist: Dictionary = maze.content.paid_events.filter(func(path: Dictionary) -> bool: return path.path_id == "alchemist")[0]
	maze.run.paths.clear()
	check(maze.run.set_paths([alchemist, alchemist, alchemist]) and maze.select_path("alchemist"), "通过正式选牌进入炼金师")
	main.run_reward_state.gold = 30
	check(maze.choose_story_option(2) and main.run_reward_state.gold == 23, "7金币购买完美合剂")
	var elixir: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/event_potion_15.tres"))
	check(elixir != null and elixir.card_data.rarity == CardData.Rarity.III, "完美合剂是III级真实装备实例")
	if elixir != null:
		var owner: OwnedCard = main.owned_card_collection.get_cards()[0]
		# 本夹具让佩戴者撑过敌方开场法术，以验证之后的突击窗口。
		owner.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 100)
		var squad := SquadData.from_owned_card(owner)
		check(squad.equip_item(elixir), "完美合剂可装备到随从")
		main.front_row.add_squad(squad, 0)
		check(maze.complete_event(true, true) and maze.select_path(maze.run.paths[0].path_id) and maze.leave_shop(true), "带合剂通过商店进入战斗轮")
		check(maze.select_path(maze.run.paths[0].path_id) and main.start_battle(-1, false), "合剂随从进入正式战斗")
		while main.battle_controller._opening_spell_active:
			main.battle_controller.resolve_next_batch()
		var effects: Array[Dictionary] = main.battle_controller.owned_card_change_ledger.get_entries()
		check(effects.any(func(entry: Dictionary) -> bool: return entry.kind == &"consume_equipment" and entry.owned_card_instance_id == elixir.instance_id), "突击将合剂消耗记入正式战后账本")
		var growth: Array[Dictionary] = main.battle_controller.permanent_growth_ledger.get_entries()
		check(growth.size() >= 3 and effects.any(func(entry: Dictionary) -> bool: return entry.parameters.get("counter_key") == &"event_potion_zeal"), "合剂登记数值、生命、护甲及热诚永久变化")
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


func _test_native_tarot_back() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(EventCardView.CARD_SIZE) * 2
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var card := EventCardView.new()
	card.disabled = true
	viewport.add_child(card)
	card.pivot_offset = Vector2.ZERO
	card.scale = Vector2(2, 2)
	var size := Vector2i(EventCardView.CARD_SIZE)
	var source_rect := Rect2i(Vector2i(44, 23), size)
	var card_rect := Rect2i(Vector2i.ZERO, size)
	var flat_back := EventCardView.BACK.get_image()
	var frame_color := Color("8c692b")
	var brown := flat_back.get_pixelv(Vector2i(EventCardView.CARD_SIZE * 0.5))
	for y: int in size.y:
		for x: int in size.x:
			if flat_back.get_pixel(x, y) == frame_color:
				flat_back.set_pixel(x, y, brown)
	for tarot_id: String in TarotBacks.CARD_IDS:
		card.tarot_back = load(TarotBacks.ART_DIRECTORY + tarot_id + ".png") as Texture2D
		var artwork := card.tarot_back.get_image()
		check(source_rect.encloses(artwork.get_used_rect()), "%s 的有效像素完整落在统一底板范围" % tarot_id)
		var overlay := artwork.get_region(source_rect)
		for reverse: bool in [false, true]:
			card.tarot_reversed = reverse
			card.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var actual := viewport.get_texture().get_image()
			if reverse: overlay.rotate_180()
			var expected := flat_back.duplicate() as Image
			expected.blend_rect(overlay, card_rect, Vector2i.ZERO)
			expected.resize(viewport.size.x, viewport.size.y, Image.INTERPOLATE_NEAREST)
			var mismatches := 0
			for y: int in actual.get_height():
				for x: int in actual.get_width():
					var pixel := actual.get_pixel(x, y)
					var source := expected.get_pixel(x, y)
					# 透明角落的 RGB 不参与显示。
					if pixel != source and (pixel.a > 0.0 or source.a > 0.0): mismatches += 1
			check(mismatches == 0, "%s %s按统一位置叠在去掉金色内框的棕色底板上，2倍放大保留原生像素" % [tarot_id, "逆位" if reverse else "正位"])
	viewport.queue_free()
