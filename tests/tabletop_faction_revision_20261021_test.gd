extends "res://tests/service_interaction_revision_20261020_test.gd"

## 真实路径选择、鼠标布阵、存档恢复与法术令牌像素回归。
const SAVE := "/private/tmp/project-card-tabletop-faction-revision.json"
const IconStyle = preload("res://scripts/ui/spell_preparation_icon_style.gd")
const Packs = preload("res://scripts/data/card_pack_registry.gd")

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("棋盘与阵营修订验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.5).timeout
	maze = main.maze_controller
	_deal("loose_coins")
	check(main._tabletop_park_button.position == Vector2(599, 713) and main._tabletop_park_button.disabled, "按钮位于指定世界位置，上半视角禁用")
	await verify_park_and_deploy("路径选择")
	check(maze.select_path("loose_coins"), "提交真实随机事件")
	await verify_park_and_deploy("事件")
	check(maze.complete_event(), "完成随机事件进入强化")
	check(maze.select_path(maze.run.paths[0].path_id), "选择真实强化事件")
	check(is_instance_valid(maze._enhancement_slot) and main._is_card_service_active(), "强化槽原有服务限制生效")
	await verify_park_and_deploy("强化")
	check(maze.complete_event(false), "跳过强化进入商店选择")
	await verify_shop_animation()
	main._open_shop_card_services()
	await create_timer(0.5).timeout
	check(main._is_card_service_active(), "购物切到真实服务页时仍使用服务槽")
	var service_ids: Array = main._shop_exchange_ids.duplicate()
	await verify_park_and_deploy("商店服务")
	check(main._shop_exchange_ids == service_ids and main.ordinary_shop_open, "收起和恢复保留原服务会话")
	main.set_world_view(main.WorldView.COLLECTION, false)
	await _click(main._tabletop_park_button)
	await create_timer(0.35).timeout
	check(main.save_run_to_path(SAVE) == OK and main.load_run_from_path(SAVE), "收起状态下可真实保存并读档")
	await create_timer(0.5).timeout
	check(main.ordinary_shop_open and main.ordinary_shop_panel.visible and not main._tabletop_panels_parked and main.ordinary_shop_panel.global_position == Vector2(189, 0), "读档直接进店并恢复正常跟随，不留下离屏状态")
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	check(maze.run.get_round_kind() == "battle" and maze.run.step == ShortMazeRunState.Step.CHOOSING, "离店正常进入战斗路径选择")
	check(maze.select_path(maze.run.paths[0].path_id), "选择真实敌方遭遇")
	await verify_park_and_deploy("战斗准备")
	check(main.start_battle(20261021, false), "布阵后仍能启动自动战斗")
	check(not main.front_row._drag_enabled and not main.back_row._drag_enabled and not main.spell_preparation_tray._drop_enabled, "自动战斗期间保持禁止手动调整")
	verify_faction_tokens()
	await capture("tabletop-faction-final")
	shell.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(SAVE)
	print("棋盘转场／布阵／阵营令牌：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func verify_park_and_deploy(stage: String) -> void:
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	check(not main._tabletop_park_button.disabled and main._tabletop_park_button.modulate == Color.WHITE, stage + "下半视角按钮亮起可点")
	var panel: Control = main.ordinary_shop_panel if main.ordinary_shop_open else maze._panel
	var prior: Vector2 = panel.global_position
	await _click(main._tabletop_park_button)
	await create_timer(0.12).timeout
	check(panel.global_position.y <= prior.y, stage + "点击后面板向上移动")
	await create_timer(0.25).timeout
	check(main._tabletop_panels_parked and panel.global_position == Vector2(189, -364), stage + "面板回到上半世界189,0")
	check(not main._is_card_service_active() and main.front_row._drop_enabled and main.back_row._drop_enabled and main.spell_preparation_tray._drop_enabled and main.player_resource_tray._enabled, stage + "收起后恢复所有准备落点")
	var owned: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
	var view := _show_owned(owned)
	await process_frame
	await _drag(view, main.front_row)
	await create_timer(0.35).timeout
	check(main._is_owned_card_deployed(owned), stage + "真实鼠标拖入战场成功")
	main.set_world_view(main.WorldView.BATTLEFIELDS)
	await create_timer(0.5).timeout
	check(not main._tabletop_panels_parked and panel.global_position == Vector2(189, 0) and main._tabletop_park_button.disabled, stage + "返回上半视角恢复位置与按钮状态")
	main.set_world_view(main.WorldView.COLLECTION, false)
	if maze.run.step != ShortMazeRunState.Step.BATTLE_PREPARE:
		check(panel.global_position == Vector2(189, 0), stage + "再次下移时面板继续跟随屏幕")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)

func verify_shop_animation() -> void:
	var table: Control = maze._event_table
	await _click(table._deck)
	await create_timer(0.65).timeout
	var selected: Button = table.cards[1]
	await _click(selected)
	await create_timer(0.35).timeout
	var hold_position := selected.position
	check(selected.face_up and not main.ordinary_shop_open, "商店牌先翻到正面，尚未进入商店")
	await create_timer(0.7).timeout
	check(selected.position == hold_position and is_equal_approx(table._dim.color.a, table.DIM_ALPHA) and not main.ordinary_shop_open, "正面停留1秒期间位置与背景亮度不变")
	var overlay: Control = table._modal
	var dim: ColorRect = table._dim
	var dim_alpha: float = table.DIM_ALPHA
	await create_timer(0.3).timeout
	check(main.ordinary_shop_open and main.ordinary_shop_panel.visible and not maze._panel.visible, "停留结束直接进入商店，没有说明中转页")
	check(selected.position.y < hold_position.y and main._shop_motion_root.position.y < 0 and dim.color.a > 0 and dim.color.a < dim_alpha, "商店从上方滑下、所选牌向上离场、背景同步渐亮")
	await capture("shop-direct-transition")
	await create_timer(0.5).timeout
	check(not is_instance_valid(overlay) and main.ordinary_shop_panel.global_position == Vector2(189, 0), "转场完成清理模态层，商店准确落位")

func verify_faction_tokens() -> void:
	var colors := [Color("777777"), Color("1e6fc3"), Color("bd2929"), Color("699a34"), Color("d67a22"), Color("7856a5")]
	# 原生底图像素是美术权威，逐阵营核对底色；中央图案仍按三类与五品级组合。
	for faction: int in range(1, 6):
		var expected: Color = colors[faction]
		if IconStyle.FACTION_BASES.has(faction): expected = IconStyle.FACTION_BASES[faction].get_image().get_pixel(5, 20)
		for column: int in 3:
			for rarity: int in 5:
				var texture: Texture2D = IconStyle.get_texture(column, rarity, faction)
				check(texture.get_size() == Vector2(42, 42) and texture.get_image().get_pixel(5, 20).is_equal_approx(expected), "阵营%d类别%d品级%d使用正确背景" % [faction, column, rarity])
	for pack: StringName in Packs.PACKS:
		var faction: int = Packs.get_faction(pack)
		var card := CardData.new()
		card.pack_id = pack
		check(card.get_effective_faction() == faction, String(pack) + "使用权威卡包阵营归属")
	var blue := IconStyle.get_texture(0, 0, CardFaction.Id.RADIANT_ALLIANCE)
	var red := IconStyle.get_texture(0, 0, CardFaction.Id.HANSA_FEDERATION)
	check(blue != red and blue.get_image().get_pixel(10, 10) != red.get_image().get_pixel(10, 10), "同类同品级的不同阵营不共用错误缓存")
