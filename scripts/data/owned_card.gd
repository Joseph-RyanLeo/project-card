class_name OwnedCard
extends Resource

## 玩家在本局中实际拥有的一张卡牌。
## CardData 继续只保存共享定义；永久成长、伤势、纹章等可变状态必须留在这里，
## 避免两张同名卡因共用同一份 .tres 资源而互相污染。

const STAT_BASE_VALUE: StringName = &"base_value"
const STAT_MAX_HEALTH: StringName = &"max_health"
const STAT_BASE_ARMOR: StringName = &"base_armor"

@export var instance_id: StringName = &"" # 本局内稳定且唯一的卡牌实例身份
@export var card_data: CardData # 共享卡牌定义；不得把永久变化直接写回此资源
@export var acquisition_order: int = -1 # 同稀有度收藏排序使用的获得先后
@export var resolved_action_type: int = -1 # 多行动方式卡获得时确定的结果；-1表示沿用定义
@export var spell_durability: int = -1 # 法术剩余耐久；-1表示尚未初始化
@export var permanent_growth: Dictionary = {} # 属性稳定ID→本局永久增加量
@export var wound_slots: Array[Dictionary] = [] # 每项对应一个伤势槽；空字典表示空槽
@export var emblem_slots: Array[Dictionary] = [] # 每项对应一个纹章槽；空字典表示空槽
@export var rune_revealed: Array[bool] = [] # 与定义中的符文槽一一对应，内容本身仍由卡牌实例持有
@export var progress_by_source: Dictionary = {} # 种子等成长对象的实例进度；来源ID→数值


func initialize(
	definition: CardData,
	stable_instance_id: StringName,
	order: int
) -> void:
	card_data = definition
	instance_id = stable_instance_id
	acquisition_order = order
	resolved_action_type = -1
	spell_durability = -1
	if definition != null and definition.card_type == CardData.CardType.SPELL:
		# 品级枚举 I～V 正好是 0～4，因此 +1 就是新法术的 1～5 点耐久。
		spell_durability = int(definition.rarity) + 1
	permanent_growth.clear()
	progress_by_source.clear()
	wound_slots = _empty_slot_array(definition.wound_slot_count if definition != null else 0)
	emblem_slots = _empty_slot_array(definition.emblem_slot_count if definition != null else 0)
	rune_revealed.clear()
	if definition != null:
		for _rune_index: int in definition.runes.size():
			rune_revealed.append(false)


func is_valid() -> bool:
	return not instance_id.is_empty() and card_data != null


func apply_permanent_growth(stat: StringName, amount: float) -> bool:
	if stat not in [STAT_BASE_VALUE, STAT_MAX_HEALTH, STAT_BASE_ARMOR] or is_zero_approx(amount):
		return false
	permanent_growth[stat] = float(permanent_growth.get(stat, 0.0)) + amount
	return true


func get_permanent_growth(stat: StringName) -> float:
	return float(permanent_growth.get(stat, 0.0))


func get_effective_base_value() -> int:
	if card_data == null:
		return 0
	return clampi(
		roundi(float(card_data.base_value) + get_permanent_growth(STAT_BASE_VALUE)),
		0,
		CardData.MAXIMUM_BASE_VALUE
	)


func get_effective_max_health() -> int:
	if card_data == null:
		return 0
	return clampi(
		roundi(float(card_data.max_health) + get_permanent_growth(STAT_MAX_HEALTH)),
		0,
		CardData.MAXIMUM_HEALTH
	)


func get_effective_base_armor() -> int:
	if card_data == null:
		return 0
	return clampi(
		roundi(float(card_data.armor) + get_permanent_growth(STAT_BASE_ARMOR)),
		0,
		CardData.MAXIMUM_ARMOR
	)


func set_wound_slot(slot_index: int, slot_state: Dictionary) -> bool:
	if slot_index < 0 or slot_index >= wound_slots.size():
		return false
	wound_slots[slot_index] = slot_state.duplicate(true)
	return true


func set_emblem_slot(slot_index: int, slot_state: Dictionary) -> bool:
	if slot_index < 0 or slot_index >= emblem_slots.size():
		return false
	var previous_source_id := emblem_slots[slot_index].get("instance_id", &"") as StringName
	var next_source_id := slot_state.get("instance_id", &"") as StringName
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
		"spell_durability": spell_durability,
		"permanent_growth": permanent_growth.duplicate(true),
		"wound_slots": wound_slots.duplicate(true),
		"emblem_slots": emblem_slots.duplicate(true),
		"rune_revealed": rune_revealed.duplicate(),
		"progress_by_source": progress_by_source.duplicate(true),
		"owned_card_ref": self,
	}


func restore_state(snapshot: Dictionary) -> bool:
	var snapshot_instance_id := snapshot.get("instance_id", &"") as StringName
	var snapshot_card_data := snapshot.get("card_data") as CardData
	if snapshot_instance_id.is_empty() or snapshot_card_data == null:
		return false
	if not instance_id.is_empty() and instance_id != snapshot_instance_id:
		return false
	instance_id = snapshot_instance_id
	card_data = snapshot_card_data
	acquisition_order = int(snapshot.get("acquisition_order", -1))
	resolved_action_type = int(snapshot.get("resolved_action_type", -1))
	spell_durability = int(snapshot.get("spell_durability", -1))
	permanent_growth = (snapshot.get("permanent_growth", {}) as Dictionary).duplicate(true)
	wound_slots.assign((snapshot.get("wound_slots", []) as Array).duplicate(true))
	emblem_slots.assign((snapshot.get("emblem_slots", []) as Array).duplicate(true))
	rune_revealed.assign((snapshot.get("rune_revealed", []) as Array).duplicate())
	progress_by_source = (snapshot.get("progress_by_source", {}) as Dictionary).duplicate(true)
	return true


static func _empty_slot_array(slot_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for _slot_index: int in maxi(slot_count, 0):
		result.append({})
	return result
