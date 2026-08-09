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
	match horizontal_cards.size():
		1:
			counts.assign([3])
		2:
			counts.assign(
				[1, 3]
				if two_card_layout == TwoCardLayout.COMPACT
				else [2, 3]
			)
		3:
			# 三卡固定 X=[0,30,60]，最上层卡露出完整三个符文，
			# 另外两张各露一个；因此可见数量会随层级最上卡的位置变化。
			counts.assign([1, 1, 1])
			var top_index := horizontal_cards.find(get_effect_source())
			if top_index >= 0:
				counts[top_index] = 3
	return counts


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
	horizontal_cards.erase(card_data)
	layer_cards.erase(card_data)
	if old_count == 3 and horizontal_cards.size() == 2:
		two_card_layout = TwoCardLayout.EXPANDED
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
