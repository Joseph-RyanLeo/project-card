extends RefCounted

## 遭遇配置只描述内容；生成的NPC实例和阵容用现有存档编码保存。
const SaveService = preload("res://scripts/data/run_save_service.gd")
const ROW_CAPACITY: int = 21 # 每排沿用正式战场的21单元容量
const RUNE_MARKERS := {"火贴纸": 0, "水贴纸": 1, "木贴纸": 2, "光贴纸": 3, "暗贴纸": 4, "混沌贴纸": -1}

static func load_card_definitions() -> Dictionary:
	var registry: Dictionary = {}
	var filenames := ResourceLoader.list_directory("res://resources/cards")
	filenames.sort()
	for filename: String in filenames:
		if filename.get_extension() != "tres": continue
		var card := ResourceLoader.load("res://resources/cards/" + filename) as CardData
		if card != null and not card.id.is_empty(): registry[card.id] = card
	return registry


static func deploy_resources(path: Dictionary, registry: Dictionary, board: ResourceBoardState) -> Array[OwnedCard]:
	var deployed: Array[OwnedCard] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(path.battle_seed) ^ 0x5EED
	for id: String in path.get("resources", []):
		var definition := registry.get(StringName(id)) as CardData
		if definition == null or definition.card_type != CardData.CardType.RESOURCE: return []
		var owned := OwnedCard.new()
		owned.initialize(definition, StringName("encounter_resource_%04d" % (board.level_resource_cards.enemy.size() + 1)), 0, rng)
		var placed := false
		for anchor: Vector2i in ResourceHexLayout.valid_cells():
			if board.deploy_level_resource("enemy", owned, anchor):
				placed = true
				break
		if not placed: return []
		deployed.append(owned)
	return deployed


static func place_level_resources(path: Dictionary, registry: Dictionary, board: ResourceBoardState) -> bool:
	if path.has("visual"): return _deploy_authored_resources(path, registry, board)
	return deploy_resources(path, registry, board).size() == path.get("resources", []).size()


static func _deploy_authored_resources(path: Dictionary, registry: Dictionary, board: ResourceBoardState) -> bool:
	# 先在独立板上安放手摆的拼图，再用剩余格子安置已有的自动资源。
	var draft := ResourceBoardState.new()
	var blocked: Array[Vector2i] = []
	if not _decode_cells(path.visual.blocked, blocked): return false
	for cell: Vector2i in blocked:
		if not ResourceHexLayout.is_valid_cell(cell): return false
	draft.disabled_by_side.enemy.assign(blocked)
	for index: int in path.visual.resources.size():
		var entry: Variant = path.visual.resources[index]
		if not entry is Dictionary or not entry.get("card_id") is String: return false
		var def := registry.get(StringName(entry.card_id)) as CardData
		var anchor: Array[Vector2i] = []
		var shape: Array[Vector2i] = []
		if def == null or def.card_type != CardData.CardType.RESOURCE or not _decode_cells([entry.get("anchor")], anchor) or not _decode_cells(entry.get("shape"), shape): return false
		if shape.size() != int(def.rarity) + 1 or not ResourceHexLayout.is_connected_shape(shape): return false
		var owned := OwnedCard.new()
		owned.initialize(def, StringName("authored_resource_%04d" % index), index)
		owned.resource_shape.assign(shape)
		if not draft.deploy_level_resource("enemy", owned, anchor[0]): return false
	var reserved := {}
	for placement: Dictionary in draft.deployments.enemy.values():
		for cell: Array in placement.shape: reserved[Vector2i(placement.anchor[0] + cell[0], placement.anchor[1] + cell[1])] = true
	for cell: Vector2i in board.disabled_by_side.enemy:
		if not reserved.has(cell) and cell not in draft.disabled_by_side.enemy: draft.disabled_by_side.enemy.append(cell)
	for automated: OwnedCard in board.get_level_resource_cards("enemy"):
		var old: Dictionary = board.deployments.enemy.get(String(automated.instance_id), {})
		if not old.is_empty() and draft.deploy_level_resource("enemy", automated, Vector2i(old.anchor[0], old.anchor[1])): continue
		for anchor: Vector2i in ResourceHexLayout.valid_cells():
			if draft.deploy_level_resource("enemy", automated, anchor): break
	board.disabled_by_side.enemy = draft.disabled_by_side.enemy
	board.level_resource_cards.enemy = draft.level_resource_cards.enemy
	board.deployments.enemy = draft.deployments.enemy
	board.authored_enemy_layout = true
	board.resources_generated = true
	return true


static func _decode_cells(value: Variant, cells: Array[Vector2i]) -> bool:
	if not value is Array: return false
	for pair: Variant in value:
		if not pair is Array or pair.size() != 2: return false
		for axis: Variant in pair:
			if not (axis is float or axis is int) or not is_finite(float(axis)) or absf(float(axis)) > 32 or int(axis) != axis: return false
		var cell := Vector2i(pair[0], pair[1])
		if cell in cells: return false
		cells.append(cell)
	return true


func build(path: Dictionary, registry: Dictionary, revealed_count: int, emblem_count: int = 0) -> Dictionary:
	if path.has("visual"): return _build_authored(path, registry)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(path.battle_seed)
	var collection := OwnedCardCollection.new()
	var rows := {&"player_front": [], &"player_back": [], &"enemy_front": [], &"enemy_back": []}
	for region: String in ["front", "back"]:
		var used_units := 0
		for entry: Variant in path[region]:
			var config: Dictionary = {"cards": [entry]} if entry is String else entry
			var wounds: Array = config.get("wounds", [])
			if not wounds.is_empty() and config.cards.size() != 1: return {}
			var squad: SquadData = null
			for id: String in config.cards:
				var owned := _create_card(id, CardData.CardType.MINION, collection, registry, rng)
				if owned == null: return {}
				for index: int in wounds.size():
					var wound_id := String(wounds[index])
					if not EmblemLibraryData.get_wound_definitions().any(func(wound: Dictionary): return wound.id == StringName(wound_id)):
						return {}
					var level := 3 if wound_id.ends_with("Ⅲ") else (2 if wound_id.ends_with("Ⅱ") else 1)
					if not owned.set_wound_slot(index, {
						"wound_id": StringName(wound_id), "level": level, "temporary": false,
						"instance_id": StringName("%s:wound:%d" % [owned.instance_id, index]), "source": "encounter",
					}): return {}
				var slots: Array[int] = []
				for slot_index: int in owned.rune_revealed.size(): slots.append(slot_index)
				for index: int in mini(revealed_count, slots.size()):
					owned.rune_revealed[slots.pop_at(rng.randi_range(0, slots.size() - 1))] = true
				var emblem_pool := EmblemLibraryData.get_basic_emblem_ids()
				var empty_slots: Array[int] = []
				for index: int in owned.emblem_slots.size(): empty_slots.append(index)
				for index: int in mini(emblem_count, empty_slots.size()):
					if emblem_pool.is_empty(): break
					var slot_index: int = empty_slots.pop_at(rng.randi_range(0, empty_slots.size() - 1))
					owned.set_emblem_slot(slot_index, {"emblem_id": emblem_pool[rng.randi_range(0, emblem_pool.size() - 1)], "instance_id": StringName("%s:emblem:%d" % [owned.instance_id, slot_index]), "temporary": false, "source": "encounter_day"})
				if squad == null:
					squad = SquadData.from_owned_card(owned)
				else:
					var layout := SquadData.TwoCardLayout.COMPACT if config.get("layout", "expanded") == "compact" else SquadData.TwoCardLayout.EXPANDED
					if not squad.insert_card(owned.get_battlefield_card(), squad.get_card_count(), layout): return {}
					squad.bind_owned_card(owned.get_battlefield_card(), owned)
			if squad == null: return {}
			# 显式指定哪张在顶层，避免配置顺序被插卡默认置顶改变。
			squad.layer_cards.assign(squad.horizontal_cards)
			var top := int(config.get("top", 0))
			if top < 0 or top >= squad.get_card_count(): return {}
			var top_card: CardData = squad.layer_cards.pop_at(top)
			squad.layer_cards.push_front(top_card)
			if config.has("equipment"):
				var equipment := _create_card(config.equipment, CardData.CardType.EQUIPMENT, collection, registry, rng)
				if equipment == null or not squad.equip_item(equipment): return {}
			used_units += squad.get_unit_count()
			if not squad.is_valid() or used_units > ROW_CAPACITY: return {}
			rows[StringName("enemy_" + region)].append(squad)
	var spell_ids: Array[String] = []
	for id: String in path.get("spells", []):
		var spell := _create_card(id, CardData.CardType.SPELL, collection, registry, rng)
		if spell == null: return {}
		spell_ids.append(String(spell.instance_id))
	if spell_ids.size() > 10: return {}
	var service := SaveService.new()
	return {"status_slot_migration_version": SaveService.STATUS_SLOT_MIGRATION_VERSION, "collection": service._encode_collection_state(collection.capture_state()), "rows": service._encode_rows(rows), "spell_ids": spell_ids}


func _build_authored(path: Dictionary, registry: Dictionary) -> Dictionary:
	var checked := restore(path.visual.encounter, registry)
	if checked.is_empty() or checked.spells.size() > 10: return {}
	if not checked.rows[&"player_front"].is_empty() or not checked.rows[&"player_back"].is_empty(): return {}
	var count := 0
	for key: StringName in [&"enemy_front", &"enemy_back"]:
		var used := 0
		for squad: SquadData in checked.rows[key]:
			used += squad.get_unit_count()
			count += 1
		if used > ROW_CAPACITY: return {}
	if count == 0: return {}
	var data: Dictionary = checked.snapshot
	var rng := RandomNumberGenerator.new()
	rng.seed = int(path.battle_seed)
	for card: Dictionary in data.collection.cards:
		var definition := registry.get(StringName(card.card_id)) as CardData
		if definition == null or definition.card_type != CardData.CardType.MINION: continue
		var fresh := OwnedCard.new()
		fresh.initialize(definition, StringName(card.instance_id), int(card.acquisition_order), rng)
		for index: int in fresh.resolved_runes.size():
			var marker: Dictionary = card.rune_stickers[index]
			var name := String(marker.get("emblem_id", ""))
			card.rune_revealed[index] = RUNE_MARKERS.has(name)
			card.resolved_runes[index] = int(RUNE_MARKERS[name]) if RUNE_MARKERS.has(name) and int(RUNE_MARKERS[name]) >= 0 else fresh.resolved_runes[index]
			card.rune_stickers[index] = {}
			card.rune_scrape_masks[index] = ""
	return data

func restore(snapshot: Dictionary, registry: Dictionary) -> Dictionary:
	var service := SaveService.new()
	var migrate_slots := int(snapshot.get("status_slot_migration_version", 0)) < SaveService.STATUS_SLOT_MIGRATION_VERSION
	var decoded := service._decode_collection_state(
		snapshot.get("collection", {}), registry, true, migrate_slots,
		SaveService.SCHEMA_VERSION, false, migrate_slots
	)
	var collection := OwnedCardCollection.new()
	if not decoded.get("success", false) or not collection.restore_state(decoded.state): return {}
	var rows := service._decode_rows(snapshot.get("rows", {}), collection, registry, collection)
	if not rows.get("success", false): return {}
	var spells: Array[OwnedCard] = []
	for id: String in snapshot.get("spell_ids", []):
		var spell := collection.get_by_instance_id(StringName(id))
		if spell == null or spell.card_data.card_type != CardData.CardType.SPELL: return {}
		spells.append(spell)
	var normalized_snapshot := snapshot.duplicate(true)
	normalized_snapshot["status_slot_migration_version"] = SaveService.STATUS_SLOT_MIGRATION_VERSION
	normalized_snapshot["collection"] = service._encode_collection_state(collection.capture_state())
	return {"rows": rows.rows, "spells": spells, "snapshot": normalized_snapshot, "owned": collection.get_cards()}

func _create_card(id: String, type: int, collection: OwnedCardCollection, registry: Dictionary, rng: RandomNumberGenerator) -> OwnedCard:
	var definition: CardData = registry.get(StringName(id))
	if definition == null or definition.card_type != type: return null
	var owned := OwnedCard.new()
	owned.initialize(definition, StringName("encounter_card_%04d" % (collection.size() + 1)), collection.size(), rng)
	if not collection.add_existing(owned): return null
	return owned
