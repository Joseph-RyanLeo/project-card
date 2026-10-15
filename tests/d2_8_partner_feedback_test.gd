extends SceneTree

const MainScene = preload("res://scenes/Main.tscn")
const SentryStyle = preload("res://scripts/ui/sentry_indicator_style.gd")
const Controller = preload("res://scripts/battle/battle_controller.gd")
const Save = preload("res://scripts/data/run_save_service.gd")
var assertions: int = 0
var failures: int = 0
var main: Control

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	main = MainScene.instantiate()
	main.short_maze_enabled = true
	main.run_save_path = "/private/tmp/project-card-partner-feedback.json"
	root.add_child(main)
	await process_frame
	var maze = main.maze_controller
	maze.new_run(1707)
	check(maze.choose_talent("sentry_guard"), "选择天赋进入首日")
	check(maze.run.get_round_kind() == "free_event", "每天先进入随机事件")
	check(maze.select_path(maze.run.paths[0].path_id), "选择随机事件")
	check(maze.complete_event(false), "跳过随机事件")
	check(maze.run.get_round_kind() == "paid_event", "第二轮进入强化事件")
	check(maze.run.paths.size() == 3, "强化轮翻三选一")
	for event: Dictionary in maze.content.paid_events:
		check(event.options.size() == 3 and int(event.options[0].cost) == 0 and int(event.options[1].cost) == 4 and int(event.options[2].cost) == 8, "每个强化事件有免费、4、8金币三档")
	var chosen: Dictionary = maze.run.paths[0]
	check(maze.select_path(chosen.path_id), "选择强化事件")
	main.set_world_view(main.WorldView.COLLECTION, false)
	maze.refresh()
	await process_frame
	check(maze._panel.is_visible_in_tree() and maze._enhancement_slot != null, "收藏视角保留右侧强化卡槽")
	var owned: OwnedCard
	for candidate: OwnedCard in main.owned_card_collection.get_cards():
		if candidate.card_data.card_type == CardData.CardType.MINION:
			owned = candidate
			break
	var data := {"kind": &"card", "owned_card": owned}
	check(maze._enhancement_slot._can_drop_data(Vector2.ZERO, data), "右侧卡槽接受原生随从拖放")
	maze._enhancement_slot._drop_data(Vector2.ZERO, data)
	check(maze._enhancement_card_id == owned.instance_id, "原生卡槽选择拥有的随从实例")
	await capture("enhancement")
	main.run_reward_state.add_gold(20)
	var old_gold: int = main.run_reward_state.gold
	var option: Dictionary = chosen.options[2]
	check(maze.apply_card_enhancement(2), "购买8金币强化")
	check(main.run_reward_state.gold == old_gold - 8, "强化准确扣款")
	for stat: StringName in [OwnedCard.STAT_BASE_VALUE, OwnedCard.STAT_MAX_HEALTH, OwnedCard.STAT_BASE_ARMOR]:
		check(owned.get_permanent_growth(stat) == float(option.get(String(stat), 0)), "强化写入实例永久成长：" + String(stat))
	check(not maze.apply_card_enhancement(2), "已完成强化不能重复领取")
	check(maze.run.get_round_kind() == "shop", "强化后进入商店")
	check(maze.select_path(maze.run.paths[0].path_id), "选择第三轮商店")
	check(main.ordinary_shop_open and main.find_child("SellCardsButton", true, false) != null, "普通商店有出售卡牌服务")
	check(maze.leave_shop(), "离开商店")
	main.ordinary_shop_open = false
	main.ordinary_shop_panel.visible = false
	check(maze.run.get_round_kind() == "battle", "商店后选择战斗")

	# 同名实例堆叠、拆队与存档往返，不改变共享定义。
	var second: OwnedCard = main.owned_card_collection.create_card(owned.card_data)
	check(owned.card_data == second.card_data, "同名卡仍共享定义")
	var left := SquadData.from_owned_card(owned)
	var member := second.get_battlefield_card()
	check(left.can_accept_card_at(member, 1) and left.insert_card(member, 1), "同名不同实例可以堆叠")
	check(left.bind_owned_card(member, second), "同名成员分别绑定实例")
	check(left.get_action_source_instance() == owned and left.get_vitals_source_instance() == second, "同名左右属性来源分别保留")
	var saver := Save.new()
	var encoded: Dictionary = saver._encode_rows({&"player_front": [left], &"player_back": [], &"enemy_front": [], &"enemy_back": []})
	var decoded: Dictionary = saver._decode_rows(JSON.parse_string(JSON.stringify(encoded)), main.owned_card_collection, main._build_card_definition_registry())
	check(decoded.success, "同名小队真实JSON存档读回")
	if decoded.success:
		var restored: SquadData = decoded.rows[&"player_front"][0]
		check(restored.get_card_count() == 2 and restored.get_action_source_instance() == owned and restored.get_vitals_source_instance() == second, "读档不合并同名成员")
	check(left.remove_card(member) and left.get_owned_card(left.get_action_source()) == owned, "拆同名卡只移除目标实例")

	# 新卡标识与检视中的真实数字变化。
	var view: CardView = main.CARD_VIEW_SCENE.instantiate()
	view.set_card_data(second.card_data)
	view.set_owned_card(second)
	root.add_child(view)
	await process_frame
	check(view._new_card_dot.visible, "新卡右上角显示绿点")
	view._on_mouse_entered()
	check(not second.is_new and not view._new_card_dot.visible, "指向后清除新卡绿点")
	main.set_world_view(main.WorldView.COLLECTION, false)
	main._open_card_inspection(owned.card_data, owned)
	await process_frame
	var before_health: String = main._inspection_card_view.health_label.text
	owned.resolved_runes[0] = CardData.ElementType.WATER
	owned.rune_revealed[0] = true
	main._refresh_owned_card_status_visuals(owned)
	check(main._inspection_card_view.health_label.text.to_int() == before_health.to_int() + 2, "收藏检视揭晓水符文立即更新生命")
	check(not main._inspection_card_view._stat_pulse_tweens.is_empty(), "变化数字启动放大缩回动画")
	main._begin_rune_scrape_stroke(Vector2.ZERO)
	main._rune_scrape_locked_index = 0
	var old_scrapers: int = main.scraper_count
	main._end_rune_scrape_stroke()
	check(main._rune_scrape_locked_index == -1 and main.scraper_count == old_scrapers, "松手解锁下一符文且不另扣刮刀")
	main._close_card_inspection(true)

	# 哨位1倍尺寸、天赋提示、自由库存位置及保存。
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	maze.refresh()
	await process_frame
	for variant: int in 4:
		check(SentryStyle.get_texture(variant).get_size() == Vector2(44, 49), "哨位四款裁掉留白并按44×49显示")
	var sentry_id: String = maze.stock[0].instance_id
	check(maze._place_sentry_in_stock(sentry_id, Vector2(91, 100)), "哨位可在库存自由重放")
	check(maze.stock[0].stock_position == [69.0, 75.5], "自由位置以图标中心对齐落点并保存")
	var saved := JSON.parse_string(JSON.stringify(maze.capture_state())) as Dictionary
	check(maze.validate_state(saved), "自由哨位位置保存后通过正式校验")
	check(maze.drop_sentry_at(sentry_id, main.front_row.get_global_rect().get_center()), "库存哨位可部署前排")
	var sentry_view: Control = maze._sentry_views.front
	check(sentry_view.size == Vector2(44, 49) and sentry_view.tooltip_text.contains("护"), "哨位大小与英雄护天赋提示正确")
	var destination := Vector2(main.front_row.size.x - 44, 0)
	await create_timer(0.4).timeout
	check(sentry_view.position.is_equal_approx(destination), "部署动画最终移动到右上角")
	for region: String in ["back", "spells"]:
		var zone: Control = maze._sentry_zones[region]
		check(maze.drop_sentry_at(sentry_id, zone.get_global_rect().get_center()), "哨位可移动到" + region)
		var moved: Control = maze._sentry_views[region]
		var target := Vector2.ZERO if region == "spells" else Vector2(zone.size.x - 44, 0)
		await create_timer(0.4).timeout
		check(moved.position.is_equal_approx(target), "哨位移动动画正确落在" + region)
	check(maze.hero_description().contains("当前等级：1") and maze.hero_description().contains("累计经验") and maze.hero_description().contains("护"), "英雄提示包含等级经验与所选强化")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	main.player_avatar_button.gui_input.emit(right_click)
	var hero_popup: AcceptDialog
	for child: Node in main.get_children():
		if child is AcceptDialog and child.title == "英雄当前状态":
			hero_popup = child
	check(hero_popup != null and hero_popup.visible and hero_popup.dialog_text == maze.hero_description(), "英雄右键信号打开真实状态提示窗")
	if hero_popup != null:
		hero_popup.queue_free()

	# 结算切换只改变界面，不改日志和奖励。
	check(maze.select_path(maze.run.paths[0].path_id), "选择真实敌人验证结算页面")
	owned.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 100.0)
	owned.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300.0)
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	check(main.start_battle(1707, false), "真实战斗开战")
	var batches := 0
	while main.battle_controller.current_result == Controller.Result.NONE and batches < 1200:
		main.battle_controller.resolve_next_batch()
		batches += 1
	check(main.battle_controller.current_result != Controller.Result.NONE, "真实战斗完成")
	main._show_battle_result(main.battle_controller.current_result)
	check(maze.run.step == ShortMazeRunState.Step.BATTLE_RESULT, "实际奖励提交后进入结算")
	var result_gold: int = main.run_reward_state.gold
	main._set_result_battlefield_visible(true)
	check(not main.battle_result_panel.visible and main._return_to_result_button.visible, "查看战场隐藏结算并显示返回按钮")
	main._set_result_battlefield_visible(false)
	check(main.battle_result_panel.visible and not main._return_to_result_button.visible and main.run_reward_state.gold == result_gold, "返回结算不重复领奖")
	await capture("result")
	check(main.battle_result_panel.get_rect().get_center().is_equal_approx(Vector2(640, 360)), "结算页位于屏幕中央")
	check(main._return_to_result_button.get_rect().get_center().is_equal_approx(Vector2(640, 360)), "返回结算按钮位于屏幕中央")
	for pair: Array in [[CardData.ActionType.MELEE, 8], [CardData.ActionType.RANGED, 4], [CardData.ActionType.MAGIC, 6], [CardData.ActionType.HEAL, 2], [CardData.ActionType.DEFENSE, 10]]:
		check(CardData.get_base_target_priority_for_action(pair[0]) == pair[1], "五种默认优先级翻倍")
	view.queue_free()
	main.queue_free()
	await process_frame
	print("合作伙伴反馈专项：%d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func capture(label: String) -> void:
	if "capture" not in OS.get_cmdline_user_args():
		return
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var output := "/private/tmp/project-card-partner-%s.png" % label
	check(root.get_texture().get_image().save_png(output) == OK, "保存原生窗口预览：" + label)
