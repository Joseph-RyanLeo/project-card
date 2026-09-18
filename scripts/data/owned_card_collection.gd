class_name OwnedCardCollection
extends RefCounted

## 本局收藏的唯一实例容器。
## 所有增删与快照恢复都通过实例 ID 对齐，因此同名、同定义的多张卡仍彼此独立。

const INSTANCE_ID_PREFIX: String = "run_card_"
const OwnedCard = preload("res://scripts/data/owned_card.gd")

var _cards: Array[OwnedCard] = []
var _next_instance_sequence: int = 1


func create_card(card_data: CardData) -> OwnedCard:
	if card_data == null:
		return null
	var owned_card := OwnedCard.new()
	owned_card.initialize(
		card_data,
		_take_next_instance_id(),
		_cards.size()
	)
	_cards.append(owned_card)
	return owned_card


func add_existing(owned_card: OwnedCard) -> bool:
	if (
		owned_card == null
		or not owned_card.is_valid()
		or get_by_instance_id(owned_card.instance_id) != null
	):
		return false
	_cards.append(owned_card)
	_next_instance_sequence = maxi(
		_next_instance_sequence,
		_extract_sequence(owned_card.instance_id) + 1
	)
	return true


func get_cards() -> Array[OwnedCard]:
	var result: Array[OwnedCard] = []
	result.assign(_cards)
	return result


func size() -> int:
	return _cards.size()


func remove_by_instance_id(instance_id: StringName) -> OwnedCard:
	for card_index: int in _cards.size():
		if _cards[card_index].instance_id != instance_id:
			continue
		var removed := _cards[card_index]
		_cards.remove_at(card_index)
		return removed
	return null


func get_by_instance_id(instance_id: StringName) -> OwnedCard:
	for owned_card: OwnedCard in _cards:
		if owned_card.instance_id == instance_id:
			return owned_card
	return null


func find_first_by_definition(
	card_data: CardData,
	excluded_instance_ids: Dictionary = {}
) -> OwnedCard:
	for owned_card: OwnedCard in _cards:
		if (
			owned_card.card_data == card_data
			and not excluded_instance_ids.has(owned_card.instance_id)
		):
			return owned_card
	return null


func capture_state() -> Dictionary:
	var card_states: Array[Dictionary] = []
	for owned_card: OwnedCard in _cards:
		card_states.append(owned_card.capture_state())
	return {
		"next_instance_sequence": _next_instance_sequence,
		"cards": card_states,
	}


func restore_state(snapshot: Dictionary) -> bool:
	var snapshot_cards := snapshot.get("cards", []) as Array
	var current_by_id: Dictionary = {}
	for owned_card: OwnedCard in _cards:
		current_by_id[owned_card.instance_id] = owned_card
	var restored_cards: Array[OwnedCard] = []
	var seen_ids: Dictionary = {}
	for value: Variant in snapshot_cards:
		if not value is Dictionary:
			return false
		var card_state := value as Dictionary
		var instance_id := card_state.get("instance_id", &"") as StringName
		if instance_id.is_empty() or seen_ids.has(instance_id):
			return false
		var owned_card := current_by_id.get(instance_id) as OwnedCard
		if owned_card == null:
			owned_card = card_state.get("owned_card_ref") as OwnedCard
		if owned_card == null:
			owned_card = OwnedCard.new()
			if not owned_card.restore_state(card_state):
				return false
		elif not owned_card.restore_state(card_state):
			return false
		if owned_card == null:
			return false
		restored_cards.append(owned_card)
		seen_ids[instance_id] = true
	_cards.assign(restored_cards)
	_next_instance_sequence = maxi(int(snapshot.get("next_instance_sequence", 1)), 1)
	return true


func _take_next_instance_id() -> StringName:
	var result := StringName("%s%06d" % [INSTANCE_ID_PREFIX, _next_instance_sequence])
	_next_instance_sequence += 1
	while get_by_instance_id(result) != null:
		result = StringName("%s%06d" % [INSTANCE_ID_PREFIX, _next_instance_sequence])
		_next_instance_sequence += 1
	return result


func _extract_sequence(instance_id: StringName) -> int:
	var text := String(instance_id)
	if not text.begins_with(INSTANCE_ID_PREFIX):
		return 0
	return int(text.trim_prefix(INSTANCE_ID_PREFIX))
