class_name SquadData
extends Resource

## 小队的权威数据模型。
## horizontal_cards 决定左右位置，layer_cards 决定遮挡层级，
## two_card_layout 决定双卡间距；显示节点只能据此绘制，不能另存一套顺序。

const OwnedCard = preload("res://scripts/data/owned_card.gd")

enum TwoCardLayout {
	COMPACT,
	EXPANDED,
}

const MAX_CARD_COUNT: int = 3 # 单个小队允许包含的随从卡上限
const SINGLE_UNIT_COUNT: int = 3 # 单卡小队占用的战场单元数
const COMPACT_DOUBLE_UNIT_COUNT: int = 4 # 紧密双卡小队占用的战场单元数
const EXPANDED_DOUBLE_UNIT_COUNT: int = 5 # 展开双卡小队占用的战场单元数
const TRIPLE_UNIT_COUNT: int = 5 # 三卡小队占用的战场单元数
const CARD_WIDTH: int = 99 # 每张完整随从卡保持的固定裸卡宽度
const RUNE_SLOT_CENTER_X: Array[float] = [19.5, 49.5, 79.5] # 三个符文槽相对裸卡左边缘的中心 X
const FORBID_STACKING_KEYWORD: StringName = &"forbid_stacking" # 带此固有关键词的卡只能独立组成单卡小队
const DEFAULT_EQUIPMENT_INDICATOR_POSITION := Vector2(49.5, 68.0) # 无落点数据时，装备指示物默认位于最上层卡牌中心
const UNSPECIFIED_EQUIPMENT_INDICATOR_POSITION := Vector2(-1.0, -1.0) # equip_item未传落点时的内部哨兵值，不代表卡面坐标

@export var horizontal_cards: Array[CardData] = [] # 小队从左到右的卡牌顺序
@export var layer_cards: Array[CardData] = [] # 从最上层到最下层保存，第一项提供卡牌效果
@export var two_card_layout: TwoCardLayout = TwoCardLayout.EXPANDED # 双卡使用紧密或展开吸附布局
var _owned_cards_by_card: Dictionary = {} # CardData引用→本局唯一OwnedCard；显示层仍可沿用CardData
var _equipped_item: OwnedCard # 装备位引用同一OwnedCard物品实例；指示物只是它的场上显示形态
var indicator_attachments: Array[Dictionary] = [] # 独立日月星实例、顶牌局部中心与附加顺序，不占装备位
var _equipment_indicator_card_position: Vector2 = DEFAULT_EQUIPMENT_INDICATOR_POSITION # 指示物中心相对小队最上层卡牌左上角的位置


static func from_card(card_data: CardData) -> SquadData:
	# 单卡进入战场时使用的最小合法小队工厂。
	var squad := SquadData.new()
	if card_data != null:
		squad.horizontal_cards.append(card_data)
		squad.layer_cards.append(card_data)
	return squad


static func from_owned_card(owned_card: OwnedCard) -> SquadData:
	var squad := from_card(owned_card.card_data if owned_card != null else null)
	if owned_card != null:
		squad.bind_owned_card(owned_card.card_data, owned_card)
	return squad


static func from_cards(
	cards: Array[CardData],
	layout: TwoCardLayout = TwoCardLayout.EXPANDED
) -> SquadData:
	# 测试、预览和批量建队共用的工厂；自动去除 null 与重复引用。
	var squad := SquadData.new()
	for card_data: CardData in cards:
		if card_data != null and not squad.horizontal_cards.has(card_data):
			squad.horizontal_cards.append(card_data)
			squad.layer_cards.append(card_data)
	squad.two_card_layout = layout
	squad._normalize()
	return squad


func duplicate_squad() -> SquadData:
	# 拖拽预览必须修改副本，成功 drop 前不得污染真实三套顺序。
	var copy := SquadData.new()
	copy.horizontal_cards.assign(horizontal_cards)
	copy.layer_cards.assign(layer_cards)
	copy.two_card_layout = two_card_layout
	copy._owned_cards_by_card = _owned_cards_by_card.duplicate()
	copy._equipped_item = _equipped_item
	copy._equipment_indicator_card_position = _equipment_indicator_card_position
	for attachment: Dictionary in indicator_attachments:
		copy.indicator_attachments.append(attachment.duplicate())
	return copy


func has_indicator(kind: int) -> bool:
	for attachment: Dictionary in indicator_attachments:
		if (attachment["indicator"] as CelestialIndicator).kind == kind:
			return true
	return false


func attach_indicator(indicator: CelestialIndicator, card_position: Vector2, order: int) -> bool:
	if indicator == null or not indicator.is_valid() or has_indicator(indicator.kind) or not card_position.is_finite() or order < 0:
		return false
	indicator_attachments.append({"indicator": indicator, "position": card_position, "order": order})
	return true


func detach_indicator(instance_id: StringName) -> bool:
	for index: int in indicator_attachments.size():
		if (indicator_attachments[index]["indicator"] as CelestialIndicator).instance_id == instance_id:
			indicator_attachments.remove_at(index)
			return true
	return false


func merge_indicators_from(other: SquadData) -> void:
	if other == null:
		return
	var combined := indicator_attachments.duplicate()
	for attachment: Dictionary in other.indicator_attachments:
		combined.append(attachment.duplicate())
	combined.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	indicator_attachments.clear()
	for attachment: Dictionary in combined:
		var indicator := attachment["indicator"] as CelestialIndicator
		attach_indicator(indicator, attachment["position"], int(attachment["order"]))


func capture_indicators() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for attachment: Dictionary in indicator_attachments:
		var state := (attachment["indicator"] as CelestialIndicator).capture_state()
		var point: Vector2 = attachment["position"]
		state["position"] = [point.x, point.y]
		state["order"] = int(attachment["order"])
		result.append(state)
	return result


func restore_indicators(entries: Array) -> bool:
	var candidate := SquadData.new()
	for value: Variant in entries:
		if not value is Dictionary:
			return false
		var entry := value as Dictionary
		var point: Variant = entry.get("position")
		if not point is Array or (point as Array).size() != 2:
			return false
		if not candidate.attach_indicator(CelestialIndicator.from_state(entry), Vector2(float(point[0]), float(point[1])), int(entry.get("order", -1))):
			return false
	indicator_attachments.assign(candidate.indicator_attachments)
	return true


func bind_owned_card(card_data: CardData, owned_card: OwnedCard) -> bool:
	if (
		card_data == null
		or owned_card == null
		or owned_card.card_data != card_data
		or not contains(card_data)
	):
		return false
	_owned_cards_by_card[card_data] = owned_card
	return true


func get_owned_card(card_data: CardData) -> OwnedCard:
	return _owned_cards_by_card.get(card_data) as OwnedCard


func get_action_source_instance() -> OwnedCard:
	return get_owned_card(get_action_source())


func get_vitals_source_instance() -> OwnedCard:
	return get_owned_card(get_vitals_source())


func get_effect_source_instance() -> OwnedCard:
	return get_owned_card(get_effect_source())


func can_equip_item(owned_item: OwnedCard) -> bool:
	return (
		_equipped_item == null
		and owned_item != null
		and owned_item.is_valid()
		and owned_item.card_data.card_type == CardData.CardType.EQUIPMENT
	)


func equip_item(
	owned_item: OwnedCard,
	indicator_position: Vector2 = UNSPECIFIED_EQUIPMENT_INDICATOR_POSITION
) -> bool:
	# 装备位只保存收藏物品实例的引用，不生成第二张“装备指示物卡”。
	if not can_equip_item(owned_item) or not indicator_position.is_finite():
		return false
	_equipped_item = owned_item
	_equipment_indicator_card_position = (
		DEFAULT_EQUIPMENT_INDICATOR_POSITION
		if indicator_position == UNSPECIFIED_EQUIPMENT_INDICATOR_POSITION
		else indicator_position - _get_effect_source_horizontal_offset()
	)
	return true


func get_equipped_item() -> OwnedCard:
	return _equipped_item


func get_equipment_zeal_delta() -> int:
	return (
		_equipped_item.card_data.equipment_zeal_delta
		if _equipped_item != null and _equipped_item.card_data != null
		else 0
	)


func get_equipment_indicator_position() -> Vector2:
	# 对显示、拖拽和存档仍提供小队局部坐标；内部落点跟随当前顶牌移动。
	if _equipped_item == null:
		return DEFAULT_EQUIPMENT_INDICATOR_POSITION
	return _equipment_indicator_card_position + _get_effect_source_horizontal_offset()


func set_equipment_indicator_position(value: Vector2) -> bool:
	if _equipped_item == null or not value.is_finite():
		return false
	_equipment_indicator_card_position = value - _get_effect_source_horizontal_offset()
	return true


func _get_effect_source_horizontal_offset() -> Vector2:
	var top_card_index := horizontal_cards.find(get_effect_source())
	var card_x_positions := get_card_x_positions()
	return (
		Vector2(card_x_positions[top_card_index], 0.0)
		if top_card_index >= 0 else Vector2.ZERO
	)


func unequip_item() -> OwnedCard:
	var returned_item := _equipped_item
	_equipped_item = null
	_equipment_indicator_card_position = DEFAULT_EQUIPMENT_INDICATOR_POSITION
	return returned_item


func return_equipment_for_split() -> OwnedCard:
	indicator_attachments.clear()
	# 拆队不判断装备来自哪一张成员卡；当前规则统一把小队装备退回收藏。
	return unequip_item()


func merge_equipment_from(other_squad: SquadData) -> Array[OwnedCard]:
	merge_indicators_from(other_squad)
	# 收藏容器始终保有这些实例；返回数组只告诉调用者哪些装备已解除绑定。
	var returned_items: Array[OwnedCard] = []
	if other_squad == null or other_squad._equipped_item == null:
		return returned_items
	if _equipped_item == null:
		_equipped_item = other_squad._equipped_item
		_equipment_indicator_card_position = other_squad._equipment_indicator_card_position
		return returned_items
	returned_items.append(_equipped_item)
	returned_items.append(other_squad._equipped_item)
	_equipped_item = null
	_equipment_indicator_card_position = DEFAULT_EQUIPMENT_INDICATOR_POSITION
	return returned_items


func get_effective_action_base_value() -> int:
	var owned_card := get_action_source_instance()
	var source := get_action_source()
	var base := (
		owned_card.get_effective_base_value()
		if owned_card != null
		else (source.base_value if source != null else 0)
	)
	var equipment := _equipped_item.card_data if _equipped_item != null else null
	return clampi(
		base + (equipment.equipment_action_delta if equipment != null else 0)
		+ (CelestialIndicator.SUN_VALUE if has_indicator(CelestialIndicator.Kind.SUN) else 0)
		+ (CelestialIndicator.STAR_VALUE if has_indicator(CelestialIndicator.Kind.STAR) else 0),
		0,
		CardData.MAXIMUM_BASE_VALUE
	)


func get_effective_max_health() -> int:
	var owned_card := get_vitals_source_instance()
	var source := get_vitals_source()
	var base := (
		owned_card.get_effective_max_health()
		if owned_card != null
		else (source.max_health if source != null else 0)
	)
	var equipment := _equipped_item.card_data if _equipped_item != null else null
	return clampi(
		base + (equipment.equipment_health_delta if equipment != null else 0)
		+ (CelestialIndicator.SUN_HEALTH if has_indicator(CelestialIndicator.Kind.SUN) else 0),
		0,
		CardData.MAXIMUM_HEALTH
	)


func get_effective_base_armor() -> int:
	var owned_card := get_vitals_source_instance()
	var source := get_vitals_source()
	var base := (
		owned_card.get_effective_base_armor()
		if owned_card != null
		else (source.armor if source != null else 0)
	)
	var equipment := _equipped_item.card_data if _equipped_item != null else null
	return clampi(
		base + (equipment.equipment_armor_delta if equipment != null else 0)
		+ (CelestialIndicator.MOON_ARMOR if has_indicator(CelestialIndicator.Kind.MOON) else 0),
		0,
		CardData.MAXIMUM_ARMOR
	)


func get_effective_action_type() -> CardData.ActionType:
	var owned_card := get_action_source_instance()
	var source := get_action_source()
	if owned_card != null and owned_card.resolved_action_type >= 0:
		return owned_card.resolved_action_type as CardData.ActionType
	return source.action_type if source != null else CardData.ActionType.MELEE


func is_valid() -> bool:
	# 合法小队要求两套顺序包含完全相同且互不重复的卡牌。
	if horizontal_cards.is_empty() or horizontal_cards.size() > MAX_CARD_COUNT:
		return false
	if horizontal_cards.size() != layer_cards.size():
		return false
	for card_data: CardData in horizontal_cards:
		if card_data == null or horizontal_cards.count(card_data) != 1:
			return false
		if layer_cards.count(card_data) != 1:
			return false
	if (
		_equipped_item != null
		and (
			not _equipped_item.is_valid()
			or _equipped_item.card_data.card_type != CardData.CardType.EQUIPMENT
			or not _equipment_indicator_card_position.is_finite()
		)
	):
		return false
	if horizontal_cards.size() > 1 and contains_stacking_forbidden_card():
		return false
	return true


func get_card_count() -> int:
	return horizontal_cards.size()


func contains(card_data: CardData) -> bool:
	return horizontal_cards.has(card_data)


func contains_stacking_forbidden_card() -> bool:
	for card_data: CardData in horizontal_cards:
		if card_data != null and card_data.has_keyword(FORBID_STACKING_KEYWORD):
			return true
	return false


func get_unit_count() -> int:
	# 战场容量只认数据布局，不读取节点实际像素宽度。
	match horizontal_cards.size():
		1:
			return SINGLE_UNIT_COUNT
		2:
			return (
				COMPACT_DOUBLE_UNIT_COUNT
				if two_card_layout == TwoCardLayout.COMPACT
				else EXPANDED_DOUBLE_UNIT_COUNT
			)
		3:
			return TRIPLE_UNIT_COUNT
		_:
			return 0


func get_display_width() -> int:
	# 真实显示宽度由卡宽与固定重叠推导，牌型标签不参与尺寸。
	match horizontal_cards.size():
		1:
			return CARD_WIDTH
		2:
			return 129 if two_card_layout == TwoCardLayout.COMPACT else 159
		3:
			return 159
		_:
			return 0


func get_card_x_positions() -> Array[float]:
	# 返回每张完整 99px 卡牌左边缘；重叠只由这些 X 差值形成。
	var positions: Array[float] = []
	match horizontal_cards.size():
		1:
			positions.assign([0.0])
		2:
			positions.assign(
				[0.0, 30.0]
				if two_card_layout == TwoCardLayout.COMPACT
				else [0.0, 60.0]
			)
		3:
			positions.assign([0.0, 30.0, 60.0])
	return positions


func get_visible_rune_counts() -> Array[int]:
	var counts: Array[int] = []
	counts.resize(horizontal_cards.size())
	counts.fill(0)
	for slot: Dictionary in get_visible_rune_slots():
		var card_index := int(slot["card_index"])
		counts[card_index] += 1
	return counts


func get_visible_rune_slots() -> Array[Dictionary]:
	# 输出的不只是数量，还包括卡牌、槽位和画面中心，保证牌型与高亮
	# 使用同一份从左到右的可见符文事实。
	var visible_slots: Array[Dictionary] = []
	var x_positions := get_card_x_positions()
	for card_index: int in horizontal_cards.size():
		var card_data := horizontal_cards[card_index]
		var card_layer_index := layer_cards.find(card_data)
		if card_layer_index < 0:
			continue
		var rune_count := mini(card_data.runes.size(), RUNE_SLOT_CENTER_X.size())
		for rune_index: int in rune_count:
			var world_center_x := (
				x_positions[card_index] + RUNE_SLOT_CENTER_X[rune_index]
			)
			if _is_rune_center_covered(world_center_x, card_layer_index, x_positions):
				continue
			visible_slots.append({
				"card": card_data,
				"card_index": card_index,
				"rune_index": rune_index,
				"element": card_data.runes[rune_index],
				"world_center_x": world_center_x,
			})

	# 水平顺序只能确定卡牌的左、中、右位置；这里再按每个真实可见
	# 槽位的画面中心排序，才得到玩家实际看到的从左到右符文序列。
	visible_slots.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left["world_center_x"]) < float(right["world_center_x"])
	)
	return visible_slots


func get_visible_runes() -> Array[CardData.ElementType]:
	var visible_runes: Array[CardData.ElementType] = []
	for slot: Dictionary in get_visible_rune_slots():
		visible_runes.append(slot["element"] as CardData.ElementType)
	return visible_runes


func get_rune_pattern_result() -> RunePatternResult:
	# SquadData 负责提供真实序列，独立规则类只负责纯识别。
	return RunePatternRules.identify(get_visible_runes())


func _is_rune_center_covered(
	world_center_x: float,
	card_layer_index: int,
	x_positions: Array[float]
) -> bool:
	# layer_cards 从最上层到最下层保存，所以当前卡之前的每一张卡
	# 都可能遮住它。符文中心落入上层完整卡面的水平范围时，该槽位
	# 在画面中不可见，也就不能进入牌型。
	for upper_layer_index: int in card_layer_index:
		var upper_card := layer_cards[upper_layer_index]
		var upper_horizontal_index := horizontal_cards.find(upper_card)
		if upper_horizontal_index < 0:
			continue
		var upper_left_x := x_positions[upper_horizontal_index]
		if (
			world_center_x > upper_left_x
			and world_center_x < upper_left_x + CARD_WIDTH
		):
			return true
	return false


func can_accept_external_card_at(horizontal_index: int) -> bool:
	# 容量允许不代表布局一定合法；展开双卡只接受第三张中插。
	if horizontal_cards.size() >= MAX_CARD_COUNT:
		return false
	if (
		horizontal_cards.size() == 2
		and two_card_layout == TwoCardLayout.EXPANDED
	):
		# 展开双卡已占五单元，只能把第三张卡插入两卡之间形成
		# 1+3+1；插到两侧会形成一张完全被遮住的 2+3+0。
		return clampi(horizontal_index, 0, horizontal_cards.size()) == 1
	return true


func can_accept_card_at(card_data: CardData, horizontal_index: int) -> bool:
	# “无法堆叠”是卡牌固有规则：无论它作为来牌还是已在目标小队中，
	# 都不能与另一张牌形成小队，也不依赖战斗中的效果是否被沉默。
	if card_data == null or contains(card_data):
		return false
	if horizontal_cards.is_empty():
		return can_accept_external_card_at(horizontal_index)
	if card_data.has_keyword(FORBID_STACKING_KEYWORD):
		return false
	if contains_stacking_forbidden_card():
		return false
	return can_accept_external_card_at(horizontal_index)


func get_action_source() -> CardData:
	# 最左卡提供小队行动类型与行动值。
	return horizontal_cards[0] if not horizontal_cards.is_empty() else null


func get_vitals_source() -> CardData:
	# 最右卡提供小队生命和护甲。
	return horizontal_cards[-1] if not horizontal_cards.is_empty() else null


func get_effect_source() -> CardData:
	# 最上层卡提供效果文字，也是新卡默认置顶的语义来源。
	return layer_cards[0] if not layer_cards.is_empty() else null


func insert_card(
	card_data: CardData,
	horizontal_index: int,
	layout: TwoCardLayout = TwoCardLayout.EXPANDED
) -> bool:
	# 成功插入同时更新水平顺序、层级顺序和双卡布局。
	if (
		card_data == null
		or contains(card_data)
		or not can_accept_card_at(card_data, horizontal_index)
	):
		return false

	var old_count := horizontal_cards.size()
	horizontal_cards.insert(
		clampi(horizontal_index, 0, horizontal_cards.size()),
		card_data
	)
	layer_cards.push_front(card_data)
	if old_count == 1:
		two_card_layout = layout
	elif horizontal_cards.size() == 3:
		two_card_layout = TwoCardLayout.EXPANDED
	_ensure_three_card_visibility()
	return true


func merge_compact_double_with_single(
	single_squad: SquadData,
	single_on_left: bool
) -> SquadData:
	# 整队合并保留双卡原本的水平顺序和完整层级顺序。目标单卡只按
	# 落点方向接到左/右侧，并始终放到层级末尾，不能夺走原顶牌的效果来源。
	if (
		get_card_count() != 2
		or two_card_layout != TwoCardLayout.COMPACT
		or get_visible_runes().size() != COMPACT_DOUBLE_UNIT_COUNT
		or single_squad == null
		or single_squad.get_card_count() != 1
		or contains_stacking_forbidden_card()
		or single_squad.contains_stacking_forbidden_card()
	):
		return null
	var single_card := single_squad.horizontal_cards[0]
	if single_card == null or contains(single_card):
		return null

	var result := duplicate_squad()
	if single_on_left:
		result.horizontal_cards.push_front(single_card)
	else:
		result.horizontal_cards.append(single_card)
	result.layer_cards.append(single_card)
	var single_owned_card := single_squad.get_owned_card(single_card)
	if single_owned_card != null:
		result.bind_owned_card(single_card, single_owned_card)
	result.two_card_layout = TwoCardLayout.EXPANDED
	result.merge_equipment_from(single_squad)
	result._normalize()
	return result if result.is_valid() else null


func remove_card(card_data: CardData) -> bool:
	# 三卡拆出后的双卡间距由被移除的水平位置决定，不能只看剩余数量。
	if not contains(card_data):
		return false

	var old_count := horizontal_cards.size()
	var removed_horizontal_index := horizontal_cards.find(card_data)
	horizontal_cards.erase(card_data)
	layer_cards.erase(card_data)
	_owned_cards_by_card.erase(card_data)
	if old_count == 3 and horizontal_cards.size() == 2:
		two_card_layout = (
			TwoCardLayout.EXPANDED
			if removed_horizontal_index == 1
			else TwoCardLayout.COMPACT
		)
	_normalize()
	return true


func move_card_horizontally(card_data: CardData, horizontal_index: int) -> bool:
	# 水平重排同时置顶，符合玩家拖动并重新放回小队的交互结果。
	var old_index := horizontal_cards.find(card_data)
	if old_index < 0:
		return false
	horizontal_cards.remove_at(old_index)
	horizontal_cards.insert(
		clampi(horizontal_index, 0, horizontal_cards.size()),
		card_data
	)
	bring_card_to_top(card_data)
	return true


func bring_card_to_top(card_data: CardData) -> bool:
	if not layer_cards.has(card_data):
		return false
	layer_cards.erase(card_data)
	layer_cards.push_front(card_data)
	_ensure_three_card_visibility()
	return true


func _normalize() -> void:
	# 修复工厂或删除后的两套顺序一致性；不改变合法卡牌的相对顺序。
	for index: int in range(layer_cards.size() - 1, -1, -1):
		if not horizontal_cards.has(layer_cards[index]):
			layer_cards.remove_at(index)
	for card_data: CardData in horizontal_cards:
		if not layer_cards.has(card_data):
			layer_cards.append(card_data)
	for mapped_card: Variant in _owned_cards_by_card.keys():
		if not horizontal_cards.has(mapped_card):
			_owned_cards_by_card.erase(mapped_card)
	if horizontal_cards.size() != 2:
		two_card_layout = TwoCardLayout.EXPANDED
	_ensure_three_card_visibility()


func _ensure_three_card_visibility() -> void:
	if horizontal_cards.size() != 3 or layer_cards.size() != 3:
		return
	var middle_card := horizontal_cards[1]
	# 三卡固定为 X=[0,30,60]。如果中卡位于最下层，而左右两卡都在
	# 它上方，两侧卡牌会合起来把中卡完整遮住。任意卡仍可成为最上层；
	# 只在侧边卡置顶时，把中卡放到第二层，确保三张卡都至少露出一段。
	if layer_cards[0] != middle_card and layer_cards[1] != middle_card:
		layer_cards.erase(middle_card)
		layer_cards.insert(1, middle_card)
