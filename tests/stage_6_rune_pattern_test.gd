extends SceneTree

## 阶段 6 的可见符文、牌型和同步流光集成回归脚本。
##
## 前半使用纯数据验证遮挡槽位与规则优先级，后半实例化 Main 验证显示、
## 真实事务刷新、预览取消不污染数据，以及所有真实卡共享流光时间轴。

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/ui/CardView.tscn")

var _failure_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_test_single_and_double_visible_runes()
	_test_three_card_visible_runes()
	_test_all_pattern_rules_and_priority()
	_test_separated_elements_do_not_merge()
	_test_straight_rotations_and_reversals()

	if _failure_count == 0:
		print("Stage 6 integration checks passed.")
	else:
		push_error("Stage 6 integration checks failed: %d" % _failure_count)
	quit(_failure_count)


# --- 可见符文几何与纯牌型规则 ---
func _test_single_and_double_visible_runes() -> void:
	var cards := _make_geometry_cards()
	var left := cards[0]
	var right := cards[1]
	var single := SquadData.from_card(left)
	_expect_slots(single, ["0:0", "0:1", "0:2"], "单卡三个槽位按卡面顺序读取")
	_expect(
		single.get_visible_runes() == left.runes,
		"单卡可见符文序列与卡面三个槽位完全一致"
	)

	var compact := SquadData.from_cards(
		_typed_cards([left, right]),
		SquadData.TwoCardLayout.COMPACT
	)
	_expect_slots(
		compact,
		["0:0", "0:1", "0:2", "1:2"],
		"紧密双卡左卡置顶时只读取右卡最右槽"
	)
	_expect(
		compact.get_visible_runes() == _runes([
			CardData.ElementType.FIRE,
			CardData.ElementType.WATER,
			CardData.ElementType.WOOD,
			CardData.ElementType.FIRE,
		]),
		"紧密双卡左卡置顶的元素顺序按画面从左到右"
	)
	compact.bring_card_to_top(right)
	_expect_slots(
		compact,
		["0:0", "1:0", "1:1", "1:2"],
		"紧密双卡右卡置顶时只读取左卡最左槽"
	)

	var expanded := SquadData.from_cards(
		_typed_cards([left, right]),
		SquadData.TwoCardLayout.EXPANDED
	)
	_expect_slots(
		expanded,
		["0:0", "0:1", "0:2", "1:1", "1:2"],
		"展开双卡左卡置顶时读取左 3 + 右 2"
	)
	expanded.bring_card_to_top(right)
	_expect_slots(
		expanded,
		["0:0", "0:1", "1:0", "1:1", "1:2"],
		"展开双卡右卡置顶时读取左 2 + 右 3"
	)


func _test_three_card_visible_runes() -> void:
	var cards := _make_geometry_cards()
	var left := cards[0]
	var middle := cards[1]
	var right := cards[2]
	var squad := SquadData.from_cards(_typed_cards([left, middle, right]))

	_expect_slots(
		squad,
		["0:0", "0:1", "0:2", "1:2", "2:2"],
		"三卡左卡置顶时读取左 3 + 中右各最右槽"
	)
	squad.bring_card_to_top(middle)
	_expect_slots(
		squad,
		["0:0", "1:0", "1:1", "1:2", "2:2"],
		"三卡中卡置顶时读取左最左 + 中 3 + 右最右"
	)
	squad.bring_card_to_top(right)
	_expect_slots(
		squad,
		["0:0", "1:0", "2:0", "2:1", "2:2"],
		"三卡右卡置顶时读取左中各最左槽 + 右 3"
	)
	_expect(
		squad.get_visible_rune_counts() == [1, 1, 3]
		and squad.get_visible_runes().size() == 5,
		"三卡被遮挡槽位不进入序列且可见总数保持五枚"
	)


func _test_all_pattern_rules_and_priority() -> void:
	var cases: Array[Dictionary] = [
		{
			"name": "五条",
			"type": RunePatternResult.PatternType.FIVE_OF_A_KIND,
			"runes": _runes([0, 0, 0, 0, 0]),
			"indices": [0, 1, 2, 3, 4],
		},
		{
			"name": "四条",
			"type": RunePatternResult.PatternType.FOUR_OF_A_KIND,
			"runes": _runes([0, 0, 0, 0, 1]),
			"indices": [0, 1, 2, 3],
		},
		{
			"name": "葫芦",
			"type": RunePatternResult.PatternType.FULL_HOUSE,
			"runes": _runes([0, 0, 0, 1, 1]),
			"indices": [0, 1, 2, 3, 4],
		},
		{
			"name": "同花两对",
			"type": RunePatternResult.PatternType.SAME_ELEMENT_TWO_PAIR,
			"runes": _runes([0, 0, 1, 0, 0]),
			"indices": [0, 1, 3, 4],
		},
		{
			"name": "两对",
			"type": RunePatternResult.PatternType.TWO_PAIR,
			"runes": _runes([0, 0, 1, 1, 2]),
			"indices": [0, 1, 2, 3],
		},
		{
			"name": "三条",
			"type": RunePatternResult.PatternType.THREE_OF_A_KIND,
			"runes": _runes([0, 0, 0, 1, 2]),
			"indices": [0, 1, 2],
		},
		{
			"name": "对子",
			"type": RunePatternResult.PatternType.PAIR,
			"runes": _runes([0, 0, 1, 2, 3]),
			"indices": [0, 1],
		},
		{
			"name": "混乱",
			"type": RunePatternResult.PatternType.CHAOS,
			"runes": _runes([0, 1, 2, 3, 4]),
			"indices": [],
		},
		{
			"name": "顺子",
			"type": RunePatternResult.PatternType.STRAIGHT,
			"runes": _runes([0, 3, 4, 1, 2]),
			"indices": [0, 1, 2, 3, 4],
		},
	]
	for test_case: Dictionary in cases:
		var input_runes := test_case["runes"] as Array[CardData.ElementType]
		var result := RunePatternRules.identify(input_runes)
		_expect(
			result.pattern_type == int(test_case["type"])
			and result.get_pattern_name() == str(test_case["name"]),
			"%s识别正确" % test_case["name"]
		)
		_expect(
			result.visible_runes == input_runes,
			"%s结果保留原始从左到右序列" % test_case["name"]
		)
		_expect(
			result.participating_indices == test_case["indices"],
			"%s结果保存实际参与牌型的符文位置" % test_case["name"]
		)
	_expect(
		RunePatternRules.identify(_runes([0, 0, 0, 1, 1])).pattern_type
		== RunePatternResult.PatternType.FULL_HOUSE,
		"3+2 优先识别为葫芦而不是三条或对子"
	)
	_expect(
		RunePatternRules.identify(_runes([0, 0, 1, 1, 2])).pattern_type
		== RunePatternResult.PatternType.TWO_PAIR,
		"2+2+1 优先识别为两对而不是对子"
	)
	var four_result := RunePatternRules.identify(_runes([0, 0, 0, 0, 1]))
	_expect(
		four_result.get_element_count(CardData.ElementType.FIRE) == 4
		and four_result.get_element_count(CardData.ElementType.WATER) == 1,
		"独立牌型结果保存每种元素的计数"
	)


func _test_separated_elements_do_not_merge() -> void:
	var cases: Array[Dictionary] = [
		{
			"runes": _runes([0, 0, 1, 0, 1]),
			"type": RunePatternResult.PatternType.PAIR,
			"indices": [0, 1],
			"message": "火火水火水只取前两个连续火组成对子",
		},
		{
			"runes": _runes([0, 0, 1, 0, 0]),
			"type": RunePatternResult.PatternType.SAME_ELEMENT_TWO_PAIR,
			"indices": [0, 1, 3, 4],
			"message": "火火水火火识别为同花两对",
		},
		{
			"runes": _runes([0, 0, 1, 2, 0]),
			"type": RunePatternResult.PatternType.PAIR,
			"indices": [0, 1],
			"message": "火火水木火不能跨越其他元素组成三条",
		},
		{
			"runes": _runes([0, 0, 2, 1, 1]),
			"type": RunePatternResult.PatternType.TWO_PAIR,
			"indices": [0, 1, 3, 4],
			"message": "火火木水水保留两个不同元素的连续对子",
		},
		{
			"runes": _runes([0, 0, 0, 1, 0]),
			"type": RunePatternResult.PatternType.THREE_OF_A_KIND,
			"indices": [0, 1, 2],
			"message": "AAABA 只按连续前三个 A 识别三条",
		},
	]
	for test_case: Dictionary in cases:
		var result := RunePatternRules.identify(
			test_case["runes"] as Array[CardData.ElementType]
		)
		_expect(
			result.pattern_type == int(test_case["type"])
			and result.participating_indices == test_case["indices"],
			str(test_case["message"])
		)


func _test_straight_rotations_and_reversals() -> void:
	var cycle := _runes([0, 3, 4, 1, 2])
	for start_index: int in cycle.size():
		var forward: Array[CardData.ElementType] = []
		var reverse: Array[CardData.ElementType] = []
		for step: int in cycle.size():
			forward.append(cycle[(start_index + step) % cycle.size()])
			reverse.append(
				cycle[(start_index - step + cycle.size()) % cycle.size()]
			)
		_expect(
			RunePatternRules.identify(forward).pattern_type
			== RunePatternResult.PatternType.STRAIGHT,
			"顺子正向循环起点 %d 识别正确" % start_index
		)
		_expect(
			RunePatternRules.identify(reverse).pattern_type
			== RunePatternResult.PatternType.STRAIGHT,
			"顺子反向循环起点 %d 识别正确" % start_index
		)
	_expect(
		RunePatternRules.identify(_runes([0, 3, 4, 1])).pattern_type
		== RunePatternResult.PatternType.CHAOS,
		"只有四枚符文时不能识别为顺子"
	)
	_expect(
		RunePatternRules.identify(_runes([0, 1, 2, 3, 4])).pattern_type
		== RunePatternResult.PatternType.CHAOS,
		"五种元素齐全但顺序不连续时仍为混乱"
	)
	_expect(
		RunePatternRules.identify(_runes([0, 3, 4, 1, 1])).pattern_type
		== RunePatternResult.PatternType.PAIR,
		"存在重复元素时不进入顺子并继续使用原牌型优先级"
	)


# --- 真实场景中的牌型显示、流光与事务刷新 ---
func _test_pattern_display_and_dimensions() -> void:
	var main: Variant = await _create_main()
	var first_collection_slot: Node = main.get_node("%CollectionCardRow").get_child(0)
	var first_collection_card_view := first_collection_slot.get_child(0) as CardView
	var hand_uses_only_static_runes := (
		first_collection_card_view.get_active_rune_animation_count() == 0
	)
	for hand_slot_index: int in 3:
		hand_uses_only_static_runes = (
			hand_uses_only_static_runes
			and not first_collection_card_view.is_rune_using_active_animation(
				hand_slot_index
			)
		)
	_expect(hand_uses_only_static_runes, "收藏符文始终使用新版静态纹理")
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var cards := _make_geometry_cards()
	var single := front_row.add_squad(SquadData.from_card(cards[0]), 0)
	var compact := front_row.add_squad(
		SquadData.from_cards(
			_typed_cards([cards[1], cards[2]]),
			SquadData.TwoCardLayout.COMPACT
		),
		1
	)
	var expanded := front_row.add_squad(
		SquadData.from_cards(
			_typed_cards([cards[3], cards[4]]),
			SquadData.TwoCardLayout.EXPANDED
		),
		2
	)
	var triple_cards := _make_geometry_cards()
	var triple := front_row.add_squad(
		SquadData.from_cards(_typed_cards([
			triple_cards[0], triple_cards[1], triple_cards[2]
		])),
		3
	)
	await process_frame
	await process_frame

	_expect(
		single.size == Vector2(99, 136)
		and compact.size == Vector2(129, 136)
		and expanded.size == Vector2(159, 136)
		and triple.size == Vector2(159, 136),
		"牌型标签不改变单卡、双卡或三卡小队真实尺寸"
	)
	_expect(
		front_row.get_used_unit_count() == 17
		and front_row.get_content_width() == 600,
		"牌型标签不改变战场单元容量或小队间距宽度"
	)
	for slot: BoardSlot in [single, compact, expanded, triple]:
		var result := slot.get_displayed_pattern_result()
		_expect(
			result != null
			and slot.pattern_label.text == result.get_pattern_name()
			and slot.pattern_label.visible,
			"每个真实小队显示与规则结果一致的紧凑牌型名称"
		)
		_expect(
			slot.pattern_label.custom_minimum_size == SquadView.PATTERN_LABEL_SIZE
			and slot.pattern_label.position.y == SquadView.PATTERN_LABEL_TOP,
			"牌型名称使用固定覆盖标签，不参与小队布局尺寸"
		)
		_expect_highlights_match_result(slot, false, "真实牌型只激活参与槽位的流光")
	await _dispose_main(main)


func _test_global_flow_synchronization() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var first_card := _make_pair_card(
		&"flow_sync_fire",
		CardData.ElementType.FIRE,
		CardData.ElementType.WATER
	)
	var second_card := _make_pair_card(
		&"flow_sync_water",
		CardData.ElementType.WATER,
		CardData.ElementType.WOOD
	)
	_expect(
		not CardView.has_active_rune_flow_started(),
		"第一张真实卡进入战场前，全局流光时钟保持未启动"
	)
	var preview_view := CARD_VIEW_SCENE.instantiate() as CardView
	root.add_child(preview_view)
	preview_view.set_card_data(first_card)
	var preview_indices: Array[int] = [0, 1]
	preview_view.set_rune_pattern_highlights(preview_indices, true)
	await process_frame
	_expect(
		not CardView.has_active_rune_flow_started(),
		"拖拽牌型预览不会提前启动真实全局特效时钟"
	)
	preview_view.queue_free()
	await process_frame

	var first_slot := front_row.add_squad(SquadData.from_card(first_card), 0)
	var first_view := first_slot.get_primary_card_view()
	var first_visible_flow_frame := first_view.get_active_rune_animation_frame()
	await process_frame
	await process_frame
	_expect(
		CardView.has_active_rune_flow_started()
		and not first_view.is_rune_waiting_for_next_flow(0)
		and first_view.is_rune_using_active_animation(0)
		and first_view.is_rune_using_active_animation(1),
		"第一张真实卡成功落场后立即启动流光特效"
	)
	var start_phase := first_view._get_active_rune_start_phase_seconds()
	_expect(
		is_equal_approx(
			start_phase,
			fposmod(
				CardView.ACTIVE_RUNE_START_PHASE_SECONDS,
				CardView.ACTIVE_RUNE_CYCLE_SECONDS
			)
		),
		"移除呼吸灯后仍保留用户确认过的首次流光起播画面"
	)
	_expect(
		first_visible_flow_frame
		== first_view._get_flow_frame_at_time(start_phase),
		"流光从人工确认并固定下来的动画帧开始"
	)

	await create_timer(0.15).timeout
	var second_slot := front_row.add_squad(SquadData.from_card(second_card), 1)
	await process_frame
	var second_view := second_slot.get_primary_card_view()
	_expect(
		second_view.is_rune_waiting_for_next_flow(0)
		and not second_view.is_rune_using_active_animation(0)
		and first_view.is_rune_using_active_animation(0),
		"首轮开始后再加入的真实符文等待下一轮共同起点"
	)

	await create_timer(CardView.ACTIVE_RUNE_CYCLE_SECONDS + 0.05).timeout
	await process_frame
	_expect(
		first_view.is_rune_using_active_animation(0)
		and first_view.is_rune_using_active_animation(1)
		and second_view.is_rune_using_active_animation(0)
		and second_view.is_rune_using_active_animation(1)
		and first_view.get_active_rune_animation_frame()
		== second_view.get_active_rune_animation_frame(),
		"已有牌型符文在同一全局帧开始并保持同步"
	)
	_expect(
		first_view.get_node_or_null("%RuneGlowLayer") == null
		and second_view.get_node_or_null("%RuneGlowLayer") == null,
		"真实牌型保留流光，但不再创建任何符文光晕覆盖层"
	)
	_expect(
		first_view._get_flow_frame_at_time(0.0) == 0
		and first_view._get_flow_frame_at_time(
			CardView.ACTIVE_RUNE_CYCLE_SECONDS - 0.001
		) == CardView.ACTIVE_RUNE_FRAME_COUNT - 1,
		"流光全部帧按统一循环时长等比播放"
	)

	var third_card := _make_pair_card(
		&"flow_sync_wood",
		CardData.ElementType.WOOD,
		CardData.ElementType.LIGHT
	)
	var third_slot := front_row.add_squad(SquadData.from_card(third_card), 2)
	await process_frame
	var third_view := third_slot.get_primary_card_view()
	_expect(
		third_view.is_rune_waiting_for_next_flow(0)
		and not third_view.is_rune_using_active_animation(0)
		and first_view.is_rune_using_active_animation(0),
		"其他卡牌播放期间刚上场的卡仍显示静态符文"
	)

	await create_timer(CardView.ACTIVE_RUNE_CYCLE_SECONDS + 0.05).timeout
	await process_frame
	_expect(
		third_view.is_rune_using_active_animation(0)
		and third_view.is_rune_using_active_animation(1)
		and not third_view.is_rune_using_active_animation(2)
		and first_view.get_active_rune_animation_frame()
		== second_view.get_active_rune_animation_frame()
		and second_view.get_active_rune_animation_frame()
		== third_view.get_active_rune_animation_frame(),
		"刚上场卡在下一轮起点加入并与已有卡保持同帧"
	)

	var inactive_card := CardData.new()
	inactive_card.id = &"flow_sync_inactive"
	inactive_card.display_name = "无牌型特效测试卡"
	inactive_card.runes.assign(_runes([
		CardData.ElementType.FIRE,
		CardData.ElementType.WATER,
		CardData.ElementType.WOOD,
	]))
	var inactive_slot := front_row.add_squad(
		SquadData.from_card(inactive_card),
		3
	)
	await process_frame
	_expect(
		inactive_slot.get_primary_card_view().get_highlighted_rune_indices().is_empty(),
		"场上可保留没有牌型特效的真实卡牌"
	)
	front_row.remove_squad_slot(first_slot)
	front_row.remove_squad_slot(second_slot)
	front_row.remove_squad_slot(third_slot)
	await process_frame
	await process_frame
	_expect(
		front_row.get_card_count() == 1
		and not CardView.has_active_rune_flow_started(),
		"场上只剩无特效卡牌时重置全局特效计时器"
	)

	var restarted_card := _make_pair_card(
		&"flow_sync_restarted",
		CardData.ElementType.DARK,
		CardData.ElementType.LIGHT
	)
	var restarted_slot := front_row.add_squad(
		SquadData.from_card(restarted_card),
		1
	)
	var restarted_view := restarted_slot.get_primary_card_view()
	var restarted_first_frame := restarted_view.get_active_rune_animation_frame()
	_expect(
		CardView.has_active_rune_flow_started()
		and restarted_view.is_rune_using_active_animation(0)
		and restarted_first_frame
		== restarted_view._get_flow_frame_at_time(
			restarted_view._get_active_rune_start_phase_seconds()
		),
		"无特效阵容后加入首张特效卡会建立全新计时器并立即起播"
	)
	await _dispose_main(main)


func _test_updates_after_real_transactions() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var original_cards: Array[CardData] = main.collection_cards.duplicate()
	var first := original_cards[0]
	var second := original_cards[1]
	var third := original_cards[2]
	_expect(
		main._transfer_card(_collection_drag(first), &"board", front_row, 0),
		"建立阶段 6 单卡真实小队"
	)
	var slot := front_row.get_squads()[0]
	await process_frame
	_expect_label_matches_data(slot, "单卡加入后牌型立即刷新")

	var joined_double := slot.get_squad_data().duplicate_squad()
	joined_double.insert_card(second, 1, SquadData.TwoCardLayout.COMPACT)
	var join_double_intent := _merge_intent(slot, joined_double, 1)
	_expect(
		main._transfer_drop_intent(
			_collection_drag(second, join_double_intent),
			front_row
		),
		"第二张卡加入真实小队"
	)
	await process_frame
	_expect_label_matches_data(slot, "双卡加入后牌型立即刷新")

	var joined_triple := slot.get_squad_data().duplicate_squad()
	joined_triple.insert_card(third, 2, SquadData.TwoCardLayout.EXPANDED)
	var join_triple_intent := _merge_intent(slot, joined_triple, 2)
	_expect(
		main._transfer_drop_intent(
			_collection_drag(third, join_triple_intent),
			front_row
		),
		"第三张卡加入真实小队"
	)
	await process_frame
	_expect_label_matches_data(slot, "三卡加入后牌型立即刷新")

	var reordered := slot.get_squad_data().duplicate_squad()
	reordered.move_card_horizontally(third, 0)
	var reorder_intent := _merge_intent(slot, reordered, 0)
	_expect(
		main._transfer_drop_intent(
			_board_drag(front_row, slot, third, reorder_intent),
			front_row
		),
		"队内水平重排通过真实事务提交"
	)
	await process_frame
	_expect(
		slot.get_squad_data().horizontal_cards[0] == third,
		"水平重排更新真实水平顺序"
	)
	_expect_label_matches_data(slot, "水平重排和置顶后牌型立即刷新")

	var removed_card := slot.get_squad_data().horizontal_cards[1]
	_expect(
		main._transfer_card(
			_board_drag(front_row, slot, removed_card),
			&"collection",
			null,
			main.collection_cards.size()
		),
		"从三卡小队拆出一张卡回收藏"
	)
	await process_frame
	_expect(
		slot.get_squad_data().get_card_count() == 2,
		"拆出后原小队保留两张卡"
	)
	_expect_label_matches_data(slot, "拆出后牌型立即刷新")
	await _dispose_main(main)


# --- 假设预览、取消恢复与阶段锁定 ---
func _test_preview_cancel_invalid_and_phase_lock() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var cards := _make_geometry_cards()
	var real_squad := SquadData.from_cards(
		_typed_cards([cards[0], cards[1]]),
		SquadData.TwoCardLayout.EXPANDED
	)
	var slot := front_row.add_squad(real_squad, 0)
	front_row.add_squad(SquadData.from_card(cards[4]), 1)
	await process_frame
	await process_frame
	var before_row_slots: Array[BoardSlot] = front_row.get_squads().duplicate()
	var before_horizontal: Array[CardData] = real_squad.horizontal_cards.duplicate()
	var before_layers: Array[CardData] = real_squad.layer_cards.duplicate()
	var before_runes := real_squad.get_visible_runes()
	var before_pattern := real_squad.get_rune_pattern_result().pattern_type
	var before_label := slot.pattern_label.text

	# 来源卡被临时隐藏只改变拖拽画面，不得把假设结果伪装成真实牌型。
	slot.set_drag_hidden_card(cards[0])
	_expect(
		slot.pattern_label.text == before_label
		and slot.get_displayed_pattern_result().pattern_type == before_pattern,
		"拖拽来源临时隐藏时仍显示真实牌型"
	)
	slot.clear_drag_hidden_card()

	var preview_squad := real_squad.duplicate_squad()
	preview_squad.insert_card(cards[2], 1)
	var preview_intent := _merge_intent(slot, preview_squad, 1)
	front_row._show_intent_preview(preview_intent)
	var preview_slot := front_row.get("_preview_slot") as BoardSlot
	_expect(
		is_instance_valid(preview_slot)
		and preview_slot.pattern_label.text.begins_with("预览·")
		and preview_slot.get_displayed_pattern_result().visible_runes
		== preview_squad.get_visible_runes(),
		"目标虚影清楚标记预览牌型并使用假设可见序列"
	)
	_expect_highlights_match_result(
		preview_slot,
		true,
		"预览牌型流光使用假设结果并标记为低透明度预览"
	)
	_expect_real_unchanged(
		real_squad,
		before_horizontal,
		before_layers,
		before_runes,
		before_pattern,
		"显示预览时真实三套顺序和牌型不变"
	)
	_expect(front_row.get_squads() == before_row_slots, "显示预览时棋盘小队顺序不变")
	front_row.clear_drop_preview()
	_expect_real_unchanged(
		real_squad,
		before_horizontal,
		before_layers,
		before_runes,
		before_pattern,
		"取消预览后真实三套顺序和牌型不变"
	)
	_expect(front_row.get_squads() == before_row_slots, "取消预览后棋盘小队顺序不变")
	_expect(slot.pattern_label.text == before_label, "取消预览后真实牌型标签保持原值")

	var invalid_intent := preview_intent.duplicate()
	invalid_intent["result_squad"] = SquadData.new()
	_expect(
		not main._transfer_drop_intent(
			_collection_drag(cards[3], invalid_intent),
			front_row
		),
		"无效放置结果被提交层拒绝"
	)
	_expect_real_unchanged(
		real_squad,
		before_horizontal,
		before_layers,
		before_runes,
		before_pattern,
		"无效放置不污染真实牌型和三套顺序"
	)
	_expect(front_row.get_squads() == before_row_slots, "无效放置不污染棋盘小队顺序")

	var phase_button := main.get_node("%StartBattleButton") as Button
	phase_button.emit_signal("pressed")
	_expect(
		main.current_phase == 1
		and not front_row.can_receive_card_drag(_collection_drag(cards[3]))
		and not front_row.preview_card_drop(Vector2(100, 68), _collection_drag(cards[3]))
		and slot.pattern_label.text == before_label,
		"战斗阶段牌型显示不能绕过阶段 5 的调整禁用"
	)
	phase_button.emit_signal("pressed")
	_expect(
		main.current_phase == 2
		and not front_row.can_receive_card_drag(_collection_drag(cards[3]))
		and slot.pattern_label.text == before_label,
		"结算阶段同样保持牌型只读并禁止调整"
	)
	await _dispose_main(main)


func _test_preview_flow_without_glow() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var target := CardData.new()
	target.id = &"preview_flow_target"
	target.display_name = "预览流光目标"
	target.runes.assign(_runes([
		CardData.ElementType.LIGHT,
		CardData.ElementType.FIRE,
		CardData.ElementType.WATER,
	]))
	var dragged := CardData.new()
	dragged.id = &"preview_flow_dragged"
	dragged.display_name = "预览流光拖动卡"
	dragged.runes.assign(_runes([
		CardData.ElementType.FIRE,
		CardData.ElementType.DARK,
		CardData.ElementType.WOOD,
	]))
	var target_slot := front_row.add_squad(SquadData.from_card(target), 0)
	await process_frame
	var merged := SquadData.from_cards(
		_typed_cards([target, dragged]),
		SquadData.TwoCardLayout.EXPANDED
	)
	merged.bring_card_to_top(dragged)
	var merge_preview := _merge_intent(target_slot, merged, 1)
	var drag_data := _collection_drag(dragged)
	var drag_visual := CardView.create_drag_visual(drag_data)
	main.add_child(drag_visual)
	drag_data["drag_visual"] = drag_visual
	front_row._show_intent_preview(merge_preview, drag_data)
	var preview_slot := front_row.get("_preview_slot") as BoardSlot
	var target_view := preview_slot.get_card_view(target)
	var dragged_view := preview_slot.get_card_view(dragged)
	var carried_view := drag_visual.get_source_card_view() as CardView
	var target_active_icon := (
		(target_view.get("_active_rune_icons") as Dictionary)[1]
		as TextureRect
	)
	var ghost_active_icon := (
		(dragged_view.get("_active_rune_icons") as Dictionary)[0]
		as TextureRect
	)
	var carried_active_icon := (
		(carried_view.get("_active_rune_icons") as Dictionary)[0]
		as TextureRect
	)
	_expect(
		target_view.get_highlighted_rune_indices() == [1]
		and target_view.is_rune_using_active_animation(1)
		and is_equal_approx(target_active_icon.modulate.a, 1.0),
		"场上原有目标卡即使由预览节点绘制，流光也保持完整颜色"
	)
	_expect(
		dragged_view.get_highlighted_rune_indices() == [0]
		and dragged_view.get_active_rune_animation_count() == 1
		and dragged_view.is_rune_using_active_animation(0)
		and dragged_view.is_rune_highlight_preview()
		and is_equal_approx(
			ghost_active_icon.modulate.a,
			CardView.PREVIEW_ACTIVE_RUNE_ALPHA
		),
		"新增的结果虚影卡继续以预览透明度播放参与槽位流光"
	)
	_expect(
		carried_view != null
		and carried_view.get_highlighted_rune_indices() == [0]
		and carried_view.get_active_rune_animation_count() == 1
		and carried_view.is_rune_using_active_animation(0)
		and carried_view.is_rune_highlight_preview()
		and is_equal_approx(carried_active_icon.modulate.a, 1.0),
		"手中拖拽实体卡同步参与槽位，但流光保持完整颜色"
	)
	_expect(
		target_view.get_node_or_null("%RuneGlowLayer") == null
		and dragged_view.get_node_or_null("%RuneGlowLayer") == null
		and carried_view.get_node_or_null("%RuneGlowLayer") == null,
		"场上实体卡、预览虚影与手中实体卡都不再包含光晕覆盖层"
	)

	var standalone_preview := {
		"operation": &"new_squad",
		"squad_index": 1,
		"card_index": 0,
		"result_squad": SquadData.from_card(dragged),
	}
	front_row._show_intent_preview(standalone_preview, drag_data)
	preview_slot = front_row.get("_preview_slot") as BoardSlot
	dragged_view = preview_slot.get_card_view(dragged)
	_expect(
		dragged_view.get_highlighted_rune_indices().is_empty()
		and dragged_view.get_active_rune_animation_count() == 0
		and carried_view.get_highlighted_rune_indices().is_empty()
		and carried_view.get_active_rune_animation_count() == 0,
		"切换到无牌型的单独放置预览时，虚影与手中卡立即恢复静态符文"
	)

	front_row._show_intent_preview(merge_preview, drag_data)
	front_row.clear_drop_preview()
	_expect(
		carried_view.get_highlighted_rune_indices().is_empty()
		and carried_view.get_active_rune_animation_count() == 0,
		"取消预览后手中实体卡立即清除预览流光"
	)

	main.collection_cards.append(dragged)
	var committed_drag := _collection_drag(dragged, merge_preview)
	_expect(
		main._transfer_drop_intent(committed_drag, front_row),
		"删除光晕状态迁移后仍可正常确认牌型放置"
	)
	var final_target_view := target_slot.get_card_view(target)
	var final_dragged_view := target_slot.get_card_view(dragged)
	_expect(
		final_target_view.get_highlighted_rune_indices() == [1]
		and final_dragged_view.get_highlighted_rune_indices() == [0]
		and final_target_view.get_active_rune_animation_count() == 1
		and final_dragged_view.get_active_rune_animation_count() == 1
		and not final_target_view.is_rune_highlight_preview()
		and not final_dragged_view.is_rune_highlight_preview(),
		"确认放置后参与槽位继续切换为真实流光"
	)
	await _dispose_main(main)


# --- 断言、测试数据与拖拽字典辅助函数 ---
func _expect_slots(squad: SquadData, expected: Array, message: String) -> void:
	var actual: Array[String] = []
	for slot: Dictionary in squad.get_visible_rune_slots():
		actual.append("%d:%d" % [slot["card_index"], slot["rune_index"]])
	_expect(actual == expected, message)


func _expect_label_matches_data(slot: BoardSlot, message: String) -> void:
	var expected := slot.get_squad_data().get_rune_pattern_result()
	_expect(
		slot.pattern_label.text == expected.get_pattern_name()
		and slot.get_displayed_pattern_result().visible_runes
		== expected.visible_runes,
		message
	)


func _expect_highlights_match_result(
	slot: BoardSlot, expected_preview: bool, message: String
) -> void:
	var data := slot.get_display_data()
	var result := slot.get_displayed_pattern_result()
	var expected_by_card: Dictionary = {}
	var visible_slots := data.get_visible_rune_slots()
	for visible_index: int in result.participating_indices:
		var visible_slot := visible_slots[visible_index]
		var card := visible_slot["card"] as CardData
		if not expected_by_card.has(card):
			expected_by_card[card] = []
		(expected_by_card[card] as Array).append(int(visible_slot["rune_index"]))

	var matches := true
	for card: CardData in data.horizontal_cards:
		var expected_indices: Array[int] = []
		expected_indices.assign(expected_by_card.get(card, []))
		var card_view := slot.get_card_view(card)
		matches = (
			matches
			and card_view != null
			and card_view.get_highlighted_rune_indices() == expected_indices
			and card_view.get_active_rune_animation_count()
			== expected_indices.size()
			and card_view.is_rune_highlight_preview() == expected_preview
			and card_view.get_node_or_null("%RuneGlowLayer") == null
		)
		for slot_index: int in card.runes.size():
			matches = (
				matches
				and card_view.is_rune_scheduled_for_active_animation(
					slot_index
				)
				== expected_indices.has(slot_index)
			)
			if expected_indices.has(slot_index):
				matches = (
					matches
					and card_view.is_rune_waiting_for_next_flow(
						slot_index
					) != expected_preview
				)
	_expect(matches, message)


func _expect_real_unchanged(
	squad: SquadData,
	horizontal: Array[CardData],
	layers: Array[CardData],
	runes: Array[CardData.ElementType],
	pattern_type: RunePatternResult.PatternType,
	message: String
) -> void:
	_expect(
		squad.horizontal_cards == horizontal
		and squad.layer_cards == layers
		and squad.get_visible_runes() == runes
		and squad.get_rune_pattern_result().pattern_type == pattern_type,
		message
	)


func _merge_intent(
	target_slot: BoardSlot,
	result_squad: SquadData,
	card_index: int
) -> Dictionary:
	return {
		"operation": &"merge_card",
		"squad_index": 0,
		"card_index": card_index,
		"two_card_layout": result_squad.two_card_layout,
		"target_slot": target_slot,
		"result_squad": result_squad,
	}


func _make_geometry_cards() -> Array[CardData]:
	var rune_sets: Array[Array] = [
		[0, 1, 2],
		[3, 4, 0],
		[1, 2, 3],
		[4, 0, 1],
		[2, 3, 4],
	]
	var cards: Array[CardData] = []
	for index: int in rune_sets.size():
		var card := CardData.new()
		card.id = StringName("stage_6_%d" % index)
		card.display_name = "阶段六测试卡%d" % index
		card.runes.assign(_runes(rune_sets[index]))
		cards.append(card)
	return cards


func _make_pair_card(
	id: StringName,
	pair_element: CardData.ElementType,
	other_element: CardData.ElementType
) -> CardData:
	var card := CardData.new()
	card.id = id
	card.display_name = "流光同步测试卡"
	card.runes.assign(_runes([pair_element, pair_element, other_element]))
	return card


func _runes(values: Array) -> Array[CardData.ElementType]:
	var runes: Array[CardData.ElementType] = []
	for value: Variant in values:
		runes.append(int(value) as CardData.ElementType)
	return runes


func _typed_cards(values: Array) -> Array[CardData]:
	var cards: Array[CardData] = []
	for value: Variant in values:
		cards.append(value as CardData)
	return cards


func _collection_drag(card_data: CardData, intent: Dictionary = {}) -> Dictionary:
	var data := {
		"kind": &"card",
		"card_data": card_data,
		"source_type": &"collection",
		"source_row": null,
		"source_slot": null,
	}
	if not intent.is_empty():
		data["drop_intent"] = intent
	return data


func _board_drag(
	row: BattlefieldRow,
	slot: BoardSlot,
	card_data: CardData,
	intent: Dictionary = {}
) -> Dictionary:
	var data := {
		"kind": &"card",
		"card_data": card_data,
		"source_type": &"board",
		"source_row": row,
		"source_slot": slot,
		"squad_data": slot.get_squad_data(),
	}
	if not intent.is_empty():
		data["drop_intent"] = intent
	return data


func _create_main() -> Variant:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	return main


func _dispose_main(main: Variant) -> void:
	main.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failure_count += 1
	push_error("FAIL: %s" % message)
