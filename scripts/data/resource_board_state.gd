class_name ResourceBoardState
extends RefCounted

## 一关双方资源板的可存档数据，不负责界面或刷新时机。

const Layout = preload("res://scripts/data/resource_hex_layout.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const RESOURCE_COUNT_MIN := 0
const RESOURCE_COUNT_MAX := 3
const RESOURCE_RARITY_ROLL_MAX := 98

var level_id: StringName = &""
var disabled_by_side: Dictionary = {"player": [], "enemy": []}
var deployments: Dictionary = {"player": {}, "enemy": {}}
var level_resource_cards: Dictionary = {"player": {}, "enemy": {}}
var resources_generated := false


func initialize_level(new_level_id: StringName, rng: RandomNumberGenerator) -> bool:
	if new_level_id.is_empty() or rng == null:
		return false
	var generated_disabled: Dictionary = {}
	for side in ["player", "enemy"]:
		var available := Layout.valid_cells()
		var count := rng.randi_range(0, 3)
		var chosen: Array[Vector2i] = []
		for _index in count:
			chosen.append(available.pop_at(rng.randi_range(0, available.size() - 1)))
		generated_disabled[side] = chosen
	level_id = new_level_id
	disabled_by_side = generated_disabled
	deployments = {"player": {}, "enemy": {}}
	level_resource_cards = {"player": {}, "enemy": {}}
	resources_generated = false
	return true


func generate_level_resources(resource_definitions: Array[CardData], rng: RandomNumberGenerator) -> Dictionary:
	if level_id.is_empty() or resources_generated or rng == null:
		return {"success": false, "reason": "resource_generation_state_invalid"}
	var pools: Dictionary = {0: [], 1: [], 2: []}
	var sorted_definitions := resource_definitions.duplicate()
	sorted_definitions.sort_custom(func(left: CardData, right: CardData) -> bool: return String(left.id) < String(right.id))
	for definition: CardData in sorted_definitions:
		if definition != null and definition.card_type == CardData.CardType.RESOURCE and int(definition.rarity) in pools:
			pools[int(definition.rarity)].append(definition)

	var next_cards: Dictionary = {"player": {}, "enemy": {}}
	var next_deployments: Dictionary = {"player": {}, "enemy": {}}
	for side in ["player", "enemy"]:
		var count := count_for_roll(rng.randi_range(0, 3))
		var cards: Array[OwnedCard] = []
		for card_index in count:
			var rarity := rarity_for_roll(rng.randi_range(0, RESOURCE_RARITY_ROLL_MAX))
			var rarity_pool: Array = pools[rarity]
			if rarity_pool.is_empty():
				return {"success": false, "reason": "resource_rarity_pool_empty_%d" % rarity}
			var definition := rarity_pool[rng.randi_range(0, rarity_pool.size() - 1)] as CardData
			var instance_id := StringName("level_%s_%s_resource_%02d" % [String(level_id), side, card_index + 1])
			var owned := OwnedCard.new()
			owned.initialize(definition, instance_id, card_index)
			if owned.resource_shape.size() != int(definition.rarity) + 1 or not Layout.is_connected_shape(owned.resource_shape):
				return {"success": false, "reason": "resource_shape_invalid_%s" % instance_id}
			cards.append(owned)
			next_cards[side][String(instance_id)] = owned
		var placements: Variant = _pack_level_resources(side, cards, rng)
		if placements == null:
			return {"success": false, "reason": "resource_placement_failed_%s" % side}
		next_deployments[side] = placements

	level_resource_cards = next_cards
	deployments = next_deployments
	resources_generated = true
	return {
		"success": true,
		"player_count": level_resource_cards.player.size(),
		"enemy_count": level_resource_cards.enemy.size(),
		"level_id": level_id,
	}


static func count_for_roll(roll: int) -> int:
	return clampi(roll, RESOURCE_COUNT_MIN, RESOURCE_COUNT_MAX)


static func rarity_for_roll(roll: int) -> int:
	var bounded_roll := clampi(roll, 0, RESOURCE_RARITY_ROLL_MAX)
	if bounded_roll < 75:
		return 0
	if bounded_roll < 95:
		return 1
	return 2


func _pack_level_resources(side: String, cards: Array[OwnedCard], rng: RandomNumberGenerator) -> Variant:
	var placements: Dictionary = {}
	var disabled: Dictionary = {}
	for cell: Vector2i in disabled_by_side.get(side, []):
		disabled[cell] = true
	var candidates := Layout.valid_cells()
	if not _place_level_resource(cards, 0, candidates, {}, disabled, placements, rng):
		return null
	return placements


func _place_level_resource(
	cards: Array[OwnedCard],
	card_index: int,
	candidates: Array[Vector2i],
	occupied: Dictionary,
	disabled: Dictionary,
	placements: Dictionary,
	rng: RandomNumberGenerator
) -> bool:
	if card_index >= cards.size():
		return true
	var shuffled_candidates := candidates.duplicate()
	for index in range(shuffled_candidates.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var swap_cell: Vector2i = shuffled_candidates[index]
		shuffled_candidates[index] = shuffled_candidates[swap_index]
		shuffled_candidates[swap_index] = swap_cell
	var owned := cards[card_index]
	for anchor: Vector2i in shuffled_candidates:
		if not Layout.can_place(owned.resource_shape, anchor, occupied, disabled):
			continue
		var next_occupied := occupied.duplicate()
		for offset: Vector2i in owned.resource_shape:
			next_occupied[anchor + offset] = owned.instance_id
		placements[String(owned.instance_id)] = {
			"anchor": [anchor.x, anchor.y],
			"shape": _encode_cells(owned.resource_shape),
			"grab_anchor": [owned.resource_shape[0].x, owned.resource_shape[0].y],
			"grab_pixel_offset": [0.0, 0.0],
		}
		if _place_level_resource(cards, card_index + 1, candidates, next_occupied, disabled, placements, rng):
			return true
		placements.erase(String(owned.instance_id))
	return false


func capture_state() -> Dictionary:
	var encoded_level_cards: Dictionary = {"player": [], "enemy": []}
	for side in ["player", "enemy"]:
		for owned: OwnedCard in level_resource_cards.get(side, {}).values():
			encoded_level_cards[side].append({
				"instance_id": String(owned.instance_id),
				"card_id": String(owned.card_data.id),
				"resource_shape": _encode_cells(owned.resource_shape),
			})
	return {
		"level_id": String(level_id),
		"disabled_by_side": _encode_side_cells(disabled_by_side),
		"deployments": deployments.duplicate(true),
		"level_resource_cards": encoded_level_cards,
		"resources_generated": resources_generated,
	}


func restore_state(state: Dictionary, card_registry: Dictionary = {}) -> bool:
	if not state.has("level_id") or not state.get("disabled_by_side", null) is Dictionary or not state.get("deployments", null) is Dictionary:
		return false
	var parsed_disabled: Dictionary = {}
	for side in ["player", "enemy"]:
		var cells: Variant = state.disabled_by_side.get(side, null)
		if not cells is Array or cells.size() > 3:
			return false
		var seen: Dictionary = {}
		var parsed: Array[Vector2i] = []
		for pair in cells:
			if not pair is Array or pair.size() != 2:
				return false
			var cell := Vector2i(int(pair[0]), int(pair[1]))
			if not Layout.is_valid_cell(cell) or seen.has(cell):
				return false
			seen[cell] = true
			parsed.append(cell)
		parsed_disabled[side] = parsed

	var parsed_level_cards: Dictionary = {"player": {}, "enemy": {}}
	var level_cards_value: Variant = state.get("level_resource_cards", null)
	if level_cards_value is Dictionary:
		for side in ["player", "enemy"]:
			var entries: Variant = level_cards_value.get(side, [])
			if not entries is Array or entries.size() > RESOURCE_COUNT_MAX:
				return false
			for saved_card: Variant in entries:
				var owned := _decode_level_resource(saved_card, card_registry, parsed_level_cards)
				if owned == null:
					return false
				parsed_level_cards[side][String(owned.instance_id)] = owned
	else:
		# Schema 4保存敌方NPC资源但不保存本关我方自动资源；只迁移已有实例，不在读档时补抽。
		var legacy_enemy_cards: Variant = state.get("enemy_resource_cards", [])
		if not legacy_enemy_cards is Array:
			return false
		for saved_card: Variant in legacy_enemy_cards:
			var owned := _decode_level_resource(saved_card, card_registry, parsed_level_cards)
			if owned == null:
				return false
			parsed_level_cards.enemy[String(owned.instance_id)] = owned

	var parsed_deployments: Dictionary = {}
	for side in ["player", "enemy"]:
		var side_deployments: Variant = state.deployments.get(side, null)
		if not side_deployments is Dictionary:
			return false
		var occupied: Dictionary = {}
		var decoded: Dictionary = {}
		var disabled_map: Dictionary = {}
		for cell: Vector2i in parsed_disabled[side]: disabled_map[cell] = true
		for instance_id_value: Variant in side_deployments:
			var instance_id := String(instance_id_value)
			if instance_id.is_empty():
				return false
			var placement: Variant = side_deployments[instance_id_value]
			if not placement is Dictionary or not placement.get("shape", null) is Array or not placement.get("anchor", null) is Array:
				return false
			var shape: Array[Vector2i] = []
			for pair: Variant in placement.shape:
				if not pair is Array or pair.size() != 2:
					return false
				shape.append(Vector2i(int(pair[0]), int(pair[1])))
			if placement.anchor.size() != 2:
				return false
			var anchor := Vector2i(int(placement.anchor[0]), int(placement.anchor[1]))
			var level_owned := parsed_level_cards[side].get(instance_id) as OwnedCard
			if side == "enemy" and level_owned == null:
				return false
			if level_owned != null and level_owned.resource_shape != shape:
				return false
			var grab_value: Variant = placement.get("grab_anchor", [0, 0])
			if not grab_value is Array or grab_value.size() != 2:
				return false
			var grab_anchor := Vector2i(int(grab_value[0]), int(grab_value[1]))
			var pixel_offset_value: Variant = placement.get("grab_pixel_offset", [0, 0])
			if not pixel_offset_value is Array or pixel_offset_value.size() != 2:
				return false
			var pixel_offset := Vector2(float(pixel_offset_value[0]), float(pixel_offset_value[1]))
			if not pixel_offset.is_finite() or not shape.has(grab_anchor) or not Layout.can_place(shape, anchor, occupied, disabled_map):
				return false
			for offset: Vector2i in shape: occupied[anchor + offset] = instance_id
			decoded[instance_id] = {
				"anchor": [anchor.x, anchor.y],
				"shape": _encode_cells(shape),
				"grab_anchor": [grab_anchor.x, grab_anchor.y],
				"grab_pixel_offset": [pixel_offset.x, pixel_offset.y],
			}
		parsed_deployments[side] = decoded
	for side in ["player", "enemy"]:
		for instance_id: String in parsed_level_cards[side]:
			if not parsed_deployments[side].has(instance_id):
				return false

	level_id = StringName(String(state.level_id))
	disabled_by_side = parsed_disabled
	deployments = parsed_deployments
	level_resource_cards = parsed_level_cards
	# 旧版本没有生成标记。标记为已处理，确保schema4读取后不会在该关补抽资源。
	resources_generated = bool(state.get("resources_generated", true))
	if not resources_generated and (not parsed_level_cards.player.is_empty() or not parsed_level_cards.enemy.is_empty()):
		return false
	return true


func is_level_resource(side: String, instance_id: String) -> bool:
	return side in ["player", "enemy"] and level_resource_cards.get(side, {}).has(instance_id)


func get_level_resource(side: String, instance_id: String) -> OwnedCard:
	if side not in ["player", "enemy"]:
		return null
	return level_resource_cards.get(side, {}).get(instance_id) as OwnedCard


func get_level_resource_cards(side: String) -> Array[OwnedCard]:
	var result: Array[OwnedCard] = []
	if side not in ["player", "enemy"]:
		return result
	for card: OwnedCard in level_resource_cards[side].values():
		result.append(card)
	return result


func clear_level_resources() -> void:
	deployments = {"player": {}, "enemy": {}}
	level_resource_cards = {"player": {}, "enemy": {}}


func deploy_level_resource(side: String, owned: OwnedCard, anchor: Vector2i) -> bool:
	if (
		side not in ["player", "enemy"]
		or owned == null
		or owned.card_data == null
		or owned.card_data.card_type != CardData.CardType.RESOURCE
		or owned.instance_id.is_empty()
		or level_resource_cards[side].has(String(owned.instance_id))
	):
		return false
	var occupied: Dictionary = {}
	for placement: Dictionary in deployments[side].values():
		var existing_anchor := Vector2i(placement.anchor[0], placement.anchor[1])
		for pair: Array in placement.shape: occupied[existing_anchor + Vector2i(pair[0], pair[1])] = true
	var disabled: Dictionary = {}
	for cell: Vector2i in disabled_by_side[side]: disabled[cell] = true
	if not Layout.can_place(owned.resource_shape, anchor, occupied, disabled):
		return false
	var instance_id := String(owned.instance_id)
	level_resource_cards[side][instance_id] = owned
	resources_generated = true
	deployments[side][instance_id] = {
		"anchor": [anchor.x, anchor.y],
		"shape": _encode_cells(owned.resource_shape),
		"grab_anchor": [owned.resource_shape[0].x, owned.resource_shape[0].y],
		"grab_pixel_offset": [0.0, 0.0],
	}
	return true


func try_deploy(side: String, instance_id: String, shape: Array[Vector2i], anchor: Vector2i, grab_anchor: Vector2i, grab_pixel_offset: Vector2 = Vector2.ZERO) -> bool:
	if side not in ["player", "enemy"] or instance_id.is_empty() or is_level_resource(side, instance_id):
		return false
	var occupied: Dictionary = {}
	for existing_id in deployments[side]:
		if String(existing_id) == instance_id: continue
		var placement: Dictionary = deployments[side][existing_id]
		var existing_anchor := Vector2i(placement.anchor[0], placement.anchor[1])
		for pair: Array in placement.shape: occupied[existing_anchor + Vector2i(pair[0], pair[1])] = existing_id
	var disabled: Dictionary = {}
	for cell: Vector2i in disabled_by_side[side]: disabled[cell] = true
	if not shape.has(grab_anchor) or not grab_pixel_offset.is_finite() or not Layout.can_place(shape, anchor, occupied, disabled):
		return false
	deployments[side][instance_id] = {
		"anchor": [anchor.x, anchor.y],
		"shape": _encode_cells(shape),
		"grab_anchor": [grab_anchor.x, grab_anchor.y],
		"grab_pixel_offset": [grab_pixel_offset.x, grab_pixel_offset.y],
	}
	return true


func _decode_level_resource(saved_card: Variant, card_registry: Dictionary, seen_by_side: Dictionary) -> OwnedCard:
	if not saved_card is Dictionary:
		return null
	var instance_id := StringName(String(saved_card.get("instance_id", "")))
	var card_id := StringName(String(saved_card.get("card_id", "")))
	var definition := card_registry.get(card_id) as CardData
	var shape_value: Variant = saved_card.get("resource_shape", null)
	if instance_id.is_empty() or definition == null or definition.card_type != CardData.CardType.RESOURCE or not shape_value is Array:
		return null
	for side in ["player", "enemy"]:
		if seen_by_side[side].has(String(instance_id)):
			return null
	var shape: Array[Vector2i] = []
	for pair: Variant in shape_value:
		if not pair is Array or pair.size() != 2:
			return null
		shape.append(Vector2i(int(pair[0]), int(pair[1])))
	if shape.size() != int(definition.rarity) + 1 or not Layout.is_connected_shape(shape):
		return null
	var owned := OwnedCard.new()
	if not owned.restore_state({
		"instance_id": instance_id,
		"card_data": definition,
		"resource_shape": _encode_cells(shape),
	}):
		return null
	return owned


func _encode_side_cells(source: Dictionary) -> Dictionary:
	var result := {}
	for side in ["player", "enemy"]:
		var pairs: Array = []
		for cell: Vector2i in source.get(side, []): pairs.append([cell.x, cell.y])
		result[side] = pairs
	return result


func _encode_cells(cells: Array[Vector2i]) -> Array:
	var result: Array = []
	for cell: Vector2i in cells: result.append([cell.x, cell.y])
	return result
