extends SceneTree

const MAIN = preload("res://scenes/Main.tscn")
const Controller = preload("res://scripts/battle/battle_controller.gd")
const FontData: Font = preload("res://assets/fonts/chill_7.ttf")
var assertions := 0
var failures := 0
var main: Control
var pointer := Vector2.ZERO

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func move_pointer(point: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - pointer
	pointer = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.warp_mouse(point)
	root.push_input(event, true)
	await process_frame

func mouse_button(point: Vector2, button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	Input.warp_mouse(point)
	root.push_input(event, true)
	await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	main = MAIN.instantiate()
	main.short_maze_enabled = true
	main.run_save_path = "/private/tmp/project-card-feedback.json"
	root.add_child(main)
	await process_frame
	var maze = main.maze_controller
	maze.new_run(1707)
	check(maze.choose_talent("sentry_guard"), "选择天赋建立首日哨位")
	await process_frame
	check(maze._panel.get_theme_font("font") == FontData and main.ordinary_shop_status.get_theme_font("font") == FontData, "事件与商店继承卡牌正文的同一字体")
	var missing := ""
	for group: String in ["enemies", "shops", "free_events", "paid_events"]:
		for definition: Dictionary in maze.content[group]:
			for character: String in String(definition.hint):
				if not FontData.has_char(character.unicode_at(0)) and not missing.contains(character): missing += character
	check(missing.is_empty(), "路径中文全部有字形，缺字：" + missing)
	var id: String = maze.stock[0].instance_id
	var view: Control
	for child: Node in maze._sentry_bar.get_children():
		if child.get_script() == preload("res://scripts/ui/sentry_indicator_view.gd"): view = child
	check(view != null and view.build_drag_data(Vector2(15, 15)).kind == &"sentry_indicator", "四种随机图标使用独立哨位拖动身份")
	var point := view.get_global_rect().get_center()
	await move_pointer(point)
	await mouse_button(point, MOUSE_BUTTON_LEFT, true)
	await move_pointer(point + Vector2(0, 45), true)
	await move_pointer(main.front_row.get_global_rect().get_center(), true)
	check(root.gui_is_dragging(), "真实鼠标输入启动Godot原生哨位拖动")
	await mouse_button(main.front_row.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, false)
	check(maze.stock.is_empty() and maze.deployed.size() == 1 and maze.deployed[0].region == "front", "松手到前排真正提交部署与保存")
	if maze.deployed.size() == 1:
		var capacity: int = maze.deployed[0].capacity
		check(maze.drop_sentry(id, "back") and maze.deployed[0].capacity == capacity, "跨区域移动保持实例与容量")
		check(maze.drop_sentry(id, "spells") and maze.deployed[0].region == "spells", "法术板也是合法目标")
		check(maze.drop_sentry(id, "stock") and maze.stock.size() == 1, "拖回库存不消耗实例")
	check(maze.select_path(String(maze.run.paths[0].path_id)), "实际选择商店路径")
	main._toggle_ordinary_shop()
	for round_index: int in [1, 2]:
		check(maze.select_path(String(maze.run.paths[0].path_id)) and maze.complete_event(round_index == 1), "事件流程生成日末战斗路径")
	check(maze.select_path(String(maze.run.paths[0].path_id)), "选择已加强的敌人路径")
	var old_snapshot: Dictionary = maze.capture_state().duplicate(true)
	var old_paths: Array = old_snapshot.run.paths.duplicate()
	old_paths.append(old_snapshot.run.selected_path)
	for path: Dictionary in old_paths:
		for definition: Dictionary in maze.content.enemies:
			if definition.path_id != path.path_id: continue
			path.front = definition.previous_formations[0].front.duplicate()
			path.back = definition.previous_formations[0].back.duplicate()
			path.erase("previous_formations")
	check(maze.validate_state(old_snapshot), "旧存档的已生成敌阵仍可通过校验")
	old_snapshot.run.selected_path.front = ["old_wolf_kaspar"]
	check(not maze.validate_state(old_snapshot), "旧阵容兼容不允许注入其他合法卡牌")
	# 真实物品与资源OwnedCard，战斗禁止编辑时仍使用检视信号。
	main.front_row.clear_squads()
	var minion: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	var item: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/coarse_bandage.tres"))
	var squad := SquadData.from_owned_card(minion)
	check(squad.equip_item(item), "真实随从装备粗麻绷带")
	main.front_row.add_squad(squad, 0)
	main.current_phase = main.GamePhase.BATTLE
	main._refresh_drag_availability()
	await process_frame
	var indicator: Control = main.front_row.get_squads()[0].get_equipment_indicator()
	indicator._on_mouse_entered()
	check(not indicator.drag_enabled and is_instance_valid(indicator._hover_card) and indicator._hover_card.card_data == item.card_data, "战斗物品无法拖动但悬停显示完整原卡")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = indicator.size * 0.5
	indicator._gui_input(right)
	check(main._inspection_owned_card == item and is_instance_valid(main._inspection_overlay) and paused, "物品右键进入只读检视并暂停战斗")
	main._close_card_inspection(true)
	check(not paused, "关闭物品检视恢复战斗")
	for side: String in ["player", "enemy"]:
		var tray: Control = main.player_resource_tray if side == "player" else main.enemy_resource_tray
		var card: OwnedCard
		for owned: OwnedCard in main.resource_board_state.get_level_resource_cards(side):
			card = owned
			break
		if card == null:
			card = main.owned_card_collection.create_card(load("res://resources/cards/rainbow_gold_ore.tres"))
			main.resource_board_state.disabled_by_side[side].clear()
			main.resource_board_state.try_deploy(side, String(card.instance_id), card.resource_shape, Vector2i(2, 2), Vector2i.ZERO, Vector2.ZERO)
			var resource_cards: Array[OwnedCard] = [card]
			tray.set_owned_cards(resource_cards)
		tray.set_drop_enabled(false)
		tray._set_hover_instance(card.instance_id)
		check(is_instance_valid(tray._hover_card) and tray._hover_card.card_data == card.card_data, side + "战斗资源弹窗显示正确实例")
		var cell: Variant = tray._piece_by_cell.keys()[0]
		right.position = tray.LAYOUT_ORIGIN + tray.Layout.center(cell)
		tray._gui_input(right)
		check(main._inspection_owned_card == card and is_instance_valid(main._inspection_overlay), side + "资源右键只读检视")
		main._close_card_inspection(true)
		tray._on_mouse_exited()
	main.current_phase = main.GamePhase.PREPARE
	main.queue_free()
	await process_frame
	await _death_tests()
	print("D2-8反馈回归：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func _death_tests() -> void:
	var successful_seed := -1
	var gains := 0
	for seed_value: int in 40:
		var collection := OwnedCardCollection.new()
		var owned := collection.create_card(load("res://resources/cards/militia.tres"))
		var controller := Controller.new()
		root.add_child(controller)
		controller.start_battle([{"squad_data": SquadData.from_owned_card(owned), "row_key": &"player_front", "formation_index": 0}], [{"squad_data": SquadData.from_card(load("res://resources/cards/heavy_knight.tres")), "row_key": &"enemy_front", "formation_index": 0}], seed_value, false, &"death_test")
		controller._random.seed = seed_value
		var state: BattleSquadState = controller.player_states[0]
		state.current_health = 0.0
		controller._finalize_batch()
		check(controller._death_wound_checked.size() == 1, "首次实际死亡只登记一次概率机会")
		var entries: Array[Dictionary] = controller.owned_card_change_ledger.get_entries()
		var before := owned.wound_slots.duplicate(true)
		if not entries.is_empty():
			gains += 1
			successful_seed = seed_value
			check(not state.get_unmasked_active_injuries().is_empty(), "新伤势立即进入本场生效实例")
		state.revive_at_current_maximum(1.0)
		state.current_health = 0.0
		controller._finalize_batch()
		check(owned.wound_slots == before and controller.owned_card_change_ledger.get_entries().size() == entries.size(), "复活后再次阵亡不重抽或新增")
		controller.clear_battle()
		controller.queue_free()
		await process_frame
	check(gains > 10 and gains < 30, "固定40个种子的概率实际有成功与失败")
	await _persistence_and_upgrade(successful_seed)

func _persistence_and_upgrade(seed_value: int) -> void:
	var collection := OwnedCardCollection.new()
	var owned := collection.create_card(load("res://resources/cards/militia.tres"))
	var main_instance: Control = MAIN.instantiate()
	main_instance.run_save_path = "/private/tmp/project-card-death-save.json"
	root.add_child(main_instance)
	await process_frame
	main_instance.owned_card_collection = collection
	main_instance.front_row.clear_squads()
	main_instance.back_row.clear_squads()
	main_instance.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	check(main_instance.start_battle(seed_value, false), "通过实际Main开战并建立战前快照")
	var controller: Node = main_instance.battle_controller
	controller._random.seed = seed_value
	var state: BattleSquadState = controller.player_states[0]
	state.current_health = 0.0
	controller._finalize_batch()
	check(not controller.owned_card_change_ledger.get_entries().is_empty(), "首次死亡登记永久伤势账本")
	check(main_instance.save_run_to_path(main_instance.run_save_path) == OK and main_instance.load_run_from_path(main_instance.run_save_path), "未完成战斗保存后可回到战前")
	owned = main_instance.owned_card_collection.get_cards()[0]
	check(owned.wound_slots.all(func(wound: Dictionary) -> bool: return wound.is_empty()), "中断读档回退首次死亡新增伤势")
	check(main_instance.start_battle(seed_value, false), "中断后仍能开始相同战斗")
	controller = main_instance.battle_controller
	controller._random.seed = seed_value
	state = controller.player_states[0]
	state.current_health = 0.0
	controller._finalize_batch()
	var wound_before := owned.wound_slots.duplicate(true)
	controller._check_battle_result()
	check(bool(main_instance.settle_current_battle().get("success", false)), "死亡伤势参与真实战后结算")
	check(owned.wound_slots == wound_before and main_instance.save_run_to_path(main_instance.run_save_path) == OK, "结算不重复追加伤势并保存")
	var loaded: bool = main_instance.load_run_from_path(main_instance.run_save_path)
	check(loaded and JSON.parse_string(JSON.stringify(main_instance.owned_card_collection.get_cards()[0].wound_slots)) == JSON.parse_string(JSON.stringify(wound_before)), "死亡伤势读档保留")
	main_instance.queue_free()
	await process_frame
	# 只有一个可升级槽，其余满级；成功死亡必须升级原槽。
	for index: int in owned.wound_slots.size():
		owned.set_wound_slot(index, {"wound_id": &"骨折Ⅱ", "level": 2})
	owned.set_wound_slot(0, {"wound_id": &"骨折Ⅰ", "level": 1})
	controller = Controller.new()
	root.add_child(controller)
	var formation: Array[Dictionary] = [{"squad_data": SquadData.from_owned_card(owned), "row_key": &"player_front", "formation_index": 0}]
	var enemies: Array[Dictionary] = [{"squad_data": SquadData.from_card(load("res://resources/cards/heavy_knight.tres")), "row_key": &"enemy_front", "formation_index": 0}]
	controller.start_battle(formation, enemies, seed_value, false)
	controller._random.seed = seed_value
	state = controller.player_states[0]
	state.current_health = 0.0
	controller._finalize_batch()
	check(owned.wound_slots[0].wound_id == &"骨折Ⅱ" and int(owned.wound_slots[0].level) == 2, "无空槽时升级唯一合法旧伤势")
	controller.clear_battle()
	controller.start_battle(formation, enemies, seed_value, false)
	controller._random.seed = seed_value
	state = controller.player_states[0]
	var full_before := owned.wound_slots.duplicate(true)
	state.current_health = 0.0
	controller._finalize_batch()
	check(owned.wound_slots == full_before and controller.owned_card_change_ledger.get_entries().is_empty(), "满槽且无可升级伤势时不生效也无额外奖励")
	owned.set_wound_slot(0, {"wound_id": &"骨折Ⅰ", "level": 1})
	controller.clear_battle()
	controller.start_battle(formation, enemies, seed_value, false)
	controller._random.seed = seed_value
	state = controller.player_states[0]
	state.mask_injury(StringName("%s:wound:0" % owned.instance_id), 1234)
	state.current_health = 0.0
	controller._finalize_batch()
	check(owned.wound_slots[0].wound_id == &"骨折Ⅰ", "战斗效果遮蔽的旧伤势不进入升级候选")
	controller.clear_battle()
	controller.queue_free()
	await process_frame
