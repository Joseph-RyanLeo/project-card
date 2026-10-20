extends "res://tests/shop_event_materials_20261020_test.gd"

## 实际2K输入验证战斗介绍留在上半世界，收藏视角可部署两排，其他事件／商店仍固定。
const ANCHOR_SAVE := "/private/tmp/project-card-battle-intro-anchor-save.json"
const ANCHOR_PREVIEW := "res://docs/previews/shop_event_20261020/battle_formation_uncovered.png"

func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("战斗介绍世界锚定验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = ANCHOR_SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await process_frame
	maze = main.maze_controller
	_deal("loose_coins")
	check(maze.select_path("loose_coins"), "选中真实随机事件")
	var fixed: Vector2 = maze._panel.global_position
	main.set_world_view(main.WorldView.COLLECTION, false)
	check(maze._panel.get_parent() == main and maze._panel.global_position == fixed, "普通事件继续固定屏幕")
	check(maze.complete_event(), "完成事件进入强化轮")
	check(maze.select_path(maze.run.paths[0].path_id) and maze.complete_event(false), "完成真实强化轮")
	check(maze.select_path(maze.run.paths[0].path_id), "选中真实商店路径")
	maze.enter_selected_shop()
	await create_timer(0.5).timeout
	main._open_shop_card_services()
	await create_timer(0.5).timeout
	check(main.ordinary_shop_panel.global_position == fixed and main._shop_card_service_panel.visible, "商店服务页仍在下半视角固定显示")
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	if main._view_tween != null and main._view_tween.is_running(): await main._view_tween.finished
	check(maze.run.step == ShortMazeRunState.Step.CHOOSING and maze.run.get_round_kind() == "battle", "离店进入真实战斗三选一")
	check(maze._panel.get_parent() == main, "尚未选择战斗牌时牌堆仍使用固定屏幕层")
	check(maze.select_path(maze.run.paths[0].path_id), "选定战斗遭遇并生成真实敌方数据")
	check(maze._panel.get_parent() == main.world_content and maze._panel.position == Vector2(189, -3), "战斗介绍改为上半世界坐标")
	check(maze._panel.global_position == fixed, "上半视角中的介绍位置保持原样")
	var table: Control = maze._event_table
	await _click(main.player_avatar_button)
	check(main.current_world_view == main.WorldView.COLLECTION, "真实点击人物切换到下半视角")
	main._view_tween.pause()
	main._view_tween.custom_step(0.32)
	check(maze._panel.global_position == main.world_content.position + Vector2(189, -3), "视角移动时介绍与上半战场一起移出")
	main._view_tween.custom_step(0.12)
	check(maze._panel.global_position == Vector2(189, -370), "下半终点中战斗介绍完整位于屏幕上方")
	check(not maze._panel.get_global_rect().intersects(Rect2(0, 0, 1280, 720)), "介绍板不再覆盖我方战场或收藏")
	check(maze._event_table == table, "切视角保留同一个介绍页，不重新翻牌")
	var player: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	var view := _show_owned(player)
	await process_frame
	var before_front: int = main.front_row.get_squad_count()
	await _drag(view, main.front_row)
	await create_timer(0.35).timeout
	check(main.front_row.get_squad_count() == before_front + 1, "下半视角可真实拖入我方前排")
	check(main.front_row.get_squads()[0].get_primary_card_view().get_owned_card() == player, "前排部署使用原有卡牌实例")
	var back_card: OwnedCard
	for owned: OwnedCard in main.owned_card_collection.get_cards():
		if owned != player and owned.card_data.card_type == CardData.CardType.MINION:
			back_card = owned
			break
	view = _show_owned(back_card)
	await process_frame
	var before_back: int = main.back_row.get_squad_count()
	await _drag(view, main.back_row)
	await create_timer(0.35).timeout
	check(main.back_row.get_squad_count() == before_back + 1, "下半视角可真实拖入我方后排")
	check(not main.get_node("WorldContent/EnemyBoardSection").visible, "准备阶段仍保留敌方阵容隐藏规则")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		shell.internal_viewport.get_texture().get_image().save_png(ANCHOR_PREVIEW)
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	check(maze._panel.global_position == fixed and maze._panel.visible, "回上半视角后战斗介绍恢复原位")
	main.set_world_view(main.WorldView.COLLECTION, false)
	check(main.save_run_to_path(ANCHOR_SAVE) == OK and main.load_run_from_path(ANCHOR_SAVE), "真实准备存档可保存并读回")
	main.set_world_view(main.WorldView.COLLECTION, false)
	check(maze._panel.get_parent() == main.world_content and maze._panel.get_global_rect().end.y < 0, "读档后介绍继续锚定上半世界")
	check(main.front_row.get_squad_count() == before_front + 1 and main.back_row.get_squad_count() == before_back + 1, "读档保留刚部署的两排阵容")
	check(main.start_battle(-1, false), "新位置关系下可正常开战")
	await process_frame
	check(not maze._panel.visible and main.get_node("WorldContent/EnemyBoardSection").visible, "开战收起介绍并显示真实敌方")
	shell.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(ANCHOR_SAVE)
	print("战斗介绍上半世界锚定：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
