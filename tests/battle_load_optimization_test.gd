extends SceneTree

## 验证正式排节点的跨排动画事务，以及空槽快速路径不遗漏真实状态。
const MAIN := preload("res://scenes/Main.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("负载优化回归超时"); quit(2))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	_test_occupied_slots()
	root.size = Vector2i(1280, 720)
	var main := MAIN.instantiate()
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-load-regression.json"
	root.add_child(main)
	await process_frame
	await process_frame
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]: row.clear_squads()
	var rng := RandomNumberGenerator.new()
	rng.seed = 719
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row]:
		for index: int in 2:
			var card: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/twilight_guard.tres"), rng)
			card.rune_revealed.fill(true)
			row.add_squad(SquadData.from_owned_card(card), index)
	main._set_battle_target_priority_display_enabled(true)
	var rebuilt: BoardSlot = main.front_row.get_squads()[0]
	var replacement: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/heavy_knight.tres"), rng)
	rebuilt.set_squad_data(SquadData.from_owned_card(replacement))
	check(rebuilt.get_card_views()[0]._battle_target_weight_display_enabled, "重建卡面继承小队目标权重显示开关")
	rebuilt.set_target_priority_display_enabled(true)
	check(rebuilt.get_card_views()[0]._battle_target_weight_display_enabled, "相同开关快速返回仍保持新卡面一致")
	main._set_battle_target_priority_display_enabled(false)
	check(not rebuilt.get_card_views()[0]._battle_target_weight_display_enabled, "关闭开关即时更新重建卡面")
	check(main.start_battle(719, false), "正式阵容开始战斗")
	var battle: BattleController = main.battle_controller
	battle.set_process(false)
	await process_frame
	await process_frame
	var a: BattleSquadState = battle.player_states[1]
	var b: BattleSquadState = battle.player_states[3]
	var slot_a: BoardSlot = main._battle_state_slots[a]
	var slot_b: BoardSlot = main._battle_state_slots[b]
	var point_a := slot_a.card_visual_layer.get_global_transform_with_canvas().origin
	var point_b := slot_b.card_visual_layer.get_global_transform_with_canvas().origin
	check(battle.silvermoon.swap(a, b), "交换两排尾端卡牌")
	check(slot_a.get_parent() == main.back_row.squad_row and slot_b.get_parent() == main.front_row.squad_row, "规则换位当刻同步节点归属")
	check(main.back_row._pending_layout_positions.get(slot_a) == point_a, "新排尾端仍保留跨排视觉起点")
	check(main.front_row._pending_layout_positions.get(slot_b) == point_b, "交换另一方也保留跨排视觉起点")
	check(not battle.has_effective_dazzling(a) and battle.has_effective_dazzling(b), "换位后光环即时使用新排位置")
	check(battle.silvermoon.swap(a, b) and battle.silvermoon.swap(a, b), "同帧连续三次换位")
	check(main.back_row._pending_layout_positions.get(slot_a) == point_a and main.front_row._pending_layout_positions.get(slot_b) == point_b, "同帧多次换位沿用最早视觉起点")
	for state: BattleSquadState in battle.player_states:
		var row: BattlefieldRow = main._row_for_battle_key(state.row_key)
		var slot: BoardSlot = main._battle_state_slots[state]
		check(slot.get_parent() == row.squad_row and row.get_slot_index(slot) == state.formation_index, "显示顺序与逻辑位置逐卡一致")
	await process_frame
	await process_frame
	var revision: int = main.front_row._layout_transaction_revision
	main._sync_battle_formation_positions()
	main.front_row.move_squad_slot(slot_b, main.front_row.get_slot_index(slot_b))
	check(main.front_row._layout_transaction_revision == revision, "无位移同步不重复创建布局事务")
	check(a.get_runtime_rune_overrides_by_card().is_empty(), "空覆盖快速返回")
	var source := a.get_effect_source()
	check(a.set_runtime_rune_override(source, 0, CardData.ElementType.LIGHT), "运行时实际改变符文")
	check(a.get_runtime_rune_overrides_by_card().get(source, {}).get(0) == CardData.ElementType.LIGHT, "非空覆盖仍即时读取")
	battle.clear_battle()
	main.queue_free()
	await process_frame
	await process_frame
	print("负载优化回归：%d 项，%d 失败" % [checks, failures])
	quit(failures)

func _test_occupied_slots() -> void:
	var owned := OwnedCard.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 718
	owned.initialize(load("res://resources/cards/heavy_knight.tres"), &"load_slots", 0, rng)
	var squad := SquadData.from_owned_card(owned)
	var source := squad.get_effect_source()
	check(squad.get_visible_wound_slots().size() == owned.wound_slots.size(), "默认槽查询保留所有空伤势槽")
	check(squad.get_visible_emblem_slot_indices(source).size() == owned.emblem_slots.size(), "默认槽查询保留所有空纹章槽")
	check(squad.get_visible_wound_slots(true).is_empty() and squad.get_visible_emblem_slot_indices(source, true).is_empty(), "属性查询省去空槽")
	owned.wound_slots[0] = {"wound_id": &"贪婪"}
	owned.emblem_slots[0] = {"emblem_id": &"盾牌Ⅰ", "instance_id": &"load_shield"}
	check(squad.get_visible_wound_slots(true).size() == 1, "安装伤势后立即返回实际槽")
	check(squad.get_visible_emblem_slot_indices(source, true) == [0], "安装纹章后立即返回实际槽")
	check(squad.get_effective_action_base_value() == 1, "贪婪属性不受空槽过滤影响")
	check(squad.get_visible_status_static_modifier(&"base_armor") > 0, "真实纹章属性仍生效")
