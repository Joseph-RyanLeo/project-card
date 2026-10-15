extends RefCounted

## 遭遇配置只描述内容；生成的NPC实例和阵容用现有存档编码保存。
const SaveService = preload("res://scripts/data/run_save_service.gd")
const ROW_CAPACITY: int = 21 # 每排沿用正式战场的21单元容量

func build(path: Dictionary, registry: Dictionary, revealed_count: int, emblem_count: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(path.battle_seed)
	var collection := OwnedCardCollection.new()
	var rows := {&"player_front": [], &"player_back": [], &"enemy_front": [], &"enemy_back": []}
	for region: String in ["front", "back"]:
		var used_units := 0
		for entry: Variant in path[region]:
			var config: Dictionary = {"cards": [entry]} if entry is String else entry
			var squad: SquadData = null
			for id: String in config.cards:
				var owned := _create_card(id, CardData.CardType.MINION, collection, registry, rng)
				if owned == null: return {}
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
	return {"rows": rows.rows, "spells": spells, "snapshot": normalized_snapshot}

func _create_card(id: String, type: int, collection: OwnedCardCollection, registry: Dictionary, rng: RandomNumberGenerator) -> OwnedCard:
	var definition: CardData = registry.get(StringName(id))
	if definition == null or definition.card_type != type: return null
	var owned := OwnedCard.new()
	owned.initialize(definition, StringName("encounter_card_%04d" % (collection.size() + 1)), collection.size(), rng)
	if not collection.add_existing(owned): return null
	return owned
