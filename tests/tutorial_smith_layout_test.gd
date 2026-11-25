extends "res://tests/militia_keyword_tutorial_test.gd"

## 只走首战至第二天铁匠，验证真实事件、保存事务、卡牌对白与避让布局。
const LAYOUT_DIR := "/private/tmp/project-card-tutorial-smith-layout-test"


func capture_pack(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(LAYOUT_DIR.path_join(label + ".png"))


func check_bottom_left(hint: Control, message: String) -> void:
	check(is_equal_approx(hint.panel.position.x, 12) and absf(hint.panel.get_rect().end.y - 708) <= 1, message + "固定在左下角")
	check(hint._surface.get_children().all(func(child: Node): return not child is ColorRect), message + "不添加暗幕")


func _run() -> void:
	if "toolbox-only" in OS.get_cmdline_user_args():
		await _run_toolbox_only()
		return
	create_timer(110).timeout.connect(func(): push_error("铁匠与教学布局专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(LAYOUT_DIR)
	Effects.load_saved(LAYOUT_DIR.path_join("effects.cfg"))
	Effects.reset_defaults()
	TextSettings.load_settings(LAYOUT_DIR.path_join("card-text.cfg"))
	TextSettings.set_mode(self, TextSettings.Mode.CARD, false)
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = LAYOUT_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await frames()
	check(await shell.start_slot(0), "创建隔离布局测试档")
	check(shell.slot_progress.select_catalog_tasks("tutorial", "") and await shell.start_new_slot_run(), "正式进入教程")
	main = shell.main_screen
	var maze = main.maze_controller
	while shell.screen_transition.busy: await process_frame
	if is_instance_valid(maze._initial_pack_drop): await maze._initial_pack_drop.finished
	check(main.save_profile_action(func():
		for id: String in ["supplies", "event_reward", "shop_route", "shop_entered", "first_victory"]:
			main.profile_progress.record_hint_read("tutorial:step:" + id, TaskCatalog.tutorial_hint(id), {"story": true, "teaching": true})
		return true), "夹具略过已验证的开包、选路对白")
	check(maze.open_task_supply(), "通过初始包实际获得卡牌")
	await create_timer(0.7).timeout
	main._card_pack_opening.auto_tear()
	await create_timer(1.0).timeout
	main._close_card_inspection(true)
	await create_timer(0.4).timeout
	while not maze.hero.pending_talent_levels.is_empty(): maze.choose_talent(String(maze.hero.get_pending_choices()[0]))
	while maze.run.get_round_kind() != "battle":
		check(maze.select_path(String(maze.run.paths[0].path_id)), "正式选择首战前事件")
		if maze.run.get_round_kind() == "shop":
			if is_instance_valid(main._shop_open_tween) and main._shop_open_tween.is_running(): await main._shop_open_tween.finished
			await click_control(main._shop_leave_button)
		elif maze.run.round_index == 0:
			check(String(maze.run.selected_path.path_id).begins_with("tutorial_fortuna_"), "教程首个事件固定为福尔图纳的馈赠")
			check(main.get_node_or_null("TaskHint") == null, "首个事件不再显示点牌堆教学")
			var before_gold: int = main.run_reward_state.gold
			var cards_before: int = main.owned_card_collection.size()
			await frames()
			if is_instance_valid(maze._event_table._text_reveal) and maze._event_table._text_reveal.is_running(): await maze._event_table._text_reveal.finished
			var choice: Button
			for button: Node in maze._detail_body.find_children("*", "Button", true, false):
				if button.text == "捡起来打开": choice = button
			await click_control(choice)
			var result: Dictionary = maze.run.selected_path.story_result
			check(int(result.roll) in range(1, 9) and main.run_reward_state.gold == before_gold + 15 and main.owned_card_collection.size() == cards_before, "真实掷骰只出1到8，恰好发15金币")
			check(is_instance_valid(maze._story_roll) and maze._story_roll._result == int(result.roll) and not maze.complete_event(true, true), "投掷演出使用已提交点数，播放时不能跳过结果")
			await capture_pack("29_fortuna_dice")
			if is_instance_valid(maze._story_roll): await maze._story_roll.finished
			check(maze.validate_state(maze.capture_state()) and not maze.choose_story_option(0), "已掷点数通过存档校验且不能重复领奖")
			check(maze.complete_event(true, true), "查看钱袋结果后正式继续")
		else:
			check(maze.complete_event(false, true), "正式完成其他前置事件")
	var legacy_choices: Dictionary = maze.capture_state()
	for path: Dictionary in legacy_choices.run.paths: path.front = ["militia"]
	check(maze.validate_state(legacy_choices), "换敌阵前保存的首战候选仍可读取")
	check(maze.select_path(String(maze.run.paths[0].path_id)), "进入实际首战准备")
	var foes: Array[BoardSlot] = main.enemy_front_row.get_squads()
	check(foes.size() == 2 and main.enemy_back_row.get_squad_count() == 0, "首战前排是两个独立敌方小队")
	if foes.size() == 2:
		var wailer := foes[0].get_squad_data().get_owned_card(foes[0].get_squad_data().horizontal_cards[0])
		check(wailer.card_data.id == &"mine_wailer" and wailer.wound_slots[0].wound_id == &"光血" and foes[1].get_squad_data().horizontal_cards[0].id == &"minecart_soul", "首战遭遇实例包含光血矿道哀嚎者和矿车亡魂")
	await expected_hint("deploy_view")
	await click_control(main.player_avatar_button)
	var hint := await expected_hint("deploy")
	await frames()
	check_bottom_left(hint, "部署教程")
	await capture_pack("19_deploy_bottom_left")
	var shield: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/shieldwall_private.tres"))
	check(main._transfer_card({"kind": &"card", "source_type": &"collection", "card_data": shield.card_data, "owned_card": shield}, &"board", main.front_row), "正式部署第一个随从")
	hint = await expected_hint("militia_inspect")
	await frames()
	var militia_view: CardView = maze._find_tutorial_card_view(&"militia")
	var militia_rect: Rect2 = maze._hint_control_rect(militia_view)
	check(hint.panel.position.x >= militia_rect.end.x + 10 and not hint.panel.get_rect().intersects(militia_rect), "检视教学贴到实际民兵卡右侧")
	check(main.collection_viewport.get_global_rect().encloses(hint.panel.get_rect()), "民兵右侧空白处容纳完整提示")
	await capture_pack("20_inspect_beside_militia")
	await right_click(militia_view)
	hint = await expected_hint("militia_keywords")
	await frames()
	check(is_equal_approx(hint.panel.get_rect().end.x, 1268.0) and is_equal_approx(hint.panel.get_rect().end.y, 708.0), "关键词介绍移到检视的右下角")
	await key_escape()
	hint = await expected_hint("militia_neighbor")
	await frames()
	check_bottom_left(hint, "乡邻站位教程")
	for id: String in ["militia", "town_priest", "musketeer"]:
		var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/%s.tres" % id))
		var row: BattlefieldRow = main.back_row if id == "musketeer" else main.front_row
		check(main._transfer_card({"kind": &"card", "source_type": &"collection", "card_data": owned.card_data, "owned_card": owned}, &"board", row, row.get_squad_count()), "真实部署：" + id)
	hint = await expected_hint("battle_ready")
	await frames()
	check_bottom_left(hint, "继续布阵教程")
	var row: BattlefieldRow = main.front_row
	var source: BoardSlot = row.get_squads()[1]
	var target: BoardSlot = row.get_squads()[0]
	var member: CardData = source.get_squad_data().horizontal_cards[0]
	var drag := {"kind": &"card", "source_type": &"board", "source_row": row, "source_slot": source, "squad_data": source.get_squad_data(), "card_data": member}
	var target_x := row._get_slot_visual_rect(target).get_center().x
	check(row._build_drop_intent(Vector2(target_x, 65), drag).get("operation") == &"new_squad", "首战叠卡位置只生成独立部署预览")
	drag["drop_intent"] = row._build_merge_intent(target, target_x, drag)
	check(not drag.drop_intent.is_empty() and not main._transfer_drop_intent(drag, row), "首战拒绝提交已生成的合法叠卡意图")
	await click_control(main.start_battle_button)
	hint = await expected_hint("battle_intro")
	check(paused and hint.instruction_label.text.contains("行动冷却") and not hint.instruction_label.text.contains("伤势"), "首战第一段只讲行动、胜利与失败")
	check(hint.find_child("HintTargetOutline", true, false) == null, "第一段不框选我方战场")
	var battle_time: float = main.battle_controller.elapsed_seconds
	await click_control(main.front_row)
	hint = await expected_hint("battle_retreat")
	var wailer: CardView = maze._battle_intro_card()
	check(paused and hint.instruction_label.text.contains("生命值降到 0") and hint.focus_rect.encloses(wailer.get_global_rect()), "第二段讲退场并高亮矿道哀嚎者")
	await capture_pack("15_battle_intro_paused")
	await right_click(wailer)
	hint = await expected_hint("battle_wounds")
	check(is_instance_valid(main._inspection_overlay) and hint.instruction_label.text.contains("稀有度"), "右键检视后才显示第三段伤势说明")
	await create_timer(0.35).timeout
	check(main._gameplay_teaching_toast.current_key == "tutorial:step:wounds" and main._gameplay_teaching_toast.progress > 0, "战斗暂停时仍能弹出伤势玩法教学")
	await capture_pack("30_battle_wounds_inspection")
	await click_control(main._gameplay_teaching_toast.title_label)
	check(main._escape_pause_menu.is_teaching_book_open() and main._escape_pause_menu.selected_teaching_key == "tutorial:step:wounds", "伤势提示直达独立教程书的对应条目")
	await key_escape()
	check(not main._escape_pause_menu.is_teaching_book_open() and is_instance_valid(main._inspection_overlay), "首次Esc关闭教程并保留卡牌检视")
	await key_escape()
	hint = await expected_hint("battle_protection")
	check(paused and hint.focus_rect == maze._status.life_track_rect(), "退出检视后高亮失败保护与生命值")
	await click_control(main.front_row)
	hint = await expected_hint("battle_playback")
	check(paused and hint.focus_rect.encloses(main.battle_speed_bar.get_global_rect()) and is_equal_approx(battle_time, main.battle_controller.elapsed_seconds), "最后高亮播放条，教学期间战斗时间轴保持暂停")
	await click_control(main.battle_speed_bar.buttons[2])
	check(paused, "必须点击继续才结束首战教学")
	await click_control(main.battle_speed_bar.buttons[1])
	check(not paused and not maze._battle_intro_pending(), "点击真实继续按钮后恢复战斗")

	var batches := 0
	while main.battle_controller.current_result == BattleController.Result.NONE and batches < 10000:
		main.battle_controller.resolve_next_batch()
		batches += 1
	check(main.battle_controller.current_result == BattleController.Result.PLAYER_VICTORY, "用真实阵容完成首战，不改敌人或属性")
	if main.current_phase != main.GamePhase.RESULT: main._show_battle_result(main.battle_controller.current_result)
	while not maze.hero.pending_talent_levels.is_empty(): maze.choose_talent(String(maze.hero.get_pending_choices()[0]))
	check(maze.continue_after_battle(true), "正式进入第二天")
	await create_timer(0.5).timeout
	check(not main.profile_progress.run.tasks.main.progress.get("smith_received", false) and main.owned_card_collection.find_first_by_definition(load("res://resources/cards/anvil_margaret.tres")) == null, "进入第二天不提前自动赠送玛格丽特")
	check(maze.run.paths.size() == 3 and maze.run.paths.all(func(path: Dictionary): return path.reward == "tutorial_smith" and path.name == "找到铁匠"), "第二天首次三个候选必定都是找到铁匠事件")
	check(maze.validate_state(maze.capture_state()), "三张独立路径使用同一事件，存档通过正式校验")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await click_control(maze._event_table._deck)
	if maze._event_table.busy: await maze._event_table.choices_ready
	await capture_pack("21_three_smith_events")
	var original_save_path: String = main.run_save_path
	var blocked := LAYOUT_DIR.path_join("blocked-parent")
	var file := FileAccess.open(blocked, FileAccess.WRITE)
	file.store_string("用于实际保存失败测试")
	file.close()
	main.run_save_path = blocked.path_join("run.json")
	check(not maze.select_path(String(maze.run.paths[0].path_id)), "真实保存失败时拒绝提交铁匠奖励")
	main.run_save_path = original_save_path
	check(not main.profile_progress.run.tasks.main.progress.get("smith_received", false) and main.owned_card_collection.find_first_by_definition(load("res://resources/cards/anvil_margaret.tres")) == null and maze.run.step == maze.RunState.Step.CHOOSING, "失败回退事件选择、卡牌与无限刮刀资格")
	await click_control(maze._event_table._deck)
	if maze._event_table.busy: await maze._event_table.choices_ready
	await click_control(maze._event_table.cards[1])
	hint = await expected_hint("smith")
	var margaret_view: CardView = maze._find_tutorial_card_view(&"anvil_margaret")
	check(is_instance_valid(margaret_view) and main.front_row.get_squads().any(func(slot: BoardSlot): return slot.get_card_views().has(margaret_view)), "选中铁匠事件后玛格丽特直接上场")
	check(hint.speech._speaker == margaret_view and hint.speech.text_label.text == hint.content.dialogue[0].text, "第一句从玛格丽特卡牌发出，不混在教学框里")
	check(hint.find_child("OtherDialogue", true, false) == null, "玛格丽特台词没有在说明框重复显示")
	await create_timer(0.5).timeout
	await capture_pack("22_margaret_card_dialogue")
	for line_index: int in [1, 2]:
		for index: int in 180:
			if hint._hero_line_index == line_index: break
			await create_timer(0.1).timeout
		var expected: Control = main.player_avatar_button if line_index == 1 else margaret_view
		check(hint._hero_line_index == line_index and hint.speech._speaker == expected and hint.speech.text_label.text == hint.content.dialogue[line_index].text, "两人按原文次序交替使用各自气泡：%d" % line_index)
	check(not is_instance_valid(maze._scraper_handoff), "最后一句尚在说话时不提前抛出刮刀")
	for index: int in 180:
		if is_instance_valid(maze._scraper_handoff): break
		await create_timer(0.05).timeout
	var flight: Control = maze._scraper_handoff
	check(is_instance_valid(flight) and flight.source == margaret_view and flight.target == main.emblem_library._scraper, "玛格丽特最后一句自然读完后，刮刀从她的卡牌飞出")
	check(main.profile_progress.run.read_story_nodes.has("tutorial:step:smith"), "自然读完后保存本局剧情已阅")
	await create_timer(0.55).timeout
	check(main.current_world_view == main.WorldView.COLLECTION and flight.icon.position.x < margaret_view.global_position.x, "刮刀离开卡面后自动下移视角并向左侧工具栏飞行")
	await capture_pack("24_scraper_handoff")
	hint = await expected_hint("smith_tools")
	check(not is_instance_valid(maze._scraper_handoff) and main.emblem_library._scraper.visible and main.profile_progress.run.tasks.main.progress.tutorial_actions.get("smith_scraper_delivered", false), "刮刀落入工具栏后才提示检视，并保存交接完成")
	check(maze.complete_event(true, true), "铁匠事件可继续，奖励不会重复领取")
	var checkpoint := LAYOUT_DIR.path_join("after-smith.json")
	check(main.save_run_to_path(checkpoint) == OK and main.load_run_from_path(checkpoint), "领取后真实保存读档")
	await create_timer(0.5).timeout
	check(main.get_node_or_null("TaskHint").get_meta("hint_key") == "tutorial:step:smith_tools" and not is_instance_valid(maze._scraper_handoff) and main.owned_card_collection.get_cards().filter(func(card: OwnedCard): return card.card_data.id == &"anvil_margaret").size() == 1, "同局读档不重播已阅对白、不重复发卡")
	await expected_hint("smith_tools")
	await _verify_toolbox()
	shell.free()
	print("Tutorial smith/layout: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _verify_toolbox() -> void:
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await frames()
	await right_click(main.maze_controller._find_tutorial_card_view(&"anvil_margaret"))
	check(is_instance_valid(main._inspection_overlay), "真实右键上场的玛格丽特进入检视")
	var hint := await expected_hint("scraper_inspection")
	await frames()
	check(hint.panel.position == Vector2(12, 64), "刮刀教程位于左上角")
	await click_control(main._inspection_library_toggle)
	await frames()
	var effect_box: PanelContainer = main._inspection_overlay.get_node("InspectionEffectSideBox")
	var visible_card := Rect2(main._inspection_surface.position + main._inspection_surface.content_padding * main._inspection_surface.scale, main._inspection_card_view.card_size * main._inspection_surface.scale)
	print("LAYOUT: card=", visible_card, " effect=", effect_box.get_rect(), " hint=", hint.panel.get_rect())
	check(not effect_box.get_rect().intersects(visible_card) and effect_box.position.x >= main._inspection_overlay.size.x, "展开工具箱时原说明滑出画面右侧")
	var scraper_rect: Rect2 = main.maze_controller._hint_control_rect(main.emblem_library._scraper)
	check(not hint.panel.get_rect().intersects(scraper_rect), "左上提示不遮挡展开工具箱中的刮刀")
	await capture_pack("23_toolbox_hint_and_card")
	await click_control(main.emblem_library._scraper)
	check(main._rune_scraper_mode and (not is_instance_valid(hint) or hint._teaching_done), "实际点击刮刀后教学自动淡出，无需确认按钮")


func _run_toolbox_only() -> void:
	create_timer(45).timeout.connect(func(): push_error("工具箱专项超时"); quit(1))
	Effects.load_saved(LAYOUT_DIR.path_join("effects.cfg"))
	TextSettings.load_settings(LAYOUT_DIR.path_join("card-text.cfg"))
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = LAYOUT_DIR
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await frames()
	check(await shell.start_slot(0), "恢复本专项刚生成的隔离铁匠存档")
	main = shell.main_screen
	check(main.load_run_from_path(LAYOUT_DIR.path_join("after-smith.json")), "恢复刮刀教学尚未阅读的实际检查点")
	await frames()
	await expected_hint("smith_tools")
	await _verify_toolbox()
	shell.free()
	print("Toolbox layout: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
