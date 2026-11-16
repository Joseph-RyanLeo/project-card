extends RefCounted

## 四种药剂用四个位标记。按位组合可以共用同一组数值，单药和合剂不会分开维护。
const BONE := 1
const HEART := 2
const SWIFT := 4
const SHELL := 8
const PERMANENT_ZEAL := &"event_potion_zeal"
const FORBIDDEN_PROTECTION := &"forbidden_protection"
const FORBIDDEN_IMMUNITY := &"forbidden_immunity"


static func growth(mask: int, owned: OwnedCard) -> Dictionary:
	var changes := {}
	if mask & BONE: changes[OwnedCard.STAT_BASE_VALUE] = 1
	if mask & (BONE | HEART):
		var amount := (2 if mask & HEART else 0) - (1 if mask & BONE else 0)
		var health := int(owned.get_base_stat_with_permanent_growth(OwnedCard.STAT_MAX_HEALTH))
		changes[OwnedCard.STAT_MAX_HEALTH] = maxi(amount, 1 - health) if amount < 0 else amount
	if mask & SHELL: changes[OwnedCard.STAT_BASE_ARMOR] = 2
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
