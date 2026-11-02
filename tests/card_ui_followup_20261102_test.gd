extends "res://tests/service_interaction_revision_20261020_test.gd"

const Settings = preload("res://scripts/ui/card_text_display_settings.gd")
const PREVIEWS := "res://docs/previews/card_ui_followup_20261102"


func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEWS))
	root.get_texture().get_image().save_png(PREVIEWS.path_join(label + ".png"))


func _run() -> void:
	create_timer(160).timeout.connect(func(): push_error("卡牌界面七项反馈超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-ui-followup-20261102.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_720P)
	await create_timer(0.4).timeout
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	for owned: OwnedCard in main.owned_card_collection.get_cards(): main.owned_card_collection.remove_by_instance_id(owned.instance_id)
	var registry: Dictionary = main._build_card_definition_registry()
	var all: Array[CardData] = []
	all.assign(registry.values())
	var disabled := 0
	for card: CardData in all:
		if card.effect_text.begins_with("占位"):
			disabled += 1
			check(not card.is_available, "占位卡退出获取池：" + card.display_name)
	check(disabled == 29, "29张占位定义保留资源但全部停用")
	var pool: Array[CardData] = main.ordinary_shop_service._eligible_cards(all, [])
	var clean := true
	for card: CardData in pool: clean = clean and not card.effect_text.begins_with("占位")
	check(clean, "普通商店、卡包和随机奖励公共候选不含占位卡")
	var gun: OwnedCard = main.owned_card_collection.create_card(registry[&"musketeer"])
	var beer: OwnedCard = main.owned_card_collection.create_card(registry[&"beer_mug"])
	var view := _show_owned(beer)
	check(view.cooldown_label.text == "0" and view.cooldown_label.position.x == CardView.COOLDOWN_VALUE_POSITION.x + 3, "零热诚无符号且数值右移3像素")
	await pack_transactions(beer)
	var squad := SquadData.from_owned_card(gun)
	check(squad.equip_item(beer), "真实装备啤酒杯到小队")
	main.front_row.add_squad(squad, 0)
	main._refresh_drag_availability()
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	await _motion(Vector2(1270, 700))
	# 新小队异步居中，必须在布局到位后读取真实指示物命中坐标。
	var layout_deadline := Time.get_ticks_msec() + 2000
	while main.front_row._has_layout_animation() and Time.get_ticks_msec() < layout_deadline: await process_frame
	var indicator: Control = main.front_row.get_squads()[0].get_equipment_indicator()
	Settings.set_mode(self, Settings.Mode.CARD, false)
	await _motion(indicator.get_global_rect().get_center())
	await create_timer(0.3).timeout
	var popup = get_first_node_in_group(&"card_effect_popup")
	if not is_instance_valid(indicator._hover_card):
		await shot("00_equipment_hover_failure")
		print("装备悬停诊断：命中", shell.internal_viewport.gui_get_hovered_control(), "，图标区域", indicator.get_global_rect(), "，指向", shell.internal_viewport.get_mouse_position(), "，日志可见", main.battle_log_panel.visible, "，携带阻止", CardView.EffectPopup.interaction_blocked(self))
		check(false, "装备预览必须实际创建")
		shell.queue_free()
		await process_frame
		quit(1)
		return
	check(is_instance_valid(indicator._hover_card) and popup != null and popup.panel.visible and popup.source == indicator._hover_card, "已装备物品指向时弹出完整卡及统一效果框，卡牌文字模式下也生效")
	var anchor_rect: Rect2 = shell.render_container.get_global_transform_with_canvas() * indicator._hover_card.get_global_rect()
	check(popup.panel.get_global_rect().end.y <= anchor_rect.position.y or popup.panel.position.y >= anchor_rect.end.y, "装备效果框显示在预览卡上方或下方")
	check(indicator.tooltip_text.is_empty() and popup.body.text.contains("强化"), "移除遮挡卡面的原生长提示，并显示实际装备效果")
	await shot("01_equipped_popup")
	await _motion(Vector2(1270, 700))
	await process_frame
	check(not is_instance_valid(indicator._hover_card) and not popup.panel.visible, "移开后装备预览与效果框同时清理")
	var star := CelestialIndicator.new()
	star.instance_id = &"feedback_star"
	star.kind = CelestialIndicator.Kind.STAR
	check(squad.attach_indicator(star, Vector2(25, 110), 1), "真实星星附加到小队")
	var slot: Control = main.front_row.get_squads()[0]
	slot._refresh()
	var star_view: Control = slot.get_celestial_indicator(star.instance_id)
	await _motion(star_view.get_global_rect().get_center())
	await create_timer(0.3).timeout
	check(popup.panel.visible and popup.source == star_view and popup.title.text == "星星" and popup.body.text.contains("遗愿"), "星星指示物复用卡牌效果窗口")
	check(star_view.tooltip_text.is_empty(), "指示物不再叠加原生长工具提示")
	await shot("05_star_popup")
	await _motion(Vector2(1270, 700))
	check(not popup.panel.visible, "移开星星后清理共享效果窗口")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	slot.show_battle_result_statistics({"damage_dealt": 106, "damage_taken": 40}, false, CardData.ActionType.RANGED)
	main.battle_log_text.text = "[b]战斗回放[/b]\n我方火枪手造成106点伤害\n装备与星星指示物位于日志后方\n".repeat(12)
	main.battle_log_panel.visible = true
	await _motion(main.battle_log_panel.get_global_rect().get_center())
	await create_timer(0.3).timeout
	check(effective_z(main.battle_log_panel) > effective_z(slot._battle_result_overlay) and effective_z(main.battle_log_panel) > effective_z(indicator), "日志层级高于真实战后统计及装备指示物")
	check(main.formula_popup.z_index > main.battle_log_panel.z_index and main.battle_log_text.get_theme_font_size("normal_font_size") == 14, "公式层高于日志，日志正文为精细14号字")
	await _motion(indicator.get_global_rect().get_center())
	await create_timer(0.3).timeout
	var log_hit: Control = shell.internal_viewport.gui_get_hovered_control()
	check(log_hit != null and (log_hit == main.battle_log_panel or main.battle_log_panel.is_ancestor_of(log_hit)) and not is_instance_valid(indicator._hover_card), "日志覆盖的装备位置由日志接收鼠标，不弹出背后装备卡")
	await shot("06_log_on_top")
	main.battle_log_panel.hide()
	slot.clear_battle_result_statistics()
	main.set_world_view(main.WorldView.COLLECTION, false)
	await inspect_fonts(gun)
	main.short_maze_enabled = true
	maze = ShortMazeController.new()
	main.maze_controller = maze
	main.add_child(maze)
	check(maze.initialize(main), "接入真实迷宫协调器")
	_deal("loose_coins")
	check(maze.select_path("loose_coins"), "真实选择第一轮事件")
	await create_timer(0.3).timeout
	var before_marker := PackedByteArray()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		before_marker = shell.internal_viewport.get_texture().get_image().get_region(Rect2i(402, 18, 13, 13)).get_data()
	check(maze.complete_event(), "完成事件推进日内轮次")
	await create_timer(0.07).timeout
	var hud: Control = maze._status
	check(is_instance_valid(hud._roll) and hud._roll.is_running() and hud._fronts[maze.run.day - 1].position.y < 0 and hud._backs[maze.run.day - 1].position.y > 0, "日内切换时旧标记滚出、新标记滚入")
	var header: Control = maze._event_table._board.get_child(1)
	await process_frame
	check(header._day_rolling, "实际事件顶栏读取同一轮盘进度")
	await shot("03_day_rolling")
	var during_marker := PackedByteArray()
	if DisplayServer.get_name() != "headless": during_marker = shell.internal_viewport.get_texture().get_image().get_region(Rect2i(402, 18, 13, 13)).get_data()
	await create_timer(0.3).timeout
	check(hud._fronts[maze.run.day - 1].position == Vector2.ZERO and hud._backs[maze.run.day - 1].texture == null, "轮盘结束仅留下新标记")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var after_marker: PackedByteArray = shell.internal_viewport.get_texture().get_image().get_region(Rect2i(402, 18, 13, 13)).get_data()
		check(during_marker != before_marker and during_marker != after_marker and before_marker != after_marker, "实际Day区域的滚动中间帧不同于旧图及新图，最终确实切换")
	check(maze.select_path(maze.run.paths[0].path_id) and maze.complete_event(false), "真实完成强化轮")
	check(maze.select_path(maze.run.paths[0].path_id), "选择商店路径")
	maze.enter_selected_shop()
	main._toggle_ordinary_shop()
	check(maze.run.get_round_kind() == "battle", "实际离店进入战斗选牌")
	await create_timer(0.7).timeout
	main.set_world_view(main.WorldView.COLLECTION, false)
	await _click(maze._event_table._deck)
	await create_timer(0.65).timeout
	await _click(maze._event_table.cards[0])
	await create_timer(1.2).timeout
	check(maze.run.step == ShortMazeRunState.Step.BATTLE_PREPARE, "下半场实际抽牌并选择战斗遭遇")
	check(maze._panel.get_parent() == main and maze._panel.global_position == Vector2(189, 0) and not main._tabletop_panels_parked, "战斗提示板保留屏幕上方，不自动跳回世界顶部")
	check(main.current_world_view == main.WorldView.COLLECTION and maze._panel.is_visible_in_tree(), "保持下半场视角且提示板仍可见")
	await shot("04_battle_intro_lower_view")
	check(main._can_park_tabletop_panels(), "保留玩家手动收起入口")
	await _click(main._tabletop_park_button)
	await create_timer(0.4).timeout
	check(main._tabletop_panels_parked and maze._panel.get_parent() == main.world_content and maze._panel.position == Vector2(189, 0), "点击收起后才动画回到世界顶部1/3")
	check(main._tabletop_park_button.disabled and not main._can_park_tabletop_panels(), "战斗提示收起后禁用按钮")
	await _click(main._tabletop_park_button)
	check(main._tabletop_panels_parked and maze._panel.get_parent() == main.world_content, "再次点击禁用按钮不召回战斗提示")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	main.set_world_view(main.WorldView.COLLECTION, false)
	maze.refresh()
	check(main._tabletop_panels_parked and maze._panel.get_parent() == main.world_content and maze._panel.position == Vector2(189, 0), "收起后切换视角和刷新仍留在世界顶部")
	print("Card UI followup checks: %d, failures: %d" % [assertions, failures])
	shell.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)


func inspect_fonts(owned: OwnedCard) -> void:
	main.hide()
	var progress := ProfileProgress.new()
	progress.start_run()
	progress.begin_collection([owned])
	var panel = preload("res://scripts/ui/slot_hub.gd").new()
	panel.progress = progress
	panel.slot_index = 0
	shell.design_canvas.add_child(panel)
	panel._inspect(progress.run.candidates.keys()[0])
	await create_timer(1.2).timeout
	var right: Control = panel._inspection.get_node("InspectionDetails")
	var font := Settings.readable_font()
	check(right.get_child(0).get_theme_font("font") == font and right.get_child(1).get_theme_font("font") == font, "右侧名称及品级阵营副标题统一黑体")
	var tabs: TabBar = right.get_node("InspectionTabs")
	check(tabs.get_theme_font("font") == font, "卡牌详情和积分构成页签统一黑体")
	await shot("02_uniform_fonts")
	panel.close_inspection(false)
	panel.queue_free()
	main.show()
	await process_frame


func pack_transactions(held: OwnedCard) -> void:
	main.run_reward_state.gold = 3165
	var offer := {"kind": "card_pack", "pack_id": "ironwall_inscription", "size": "large", "price": 18, "cards": ["beer_mug", "formation_infantry", "formation_infantry", "runic_anvil", "formation_infantry"], "offer_id": "regression_pack"}
	main.ordinary_shop_service.offers.assign([offer])
	var before_rng: int = main.ordinary_shop_service.rng.state
	var before: Dictionary = main.owned_card_collection.capture_state()
	var original := offer.duplicate(true)
	check(main._can_buy_shop_card_pack(offer), "已经持有啤酒杯时铁壁大包仍能按当前合法池去重购买")
	var resolved: Dictionary = main._resolve_shop_card_pack(offer)
	check(resolved.cards.size() == 5 and main.ordinary_shop_service._contains_rarity_at_least(resolved.cards, CardData.Rarity.II), "重核后的大包仍为5张且满足II级保底")
	check(not resolved.cards.has(held.card_data) and main.ordinary_shop_service.rng.state == before_rng and offer == original, "预览不消耗随机流、不改包内容，并排除已持有唯一卡")
	main.ordinary_shop_open = true
	main._refresh_ordinary_shop_panel()
	var tile: Control = main.ordinary_shop_offer_list.find_child("ShopOffer_0", true, false)
	check(tile != null and tile.get_meta("purchase_enabled") and is_equal_approx(tile.modulate.a, 1.0), "真实商品陈列恢复可购买状态，不再显示虚影")
	check(main.save_run_to_path(main.run_save_path) == OK, "写入真实隔离测试档")
	DirAccess.make_dir_absolute(main.run_save_path + ".tmp")
	check(main._buy_shop_card_pack(0, offer).is_empty(), "保存失败时不完成购买")
	check(main.owned_card_collection.capture_state() == before and main.run_reward_state.gold == 3165 and main.ordinary_shop_service.rng.state == before_rng and offer == original, "重核包保存失败回滚卡牌、余额、随机源和原预抽内容")
	DirAccess.remove_absolute(main.run_save_path + ".tmp")
	var acquired: Array[OwnedCard] = main._buy_shop_card_pack(0, offer)
	check(acquired.size() == 5 and main.run_reward_state.gold == 3147 and offer.get("sold", false), "保存成功才提交5张卡并扣18金币")
	var valid := true
	for card: OwnedCard in acquired: valid = valid and card.card_data.is_available and card.card_data != held.card_data
	check(valid, "购入卡均为正式可获取卡，不重复赠送已持有唯一装备")
	main.ordinary_shop_open = false
	main.ordinary_shop_panel.hide()
