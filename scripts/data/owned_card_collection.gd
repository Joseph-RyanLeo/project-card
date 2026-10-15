class_name OwnedCardCollection
extends RefCounted

## 本局收藏的唯一实例容器。
## 所有增删与快照恢复都通过实例 ID 对齐，因此同名、同定义的多张卡仍彼此独立。

const INSTANCE_ID_PREFIX: String = "run_card_"
const OwnedCard = preload("res://scripts/data/owned_card.gd")

signal card_removed(instance_id: StringName)

var _cards: Array[OwnedCard] = []
var _next_instance_sequence: int = 1


func create_card(card_data: CardData, instance_rng: RandomNumberGenerator = null) -> OwnedCard:
	if card_data == null:
		return null
	var owned_card := OwnedCard.new()
	owned_card.initialize(
		card_data,
		_take_next_instance_id(),
		_cards.size(),
		instance_rng
	)
	_assign_member_identity(owned_card, _cards)
	_cards.append(owned_card)
	_grant_acquisition_cards(owned_card, instance_rng)
	return owned_card


func add_existing(owned_card: OwnedCard) -> bool:
	if (
		owned_card == null
		or not owned_card.is_valid()
		or get_by_instance_id(owned_card.instance_id) != null
	):
		return false
	_assign_member_identity(owned_card, _cards)
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
		card_removed.emit(instance_id)
		for companion: OwnedCard in get_cards():
			if companion.companion_source_id == instance_id: remove_by_instance_id(companion.instance_id)
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
		_assign_member_identity(owned_card, restored_cards)
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


func _assign_member_identity(owned_card: OwnedCard, existing_cards: Array[OwnedCard]) -> void:
	# 队列/层级以资源引用定位队员，同名实例出现引用冲突时才复制只读定义。
	# 共享card_data和所有可变实例状态保持原归属，读档同样经过此入口。
	for existing: OwnedCard in existing_cards:
		if existing.get_battlefield_card() == owned_card.get_battlefield_card():
			owned_card._battlefield_card = owned_card.card_data.duplicate() as CardData
			return


func _grant_acquisition_cards(owned: OwnedCard, rng: RandomNumberGenerator) -> void:
	if owned.card_data.content_effect == &"augustus_ironwall":
		for id: String in ["skirmish_formation", "rally_formation"]:
			var companion := create_card(load("res://resources/cards/%s.tres" % id), rng)
			companion.companion_source_id = owned.instance_id
	elif owned.card_data.content_effect == &"gunsmith_master":
		var candidates: Array[CardData] = []
		var filenames := ResourceLoader.list_directory("res://resources/cards")
		filenames.sort()
		for filename: String in filenames:
			if filename.get_extension() != "tres": continue
			var card := load("res://resources/cards/" + filename) as CardData
			if card == null or not card.is_available or card.is_derived or card.get_effective_faction() == CardFaction.Id.LABYRINTH: continue
			if card.card_type == CardData.CardType.EQUIPMENT and card.equipment_type == CardData.EquipmentType.RANGED_WEAPON and card.rarity <= CardData.Rarity.II: candidates.append(card)
		if candidates.is_empty(): return
		var source := rng
		if source == null:
			source = RandomNumberGenerator.new()
			source.randomize()
		var selector := OrdinaryShopService.new()
		selector.load_config()
		create_card(selector.draw_card_candidate(candidates, source, selector.count_owned_cards(_cards)), source)
