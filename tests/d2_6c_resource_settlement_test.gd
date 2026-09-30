extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const BattleRunRewardLedger = preload("res://scripts/battle/battle_run_reward_ledger.gd")
const BattleEffectOwnerRef = preload("res://scripts/battle/effects/battle_effect_owner_ref.gd")
const BattleSquadState = preload("res://scripts/battle/battle_squad_state.gd")
const ResourceHexLayout = preload("res://scripts/data/resource_hex_layout.gd")
const CardArtTuner = preload("res://scripts/tools/card_art_tuner.gd")
const SAVE_PATH := "/private/tmp/project-card-d2-6c-settlement.json"

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if FileAccess.file_exists(SAVE_PATH): DirAccess.remove_absolute(SAVE_PATH)
	root.size = Vector2i(1280, 720)
	var main = await _new_main()
	var player_card := load("res://resources/cards/militia.tres") as CardData
	var enemy_card := load("res://resources/cards/heavy_knight.tres") as CardData
	var player_owned: OwnedCard = main.owned_card_collection.create_card(player_card)
	var enemy_owned: OwnedCard = main.owned_card_collection.create_card(enemy_card)
	var old_level_id: StringName = main.resource_board_state.level_id
	var resources_before_refresh := JSON.stringify(main.resource_board_state.capture_state())
	main._refresh_resource_preparation_trays()
	_expect(JSON.stringify(main.resource_board_state.capture_state()) == resources_before_refresh, "准备界面UI刷新不重新抽取或移动本关资源")
	var deployed_resource: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/fire_element_shard.tres") as CardData)
	var unplaced_resource: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/light_element_shard.tres") as CardData)
	var npc_resource := OwnedCard.new()
	npc_resource.initialize(load("res://resources/cards/wood_element_shard.tres") as CardData, &"e2e_npc_resource", 99)

	_expect(_deploy(main.resource_board_state, "player", deployed_resource), "主场景战前部署玩家资源")
	_expect(_deploy(main.resource_board_state, "enemy", npc_resource), "主场景战前部署NPC资源")
	main.front_row.add_squad(SquadData.from_owned_card(player_owned), 0)
	main.enemy_front_row.add_squad(SquadData.from_owned_card(enemy_owned), 0)
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	main._refresh_resource_preparation_trays()
	main.recently_returned_cards.push_front(deployed_resource.card_data)
	main.recently_returned_owned_cards.push_front(deployed_resource)
	var seeded := 0
	for index: int in 80:
		if main.emblem_library._sticker_inventory.get_items().size() >= 27: break
		var state := {"instance_id": StringName("e2e_toolbox_fill_%02d" % index), "emblem_id": &"火把", "temporary": false}
		if not main.emblem_library.can_add_sticker(state): break
		if not main.emblem_library.return_sticker(state): break
		seeded += 1
	_expect(seeded > 0 and main.emblem_library._sticker_inventory.get_items().size() == 27, "预留一个实际工具箱格以制造可重现的地面纹章奖励")
	_expect(main.start_battle(20260930, false), "主场景在双方真实随从和资源部署下启动战斗")
	var battle_id: StringName = main.battle_controller.battle_instance_id
	var player_state: BattleSquadState = main.battle_controller.player_states[0]
	var owner = BattleEffectOwnerRef.for_state(player_state, BattleEffectDefinition.OwnerKind.OWNING_PLAYER)
	for index: int in 2:
		_expect(main.battle_controller.record_pending_run_reward(
			owner, BattleRunRewardLedger.KIND_RANDOM_EMBLEM_INSTANCE, 1,
			StringName("e2e_emblem_%d" % index), player_state.runtime_id, index + 1,
			{"emblem_id": &"火把", "emblem_instance_id": StringName("%s:e2e_emblem:%d" % [battle_id, index]), "source": "e2e_test"}
		), "战斗控制器接收纹章奖励 %d" % index)
	main.battle_controller.record_pending_run_reward(
		owner, BattleRunRewardLedger.KIND_OWNED_CARD_AWARD, 1,
		&"e2e_resource_card_award", player_state.runtime_id, 5,
		{"card_id": &"fire_element_shard", "card_name": "火元素碎晶"}
	)
	main._show_battle_result(main.battle_controller.Result.PLAYER_VICTORY)
	var awarded_id: StringName = main.owned_card_collection.get_cards()[-1].instance_id
	_expect(
		main._last_battle_settlement_result.get("success", false)
		and main.owned_card_collection.get_by_instance_id(deployed_resource.instance_id) == null
		and main.owned_card_collection.get_by_instance_id(unplaced_resource.instance_id) == unplaced_resource
		and main.owned_card_collection.get_by_instance_id(npc_resource.instance_id) == null
		and main.owned_card_collection.get_by_instance_id(awarded_id) != null
		and not main.resource_board_state.deployments.player.has(String(deployed_resource.instance_id))
		and not main.resource_board_state.deployments.player.has(String(awarded_id))
		and main.resource_board_state.level_resource_cards.player.is_empty()
		and main.resource_board_state.level_resource_cards.enemy.is_empty(),
		"结算仅消耗玩家手动部署资源，保留未部署资源并清除双方本关自动资源"
	)
	_expect(
		main.collection_cards.count(deployed_resource.card_data) == 2
		and main.collection_cards.count(unplaced_resource.card_data) == 2
		and main.owned_card_collection.get_by_instance_id(unplaced_resource.instance_id) == unplaced_resource,
		"真实收藏派生列表按实例权威数据同步，移除已部署卡并保留未部署同名实例"
	)
	main.active_card_type_filters.assign([CardData.CardType.RESOURCE])
	var collected_resources: Array[CardData] = main.get_filtered_collection_cards()
	var deployed_resource_resolves_from_collection := false
	var unplaced_resource_resolves_from_collection := false
	for index: int in collected_resources.size():
		if collected_resources[index] not in [deployed_resource.card_data, unplaced_resource.card_data]: continue
		var resolved: OwnedCard = main._get_owned_card_for_collection_index(collected_resources, index)
		if collected_resources[index] == deployed_resource.card_data:
			deployed_resource_resolves_from_collection = deployed_resource_resolves_from_collection or resolved == deployed_resource
		if collected_resources[index] == unplaced_resource.card_data:
			unplaced_resource_resolves_from_collection = unplaced_resource_resolves_from_collection or resolved == unplaced_resource
	_expect(
		not deployed_resource_resolves_from_collection and unplaced_resource_resolves_from_collection,
		"实际收藏筛选/索引解析不再返回已消耗实例，仍可解析未部署资源实例"
	)
	_expect(
		not main.recently_returned_owned_cards.has(deployed_resource)
		and not main.recently_returned_cards.has(deployed_resource.card_data),
		"资源消耗后最近使用书签按权威收藏同步剔除已失效实例"
	)
	_expect(
		main.run_reward_state.pending_ground_items.size() == 1
		and main.continue_next_level_button.disabled
		and main.start_battle_button.disabled,
		"工具箱溢出纹章落入持久地面背包并同时阻止开战和继续"
	)
	var committed_gold: int = main.run_reward_state.gold
	var duplicate: Dictionary = main.settle_current_battle()
	_expect(
		duplicate.get("status") == "already_committed"
		and main.run_reward_state.gold == committed_gold
		and main.run_reward_state.pending_ground_items.size() == 1,
		"重复结算不重复奖励也不删除新地面物品"
	)
	_expect(main.save_run_to_path(SAVE_PATH) == OK, "带地面奖励和待继续关卡的主场景写入JSON")
	main.queue_free()
	await process_frame
	var resumed = await _new_main()
	var load_success: bool = resumed.load_run_from_path(SAVE_PATH)
	if not load_success:
		print("LOAD DEBUG: %s / %s / %s" % [resumed.play_area_label.text, str(resumed._last_run_persistence_result), str(resumed.run_reward_state.pending_ground_items)])
	_expect(load_success, "真实主场景从JSON恢复地面奖励、资源和关卡状态")
	var restored_level: StringName = resumed.resource_board_state.level_id
	_expect(
		resumed.run_reward_state.pending_ground_items.size() == 1
		and resumed.run_reward_state.pending_next_level_from_id == restored_level
		and resumed.continue_next_level_button.visible
		and resumed.continue_next_level_button.disabled,
		"读档后地面奖励仍阻塞关卡推进且继续入口保持可见"
	)
	if not resumed.run_reward_state.pending_ground_items.is_empty():
		var ground_id := StringName(String(resumed.run_reward_state.pending_ground_items[0].get("ground_id", "")))
		resumed._discard_ground_item(ground_id)
		_expect(resumed.run_reward_state.pending_ground_items.is_empty() and not resumed.continue_next_level_button.disabled, "处理地面奖励后恢复继续权限")
	for row in [resumed.enemy_back_row, resumed.enemy_front_row, resumed.front_row, resumed.back_row]:
		for slot in row.get_squads():
			slot.show_battle_result_statistics({"actions": 1}, true, CardData.ActionType.MELEE)
			slot.set_battle_status(1, 0, 2.0)
	resumed.continue_next_level_button.pressed.emit()
	var stale_presentation := false
	for row in [resumed.enemy_back_row, resumed.enemy_front_row, resumed.front_row, resumed.back_row]:
		for slot in row.get_squads():
			stale_presentation = stale_presentation or slot.is_showing_battle_result_statistics()
	_expect(not stale_presentation, "下一准备阶段清除四排统计、死亡標记和战斗卡面临时属性")
	_expect(
		resumed.current_phase == resumed.GamePhase.PREPARE
		and resumed.resource_board_state.level_id != restored_level
		and resumed.run_reward_state.pending_next_level_from_id.is_empty()
		and (resumed.player_resource_tray as Node).get("_battle_health_by_id").is_empty()
		and (resumed.enemy_resource_tray as Node).get("_battle_health_by_id").is_empty()
		and resumed.resource_board_state.level_id != old_level_id
		and resumed.resource_board_state.resources_generated,
		"通过继续按钮信号进入新准备关卡，仅生成一次新关双方资源并清除旧关生命缓存"
	)
	resumed.queue_free()
	await process_frame
	if FileAccess.file_exists(SAVE_PATH): DirAccess.remove_absolute(SAVE_PATH)
	if failures == 0:
		print("D2-6C real settlement checks passed.")
	quit(failures)

func _new_main():
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var default_resource_ids: Array[StringName] = [
		&"fire_element_shard", &"light_element_shard", &"dark_element_shard",
		&"water_element_shard", &"wood_element_shard", &"rainbow_gold_ore",
		&"crystallized_remains", &"stone_of_greed", &"abandoned_toolbox",
	]
	for card_id: StringName in default_resource_ids:
		var definition := load("res://resources/cards/%s.tres" % card_id) as CardData
		var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(definition)
		_expect(owned != null and owned.resource_shape.size() > 0 and owned.resource_shape.size() <= 5, "新运行默认拥有合法固定形状资源 %s" % card_id)
	var tuner_resources := 0
	for path: String in CardArtTuner.CARD_RESOURCE_PATHS:
		var definition := load(path) as CardData
		if definition != null and definition.card_type == CardData.CardType.RESOURCE: tuner_resources += 1
	_expect(tuner_resources == 9, "卡面调整器资源筛选来源包含九张实际资源定义")
	return main

func _minion(card_id: StringName, name: String, action_type: CardData.ActionType) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = name
	card.card_type = CardData.CardType.MINION
	card.action_type = action_type
	card.base_value = 1
	card.max_health = 10
	card.cooldown_seconds = 3.0
	return card

func _deploy(board, side: String, owned: OwnedCard) -> bool:
	for cell: Vector2i in ResourceHexLayout.valid_cells():
		for grab: Vector2i in owned.resource_shape:
			var anchor := cell - grab
			if side == "enemy":
				if board.deploy_level_resource(side, owned, anchor): return true
			elif board.try_deploy(side, String(owned.instance_id), owned.resource_shape, anchor, grab):
				return true
	return false

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
