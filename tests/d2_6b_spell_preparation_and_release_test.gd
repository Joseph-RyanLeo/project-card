extends SceneTree

## D2-6B 用真实法术资源、OwnedCard、战斗控制器和 Main 场景验证准备/释放闭环。

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/ui/CardView.tscn")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const BattleControllerScript = preload("res://scripts/battle/battle_controller.gd")
const BattleEffectEvent = preload("res://scripts/battle/battle_effect_event.gd")
const BattleFormulaData = preload("res://scripts/battle/battle_formula_data.gd")
const SpellPreparationIconStyle = preload("res://scripts/ui/spell_preparation_icon_style.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const SIDE_BY_SIDE: CardData = preload("res://resources/cards/side_by_side.tres")
const BATTLE_FURY: CardData = preload("res://resources/cards/battle_fury.tres")
const HEALING_AURA: CardData = preload("res://resources/cards/support_healing_aura.tres")
const SACRED_SHIELD: CardData = preload("res://resources/cards/blessing_sacred_shield.tres")
const VOLLEY_ORDER: CardData = preload("res://resources/cards/volley_order.tres")
const RETURN_TO_BATTLEFIELD: CardData = preload("res://resources/cards/return_to_battlefield.tres")
const LAYOUT_MINION: CardData = preload("res://resources/cards/militia.tres")
const LAYOUT_EQUIPMENT: CardData = preload("res://resources/cards/starsea_ring.tres")
const LAYOUT_RESOURCE: CardData = preload("res://resources/cards/wood_element_shard.tres")
const SAVE_PATH: String = "/private/tmp/project-card-d2-6b-prepared-spells.json"

var failures: int = 0
var serial: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_spell_durability_number_layout()
	await _test_main_preparation_snapshot_and_save()
	await _test_main_revival_after_death_departure()
	_test_opening_pause_and_neighbor_spell()
	_test_opening_spell_alternation()
	_test_battle_fury_health_floor()
	_test_volley_and_revival_schedules()
	_test_prepared_spells_consume_empty_attempts()
	if failures == 0:
		print("D2-6B spell preparation and release checks passed.")
	else:
		push_error("D2-6B spell preparation and release checks failed: %d" % failures)
	quit(failures)


func _test_spell_durability_number_layout() -> void:
	var definitions: Array[CardData] = [
		BATTLE_FURY,
		SIDE_BY_SIDE,
		RETURN_TO_BATTLEFIELD,
		VOLLEY_ORDER,
	]
	var views: Array[CardView] = []
	for index: int in definitions.size():
		var owned := OwnedCard.new()
		owned.initialize(definitions[index], StringName("durability_layout_%d" % index), index)
		owned.spell_durability = 1 + index
		var view := CARD_VIEW_SCENE.instantiate() as CardView
		view.set_card_data(definitions[index])
		view.set_owned_card(owned)
		root.add_child(view)
		views.append(view)
	var duplicate := OwnedCard.new()
	duplicate.initialize(SIDE_BY_SIDE, &"durability_layout_duplicate", 5)
	duplicate.spell_durability = 1
	var duplicate_view := CARD_VIEW_SCENE.instantiate() as CardView
	duplicate_view.set_card_data(SIDE_BY_SIDE)
	duplicate_view.set_owned_card(duplicate)
	root.add_child(duplicate_view)
	views.append(duplicate_view)
	await process_frame
	var aligned := true
	for view: CardView in views:
		var displayed_durability := int(view.health_label.text)
		aligned = aligned and displayed_durability == view._owned_card.spell_durability
		aligned = aligned and view.health_label.position == CardView.get_health_value_position(displayed_durability)
	_expect(
		aligned and views[1].health_label.text == "2" and duplicate_view.health_label.text == "1",
		"四张正式法术按各OwnedCard剩余耐久定位桃心数字，同名实例互不共用耐久"
	)
	for view: CardView in views:
		view.queue_free()
	await process_frame
	var non_spell_views: Array[CardView] = []
	var layout_cards: Array[CardData] = [LAYOUT_MINION, LAYOUT_EQUIPMENT, LAYOUT_RESOURCE]
	for index: int in layout_cards.size():
		var owned := OwnedCard.new()
		owned.initialize(layout_cards[index], StringName("vitals_layout_%d" % index), index)
		var view := CARD_VIEW_SCENE.instantiate() as CardView
		view.set_card_data(owned.card_data)
		view.set_owned_card(owned)
		root.add_child(view)
		non_spell_views.append(view)
	await process_frame
	var other_layouts_match := true
	for view: CardView in non_spell_views:
		var health_value := int(view.health_label.text)
		other_layouts_match = other_layouts_match and (
			view.health_label.position == CardView.get_health_value_position(health_value)
		)
		if view.card_data.card_type == CardData.CardType.EQUIPMENT:
			other_layouts_match = other_layouts_match and (
				view.armor_label.position == CardView.get_armor_value_position(
					view.card_data.equipment_armor_delta
				)
			)
	_expect(
		non_spell_views.size() == 3 and other_layouts_match,
		"同一布局修正不改变真实随从、装备和资源卡的生命／护甲数字位置"
	)
	for view: CardView in non_spell_views:
		view.queue_free()
	await process_frame


func _test_main_preparation_snapshot_and_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	var main := await _new_main()
	var tray_background := main.spell_preparation_tray.get_child(0) as TextureRect
	_expect(
		main.spell_preparation_tray.size == Vector2(193.0, 310.0)
		and main.spell_preparation_tray.position == main.SPELL_PREPARATION_TRAY_POSITION
		and tray_background.texture.get_size() == main.spell_preparation_tray.size
		and main.spell_preparation_tray.z_index + tray_background.z_index < -60
		and main.spell_preparation_tray.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"法术板使用原比例原尺寸素材，位于种子下方并把背景绘制在战场底板后"
	)
	var master_bus_index := AudioServer.get_bus_index("Master")
	main.battle_volume_slider.value = 40.0
	var audio_volume_applied := is_equal_approx(
		AudioServer.get_bus_volume_linear(master_bus_index),
		0.4
	)
	main.battle_volume_slider.value = 25.0
	_expect(audio_volume_applied, "移动音量滑条仍实际更新全局 Master 总线音量")
	var spell := _owned_spell(main, SIDE_BY_SIDE, &"main_prepared_side_by_side")
	main._sync_legacy_collection_cards()
	var drag_data := {
		"kind": &"card",
		"card_data": SIDE_BY_SIDE,
		"owned_card": spell,
		"source_type": &"collection",
	}
	main.spell_preparation_tray.call("_drop_data", Vector2(20, 42), drag_data)
	var first_icon := main.spell_preparation_tray._icons_by_instance_id.get(spell.instance_id) as TextureButton
	var icon_column := SpellPreparationIconStyle.source_column_for_trigger(
		spell.card_data.spell_trigger_kind
	)
	_expect(
		first_icon != null
		and first_icon.texture_normal == SpellPreparationIconStyle.get_texture(icon_column, spell.card_data.rarity),
		"准备法术按启动类别与品级显示对应图标素材"
	)
	var unprepared_copy: OwnedCard = main.owned_card_collection.create_card(SIDE_BY_SIDE)
	main._sync_legacy_collection_cards()
	var prepared_page_ghost := _page_snapshot_ghost_state(main, spell)
	var unprepared_page_ghost := _page_snapshot_ghost_state(main, unprepared_copy)
	_expect(
		bool(prepared_page_ghost.get("found", false))
		and bool(prepared_page_ghost.get("ghost", false))
		and bool(unprepared_page_ghost.get("found", false))
		and not bool(unprepared_page_ghost.get("ghost", true)),
		"翻页快照只把已准备的OwnedCard实例保持虚影，同名未准备副本仍为实体"
	)
	await _test_prepared_spell_page_turn(main, spell)
	var refreshed_cards: Array[OwnedCard] = [spell]
	main.spell_preparation_tray.set_prepared_cards(refreshed_cards)
	_expect(
		main.spell_preparation_tray._icons_by_instance_id.get(spell.instance_id) == first_icon,
		"刷新准备状态会复用同一实例的图标节点"
	)
	var condition_a := _owned_spell(main, HEALING_AURA, &"condition_a")
	var condition_b := _owned_spell(main, SACRED_SHIELD, &"condition_b")
	var condition_c := _owned_spell(main, HEALING_AURA, &"condition_c")
	var original_order: Array[StringName] = main.prepared_spell_instance_ids.duplicate()
	main.prepared_spell_instance_ids.assign([
		spell.instance_id, condition_a.instance_id, condition_b.instance_id, condition_c.instance_id
	])
	main._refresh_spell_preparation_tray()
	main.spell_preparation_tray.call("_set_hovered_instance", condition_c.instance_id)
	_expect(
		main.spell_preparation_tray._hovered_column_index() == 1
		and main.spell_preparation_tray._hovered_row_index(1) == 2
		and main.spell_preparation_tray._hover_card_popup.get_owned_card() == condition_c,
		"准备顺序重排后仍以第三个真实OwnedCard实例驱动悬停卡面"
	)
	main.spell_preparation_tray.clear_hover_card()
	var cross_column_spell := _owned_spell(main, HEALING_AURA, &"cross_column_spell")
	var cross_column_data := {
		"kind": &"card",
		"card_data": HEALING_AURA,
		"owned_card": cross_column_spell,
		"source_type": &"collection",
	}
	var condition_column_preview := bool(main.spell_preparation_tray.call(
		"_can_drop_data", Vector2(150.0, 100.0), cross_column_data
	))
	var preview_index: int = main.spell_preparation_tray.insertion_index_for_global_position(
		main.spell_preparation_tray.get_global_transform_with_canvas() * Vector2(150.0, 100.0),
		cross_column_data
	)
	_expect(
		condition_column_preview
		and main.spell_preparation_tray._insertion_marker.position.x == 70.0
		and main.spell_preparation_tray._insertion_ghost.visible,
		"条件法术指针横穿到准备列时仍在条件列显示黄色位置条和目标虚影"
	)
	main.spell_preparation_tray.call("_drop_data", Vector2(150.0, 100.0), cross_column_data)
	_expect(
		main.prepared_spell_instance_ids.find(cross_column_spell.instance_id) == preview_index
		and main.prepared_spell_instance_ids[preview_index] == cross_column_spell.instance_id
		and not main.spell_preparation_tray._insertion_ghost.visible
		and not main.spell_preparation_tray._insertion_marker.visible,
		"横穿列后的实际提交顺序与预览索引一致，放下后清理目标预留位"
	)
	var move_condition_data := {
		"kind": &"card",
		"card_data": HEALING_AURA,
		"owned_card": condition_a,
		"source_type": &"spell_preparation",
	}
	main.spell_preparation_tray.begin_card_carry(condition_a.instance_id)
	var order_before_middle_preview: Array = main.prepared_spell_instance_ids.duplicate()
	var middle_accepted := bool(main.spell_preparation_tray.call(
		"_can_drop_data", Vector2(150.0, 79.0), move_condition_data
	))
	var preview_positions: Dictionary = main.spell_preparation_tray._target_positions
	_expect(
		middle_accepted
		and is_equal_approx(preview_positions[condition_c.instance_id].y - preview_positions[condition_a.instance_id].y, 42.0)
		and main.prepared_spell_instance_ids == order_before_middle_preview,
		"向下插入时后方图标让出完整42像素目标虚影，预览不修改实际顺序"
	)
	main.spell_preparation_tray.call("_drop_data", Vector2(150.0, 79.0), move_condition_data)
	main.spell_preparation_tray.end_card_carry()
	var settled_positions: Dictionary = main.spell_preparation_tray._target_positions
	_expect(
		is_equal_approx(settled_positions[condition_c.instance_id].y - settled_positions[condition_a.instance_id].y, 21.0)
		and not main.spell_preparation_tray._insertion_ghost.visible,
		"提交后目标虚影清除，下方图标恢复21像素半重叠布局"
	)
	main.spell_preparation_tray.begin_card_carry(condition_a.instance_id)
	var move_to_end_accepted := bool(main.spell_preparation_tray.call(
		"_can_drop_data", Vector2(150.0, 130.0), move_condition_data
	))
	main.spell_preparation_tray.call("_drop_data", Vector2(150.0, 130.0), move_condition_data)
	main.spell_preparation_tray.end_card_carry()
	_expect(
		move_to_end_accepted
		and main.prepared_spell_instance_ids.back() == condition_a.instance_id,
		"同列向下拖动按移除源卡后的最终顺序预览并提交，不发生二次索引偏移"
	)
	var scroll_cards: Array[OwnedCard] = []
	var scroll_order: Array[StringName] = []
	for card_index: int in 15:
		var scroll_card := _owned_spell(main, HEALING_AURA, StringName("scroll_spell_%d" % card_index))
		scroll_cards.append(scroll_card)
		scroll_order.append(scroll_card.instance_id)
	scroll_order.insert(0, spell.instance_id)
	main.prepared_spell_instance_ids.assign(scroll_order)
	main.spell_preparation_capacity = 20
	main._refresh_spell_preparation_tray()
	var condition_scroll := main.spell_preparation_tray._scrolls[1] as ScrollContainer
	await process_frame
	condition_scroll.scroll_vertical = 70
	await process_frame
	var scroll_incoming := _owned_spell(main, HEALING_AURA, &"scroll_incoming_spell")
	var scroll_drag_data := {"owned_card": scroll_incoming, "source_type": &"collection"}
	var scroll_preview := bool(main.spell_preparation_tray.call(
		"_can_drop_data", Vector2(150.0, 100.0), scroll_drag_data
	))
	var expected_scroll_index := clampi(
		floori((63.0 + condition_scroll.scroll_vertical + 10.5) / 21.0),
		0,
		scroll_cards.size()
	) + 1
	_expect(
		condition_scroll.scroll_vertical > 0
		and main.spell_preparation_tray._lists[1].size.y >= 15 * 21.0 + 21.0
		and scroll_preview
		and main.spell_preparation_tray._preview_index == expected_scroll_index,
		"滚动到条件列中段时仍按可见指针行命中，内容高度保留最后一张完整图标"
	)
	main.spell_preparation_tray.call("_clear_insertion_preview")
	main.prepared_spell_instance_ids.assign(original_order)
	main.spell_preparation_capacity = 10
	main._refresh_spell_preparation_tray()
	for scroll_card: OwnedCard in scroll_cards:
		main.owned_card_collection.remove_by_instance_id(scroll_card.instance_id)
	main.owned_card_collection.remove_by_instance_id(scroll_incoming.instance_id)
	var low_durability_spell := _owned_spell(main, SIDE_BY_SIDE, &"low_durability_spell")
	var high_durability_spell := _owned_spell(main, SIDE_BY_SIDE, &"high_durability_spell")
	low_durability_spell.spell_durability = 1
	high_durability_spell.spell_durability = 3
	var low_durability_view := CARD_VIEW_SCENE.instantiate() as CardView
	var high_durability_view := CARD_VIEW_SCENE.instantiate() as CardView
	root.add_child(low_durability_view)
	root.add_child(high_durability_view)
	low_durability_view.set_card_data(SIDE_BY_SIDE)
	high_durability_view.set_card_data(SIDE_BY_SIDE)
	low_durability_view.set_owned_card(low_durability_spell)
	high_durability_view.set_owned_card(high_durability_spell)
	_expect(
		low_durability_view.health_icon.visible
		and high_durability_view.health_icon.visible
		and low_durability_view.health_label.text == "1"
		and high_durability_view.health_label.text == "3",
		"两张同定义法术卡的桃心分别显示OwnedCard耐久且不修改共享卡牌定义"
	)
	low_durability_view.queue_free()
	high_durability_view.queue_free()
	var early_prepared := _owned_spell(main, VOLLEY_ORDER, &"prepared_at_eight_seconds")
	var late_prepared := _owned_spell(main, RETURN_TO_BATTLEFIELD, &"prepared_at_fifteen_seconds")
	var late_drag_data := {"owned_card": late_prepared, "source_type": &"collection"}
	var early_drag_data := {"owned_card": early_prepared, "source_type": &"collection"}
	var late_drop_preview := bool(main.spell_preparation_tray.call(
		"_can_drop_data", Vector2(150.0, 42.0), late_drag_data
	))
	var late_preview_index: int = main.spell_preparation_tray._preview_index
	main.spell_preparation_tray.call("_drop_data", Vector2(150.0, 42.0), late_drag_data)
	var early_drop_preview := bool(main.spell_preparation_tray.call(
		"_can_drop_data", Vector2(150.0, 250.0), early_drag_data
	))
	var early_preview_index: int = main.spell_preparation_tray._preview_index
	main.spell_preparation_tray.call("_drop_data", Vector2(150.0, 250.0), early_drag_data)
	_expect(
		main.prepared_spell_instance_ids.slice(1) == [early_prepared.instance_id, late_prepared.instance_id]
		and late_drop_preview
		and early_drop_preview
		and late_preview_index == 1
		and early_preview_index == 1
		and is_equal_approx(main.battle_controller.get_elapsed_spell_trigger_seconds(VOLLEY_ORDER), 8.0)
		and is_equal_approx(main.battle_controller.get_elapsed_spell_trigger_seconds(RETURN_TO_BATTLEFIELD), 15.0),
		"準備類按效果定義中的秒數排序，时序读取8秒与15秒效果参数"
	)
	main._on_spell_preparation_drop_requested({"owned_card": late_prepared}, 1)
	_expect(
		main.prepared_spell_instance_ids.slice(1) == [early_prepared.instance_id, late_prepared.instance_id]
		and main.play_area_label.text.contains("只能调整相同秒数"),
		"跨准备秒数排序明确提示并拒绝，原存储顺序不变"
	)
	main._on_collection_card_dropped(
		{"source_type": &"spell_preparation", "owned_card": late_prepared}, Vector2.ZERO
	)
	main._on_collection_card_dropped(
		{"source_type": &"spell_preparation", "owned_card": early_prepared}, Vector2.ZERO
	)
	var duplicate_spell := _owned_spell(main, SIDE_BY_SIDE, &"main_prepared_duplicate")
	var duplicate_drag_data := {
		"kind": &"card",
		"card_data": SIDE_BY_SIDE,
		"owned_card": duplicate_spell,
		"source_type": &"collection",
	}
	main.spell_preparation_tray.set_capacity(1)
	_expect(
		not main.spell_preparation_tray.call("_can_drop_data", Vector2(20, 42), duplicate_drag_data),
		"准备栏达到容量后拒绝新的法术实例"
	)
	_expect(
		not main.spell_preparation_tray.call("_can_drop_data", Vector2(20, 10), drag_data),
		"标题区等非槽位位置拒绝法术投放"
	)
	main.spell_preparation_tray.set_capacity(10)
	main._sync_legacy_collection_cards()
	main._on_spell_preparation_drop_requested(duplicate_drag_data, 1)
	var second_icon := main.spell_preparation_tray._icons_by_instance_id.get(duplicate_spell.instance_id) as TextureButton
	main._on_spell_preparation_drop_requested(duplicate_drag_data, 0)
	_expect(
		main.prepared_spell_instance_ids == [duplicate_spell.instance_id, spell.instance_id]
		and main.spell_preparation_tray._icons_by_instance_id.get(spell.instance_id) == first_icon
		and main.spell_preparation_tray._icons_by_instance_id.get(duplicate_spell.instance_id) == second_icon
		and first_icon.has_meta("sort_tween")
		and (first_icon.get_meta("sort_tween") as Tween).is_running(),
		"同类排序按OwnedCard实例区分并平滑复用原图标"
	)
	main._on_collection_card_dropped(
		{"source_type": &"spell_preparation", "owned_card": duplicate_spell},
		Vector2.ZERO
	)
	_expect(
		main.prepared_spell_instance_ids == [spell.instance_id]
		and main.spell_preparation_tray._icons_by_instance_id.get(spell.instance_id) == first_icon,
		"取回副本后原准备实例图标仍保留身份"
	)
	var click_spell := _owned_spell(main, SIDE_BY_SIDE, &"main_click_prepared_spell")
	main._sync_legacy_collection_cards()
	var click_drag_data := {
		"kind": &"card",
		"card_data": SIDE_BY_SIDE,
		"owned_card": click_spell,
		"source_type": &"collection",
	}
	main._on_click_carry_requested(click_drag_data, Vector2(480.0, 220.0))
	var tray_drop_point: Vector2 = main.spell_preparation_tray.get_global_transform_with_canvas() * Vector2(20.0, 42.0)
	main._commit_click_carry(tray_drop_point)
	var click_icon := main.spell_preparation_tray._icons_by_instance_id.get(click_spell.instance_id) as TextureButton
	_expect(
		main.prepared_spell_instance_ids.has(click_spell.instance_id)
		and main.spell_preparation_tray._drop_transitions.has(click_spell.instance_id)
		and click_icon != null,
		"点按携带在释放位置衔接卡牌到图标的渐变动画"
	)
	for _frame_index: int in 24:
		await process_frame
	_expect(
		is_equal_approx(click_icon.modulate.a, 1.0),
		"卡牌渐隐完成后目标法术图标恢复完整不透明度"
	)
	_expect(
		not main.spell_preparation_tray._drop_transitions.has(click_spell.instance_id),
		"法术图标过渡结束后清理临时动画状态"
	)
	main._on_collection_card_dropped(
		{"source_type": &"spell_preparation", "owned_card": click_spell},
		Vector2.ZERO
	)
	var initial_minion: OwnedCard
	for candidate: OwnedCard in main.owned_card_collection.get_cards():
		if candidate.card_data.card_type == CardData.CardType.MINION:
			initial_minion = candidate
			break
	if initial_minion != null:
		main.front_row.add_squad(SquadData.from_owned_card(initial_minion), 0)
	_expect(
		main.prepared_spell_instance_ids == [spell.instance_id]
		and main.spell_preparation_tray.get_child_count() > 0,
		"真实准备栏按法术实例接收拖放并保留唯一实例ID"
	)
	var return_drag_data := drag_data.duplicate()
	return_drag_data["source_type"] = &"spell_preparation"
	main._on_collection_card_dropped(return_drag_data, Vector2.ZERO)
	_expect(main.prepared_spell_instance_ids.is_empty(), "准备栏法术拖回收藏会解除准备状态")
	main.spell_preparation_tray.call("_drop_data", Vector2(20, 42), drag_data)
	_expect(main.save_run_to_path(SAVE_PATH) == OK, "准备顺序可写入真实本局JSON存档")
	_expect(main.start_battle(8123, false), "准备快照可带入正式战斗入口")
	_expect(
		main.battle_controller._opening_spell_active
		and is_zero_approx(main.battle_controller.elapsed_seconds),
		"即时法术开场阶段保持战斗时钟为0"
	)
	main.battle_controller.advance_time(0.30)
	_expect(
		main.battle_controller._opening_spell_active
		and is_zero_approx(main.battle_controller.elapsed_seconds),
		"开场卡面演出期间行动冷却与战斗计时未推进"
	)
	main.battle_controller.advance_time(0.30)
	_expect(
		not main.battle_controller._opening_spell_active
		and is_zero_approx(main.battle_controller.elapsed_seconds),
		"开场演出完成后继续战斗，但开场期间不消费战斗秒数"
	)
	_expect(main.restart_battle(), "重开战斗可恢复战前准备快照")
	_expect(
		main.prepared_spell_instance_ids == [spell.instance_id],
		"重开保留法术准备顺序且未提前扣耐久"
	)
	_expect(not main.get_tree().paused, "普通即时法术动画不接管战斗暂停")
	main.current_phase = main.GamePhase.BATTLE
	main._on_battle_pause_button_pressed()
	main._open_card_inspection(initial_minion.card_data, initial_minion)
	main._close_card_inspection(true)
	_expect(main.get_tree().paused, "关闭只读检视只释放检视暂停，不解除玩家手动暂停")
	main.set_special_spell_pause_requested(true)
	main.set_special_spell_pause_requested(false)
	_expect(main.get_tree().paused, "特殊法术暂停接口与手动暂停分别持有暂停状态")
	main._on_battle_pause_button_pressed()
	_expect(not main.get_tree().paused, "最后一个暂停持有者释放后战斗恢复")
	main.queue_free()
	await process_frame
	var restored := await _new_main()
	_expect(restored.load_run_from_path(SAVE_PATH), "真实Main场景可以读回准备法术存档")
	_expect(
		restored.prepared_spell_instance_ids == [spell.instance_id]
		and restored.owned_card_collection.get_by_instance_id(spell.instance_id) != null,
		"读档恢复同一OwnedCard实例及准备顺序"
	)
	var restored_spell := restored.owned_card_collection.get_by_instance_id(spell.instance_id) as OwnedCard
	_expect(restored.start_battle(8123, false), "读档后的准备顺序可以再次进入战斗")
	var settlement: Dictionary = restored.settle_current_battle()
	var repeated_settlement: Dictionary = restored.settle_current_battle()
	_expect(
		settlement.get("success", false)
		and repeated_settlement.get("status") == "already_committed"
		and restored_spell.spell_durability == 2
		and restored.prepared_spell_instance_ids.is_empty(),
		"正常结算对准备法术扣1次耐久并清空准备栏，重复提交不重扣"
	)
	restored.queue_free()
	await process_frame


func _test_main_revival_after_death_departure() -> void:
	var main := await _new_main()
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]:
		row.clear_squads()
	var doomed_card := _card(&"revived_after_departure", CardData.ActionType.MELEE, 20, 60.0)
	var survivor_card := _card(&"revival_survivor", CardData.ActionType.MELEE, 100, 60.0)
	var enemy_card := _card(&"revival_enemy", CardData.ActionType.MELEE, 100, 60.0)
	main.front_row.add_card(doomed_card, 0)
	main.front_row.add_card(survivor_card, 1)
	main.enemy_front_row.add_card(enemy_card, 0)
	var revive_spell := _owned_spell(main, RETURN_TO_BATTLEFIELD, &"main_revival_after_departure")
	main.prepared_spell_instance_ids.assign([revive_spell.instance_id])
	main._refresh_spell_preparation_tray()
	_expect(main.start_battle(7123, false), "真实主场景启动带重返战场的战斗")
	var revived_state := main.battle_controller.player_states[0] as BattleSquadState
	var enemy_state := main.battle_controller.enemy_states[0] as BattleSquadState
	var death_event := _damage_event(enemy_state, revived_state, 1000.0, true)
	main.battle_controller._apply_effect_event(death_event)
	main.battle_controller._finalize_batch()
	await create_timer(0.65).timeout
	_expect(
		not revived_state.alive and main.front_row.get_squad_count() == 1
		and not main._battle_state_slots.has(revived_state),
		"真实死亡后卡面完成退场并从战场槽映射中移除"
	)
	main.battle_controller.advance_time(15.0)
	var revived_slot := main._battle_state_slots.get(revived_state) as BoardSlot
	_expect(
		revived_state.alive and is_instance_valid(revived_slot)
		and revived_slot.get_parent() == main.front_row.squad_row
		and revived_slot.get_squad_data().horizontal_cards.has(doomed_card)
		and is_equal_approx(revived_state.current_health, 10.0),
		"第15秒真实复活重新创建並映射卡面，恢复50%生命"
	)
	if revived_state.alive:
		revived_state.remaining_cooldown = 0.01
		main.battle_controller.advance_time(0.02)
	_expect(
		revived_state.alive and revived_state.remaining_cooldown > 9.0,
		"重新入场的小队冷却到期后正常行动并重置冷却"
	)
	main.queue_free()
	await process_frame


func _test_opening_pause_and_neighbor_spell() -> void:
	var spell := _owned_spell(null, SIDE_BY_SIDE, &"side_by_side_instance")
	var left := _card(&"side_left", CardData.ActionType.MELEE, 50, 9.0)
	var receiver := _card(&"side_receiver", CardData.ActionType.MELEE, 50, 9.0)
	var enemy := _card(&"side_enemy", CardData.ActionType.MELEE, 50, 9.0)
	var controller := _start_controller(
		[
			_entry(SquadData.from_card(left), &"player_front", 0, 9.0),
			_entry(SquadData.from_card(receiver), &"player_front", 1, 9.0),
		],
		[_entry(SquadData.from_card(enemy), &"enemy_front", 0, 9.0)],
		[spell]
	)
	controller.advance_time(0.60)
	_expect(
		not controller._opening_spell_active and is_zero_approx(controller.elapsed_seconds),
		"即时卡面与施法效果串行完成，开场阶段结束时战斗时间仍是0"
	)
	var target := controller.player_states[1]
	var source := controller.enemy_states[0]
	var event := _damage_event(source, target, 3.0, true)
	controller._apply_effect_event(event)
	_expect(
		is_equal_approx(target.current_health, 48.0),
		"并肩作战只在施法时友军仍有乡邻时把攻击伤害降低1"
	)
	_free_controller(controller)


func _test_opening_spell_alternation() -> void:
	var player_first := _owned_spell(null, SIDE_BY_SIDE, &"player_spell_first")
	var player_second := _owned_spell(null, SIDE_BY_SIDE, &"player_spell_second")
	var enemy_spell := _owned_spell(null, SIDE_BY_SIDE, &"enemy_spell_first")
	var player := _card(&"alternating_player", CardData.ActionType.MELEE, 50, 60.0)
	var enemy := _card(&"alternating_enemy", CardData.ActionType.MELEE, 50, 60.0)
	var controller := BattleControllerScript.new()
	root.add_child(controller)
	controller.use_projectile_timing = false
	var cast_order: Array[StringName] = []
	controller.spell_cast_started.connect(func(spell: OwnedCard, _generation: int, _duration: float) -> void:
		cast_order.append(spell.instance_id)
	)
	controller.start_battle(
		[_entry(SquadData.from_card(player), &"player_front", 0, 60.0)],
		[_entry(SquadData.from_card(enemy), &"enemy_front", 0, 60.0)],
		7101,
		false,
		&"d2_6b_alternating_spells",
		[player_first, player_second],
		[enemy_spell]
	)
	controller.advance_time(2.0)
	_expect(
		cast_order == [player_first.instance_id, enemy_spell.instance_id, player_second.instance_id]
		and controller._side_by_side_grants.size() == 3,
		"双方开场即时法术按玩家先手逐张交替，效果归属各自队伍"
	)
	_free_controller(controller)


func _test_battle_fury_health_floor() -> void:
	var spell := _owned_spell(null, BATTLE_FURY, &"battle_fury_instance")
	var protected := _card(&"fury_target", CardData.ActionType.MELEE, 10, 9.0)
	var ally := _card(&"fury_ally", CardData.ActionType.MELEE, 10, 9.0)
	var enemy := _card(&"fury_enemy", CardData.ActionType.MELEE, 50, 9.0)
	var controller := _start_controller(
		[
			_entry(SquadData.from_card(protected), &"player_front", 0, 9.0),
			_entry(SquadData.from_card(ally), &"player_front", 1, 9.0),
		],
		[_entry(SquadData.from_card(enemy), &"enemy_front", 0, 9.0)],
		[spell]
	)
	var target := controller.player_states[0]
	var event := _damage_event(controller.enemy_states[0], target, 20.0, true)
	controller._apply_effect_event(event)
	_expect(
		is_equal_approx(target.current_health, 1.0)
		and is_equal_approx(controller.player_states[1].current_health, 10.0)
		and controller.notify_spell_triggered(spell.instance_id, 0) == false,
		"战斗怒火在致死写入前把全体友军生命下限设为1，启咒记录不重复"
	)
	_expect(
		is_equal_approx(event.effective_amount, 9.0),
		"被阻止的生命伤害不会在保护结束时追溯结算"
	)
	controller.advance_time(5.1)
	controller._apply_effect_event(_damage_event(controller.enemy_states[0], target, 20.0, true))
	controller._finalize_batch()
	_expect(
		not target.alive and target.current_health <= 0.0,
		"战斗怒火5秒到期后不追溯旧伤害，新的致死伤害正常生效"
	)
	_free_controller(controller)


func _test_volley_and_revival_schedules() -> void:
	var volley := _owned_spell(null, VOLLEY_ORDER, &"volley_spell_instance")
	var ranged := _card(&"back_ranged", CardData.ActionType.RANGED, 100, 60.0)
	var enemy := _card(&"volley_enemy", CardData.ActionType.MELEE, 100, 60.0)
	var volley_controller := _start_controller(
		[_entry(SquadData.from_card(ranged), &"player_back", 0, 60.0)],
		[_entry(SquadData.from_card(enemy), &"enemy_front", 0, 60.0)],
		[volley]
	)
	var ranged_state := volley_controller.player_states[0]
	var reinforcement := BattleModifier.new()
	reinforcement.stat = BattleModifier.Stat.REINFORCEMENT
	reinforcement.mode = BattleModifier.Mode.ADD
	reinforcement.value = 3.0
	ranged_state.modifiers.add_modifier(reinforcement)
	volley_controller.advance_time(8.0)
	_expect(
		is_zero_approx(ranged_state.cooldown_progress)
		and is_equal_approx(ranged_state.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT), 0.0)
		and volley_controller._elapsed_spell_attempted.has(volley.instance_id),
		"齐射令第8秒只尝试一次远程立即行动，并消耗强化、重置冷却"
	)
	_free_controller(volley_controller)

	var revive := _owned_spell(null, RETURN_TO_BATTLEFIELD, &"revive_spell_instance")
	var dead_card := _card(&"revive_dead", CardData.ActionType.MELEE, 20, 60.0)
	var living_enemy := _card(&"revive_enemy", CardData.ActionType.MELEE, 100, 60.0)
	var revive_controller := _start_controller(
		[_entry(SquadData.from_card(dead_card), &"player_front", 0, 60.0)],
		[_entry(SquadData.from_card(living_enemy), &"enemy_front", 0, 60.0)],
		[revive]
	)
	var dead_state := revive_controller.player_states[0]
	dead_state.current_health = 0.0
	dead_state.alive = false
	revive_controller._death_history.append({"state": dead_state, "sequence": 1, "time": 0.0})
	revive_controller.advance_time(15.0)
	_expect(
		dead_state.alive
		and is_equal_approx(dead_state.current_health, 10.0)
		and revive_controller._elapsed_spell_attempted.has(revive.instance_id),
		"重返战场在第15秒复活最近死亡非衍生友军至50%生命"
	)
	_free_controller(revive_controller)


func _test_prepared_spells_consume_empty_attempts() -> void:
	var volley := _owned_spell(null, VOLLEY_ORDER, &"empty_volley_spell")
	var melee := _card(&"empty_volley_melee", CardData.ActionType.MELEE, 100, 60.0)
	var enemy := _card(&"empty_volley_enemy", CardData.ActionType.MELEE, 100, 60.0)
	var controller := _start_controller(
		[_entry(SquadData.from_card(melee), &"player_front", 0, 60.0)],
		[_entry(SquadData.from_card(enemy), &"enemy_front", 0, 60.0)],
		[volley]
	)
	controller.advance_time(8.0)
	var state := controller.player_states[0]
	state.row_key = &"player_back"
	state.set_runtime_action_type(CardData.ActionType.RANGED)
	controller.advance_time(1.0)
	_expect(
		controller._elapsed_spell_attempted.has(volley.instance_id)
		and is_equal_approx(state.remaining_cooldown, 51.0),
		"齐射令第8秒没有合法目标时消耗机会且稍后不补放"
	)
	_free_controller(controller)

	var revive := _owned_spell(null, RETURN_TO_BATTLEFIELD, &"empty_revival_spell")
	var friend := _card(&"empty_revival_friend", CardData.ActionType.MELEE, 20, 60.0)
	var foe := _card(&"empty_revival_foe", CardData.ActionType.MELEE, 100, 60.0)
	var revive_controller := _start_controller(
		[_entry(SquadData.from_card(friend), &"player_front", 0, 60.0)],
		[_entry(SquadData.from_card(foe), &"enemy_front", 0, 60.0)],
		[revive]
	)
	revive_controller.advance_time(15.0)
	var later_dead_state := revive_controller.player_states[0]
	later_dead_state.current_health = 0.0
	later_dead_state.alive = false
	revive_controller._death_history.append({"state": later_dead_state, "sequence": 2, "time": 15.0})
	revive_controller.advance_time(1.0)
	_expect(
		revive_controller._elapsed_spell_attempted.has(revive.instance_id)
		and not later_dead_state.alive,
		"重返战场第15秒无目标时消耗机会，之后出现死亡目标也不重试"
	)
	_free_controller(revive_controller)

	var relocated_spell := _owned_spell(null, RETURN_TO_BATTLEFIELD, &"occupied_position_revival")
	var original_position := _card(&"occupied_original_position", CardData.ActionType.MELEE, 20, 60.0)
	var occupying_ally := _card(&"occupying_ally", CardData.ActionType.MELEE, 100, 60.0)
	var occupied_controller := _start_controller(
		[
			_entry(SquadData.from_card(original_position), &"player_front", 0, 60.0),
			_entry(SquadData.from_card(occupying_ally), &"player_front", 0, 60.0),
		],
		[_entry(SquadData.from_card(foe), &"enemy_front", 0, 60.0)],
		[relocated_spell]
	)
	var relocated_state := occupied_controller.player_states[0]
	relocated_state.current_health = 0.0
	relocated_state.alive = false
	occupied_controller._death_history.append({"state": relocated_state, "sequence": 1, "time": 0.0})
	occupied_controller.advance_time(15.0)
	_expect(
		relocated_state.alive and relocated_state.formation_index == 1,
		"重返战场原位被占用时改放到同排右侧"
	)
	_free_controller(occupied_controller)

	var no_space_spell := _owned_spell(null, RETURN_TO_BATTLEFIELD, &"full_row_revival")
	var full_row_players: Array[Dictionary] = []
	for index: int in 8:
		var full_row_card := _card(
			StringName("full_row_%d" % index), CardData.ActionType.MELEE, 100, 60.0
		)
		full_row_players.append(
			_entry(SquadData.from_card(full_row_card), &"player_front", index, 60.0)
		)
	var full_row_controller := _start_controller(
		full_row_players,
		[_entry(SquadData.from_card(foe), &"enemy_front", 0, 60.0)],
		[no_space_spell]
	)
	var space_blocked_state := full_row_controller.player_states[0]
	space_blocked_state.current_health = 0.0
	space_blocked_state.alive = false
	full_row_controller._death_history.append({"state": space_blocked_state, "sequence": 1, "time": 0.0})
	full_row_controller.advance_time(15.0)
	_expect(
		full_row_controller._elapsed_spell_attempted.has(no_space_spell.instance_id)
		and not space_blocked_state.alive,
		"整排无复活空间时消耗本次机会而不超容量复活"
	)
	_free_controller(full_row_controller)


func _page_snapshot_ghost_state(main: Node, wanted: OwnedCard) -> Dictionary:
	var displayed_cards: Array[CardData] = main.get_displayed_collection_cards()
	var filtered_index := -1
	for index: int in displayed_cards.size():
		if main._get_owned_card_for_collection_index(displayed_cards, index) == wanted:
			filtered_index = index
			break
	if filtered_index < 0:
		return {"found": false, "ghost": false}
	var page_index: int = filtered_index / main.COLLECTION_SLOTS_PER_PAGE
	var page_side: int = (filtered_index % main.COLLECTION_SLOTS_PER_PAGE) / 6
	var page := main._create_page_turn_snapshot(
		page_side,
		page_index,
		displayed_cards,
		main._get_regular_page_texture(page_side),
		true
	) as Control
	var card_layer := page.get_node("CardLayer") as Control
	var result := {"found": false, "ghost": false}
	for slot: Control in card_layer.get_children():
		if slot.has_meta("owned_card") and slot.get_meta("owned_card") == wanted:
			result["found"] = true
			result["ghost"] = bool(slot.get_meta("is_deployed_ghost"))
	page.free()
	return result


func _test_prepared_spell_page_turn(main: Node, wanted: OwnedCard) -> void:
	var displayed_cards: Array[CardData] = main.get_displayed_collection_cards()
	var filtered_index := _find_owned_collection_index(main, displayed_cards, wanted)
	if filtered_index < 0:
		_expect(false, "已准备法术位于当前可翻收藏结果中")
		return
	var origin_spread: int = filtered_index / main.COLLECTION_SLOTS_PER_PAGE
	var target_spread := origin_spread + 1
	if target_spread >= main.get_collection_spread_count():
		target_spread = origin_spread - 1
	if target_spread < 0:
		_expect(false, "有相邻收藏页可用于真实翻页测试")
		return
	main.current_collection_page = origin_spread
	main._build_collection_cards()
	await process_frame
	_expect(
		_visible_collection_ghost_state(main, wanted).get("ghost", false),
		"翻页前真实收藏卡位显示已准备法术虚影"
	)
	_expect(main.turn_collection_page(target_spread, &"direct"), "已准备法术所在展开页启动翻页")
	await process_frame
	_expect(
		_turn_overlay_ghost_state(main, wanted).get("ghost", false),
		"翻页动画中的固定页与活动页快照继续显示同一法术实例虚影"
	)
	_expect(not main.turn_collection_page(origin_spread, &"direct"), "动画未结束时快速再次翻页被阻止")
	await create_timer(main.PAGE_TURN_HALF_DURATION * 2.0 + 0.15).timeout
	_expect(main.turn_collection_page(origin_spread, &"direct"), "可向反方向翻回法术所在展开页")
	await process_frame
	_expect(
		_turn_overlay_ghost_state(main, wanted).get("ghost", false),
		"反向翻页动画快照仍按OwnedCard准备状态显示虚影"
	)
	await create_timer(main.PAGE_TURN_HALF_DURATION * 2.0 + 0.15).timeout
	_expect(
		_visible_collection_ghost_state(main, wanted).get("ghost", false),
		"翻页结束后重建的真实收藏卡仍保持已准备虚影"
	)
	main._on_search_text_changed(wanted.card_data.display_name)
	await process_frame
	_expect(
		_visible_collection_ghost_state(main, wanted).get("ghost", false),
		"搜索筛选重建收藏页后已准备法术仍按实例显示虚影"
	)
	main._on_search_text_changed("")
	await process_frame
	main.current_collection_page = 0
	main._build_collection_cards()
	await process_frame


func _find_owned_collection_index(main: Node, cards: Array[CardData], wanted: OwnedCard) -> int:
	for index: int in cards.size():
		if main._get_owned_card_for_collection_index(cards, index) == wanted:
			return index
	return -1


func _visible_collection_ghost_state(main: Node, wanted: OwnedCard) -> Dictionary:
	for slot: Control in main._get_collection_card_slots():
		if slot.get_meta("owned_card", null) != wanted:
			continue
		return {"found": true, "ghost": is_equal_approx(slot.get_child(0).modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA)}
	return {"found": false, "ghost": false}


func _turn_overlay_ghost_state(main: Node, wanted: OwnedCard) -> Dictionary:
	var overlay := main._page_turn_overlay as Control
	if not is_instance_valid(overlay):
		return {"found": false, "ghost": false}
	for page: Control in overlay.get_children():
		var layer := page.get_node_or_null("CardLayer") as Control
		if layer == null:
			continue
		for slot: Control in layer.get_children():
			if slot.get_meta("owned_card", null) != wanted:
				continue
			return {"found": true, "ghost": is_equal_approx(slot.get_child(0).modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA)}
	return {"found": false, "ghost": false}


func _new_main() -> Node:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	return main


func _owned_spell(main: Node, definition: CardData, instance_id: StringName) -> OwnedCard:
	serial += 1
	if main != null:
		return main.owned_card_collection.create_card(definition)
	var spell := OwnedCard.new()
	spell.initialize(definition, instance_id, serial)
	return spell


func _card(card_id: StringName, action_type: CardData.ActionType, health: int, cooldown: float) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = String(card_id)
	card.card_type = CardData.CardType.MINION
	card.action_type = action_type
	card.base_value = 2
	card.max_health = health
	card.cooldown_seconds = cooldown
	return card


func _entry(squad: SquadData, row: StringName, index: int, cooldown: float) -> Dictionary:
	return {"squad_data": squad, "row_key": row, "formation_index": index, "base_cooldown_override": cooldown}


func _start_controller(
	players: Array[Dictionary],
	enemies: Array[Dictionary],
	spells: Array[OwnedCard],
	enemy_spells: Array[OwnedCard] = []
) -> BattleController:
	var controller := BattleControllerScript.new()
	root.add_child(controller)
	controller.use_projectile_timing = false
	controller.start_battle(players, enemies, 7101, false, &"d2_6b_test_battle", spells, enemy_spells)
	return controller


func _damage_event(
	source: BattleSquadState,
	target: BattleSquadState,
	amount: float,
	is_base_action: bool
) -> BattleEffectEvent:
	var event := BattleEffectEvent.new()
	event.source = source
	event.target = target
	event.action_type = CardData.ActionType.MELEE
	event.effect_kind = BattleEffectEvent.EffectKind.DAMAGE
	event.exact_amount = amount
	event.is_base_action = is_base_action
	event.uses_attack_type_multiplier = false
	event.formula = BattleFormulaData.create("伤害", CardData.ActionType.MELEE, amount, 1.0, 1.0, source, target)
	return event


func _free_controller(controller: BattleController) -> void:
	controller.clear_battle()
	controller.free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
