extends SceneTree

## 真实主场景验证战后快照、召唤统计分类和按钮输入，不使用 mock。
const MAIN := preload("res://scenes/Main.tscn")
const DISPLAY := preload("res://scenes/GameDisplay.tscn")
const SAVE_PATH := "/private/tmp/project-card-result-summons-save.json"
var assertions := 0
var failures := 0
var shell: Control

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("战况专项超时"); quit(2))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	print("PASS: " if value else "FAIL: ", message)
	if not value:
		failures += 1

func new_main():
	var main: Control
	if "--2k" in OS.get_cmdline_user_args():
		shell = DISPLAY.instantiate()
		main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	else:
		main = MAIN.instantiate()
	main.short_maze_enabled = false
	main.run_save_path = SAVE_PATH
	root.add_child(shell if is_instance_valid(shell) else main)
	await process_frame
	if is_instance_valid(shell):
		shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
		for index: int in 6: await process_frame
		check(root.size == Vector2i(2560, 1440), "真实2K窗口尺寸")
	await process_frame
	for row in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]:
		row.clear_squads()
	return main

func main_to_screen(point: Vector2) -> Vector2:
	return shell.render_container.get_global_transform_with_canvas() * point if is_instance_valid(shell) else point

func free_main(main) -> void:
	if is_instance_valid(shell):
		shell.queue_free()
		shell = null
	else:
		main.queue_free()
	await process_frame

func deploy(main, row: BattlefieldRow, id: String, player: bool = true) -> OwnedCard:
	var owned: OwnedCard
	var definition: CardData = load("res://resources/cards/%s.tres" % id)
	if player:
		owned = main.owned_card_collection.create_card(definition)
	else:
		owned = OwnedCard.new()
		owned.initialize(definition, StringName("npc:%s:%d" % [id, row.get_squad_count()]), 0)
	owned.rune_revealed.fill(false)
	row.add_squad(SquadData.from_owned_card(owned), row.get_squad_count())
	return owned

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame

func finish_battle(main) -> void:
	var batches := 0
	while main.battle_controller.current_result == BattleController.Result.NONE and batches < 1200:
		main.battle_controller.resolve_next_batch()
		await process_frame
		batches += 1
	check(batches < 1200, "真实战斗正常结束")
	await create_timer(SquadView.DEATH_DISSOLVE_EDGE_SECONDS + 0.15).timeout
	check(main.current_phase == main.GamePhase.RESULT, "等待阵亡动画后自动进入结算")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main = await new_main()
	var board := ResourceBoardState.new()
	board.level_id = &"result_resource_test"
	board.resources_generated = true
	var ore: CardData = load("res://resources/cards/stone_of_greed.tres")
	for index: int in 4:
		var owned := OwnedCard.new()
		owned.initialize(ore, StringName("result_ore_%d" % index), index)
		check(board.deploy_level_resource("enemy", owned, Vector2i(0, index)), "资源板合法部署第%d张资源" % (index + 1))
	var snapshot: Dictionary = board.capture_state()
	var registry: Dictionary = main._build_card_definition_registry()
	var restored := ResourceBoardState.new()
	check(restored.restore_state(JSON.parse_string(JSON.stringify(snapshot)), registry), "四张资源经过真实JSON往返恢复成功")
	check(JSON.stringify(restored.capture_state()) == JSON.stringify(snapshot), "额外资源的身份、形状和位置精确保留")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid.deployments.enemy.result_ore_3.anchor = [0, 0]
	check(not ResourceBoardState.new().restore_state(invalid, registry), "放宽数量后仍拒绝资源重叠")
	main.resource_board_state = board
	main._refresh_resource_preparation_trays()
	deploy(main, main.front_row, "guard_remains")
	deploy(main, main.front_row, "rallying_mine_bell")
	deploy(main, main.front_row, "minecart_soul")
	deploy(main, main.back_row, "musketeer")
	deploy(main, main.back_row, "musketeer")
	deploy(main, main.enemy_front_row, "crystal_shell_broodmother", false)
	deploy(main, main.enemy_front_row, "crystal_skin_sentry", false)
	deploy(main, main.enemy_back_row, "gold_sprite", false)
	await process_frame
	check(main.start_battle(249162182, false), "四张敌方资源与召唤阵容通过正式开战入口")
	var c: BattleController = main.battle_controller
	var original: Array[BattleSquadState] = []
	for state: BattleSquadState in c.get_all_states():
		if state.initial_formation_index >= 0:
			original.append(state)
	var summons: Array[BattleSquadState] = []
	for side_source: BattleSquadState in [c.player_states[1], c.enemy_states[0]]:
		for index: int in 2:
			var state := c.summon_content_minion(side_source, load("res://resources/cards/crystal_shard_beetle.tres"))
			check(state != null and state.initial_formation_index == -1, "双方同名召唤分别标记为非战前单位")
			if state != null: summons.append(state)
	check(original.any(func(s: BattleSquadState): return s.formation_index != s.initial_formation_index), "召唤确实挤动了原小队的战中排位")
	await finish_battle(main)
	check(bool(main._last_battle_settlement_result.get("success", false)), "资源恢复后正式战后结算成功")
	check(main._battle_state_slots.size() == original.size(), "全部战前小队恢复，生成单位不覆盖原卡槽")
	for state: BattleSquadState in original:
		var slot: BoardSlot = main._battle_state_slots.get(state)
		check(slot != null and slot.get_squad_data().get_effect_source().id == state.get_effect_source().id,
			"战前小队恢复自身卡面：" + state.get_effect_source().display_name)
		if slot != null:
			check(slot.get_squad_data().get_effect_source_instance().instance_id == state.squad_data.get_effect_source_instance().instance_id
				and slot.get_battle_result_statistics() == state.get_battle_statistics(), "同名原小队仍按自身实例显示精确统计")
			check(slot.is_showing_battle_result_statistics() and slot.has_battle_result_death_mark() == not state.alive,
				"自身统计与阵亡标识正确：" + state.get_effect_source().display_name)
	var others: Array[BattleSquadState] = main._get_other_battle_states()
	check(others.size() >= summons.size() and others.any(func(s: BattleSquadState): return not s.alive), "列表包含双方生成单位及已阵亡单位")
	for state: BattleSquadState in others:
		check(not main._battle_state_slots.has(state), "生成单位不再挤占战前卡面统计")
	var text: String = main._format_other_battle_statistics()
	check(text.contains("我方") and text.contains("敌方") and text.contains("阵亡") and text.contains("造成伤害") and text.contains("承受伤害") and text.contains("治疗") and text.contains("给予护甲"), "列表提供阵营、阵亡及四项实际战况")
	for state: BattleSquadState in summons:
		check(text.contains("#%d ·" % state.runtime_id), "同名单位用独立编号显示")
	var button: Button = main._other_battle_statistics_button
	var view_button: Button = main.get_node("%ViewResultBattlefieldButton")
	check(button.is_visible_in_tree() and button.position.y + button.size.y <= view_button.position.y, "新按钮显示在查看战场上方且互不重叠")
	var collection_before: Dictionary = main.owned_card_collection.capture_state()
	var rewards_before: Dictionary = main.run_reward_state.capture_state()
	await click(main_to_screen(button.get_global_rect().get_center()))
	check(is_instance_valid(main._other_battle_statistics_dialog) and main._other_battle_statistics_dialog.visible, "真实鼠标点击打开统计窗口")
	if is_instance_valid(main._other_battle_statistics_dialog):
		check(main._other_battle_statistics_text.text == text and main._other_battle_statistics_text.scroll_active, "窗口显示全部生成单位且可滚动")
		if "--visual" in OS.get_cmdline_user_args():
			await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("/private/tmp/project-card-result-summons-dialog.png") == OK, "保存统计窗口真实画面")
		await click(Vector2(main._other_battle_statistics_dialog.position) + main._other_battle_statistics_dialog.get_ok_button().get_global_rect().get_center())
		check(not main._other_battle_statistics_dialog.visible, "真实点击关闭统计窗口")
		await process_frame
		await click(main_to_screen(button.get_global_rect().get_center()))
		check(main._other_battle_statistics_dialog.visible and main._other_battle_statistics_text.text == text, "重复打开使用同一场统计")
		main._other_battle_statistics_dialog.hide()
	check(main.owned_card_collection.capture_state() == collection_before and main.run_reward_state.capture_state() == rewards_before, "查看生成单位统计不重复结算或改动收藏奖励")
	main._set_result_battlefield_visible(true)
	check(not main.battle_result_panel.visible and main._return_to_result_button.visible, "仍可查看战前战场")
	main._set_result_battlefield_visible(false)
	check(button.is_visible_in_tree(), "返回结算保留其他单位按钮")
	if "--visual" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-result-summons-panel.png")
	await free_main(main)
	main = await new_main()
	deploy(main, main.front_row, "musketeer")
	deploy(main, main.enemy_front_row, "timid_infantry", false)
	check(main.start_battle(7043, false), "无召唤场次正式开战")
	await finish_battle(main)
	check(main._get_other_battle_states().is_empty() and not main._other_battle_statistics_button.visible, "无生成单位时隐藏按钮，上一场数据不残留")
	main._show_other_battle_statistics()
	check(not is_instance_valid(main._other_battle_statistics_dialog), "无生成单位不打开空窗口")
	await free_main(main)
	print("战况召唤专项：%d条断言，%d失败" % [assertions, failures])
	quit(failures)
