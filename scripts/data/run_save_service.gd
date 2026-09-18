class_name RunSaveService
extends RefCounted

## D2-5 的本局存档边界。
## 内存快照可以保存 Resource 引用；磁盘 JSON 不可以，因此这里把卡牌定义转换为
## 稳定 card_id + resource_path，并在读取后重新绑定 OwnedCard 与 SquadData。

const OwnedCardCollection = preload("res://scripts/data/owned_card_collection.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const RunRewardState = preload("res://scripts/data/run_reward_state.gd")
const RunSettlementJournal = preload("res://scripts/data/run_settlement_journal.gd")

const SCHEMA_VERSION: int = 1
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
	phase_on_save: int
) -> Dictionary:
	var encoded_collection := _encode_collection_state(collection_state)
	var encoded_rows := _encode_rows(rows)
	if encoded_collection.is_empty() or encoded_rows.is_empty():
		return {}
	return {
		"schema_version": SCHEMA_VERSION,
		"collection": encoded_collection,
		"rows": encoded_rows,
		"battle_seed": battle_seed,
		"pending_battle_instance_id": String(pending_battle_instance_id),
		"next_battle_instance_sequence": maxi(next_battle_instance_sequence, 1),
		"reward_state": _json_safe(reward_state.capture_state()),
		"committed_battle_ids": _encode_committed_battles(settlement_journal.capture_state()),
		"phase_on_save": phase_on_save,
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
	if int(checkpoint.get("schema_version", 0)) != SCHEMA_VERSION:
		return _failure("save_schema_unsupported")
	return {"success": true, "checkpoint": checkpoint}


func restore_checkpoint(
	checkpoint: Dictionary,
	owned_collection: OwnedCardCollection,
	reward_state: RunRewardState,
	settlement_journal: RunSettlementJournal,
	card_registry: Dictionary
) -> Dictionary:
	if (
		int(checkpoint.get("schema_version", 0)) != SCHEMA_VERSION
		or owned_collection == null
		or reward_state == null
		or settlement_journal == null
	):
		return _failure("save_context_invalid")
	var decoded_collection_result := _decode_collection_state(
		checkpoint.get("collection", {}) as Dictionary,
		card_registry
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
			"wound_slots": _json_safe(state.get("wound_slots", [])),
			"emblem_slots": _json_safe(state.get("emblem_slots", [])),
			"rune_revealed": _json_safe(state.get("rune_revealed", [])),
			"progress_by_source": _json_safe(state.get("progress_by_source", {})),
		})
	return {
		"next_instance_sequence": maxi(int(collection_state.get("next_instance_sequence", 1)), 1),
		"cards": encoded_cards,
	}


func _decode_collection_state(data: Dictionary, card_registry: Dictionary) -> Dictionary:
	if not data.get("cards", []) is Array:
		return _failure("save_collection_cards_invalid")
	var card_states: Array[Dictionary] = []
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
		if (
			encoded_wound_slots.size() != card_data.wound_slot_count
			or encoded_emblem_slots.size() != card_data.emblem_slot_count
			or encoded_rune_revealed.size() != card_data.runes.size()
		):
			return _failure("save_card_slot_count_invalid")
		var wound_slots := _decode_slot_array(encoded_wound_slots, true)
		var emblem_slots := _decode_slot_array(encoded_emblem_slots, false)
		if (
			wound_slots.size() != encoded_wound_slots.size()
			or emblem_slots.size() != encoded_emblem_slots.size()
		):
			return _failure("save_card_slot_state_invalid")
		card_states.append({
			"instance_id": instance_id,
			"card_data": card_data,
			"acquisition_order": int(encoded.get("acquisition_order", -1)),
			"resolved_action_type": int(encoded.get("resolved_action_type", -1)),
			"spell_durability": int(encoded.get("spell_durability", -1)),
			"permanent_growth": _decode_number_dictionary(
				encoded.get("permanent_growth", {}) as Dictionary
			),
			"wound_slots": wound_slots,
			"emblem_slots": emblem_slots,
			"rune_revealed": _decode_bool_array(encoded_rune_revealed),
			"progress_by_source": _decode_number_dictionary(
				encoded.get("progress_by_source", {}) as Dictionary
			),
		})
		seen_instance_ids[instance_id] = true
	return {
		"success": true,
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
				"horizontal_cards": horizontal_refs,
				"layer_cards": layer_refs,
				"two_card_layout": int(squad.two_card_layout),
			})
		result[String(row_key)] = encoded_squads
	return result


func _decode_rows(
	data: Dictionary,
	owned_collection: OwnedCardCollection,
	card_registry: Dictionary
) -> Dictionary:
	var result: Dictionary = {}
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
	return {"gold": int(data.get("gold", 0)), "pending_random_card_requests": requests}


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
