class_name RunSaveService
extends RefCounted

## D2-5 的本局存档边界。
## 内存快照可以保存 Resource 引用；磁盘 JSON 不可以，因此这里把卡牌定义转换为
## 稳定 card_id + resource_path，并在读取后重新绑定 OwnedCard 与 SquadData。

const OwnedCardCollection = preload("res://scripts/data/owned_card_collection.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const RunRewardState = preload("res://scripts/data/run_reward_state.gd")
const RunSettlementJournal = preload("res://scripts/data/run_settlement_journal.gd")
const CardSlotLayout = preload("res://scripts/data/card_slot_layout.gd")

const SCHEMA_VERSION: int = 2
const STATUS_SLOT_MIGRATION_VERSION: int = 1
const ROW_KEYS: Array[StringName] = [
	&"player_front",
	&"player_back",
	&"enemy_front",
	&"enemy_back",
]


func create_checkpoint(
	collection_state: Dictionary,
	rows: Dictionary,
	battle_seed: int,
	pending_battle_instance_id: StringName,
	next_battle_instance_sequence: int,
	reward_state: RunRewardState,
	settlement_journal: RunSettlementJournal,
	phase_on_save: int,
	indicator_inventory: Dictionary = {}
) -> Dictionary:
	var encoded_collection := _encode_collection_state(collection_state)
	var encoded_rows := _encode_rows(rows)
	if encoded_collection.is_empty() or encoded_rows.is_empty():
		return {}
	return {
		"schema_version": SCHEMA_VERSION,
		"status_slot_migration_version": STATUS_SLOT_MIGRATION_VERSION,
		"collection": encoded_collection,
		"rows": encoded_rows,
		"battle_seed": battle_seed,
		"pending_battle_instance_id": String(pending_battle_instance_id),
		"next_battle_instance_sequence": maxi(next_battle_instance_sequence, 1),
		"reward_state": _json_safe(reward_state.capture_state()),
		"committed_battle_ids": _encode_committed_battles(settlement_journal.capture_state()),
		"phase_on_save": phase_on_save,
		"indicator_inventory": indicator_inventory.duplicate(true),
	}


func save_checkpoint(path: String, checkpoint: Dictionary) -> Error:
	if path.is_empty() or checkpoint.is_empty():
		return ERR_INVALID_PARAMETER
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(checkpoint, "\t"))
	return OK


func load_checkpoint(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return _failure("save_file_missing")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("save_file_open_failed")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _failure("save_json_invalid")
	var checkpoint := parsed as Dictionary
	if int(checkpoint.get("schema_version", 0)) < 1 or int(checkpoint.get("schema_version", 0)) > SCHEMA_VERSION:
		return _failure("save_schema_unsupported")
	return {"success": true, "checkpoint": checkpoint}


func restore_checkpoint(
	checkpoint: Dictionary,
	owned_collection: OwnedCardCollection,
	reward_state: RunRewardState,
	settlement_journal: RunSettlementJournal,
	card_registry: Dictionary,
	test_mode: bool = true
) -> Dictionary:
	if (
		int(checkpoint.get("schema_version", 0)) < 1
		or int(checkpoint.get("schema_version", 0)) > SCHEMA_VERSION
		or owned_collection == null
		or reward_state == null
		or settlement_journal == null
	):
		return _failure("save_context_invalid")
	var decoded_collection_result := _decode_collection_state(
		checkpoint.get("collection", {}) as Dictionary,
		card_registry,
		test_mode,
		int(checkpoint.get("schema_version", 0)) < SCHEMA_VERSION
		or int(checkpoint.get("status_slot_migration_version", 0)) < STATUS_SLOT_MIGRATION_VERSION
	)
	if not bool(decoded_collection_result.get("success", false)):
		return decoded_collection_result
	var decoded_collection := decoded_collection_result.get("state", {}) as Dictionary

	# 先在临时容器中完整验证阵容引用；全部成功后才替换主流程状态。
	var validation_collection := OwnedCardCollection.new()
	if not validation_collection.restore_state(decoded_collection):
		return _failure("save_collection_invalid")
	var validation_rows := _decode_rows(
		checkpoint.get("rows", {}) as Dictionary,
		validation_collection,
		card_registry
	)
	if not bool(validation_rows.get("success", false)):
		return validation_rows
	var inventory: Dictionary = checkpoint.get("indicator_inventory", {})
	var known_indicators: Dictionary = {}
	for value: Variant in inventory.get("items", []):
		if not value is Dictionary:
			return _failure("save_indicator_inventory_invalid")
		var item := CelestialIndicator.from_state(value)
		if item == null or known_indicators.has(item.instance_id):
			return _failure("save_indicator_inventory_invalid")
		known_indicators[item.instance_id] = item.kind
	for squads: Array in (validation_rows["rows"] as Dictionary).values():
		for squad: SquadData in squads:
			for attachment: Dictionary in squad.indicator_attachments:
				var item := attachment["indicator"] as CelestialIndicator
				if known_indicators.get(item.instance_id, -1) != item.kind:
					return _failure("save_indicator_reference_invalid")
	if not owned_collection.restore_state(decoded_collection):
		return _failure("save_collection_restore_failed")
	var restored_rows := _decode_rows(
		checkpoint.get("rows", {}) as Dictionary,
		owned_collection,
		card_registry
	)
	if not bool(restored_rows.get("success", false)):
		return restored_rows

	reward_state.restore_state(_decode_reward_state(checkpoint.get("reward_state", {}) as Dictionary))
	settlement_journal.restore_state(
		_decode_committed_battles(checkpoint.get("committed_battle_ids", []) as Array)
	)
	return {
		"success": true,
		"rows": restored_rows.get("rows", {}),
		"battle_seed": maxi(int(checkpoint.get("battle_seed", 0)), 0),
		"pending_battle_instance_id": StringName(
			String(checkpoint.get("pending_battle_instance_id", ""))
		),
		"next_battle_instance_sequence": maxi(
			int(checkpoint.get("next_battle_instance_sequence", 1)),
			1
		),
		"phase_on_save": int(checkpoint.get("phase_on_save", 0)),
		"indicator_inventory": inventory.duplicate(true),
		"slot_migration_returns": decoded_collection_result.get("migration_returns", []).duplicate(true),
	}


func _encode_collection_state(collection_state: Dictionary) -> Dictionary:
	var encoded_cards: Array[Dictionary] = []
	for value: Variant in collection_state.get("cards", []) as Array:
		if not value is Dictionary:
			return {}
		var state := value as Dictionary
		var card_data := state.get("card_data") as CardData
		var instance_id := state.get("instance_id", &"") as StringName
		if card_data == null or instance_id.is_empty() or card_data.id.is_empty():
			return {}
		encoded_cards.append({
			"instance_id": String(instance_id),
			"card_id": String(card_data.id),
			"card_resource_path": card_data.resource_path,
			"acquisition_order": int(state.get("acquisition_order", -1)),
			"resolved_action_type": int(state.get("resolved_action_type", -1)),
			"spell_durability": int(state.get("spell_durability", -1)),
			"permanent_growth": _json_safe(state.get("permanent_growth", {})),
			"crystallization_health_loss": maxi(int(state.get("crystallization_health_loss", 0)), 0),
			"wound_slots": _json_safe(state.get("wound_slots", [])),
			"emblem_slots": _json_safe(state.get("emblem_slots", [])),
			"slot_layout": _json_safe(state.get("slot_layout", [])),
			"rune_revealed": _json_safe(state.get("rune_revealed", [])),
			"rune_stickers": _json_safe(state.get("rune_stickers", [])),
			"progress_by_source": _json_safe(state.get("progress_by_source", {})),
			"wound_battle_counters": _json_safe(state.get("wound_battle_counters", {})),
		})
	return {
		"next_instance_sequence": maxi(int(collection_state.get("next_instance_sequence", 1)), 1),
		"cards": encoded_cards,
	}


func _decode_collection_state(
	data: Dictionary,
	card_registry: Dictionary,
	test_mode: bool = true,
	migrate_status_slots: bool = true
) -> Dictionary:
	if not data.get("cards", []) is Array:
		return _failure("save_collection_cards_invalid")
	var card_states: Array[Dictionary] = []
	var migration_returns: Array[Dictionary] = []
	var seen_instance_ids: Dictionary = {}
	for value: Variant in data.get("cards", []) as Array:
		if not value is Dictionary:
			return _failure("save_card_state_invalid")
		var encoded := value as Dictionary
		var instance_id := StringName(String(encoded.get("instance_id", "")))
		var card_data := _resolve_card_definition(
			String(encoded.get("card_id", "")),
			String(encoded.get("card_resource_path", "")),
			card_registry
		)
		if instance_id.is_empty() or seen_instance_ids.has(instance_id) or card_data == null:
			return _failure("save_card_identity_invalid")
		var encoded_wound_slots := encoded.get("wound_slots", []) as Array
		var encoded_emblem_slots := encoded.get("emblem_slots", []) as Array
		var encoded_rune_revealed := encoded.get("rune_revealed", []) as Array
		var stickers: Array = encoded.get("rune_stickers", OwnedCard._empty_slot_array(card_data.runes.size()))
		if stickers.size() != card_data.runes.size():
			return _failure("save_rune_sticker_count_invalid")
		for sticker: Variant in stickers:
			if not sticker is Dictionary:
				return _failure("save_rune_sticker_invalid")
			if not sticker.is_empty() and (int(sticker.get("element", -1)) < 0 or int(sticker.get("element", -1)) > 4 or String(sticker.get("emblem_id", "")).is_empty()):
				return _failure("save_rune_sticker_invalid")
		var wound_slots := _decode_slot_array(encoded_wound_slots, true)
		var emblem_slots := _decode_slot_array(encoded_emblem_slots, false)
		if (
			wound_slots.size() != encoded_wound_slots.size()
			or emblem_slots.size() != encoded_emblem_slots.size()
		):
			return _failure("save_card_slot_state_invalid")
		if encoded_rune_revealed.size() != card_data.runes.size():
			return _failure("save_rune_revealed_count_invalid")
		var resolved_counts := CardSlotLayout.resolve_counts(card_data)
		var saved_layout: Array = encoded.get("slot_layout", [])
		var saved_layout_is_valid := CardSlotLayout.is_valid_layout(card_data, saved_layout)
		if not migrate_status_slots and (
			wound_slots.size() != resolved_counts.x
			or emblem_slots.size() != resolved_counts.y
			or not saved_layout_is_valid
		):
			return _failure("save_status_slot_migration_marker_invalid")
		if not saved_layout_is_valid:
			saved_layout = CardSlotLayout.get_stable_layout(card_data)
		var progress_by_source := _decode_number_dictionary(
			encoded.get("progress_by_source", {}) as Dictionary
		)
		if _occupied_count(emblem_slots) > resolved_counts.y:
			if not migrate_status_slots:
				return _failure("save_status_slot_migration_marker_invalid")
			for emblem_index: int in emblem_slots.size():
				var state := emblem_slots[emblem_index]
				if state.is_empty():
					continue
				var returned_emblem := state.duplicate(true)
				var emblem_instance_id := StringName(String(returned_emblem.get("instance_id", "")))
				if emblem_instance_id.is_empty():
					emblem_instance_id = StringName("migrated_emblem_%s_%d" % [String(instance_id), emblem_index])
					returned_emblem["instance_id"] = emblem_instance_id
				if not emblem_instance_id.is_empty() and progress_by_source.has(emblem_instance_id):
					returned_emblem["saved_progress"] = progress_by_source[emblem_instance_id]
					progress_by_source.erase(emblem_instance_id)
				migration_returns.append({"kind": "emblem", "state": returned_emblem})
			emblem_slots = OwnedCard._empty_slot_array(resolved_counts.y)
		if _occupied_count(wound_slots) > resolved_counts.x:
			if not migrate_status_slots:
				return _failure("save_status_slot_migration_marker_invalid")
			if test_mode:
				for wound_index: int in wound_slots.size():
					var state := wound_slots[wound_index]
					if state.is_empty():
						continue
					var returned_wound := state.duplicate(true)
					if String(returned_wound.get("instance_id", "")).is_empty():
						returned_wound["instance_id"] = "migrated_wound_%s_%d" % [String(instance_id), wound_index]
					migration_returns.append({"kind": "wound", "state": returned_wound})
			wound_slots = OwnedCard._empty_slot_array(resolved_counts.x)
		else:
			wound_slots = _fit_status_slot_array(wound_slots, resolved_counts.x)
		if _occupied_count(emblem_slots) <= resolved_counts.y:
			emblem_slots = _fit_status_slot_array(emblem_slots, resolved_counts.y)
		card_states.append({
			"instance_id": instance_id,
			"card_data": card_data,
			"acquisition_order": int(encoded.get("acquisition_order", -1)),
			"resolved_action_type": int(encoded.get("resolved_action_type", -1)),
			"spell_durability": int(encoded.get("spell_durability", -1)),
			"permanent_growth": _decode_number_dictionary(
				encoded.get("permanent_growth", {}) as Dictionary
			),
			"crystallization_health_loss": maxi(int(encoded.get("crystallization_health_loss", 0)), 0),
			"wound_slots": wound_slots,
			"emblem_slots": emblem_slots,
			"slot_layout": saved_layout.duplicate(),
			"rune_revealed": _decode_bool_array(encoded_rune_revealed),
			"rune_stickers": stickers.duplicate(true),
			"progress_by_source": progress_by_source,
			"wound_battle_counters": _decode_number_dictionary(
				encoded.get("wound_battle_counters", {}) as Dictionary
			),
		})
		seen_instance_ids[instance_id] = true
	return {
		"success": true,
		"migration_returns": migration_returns,
		"state": {
			"next_instance_sequence": maxi(int(data.get("next_instance_sequence", 1)), 1),
			"cards": card_states,
		},
	}


func _encode_rows(rows: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for row_key: StringName in ROW_KEYS:
		var encoded_squads: Array[Dictionary] = []
		for value: Variant in rows.get(row_key, []) as Array:
			var squad := value as SquadData
			if squad == null or not squad.is_valid():
				return {}
			var horizontal_refs: Array[Dictionary] = []
			var layer_refs: Array[Dictionary] = []
			for card_data: CardData in squad.horizontal_cards:
				horizontal_refs.append(_encode_squad_card_ref(squad, card_data))
			for card_data: CardData in squad.layer_cards:
				layer_refs.append(_encode_squad_card_ref(squad, card_data))
			encoded_squads.append({
				"indicators": squad.capture_indicators(),
				"horizontal_cards": horizontal_refs,
				"layer_cards": layer_refs,
				"two_card_layout": int(squad.two_card_layout),
				"equipped_item_instance_id": (
					String(squad.get_equipped_item().instance_id)
					if squad.get_equipped_item() != null
					else ""
				),
				"equipment_indicator_position": [
					squad.get_equipment_indicator_position().x,
					squad.get_equipment_indicator_position().y,
				],
			})
		result[String(row_key)] = encoded_squads
	return result


func _decode_rows(
	data: Dictionary,
	owned_collection: OwnedCardCollection,
	card_registry: Dictionary
) -> Dictionary:
	var result: Dictionary = {}
	var claimed_equipment_instance_ids: Dictionary = {}
	var claimed_indicator_ids: Dictionary = {}
	for row_key: StringName in ROW_KEYS:
		if not data.has(String(row_key)) and not data.has(row_key):
			return _failure("save_row_missing")
		var row_value: Variant = data.get(String(row_key), data.get(row_key, []))
		if not row_value is Array:
			return _failure("save_row_invalid")
		var decoded_squads: Array[SquadData] = []
		for value: Variant in row_value as Array:
			if not value is Dictionary:
				return _failure("save_squad_invalid")
			var encoded_squad := value as Dictionary
			var horizontal_result := _decode_squad_card_refs(
				encoded_squad.get("horizontal_cards", []) as Array,
				owned_collection,
				card_registry
			)
			var layer_result := _decode_squad_card_refs(
				encoded_squad.get("layer_cards", []) as Array,
				owned_collection,
				card_registry
			)
			if (
				not bool(horizontal_result.get("success", false))
				or not bool(layer_result.get("success", false))
			):
				return _failure("save_squad_card_invalid")
			var squad := SquadData.new()
			if not squad.restore_indicators(encoded_squad.get("indicators", [])):
				return _failure("save_indicator_attachment_invalid")
			for attachment: Dictionary in squad.indicator_attachments:
				var indicator := attachment["indicator"] as CelestialIndicator
				if claimed_indicator_ids.has(indicator.instance_id):
					return _failure("save_indicator_duplicate_attachment")
				claimed_indicator_ids[indicator.instance_id] = true
			squad.horizontal_cards.assign(horizontal_result.get("cards", []) as Array)
			squad.layer_cards.assign(layer_result.get("cards", []) as Array)
			squad.two_card_layout = int(
				encoded_squad.get("two_card_layout", SquadData.TwoCardLayout.EXPANDED)
			) as SquadData.TwoCardLayout
			for binding_value: Variant in horizontal_result.get("bindings", []) as Array:
				var binding := binding_value as Dictionary
				squad.bind_owned_card(
					binding.get("card_data") as CardData,
					binding.get("owned_card") as OwnedCard
				)
			var equipment_instance_id := StringName(
				String(encoded_squad.get("equipped_item_instance_id", ""))
			)
			if not equipment_instance_id.is_empty():
				var equipped_item := owned_collection.get_by_instance_id(
					equipment_instance_id
				)
				var indicator_position := SquadData.UNSPECIFIED_EQUIPMENT_INDICATOR_POSITION
				var encoded_position: Variant = encoded_squad.get(
					"equipment_indicator_position",
					[]
				)
				if encoded_position is Array and (encoded_position as Array).size() == 2:
					indicator_position = Vector2(
						float((encoded_position as Array)[0]),
						float((encoded_position as Array)[1])
					)
				if (
					equipped_item == null
					or equipped_item.card_data.card_type != CardData.CardType.EQUIPMENT
					or claimed_equipment_instance_ids.has(equipment_instance_id)
					or not squad.equip_item(equipped_item, indicator_position)
				):
					return _failure("save_squad_equipment_invalid")
				claimed_equipment_instance_ids[equipment_instance_id] = true
			if not squad.is_valid():
				return _failure("save_squad_layout_invalid")
			decoded_squads.append(squad)
		result[row_key] = decoded_squads
	return {"success": true, "rows": result}


func _encode_squad_card_ref(squad: SquadData, card_data: CardData) -> Dictionary:
	var owned_card := squad.get_owned_card(card_data)
	return {
		"owned_card_instance_id": String(owned_card.instance_id) if owned_card != null else "",
		"card_id": String(card_data.id),
		"card_resource_path": card_data.resource_path,
	}


func _decode_squad_card_refs(
	encoded_refs: Array,
	owned_collection: OwnedCardCollection,
	card_registry: Dictionary
) -> Dictionary:
	var cards: Array[CardData] = []
	var bindings: Array[Dictionary] = []
	for value: Variant in encoded_refs:
		if not value is Dictionary:
			return _failure("save_squad_card_ref_invalid")
		var encoded := value as Dictionary
		var owned_instance_id := StringName(String(encoded.get("owned_card_instance_id", "")))
		var owned_card := owned_collection.get_by_instance_id(owned_instance_id)
		if not owned_instance_id.is_empty() and owned_card == null:
			return _failure("save_squad_owned_card_missing")
		var card_data: CardData = owned_card.card_data if owned_card != null else null
		if (
			card_data != null
			and not String(encoded.get("card_id", "")).is_empty()
			and card_data.id != StringName(String(encoded.get("card_id", "")))
		):
			return _failure("save_squad_owned_card_mismatch")
		if card_data == null:
			card_data = _resolve_card_definition(
				String(encoded.get("card_id", "")),
				String(encoded.get("card_resource_path", "")),
				card_registry
			)
		if card_data == null:
			return _failure("save_squad_card_definition_missing")
		cards.append(card_data)
		if owned_card != null:
			bindings.append({"card_data": card_data, "owned_card": owned_card})
	return {"success": true, "cards": cards, "bindings": bindings}


func _resolve_card_definition(
	card_id_text: String,
	resource_path: String,
	card_registry: Dictionary
) -> CardData:
	var card_id := StringName(card_id_text)
	var card_data := card_registry.get(card_id) as CardData
	if card_data == null:
		card_data = card_registry.get(card_id_text) as CardData
	if card_data == null and resource_path.begins_with("res://"):
		card_data = load(resource_path) as CardData
	if card_data == null or card_data.id != card_id:
		return null
	return card_data


func _decode_slot_array(values: Array, wound_slots: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in values:
		if not value is Dictionary:
			return []
		var slot_state := (value as Dictionary).duplicate(true)
		if wound_slots and slot_state.has("wound_id"):
			slot_state["wound_id"] = StringName(String(slot_state["wound_id"]))
		if not wound_slots:
			if slot_state.has("emblem_id"):
				slot_state["emblem_id"] = StringName(String(slot_state["emblem_id"]))
			if slot_state.has("instance_id"):
				slot_state["instance_id"] = StringName(String(slot_state["instance_id"]))
		result.append(slot_state)
	return result


func _occupied_count(values: Array[Dictionary]) -> int:
	var count := 0
	for value: Dictionary in values:
		if not value.is_empty():
			count += 1
	return count


func _fit_status_slot_array(values: Array[Dictionary], capacity: int) -> Array[Dictionary]:
	if values.size() <= capacity:
		values.resize(capacity)
		return values
	var result := OwnedCard._empty_slot_array(capacity)
	var next_index := 0
	for state: Dictionary in values:
		if state.is_empty() or next_index >= capacity:
			continue
		result[next_index] = state.duplicate(true)
		next_index += 1
	return result


func _decode_number_dictionary(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in data:
		result[StringName(String(key))] = data[key]
	return result


func _decode_bool_array(data: Array) -> Array[bool]:
	var result: Array[bool] = []
	for value: Variant in data:
		result.append(bool(value))
	return result


func _decode_reward_state(data: Dictionary) -> Dictionary:
	var requests: Array[Dictionary] = []
	for value: Variant in data.get("pending_random_card_requests", []) as Array:
		if not value is Dictionary:
			continue
		var request := (value as Dictionary).duplicate(true)
		for key: String in ["entry_id", "battle_instance_id", "effect_id"]:
			request[key] = StringName(String(request.get(key, "")))
		requests.append(request)
	var emblem_instances: Array[Dictionary] = []
	for value: Variant in data.get("pending_emblem_instances", []) as Array:
		if not value is Dictionary:
			continue
		var entry := (value as Dictionary).duplicate(true)
		for key: String in ["entry_id", "battle_instance_id", "emblem_instance_id", "emblem_id"]:
			entry[key] = StringName(String(entry.get(key, "")))
		emblem_instances.append(entry)
	return {"gold": int(data.get("gold", 0)), "pending_random_card_requests": requests, "pending_emblem_instances": emblem_instances}


func _encode_committed_battles(state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for battle_id: Variant in state:
		if bool(state[battle_id]):
			result.append(String(battle_id))
	result.sort()
	return result


func _decode_committed_battles(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value: Variant in values:
		var battle_id := StringName(String(value))
		if not battle_id.is_empty():
			result[battle_id] = true
	return result


func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_STRING_NAME:
			return String(value)
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key: Variant in value as Dictionary:
				result[String(key)] = _json_safe((value as Dictionary)[key])
			return result
		TYPE_ARRAY:
			var result: Array = []
			for item: Variant in value as Array:
				result.append(_json_safe(item))
			return result
		_:
			return value


func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
