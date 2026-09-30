extends SceneTree

const Layout = preload("res://scripts/data/resource_hex_layout.gd")
const ResourceBoardState = preload("res://scripts/data/resource_board_state.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const OwnedCardCollection = preload("res://scripts/data/owned_card_collection.gd")
const RunSaveService = preload("res://scripts/data/run_save_service.gd")
const RunRewardState = preload("res://scripts/data/run_reward_state.gd")
const RunSettlementJournal = preload("res://scripts/data/run_settlement_journal.gd")
const ResourcePreparationTray = preload("res://scripts/ui/resource_preparation_tray.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_fixed_geometry_and_translation()
	_test_connected_shapes_and_placement()
	_test_board_snapshot_and_invalid_placement()
	_test_level_resource_generation_and_roundtrip()
	_test_owned_resource_shape_snapshot()
	await _test_resource_tray_lifecycle_and_payload()
	await _test_legacy_save_migration()
	if failures == 0:
		print("D2-6C resource layout checks passed.")
	quit(failures)

func _test_fixed_geometry_and_translation() -> void:
	var cells := Layout.valid_cells()
	_expect(cells.size() == 27, "图4几何包含27格")
	_expect(Layout.center(Vector2i(0, 0)) == Vector2(17, 32) and Layout.center(Vector2i(1, 0)) == Vector2(44, 16) and Layout.center(Vector2i(5, 6)) == Vector2(152, 144), "六列交错中心坐标对应图4")
	for size in range(1, 6):
		var rng := RandomNumberGenerator.new()
		rng.seed = size * 101
		var shape := Layout.create_random_shape(size, rng)
		for first in shape:
			for second in Layout.neighbors(first):
				if not shape.has(second): continue
				var vector := Layout.center(second) - Layout.center(first)
				for anchor in cells:
					var translated_first := anchor + first
					var translated_second := anchor + second
					if Layout.center(translated_second) - Layout.center(translated_first) != vector:
						_expect(false, "%d格形状跨奇偶列平移仍保持像素邻接向量" % size)
						return
		_expect(true, "%d格形状邻接向量跨奇偶列稳定" % size)

func _test_connected_shapes_and_placement() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9182
	for size in range(1, 6):
		var shape := Layout.create_random_shape(size, rng)
		_expect(shape.size() == size and Layout.is_connected_shape(shape) and Layout.find_any_placement(shape), "%d格形状唯一、相连且可部署" % size)
	_expect(not Layout.can_place([Vector2i(0, 0), Vector2i(3, 0)], Vector2i(0, 0), {}, {}), "不相连形状不能部署")

func _test_board_snapshot_and_invalid_placement() -> void:
	var generated := ResourceBoardState.new()
	var disabled_rng := RandomNumberGenerator.new()
	disabled_rng.seed = 783
	_expect(generated.initialize_level(&"level_generated", disabled_rng), "关卡禁用格生成初始化成功")
	for side in ["player", "enemy"]:
		var generated_cells: Array = generated.disabled_by_side[side]
		var unique: Dictionary = {}
		for cell in generated_cells: unique[cell] = true
		_expect(generated_cells.size() <= 3 and unique.size() == generated_cells.size(), "每侧禁用格数量不超3且不重复")
	var board := ResourceBoardState.new()
	board.level_id = &"level_demo_01"
	board.disabled_by_side["player"] = [Vector2i(0, 0)]
	var one: Array[Vector2i] = [Vector2i(0, 0)]
	_expect(board.try_deploy("player", "ore_a", one, Vector2i(1, 0), Vector2i(0, 0)), "合法资源部署成功")
	var before := board.capture_state()
	_expect(not board.try_deploy("player", "ore_b", one, Vector2i(1, 0), Vector2i(0, 0)) and board.capture_state() == before, "非法冲突部署不改变原状态")
	_expect(not board.try_deploy("player", "ore_a", one, Vector2i(9, 9), Vector2i(0, 0)) and board.capture_state() == before, "已有部署非法移动时保留原位置")
	_expect(not board.try_deploy("player", "ore_b", one, Vector2i(0, 0), Vector2i(0, 0)), "禁用格不可部署")
	var encoded := JSON.stringify(board.capture_state())
	var restored := ResourceBoardState.new()
	var restored_ok := restored.restore_state(JSON.parse_string(encoded))
	_expect(restored_ok and JSON.stringify(restored.capture_state()) == encoded, "禁用格、部署和关卡标识经过JSON往返稳定")

func _test_level_resource_generation_and_roundtrip() -> void:
	var quantity_counts := [0, 0, 0, 0]
	for roll in range(4): quantity_counts[ResourceBoardState.count_for_roll(roll)] += 1
	_expect(quantity_counts == [1, 1, 1, 1], "0—3张数量掷点均匀覆盖四种结果")
	var rarity_counts := [0, 0, 0]
	for roll in range(99): rarity_counts[ResourceBoardState.rarity_for_roll(roll)] += 1
	_expect(rarity_counts == [75, 20, 4], "资源稀有度掷点精确对应75/99、20/99、4/99")
	var definitions: Array[CardData] = []
	var registry: Dictionary = {}
	for path in [
		"res://resources/cards/wood_element_shard.tres",
		"res://resources/cards/fire_element_shard.tres",
		"res://resources/cards/water_element_shard.tres",
		"res://resources/cards/light_element_shard.tres",
		"res://resources/cards/dark_element_shard.tres",
		"res://resources/cards/rainbow_gold_ore.tres",
		"res://resources/cards/stone_of_greed.tres",
		"res://resources/cards/crystallized_remains.tres",
		"res://resources/cards/abandoned_toolbox.tres",
		"res://resources/cards/dark_element_shard.tres",
	]:
		var definition := load(path) as CardData
		if definition != null and not registry.has(definition.id):
			definitions.append(definition)
			registry[definition.id] = definition
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260930
	var board := ResourceBoardState.new()
	_expect(board.initialize_level(&"generated_roundtrip", rng), "随机资源测试关初始化")
	var result := board.generate_level_resources(definitions, rng)
	_expect(bool(result.get("success", false)) and board.resources_generated, "一关双方资源只生成一次并写入生成标记")
	for side in ["player", "enemy"]:
		var cards := board.get_level_resource_cards(side)
		_expect(cards.size() <= 3 and board.deployments[side].size() == cards.size(), "%s自动资源为0—3张且全部有部署" % side)
		var occupied: Dictionary = {}
		var disabled: Dictionary = {}
		for cell: Vector2i in board.disabled_by_side[side]: disabled[cell] = true
		for owned: OwnedCard in cards:
			var placement: Dictionary = board.deployments[side][String(owned.instance_id)]
			var anchor := Vector2i(int(placement.anchor[0]), int(placement.anchor[1]))
			_expect(owned.resource_shape.size() == int(owned.card_data.rarity) + 1 and Layout.can_place(owned.resource_shape, anchor, occupied, disabled), "%s资源形状合法且未占禁用/重叠格" % side)
			for offset: Vector2i in owned.resource_shape: occupied[anchor + offset] = owned.instance_id
			_expect(board.is_level_resource(side, String(owned.instance_id)) and not board.try_deploy(side, String(owned.instance_id), owned.resource_shape, anchor, owned.resource_shape[0]), "自动资源属于关卡且不能进入手动部署流程")
	var encoded := JSON.stringify(board.capture_state())
	var restored := ResourceBoardState.new()
	var restored_ok := restored.restore_state(JSON.parse_string(encoded), registry)
	_expect(restored_ok and JSON.stringify(restored.capture_state()) == encoded, "存档恢复保留本关抽牌实例、形状、位置与生成标记，不重新抽取")
	_expect(not board.generate_level_resources(definitions, rng).get("success", false), "刷新请求不能重复生成本关资源")

func _test_owned_resource_shape_snapshot() -> void:
	var card := load("res://resources/cards/rainbow_gold_ore.tres") as CardData
	var owned := OwnedCard.new()
	owned.initialize(card, &"resource_instance_test", 0)
	var saved := owned.capture_state()
	var shape := owned.resource_shape.duplicate()
	var restored := OwnedCard.new()
	_expect(restored.restore_state(saved) and restored.resource_shape == shape, "OwnedCard 快照往返保留获得时的形状")

func _test_resource_tray_lifecycle_and_payload() -> void:
	var definition := (load("res://resources/cards/wood_element_shard.tres") as CardData).duplicate() as CardData
	definition.rarity = CardData.Rarity.I
	var owned := OwnedCard.new()
	owned.initialize(definition, &"tray_overlay_test", 0)
	var board := ResourceBoardState.new()
	board.level_id = &"tray_overlay_level"
	var one: Array[Vector2i] = [Vector2i.ZERO]
	_expect(board.try_deploy("player", String(owned.instance_id), one, Vector2i.ZERO, Vector2i.ZERO), "悬停预览测试资源放置到板上")
	var host := Control.new()
	root.add_child(host)
	var tray := ResourcePreparationTray.new()
	tray.configure(board, "player")
	host.add_child(tray)
	tray.set_owned_cards([owned])
	await process_frame
	_expect(is_instance_valid(tray._overlay) and tray._overlay.is_inside_tree() and not tray._overlay.is_queued_for_deletion(), "首帧刷新后悬停/落点绘制层仍留在场景树")
	var payload := {"owned_card": owned, "source_type": &"collection", "grab_local_position": Vector2(49, 68)}
	var pointer := tray.get_global_transform_with_canvas() * (tray.LAYOUT_ORIGIN + Layout.center(Vector2i.ZERO))
	var resolution := tray.update_preview(pointer, payload)
	tray.clear_preview()
	await process_frame
	_expect(payload.get("owned_card") == owned and payload.get("source_type") == &"collection", "离开落点预览后原始拖拽payload保持完整")
	_expect(is_instance_valid(tray._overlay) and tray._overlay.is_inside_tree(), "等待下一帧后预览绘制层仍可重绘")
	_expect(resolution.has("has_target"), "鼠标落在资源板时共享解析返回落点预览")
	host.queue_free()
	await process_frame

func _test_legacy_save_migration() -> void:
	var definition := (load("res://resources/cards/rainbow_gold_ore.tres") as CardData).duplicate() as CardData
	definition.rarity = CardData.Rarity.V
	var collection := OwnedCardCollection.new()
	var owned := collection.create_card(definition)
	var rows := {"player_front": [], "player_back": [], "enemy_front": [], "enemy_back": []}
	var service := RunSaveService.new()
	var reward := RunRewardState.new()
	reward.add_ground_item({"ground_id": "ground_overflow_01", "item_kind": "emblem", "item_id": "seed", "instance_id": "ground_overflow_01"})
	var journal := RunSettlementJournal.new()
	var card_registry := {definition.id: definition}
	var resource_board := ResourceBoardState.new()
	var board_rng := RandomNumberGenerator.new()
	board_rng.seed = 551
	resource_board.initialize_level(&"save_level_01", board_rng)
	var player_shape := owned.resource_shape
	var player_anchor := _find_available_anchor(player_shape, resource_board.disabled_by_side["player"])
	_expect(Layout.is_valid_cell(player_anchor) and resource_board.try_deploy("player", String(owned.instance_id), player_shape, player_anchor, player_shape[0], Vector2(3.5, -2.0)), "玩家收藏资源可带抓取偏移写入资源板")
	var enemy_owned := OwnedCard.new()
	enemy_owned.initialize(definition, &"enemy_resource_test", 0)

	var enemy_anchor := _find_available_anchor(enemy_owned.resource_shape, resource_board.disabled_by_side["enemy"])
	_expect(Layout.is_valid_cell(enemy_anchor) and resource_board.deploy_level_resource("enemy", enemy_owned, enemy_anchor), "敌方资源实例可独立部署")
	var checkpoint := service.create_checkpoint(collection.capture_state(), rows, 123, &"", 1, reward, journal, 0, {}, [], resource_board)
	var current_restored_collection := OwnedCardCollection.new()
	var restored_reward := RunRewardState.new()
	var current_restored := service.restore_checkpoint(checkpoint, current_restored_collection, restored_reward, RunSettlementJournal.new(), card_registry)
	var roundtrip_board := current_restored.get("resource_board_state") as ResourceBoardState
	_expect(current_restored.get("success", false) and roundtrip_board != null and roundtrip_board.capture_state() == resource_board.capture_state(), "RunSaveService JSON往返保留双方资源部署、抓取偏移、禁用格和关卡ID")
	_expect(restored_reward.pending_ground_items.size() == 1 and restored_reward.pending_ground_items[0].get("instance_id") == "ground_overflow_01", "RunSaveService JSON往返持久保留地面临时背包奖励实例")
	_expect(roundtrip_board != null and roundtrip_board.get_level_resource_cards("enemy").size() == 1 and current_restored_collection.get_by_instance_id(enemy_owned.instance_id) == null, "敌方资源实例随资源板恢复且不进入玩家收藏")
	var legacy_schema4 := checkpoint.duplicate(true)
	legacy_schema4["schema_version"] = 4
	var legacy_board: Dictionary = legacy_schema4["resource_board_state"]
	legacy_board["enemy_resource_cards"] = legacy_board["level_resource_cards"]["enemy"]
	legacy_board.erase("level_resource_cards")
	legacy_board.erase("resources_generated")
	var migrated_v4 := service.restore_checkpoint(legacy_schema4, OwnedCardCollection.new(), RunRewardState.new(), RunSettlementJournal.new(), card_registry)
	var migrated_v4_board := migrated_v4.get("resource_board_state") as ResourceBoardState
	_expect(migrated_v4.get("success", false) and migrated_v4_board != null and migrated_v4_board.resources_generated and migrated_v4_board.get_level_resource_cards("enemy").size() == 1, "schema4敌方资源迁入新关卡容器并标记已处理，不会读档重抽")
	var old_checkpoint := checkpoint.duplicate(true)
	old_checkpoint["schema_version"] = 3
	old_checkpoint["collection"]["cards"][0].erase("resource_shape")
	old_checkpoint["resource_board_state"] = {}
	var restored_collection := OwnedCardCollection.new()
	var restored := service.restore_checkpoint(old_checkpoint, restored_collection, RunRewardState.new(), RunSettlementJournal.new(), card_registry)
	var migrated_card := restored_collection.get_by_instance_id(owned.instance_id)
	_expect(restored.get("success", false) and restored_collection.size() == 1 and migrated_card != null, "旧schema实际restore_checkpoint迁移资源实例：%s / size=%d" % [restored, restored_collection.size()])
	_expect(migrated_card != null and migrated_card.resource_shape.size() == 5, "旧存档五格资源形状迁移后保持五格")
	var corrupt_new := checkpoint.duplicate(true)
	corrupt_new["collection"]["cards"][0]["resource_shape"] = [[0, 0], [9, 9], [0, 2], [0, 3], [0, 4]]
	var rejected := service.restore_checkpoint(corrupt_new, OwnedCardCollection.new(), RunRewardState.new(), RunSettlementJournal.new(), card_registry)
	_expect(not rejected.get("success", false), "当前schema损坏的资源形状被拒绝")
	var missing_new_shape := checkpoint.duplicate(true)
	missing_new_shape["collection"]["cards"][0].erase("resource_shape")
	_expect(not service.restore_checkpoint(missing_new_shape, OwnedCardCollection.new(), RunRewardState.new(), RunSettlementJournal.new(), card_registry).get("success", false), "当前schema缺失资源形状时拒绝静默迁移")

func _find_available_anchor(shape: Array[Vector2i], disabled_cells: Array) -> Vector2i:
	var disabled: Dictionary = {}
	for cell in disabled_cells: disabled[cell] = true
	for board_cell in Layout.valid_cells():
		for shape_cell in shape:
			var anchor := board_cell - shape_cell
			if Layout.can_place(shape, anchor, {}, disabled): return anchor
	return Vector2i(99, 99)

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
