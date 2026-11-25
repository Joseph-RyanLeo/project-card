extends RefCounted

## 四种药剂用四个位标记。按位组合可以共用同一组数值，单药和合剂不会分开维护。
const BONE := 1
const HEART := 2
const SWIFT := 4
const SHELL := 8
const PERMANENT_ZEAL := &"event_potion_zeal"
const FORBIDDEN_PROTECTION := &"forbidden_protection"
const FORBIDDEN_IMMUNITY := &"forbidden_immunity"


static func mask_for(card: CardData) -> int:
	var effect := String(card.content_effect)
	if not effect.begins_with("event_potion_"):
		return 0
	var mask := int(effect.trim_prefix("event_potion_"))
	return mask if mask > 0 and mask <= (BONE | HEART | SWIFT | SHELL) else 0


static func attribute_deltas(mask: int) -> Vector4i:
	var bone := 1 if mask & BONE else 0
	return Vector4i(bone, (2 if mask & HEART else 0) - bone, 2 if mask & SHELL else 0, 1 if mask & SWIFT else 0)


static func equipment_display_deltas(card: CardData) -> Vector4i:
	var mask := mask_for(card)
	if mask != 0:
		return attribute_deltas(mask)
	return Vector4i(card.equipment_action_delta, card.equipment_health_delta, card.equipment_armor_delta, card.equipment_zeal_delta)


static func growth(mask: int, owned: OwnedCard) -> Dictionary:
	var deltas := attribute_deltas(mask)
	var changes := {}
	if deltas.x != 0: changes[OwnedCard.STAT_BASE_VALUE] = deltas.x
	if deltas.y != 0:
		var health := int(owned.get_base_stat_with_permanent_growth(OwnedCard.STAT_MAX_HEALTH))
		changes[OwnedCard.STAT_MAX_HEALTH] = maxi(deltas.y, 1 - health) if deltas.y < 0 else deltas.y
	if deltas.z != 0: changes[OwnedCard.STAT_BASE_ARMOR] = deltas.z
	return changes


static func add_locked_wound(owned: OwnedCard, pool: Array, rng: RandomNumberGenerator, receipt: String) -> bool:
	var empty_slots: Array[int] = []
	for index: int in owned.wound_slots.size():
		if owned.wound_slots[index].is_empty(): empty_slots.append(index)
	if empty_slots.is_empty(): return upgrade_locked_wound(owned, rng)
	if pool.is_empty(): return false
	var index := empty_slots[rng.randi_range(0, empty_slots.size() - 1)]
	return owned.set_wound_slot(index, make_locked_wound(pool, rng, receipt))


static func make_locked_wound(pool: Array, rng: RandomNumberGenerator, receipt: String) -> Dictionary:
	return {"wound_id": StringName(pool[rng.randi_range(0, pool.size() - 1)]), "instance_id": receipt, "level": 1, "temporary": false, "source": "maze_event", "locked": true}


static func upgrade_locked_wound(owned: OwnedCard, rng: RandomNumberGenerator) -> bool:
	var upgrades := {}
	var known := {}
	for definition: Dictionary in EmblemLibraryData.get_wound_definitions():
		known[String(definition.id)] = true
	for index: int in owned.wound_slots.size():
		var wound := String(owned.wound_slots[index].get("wound_id", ""))
		var next := ""
		if wound.ends_with("Ⅰ"): next = wound.trim_suffix("Ⅰ") + "Ⅱ"
		elif wound.ends_with("Ⅱ"): next = wound.trim_suffix("Ⅱ") + "Ⅲ"
		if known.has(next): upgrades[index] = next
	if upgrades.is_empty(): return false
	var indices := upgrades.keys()
	var index: int = indices[rng.randi_range(0, indices.size() - 1)]
	var state := owned.wound_slots[index].duplicate(true)
	state.wound_id = StringName(upgrades[index])
	state.level = mini(int(state.get("level", 1)) + 1, 3)
	state.locked = true
	return owned.set_wound_slot(index, state)
