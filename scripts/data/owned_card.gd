class_name OwnedCard
extends Resource

## 玩家在本局中实际拥有的一张卡牌。
## CardData 继续只保存共享定义；永久成长、伤势、纹章等可变状态必须留在这里，
## 避免两张同名卡因共用同一份 .tres 资源而互相污染。

const STAT_BASE_VALUE: StringName = &"base_value"
const STAT_MAX_HEALTH: StringName = &"max_health"
const STAT_BASE_ARMOR: StringName = &"base_armor"
const RuneRevealCoverStyleScript = preload("res://scripts/ui/rune_reveal_cover_style.gd")
const RUNE_SCRAPE_SIZE: int = RuneRevealCoverStyleScript.SIZE
const RUNE_SCRAPE_PIXEL_COUNT: int = RUNE_SCRAPE_SIZE * RUNE_SCRAPE_SIZE
const RUNE_SCRAPE_BYTE_COUNT: int = (RUNE_SCRAPE_PIXEL_COUNT + 7) / 8
const EmblemLibraryDataScript = preload("res://scripts/data/emblem_library_data.gd")
const CardSlotLayoutScript = preload("res://scripts/data/card_slot_layout.gd")
const ResourceHexLayoutScript = preload("res://scripts/data/resource_hex_layout.gd")

@export var instance_id: StringName = &"" # 本局内稳定且唯一的卡牌实例身份
@export var card_data: CardData # 共享卡牌定义；不得把永久变化直接写回此资源
@export var acquisition_order: int = -1 # 同稀有度收藏排序使用的获得先后
@export var resolved_action_type: int = -1 # 多行动方式卡获得时确定的结果；-1表示沿用定义
@export var resolved_runes: Array[int] = [] # 获得时固定的符文元素，按实例存档，不改共享定义
@export var spell_durability: int = -1 # 法术剩余耐久；-1表示尚未初始化
@export var permanent_growth: Dictionary = {} # 属性稳定ID→本局永久增加量
@export var crystallization_health_loss: int = 0 # 晶体化护甲归零造成的永久基础生命损失
@export var wound_slots: Array[Dictionary] = [] # 每项对应一个伤势槽；空字典表示空槽
@export var emblem_slots: Array[Dictionary] = [] # 每项对应一个纹章槽；空字典表示空槽
@export var slot_layout: Array[int] = [] # 获得时抽定并随实例保存的8个边缘槽位类别
@export var rune_revealed: Array[bool] = [] # 与定义中的符文槽一一对应，内容本身仍由卡牌实例持有
@export var rune_scrape_masks: Array[String] = [] # 每槽23×23圆形覆盖图的擦除位图，以位打包并Base64编码保存
@export var rune_stickers: Array[Dictionary] = [] # 后贴符文独立保存，刮下不会修改底层符文或揭晓状态
@export var progress_by_source: Dictionary = {} # 种子等成长对象的实例进度；来源ID→数值
@export var wound_battle_counters: Dictionary = {} # 持久伤势实例跨战计数，如骨折每场参战次数
@export var resource_shape: Array[Vector2i] = [] # 资源卡实例获得时抽定的六边格形状；非资源卡为空


func initialize(
	definition: CardData,
	stable_instance_id: StringName,
	order: int,
	instance_rng: RandomNumberGenerator = null
) -> void:
	card_data = definition
	instance_id = stable_instance_id
	acquisition_order = order
	resolved_action_type = -1
	resolved_runes.clear()
	spell_durability = -1
	if definition != null and definition.card_type == CardData.CardType.SPELL:
		# 品级枚举 I～V 正好是 0～4，因此 +1 就是新法术的 1～5 点耐久。
		spell_durability = int(definition.rarity) + 1
	permanent_growth.clear()
	crystallization_health_loss = 0
	progress_by_source.clear()
	wound_battle_counters.clear()
	resource_shape.clear()
	if definition != null and definition.card_type == CardData.CardType.RESOURCE:
		var shape_rng := instance_rng if instance_rng != null else RandomNumberGenerator.new()
		if instance_rng == null:
			shape_rng.randomize()
		resource_shape = ResourceHexLayoutScript.create_random_shape(int(definition.rarity) + 1, shape_rng)
	# 商店可传入已存档的随机流，使实例形状/槽位也能在购买和失败回滚后复现。
	var layout_rng := instance_rng if instance_rng != null else RandomNumberGenerator.new()
	if instance_rng == null:
		layout_rng.randomize()
	if definition != null:
		if definition.acquisition_action_types.size() > 1:
			resolved_action_type = definition.acquisition_action_types[layout_rng.randi_range(0, definition.acquisition_action_types.size() - 1)]
		else:
			resolved_action_type = definition.action_type
		if instance_rng != null:
			for _rune_index: int in definition.runes.size():
				resolved_runes.append(layout_rng.randi_range(0, CardData.ElementType.size() - 1))
		else:
			# 旧式开发实例与测试夹具没有获得随机流，沿用卡牌定义中的固定符文。
			resolved_runes.assign(definition.runes)
	slot_layout = CardSlotLayoutScript.create_random_layout(definition, layout_rng)
	var resolved_counts := CardSlotLayoutScript.resolve_counts(definition)
	wound_slots = _empty_slot_array(resolved_counts.x)
	emblem_slots = _empty_slot_array(resolved_counts.y)
	rune_revealed.clear()
	rune_scrape_masks.clear()
	rune_stickers = _empty_slot_array(definition.runes.size() if definition != null else 0)
	if definition != null:
		for _rune_index: int in definition.runes.size():
			rune_revealed.append(false)
			rune_scrape_masks.append("")


func is_valid() -> bool:
	return not instance_id.is_empty() and card_data != null


func apply_permanent_growth(stat: StringName, amount: float) -> bool:
	if stat not in [STAT_BASE_VALUE, STAT_MAX_HEALTH, STAT_BASE_ARMOR] or is_zero_approx(amount):
		return false
	permanent_growth[stat] = float(permanent_growth.get(stat, 0.0)) + amount
	return true


func apply_crystallization_health_loss(amount: int = 1) -> bool:
	if amount <= 0 or card_data == null:
		return false
	crystallization_health_loss = mini(
		crystallization_health_loss + amount,
		maxi(card_data.max_health - 1, 0)
	)
	return true


func get_permanent_growth(stat: StringName) -> float:
	return float(permanent_growth.get(stat, 0.0))


func get_effective_base_value() -> int:
	return get_effective_base_value_for_status_slots(
		_all_emblem_slot_indices(),
		_all_wound_slot_indices()
	)


func get_effective_base_value_for_emblem_slots(active_slot_indices: Array[int]) -> int:
	return get_effective_base_value_for_status_slots(active_slot_indices, _all_wound_slot_indices())


func get_effective_base_value_for_status_slots(
	active_emblem_slot_indices: Array[int],
	active_wound_slot_indices: Array[int]
) -> int:
	if card_data == null:
		return 0
	return clampi(
		roundi(
			get_base_stat_with_permanent_growth(STAT_BASE_VALUE)
			+ get_emblem_static_modifier(&"base_value", active_emblem_slot_indices)
			+ get_wound_static_modifier(&"base_value", active_wound_slot_indices)
		),
		0,
		CardData.MAXIMUM_BASE_VALUE
	)


func get_effective_max_health() -> int:
	return get_effective_max_health_for_status_slots(
		_all_emblem_slot_indices(),
		_all_wound_slot_indices()
	)


func get_effective_max_health_for_emblem_slots(active_slot_indices: Array[int]) -> int:
	return get_effective_max_health_for_status_slots(active_slot_indices, _all_wound_slot_indices())


func get_effective_max_health_for_status_slots(
	active_emblem_slot_indices: Array[int],
	active_wound_slot_indices: Array[int]
) -> int:
	if card_data == null:
		return 0
	return clampi(
		roundi(
			get_base_stat_with_permanent_growth(STAT_MAX_HEALTH)
			+ get_emblem_static_modifier(&"max_health", active_emblem_slot_indices)
			+ get_wound_static_modifier(&"max_health", active_wound_slot_indices)
		),
		0,
		CardData.MAXIMUM_HEALTH
	)


func get_effective_base_armor() -> int:
	return get_effective_base_armor_for_status_slots(
		_all_emblem_slot_indices(),
		_all_wound_slot_indices()
	)


func get_effective_base_armor_for_emblem_slots(active_slot_indices: Array[int]) -> int:
	return get_effective_base_armor_for_status_slots(active_slot_indices, _all_wound_slot_indices())


func get_effective_base_armor_for_status_slots(
	active_emblem_slot_indices: Array[int],
	active_wound_slot_indices: Array[int]
) -> int:
	if card_data == null:
		return 0
	return clampi(
		roundi(
			get_base_stat_with_permanent_growth(STAT_BASE_ARMOR)
			+ get_emblem_static_modifier(&"base_armor", active_emblem_slot_indices)
			+ get_wound_static_modifier(&"base_armor", active_wound_slot_indices)
		),
		0,
		CardData.MAXIMUM_ARMOR
	)


func get_emblem_static_modifier(stat: StringName, active_slot_indices: Array[int]) -> int:
	var total := 0
	for slot_index: int in active_slot_indices:
		if slot_index < 0 or slot_index >= emblem_slots.size():
			continue
		var state := emblem_slots[slot_index]
		if state.is_empty():
			continue
		total += EmblemLibraryDataScript.get_static_modifier(
			StringName(String(state.get("emblem_id", ""))),
			stat
		)
	return total


func get_wound_static_modifier(stat: StringName, active_slot_indices: Array[int]) -> int:
	var total := 0
	for slot_index: int in active_slot_indices:
		if slot_index < 0 or slot_index >= wound_slots.size():
			continue
		var state := wound_slots[slot_index]
		if state.is_empty():
			continue
		total += EmblemLibraryDataScript.get_wound_static_modifier(
			StringName(String(state.get("wound_id", ""))),
			stat
		)
	return total


func get_base_stat_with_permanent_growth(stat: StringName) -> float:
	if card_data == null:
		return 0.0
	var definition_value := 0.0
	match stat:
		STAT_BASE_VALUE:
			definition_value = float(card_data.base_value)
		STAT_MAX_HEALTH:
			definition_value = float(card_data.max_health - crystallization_health_loss)
		STAT_BASE_ARMOR:
			definition_value = float(card_data.armor)
		_:
			return 0.0
	return definition_value + get_permanent_growth(stat)


func get_emblem_zeal_for_slots(active_slot_indices: Array[int]) -> int:
	return get_emblem_static_modifier(&"zeal", active_slot_indices)


func get_emblem_zeal() -> int:
	return get_emblem_zeal_for_slots(_all_emblem_slot_indices())


func get_status_zeal() -> int:
	return get_emblem_zeal() + get_wound_static_modifier(&"zeal", _all_wound_slot_indices())


func _all_emblem_slot_indices() -> Array[int]:
	var result: Array[int] = []
	for slot_index: int in emblem_slots.size():
		result.append(slot_index)
	return result


func _all_wound_slot_indices() -> Array[int]:
	var result: Array[int] = []
	for slot_index: int in wound_slots.size():
		result.append(slot_index)
	return result


func set_wound_slot(slot_index: int, slot_state: Dictionary) -> bool:
	if slot_index < 0 or slot_index >= wound_slots.size():
		return false
	wound_slots[slot_index] = slot_state.duplicate(true)
	return true


func set_emblem_slot(slot_index: int, slot_state: Dictionary) -> bool:
	if slot_index < 0 or slot_index >= emblem_slots.size():
		return false
	var previous_source_id := StringName(String(emblem_slots[slot_index].get("instance_id", "")))
	var next_source_id := StringName(String(slot_state.get("instance_id", "")))
	emblem_slots[slot_index] = slot_state.duplicate(true)
	if not previous_source_id.is_empty() and previous_source_id != next_source_id:
		progress_by_source.erase(previous_source_id)
	return true


func add_emblem_progress(emblem_instance_id: StringName, amount: int) -> int:
	if emblem_instance_id.is_empty() or amount <= 0:
		return -1
	for slot_state: Dictionary in emblem_slots:
		if slot_state.get("instance_id", &"") != emblem_instance_id:
			continue
		if bool(slot_state.get("temporary", false)):
			# 临时种子的进度随临时纹章消失，不进入永久实例状态。
			return 0
		var next_progress := int(progress_by_source.get(emblem_instance_id, 0)) + amount
		progress_by_source[emblem_instance_id] = next_progress
		return next_progress
	return -1


func capture_state() -> Dictionary:
	# 快照保留资源引用只用于当前运行中的精确恢复；以后写入磁盘时再由存档层
	# 把 card_data 转换成稳定 card_id / resource_path，而不是在这里猜存档格式。
	return {
		"instance_id": instance_id,
		"card_data": card_data,
		"acquisition_order": acquisition_order,
		"resolved_action_type": resolved_action_type,
		"resolved_runes": resolved_runes.duplicate(),
		"spell_durability": spell_durability,
		"permanent_growth": permanent_growth.duplicate(true),
		"crystallization_health_loss": crystallization_health_loss,
		"wound_slots": wound_slots.duplicate(true),
		"emblem_slots": emblem_slots.duplicate(true),
		"slot_layout": slot_layout.duplicate(),
		"rune_revealed": rune_revealed.duplicate(),
		"rune_scrape_masks": rune_scrape_masks.duplicate(),
		"rune_stickers": rune_stickers.duplicate(true),
		"progress_by_source": progress_by_source.duplicate(true),
		"wound_battle_counters": wound_battle_counters.duplicate(true),
		"resource_shape": _encode_resource_shape(),
		"owned_card_ref": self,
	}


func restore_state(snapshot: Dictionary) -> bool:
	var snapshot_instance_id := snapshot.get("instance_id", &"") as StringName
	var snapshot_card_data := snapshot.get("card_data") as CardData
	var resolved_runes_value: Variant = snapshot.get("resolved_runes", snapshot_card_data.runes if snapshot_card_data != null else [])
	var rune_scrape_masks_value: Variant = snapshot.get("rune_scrape_masks", _empty_rune_scrape_masks(snapshot_card_data.runes.size() if snapshot_card_data != null else 0))
	var resolved_action_type := int(snapshot.get("resolved_action_type", -1))
	var prevalidated_shape: Array[Vector2i] = []
	var prevalidated_runes: Array[int] = []
	if snapshot_card_data == null or not resolved_runes_value is Array or resolved_runes_value.size() != snapshot_card_data.runes.size():
		return false
	if resolved_action_type < -1 or resolved_action_type >= CardData.ActionType.size():
		return false
	if not rune_scrape_masks_value is Array or rune_scrape_masks_value.size() != snapshot_card_data.runes.size():
		return false
	var prevalidated_rune_scrape_masks: Array[String] = []
	for mask_value: Variant in rune_scrape_masks_value:
		if not mask_value is String or not is_rune_scrape_mask_valid(mask_value as String):
			return false
		prevalidated_rune_scrape_masks.append(mask_value as String)
	for rune_value: Variant in resolved_runes_value:
		if not (rune_value is int or rune_value is float) or not is_finite(float(rune_value)) or float(rune_value) != floor(float(rune_value)) or int(rune_value) < 0 or int(rune_value) >= CardData.ElementType.size():
			return false
		prevalidated_runes.append(int(rune_value))
	if snapshot_card_data != null and snapshot_card_data.card_type == CardData.CardType.RESOURCE:
		var shape_value: Variant = snapshot.get("resource_shape", null)
		if not shape_value is Array:
			return false
		for pair in shape_value:
			if not pair is Array or pair.size() != 2:
				return false
			prevalidated_shape.append(Vector2i(int(pair[0]), int(pair[1])))
		if prevalidated_shape.size() != int(snapshot_card_data.rarity) + 1 or not ResourceHexLayoutScript.is_connected_shape(prevalidated_shape):
			return false
	if snapshot_instance_id.is_empty() or snapshot_card_data == null:
		return false
	if not instance_id.is_empty() and instance_id != snapshot_instance_id:
		return false
	instance_id = snapshot_instance_id
	card_data = snapshot_card_data
	acquisition_order = int(snapshot.get("acquisition_order", -1))
	self.resolved_action_type = resolved_action_type
	resolved_runes.assign(prevalidated_runes)
	spell_durability = int(snapshot.get("spell_durability", -1))
	permanent_growth = (snapshot.get("permanent_growth", {}) as Dictionary).duplicate(true)
	crystallization_health_loss = maxi(int(snapshot.get("crystallization_health_loss", 0)), 0)
	wound_slots.assign((snapshot.get("wound_slots", []) as Array).duplicate(true))
	emblem_slots.assign((snapshot.get("emblem_slots", []) as Array).duplicate(true))
	var restored_layout: Array = snapshot.get("slot_layout", []) as Array
	slot_layout.assign(
		(restored_layout if CardSlotLayoutScript.is_valid_layout(card_data, restored_layout) else CardSlotLayoutScript.get_stable_layout(card_data)).duplicate()
	)
	rune_revealed.assign((snapshot.get("rune_revealed", []) as Array).duplicate())
	rune_scrape_masks.assign(prevalidated_rune_scrape_masks)
	rune_stickers.assign((snapshot.get("rune_stickers", _empty_slot_array(card_data.runes.size())) as Array).duplicate(true))
	progress_by_source = (snapshot.get("progress_by_source", {}) as Dictionary).duplicate(true)
	wound_battle_counters = (snapshot.get("wound_battle_counters", {}) as Dictionary).duplicate(true)
	if card_data.card_type == CardData.CardType.RESOURCE:
		resource_shape = prevalidated_shape
	else:
		resource_shape.clear()
	return true


func get_effective_rune(index: int) -> CardData.ElementType:
	if index < rune_stickers.size() and not rune_stickers[index].is_empty():
		return int(rune_stickers[index].get("element", resolved_runes[index])) as CardData.ElementType
	return resolved_runes[index] as CardData.ElementType if index < resolved_runes.size() else card_data.runes[index]


func record_rune_scrape_pixels(index: int, pixels: Array[Vector2i]) -> int:
	if card_data == null or index < 0 or index >= card_data.runes.size() or index >= rune_scrape_masks.size():
		return 0
	var mask_bytes := _decode_rune_scrape_mask(rune_scrape_masks[index])
	var added := 0
	for pixel: Vector2i in pixels:
		if not is_rune_cover_pixel(pixel):
			continue
		var pixel_index := pixel.y * RUNE_SCRAPE_SIZE + pixel.x
		var byte_index := pixel_index >> 3
		var bit_mask := 1 << (pixel_index % 8)
		if int(mask_bytes[byte_index]) & bit_mask != 0:
			continue
		mask_bytes[byte_index] = int(mask_bytes[byte_index]) | bit_mask
		added += 1
	if added > 0:
		rune_scrape_masks[index] = Marshalls.raw_to_base64(mask_bytes)
	return added


func get_rune_scrape_mask_bytes(index: int) -> PackedByteArray:
	if index < 0 or index >= rune_scrape_masks.size():
		return PackedByteArray()
	return _decode_rune_scrape_mask(rune_scrape_masks[index])


func has_rune_scraped_pixel(index: int, pixel: Vector2i) -> bool:
	if index < 0 or index >= rune_scrape_masks.size() or not is_rune_cover_pixel(pixel):
		return false
	return _mask_byte_has_pixel(get_rune_scrape_mask_bytes(index), pixel)


func get_rune_scraped_pixel_count(index: int) -> int:
	var bytes := get_rune_scrape_mask_bytes(index)
	if bytes.size() != RUNE_SCRAPE_BYTE_COUNT:
		return 0
	var count := 0
	for y: int in RUNE_SCRAPE_SIZE:
		for x: int in RUNE_SCRAPE_SIZE:
			var point := Vector2i(x, y)
			if is_rune_cover_pixel(point) and _mask_byte_has_pixel(bytes, point):
				count += 1
	return count


static func is_rune_cover_pixel(point: Vector2i) -> bool:
	return RuneRevealCoverStyleScript.is_cover_pixel(point)


static func is_rune_scrape_mask_valid(encoded_mask: String) -> bool:
	if encoded_mask.is_empty():
		return true
	var bytes := Marshalls.base64_to_raw(encoded_mask)
	if bytes.size() != RUNE_SCRAPE_BYTE_COUNT:
		return false
	for y: int in RUNE_SCRAPE_SIZE:
		for x: int in RUNE_SCRAPE_SIZE:
			var point := Vector2i(x, y)
			if not is_rune_cover_pixel(point) and _mask_byte_has_pixel(bytes, point):
				return false
	return true


static func _empty_rune_scrape_masks(count: int) -> Array[String]:
	var result: Array[String] = []
	for _index: int in count:
		result.append("")
	return result


static func _decode_rune_scrape_mask(encoded_mask: String) -> PackedByteArray:
	if encoded_mask.is_empty():
		var empty := PackedByteArray()
		empty.resize(RUNE_SCRAPE_BYTE_COUNT)
		empty.fill(0)
		return empty
	return Marshalls.base64_to_raw(encoded_mask)


static func _mask_byte_has_pixel(bytes: PackedByteArray, point: Vector2i) -> bool:
	var pixel_index := point.y * RUNE_SCRAPE_SIZE + point.x
	var byte_index := pixel_index >> 3
	return byte_index < bytes.size() and (int(bytes[byte_index]) & (1 << (pixel_index % 8))) != 0


func set_rune_sticker(index: int, state: Dictionary) -> bool:
	if card_data == null or index < 0 or index >= card_data.runes.size():
		return false
	while rune_stickers.size() < card_data.runes.size():
		rune_stickers.append({})
	rune_stickers[index] = state.duplicate(true)
	return true


static func _empty_slot_array(slot_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for _slot_index: int in maxi(slot_count, 0):
		result.append({})
	return result


func _encode_resource_shape() -> Array:
	var result: Array = []
	for cell in resource_shape:
		result.append([cell.x, cell.y])
	return result
