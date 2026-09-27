class_name CardSlotLayout
extends RefCounted

## 卡牌边缘的伤势／纹章槽位布局。
## 槽位编号按用户确认的顺序保存：左侧从上到下，再右侧从下到上。

enum Kind { WOUND, EMBLEM }

const SLOT_POSITIONS: Array[Vector2] = [
	Vector2(-2, 39),
	Vector2(-2, 55),
	Vector2(-2, 71),
	Vector2(-2, 87),
	Vector2(86, 53),
	Vector2(86, 37),
	Vector2(86, 21),
	Vector2(86, 5),
] # 左一～左四、右一～右四；右侧数组故意从下向上保存

static var _stable_layout_cache: Dictionary = {}

static func get_default_counts(rarity: CardData.Rarity) -> Vector2i:
	match rarity:
		CardData.Rarity.I:
			return Vector2i(2, 2)
		CardData.Rarity.II:
			return Vector2i(2, 2)
		CardData.Rarity.III:
			return Vector2i(3, 3)
		CardData.Rarity.IV:
			return Vector2i(4, 4)
		CardData.Rarity.V:
			return Vector2i(3, 5)
	return Vector2i.ZERO


static func resolve_counts(card_data: CardData) -> Vector2i:
	if card_data == null:
		return Vector2i.ZERO
	var defaults := get_default_counts(card_data.rarity) if card_data.card_type == CardData.CardType.MINION else Vector2i.ZERO
	var wounds := defaults.x if card_data.wound_slot_count < 0 else card_data.wound_slot_count
	var emblems := defaults.y if card_data.emblem_slot_count < 0 else card_data.emblem_slot_count
	wounds = clampi(wounds, 0, 8)
	emblems = clampi(emblems, 0, 8 - wounds)
	return Vector2i(wounds, emblems)


static func get_stable_layout(card_data: CardData) -> Array[int]:
	if is_valid_layout(card_data, card_data.slot_layout):
		return card_data.slot_layout.duplicate()
	return _get_stable_default_layout(card_data)


static func create_random_layout(card_data: CardData, rng: RandomNumberGenerator) -> Array[int]:
	if is_valid_layout(card_data, card_data.slot_layout):
		return card_data.slot_layout.duplicate()
	var layouts := _enumerate_legal_layouts(card_data)
	if layouts.is_empty():
		return []
	return layouts[rng.randi_range(0, layouts.size() - 1)]


static func get_slot_definitions(card_data: CardData, owned_card: Variant = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if card_data == null:
		return result
	var configured_kinds: Array = []
	if owned_card != null and is_valid_layout(card_data, owned_card.slot_layout):
		configured_kinds = owned_card.slot_layout
	elif is_valid_layout(card_data, card_data.slot_layout):
		configured_kinds = card_data.slot_layout
	else:
		configured_kinds = _get_stable_default_layout(card_data)
	var used_counts := {Kind.WOUND: 0, Kind.EMBLEM: 0}
	for slot_index: int in SLOT_POSITIONS.size():
		var kind := int(configured_kinds[slot_index])
		if kind not in [Kind.WOUND, Kind.EMBLEM]:
			continue
		var storage_index := int(used_counts[kind])
		used_counts[kind] = storage_index + 1
		result.append({
			"slot_index": slot_index,
			"kind": kind,
			"storage_index": storage_index,
			"position": SLOT_POSITIONS[slot_index],
		})
	return result


static func _get_stable_default_layout(card_data: CardData) -> Array[int]:
	if card_data == null:
		return []
	var counts := resolve_counts(card_data)
	var cache_key := Vector2i(counts.x, counts.y)
	if _stable_layout_cache.has(cache_key):
		var cached_layout: Array[int] = []
		cached_layout.assign(_stable_layout_cache[cache_key])
		return cached_layout
	var layouts := _enumerate_legal_layouts(card_data)
	var stable_layout: Array[int] = []
	if not layouts.is_empty():
		stable_layout.assign(layouts[0])
	_stable_layout_cache[cache_key] = stable_layout.duplicate()
	return stable_layout


static func is_valid_layout(card_data: CardData, layout: Array) -> bool:
	if card_data == null or layout.size() != SLOT_POSITIONS.size():
		return false
	var counts := resolve_counts(card_data)
	var used_wounds := 0
	var used_emblems := 0
	var left_wounds := 0
	var left_emblems := 0
	var right_wounds := 0
	var right_emblems := 0
	for side_start: int in [0, 4]:
		var found_empty := false
		for offset: int in 4:
			var kind := int(layout[side_start + offset])
			if kind == -1:
				found_empty = true
				continue
			if found_empty or kind not in [Kind.WOUND, Kind.EMBLEM]:
				return false
			if side_start == 0:
				if kind == Kind.WOUND:
					left_wounds += 1
				else:
					left_emblems += 1
			else:
				if kind == Kind.WOUND:
					right_wounds += 1
				else:
					right_emblems += 1
			if kind == Kind.WOUND:
				used_wounds += 1
			else:
				used_emblems += 1
	return (
		used_wounds == counts.x
		and used_emblems == counts.y
		and abs(left_wounds - right_wounds) <= 1
		and abs(left_emblems - right_emblems) <= 1
	)


static func _enumerate_legal_layouts(card_data: CardData) -> Array[Array]:
	var result: Array[Array] = []
	if card_data == null:
		return result
	var counts := resolve_counts(card_data)
	if counts.x + counts.y > SLOT_POSITIONS.size():
		return result
	for left_total: int in range(0, 5):
		var right_total := counts.x + counts.y - left_total
		if right_total < 0 or right_total > 4:
			continue
		for left_emblems: int in range(maxi(0, left_total - counts.x), mini(left_total, counts.y) + 1):
			var left_wounds := left_total - left_emblems
			var right_emblems := counts.y - left_emblems
			var right_wounds := counts.x - left_wounds
			if right_emblems < 0 or right_wounds < 0:
				continue
			if abs(left_emblems - right_emblems) > 1 or abs(left_wounds - right_wounds) > 1:
				continue
			for left_mask: int in range(1 << left_total):
				if _count_set_bits(left_mask) != left_emblems:
					continue
				for right_mask: int in range(1 << right_total):
					if _count_set_bits(right_mask) != right_emblems:
						continue
					var layout: Array[int] = []
					for slot_index: int in SLOT_POSITIONS.size():
						layout.append(-1)
					for local_index: int in left_total:
						layout[local_index] = Kind.EMBLEM if (left_mask & (1 << local_index)) != 0 else Kind.WOUND
					for local_index: int in right_total:
						layout[4 + local_index] = Kind.EMBLEM if (right_mask & (1 << local_index)) != 0 else Kind.WOUND
					result.append(layout)
	return result


static func _count_set_bits(value: int) -> int:
	var count := 0
	while value != 0:
		count += value & 1
		value >>= 1
	return count
