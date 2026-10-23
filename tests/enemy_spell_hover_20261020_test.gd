extends "res://tests/board_ui_fixes_20261019_test.gd"

## 正式迷宫第二天遭遇和实际战斗数据，验证只读法术的布局与鼠标预览。
func snapshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-spell-hover-" + label + ".png")

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("敌方法术悬停验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-enemy-spell-hover.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.7).timeout
	maze = main.maze_controller
	maze.new_run(20261019)
	await process_frame
	var choices := ""
	for child: Node in maze._body.find_children("*", "Button", true, false):
		if child is Button: choices += child.text
	check(choices.count("突击") == 2 and choices.count("遗愿") == 1 and not "战吼" in choices and not "亡语" in choices, "真实天赋选择按钮统一使用突击与遗愿")
	for definition: Dictionary in maze.rewards.config.talents.values():
		check(not "战吼" in definition.source_text and not "亡语" in definition.source_text, "所有天赋说明均无旧用词")
	await create_timer(2.5).timeout
	await snapshot("talents")
	maze.choose_talent("sentry_guard")
	finish_events()
	check(maze.select_path(maze.run.paths[0].path_id), "首日进入真实遭遇")
	var player: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	player.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 3000)
	player.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 20)
	main.front_row.add_squad(SquadData.from_owned_card(player), 0)
	check(main.start_battle(20261020, false), "启动首日实际战斗")
	await resolve_real_battle()
	check(maze.continue_after_battle(), "实际结算进入第二天")
	while not maze.hero.pending_talent_levels.is_empty(): maze.choose_talent(maze.hero.get_pending_choices()[0])
	finish_events()
	var path_id := ""
	for path: Dictionary in maze.run.paths:
		if not path.get("spells", []).is_empty(): path_id = path.path_id; break
	check(not path_id.is_empty() and maze.select_path(path_id), "第二天选择带真实敌方法术的遭遇")
	var tray: Control = main.enemy_spell_preparation_tray
	check(tray._prepared_cards.is_empty() and not tray.get_meta("expanded", false), "准备阶段仍隐藏敌方法术详情")
	var spell: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/damage_fireball.tres"))
	main.prepared_spell_instance_ids.append(spell.instance_id)
	main._refresh_spell_preparation_tray()
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	check(main.start_battle(20261020, false), "启动双方带法术的真实战斗")
	await create_timer(0.6).timeout
	main._update_battle_timer()
	var states: Array[Dictionary] = main.battle_controller.get_spell_display_states(BattleSquadState.Side.ENEMY)
	check(not states.is_empty() and tray._prepared_cards.size() == states.size() and not tray._drop_enabled, "右侧保持实际战斗队列且禁止拖放")
	for entry: Dictionary in states:
		var enemy: OwnedCard = entry.spell
		var icon: Control = tray._icons_by_instance_id[enemy.instance_id]
		var column: int = enemy.card_data.get_spell_preparation_column()
		var header: Control = tray._columns[column].get_child(0)
		check(is_equal_approx(icon.get_global_rect().get_center().x, header.get_global_rect().get_center().x), "敌方法术与所在分类标题精确居中对齐")
		await move_pointer(icon.get_global_rect().get_center())
		await create_timer(0.2).timeout
		check(is_instance_valid(tray._hover_card_popup) and tray._hover_card_popup.visible and tray._hover_card_popup.get_owned_card() == enemy, "真实鼠标指向敌方图标弹出对应完整法术卡")
		check(tray._hover_card_popup.get_global_rect().end.x < icon.get_global_rect().position.x and tray._hover_card_popup.get_global_rect().position.x >= 0, "敌方预览向左展开，完整位于屏幕内")
		check(icon._get_drag_data(Vector2(20, 20)) == null, "允许预览仍不能拖起敌方法术")
		await press_pointer(true)
		await press_pointer(false)
		check(main._click_carry_data.is_empty(), "单击敌方法术不会进入携带")
		await snapshot("enemy")
	var own: Control = main.spell_preparation_tray
	var own_icon: Control = own._icons_by_instance_id[spell.instance_id]
	await move_pointer(own_icon.get_global_rect().get_center())
	await create_timer(0.2).timeout
	check(not own._drop_enabled and is_instance_valid(own._hover_card_popup) and own._hover_card_popup.visible and own._hover_card_popup.get_owned_card() == spell, "我方战斗中同样可悬停预览且保持禁止拖放")
	check(own._hover_card_popup.get_global_rect().position.x > own_icon.get_global_rect().end.x, "我方预览仍向右展开")
	check(not tray._hover_card_popup.visible, "移开敌方图标后预览关闭")
	var enemy_icon: Control = tray._icons_by_instance_id[states[0].spell.instance_id]
	await move_pointer(enemy_icon.get_global_rect().get_center())
	await create_timer(0.1).timeout
	await snapshot("enemy-hover")
	await resolve_real_battle()
	await process_frame
	check(not tray.get_meta("expanded", false) and not tray._hover_card_popup.visible, "普通结算收起托盘时立即清除悬停卡")
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Enemy spell hover: ", assertions, " checks, ", failures, " failures")
	quit(1 if failures else 0)
