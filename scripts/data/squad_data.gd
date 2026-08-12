class_name SquadData
extends Resource

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

@export var horizontal_cards: Array[CardData] = [] # 小队从左到右的卡牌顺序
@export var layer_cards: Array[CardData] = [] # 从最上层到最下层保存，第一项提供卡牌效果
@export var two_card_layout: TwoCardLayout = TwoCardLayout.EXPANDED # 双卡使用紧密或展开吸附布局


static func from_card(card_data: CardData) -> SquadData:
	var squad := SquadData.new()
	if card_data != null:
		squad.horizontal_cards.append(card_data)
		squad.layer_cards.append(card_data)
	return squad


static func from_cards(
	cards: Array[CardData],
	layout: TwoCardLayout = TwoCardLayout.EXPANDED
) -> SquadData:
	var squad := SquadData.new()
	for card_data: CardData in cards:
		if card_data != null and not squad.horizontal_cards.has(card_data):
			squad.horizontal_cards.append(card_data)
			squad.layer_cards.append(card_data)
	squad.two_card_layout = layout
	squad._normalize()
	return squad


func duplicate_squad() -> SquadData:
	var copy := SquadData.new()
	copy.horizontal_cards.assign(horizontal_cards)
	copy.layer_cards.assign(layer_cards)
	copy.two_card_layout = two_card_layout
	return copy


func is_valid() -> bool:
	if horizontal_cards.is_empty() or horizontal_cards.size() > MAX_CARD_COUNT:
		return false
	if horizontal_cards.size() != layer_cards.size():
		return false
	for card_data: CardData in horizontal_cards:
		if card_data == null or horizontal_cards.count(card_data) != 1:
			return false
		if layer_cards.count(card_data) != 1:
			return false
	return true


func get_card_count() -> int:
	return horizontal_cards.size()


func contains(card_data: CardData) -> bool:
	return horizontal_cards.has(card_data)


func get_unit_count() -> int:
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


func get_action_source() -> CardData:
	return horizontal_cards[0] if not horizontal_cards.is_empty() else null


func get_vitals_source() -> CardData:
	return horizontal_cards[-1] if not horizontal_cards.is_empty() else null


func get_effect_source() -> CardData:
	return layer_cards[0] if not layer_cards.is_empty() else null


func insert_card(
	card_data: CardData,
	horizontal_index: int,
	layout: TwoCardLayout = TwoCardLayout.EXPANDED
) -> bool:
	if (
		card_data == null
		or contains(card_data)
		or horizontal_cards.size() >= MAX_CARD_COUNT
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


func remove_card(card_data: CardData) -> bool:
	if not contains(card_data):
		return false

	var old_count := horizontal_cards.size()
	var removed_horizontal_index := horizontal_cards.find(card_data)
	horizontal_cards.erase(card_data)
	layer_cards.erase(card_data)
	if old_count == 3 and horizontal_cards.size() == 2:
		two_card_layout = (
			TwoCardLayout.EXPANDED
			if removed_horizontal_index == 1
			else TwoCardLayout.COMPACT
		)
	_normalize()
	return true


func move_card_horizontally(card_data: CardData, horizontal_index: int) -> bool:
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
	for index: int in range(layer_cards.size() - 1, -1, -1):
		if not horizontal_cards.has(layer_cards[index]):
			layer_cards.remove_at(index)
	for card_data: CardData in horizontal_cards:
		if not layer_cards.has(card_data):
			layer_cards.append(card_data)
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
