extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_test_instances_and_attributes()
	_test_battle_rules()
	await _test_main_drag_and_save()
	print("D2-6A celestial indicator checks: %d failures" % failures)
	quit(failures)

func _item(kind: CelestialIndicator.Kind, id: StringName) -> CelestialIndicator:
	var item := CelestialIndicator.new()
	item.kind = kind
	item.instance_id = id
	return item

func _card(id: StringName) -> CardData:
	var card := CardData.new()
	card.id = id
	card.base_value = 2
	card.max_health = 100
	card.cooldown_seconds = 9.9
	return card

func _entry(squad: SquadData, index: int, enemy: bool = false) -> Dictionary:
	return {"squad_data": squad, "row_key": &"enemy_front" if enemy else &"player_front", "formation_index": index}

func _test_instances_and_attributes() -> void:
	var squad := SquadData.from_card(_card(&"all_tokens"))
	for kind: int in CelestialIndicator.Kind.values():
		_expect(squad.attach_indicator(_item(kind as CelestialIndicator.Kind, StringName("token_%d" % kind)), Vector2(49, 60), kind + 1), "不同种类可共存：%s" % CelestialIndicator.NAMES[kind])
	_expect(squad.get_effective_action_base_value() == 6 and squad.get_effective_max_health() == 106 and squad.get_effective_base_armor() == 8, "日月星基础属性直接进入小队有效属性")
	_expect(not squad.attach_indicator(_item(CelestialIndicator.Kind.MOON, &"duplicate_moon"), Vector2(49, 60), 9), "同一个小队不能重复附加同名月亮")
	var copy := squad.duplicate_squad()
	copy.detach_indicator(&"token_0")
	_expect(squad.has_indicator(CelestialIndicator.Kind.MOON) and not copy.has_indicator(CelestialIndicator.Kind.MOON), "战斗及快照副本变更不会污染准备阵容")
	var earlier := SquadData.from_card(_card(&"earlier"))
	earlier.attach_indicator(_item(CelestialIndicator.Kind.STAR, &"earlier_star"), Vector2(40, 60), 0)
	squad.merge_indicators_from(earlier)
	var kept := false
	for attachment: Dictionary in squad.indicator_attachments:
		kept = kept or (attachment["indicator"] as CelestialIndicator).instance_id == &"earlier_star"
	_expect(kept and squad.indicator_attachments.size() == 3, "合并同名指示物保留先附加者，同时保留不同名指示物")
	var restored := SquadData.new()
	_expect(restored.restore_indicators(squad.capture_indicators()) and restored.indicator_attachments.size() == 3, "指示物身份、顺序和局部位置可序列化往返")

func _test_battle_rules() -> void:
	var moon := SquadData.from_card(_card(&"moon_owner"))
	moon.attach_indicator(_item(CelestialIndicator.Kind.MOON, &"moon"), Vector2(49, 60), 1)
	var ally := SquadData.from_card(_card(&"ally"))
	var enemy := SquadData.from_card(_card(&"enemy"))
	var battle := BattleController.new()
	root.add_child(battle)
	battle.start_battle([_entry(moon, 0), _entry(ally, 1)], [_entry(enemy, 0, true)], 123, false)
	var moon_state := battle.player_states[0]
	_expect(moon_state.current_armor == 8 and moon_state.moon_shadowed, "月亮开场拥有初始护甲8与影蔽")
	_expect(not battle._is_base_candidate(battle.enemy_states[0], moon_state, CardData.ActionType.MELEE) and battle._is_base_candidate(battle.player_states[1], moon_state, CardData.ActionType.HEAL), "影蔽阻止敌方主目标选择，不阻止友方治疗")
	battle.execute_immediate_action(moon_state, CardData.ActionType.MELEE)
	_expect(not moon_state.moon_shadowed and is_equal_approx(moon_state.moon_restore_time, 3.0), "发射行动后失去影蔽并启动固定3秒恢复")
	battle.advance_time(2.0)
	battle.execute_immediate_action(moon_state, CardData.ActionType.MELEE)
	_expect(is_equal_approx(moon_state.moon_restore_time, 3.0), "两秒时再次行动不把恢复推迟到五秒")
	battle.advance_time(1.0)
	_expect(moon_state.moon_shadowed, "行动计时线在第三秒恢复影蔽")
	var action := battle._build_action(battle.enemy_states[0], battle.player_states, CardData.ActionType.MELEE)
	var reflection := battle._build_light_events(action, action["base_event"], 2, {"count": 1, "multiplier": 0.4}, 1)
	_expect(reflection.size() == 1 and reflection[0].target == moon_state, "影蔽单位仍然可被光折射副效果命中")
	moon_state.squad_data.attach_indicator(_item(CelestialIndicator.Kind.SUN, &"sun_a"), Vector2(50, 60), 2)
	var enemy_state := battle.enemy_states[0]
	enemy_state.squad_data.attach_indicator(_item(CelestialIndicator.Kind.SUN, &"sun_b"), Vector2(50, 60), 3)
	var ally_state := battle.player_states[1]
	ally_state.grant_runtime_keyword(&"dazzling", 100)
	_expect(battle.has_effective_dazzling(moon_state) and battle.has_effective_dazzling(enemy_state) and not battle.has_effective_dazzling(ally_state), "双方太阳携带者均保留耀眼，其他耀眼被压制")
	moon_state.squad_data.detach_indicator(&"sun_a")
	enemy_state.squad_data.detach_indicator(&"sun_b")
	_expect(battle.has_effective_dazzling(ally_state), "最后的太阳移除后其他来源的耀眼恢复")
	battle.free()

	var star_source := SquadData.from_card(_card(&"star_source"))
	star_source.attach_indicator(_item(CelestialIndicator.Kind.STAR, &"travelling_star"), Vector2(40, 60), 4)
	var recipient := SquadData.from_card(_card(&"recipient"))
	var occupied := SquadData.from_card(_card(&"occupied"))
	occupied.attach_indicator(_item(CelestialIndicator.Kind.STAR, &"other_star"), Vector2(50, 60), 5)
	battle = BattleController.new()
	root.add_child(battle)
	battle.start_battle([_entry(star_source, 0), _entry(recipient, 1), _entry(occupied, 2)], [_entry(enemy, 0, true)], 456, false)
	battle.player_states[0].current_health = 0
	battle._finalize_batch()
	var target := battle.player_states[1]
	_expect(target.squad_data.has_indicator(CelestialIndicator.Kind.STAR) and target.get_display_action_value() == 4 and battle.has_effective_dazzling(target), "星星转给没有星星的友军，获得完整星星与本场额外+1，合计+2")
	_expect(star_source.has_indicator(CelestialIndicator.Kind.STAR) and not recipient.has_indicator(CelestialIndicator.Kind.STAR), "星星传播未改写战前持有者和位置")
	var hit := battle._build_action(target, battle.enemy_states, CardData.ActionType.MELEE)
	_expect((hit["base_event"] as BattleEffectEvent).formula.base_value == 3.0, "星星基础数值真实进入攻击公式，不只改变卡面")
	battle.free()

func _test_main_drag_and_save() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var controller: CelestialIndicatorController = main.celestial_indicators
	_expect(controller.items.size() == 3 and controller._tray_views.size() == 3, "开发主场景提供各一枚日月星独立库存")
	var owned = main.owned_card_collection.get_cards()[0]
	var slot: BoardSlot = main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	await process_frame
	var item := controller.items[0]
	var view := controller._tray_views[item.instance_id] as CelestialIndicatorView
	var data := view.build_drag_data(Vector2(9, 11))
	var old_center := view._indicator_visual.get_global_transform_with_canvas() * (view.size * 0.5)
	controller.begin_click_carry(data, view.get_global_transform_with_canvas() * Vector2(9, 11))
	_expect(controller._preview.get_visual_center().distance_to(old_center) < 0.01, "拿起第一帧保留屏幕可见位置，没有中心瞬移")
	await create_timer(0.13).timeout
	var card := slot.get_primary_card_view()
	var intended := card.get_global_transform_with_canvas() * Vector2(49, 60)
	controller._preview.global_position += intended - controller._preview.get_visual_center()
	controller.finish_drop()
	var attached := slot.get_celestial_indicator(item.instance_id)
	_expect(attached != null and slot.get_squad_data().has_indicator(item.kind), "点击携带可把独立指示物绑定到随从")
	_expect((attached._indicator_visual.get_global_transform_with_canvas() * (attached.size * 0.5)).distance_to(intended) < 0.01, "放下第一帧与手持图标位置一致，再向下落到卡面")
	await create_timer(0.17).timeout
	var final_center := attached._indicator_visual.get_global_transform_with_canvas() * (attached.size * 0.5)
	_expect(final_center.distance_to(card.get_global_transform_with_canvas() * Vector2(49, 66)) < 0.1, "放下后中心在松手位置下方6个逻辑像素")
	var path := "/private/tmp/project-card-celestial-save.json"
	_expect(main.save_run_to_path(path) == OK and main.load_run_from_path(path), "真实主场景的指示物库存与阵容位置通过JSON存取")
	await process_frame
	var restored: BoardSlot = main.front_row.get_squads()[0]
	_expect(restored.get_squad_data().has_indicator(item.kind) and controller.items.size() == 3, "读取后同一实例仍绑定原小队，未复制或丢失库存")
	var second: CardData = load("res://resources/cards/militia.tres")
	restored.get_squad_data().insert_card(second, 1)
	restored.set_squad_data(restored.get_squad_data())
	main.front_row.remove_card_from_squad(restored, second)
	await process_frame
	_expect(
		restored.get_squad_data().indicator_attachments.is_empty()
		and controller._tray_views.has(item.instance_id)
		and controller._tray_board.visible,
		"拆队把指示物返还独立库存并显示临时卡板"
	)
	await create_timer(0.2).timeout
	view = controller._tray_views[item.instance_id] as CelestialIndicatorView
	var tray_start := view._indicator_visual.get_global_transform_with_canvas() * (view.size * 0.5)
	var tray_destination := controller._tray.get_global_transform_with_canvas() * Vector2(150, 54)
	await _mouse_motion(tray_start)
	await _mouse_button(tray_start, true)
	await _mouse_motion(tray_destination, true, tray_destination - tray_start)
	await _mouse_button(tray_destination, false)
	var stored_tray_position := controller._tray_positions[item.instance_id] as Vector2
	_expect(
		stored_tray_position.distance_to(Vector2(12, 25)) > 1.0
		and Rect2(Vector2.ZERO, controller.TRAY_SIZE).encloses(Rect2(stored_tray_position, view.size)),
		"库存内长按拖动保留自由摆放位置，不对齐固定横排"
	)
	var tray_save_path := "/private/tmp/project-card-celestial-tray-save.json"
	_expect(main.save_run_to_path(tray_save_path) == OK and main.load_run_from_path(tray_save_path), "库存自由位置写入并从JSON恢复")
	await process_frame
	restored = main.front_row.get_squads()[0]
	view = controller._tray_views[item.instance_id] as CelestialIndicatorView
	_expect(view.position.distance_to(stored_tray_position) < 0.01, "读档后指示物回到保存的库存位置")
	await create_timer(0.2).timeout
	var pointer := view.get_global_transform_with_canvas() * Vector2(10, 12)
	await _mouse_motion(pointer)
	await _mouse_button(pointer, true)
	await _mouse_motion(pointer + Vector2(28, 3), true, Vector2(28, 3))
	_expect(root.gui_is_dragging() and controller._native, "真实鼠标按住移动启动原生指示物拖拽")
	if root.gui_is_dragging() and controller._preview != null:
		await create_timer(0.13).timeout
		var top := restored.get_primary_card_view()
		var destination := top.get_global_transform_with_canvas() * Vector2(49, 60)
		pointer = controller._preview.global_position + destination - controller._preview.get_visual_center()
		await _mouse_motion(pointer, true)
		await _mouse_button(pointer, false)
		_expect(restored.get_squad_data().has_indicator(item.kind), "真实长按拖拽松手绑定到随从，与点击携带使用同一落点逻辑")
	if "--capture" in OS.get_cmdline_user_args():
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-celestial-scene.png")
	main.queue_free()
	await process_frame

func _mouse_motion(
	point: Vector2,
	held: bool = false,
	relative: Vector2 = Vector2.ZERO
) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.relative = relative
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(motion, true)
	await process_frame

func _mouse_button(point: Vector2, pressed: bool) -> void:
	var button := InputEventMouseButton.new()
	button.position = point
	button.global_position = point
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = pressed
	button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(button, true)
	await process_frame

func _expect(condition: bool, text: String) -> void:
	if condition:
		print("PASS: " + text)
	else:
		failures += 1
		push_error("FAIL: " + text)
