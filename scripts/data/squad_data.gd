class_name SquadData
extends Resource

## 小队的权威数据模型。
## horizontal_cards 决定左右位置，layer_cards 决定遮挡层级，
## two_card_layout 决定双卡间距；显示节点只能据此绘制，不能另存一套顺序。

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
	# 单卡进入战场时使用的最小合法小队工厂。
	var squad := SquadData.new()
	if card_data != null:
		squad.horizontal_cards.append(card_data)
		squad.layer_cards.append(card_data)
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
	return copy


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
	return true


func get_card_count() -> int:
	return horizontal_cards.size()


func contains(card_data: CardData) -> bool:
	return horizontal_cards.has(card_data)


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
	result.two_card_layout = TwoCardLayout.EXPANDED
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
