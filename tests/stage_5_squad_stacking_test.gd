extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")

var _failure_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_squad_data_layout_and_orders()
	await _test_squad_view_sources_and_row_width()
	await _test_card_transactions()
	await _test_external_merge_preview_anchors_to_target_boundary()
	await _test_geometry_targeting_and_distance_feedback()
	await _test_whole_squad_transactions()
	await _test_capacity_rules_and_cancel_restore()
	await _test_drag_mode_feedback_and_phase_lock()
	await _test_hand_carry_clears_stale_board_hover()
	await _test_prefer_squad_native_hand_stack()
	await _test_prefer_squad_single_source_stack()
	await _test_prefer_squad_expanded_target_rules()
	await _test_stable_drop_reservation()
	await _test_stack_intent_continuity_across_center()
	if _failure_count == 0:
		print("Stage 5 integration checks passed.")
	else:
		push_error("Stage 5 integration checks failed: %d" % _failure_count)
	quit(_failure_count)


func _test_squad_data_layout_and_orders() -> void:
	var cards := _make_cards(4)
	var single := SquadData.from_card(cards[0])
	_expect_layout(single, 3, 99, [0.0], [3], "单卡")

	var compact := SquadData.from_cards(
		_typed_cards([cards[0], cards[1]]),
		SquadData.TwoCardLayout.COMPACT
	)
	_expect_layout(compact, 4, 129, [0.0, 30.0], [3, 1], "紧密双卡")
	compact.bring_card_to_top(cards[1])
	_expect(
		compact.get_visible_rune_counts() == [1, 3],
		"紧密双卡的 3+1 / 1+3 显示随层级最上卡方向变化"
	)

	var expanded := SquadData.from_cards(
		_typed_cards([cards[0], cards[1]]),
		SquadData.TwoCardLayout.EXPANDED
	)
	_expect_layout(expanded, 5, 159, [0.0, 60.0], [3, 2], "展开双卡")
	expanded.bring_card_to_top(cards[1])
	_expect(
		expanded.get_visible_rune_counts() == [2, 3],
		"展开双卡的 3+2 / 2+3 显示随层级最上卡方向变化"
	)

	var triple := SquadData.from_cards(_typed_cards([cards[0], cards[1], cards[2]]))
	_expect_layout(triple, 5, 159, [0.0, 30.0, 60.0], [3, 1, 1], "三卡")

	var example_one := SquadData.from_cards(_typed_cards([cards[0], cards[2]]))
	example_one.layer_cards.assign(_typed_cards([cards[2], cards[0]]))
	var inserted := example_one.insert_card(
		cards[1],
		1,
		SquadData.TwoCardLayout.EXPANDED
	)
	_expect(inserted, "示例一可把第三张卡插到水平中间")
	_expect(
		example_one.horizontal_cards == [cards[0], cards[1], cards[2]]
		and example_one.layer_cards == [cards[1], cards[2], cards[0]],
		"水平插入后水平为左/新中/右，层级为新中/右/左"
	)

	var example_two := SquadData.from_cards(_typed_cards([cards[0], cards[1], cards[2]]))
	var before_horizontal: Array[CardData] = example_two.horizontal_cards.duplicate()
	example_two.bring_card_to_top(cards[1])
	_expect(
		example_two.horizontal_cards == before_horizontal
		and example_two.layer_cards == [cards[1], cards[0], cards[2]],
		"把中卡提到最上只改变层级顺序，不改变水平顺序"
	)
	example_two.bring_card_to_top(cards[2])
	_expect(
		example_two.horizontal_cards == before_horizontal
		and example_two.layer_cards == [cards[2], cards[1], cards[0]],
		"右卡置顶时中卡保持第二层，三张卡都仍有可见区域"
	)
	example_two.bring_card_to_top(cards[0])
	_expect(
		example_two.horizontal_cards == before_horizontal
		and example_two.layer_cards == [cards[0], cards[1], cards[2]],
		"左卡置顶时中卡同样保持第二层，不会被左右两卡完全遮住"
	)

	triple.remove_card(cards[1])
	_expect(
		triple.get_unit_count() == 5
		and triple.two_card_layout == SquadData.TwoCardLayout.EXPANDED,
		"三卡移出中卡后保留两侧 60px 间距，成为 5 单元展开双卡"
	)
	triple.remove_card(cards[0])
	_expect(triple.get_unit_count() == 3, "双卡再移出一张后成为 3 单元单卡")

	var remove_left := SquadData.from_cards(_typed_cards([cards[0], cards[1], cards[2]]))
	remove_left.remove_card(cards[0])
	_expect(
		remove_left.two_card_layout == SquadData.TwoCardLayout.COMPACT
		and remove_left.get_unit_count() == 4
		and remove_left.get_card_x_positions() == [0.0, 30.0],
		"三卡移出水平第一张后收为 30px 紧密双卡"
	)
	var remove_right := SquadData.from_cards(_typed_cards([cards[0], cards[1], cards[2]]))
	remove_right.remove_card(cards[2])
	_expect(
		remove_right.two_card_layout == SquadData.TwoCardLayout.COMPACT
		and remove_right.get_unit_count() == 4
		and remove_right.get_card_x_positions() == [0.0, 30.0],
		"三卡移出水平第三张后同样收为 30px 紧密双卡"
	)


func _test_squad_view_sources_and_row_width() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var cards: Array[CardData] = main.hand_cards.duplicate()
	var squad := SquadData.from_cards(_typed_cards([cards[0], cards[1], cards[2]]))
	squad.layer_cards.assign(_typed_cards([cards[1], cards[2], cards[0]]))
	var slot := front_row.add_squad(squad, 0)
	await process_frame
	await process_frame
	_expect(slot.size == Vector2(159, 136), "三卡小队视图真实尺寸为 159×136px")
	var views := slot.get_card_views()
	_expect(
		views.size() == 3
		and views[0].size == Vector2(99, 136)
		and views[1].size == Vector2(99, 136)
		and views[2].size == Vector2(99, 136),
		"小队内每张卡仍保持完整 99×136px"
	)
	_expect(
		views[0].position.x == 0.0
		and views[1].position.x == 30.0
		and views[2].position.x == 60.0,
		"三卡小队按 [0,30,60] 水平放置"
	)
	_expect(
		is_equal_approx(views[0].action_icon.modulate.a, 1.0)
		and is_equal_approx(views[1].action_icon.modulate.a, SquadView.INACTIVE_ATTRIBUTE_ALPHA)
		and is_equal_approx(views[2].health_icon.modulate.a, 1.0)
		and is_equal_approx(views[0].health_icon.modulate.a, SquadView.INACTIVE_ATTRIBUTE_ALPHA),
		"非最左行动与非最右生命/护甲图标降为 40% 透明度而非隐藏"
	)
	_expect(
		is_equal_approx(slot.get_card_view(cards[1]).effect_text_label.modulate.a, 1.0)
		and is_equal_approx(slot.get_card_view(cards[0]).effect_text_label.modulate.a, SquadView.INACTIVE_ATTRIBUTE_ALPHA),
		"最上层效果保持完整显示，其他卡牌效果标记为非来源"
	)
	_expect(
		views[0].action_icon.visible
		and views[1].action_icon.visible
		and views[0].health_icon.visible
		and views[1].health_icon.visible,
		"非来源属性图标仍保持可见"
	)
	_expect(
		squad.get_action_source() == cards[0]
		and squad.get_vitals_source() == cards[2]
		and squad.get_effect_source() == cards[1],
		"最左、最右、最上分别提供行动、生命护甲、卡牌效果"
	)
	_expect(
		slot.get_card_view(cards[1]).z_index
		- slot.get_card_view(cards[0]).z_index
		>= CardView.CARD_LAYER_Z_STEP
		and slot.get_card_view(cards[1]).z_index
		- slot.get_card_view(cards[2]).z_index
		>= CardView.CARD_LAYER_Z_STEP
		and slot.get_card_view(cards[1]).get_index()
		> slot.get_card_view(cards[0]).get_index()
		and slot.get_card_view(cards[1]).get_index()
		> slot.get_card_view(cards[2]).get_index(),
		"三卡中卡的整卡 Z 与兄弟顺序都置顶，绘制和鼠标命中一致"
	)
	var left_top_double := SquadData.from_cards(_typed_cards([cards[0], cards[2]]))
	left_top_double.layer_cards.assign(_typed_cards([cards[2], cards[0]]))
	left_top_double.bring_card_to_top(cards[0])
	var original_left_view := views[0]
	var original_middle_view := views[1]
	var original_right_view := views[2]
	slot.set_squad_data(left_top_double)
	var left_view := slot.get_card_view(cards[0])
	var right_view := slot.get_card_view(cards[2])
	_expect(
		left_view == original_left_view
		and right_view == original_right_view
		and slot.get_card_view(cards[1]) == null
		and original_middle_view.get_parent() == null,
		"小队刷新复用仍在队内的 CardView，只释放真正离队的卡牌节点"
	)
	_expect(
		left_view.position.x == 0.0
		and right_view.position.x == 60.0
		and left_view.z_index - right_view.z_index
		>= CardView.CARD_LAYER_Z_STEP
		and left_view.get_index() > right_view.get_index(),
		"双卡左卡的整卡 Z 与兄弟顺序都置顶，不会穿插或误选右卡"
	)
	left_view._on_mouse_entered()
	slot._on_card_mouse_entered(cards[0])
	slot.set_squad_data(left_top_double.duplicate_squad())
	_expect(
		slot.get_card_view(cards[0]) == left_view
		and bool(left_view.get("_mouse_hovered"))
		and slot.get("_hovered_card") == cards[0],
		"仅刷新小队数据时保留原生鼠标悬停节点和状态"
	)
	slot.reset_hover_feedback()
	slot.set_drag_hidden_card(cards[0])
	_expect(
		slot.get_card_view(cards[0]) == left_view and not left_view.visible,
		"拖动期间临时收拢只隐藏来源卡，不销毁真实 CardView"
	)
	slot.clear_drag_hidden_card()
	_expect(
		slot.get_card_view(cards[0]) == left_view and left_view.visible,
		"取消或完成拖动后复用同一 CardView 恢复来源卡"
	)

	for child: Node in front_row.get_squad_container().get_children():
		child.queue_free()
	await process_frame
	for index: int in 7:
		front_row.add_card(cards[index], index)
	await process_frame
	await process_frame
	_expect(front_row.get_used_unit_count() == 21, "七个单卡小队正好占 21 单元")
	_expect(front_row.get_content_width() == 801, "七个单卡小队含 18px 间距仍为 801px")
	var slots := front_row.get_squads()
	var measured_width := slots[-1].position.x + slots[-1].size.x - slots[0].position.x
	_expect(is_equal_approx(measured_width, 801.0), "战场行按真实小队宽度居中并保持 801px 满排")
	await _dispose_main(main)


func _test_card_transactions() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var back_row := main.get_node("%BackRow") as BattlefieldRow
	var original_cards: Array[CardData] = main.hand_cards.duplicate()
	_expect(main._transfer_card(_hand_drag(original_cards[0]), &"board", front_row, 0), "手牌创建单卡小队")
	var target := front_row.get_squads()[0]
	var snap_drag := _hand_drag(original_cards[1])
	snap_drag["grab_local_position"] = Vector2.ZERO
	snap_drag["preview_scale"] = Vector2.ONE
	var right_overlap_9 := _pointer_for_stack_overlap(
		front_row, target, snap_drag, 9.0, true
	)
	var right_overlap_71 := _pointer_for_stack_overlap(
		front_row, target, snap_drag, 71.0, true
	)
	_expect(
		front_row._find_card_stack_target(right_overlap_9, snap_drag) == null
		and front_row._find_card_stack_target(right_overlap_71, snap_drag)
		== null,
		"从右侧覆盖小于 10px 或大于 70px 时不进入叠卡逻辑"
	)
	var ten_pixel_intent := front_row._build_capacity_fitting_merge_intent(
		target,
		_pointer_for_stack_overlap(front_row, target, snap_drag, 10.0, true),
		snap_drag
	)
	var forty_pixel_intent := front_row._build_capacity_fitting_merge_intent(
		target,
		_pointer_for_stack_overlap(front_row, target, snap_drag, 40.0, true),
		snap_drag
	)
	_expect(
		front_row._find_card_stack_target(
			_pointer_for_stack_overlap(front_row, target, snap_drag, 10.0, true),
			snap_drag
		)
		== target
		and int(ten_pixel_intent.get("two_card_layout"))
		== SquadData.TwoCardLayout.EXPANDED
		and int(forty_pixel_intent.get("two_card_layout"))
		== SquadData.TwoCardLayout.EXPANDED,
		"从右侧覆盖 10～40px 时只盖一个符文，吸附为 60px 展开双卡"
	)
	var forty_one_pixel_intent := front_row._build_capacity_fitting_merge_intent(
		target,
		_pointer_for_stack_overlap(front_row, target, snap_drag, 41.0, true),
		snap_drag
	)
	var seventy_pixel_intent := front_row._build_capacity_fitting_merge_intent(
		target,
		_pointer_for_stack_overlap(front_row, target, snap_drag, 70.0, true),
		snap_drag
	)
	_expect(
		front_row._find_card_stack_target(
			_pointer_for_stack_overlap(front_row, target, snap_drag, 70.0, true),
			snap_drag
		)
		== target
		and int(forty_one_pixel_intent.get("two_card_layout"))
		== SquadData.TwoCardLayout.COMPACT
		and int(seventy_pixel_intent.get("two_card_layout"))
		== SquadData.TwoCardLayout.COMPACT,
		"从右侧覆盖 41～70px 时盖住两个符文，吸附为 30px 紧密双卡"
	)
	_expect(
		front_row._find_card_stack_target(
			_pointer_for_stack_overlap(front_row, target, snap_drag, 9.0, false),
			snap_drag
		) == null
		and front_row._find_card_stack_target(
			_pointer_for_stack_overlap(front_row, target, snap_drag, 71.0, false),
			snap_drag
		)
		== null,
		"从左侧覆盖也只接受 10～70px 两段吸附带"
	)
	var reverse_expanded_intent := front_row._build_capacity_fitting_merge_intent(
		target,
		_pointer_for_stack_overlap(front_row, target, snap_drag, 40.0, false),
		snap_drag
	)
	var reverse_compact_intent := front_row._build_capacity_fitting_merge_intent(
		target,
		_pointer_for_stack_overlap(front_row, target, snap_drag, 41.0, false),
		snap_drag
	)
	_expect(
		front_row._find_card_stack_target(
			_pointer_for_stack_overlap(front_row, target, snap_drag, 10.0, false),
			snap_drag
		)
		== target
		and front_row._find_card_stack_target(
			_pointer_for_stack_overlap(front_row, target, snap_drag, 70.0, false),
			snap_drag
		)
		== target
		and int(reverse_expanded_intent.get("two_card_layout"))
		== SquadData.TwoCardLayout.EXPANDED
		and int(reverse_compact_intent.get("two_card_layout"))
		== SquadData.TwoCardLayout.COMPACT,
		"左右方向使用完全对称的 10～40 / 41～70px 卡边覆盖带"
	)
	snap_drag["grab_local_position"] = Vector2(10.0, 68.0)
	var expanded_snap_position := Vector2(
		_pointer_for_stack_overlap(front_row, target, snap_drag, 30.0, true),
		68.0
	)
	_expect(
		front_row.preview_card_drop(expanded_snap_position, snap_drag)
		and int((front_row.get("_preview_intent") as Dictionary).get("two_card_layout"))
		== SquadData.TwoCardLayout.EXPANDED,
		"拖动卡从右侧覆盖 30px 时选择 2+3 展开吸附点"
	)
	front_row.clear_drop_preview()
	await process_frame
	await process_frame
	# 抓住卡牌不同位置，但保持两张卡的实际覆盖量同为 60px；结果必须相同。
	snap_drag["grab_local_position"] = Vector2(50.0, 68.0)
	var compact_snap_position := Vector2(
		_pointer_for_stack_overlap(front_row, target, snap_drag, 60.0, true),
		68.0
	)
	_expect(
		front_row.preview_card_drop(compact_snap_position, snap_drag)
		and int((front_row.get("_preview_intent") as Dictionary).get("two_card_layout"))
		== SquadData.TwoCardLayout.COMPACT,
		"拖动卡从右侧覆盖 60px 时选择 1+3 紧密吸附点"
	)
	front_row.clear_drop_preview()
	await process_frame
	await process_frame
	snap_drag["grab_local_position"] = Vector2(10.0, 68.0)
	compact_snap_position = Vector2(
		_pointer_for_stack_overlap(front_row, target, snap_drag, 60.0, true),
		68.0
	)
	_expect(
		front_row.preview_card_drop(compact_snap_position, snap_drag)
		and int((front_row.get("_preview_intent") as Dictionary).get("two_card_layout"))
		== SquadData.TwoCardLayout.COMPACT,
		"同一 60px 覆盖量换成不同抓取点后仍选择紧密吸附，判定不依赖鼠标"
	)
	front_row.clear_drop_preview()
	var native_merge_drag := _hand_drag(original_cards[1])
	native_merge_drag["grab_local_position"] = Vector2(50.0, 68.0)
	native_merge_drag["preview_scale"] = Vector2.ONE
	var target_center := Vector2(
		_pointer_for_stack_overlap(front_row, target, native_merge_drag, 60.0, true),
		68.0
	)
	_expect(
		front_row.preview_card_drop(target_center, native_merge_drag),
		"手牌拖到已有场上卡牌时显示叠卡虚影"
	)
	var merge_preview := front_row.get("_preview_slot") as BoardSlot
	_expect(
		is_equal_approx(
			merge_preview.get_card_view(original_cards[0]).modulate.a,
			1.0
		)
		and is_equal_approx(
			merge_preview.get_card_view(original_cards[1]).modulate.a,
			SquadView.PREVIEW_ALPHA
		),
		"叠卡预览只让待加入卡半透明，目标原卡保持 100% 不透明"
	)
	var preview_intent_before_drop: Dictionary = front_row.get("_preview_intent").duplicate()
	front_row.commit_card_drop(target_center, native_merge_drag)
	target.reset_hover_feedback()
	var committed_views := target.get_card_views()
	_expect(
		preview_intent_before_drop.get("operation") == &"merge_card"
		and target.get_squad_data().get_card_count() == 2
		and committed_views.size() == 2
		and committed_views[0].position.x == 0.0
		and committed_views[1].position.x > 0.0,
		"松手并恢复悬停视觉后仍沿用叠卡意图和水平错位"
	)
	var native_third_drag := _hand_drag(original_cards[2])
	native_third_drag["grab_local_position"] = Vector2(50.0, 68.0)
	native_third_drag["preview_scale"] = Vector2.ONE
	var native_third_visual := CardView.create_drag_visual(native_third_drag)
	root.add_child(native_third_visual)
	native_third_drag["drag_visual"] = native_third_visual
	var native_third_position := Vector2(
		_pointer_for_stack_overlap(front_row, target, native_third_drag, 60.0, true),
		68.0
	)
	native_third_visual.global_position = (
		front_row.placement_overlay.get_global_transform_with_canvas()
		* native_third_position
	)
	_expect(
		front_row.preview_card_drop(native_third_position, native_third_drag),
		"尚未封顶的紧密双卡可原生预览第三张手牌卡"
	)
	var native_preview := front_row.get("_preview_slot") as BoardSlot
	var native_preview_view := native_preview.get_card_view(original_cards[2])
	_expect(
		native_preview.get_squad_data() == null
		and native_preview.get_display_data().get_card_count() == 3
		and native_preview.get_display_data().layer_cards[0] == original_cards[2]
		and native_preview_view.z_index
		> native_preview.get_card_view(original_cards[0]).z_index
		and native_preview_view.z_index
		> native_preview.get_card_view(original_cards[1]).z_index
		and native_preview_view.get_index()
		> native_preview.get_card_view(original_cards[0]).get_index()
		and native_preview_view.get_index()
		> native_preview.get_card_view(original_cards[1]).get_index(),
		"第三张新卡在目标虚影的数据、整卡 Z 与命中顺序中都位于最上层"
	)
	_expect(
		native_third_visual.z_index > native_preview.z_index
		and native_preview.z_index > target.z_index,
		"鼠标携带卡高于目标虚影，目标虚影高于真实小队，不再相互穿模"
	)
	front_row.commit_card_drop(native_third_position, native_third_drag)
	_expect(
		target.get_squad_data().get_card_count() == 3
		and target.get_squad_data().layer_cards[0] == original_cards[2]
		and target.get_card_view(original_cards[2]).z_index
		> target.get_card_view(original_cards[0]).z_index
		and target.get_card_view(original_cards[2]).get_index()
		> target.get_card_view(original_cards[1]).get_index(),
		"第三张卡松手后仍保持最上层，不会被原双卡盖住"
	)
	native_third_visual.queue_free()
	front_row.remove_card_from_squad(target, original_cards[2])
	main.hand_cards.push_front(original_cards[2])
	# 还原为单卡，后续继续分别覆盖紧密和展开布局。
	front_row.remove_card_from_squad(target, original_cards[1])
	main.hand_cards.push_front(original_cards[1])
	main._build_hand_cards()

	var compact_result := target.get_squad_data().duplicate_squad()
	compact_result.insert_card(original_cards[1], 1, SquadData.TwoCardLayout.COMPACT)
	_expect(
		main._transfer_drop_intent(
			_hand_drag(original_cards[1], {
				"operation": &"merge_card",
				"squad_index": 0,
				"card_index": 1,
				"target_slot": target,
				"result_squad": compact_result,
			}),
			front_row
		),
		"手牌卡可加入已有小队"
	)
	_expect(target.get_squad_data().get_unit_count() == 4, "单卡加入为紧密双卡时只增加 1 单元")
	_expect(target.get_squad_data().get_effect_source() == original_cards[1], "新加入卡默认成为最上层")
	var left_top_drag := _board_card_drag(front_row, target, original_cards[0])
	front_row._begin_card_drag(left_top_drag)
	var left_top_drop := target.position + Vector2(10.0, 68.0)
	_expect(
		front_row.preview_card_drop(left_top_drop, left_top_drag),
		"双卡左侧暴露区域可作为单卡拖动来源"
	)
	front_row.commit_card_drop(left_top_drop, left_top_drag)
	_expect(
		target.get_squad_data().horizontal_cards == [original_cards[0], original_cards[1]]
		and target.get_squad_data().layer_cards[0] == original_cards[0],
		"把双卡左卡拖回原水平位置后，左卡成为完整最上层"
	)

	var triple_result := target.get_squad_data().duplicate_squad()
	triple_result.insert_card(original_cards[2], 1)
	_expect(
		main._transfer_drop_intent(
			_hand_drag(original_cards[2], {
				"operation": &"merge_card",
				"squad_index": 0,
				"card_index": 1,
				"target_slot": target,
				"result_squad": triple_result,
			}),
			front_row
		),
		"第三张手牌卡可加入小队并统一重排"
	)
	_expect(target.get_squad_data().horizontal_cards == [original_cards[0], original_cards[2], original_cards[1]], "第三张卡插入水平中间")
	target.get_squad_data().bring_card_to_top(original_cards[1])
	target.set_squad_data(target.get_squad_data())
	var middle_top_drag := _board_card_drag(front_row, target, original_cards[2])
	front_row._begin_card_drag(middle_top_drag)
	var middle_top_drop := target.position + Vector2(target.size.x * 0.5, 68.0)
	_expect(
		front_row.preview_card_drop(middle_top_drop, middle_top_drag),
		"三卡中间暴露区域可作为单卡拖动来源"
	)
	front_row.commit_card_drop(middle_top_drop, middle_top_drag)
	_expect(
		target.get_squad_data().horizontal_cards == [original_cards[0], original_cards[2], original_cards[1]]
		and target.get_squad_data().layer_cards[0] == original_cards[2],
		"把三卡中卡拖回水平中间后，中卡成为完整最上层"
	)

	var reorder_result := target.get_squad_data().duplicate_squad()
	reorder_result.move_card_horizontally(original_cards[2], 0)
	_expect(
		main._transfer_drop_intent(
			_board_card_drag(front_row, target, original_cards[2], {
				"operation": &"merge_card",
				"squad_index": 0,
				"card_index": 0,
				"target_slot": target,
				"result_squad": reorder_result,
			}),
			front_row
		),
		"同一小队内可调整卡牌水平位置"
	)
	_expect(
		target.get_squad_data().horizontal_cards[0] == original_cards[2]
		and target.get_squad_data().layer_cards[0] == original_cards[2],
		"同队水平重排同时把该卡提到最上层"
	)

	var extracted := SquadData.from_card(original_cards[2])
	_expect(
		main._transfer_drop_intent(
			_board_card_drag(front_row, target, original_cards[2], {
				"operation": &"new_squad",
				"squad_index": 1,
				"card_index": 0,
				"result_squad": extracted,
			}),
			front_row
		),
		"可从三卡小队抽出任意卡成为新小队"
	)
	_expect(
		front_row.get_squad_count() == 2
		and target.get_squad_data().get_card_count() == 2
		and target.get_squad_data().get_unit_count() == 4,
		"抽出水平第一张后来源收为紧密双卡，新卡成为独立小队"
	)

	var extracted_slot := front_row.get_squads()[1]
	var removed_for_space := original_cards[1]
	front_row.remove_card_from_squad(target, removed_for_space)
	main.hand_cards.append(removed_for_space)
	var cross_result := target.get_squad_data().duplicate_squad()
	cross_result.insert_card(
		original_cards[2],
		1,
		SquadData.TwoCardLayout.COMPACT
	)
	_expect(
		main._transfer_drop_intent(
			_board_card_drag(front_row, extracted_slot, original_cards[2], {
				"operation": &"merge_card",
				"squad_index": 0,
				"card_index": 1,
				"target_slot": target,
				"result_squad": cross_result,
			}),
			front_row
		),
		"目标降到三单元后，单卡仍可跨小队加入"
	)
	_expect(
		front_row.get_squad_count() == 1
		and target.get_squad_data().get_card_count() == 2,
		"合法跨小队后空来源小队被移除"
	)

	var cross_row_result := SquadData.from_card(original_cards[2])
	_expect(
		main._transfer_drop_intent(
			_board_card_drag(front_row, target, original_cards[2], {
				"operation": &"new_squad",
				"squad_index": 0,
				"card_index": 0,
				"result_squad": cross_row_result,
			}),
			back_row
		),
		"单卡可从小队抽出并跨排成为新小队"
	)
	var back_slot := back_row.get_squads()[0]
	_expect(
		main._transfer_card(_board_card_drag(back_row, back_slot, original_cards[2]), &"hand", null, main.hand_cards.size()),
		"场上单卡可拖回手牌"
	)
	_expect(back_row.get_squad_count() == 0 and main.hand_cards.has(original_cards[2]), "拖回手牌不丢卡也不复制")
	var rebuilt_target := target.get_squad_data().duplicate_squad()
	rebuilt_target.insert_card(
		removed_for_space,
		1,
		SquadData.TwoCardLayout.COMPACT
	)
	_expect(
		main._transfer_drop_intent(
			_hand_drag(removed_for_space, {
				"operation": &"merge_card",
				"squad_index": 0,
				"card_index": 1,
				"target_slot": target,
				"result_squad": rebuilt_target,
			}),
			front_row
		),
		"三单元目标可重新组成紧密双卡，继续验证非最左卡回手"
	)
	var non_left_card := target.get_squad_data().horizontal_cards[-1]
	var source_count_before := target.get_squad_data().get_card_count()
	_expect(
		main._transfer_card(
			_board_card_drag(front_row, target, non_left_card),
			&"hand",
			null,
			main.hand_cards.size()
		),
		"可点击并拖回多卡小队中的非最左卡"
	)
	_expect(
		target.get_squad_data().get_card_count() == source_count_before - 1
		and main.hand_cards.has(non_left_card),
		"非最左卡回手后来源小队正确收拢"
	)
	await _dispose_main(main)


func _test_external_merge_preview_anchors_to_target_boundary() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var back_row := main.get_node("%BackRow") as BattlefieldRow
	var cards: Array[CardData] = main.hand_cards.duplicate()
	_expect(
		main._transfer_card(_hand_drag(cards[0]), &"board", front_row, 0),
		"建立外部来源虚影边界测试目标"
	)
	_expect(
		main._transfer_card(_hand_drag(cards[1]), &"board", back_row, 0),
		"建立跨排虚影边界测试来源"
	)
	var target := front_row.get_squads()[0]
	await process_frame
	await process_frame

	var hand_drag := _hand_drag(cards[2])
	hand_drag["grab_local_position"] = Vector2(50.0, 68.0)
	hand_drag["preview_scale"] = Vector2.ONE
	var hand_pointer := Vector2(
		_pointer_for_stack_overlap(front_row, target, hand_drag, 60.0, false),
		68.0
	)
	var target_anchor_before_hand := (
		target.get_card_view(cards[0]).get_global_transform_with_canvas()
		* Vector2.ZERO
	)
	_expect(
		front_row.preview_card_drop(hand_pointer, hand_drag),
		"手牌从左侧直接覆盖目标时建立叠卡虚影"
	)
	await process_frame
	var hand_preview := front_row.get("_preview_slot") as BoardSlot
	var target_anchor_in_hand_preview := (
		hand_preview.get_card_view(cards[0]).get_global_transform_with_canvas()
		* Vector2.ZERO
	)
	_expect(
		(front_row.get("_preview_intent") as Dictionary).get("operation")
		== &"merge_card"
		and int(
			(front_row.get("_preview_intent") as Dictionary).get("card_index")
		) == 0
		and target_anchor_in_hand_preview.distance_to(
			target_anchor_before_hand
		) < 0.1,
		"手牌叠卡虚影以目标原卡边界为锚点，不把原卡向右推移"
	)
	front_row.clear_drop_preview()
	await process_frame
	await process_frame

	var source := back_row.get_squads()[0]
	var cross_row_drag := _board_card_drag(back_row, source, cards[1])
	cross_row_drag["grab_local_position"] = Vector2(50.0, 68.0)
	cross_row_drag["preview_scale"] = Vector2.ONE
	var cross_row_pointer := Vector2(
		_pointer_for_stack_overlap(
			front_row,
			target,
			cross_row_drag,
			60.0,
			false
		),
		68.0
	)
	var target_anchor_before_cross_row := (
		target.get_card_view(cards[0]).get_global_transform_with_canvas()
		* Vector2.ZERO
	)
	_expect(
		front_row.preview_card_drop(cross_row_pointer, cross_row_drag),
		"跨排卡从左侧直接覆盖目标时建立叠卡虚影"
	)
	await process_frame
	var cross_row_preview := front_row.get("_preview_slot") as BoardSlot
	var target_anchor_in_cross_row_preview := (
		cross_row_preview.get_card_view(cards[0]).get_global_transform_with_canvas()
		* Vector2.ZERO
	)
	_expect(
		(front_row.get("_preview_intent") as Dictionary).get("operation")
		== &"merge_card"
		and int(
			(front_row.get("_preview_intent") as Dictionary).get("card_index")
		) == 0
		and target_anchor_in_cross_row_preview.distance_to(
			target_anchor_before_cross_row
		) < 0.1,
		"跨排叠卡虚影同样以目标原卡边界为锚点"
	)
	front_row.clear_drop_preview()
	await _dispose_main(main)


func _test_geometry_targeting_and_distance_feedback() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var cards: Array[CardData] = main.hand_cards.duplicate()
	var source := front_row.add_squad(
		SquadData.from_cards(
			_typed_cards([cards[0], cards[1]]),
			SquadData.TwoCardLayout.EXPANDED
		),
		0
	)
	var target := front_row.add_card(cards[2], 1)
	await process_frame
	await process_frame
	var same_row_drag := _board_card_drag(front_row, source, cards[1])
	same_row_drag["grab_local_position"] = Vector2(10.0, 68.0)
	same_row_drag["preview_scale"] = Vector2.ONE
	front_row._begin_card_drag(same_row_drag)
	await process_frame
	await process_frame
	# 模拟来源小队随预留位让位但卡面仍在补间中的一帧；吸附必须读取
	# 玩家实际看到的卡边，而不是 Container 已经提前更新的 slot.position。
	source.animate_from_global_position(source.global_position - Vector2(30.0, 0.0))
	var same_source_expanded_pointer := _pointer_for_stack_overlap(
		front_row,
		source,
		same_row_drag,
		30.0,
		true
	)
	_expect(
		front_row.preview_card_drop(
			Vector2(same_source_expanded_pointer, 68.0),
			same_row_drag
		)
		and (front_row.get("_preview_intent") as Dictionary).get("target_slot")
		== source
		and int((front_row.get("_preview_intent") as Dictionary).get(
			"two_card_layout"
		)) == SquadData.TwoCardLayout.EXPANDED,
		"同队重新堆叠按屏幕真实覆盖 30px 显示 2+3 展开虚影"
	)
	front_row.clear_drop_preview()
	await create_timer(SquadView.LAYOUT_TWEEN_DURATION + 0.02).timeout
	var drag_width := (
		SquadView.CARD_SIZE.x * CardDragPreview.DRAG_SCALE_MULTIPLIER
	)
	var covered_pixels := 25.0
	var drag_left_x := target.position.x - drag_width + covered_pixels
	var pointer_x := (
		drag_left_x
		+ 10.0 * CardDragPreview.DRAG_SCALE_MULTIPLIER
	)
	_expect(
		pointer_x < target.position.x
		and front_row.preview_card_drop(Vector2(pointer_x, 68.0), same_row_drag)
		and (front_row.get("_preview_intent") as Dictionary).get("target_slot") == source
		and ((front_row.get("_preview_intent") as Dictionary).get(
			"result_squad"
		) as SquadData).layer_cards[0] == cards[1]
		and is_equal_approx(
			source.get_stack_target_feedback_strength(),
			1.0
		),
		"抽出的下层卡同时覆盖原小队和邻队时，原小队以最高优先级接回并置顶"
	)
	_expect(
		source.get_stack_target_snapshot_count() == 1,
		"多卡小队抽出一张后，来源颤动快照只绘制剩余卡，不重复绘制拖动卡"
	)
	await create_timer(SquadView.LAYOUT_TWEEN_DURATION + 0.02).timeout
	# 再向右移动到从左侧覆盖邻队 60px，此时已经离开中央独立部署区。
	pointer_x = _pointer_for_stack_overlap(
		front_row,
		target,
		same_row_drag,
		60.0,
		false
	)
	_expect(
		front_row.preview_card_drop(Vector2(pointer_x, 68.0), same_row_drag)
		and (front_row.get("_preview_intent") as Dictionary).get("target_slot") == target,
		"抽出卡离开原小队后，仍可吸附到相邻小队"
	)
	front_row._finish_card_drag()
	await _dispose_main(main)

	main = await _create_main()
	front_row = main.get_node("%FrontRow") as BattlefieldRow
	cards = main.hand_cards.duplicate()
	front_row.add_squad(
		SquadData.from_cards(
			_typed_cards([cards[0], cards[1]]),
			SquadData.TwoCardLayout.EXPANDED
		),
		0
	)
	var full_row_source := front_row.add_squad(
		SquadData.from_cards(
			_typed_cards([cards[2], cards[3]]),
			SquadData.TwoCardLayout.COMPACT
		),
		1
	)
	for index: int in 4:
		front_row.add_card(cards[4 + index], index + 2)
	await process_frame
	await process_frame
	_expect(
		front_row.get_used_unit_count() == 21,
		"构造与截图一致的 5+4+3+3+3+3 满 21 单元阵容"
	)
	var full_row_source_drag := _board_card_drag(
		front_row,
		full_row_source,
		cards[3]
	)
	full_row_source_drag["grab_local_position"] = Vector2(50.0, 68.0)
	full_row_source_drag["preview_scale"] = Vector2.ONE
	front_row._begin_card_drag(full_row_source_drag)
	await process_frame
	await process_frame
	var source_pointer_x := (
		full_row_source.position.x
		+ 30.0
		+ 50.0 * CardDragPreview.DRAG_SCALE_MULTIPLIER
	)
	_expect(
		front_row.preview_card_drop(
			Vector2(source_pointer_x, 68.0),
			full_row_source_drag
		)
		and (front_row.get("_preview_intent") as Dictionary).get("target_slot")
		== full_row_source
		and is_equal_approx(
			full_row_source.get_stack_target_feedback_strength(),
			1.0
		),
		"满 21 单元时下层卡放回本小队只计算一次结果占位，并保持最高优先级"
	)
	var source_restack_result := (front_row.get("_preview_intent") as Dictionary).get(
		"result_squad"
	) as SquadData
	_expect(
		source_restack_result != null
		and source_restack_result.get_unit_count() == 4
		and source_restack_result.layer_cards[0] == cards[3],
		"满排内放回原小队维持 4 单元，并把选中的下层卡提到最上"
	)
	front_row._finish_card_drag()
	await _dispose_main(main)

	main = await _create_main()
	front_row = main.get_node("%FrontRow") as BattlefieldRow
	cards = main.hand_cards.duplicate()
	var insert_left := front_row.add_card(cards[0], 0)
	var insert_right := front_row.add_card(cards[1], 1)
	await process_frame
	await process_frame
	var insert_drag := _hand_drag(cards[2])
	insert_drag["grab_local_position"] = Vector2(50.0, 68.0)
	insert_drag["preview_scale"] = Vector2.ONE
	var insert_gap_center := (
		insert_left.position.x + insert_left.size.x + insert_right.position.x
	) * 0.5
	var insert_pointer_x := (
		insert_gap_center
		- SquadView.CARD_SIZE.x * CardDragPreview.DRAG_SCALE_MULTIPLIER * 0.5
		+ 50.0 * CardDragPreview.DRAG_SCALE_MULTIPLIER
	)
	_expect(
		front_row.preview_card_drop(
			Vector2(insert_pointer_x, 68.0),
			insert_drag
		)
		and (front_row.get("_preview_intent") as Dictionary).get("operation")
		== &"new_squad"
		and (front_row.get("_preview_intent") as Dictionary).get("squad_index")
		== 1,
		"有容量时把完整单卡放在两个小队之间，会优先显示新建小队虚影"
	)
	_expect(
		front_row.preview_card_drop(
			Vector2(insert_pointer_x, 68.0),
			insert_drag
		)
		and (front_row.get("_preview_intent") as Dictionary).get("operation")
		== &"new_squad",
		"新建小队虚影出现后，完整虚影区域保持稳定，不会下一帧又吸附邻队"
	)
	front_row.commit_card_drop(Vector2(insert_pointer_x, 68.0), insert_drag)
	_expect(
		front_row.get_squad_count() == 3
		and front_row.get_squads()[1].get_card_data() == cards[2],
		"手牌单卡可在相邻两个小队之间直接释放为独立小队"
	)
	await _dispose_main(main)

	main = await _create_main()
	front_row = main.get_node("%FrontRow") as BattlefieldRow
	cards = main.hand_cards.duplicate()
	front_row.add_squad(
		SquadData.from_cards(
			_typed_cards([cards[0], cards[1]]),
			SquadData.TwoCardLayout.EXPANDED
		),
		0
	)
	for index: int in 5:
		front_row.add_card(cards[2 + index], index + 1)
	await process_frame
	await process_frame
	_expect(front_row.get_used_unit_count() == 20, "构造 5+3+3+3+3+3 的 20 单元目标排")
	var capacity_slots := front_row.get_squads()
	var nearby_left := capacity_slots[2]
	var nearby_right := capacity_slots[3]
	var capacity_drag := _hand_drag(cards[7])
	capacity_drag["grab_local_position"] = Vector2(50.0, 68.0)
	capacity_drag["preview_scale"] = Vector2.ONE
	var nearby_gap_center := (
		nearby_left.position.x + nearby_left.size.x + nearby_right.position.x
	) * 0.5
	var capacity_drag_center := nearby_gap_center - 6.0
	var capacity_pointer_x := (
		capacity_drag_center
		- SquadView.CARD_SIZE.x * CardDragPreview.DRAG_SCALE_MULTIPLIER * 0.5
		+ 50.0 * CardDragPreview.DRAG_SCALE_MULTIPLIER
	)
	_expect(
		front_row.preview_card_drop(
			Vector2(capacity_pointer_x, 68.0),
			capacity_drag
		)
		and (front_row.get("_preview_intent") as Dictionary).get("target_slot")
		== nearby_left
		and (front_row.get("_preview_intent") as Dictionary).get("target_slot")
		!= capacity_slots[0],
		"20 单元时卡牌位于两张单卡之间，只选择画面附近目标而不跳到最左小队"
	)
	var capacity_result := (front_row.get("_preview_intent") as Dictionary).get(
		"result_squad"
	) as SquadData
	var nearby_original := nearby_left.get_card_data()
	_expect(
		capacity_result != null
		and capacity_result.two_card_layout == SquadData.TwoCardLayout.COMPACT
		and capacity_result.contains(nearby_original)
		and capacity_result.contains(cards[7]),
		"附近展开叠法超容量时降级为紧密双卡，并保留原下层卡数据"
	)
	front_row.commit_card_drop(
		Vector2(capacity_pointer_x, 68.0),
		capacity_drag
	)
	_expect(
		nearby_left.get_squad_data().get_card_count() == 2
		and nearby_left.get_squad_data().contains(nearby_original)
		and nearby_left.get_squad_data().contains(cards[7])
		and capacity_slots[0].get_squad_data().get_card_count() == 2,
		"松手后只修改附近小队，目标原卡和最左小队都不会被替换"
	)
	await _dispose_main(main)

	main = await _create_main()
	front_row = main.get_node("%FrontRow") as BattlefieldRow
	cards = main.hand_cards.duplicate()
	front_row.add_squad(
		SquadData.from_cards(
			_typed_cards([cards[0], cards[1]]),
			SquadData.TwoCardLayout.COMPACT
		),
		0
	)
	for index: int in 5:
		front_row.add_card(cards[2 + index], index + 1)
	await process_frame
	await process_frame
	_expect(front_row.get_used_unit_count() == 19, "构造 4+3+3+3+3+3 的 19 单元目标排")
	var slots := front_row.get_squads()
	var left_target := slots[2]
	var right_target := slots[3]
	var far_target := slots[-1]
	var ambiguous_drag := _hand_drag(cards[7])
	ambiguous_drag["grab_local_position"] = Vector2(50.0, 68.0)
	ambiguous_drag["preview_scale"] = Vector2.ONE
	var left_center := left_target.position.x + left_target.size.x * 0.5
	var right_center := right_target.position.x + right_target.size.x * 0.5
	var desired_drag_center := (left_center + right_center) * 0.5 - 8.0
	pointer_x = (
		desired_drag_center - drag_width * 0.5
		+ 50.0 * CardDragPreview.DRAG_SCALE_MULTIPLIER
	)
	var lag_drag := ambiguous_drag.duplicate()
	var lag_visual := CardView.create_drag_visual(lag_drag)
	main.add_child(lag_visual)
	var compact_center := slots[0].position.x + slots[0].size.x * 0.5
	var lag_pointer_x := (
		compact_center - drag_width * 0.5
		+ 50.0 * CardDragPreview.DRAG_SCALE_MULTIPLIER
	)
	lag_visual.global_position = (
		front_row.placement_overlay.get_global_transform_with_canvas()
		* Vector2(lag_pointer_x, 68.0)
	)
	lag_visual.set("_visual_lag", Vector2(245.0, 0.0))
	lag_visual.call("_update_visual_transform")
	lag_drag["drag_visual"] = lag_visual
	var desired_visual_left := left_target.position.x + 30.0
	var current_visual_left := front_row._get_drag_card_left_x(
		lag_pointer_x,
		lag_drag
	)
	lag_visual.set(
		"_visual_lag",
		lag_visual.get("_visual_lag")
		+ Vector2(desired_visual_left - current_visual_left, 0.0)
	)
	lag_visual.call("_update_visual_transform")
	var actual_drag_center := front_row._get_drag_card_center_x(
		lag_pointer_x,
		lag_drag
	)
	var actual_nearest_slots: Array[BoardSlot] = slots.duplicate()
	actual_nearest_slots.sort_custom(func(left: BoardSlot, right: BoardSlot) -> bool:
		return (
			absf(left.position.x + left.size.x * 0.5 - actual_drag_center)
			< absf(right.position.x + right.size.x * 0.5 - actual_drag_center)
		)
	)
	front_row._update_stack_target_feedback(lag_pointer_x, lag_drag)
	_expect(
		actual_nearest_slots[0].get_stack_target_feedback_strength() > 0.0
		and actual_nearest_slots[1].get_stack_target_feedback_strength() > 0.0
		and actual_nearest_slots[0].get_stack_target_feedback_strength()
		> slots[0].get_stack_target_feedback_strength(),
		"拖动快照发生追赶滞后时，反馈跟随画面中的真实卡牌而不是远处鼠标"
	)
	_expect(
		front_row.preview_card_drop(
			Vector2(lag_pointer_x, 68.0),
			lag_drag
		)
		and (front_row.get("_preview_intent") as Dictionary).get("target_slot")
		== actual_nearest_slots[0]
		and (front_row.get("_preview_intent") as Dictionary).get("target_slot")
		!= slots[0],
		"拖动卡视觉位于中间时只吸附最近小队，不会跳到鼠标附近的最左小队"
	)
	var lag_result := (front_row.get("_preview_intent") as Dictionary).get(
		"result_squad"
	) as SquadData
	_expect(
		lag_result != null
		and lag_result.contains(lag_drag.get("card_data") as CardData)
		and lag_result.contains(
			actual_nearest_slots[0].get_squad_data().horizontal_cards[0]
		),
		"叠卡预览会保留目标原卡并加入拖动卡，不会用新卡替换原下层卡"
	)
	front_row.clear_drop_preview()
	front_row.stop_stack_target_feedback()
	lag_visual.queue_free()
	var pointer_global := (
		front_row.placement_overlay.get_global_transform_with_canvas()
		* Vector2(pointer_x, 68.0)
	)
	# Y 放到手牌区域，验证鼠标尚未进入战场行时，也会根据拖动卡的
	# 水平位置立刻提示两排附近的合法叠卡目标。
	pointer_global.y = (main.get_node("%HandDropZone") as Control).get_global_rect().get_center().y
	front_row.update_stack_target_feedback_global(pointer_global, ambiguous_drag)
	var compact_target := slots[0]
	var compact_snapshot_layer := compact_target.get(
		"_stack_target_snapshot_layer"
	) as Control
	var every_card_is_flattened := compact_snapshot_layer != null
	if compact_snapshot_layer != null:
		for child: Node in compact_snapshot_layer.get_children():
			var snapshot := child as CardSnapshotVisual
			every_card_is_flattened = (
				every_card_is_flattened
				and snapshot != null
				and snapshot.get_texture_control() != null
				and snapshot.get_texture_control().texture_filter
				== CanvasItem.TEXTURE_FILTER_NEAREST
			)
	_expect(
		not front_row.has_active_drop_preview()
		and left_target.get_stack_target_feedback_strength() > 0.0,
		"单卡刚开始移动、尚未进入战场行时就立即提示附近合法目标"
	)
	_expect(
		compact_target.get_stack_target_snapshot_count() == 2
		and every_card_is_flattened
		and not compact_target.card_visual_layer.visible,
		"双卡目标逐卡生成最近邻快照，切换首帧像素对齐且反馈期间不再绘制割裂节点"
	)
	front_row.stop_stack_target_feedback()
	_expect(
		compact_target.get_stack_target_snapshot_count() == 0
		and compact_target.card_visual_layer.visible,
		"目标反馈结束后清除逐卡快照并恢复真实卡牌"
	)
	front_row._update_stack_target_feedback(pointer_x, ambiguous_drag)
	_expect(
		left_target.get_stack_target_feedback_strength()
		> right_target.get_stack_target_feedback_strength()
		and right_target.get_stack_target_feedback_strength() > 0.0
		and right_target.get_stack_target_feedback_strength()
		> far_target.get_stack_target_feedback_strength()
		and far_target.get_stack_target_feedback_strength() > 0.0
		and left_target.is_stack_target_rotation_active()
		and right_target.is_stack_target_rotation_active()
		and far_target.is_stack_target_rotation_active(),
		"400px 范围内的合法目标持续旋转颤动，距离越远反馈强度越小"
	)
	await create_timer(0.08).timeout
	_expect(
		left_target.is_stack_target_rotation_active()
		and right_target.is_stack_target_rotation_active()
		and absf(left_target.stack_feedback_layer.rotation_degrees) > 0.0
		and absf(right_target.stack_feedback_layer.rotation_degrees) > 0.0
		and absf(left_target.stack_feedback_layer.rotation_degrees)
		> absf(right_target.stack_feedback_layer.rotation_degrees),
		"合法目标持续左右旋转颤动，且越靠近拖动卡旋转幅度越大"
	)
	_expect(
		front_row.preview_card_drop(Vector2(pointer_x, 68.0), ambiguous_drag)
		and (front_row.get("_preview_intent") as Dictionary).get("target_slot")
		== left_target,
		"19 单元无法新建小队时，拖动卡中心向左偏就吸附左侧合法目标"
	)
	front_row.clear_drop_preview()
	await process_frame
	await process_frame
	left_center = left_target.position.x + left_target.size.x * 0.5
	right_center = right_target.position.x + right_target.size.x * 0.5
	desired_drag_center = (left_center + right_center) * 0.5 + 8.0
	pointer_x = (
		desired_drag_center - drag_width * 0.5
		+ 50.0 * CardDragPreview.DRAG_SCALE_MULTIPLIER
	)
	_expect(
		front_row.preview_card_drop(Vector2(pointer_x, 68.0), ambiguous_drag)
		and (front_row.get("_preview_intent") as Dictionary).get("target_slot")
		== right_target,
		"同一位置向右偏时改为吸附右侧合法目标"
	)
	front_row.clear_drop_preview()
	_expect(
		is_zero_approx(left_target.get_stack_target_feedback_strength())
		and is_zero_approx(right_target.get_stack_target_feedback_strength())
		and not left_target.is_stack_target_rotation_active()
		and not right_target.is_stack_target_rotation_active()
		and is_zero_approx(left_target.stack_feedback_layer.rotation_degrees)
		and is_zero_approx(right_target.stack_feedback_layer.rotation_degrees),
		"离开或结束放置后清除全部合法目标旋转颤动并回正"
	)
	await _dispose_main(main)


func _test_whole_squad_transactions() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var back_row := main.get_node("%BackRow") as BattlefieldRow
	var cards: Array[CardData] = main.hand_cards.duplicate()
	var first := front_row.add_squad(SquadData.from_cards(_typed_cards([cards[0], cards[1]])), 0)
	var second := front_row.add_card(cards[2], 1)
	var squad_drag := _squad_drag(front_row, first)
	_expect(
		main._transfer_whole_squad(squad_drag, front_row, 1),
		"整队可在同排调整小队顺序"
	)
	_expect(front_row.get_squads() == [second, first], "同排整队换序保持小队内部两套顺序")
	_expect(
		main._transfer_whole_squad(squad_drag, back_row, 0),
		"整队可按完整占位跨排移动"
	)
	_expect(front_row.get_squad_count() == 1 and back_row.get_squads()[0].get_squad_data() == first.get_squad_data(), "跨排不拆分小队")

	var moved := back_row.get_squads()[0]
	var existing_target := front_row.get_squads()[0]
	var moved_drag := _squad_drag(back_row, moved)
	var target_center := existing_target.position.x + existing_target.size.x * 0.5
	back_row._begin_card_drag(moved_drag)
	_expect(
		not front_row.preview_card_drop(Vector2(target_center, 68.0), moved_drag),
		"整队拖到已有单卡小队时拒绝合并"
	)
	var multi_target := front_row.add_squad(SquadData.from_cards(_typed_cards([cards[3], cards[4]])), 1)
	await process_frame
	var multi_center := multi_target.position.x + multi_target.size.x * 0.5
	_expect(
		not front_row.preview_card_drop(Vector2(multi_center, 68.0), moved_drag),
		"整队拖到已有多卡小队时同样拒绝合并"
	)
	back_row._finish_card_drag()

	var hand_before: int = main.hand_cards.size()
	var horizontal_before: Array[CardData] = moved.get_squad_data().horizontal_cards.duplicate()
	_expect(main._transfer_squad_to_hand(moved_drag), "整队可拆开拖回手牌")
	_expect(
		main.hand_cards.slice(hand_before) == horizontal_before,
		"整队按水平顺序从左到右依次追加到手牌"
	)
	await _dispose_main(main)


func _test_capacity_rules_and_cancel_restore() -> void:
	var cards := _make_cards(8)
	var single := SquadData.from_card(cards[0])
	var compact := SquadData.from_cards(_typed_cards([cards[0], cards[1]]), SquadData.TwoCardLayout.COMPACT)
	var expanded := SquadData.from_cards(_typed_cards([cards[0], cards[1]]), SquadData.TwoCardLayout.EXPANDED)
	var compact_triple := compact.duplicate_squad()
	compact_triple.insert_card(cards[2], 2)
	var expanded_triple := expanded.duplicate_squad()
	expanded_triple.insert_card(cards[2], 1)
	var hidden_side_triple := expanded.duplicate_squad()
	hidden_side_triple.insert_card(cards[2], 2)
	_expect(compact.get_unit_count() - single.get_unit_count() == 1, "单卡→紧密双卡容量增量为 +1")
	_expect(expanded.get_unit_count() - single.get_unit_count() == 2, "单卡→展开双卡容量增量为 +2")
	_expect(compact_triple.get_unit_count() - compact.get_unit_count() == 1, "紧密双卡→三卡容量增量为 +1")
	_expect(
		expanded_triple.get_unit_count() - expanded.get_unit_count() == 0,
		"展开双卡从中间加入第三张时容量增量为 +0"
	)
	_expect(
		expanded_triple.get_visible_rune_counts() == [1, 3, 1],
		"展开双卡的第三张卡置于中间最上层时显示 1+3+1"
	)

	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var back_row := main.get_node("%BackRow") as BattlefieldRow
	var target := front_row.add_squad(expanded.duplicate_squad(), 0)
	front_row.add_squad(compact.duplicate_squad(), 1)
	for index: int in 4:
		front_row.add_card(cards[3 + index], 2 + index)
	await process_frame
	await process_frame
	_expect(front_row.get_used_unit_count() == 21, "构造 5+4+3+3+3+3 的 21 单元满排")
	var middle_capacity_intent := {
		"operation": &"merge_card",
		"squad_index": 0,
		"card_index": 1,
		"target_slot": target,
		"result_squad": expanded_triple,
	}
	_expect(
		front_row._intent_fits_capacity(
			middle_capacity_intent,
			_hand_drag(cards[7])
		),
		"满 21 单元时，展开双卡仍可从中间加入第三张且保持五单元"
	)
	var hidden_side_intent := middle_capacity_intent.duplicate()
	hidden_side_intent["card_index"] = 2
	hidden_side_intent["result_squad"] = hidden_side_triple
	_expect(
		not front_row._intent_fits_capacity(hidden_side_intent, _hand_drag(cards[7])),
		"展开双卡拒绝从侧边加入第三张形成 2+3+0"
	)
	var capped_drag := _hand_drag(cards[7])
	capped_drag["grab_local_position"] = Vector2(50.0, 68.0)
	capped_drag["preview_scale"] = Vector2.ONE
	var capped_pointer := target.position + Vector2(
		60.0 + 50.0 * CardDragPreview.DRAG_SCALE_MULTIPLIER,
		68.0
	)
	_expect(
		not front_row.preview_card_drop(capped_pointer, capped_drag)
		and is_zero_approx(target.get_stack_target_feedback_strength()),
		"展开双卡的侧边位置不进入合法候选，不晃动也不显示 2+3+0 虚影"
	)
	var middle_pointer := target.position + Vector2(
		30.0 + 50.0 * CardDragPreview.DRAG_SCALE_MULTIPLIER,
		68.0
	)
	var middle_preview_valid := front_row.preview_card_drop(
		middle_pointer,
		capped_drag
	)
	var middle_preview := front_row.get("_preview_slot") as BoardSlot
	_expect(
		middle_preview_valid
		and (front_row.get("_preview_intent") as Dictionary).get("operation")
		== &"merge_card"
		and int((front_row.get("_preview_intent") as Dictionary).get("card_index"))
		== 1
		and is_instance_valid(middle_preview)
		and middle_preview.get_display_data().get_visible_rune_counts()
		== [1, 3, 1],
		"展开双卡中间位置显示 1+3+1 的三卡叠放虚影"
	)
	front_row.clear_drop_preview()
	var hand_card := main.hand_cards[0] as CardData
	var forged_side_result := target.get_squad_data().duplicate_squad()
	forged_side_result.insert_card(hand_card, 2)
	var forged_side_intent := {
		"operation": &"merge_card",
		"squad_index": 0,
		"card_index": 2,
		"target_slot": target,
		"result_squad": forged_side_result,
	}
	var hand_count_before: int = main.hand_cards.size()
	_expect(
		not main._transfer_drop_intent(
			_hand_drag(hand_card, forged_side_intent),
			front_row
		)
		and target.get_squad_data().get_card_count() == 2
		and main.hand_cards.size() == hand_count_before,
		"提交层再次拒绝 2+3+0，目标与手牌数据都保持不变"
	)
	var valid_middle_result := target.get_squad_data().duplicate_squad()
	valid_middle_result.insert_card(hand_card, 1)
	var valid_middle_intent := forged_side_intent.duplicate()
	valid_middle_intent["card_index"] = 1
	valid_middle_intent["result_squad"] = valid_middle_result
	_expect(
		main._transfer_drop_intent(
			_hand_drag(hand_card, valid_middle_intent),
			front_row
		)
		and target.get_squad_data().get_card_count() == 3
		and target.get_squad_data().get_effect_source() == hand_card
		and target.get_squad_data().get_visible_rune_counts() == [1, 3, 1]
		and main.hand_cards.size() == hand_count_before - 1,
		"最终提交允许展开双卡从中间成为 1+3+1，且新中卡位于最上层"
	)
	_expect(
		not target.get_squad_data().can_accept_external_card_at(1),
		"小队达到三张卡后彻底封顶，不再接受第四张卡"
	)
	var moving_slot := back_row.add_card(cards[7], 0)
	await process_frame
	await process_frame
	var whole_squad_drag := _squad_drag(back_row, moving_slot)
	whole_squad_drag["grab_local_position"] = Vector2(49.0, 68.0)
	whole_squad_drag["preview_scale"] = Vector2.ONE
	whole_squad_drag["squad_cards"] = moving_slot.get_squad_data().horizontal_cards.duplicate()
	whole_squad_drag["squad_x_positions"] = moving_slot.get_squad_data().get_card_x_positions()
	whole_squad_drag["squad_layer_cards"] = moving_slot.get_squad_data().layer_cards.duplicate()
	whole_squad_drag["squad_size"] = Vector2(
		moving_slot.get_squad_data().get_display_width(),
		SquadView.CARD_SIZE.y
	)
	var whole_squad_visual := CardView.create_drag_visual(whole_squad_drag)
	root.add_child(whole_squad_visual)
	var full_slots := front_row.get_squads()
	var full_gap_x := (
		full_slots[0].position.x + full_slots[0].size.x
		+ full_slots[1].position.x
	) * 0.5
	_expect(
		not front_row.preview_card_drop(Vector2(full_gap_x, 68.0), whole_squad_drag)
		and front_row.get("_preview_slot") == null
		and whole_squad_visual.z_index == CardDragPreview.DRAG_PREVIEW_Z_INDEX,
		"满 21 单元时整队跨排无目标虚影，携带小队仍保持最高层而不穿模"
	)
	whole_squad_visual.queue_free()

	var before_horizontal: Array[CardData] = target.get_squad_data().horizontal_cards.duplicate()
	var before_layers: Array[CardData] = target.get_squad_data().layer_cards.duplicate()
	var cancel_drag := _board_card_drag(front_row, target, cards[0])
	front_row._begin_card_drag(cancel_drag)
	front_row.preview_card_drop(Vector2(800.0, 68.0), cancel_drag)
	front_row._finish_card_drag(Vector2(20.0, 20.0))
	_expect(
		target.get_squad_data().horizontal_cards == before_horizontal
		and target.get_squad_data().layer_cards == before_layers
		and front_row.get_used_unit_count() == 21,
		"取消或无效放置后水平、层级、容量均不变"
	)
	await _dispose_main(main)


func _test_drag_mode_feedback_and_phase_lock() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var cards: Array[CardData] = main.hand_cards.duplicate()
	var slot := front_row.add_squad(SquadData.from_cards(_typed_cards([cards[0], cards[1]])), 0)
	await process_frame
	var first_view := slot.get_card_view(cards[0])
	var shadow := slot.get_node("SquadInteractionShadow") as Panel
	var lift_layer := slot.get_node("StackFeedbackLayer/SquadLiftLayer") as Control
	_expect(
		is_equal_approx(SquadView.MODE_SWITCH_HOVER_SECONDS, 0.65)
		and is_equal_approx((slot.get_node("ModeSwitchTimer") as Timer).wait_time, 0.65),
		"模式切换悬停时间默认并实际配置为 0.65 秒"
	)

	slot.set_prefer_minion(true)
	first_view._on_mouse_entered()
	slot._on_card_mouse_entered(cards[0])
	_expect(slot.get_active_drag_kind() == &"card" and first_view.position.y < 0.0, "优先随从时即时抽出鼠标下单卡")
	await create_timer(0.12).timeout
	_expect(
		first_view.scale == slot.get_card_view(cards[1]).scale
		and first_view.position.y == -SquadView.CARD_LIFT_OFFSET,
		"单卡反馈只抽出鼠标下的卡牌，不再缩放像素卡面"
	)
	slot._on_mode_switch_timeout()
	_expect(
		slot.get_active_drag_kind() == &"squad"
		and shadow.visible
		and first_view.position.y == -SquadView.SQUAD_LIFT_OFFSET
		and slot.get_card_view(cards[1]).position.y
		== -SquadView.SQUAD_LIFT_OFFSET
		and first_view.scale == slot.get_card_view(cards[1]).scale,
		"优先随从悬停 0.65 秒后切为整队反馈，所有成员恢复相同尺寸"
	)
	_expect(
		lift_layer.position.y == 0.0
		and first_view.position.y == -SquadView.SQUAD_LIFT_OFFSET
		and slot.get_card_view(cards[1]).position.y
		== -SquadView.SQUAD_LIFT_OFFSET,
		"小队整体反馈时全部成员一起向上提起 7px"
	)
	await process_frame
	_expect(
		first_view.position.y == -SquadView.SQUAD_LIFT_OFFSET
		and slot.get_card_view(cards[1]).position.y
		== -SquadView.SQUAD_LIFT_OFFSET,
		"小队整体上移经过 Container 下一帧重新排版后仍然保持"
	)
	slot.lock_drag_subject(cards[0])
	var locked_kind := slot.get_active_drag_kind()
	slot._on_mode_switch_timeout()
	_expect(slot.get_active_drag_kind() == locked_kind, "鼠标按下后锁定当前操作对象")
	slot.reset_hover_feedback()
	_expect(
		not shadow.visible
		and first_view.position.y == 0.0
		and lift_layer.position.y == 0.0,
		"鼠标离开小队后取消计时并恢复默认位置"
	)
	slot.set_prefer_minion(true)
	var bottom_entry_position := (
		first_view.get_global_transform_with_canvas()
		* Vector2(10.0, SquadView.CARD_SIZE.y - 1.0)
	)
	var below_card_position := (
		first_view.get_global_transform_with_canvas()
		* Vector2(10.0, SquadView.CARD_SIZE.y + 20.0)
	)
	await _send_mouse_motion(below_card_position, Vector2.ZERO, 0)
	await _send_mouse_motion(
		bottom_entry_position,
		bottom_entry_position - below_card_position,
		0
	)
	_expect(
		first_view.position.y == -SquadView.CARD_LIFT_OFFSET
		and bool(first_view.get("_mouse_hovered"))
		and slot.get("_hovered_card") == cards[0]
		and first_view._has_point(
			Vector2(50.0, SquadView.CARD_SIZE.y + SquadView.CARD_LIFT_OFFSET - 1.0)
		),
		"卡牌从下边缘再次进入时，抽出后的命中区域仍覆盖原静止卡面"
	)
	await _send_mouse_motion(
		below_card_position,
		below_card_position - bottom_entry_position,
		0
	)
	_expect(
		first_view.position.y == 0.0
		and not bool(first_view.get("_mouse_hovered"))
		and slot.get("_hovered_card") == null,
		"原生鼠标离开卡牌下边缘后立即复位"
	)
	await _send_mouse_motion(
		bottom_entry_position,
		bottom_entry_position - below_card_position,
		0
	)
	_expect(
		first_view.position.y == -SquadView.CARD_LIFT_OFFSET
		and bool(first_view.get("_mouse_hovered"))
		and slot.get("_hovered_card") == cards[0],
		"从手牌方向第二次进入同一卡牌仍正常播放原生悬停"
	)
	await _send_mouse_motion(
		below_card_position,
		below_card_position - bottom_entry_position,
		0
	)

	slot.set_prefer_minion(false)
	slot.get_card_view(cards[1])._on_mouse_entered()
	slot._on_card_mouse_entered(cards[1])
	_expect(
		slot.get_active_drag_kind() == &"squad"
		and shadow.visible
		and first_view.scale == slot.get_card_view(cards[1]).scale
		and first_view.position.y == -SquadView.SQUAD_LIFT_OFFSET
		and slot.get_card_view(cards[1]).position.y
		== -SquadView.SQUAD_LIFT_OFFSET,
		"优先小队时即时显示整体震动与阴影反馈，成员尺寸保持一致"
	)
	await process_frame
	_expect(
		first_view.position.y == -SquadView.SQUAD_LIFT_OFFSET
		and slot.get_card_view(cards[1]).position.y
		== -SquadView.SQUAD_LIFT_OFFSET,
		"优先小队的即时整体上移不会在下一帧被布局系统回收"
	)
	slot._on_mode_switch_timeout()
	_expect(
		slot.get_active_drag_kind() == &"card"
		and slot.get_card_view(cards[1]).position.y < 0.0
		and lift_layer.position.y == 0.0,
		"优先小队悬停 0.65 秒后切为单卡抽出并取消整队上移"
	)
	slot.lock_drag_subject(cards[1])
	var squad_drag_data := slot.enrich_drag_data({
		"kind": &"card",
		"card_data": cards[1],
		"source_type": &"board",
		"source_row": front_row,
		"source_slot": slot,
		"grab_local_position": Vector2(40, 50),
		"preview_scale": Vector2.ONE,
	}, cards[1])
	# 先解锁并切回整队状态，验证真实预览包含小队内全部卡牌。
	slot.unlock_drag_subject()
	slot.set_prefer_minion(false)
	slot._on_card_mouse_entered(cards[1])
	slot.lock_drag_subject(cards[1])
	squad_drag_data = slot.enrich_drag_data(squad_drag_data, cards[1])
	var squad_drag_visual := CardView.create_drag_visual(squad_drag_data)
	root.add_child(squad_drag_visual)
	await process_frame
	var snapshot_source := squad_drag_visual.get_source_card_view() as Control
	_expect(
		squad_drag_data.get("kind") == &"squad"
		and snapshot_source != null
		and snapshot_source.get_child_count() == 2,
		"点击携带与长按拖动共用锁定结果，整队预览包含全部卡牌"
	)
	squad_drag_visual.queue_free()

	# 模式按钮不能污染手牌来源的 kind；单卡目标即使处于“优先小队”模式，
	# 也应保持单卡反馈并允许手牌直接叠入。
	var hand_stack_target := front_row.add_card(cards[2], 1)
	await process_frame
	await process_frame
	var mode_button := main.get_node("%DragModeButton") as Button
	mode_button.set_pressed_no_signal(false)
	main._on_drag_mode_toggled(false)
	hand_stack_target._on_card_mouse_entered(cards[2])
	await create_timer(0.05).timeout
	var hand_stack_view: CardView
	for hand_slot: Control in main.get_node("%HandCardRow").get_children():
		var candidate := hand_slot.get_child(0) as CardView
		if candidate.card_data == cards[3]:
			hand_stack_view = candidate
			break
	var hand_stack_drag := hand_stack_view._build_drag_data(Vector2(50.0, 68.0))
	var hand_stack_visual := CardView.create_drag_visual(hand_stack_drag)
	root.add_child(hand_stack_visual)
	hand_stack_drag["drag_visual"] = hand_stack_visual
	var hand_stack_position := hand_stack_target.position + Vector2(
		30.0 + 50.0 * CardDragPreview.DRAG_SCALE_MULTIPLIER,
		68.0
	)
	hand_stack_visual.global_position = (
		front_row.placement_overlay.get_global_transform_with_canvas()
		* hand_stack_position
	)
	await process_frame
	var hand_stack_preview_valid := front_row.placement_overlay._can_drop_data(
		hand_stack_position,
		hand_stack_drag
	)
	var hand_stack_intent := (front_row.get("_preview_intent") as Dictionary).duplicate()
	_expect(
		hand_stack_drag.get("kind") == &"card"
		and hand_stack_target.get_active_drag_kind() == &"card"
		and not (hand_stack_target.get_node("SquadInteractionShadow") as Panel).visible
		and hand_stack_preview_valid
		and hand_stack_intent.get("operation") == &"merge_card",
		"优先小队模式下手牌与场上单卡都使用单卡反馈，并能触发叠卡"
	)
	front_row.placement_overlay._drop_data(hand_stack_position, hand_stack_drag)
	_expect(
		hand_stack_target.get_squad_data().get_card_count() == 2
		and hand_stack_target.get_squad_data().get_effect_source() == cards[3],
		"优先小队模式下真实手牌拖拽可经战场接收层叠卡，并成为最上层"
	)
	hand_stack_visual.queue_free()

	mode_button.set_pressed_no_signal(true)
	main._on_drag_mode_toggled(true)
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	_expect(
		mode_button.button_pressed
		and mode_button.text == "拖拽：优先随从"
		and mode_button.is_visible_in_tree()
		and viewport_rect.encloses(mode_button.get_global_rect()),
		"模式按钮默认优先随从，并完整位于 1280×720 可视区域"
	)
	main._on_start_battle_button_pressed()
	_expect(
		not front_row.can_receive_card_drag(_board_card_drag(front_row, slot, cards[0]))
		and not front_row.preview_card_drop(Vector2(400, 68), _hand_drag(cards[2])),
		"战斗阶段禁止堆叠、抽出和整队调整"
	)
	await _dispose_main(main)


func _test_hand_carry_clears_stale_board_hover() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var board_card := _make_cards(1)[0]
	var target := front_row.add_card(board_card, 0)
	await process_frame
	await process_frame
	var target_view := target.get_card_view(board_card)
	target_view._on_mouse_entered()
	target._on_card_mouse_entered(board_card)
	await create_timer(0.05).timeout
	_expect(
		bool(target_view.get("_mouse_hovered"))
		and target.get("_hovered_card") == board_card,
		"先建立场上卡牌的鼠标指向状态"
	)

	var hand_view: CardView
	for hand_slot: Control in main.get_node("%HandCardRow").get_children():
		var candidate := hand_slot.get_child(0) as CardView
		if candidate != null:
			hand_view = candidate
			break
	var hand_position := hand_view.get_global_rect().get_center()
	target_view._on_mouse_exited()
	target._on_card_mouse_exited(board_card)
	var interaction_shadow := target_view.get_node("InteractionShadow") as Panel
	var squad_shadow := target.get_node("SquadInteractionShadow") as Panel
	_expect(
		not bool(target_view.get("_mouse_hovered"))
		and target.get("_hovered_card") == null
		and not interaction_shadow.visible
		and not squad_shadow.visible
		and target_view.position.y == 0.0,
		"鼠标离开场上卡并移动到手牌区时立即取消指向状态，无需等待选中其他卡"
	)

	# 再制造一次遗留状态，验证开始新操作时的兜底仍然有效。
	target_view._on_mouse_entered()
	target._on_card_mouse_entered(board_card)
	var hand_drag := hand_view._build_drag_data(hand_view.size * 0.5)
	main._on_click_carry_requested(hand_drag, hand_position)
	await process_frame
	_expect(
		not bool(target_view.get("_mouse_hovered"))
		and target.get("_hovered_card") == null
		and not interaction_shadow.visible
		and not squad_shadow.visible
		and target_view.position.y == 0.0,
		"从手牌开始点击携带时清除旧战场卡的抽出、阴影和小队悬停反馈"
	)
	main._cancel_click_carry()
	await _dispose_main(main)


func _test_prefer_squad_native_hand_stack() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var cards: Array[CardData] = main.hand_cards.duplicate()
	var target := front_row.add_card(cards[0], 0)
	await process_frame
	await process_frame
	var mode_button := main.get_node("%DragModeButton") as Button
	mode_button.button_pressed = false
	await process_frame

	var hand_view: CardView
	for hand_slot: Control in main.get_node("%HandCardRow").get_children():
		var candidate := hand_slot.get_child(0) as CardView
		if candidate.card_data == cards[1]:
			hand_view = candidate
			break
	var source_position := hand_view.get_global_rect().get_center()
	var initial_hand_count: int = main.hand_cards.size()
	var native_drop_events: Array[int] = [0]
	var native_drop_targets: Array[BoardSlot] = []
	var native_drop_operations: Array[StringName] = []
	var native_drop_positions: Array[Vector2] = []
	front_row.card_dropped.connect(
		func(
			_target_row: BattlefieldRow,
			_insert_index: int,
			_drag_data: Dictionary,
			card_global_position: Vector2
		) -> void:
			native_drop_events[0] += 1
			native_drop_positions.append(card_global_position)
			var emitted_intent := _drag_data.get("drop_intent") as Dictionary
			native_drop_targets.append(
				emitted_intent.get("target_slot") as BoardSlot
			)
			native_drop_operations.append(emitted_intent.get("operation") as StringName)
	)
	await _send_mouse_motion(source_position, Vector2.ZERO, 0)
	await _send_left_button(source_position, true)
	await _send_mouse_motion(
		source_position + Vector2(32.0, -16.0),
		Vector2(32.0, -16.0),
		MOUSE_BUTTON_MASK_LEFT
	)
	var native_drag_data := root.gui_get_drag_data() as Dictionary
	_expect(
		native_drag_data.get("kind") == &"card"
		and native_drag_data.get("source_type") == &"hand",
		"优先小队模式下 Godot 原生手牌拖拽仍锁定为单卡来源"
	)
	var native_grab: Vector2 = native_drag_data.get(
		"grab_local_position",
		Vector2.ZERO
	)
	var native_scale: Vector2 = native_drag_data.get("preview_scale", Vector2.ONE)
	var target_position := (
		front_row.placement_overlay.get_global_transform_with_canvas()
		* Vector2(
			target.position.x + 30.0
			+ native_grab.x * native_scale.x
			* CardDragPreview.DRAG_SCALE_MULTIPLIER,
			68.0
		)
	)
	await _send_mouse_motion(
		target_position,
		target_position - source_position,
		MOUSE_BUTTON_MASK_LEFT
	)
	await process_frame
	var native_intent := (front_row.get("_preview_intent") as Dictionary).duplicate()
	_expect(
		front_row.has_active_drop_preview()
		and native_intent.get("operation") == &"merge_card",
		"优先小队模式下原生手牌拖到战场单卡会显示叠卡虚影"
	)
	var native_drag_visual := native_drag_data.get("drag_visual") as CardDragPreview
	# 模拟快速拖动时快照明显落后鼠标；叠卡意图已经由屏幕快照确定，
	# 这里只验证成功松手后的飞行动画不再沿用这个滞后坐标。
	native_drag_visual.set("_visual_lag", Vector2(-240.0, 0.0))
	native_drag_visual.call("_update_visual_transform")
	var lagged_visual_position := native_drag_visual.get_card_global_position()
	var expected_release_position := (
		native_drag_visual.global_position
		- native_drag_data.get("preview_offset", Vector2.ZERO) as Vector2
	)
	await _send_left_button(target_position, false)
	var native_drop_successful := root.gui_is_drag_successful()
	await process_frame
	await process_frame
	_expect(
		native_drop_successful and native_drop_events[0] == 1,
		"优先小队模式下原生鼠标松手会由战场接收层提交一次 drop"
	)
	_expect(
		native_drop_operations.size() == 1
		and native_drop_operations[0] == &"merge_card",
		"优先小队模式下原生松手仍提交叠卡操作（实际：%s）"
		% [native_drop_operations[0] if not native_drop_operations.is_empty() else &"none"]
	)
	_expect(
		native_drop_targets.size() == 1 and native_drop_targets[0] == target,
		"优先小队模式下原生松手仍指向吸附预览的原目标小队"
	)
	_expect(
		native_drop_positions.size() == 1
		and native_drop_positions[0].distance_to(expected_release_position) < 0.1
		and native_drop_positions[0].distance_to(lagged_visual_position) > 100.0,
		"快速松手的飞入起点使用鼠标逻辑位置，同时保留拖动快照的追赶手感"
		+ "（发出=%s，逻辑=%s，快照=%s）"
		% [
			native_drop_positions[0] if not native_drop_positions.is_empty() else Vector2.ZERO,
			expected_release_position,
			lagged_visual_position,
		]
	)
	_expect(
		target.get_squad_data().get_card_count() == 2,
		"优先小队模式下原生鼠标松手会把手牌加入目标小队"
	)
	_expect(
		target.get_squad_data().get_effect_source() == cards[1],
		"优先小队模式下原生鼠标叠入的新卡成为最上层"
	)
	_expect(
		main.hand_cards.size() == initial_hand_count - 1,
		"优先小队模式下原生手牌叠卡不会丢失或复制卡牌"
	)
	await _dispose_main(main)


func _test_prefer_squad_single_source_stack() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var cards: Array[CardData] = main.hand_cards.duplicate()
	var source := front_row.add_card(cards[0], 0)
	var target := front_row.add_card(cards[1], 1)
	await process_frame
	await process_frame
	var mode_button := main.get_node("%DragModeButton") as Button
	mode_button.button_pressed = false
	await process_frame

	var source_view := source.get_card_view(cards[0])
	var source_position := source_view.get_global_rect().get_center()
	await _send_mouse_motion(source_position, Vector2.ZERO, 0)
	_expect(
		source.get_active_drag_kind() == &"card"
		and source_view.position.y < 0.0,
		"优先小队模式下单卡小队会立即使用单卡抽出状态"
	)
	await create_timer(SquadView.MODE_SWITCH_HOVER_SECONDS + 0.05).timeout
	_expect(
		source.get_active_drag_kind() == &"card"
		and not (source.get_node("SquadInteractionShadow") as Panel).visible,
		"单卡小队悬停超过 0.65 秒后仍保持单卡逻辑，不切成整队"
	)

	source_position = source_view.get_global_rect().get_center()
	await _send_left_button(source_position, true)
	await _send_mouse_motion(
		source_position + Vector2(32.0, -16.0),
		Vector2(32.0, -16.0),
		MOUSE_BUTTON_MASK_LEFT
	)
	var native_drag_data := root.gui_get_drag_data() as Dictionary
	_expect(
		native_drag_data.get("kind") == &"card"
		and native_drag_data.get("source_type") == &"board",
		"优先小队模式下原生拖拽会直接锁定场上单卡而不是整队"
	)

	var native_grab: Vector2 = native_drag_data.get(
		"grab_local_position",
		Vector2.ZERO
	)
	var native_scale: Vector2 = native_drag_data.get("preview_scale", Vector2.ONE)
	var target_position := (
		front_row.placement_overlay.get_global_transform_with_canvas()
		* Vector2(
			target.position.x + 30.0
			+ native_grab.x * native_scale.x
			* CardDragPreview.DRAG_SCALE_MULTIPLIER,
			68.0
		)
	)
	await _send_mouse_motion(
		target_position,
		target_position - source_position,
		MOUSE_BUTTON_MASK_LEFT
	)
	await process_frame
	var native_intent := (front_row.get("_preview_intent") as Dictionary).duplicate()
	_expect(
		front_row.has_active_drop_preview()
		and native_intent.get("operation") == &"merge_card"
		and native_intent.get("target_slot") == target,
		"优先小队模式下场上单卡拖到另一张单卡会显示叠卡虚影"
	)
	await _send_left_button(target_position, false)
	await process_frame
	await process_frame
	_expect(
		front_row.get_squad_count() == 1
		and target.get_squad_data().get_card_count() == 2
		and target.get_squad_data().get_effect_source() == cards[0],
		"优先小队模式下场上单卡可直接叠入另一小队并成为最上层"
	)
	await _dispose_main(main)


func _test_prefer_squad_expanded_target_rules() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var back_row := main.get_node("%BackRow") as BattlefieldRow
	var cards := _make_cards(9)
	var source := front_row.add_card(cards[0], 0)
	var blocked_target := back_row.add_squad(
		SquadData.from_cards(
			_typed_cards([cards[1], cards[2]]),
			SquadData.TwoCardLayout.EXPANDED
		),
		0
	)
	back_row.add_squad(
		SquadData.from_cards(
			_typed_cards([cards[3], cards[4]]),
			SquadData.TwoCardLayout.EXPANDED
		),
		1
	)
	back_row.add_squad(
		SquadData.from_cards(
			_typed_cards([cards[5], cards[6]]),
			SquadData.TwoCardLayout.EXPANDED
		),
		2
	)
	back_row.add_card(cards[7], 3)
	back_row.add_card(cards[8], 4)
	await process_frame
	await process_frame
	var mode_button := main.get_node("%DragModeButton") as Button
	mode_button.button_pressed = false
	await process_frame
	source._on_card_mouse_entered(cards[0])
	var source_view := source.get_card_view(cards[0])
	var drag_data := source_view._build_drag_data(source_view.size * 0.5)
	var grab_local_position: Vector2 = drag_data.get(
		"grab_local_position",
		Vector2.ZERO
	)
	var preview_scale: Vector2 = drag_data.get("preview_scale", Vector2.ONE)
	var middle_position := Vector2(
		blocked_target.position.x + 30.0
		+ grab_local_position.x * preview_scale.x
		* CardDragPreview.DRAG_SCALE_MULTIPLIER,
		68.0
	)
	_expect(
		drag_data.get("kind") == &"card"
		and back_row.get_used_unit_count() == 21
		and back_row.preview_card_drop(middle_position, drag_data)
		and (back_row.get("_preview_intent") as Dictionary).get("target_slot")
		== blocked_target
		and int((back_row.get("_preview_intent") as Dictionary).get("card_index"))
		== 1,
		"优先小队模式下，单卡可叠入五单元展开双卡的水平中间"
	)
	back_row.clear_drop_preview()
	var side_position := Vector2(
		blocked_target.position.x + 60.0
		+ grab_local_position.x * preview_scale.x
		* CardDragPreview.DRAG_SCALE_MULTIPLIER,
		68.0
	)
	_expect(
		not back_row.preview_card_drop(side_position, drag_data)
		and not back_row.has_active_drop_preview()
		and blocked_target.get_squad_data().get_card_count() == 2,
		"优先小队模式下，展开双卡侧边仍拒绝 2+3+0"
	)
	await _dispose_main(main)


func _test_stable_drop_reservation() -> void:
	await _run_drop_reservation_case([], 117.0, true)
	await _run_drop_reservation_case([5, 5, 3], 79.0, false)
	await _run_drop_reservation_case([5, 5, 4], 49.0, false)
	await _test_zero_unit_drop_without_reservation()
	await _test_new_squad_reservation_follows_insert_boundary()


func _test_stack_intent_continuity_across_center() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var target := front_row.add_card(_make_cards(1)[0], 0)
	await process_frame
	await process_frame
	var incoming := main.hand_cards[0] as CardData
	var drag_data := _hand_drag(incoming)
	drag_data["grab_local_position"] = Vector2(49.5, 68.0)
	drag_data["preview_scale"] = Vector2.ONE
	var grab_offset := (
		49.5 * CardDragPreview.DRAG_SCALE_MULTIPLIER
	)
	var first_stack_position := Vector2(
		_pointer_for_stack_overlap(front_row, target, drag_data, 30.0, true),
		68.0
	)
	_expect(
		front_row.preview_card_drop(first_stack_position, drag_data)
		and (front_row.get("_preview_intent") as Dictionary).get("operation")
		== &"merge_card",
		"从右侧覆盖 30px 时先建立叠卡意图"
	)
	var center_dead_zone_position := Vector2(
		front_row._get_slot_visual_left_x(target)
		+ SquadView.CARD_SIZE.x * 0.5
		- front_row._get_drag_card_width(drag_data) * 0.5
		+ grab_offset,
		68.0
	)
	_expect(
		front_row.preview_card_drop(center_dead_zone_position, drag_data)
		and (front_row.get("_preview_intent") as Dictionary).get("operation")
		== &"merge_card"
		and (front_row.get("_preview_intent") as Dictionary).get("target_slot")
		== target,
		"已吸附目标穿过卡面中央深度重叠区时保持叠卡，虚影不会跳到左侧"
	)
	var opposite_stack_position := Vector2(
		_pointer_for_stack_overlap(front_row, target, drag_data, 30.0, false),
		68.0
	)
	_expect(
		front_row.preview_card_drop(opposite_stack_position, drag_data)
		and (front_row.get("_preview_intent") as Dictionary).get("operation")
		== &"merge_card",
		"继续穿过中心到目标另一侧后仍正常叠卡"
	)
	await _dispose_main(main)


func _test_new_squad_reservation_follows_insert_boundary() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var cards := _make_cards(4)
	var squad_a := front_row.add_card(cards[0], 0)
	var squad_b := front_row.add_card(cards[1], 1)
	var squad_c := front_row.add_card(cards[2], 2)
	await process_frame
	await process_frame

	var incoming := main.hand_cards[0] as CardData
	var drag_data := _hand_drag(incoming)
	drag_data["grab_local_position"] = Vector2(49.5, 68.0)
	drag_data["preview_scale"] = Vector2.ONE
	var gap_ab_x := (
		squad_a.position.x + squad_a.size.x + squad_b.position.x
	) * 0.5
	_expect(
		front_row.preview_card_drop(Vector2(gap_ab_x, 68.0), drag_data)
		and front_row.get_drop_reservation_index() == 1
		and int((front_row.get("_preview_intent") as Dictionary).get(
			"squad_index"
		)) == 1,
		"独立部署到 A/B 中间时显示 A [虚影] B C"
	)
	await process_frame
	await process_frame

	var gap_bc_x := (
		squad_b.position.x + squad_b.size.x + squad_c.position.x
	) * 0.5
	_expect(
		front_row.preview_card_drop(Vector2(gap_bc_x, 68.0), drag_data)
		and front_row.get_drop_reservation_index() == 2
		and int((front_row.get("_preview_intent") as Dictionary).get(
			"squad_index"
		)) == 2,
		"拖到 B/C 中间时预留位和虚影一起变成 A B [虚影] C"
	)
	await process_frame
	await process_frame

	var left_x := squad_a.position.x - 20.0
	_expect(
		front_row.preview_card_drop(Vector2(left_x, 68.0), drag_data)
		and front_row.get_drop_reservation_index() == 0,
		"拖到最左侧时预留位和虚影一起移动到 [虚影] A B C"
	)
	await process_frame
	await process_frame

	var right_x := squad_c.position.x + squad_c.size.x + 90.0
	_expect(
		front_row.preview_card_drop(Vector2(right_x, 68.0), drag_data)
		and front_row.get_drop_reservation_index() == 3,
		"拖到最右侧时预留位和虚影一起移动到 A B C [虚影]"
	)
	await process_frame
	await process_frame

	gap_bc_x = (
		squad_b.position.x + squad_b.size.x + squad_c.position.x
	) * 0.5
	_expect(
		front_row.preview_card_drop(Vector2(gap_bc_x, 68.0), drag_data)
		and front_row.get_drop_reservation_index() == 2,
		"从其他边界返回 B/C 中间时虚影重新跟随到 index 2"
	)
	front_row.commit_card_drop(Vector2(gap_bc_x, 68.0), drag_data)
	await process_frame
	await process_frame
	_expect(
		front_row.get_squad_count() == 4
		and front_row.get_squads()[2].get_card_data() == incoming
		and not front_row.has_drop_reservation(),
		"松手后的真实部署位置与 B/C 中间虚影一致"
	)
	await _dispose_main(main)


func _run_drop_reservation_case(
	filler_units: Array,
	expected_width: float,
	commit_drop: bool
) -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var cards := _make_cards(12)
	var left_target := front_row.add_card(cards[0], 0)
	var right_target := front_row.add_card(cards[1], 1)
	var card_index: int = 2
	for units: int in filler_units:
		if units == 3:
			front_row.add_card(cards[card_index], front_row.get_squad_count())
			card_index += 1
		else:
			front_row.add_squad(
				SquadData.from_cards(
					_typed_cards([cards[card_index], cards[card_index + 1]]),
					SquadData.TwoCardLayout.COMPACT
					if units == 4
					else SquadData.TwoCardLayout.EXPANDED
				),
				front_row.get_squad_count()
			)
			card_index += 2
	await process_frame
	await process_frame

	var incoming := main.hand_cards[0] as CardData
	var drag_data := _hand_drag(incoming)
	drag_data["grab_local_position"] = Vector2(49.5, 68.0)
	drag_data["preview_scale"] = Vector2.ONE
	var original_gap_center := (
		left_target.position.x + left_target.size.x + right_target.position.x
	) * 0.5
	var original_target_distance := right_target.position.x - left_target.position.x
	var first_preview_valid := front_row.preview_card_drop(
		Vector2(original_gap_center, 68.0),
		drag_data
	)
	await process_frame
	await process_frame
	var layout_left := left_target
	if front_row.get("_preview_replaced_slot") == left_target:
		layout_left = front_row.get("_preview_slot") as BoardSlot
	_expect(
		first_preview_valid
		and front_row.has_drop_reservation()
		and is_equal_approx(front_row.get_drop_reservation_width(), expected_width)
		and is_equal_approx(
			right_target.position.x - layout_left.position.x,
			original_target_distance + expected_width
		)
		and front_row.get_drop_reservation_index() == 1,
		"剩余 %d 单元时相邻小队整体只让出 %.0fpx 总预算"
		% [BattlefieldRow.BATTLEFIELD_UNIT_COUNT - front_row.get_used_unit_count(), expected_width]
	)

	var reserved_width := front_row.get_drop_reservation_width()
	var left_stack_position := Vector2(
		_pointer_for_stack_overlap(front_row, left_target, drag_data, 60.0, true),
		68.0
	)
	var merge_preview_valid := front_row.preview_card_drop(
		left_stack_position,
		drag_data
	)
	var merge_intent := (front_row.get("_preview_intent") as Dictionary).duplicate()
	var merge_preview := front_row.get("_preview_slot") as BoardSlot
	var preview_growth := maxf(0.0, merge_preview.size.x - left_target.size.x)
	var expected_empty_width := maxf(
		0.0,
		reserved_width - BattlefieldRow.SQUAD_GAP - preview_growth
	)
	_expect(
		merge_preview_valid
		and merge_intent.get("operation") == &"merge_card"
		and merge_intent.get("target_slot") == left_target
		and front_row.has_drop_reservation()
		and is_equal_approx(front_row.get_drop_reservation_width(), reserved_width)
		and is_equal_approx(
			front_row.get_drop_reservation_empty_width(),
			expected_empty_width
		),
		"叠卡虚影增量计入总预算，纯空白 %.0fpx（实际 %.0fpx）"
		% [expected_empty_width, front_row.get_drop_reservation_empty_width()]
	)

	if commit_drop:
		front_row.commit_card_drop(left_stack_position, drag_data)
		await process_frame
		await process_frame
		_expect(
			left_target.get_squad_data().get_card_count() == 2
			and not front_row.has_drop_reservation()
			and not front_row.has_active_drop_preview(),
			"确认叠卡后移除预留空位并恢复真实阵容居中布局"
		)
	else:
		front_row.clear_drop_preview()
		await process_frame
		_expect(
			not front_row.has_drop_reservation()
			and not front_row.has_active_drop_preview(),
			"取消放置后移除预留空位和虚影"
		)
	await _dispose_main(main)


func _test_zero_unit_drop_without_reservation() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var cards := _make_cards(10)
	var expanded_target := front_row.add_squad(
		SquadData.from_cards(
			_typed_cards([cards[0], cards[1]]),
			SquadData.TwoCardLayout.EXPANDED
		),
		0
	)
	front_row.add_squad(
		SquadData.from_cards(
			_typed_cards([cards[2], cards[3]]),
			SquadData.TwoCardLayout.COMPACT
		),
		1
	)
	for index: int in 4:
		front_row.add_card(cards[4 + index], index + 2)
	await process_frame
	await process_frame
	var hand_drag := _hand_drag(cards[8])
	hand_drag["grab_local_position"] = Vector2(49.5, 68.0)
	hand_drag["preview_scale"] = Vector2.ONE
	var middle_pointer := Vector2(
		_pointer_for_stack_overlap(
			front_row, expanded_target, hand_drag, 60.0, true
		),
		68.0
	)
	_expect(
		front_row.get_used_unit_count() == 21
		and front_row.preview_card_drop(middle_pointer, hand_drag)
		and not front_row.has_drop_reservation()
		and ((front_row.get("_preview_intent") as Dictionary).get(
			"target_slot"
		) as BoardSlot) == expanded_target
		and ((front_row.get("_preview_intent") as Dictionary).get(
			"result_squad"
		) as SquadData).get_unit_count() == 5,
		"剩余 0 单元时手牌插入展开双卡中间走 +0 叠卡，不创建预留位"
	)
	await _dispose_main(main)

	main = await _create_main()
	front_row = main.get_node("%FrontRow") as BattlefieldRow
	cards = _make_cards(10)
	var triple_target := front_row.add_squad(
		SquadData.from_cards(_typed_cards([cards[0], cards[1], cards[2]])),
		0
	)
	front_row.add_squad(
		SquadData.from_cards(
			_typed_cards([cards[3], cards[4]]),
			SquadData.TwoCardLayout.COMPACT
		),
		1
	)
	for index: int in 4:
		front_row.add_card(cards[5 + index], index + 2)
	await process_frame
	await process_frame
	var same_squad_drag := _board_card_drag(front_row, triple_target, cards[1])
	same_squad_drag["grab_local_position"] = Vector2(49.5, 68.0)
	same_squad_drag["preview_scale"] = Vector2.ONE
	middle_pointer = Vector2(
		_pointer_for_stack_overlap(
			front_row, triple_target, same_squad_drag, 60.0, true
		),
		68.0
	)
	_expect(
		front_row.get_used_unit_count() == 21
		and front_row.preview_card_drop(middle_pointer, same_squad_drag)
		and not front_row.has_drop_reservation()
		and ((front_row.get("_preview_intent") as Dictionary).get(
			"result_squad"
		) as SquadData).get_effect_source() == cards[1],
		"满编三卡小队抽出后放回或调整层级同样不创建预留位"
	)
	await _dispose_main(main)


func _expect_layout(
	squad: SquadData,
	units: int,
	width: int,
	x_positions: Array,
	rune_counts: Array,
	label: String
) -> void:
	_expect(
		squad.get_unit_count() == units
		and squad.get_display_width() == width
		and squad.get_card_x_positions() == x_positions
		and squad.get_visible_rune_counts() == rune_counts,
		"%s布局的占位、宽度、X 与可见符文正确" % label
	)


func _create_main() -> Variant:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	return main


func _dispose_main(main: Variant) -> void:
	main.queue_free()
	await process_frame


func _make_cards(count: int) -> Array[CardData]:
	var cards: Array[CardData] = []
	for index: int in count:
		var card := CardData.new()
		card.id = StringName("test_%d" % index)
		card.display_name = "测试卡%d" % index
		card.runes.assign([
			CardData.ElementType.FIRE,
			CardData.ElementType.WATER,
			CardData.ElementType.WOOD,
		])
		cards.append(card)
	return cards


func _typed_cards(values: Array) -> Array[CardData]:
	var cards: Array[CardData] = []
	for value: Variant in values:
		cards.append(value as CardData)
	return cards


func _hand_drag(card_data: CardData, intent: Dictionary = {}) -> Dictionary:
	var data := {
		"kind": &"card",
		"card_data": card_data,
		"source_type": &"hand",
		"source_row": null,
		"source_slot": null,
	}
	if not intent.is_empty():
		data["drop_intent"] = intent
	return data


func _board_card_drag(
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


func _pointer_for_stack_overlap(
	row: BattlefieldRow,
	target: BoardSlot,
	drag_data: Dictionary,
	overlap: float,
	incoming_from_right: bool
) -> float:
	var target_left := row._get_slot_visual_left_x(target)
	var drag_width := row._get_drag_card_width(drag_data)
	var drag_left := (
		target_left + SquadView.CARD_SIZE.x - overlap
		if incoming_from_right
		else target_left + overlap - drag_width
	)
	var grab_local_position: Vector2 = drag_data.get(
		"grab_local_position",
		Vector2.ZERO
	)
	var preview_scale: Vector2 = drag_data.get("preview_scale", Vector2.ONE)
	return (
		drag_left
		+ grab_local_position.x * preview_scale.x
		* CardDragPreview.DRAG_SCALE_MULTIPLIER
	)


func _send_left_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame


func _send_mouse_motion(
	position: Vector2,
	relative: Vector2,
	button_mask: int
) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	event.button_mask = button_mask
	root.push_input(event, true)
	await process_frame


func _squad_drag(row: BattlefieldRow, slot: BoardSlot) -> Dictionary:
	return {
		"kind": &"squad",
		"card_data": slot.get_squad_data().get_effect_source(),
		"squad_data": slot.get_squad_data(),
		"source_type": &"board",
		"source_row": row,
		"source_slot": slot,
	}


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failure_count += 1
	push_error("FAIL: %s" % message)
