extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const SAVE_PATH := "/private/tmp/project-card-twisted-main-save.json"
var failures := 0
var assertions := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func new_main():
	var main = MAIN_SCENE.instantiate()
	main.run_save_path = SAVE_PATH
	root.add_child(main)
	await process_frame
	await process_frame
	for row in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]: row.clear_squads()
	return main

func create(main, id: String) -> OwnedCard:
	var card: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/%s.tres" % id))
	card.rune_revealed.fill(false)
	return card

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main = await new_main()
	var registry: Dictionary = main._build_card_definition_registry()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/demo2/twisted_vein_manifest.json"))
	check(manifest.cards.all(func(entry: Dictionary): return registry.has(StringName(entry.id))), "主场景自动注册全部36张定义")
	var guard := create(main, "guard_remains")
	var bell := create(main, "rallying_mine_bell")
	var cart := create(main, "minecart_soul")
	var enemy := create(main, "golden_golem")
	main.front_row.add_squad(SquadData.from_owned_card(guard), 0)
	main.front_row.add_squad(SquadData.from_owned_card(bell), 1)
	main.front_row.add_squad(SquadData.from_owned_card(cart), 2)
	main.enemy_front_row.add_squad(SquadData.from_owned_card(enemy), 0)
	await process_frame
	await process_frame
	var before_board := JSON.stringify(main.resource_board_state.capture_state())
	var before_count: int = main.owned_card_collection.size()
	var opening_sources_mapped: Array[bool] = []
	main.battle_controller.projectile_launched.connect(func(e: BattleEffectEvent):
		if is_zero_approx(e.timestamp) and e.source != null: opening_sources_mapped.append(main._battle_state_slots.has(e.source)))
	check(main.start_battle(7041, false), "真实主场景启动矿铃及矿车开场")
	var c: BattleController = main.battle_controller
	check(c.player_states.size() == 4 and main.front_row.get_squad_count() == 4, "矿铃召唤同时进入运行时及真实战场槽位")
	var summoned := c.player_states[-1]
	var summoned_name := summoned.get_effect_source().id
	var slots: Array = main.front_row.get_squads()
	check(slots[1].get_squad_data().get_effect_source_instance().instance_id == bell.instance_id and slots[2].get_squad_data().get_effect_source().id == summoned_name and slots[3].get_squad_data().get_effect_source_instance().instance_id == cart.instance_id, "开场召唤落在矿铃右侧，原阵容映射正确")
	check(not opening_sources_mapped.is_empty() and opening_sources_mapped.all(func(v: bool): return v), "开场立即行动发射前主场景已建立来源槽位")
	var resource: RefCounted = c.spawn_content_resource(load("res://resources/cards/light_element_shard.tres"), 1)
	check(resource != null and main.enemy_resource_tray.board_state == c.battle_resource_board and main.enemy_resource_tray._tile_nodes_by_id.has(String(resource.owned_card.instance_id)), "战中资源实际显示在敌方资源拼图板")
	var resource_center: Vector2 = main.enemy_resource_tray.get_instance_center_global(resource.owned_card.instance_id)
	resource.apply_damage(100)
	c.spawn_content_resource(load("res://resources/cards/light_element_shard.tres"), 1)
	check(main.enemy_resource_tray.get_resource_center_global(resource).is_equal_approx(resource_center), "资源击碎腾位后，清障机起点仍保持原资源拼图中心")
	check(JSON.stringify(main.resource_board_state.capture_state()) == before_board and main.owned_card_collection.size() == before_count, "战中召唤和资源没有提前写入永久收藏或准备板")
	if "--visual" in OS.get_cmdline_user_args():
		main.set_world_view(main.WorldView.BATTLEFIELDS, false)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/private/tmp/project-card-twisted-main.png") == OK, "保存真实主场景验收画面")
	check(main.restart_battle(), "真实重开恢复战前快照")
	await process_frame
	check(main.front_row.get_squad_count() == 3 and JSON.stringify(main.resource_board_state.capture_state()) == before_board and main.run_reward_state.mining_totals == [0,0], "重开撤销召唤、动态资源及开采累计")
	check(main.start_battle(7041, false) and main.battle_controller.player_states[-1].get_effect_source().id == summoned_name, "同一战前快照与种子重现同一卡铃召唤")
	main.restart_battle()
	await process_frame
	for row in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]: row.clear_squads()
	var sentry := create(main, "crystal_skin_sentry")
	var pouch := create(main, "crystal_shard_pouch")
	pouch.equipment_durability = 1
	var holder := SquadData.from_owned_card(guard)
	holder.equip_item(pouch)
	main.front_row.add_squad(holder, 0)
	main.front_row.add_squad(SquadData.from_owned_card(sentry), 1)
	main.enemy_front_row.add_squad(SquadData.from_owned_card(enemy), 0)
	check(main.start_battle(7042, false), "主场景启动哨兵销毁和小包耗尽场次")
	c = main.battle_controller
	var event := c.twisted_vein.make_event(c.enemy_states[0], c.player_states[1], 1, CardData.ActionType.MELEE, false, "真实销毁")
	event.pierces_armor = true
	c._apply_effect_event(event)
	c._finalize_batch()
	c.twisted_vein.finish(BattleController.Result.PLAYER_VICTORY)
	main._show_battle_result(BattleController.Result.PLAYER_VICTORY)
	check(bool(main._last_battle_settlement_result.get("success", false)), "主场景提交正式永久结算")
	check(main.owned_card_collection.get_by_instance_id(sentry.instance_id) == null and main.owned_card_collection.get_by_instance_id(pouch.instance_id) == null, "永久销毁哨兵并移除最后耐久的小包")
	main._restore_battle_snapshot(false)
	check(main.front_row.get_squad_count() == 1 and main.front_row.get_squads()[0].get_squad_data().get_equipped_item() == null, "结算后还原阵容不复活已销毁卡，也不重新装备耗尽物品")
	main.run_reward_state.mining_totals.assign([8, 5])
	check(main.save_run_to_path(SAVE_PATH) == OK, "主场景保存正式矿脉结算")
	main.queue_free()
	await process_frame
	main = await new_main()
	check(main.load_run_from_path(SAVE_PATH) and main.run_reward_state.mining_totals == [8,5], "真实JSON读档恢复双方整局开采累计")
	check(main.owned_card_collection.get_by_instance_id(sentry.instance_id) == null and main.owned_card_collection.get_by_instance_id(pouch.instance_id) == null, "读档后销毁与耗尽卡保持消耗状态")
	main.queue_free()
	await process_frame
	print("矿脉主场景：%d条断言，%d失败" % [assertions, failures])
	quit(1 if failures > 0 else 0)
