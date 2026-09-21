extends SceneTree

## D2-6A：物品实例归属、拖拽途中双形态、鼠标落点与无效区域返还。
## 只使用真实 Resource、场景节点与存档服务，不使用 mock。

const OwnedCardCollection = preload("res://scripts/data/owned_card_collection.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const BattlePreparationSnapshot = preload("res://scripts/data/battle_preparation_snapshot.gd")
const RunSaveService = preload("res://scripts/data/run_save_service.gd")
const RunRewardState = preload("res://scripts/data/run_reward_state.gd")
const RunSettlementJournal = preload("res://scripts/data/run_settlement_journal.gd")
const EquipmentIndicatorStyle = preload(
	"res://scripts/ui/equipment_indicator_style.gd"
)
const CardFaction = preload("res://scripts/data/card_faction.gd")
const CardPackRegistry = preload("res://scripts/data/card_pack_registry.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_equipment_identity_and_split_return()
	await _test_equipment_attributes_and_preparation_view()
	_test_equipment_effect_owner_registration()
	_test_stack_conflict_rules()
	_test_snapshot_and_json_round_trip()
	_test_indicator_assets_and_margaret_name()
	await _test_drag_transition_animation()
	await _test_equipment_placement_bounds()
	await _test_equipment_follows_top_card_after_stacking()
	await _test_main_drag_transformation_round_trip()
	await _test_click_carry_drop_hover_reentry()
	await _test_owned_minion_ghost_and_conflict_return()
	if failures == 0:
		print("D2-6A equipment attachment checks passed.")
	else:
		push_error("D2-6A equipment attachment checks failed: %d" % failures)
	quit(failures)


func _test_equipment_identity_and_split_return() -> void:
	var collection := OwnedCardCollection.new()
	var minion := collection.create_card(_minion_definition(&"equipment_owner"))
	var item := collection.create_card(_equipment_definition(&"equipment_item"))
	var squad := SquadData.from_owned_card(minion)
	_expect(
		squad.equip_item(item)
		and squad.get_equipped_item() == item
		and collection.get_by_instance_id(item.instance_id) == item,
		"装备位引用收藏中的同一物品实例，不复制或移除OwnedCard"
	)
	_expect(
		not squad.equip_item(minion),
		"随从实例不能进入装备位"
	)
	var returned_item := squad.return_equipment_for_split()
	_expect(
		returned_item == item
		and squad.get_equipped_item() == null
		and collection.get_by_instance_id(item.instance_id) == item,
		"拆队解除装备引用，物品实例仍由收藏容器持有"
	)


func _test_equipment_attributes_and_preparation_view() -> void:
	var minion := _minion_definition(&"equipped_attribute_minion")
	minion.base_value = 7
	minion.max_health = 11
	minion.armor = 2
	var equipment := _equipment_definition(&"equipped_attribute_item")
	equipment.equipment_action_delta = -2
	equipment.equipment_health_delta = 4
	equipment.equipment_armor_delta = 3
	equipment.equipment_zeal_delta = 1
	var owned_minion := OwnedCard.new()
	owned_minion.initialize(minion, &"equipped_attribute_minion_1", 0)
	owned_minion.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 2.0)
	var owned_item := OwnedCard.new()
	owned_item.initialize(equipment, &"equipped_attribute_item_1", 1)
	var squad := SquadData.from_owned_card(owned_minion)
	_expect(squad.equip_item(owned_item), "属性测试装备绑定到同一小队")
	var slot := preload("res://scenes/ui/BoardSlot.tscn").instantiate() as BoardSlot
	root.add_child(slot)
	slot.set_squad_data(squad)
	await process_frame
	var card_view := slot.get_card_view(minion)
	var state := BattleSquadState.new()
	state.initialize(squad.duplicate_squad(), BattleSquadState.Side.PLAYER, &"player_front", 0)
	_expect(
		squad.get_effective_action_base_value() == 7
		and squad.get_effective_max_health() == 15
		and squad.get_effective_base_armor() == 5
		and state.get_display_action_value() == 7
		and state.current_health == 15
		and state.current_armor == 5
		and state.get_zeal_layers() == 1
		and is_equal_approx(state.get_action_interval(), 3.0 / 1.05),
		"装备三项属性及+1热诚与随从永久成长进入正式战斗计算且只计算一次"
	)
	_expect(
		card_view.value_label.text == "7"
		and card_view.health_label.text == "15"
		and card_view.armor_label.text == "5"
		and card_view.cooldown_label.text == "2.9"
		and minion.base_value == 7
		and minion.max_health == 11
		and minion.armor == 2,
		"战前随从卡显示装备后的行动、生命、护甲和热诚后间隔，原共享资源不被改写"
	)
	var drag_data := card_view._build_drag_data(Vector2(49.5, 68.0))
	var preview := CardView.create_drag_visual(drag_data)
	root.add_child(preview)
	var preview_card := preview.get_source_card_view() as CardView
	_expect(
		preview_card.value_label.text == "7"
		and preview_card.health_label.text == "15"
		and preview_card.armor_label.text == "5",
		"已装备随从的拖拽快照保留装备后的战前数值"
	)
	preview.queue_free()
	squad.unequip_item()
	slot.set_squad_data(squad)
	_expect(
		squad.get_effective_action_base_value() == 9
		and squad.get_effective_max_health() == 11
		and squad.get_effective_base_armor() == 2
		and card_view.value_label.text == "9"
		and card_view.health_label.text == "11"
		and card_view.armor_label.text == "2",
		"卸下装备后立即恢复小队属性与战前卡面数值"
	)
	slot.queue_free()
	await process_frame
	equipment.equipment_zeal_delta = -1
	squad.equip_item(owned_item)
	var slowed := BattleSquadState.new()
	slowed.initialize(squad, BattleSquadState.Side.PLAYER, &"player_front", 0)
	_expect(
		slowed.get_zeal_layers() == -1
		and is_equal_approx(slowed.get_action_interval(), 3.0 / 0.95),
		"装备-1热诚使普通行动速度下降5%，而不是把冷却秒数直接加减"
	)


func _test_equipment_effect_owner_registration() -> void:
	var equipment := _equipment_definition(&"ash_war_banner")
	equipment.effect_ids.assign([&"ash_war_banner.effect.01"])
	var owned_item := OwnedCard.new()
	owned_item.initialize(equipment, &"ash_war_banner_instance_1", 1)
	var squad := SquadData.from_card(_minion_definition(&"effect_equipped_minion"))
	squad.equip_item(owned_item)
	var controller := preload("res://scripts/battle/battle_controller.gd").new() as BattleController
	root.add_child(controller)
	var formation: Array[Dictionary] = [{
		"squad_data": squad,
		"row_key": &"player_front",
		"formation_index": 0,
	}]
	controller._initialize_battle_state(formation, [], 501)
	var binding: BattleEffectBinding
	for candidate: BattleEffectBinding in controller.effect_runtime.bindings:
		if candidate.definition.effect_id == &"ash_war_banner.effect.01":
			binding = candidate
			break
	_expect(
		binding != null
		and binding.source.state == controller.player_states[0]
		and binding.source.card_data == equipment
		and binding.source.owned_card == owned_item
		and binding.source.owned_card_instance_id == owned_item.instance_id
		and binding.source.card_index == -1,
		"装备effect_ids注册到正式战斗，来源保留装备实例而不冒充小队随从"
	)
	squad.unequip_item()
	controller._initialize_battle_state(formation, [], 502)
	_expect(
		controller.effect_runtime.bindings.is_empty(),
		"卸下装备后新战斗不再注册该装备效果"
	)
	controller.queue_free()


func _test_stack_conflict_rules() -> void:
	var collection := OwnedCardCollection.new()
	var left := SquadData.from_owned_card(
		collection.create_card(_minion_definition(&"stack_left"))
	)
	var middle := collection.create_card(_minion_definition(&"stack_middle"))
	var right := SquadData.from_owned_card(
		collection.create_card(_minion_definition(&"stack_right"))
	)
	var first_item := collection.create_card(_equipment_definition(&"first_item"))
	var second_item := collection.create_card(_equipment_definition(&"second_item"))
	left.equip_item(first_item, Vector2(49.5, 55.0))
	left.insert_card(middle.card_data, 1, SquadData.TwoCardLayout.COMPACT)
	left.bind_owned_card(middle.card_data, middle)
	_expect(
		left.get_equipment_indicator_position() == Vector2(79.5, 55.0),
		"已装备单卡叠入右侧顶牌后，指示物仍位于新顶牌立绘中央"
	)
	var single_item_result := left.merge_compact_double_with_single(right, false)
	_expect(
		single_item_result != null
		and single_item_result.get_equipped_item() == first_item
		and single_item_result.get_equipment_indicator_position() == Vector2(79.5, 55.0),
		"堆叠双方合计一件装备时，新小队保留原物品实例"
	)
	var incoming_item := collection.create_card(_equipment_definition(&"incoming_item"))
	var incoming := SquadData.from_owned_card(
		collection.create_card(_minion_definition(&"incoming_equipped_card"))
	)
	incoming.equip_item(incoming_item, Vector2(49.5, 55.0))
	var empty_target := SquadData.from_owned_card(
		collection.create_card(_minion_definition(&"incoming_target_card"))
	)
	empty_target.insert_card(
		incoming.get_effect_source(), 1, SquadData.TwoCardLayout.COMPACT
	)
	empty_target.merge_equipment_from(incoming)
	_expect(
		empty_target.get_equipped_item() == incoming_item
		and empty_target.get_equipment_indicator_position() == Vector2(79.5, 55.0),
		"带装备单卡叠入无装备小队时，装备落点转到结果顶牌而不是旧小队原点"
	)
	right.equip_item(second_item)
	var conflict_result := left.merge_compact_double_with_single(right, false)
	_expect(
		conflict_result != null
		and conflict_result.get_equipped_item() == null
		and collection.get_by_instance_id(first_item.instance_id) == first_item
		and collection.get_by_instance_id(second_item.instance_id) == second_item,
		"堆叠双方各有装备时两件都解除，新小队不擅自选择保留项"
	)


func _test_snapshot_and_json_round_trip() -> void:
	var collection := OwnedCardCollection.new()
	var minion := collection.create_card(_minion_definition(&"saved_owner"))
	var item := collection.create_card(_equipment_definition(&"saved_item"))
	var squad := SquadData.from_owned_card(minion)
	var saved_indicator_position := Vector2(23.0, 91.0)
	squad.equip_item(item, saved_indicator_position)
	var snapshot := BattlePreparationSnapshot.new()
	_expect(
		snapshot.initialize(
			&"equipment_battle",
			260618,
			collection,
			{&"player_front": [squad]}
		),
		"战前快照接受带装备实例的小队"
	)
	var snapshot_squad := snapshot.get_row_squads(&"player_front")[0]
	_expect(
		snapshot_squad.get_equipped_item() == item,
		"战前阵容副本保留同一个物品实例引用"
	)
	_expect(
		snapshot_squad.get_equipment_indicator_position() == saved_indicator_position,
		"战前阵容副本保留装备指示物的卡面落点"
	)

	var rows := _empty_rows()
	rows[&"player_front"] = [squad]
	var save_service := RunSaveService.new()
	var reward_state := RunRewardState.new()
	var journal := RunSettlementJournal.new()
	var checkpoint := save_service.create_checkpoint(
		collection.capture_state(),
		rows,
		260618,
		&"",
		1,
		reward_state,
		journal,
		0
	)
	var restored_collection := OwnedCardCollection.new()
	var restored_reward_state := RunRewardState.new()
	var restored_journal := RunSettlementJournal.new()
	var restore_result := save_service.restore_checkpoint(
		checkpoint,
		restored_collection,
		restored_reward_state,
		restored_journal,
		{
			minion.card_data.id: minion.card_data,
			item.card_data.id: item.card_data,
		}
	)
	var restored_rows := restore_result.get("rows", {}) as Dictionary
	var restored_front := restored_rows.get(&"player_front", []) as Array
	var restored_squad := restored_front[0] as SquadData if not restored_front.is_empty() else null
	var restored_item = restored_collection.get_by_instance_id(item.instance_id)
	_expect(
		bool(restore_result.get("success", false))
		and restored_squad != null
		and restored_squad.get_equipped_item() == restored_item
		and restored_squad.get_equipment_indicator_position() == saved_indicator_position
		and restored_item.instance_id == item.instance_id,
		"JSON往返恢复装备实例及指示物落点，不生成新的物品身份"
	)
	var stacked_member := collection.create_card(_minion_definition(&"saved_top_member"))
	var stacked_squad := squad.duplicate_squad()
	stacked_squad.set_equipment_indicator_position(Vector2(49.5, 55.0))
	stacked_squad.insert_card(
		stacked_member.card_data, 1, SquadData.TwoCardLayout.COMPACT
	)
	stacked_squad.bind_owned_card(stacked_member.card_data, stacked_member)
	var stacked_rows := _empty_rows()
	stacked_rows[&"player_front"] = [stacked_squad]
	var stacked_checkpoint := save_service.create_checkpoint(
		collection.capture_state(), stacked_rows, 260618, &"", 1,
		reward_state, journal, 0
	)
	var stacked_restore := save_service.restore_checkpoint(
		stacked_checkpoint,
		OwnedCardCollection.new(),
		RunRewardState.new(),
		RunSettlementJournal.new(),
		{
			minion.card_data.id: minion.card_data,
			stacked_member.card_data.id: stacked_member.card_data,
			item.card_data.id: item.card_data,
		}
	)
	var stacked_restored_rows := stacked_restore.get("rows", {}) as Dictionary
	var stacked_restored_front := stacked_restored_rows.get(&"player_front", []) as Array
	var stacked_restored := (
		stacked_restored_front[0] as SquadData
		if not stacked_restored_front.is_empty() else null
	)
	var stacked_anchor_survives_save := (
		bool(stacked_restore.get("success", false))
		and stacked_restored != null
		and stacked_restored.get_equipment_indicator_position() == Vector2(79.5, 55.0)
	)
	if stacked_restored != null:
		stacked_restored.bring_card_to_top(minion.card_data)
		stacked_anchor_survives_save = (
			stacked_anchor_survives_save
			and stacked_restored.get_equipment_indicator_position() == Vector2(49.5, 55.0)
		)
	_expect(
		stacked_anchor_survives_save,
		"多卡小队存档往返保留顶牌局部装备落点，切换顶牌仍在立绘内"
	)

	var duplicate_owner := collection.create_card(_minion_definition(&"duplicate_owner"))
	var duplicate_squad := SquadData.from_owned_card(duplicate_owner)
	duplicate_squad.equip_item(item)
	rows[&"player_back"] = [duplicate_squad]
	var duplicate_checkpoint := save_service.create_checkpoint(
		collection.capture_state(),
		rows,
		260618,
		&"",
		1,
		reward_state,
		journal,
		0
	)
	var duplicate_restore_result := save_service.restore_checkpoint(
		duplicate_checkpoint,
		OwnedCardCollection.new(),
		RunRewardState.new(),
		RunSettlementJournal.new(),
		{
			minion.card_data.id: minion.card_data,
			item.card_data.id: item.card_data,
			stacked_member.card_data.id: stacked_member.card_data,
			duplicate_owner.card_data.id: duplicate_owner.card_data,
		}
	)
	_expect(
		not bool(duplicate_restore_result.get("success", false))
		and duplicate_restore_result.get("reason") == "save_squad_equipment_invalid",
		"读档拒绝同一物品实例同时占用两个小队装备位"
	)


func _test_indicator_assets_and_margaret_name() -> void:
	var radiant_item := _equipment_definition(&"radiant_indicator")
	radiant_item.faction = CardFaction.Id.RADIANT_ALLIANCE
	radiant_item.equipment_type = CardData.EquipmentType.ACCESSORY
	radiant_item.rarity = CardData.Rarity.I
	var hansa_item := _equipment_definition(&"hansa_indicator")
	hansa_item.faction = CardFaction.Id.HANSA_FEDERATION
	hansa_item.equipment_type = CardData.EquipmentType.MELEE_WEAPON
	hansa_item.rarity = CardData.Rarity.III
	var wild_item := _equipment_definition(&"wild_indicator")
	wild_item.faction = CardFaction.Id.WILD_BEAST_NEST
	wild_item.equipment_type = CardData.EquipmentType.ARMOR
	wild_item.rarity = CardData.Rarity.V
	var pathfinder_item := _equipment_definition(&"pathfinder_indicator")
	pathfinder_item.faction = CardFaction.Id.PATHFINDER_ASSOCIATION
	var labyrinth_item := _equipment_definition(&"labyrinth_indicator")
	labyrinth_item.pack_id = &"labyrinth"
	var radiant_texture := EquipmentIndicatorStyle.get_texture(radiant_item)
	var hansa_texture := EquipmentIndicatorStyle.get_texture(hansa_item)
	var wild_texture := EquipmentIndicatorStyle.get_texture(wild_item)
	var pathfinder_texture := EquipmentIndicatorStyle.get_texture(pathfinder_item)
	var labyrinth_texture := EquipmentIndicatorStyle.get_texture(labyrinth_item)
	var native_size_visual := EquipmentIndicatorStyle.create_visual(radiant_item)
	_expect(
		EquipmentIndicatorStyle.DISPLAY_SIZE == Vector2(30.0, 30.0)
		and radiant_texture.get_size() == Vector2(30.0, 30.0)
		and native_size_visual.size == Vector2(30.0, 30.0)
		and native_size_visual.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR
		and radiant_texture.get_image().get_pixel(15, 15)
		!= hansa_texture.get_image().get_pixel(15, 15)
		and hansa_texture.get_image().get_pixel(15, 15)
		!= wild_texture.get_image().get_pixel(15, 15)
		and pathfinder_texture.get_image().get_pixel(4, 15)
		!= labyrinth_texture.get_image().get_pixel(4, 15),
		"装备指示物按阵营底座、装备类型与品级图案实时组合"
	)
	native_size_visual.free()
	var all_icons_centered := true
	for equipment_type: int in CardData.EquipmentType.size():
		for rarity: int in CardData.Rarity.size():
			var icon := EquipmentIndicatorStyle.TYPE_ATLAS.get_image().get_region(
				EquipmentIndicatorStyle._get_type_region(equipment_type, rarity)
			)
			var visible_rect := icon.get_used_rect()
			var icon_offset := EquipmentIndicatorStyle._get_centered_icon_offset(icon)
			var occupied_center := Vector2(
				icon_offset.x + visible_rect.position.x + visible_rect.size.x * 0.5,
				icon_offset.y + visible_rect.position.y + visible_rect.size.y * 0.5
			)
			if occupied_center.distance_to(Vector2(15.0, 15.0)) > 0.71:
				all_icons_centered = false
	_expect(all_icons_centered, "六类装备各五级图案按非透明像素居中于30×30底座")
	var catalog := load(
		"res://assets/card_ui/equipment/equipment_indicator_catalog.png"
	) as Texture2D
	_expect(
		catalog != null and catalog.get_size() == Vector2(822.0, 190.0),
		"静态装备总览也使用30×30原生图标，不再保留60×60放大版"
	)
	_expect(
		CardPackRegistry.get_faction(&"ash_ledger")
		== CardFaction.Id.RADIANT_ALLIANCE
		and CardPackRegistry.get_faction(&"gilded_formulae")
		== CardFaction.Id.HANSA_FEDERATION
		and CardPackRegistry.get_faction(&"insect_eaten_bestiary")
		== CardFaction.Id.WILD_BEAST_NEST
		and CardPackRegistry.get_faction(&"labyrinth")
		== CardFaction.Id.LABYRINTH,
		"已确认卡包归属覆盖辉光、汉萨、野性与迷宫，寻路者阵营保留橙色"
	)
	var margaret := load("res://resources/cards/anvil_margaret.tres") as CardData
	_expect(
		margaret != null and margaret.display_name == "铁砧-玛格丽特",
		"铁砧-玛格丽特的权威卡牌资源不会再恢复旧名称"
	)


func _test_drag_transition_animation() -> void:
	var owned_item := OwnedCard.new()
	owned_item.initialize(
		_equipment_definition(&"transition_item"),
		&"transition_item",
		0
	)
	var drag_data := {
		"kind": &"equipment_card",
		"card_data": owned_item.card_data,
		"owned_card": owned_item,
		"source_type": &"collection",
		"grab_local_position": Vector2(49.5, 68.0),
		"preview_scale": Vector2.ONE,
	}
	var preview := CardView.create_drag_visual(drag_data)
	root.add_child(preview)
	preview.position = Vector2(720.0, 430.0)
	preview.set_equipment_indicator_mode(true)
	var indicator := preview.get_node("EquipmentIndicatorVisual") as TextureRect
	var indicator_shadow := indicator.get_node("IndicatorShadow") as TextureRect
	var indicator_rest_position := -EquipmentIndicatorStyle.DISPLAY_SIZE * 0.5
	_expect(
		preview.get_equipment_indicator_visual_global_center().distance_to(
			indicator.get_global_transform_with_canvas() * Vector2(15.0, 15.0)
		) < 0.01,
		"非零屏幕坐标下放置起点等于真实图像中心，不能将屏幕平移量减半"
	)
	_expect(
		indicator.visible
		and indicator.scale == Vector2.ONE * CardDragPreview.EQUIPMENT_INDICATOR_START_SCALE
		and indicator.modulate.a == 0.0
		and indicator.position == indicator_rest_position - CardDragPreview.EQUIPMENT_INDICATOR_DROP_LIFT
		and indicator_shadow.texture == indicator.texture,
		"装备牌切换开始时，带阴影的指示物从2倍大小和上方透明状态出现"
	)
	await create_timer(CardDragPreview.EQUIPMENT_TRANSITION_DURATION + 0.03).timeout
	await process_frame
	_expect(
		preview.is_equipment_indicator_mode()
		and indicator.visible
		and indicator.scale.is_equal_approx(Vector2.ONE)
		and is_equal_approx(indicator.modulate.a, 1.0)
		and indicator.position.is_equal_approx(indicator_rest_position),
		"快速交叉渐变结束后，指示物向下落到鼠标中心并保留右下阴影"
	)
	preview.set_equipment_indicator_mode(false)
	# 模拟原生长按拖拽：鼠标离开卡面后，每帧都会继续报告“显示完整卡牌”。
	# 重复请求不能重启渐显，否则画面会长期只剩黑色卡牌阴影。
	for _frame_index: int in 8:
		await create_timer(0.02).timeout
		preview.set_equipment_indicator_mode(false)
	var snapshot := preview.get_node("CardSnapshotVisual") as Control
	_expect(
		not preview.is_equipment_indicator_mode()
		and snapshot.visible
		and snapshot.modulate.a > 0.95
		and not indicator.visible,
		"原生长按拖离随从卡面后，重复状态更新不会卡成黑色阴影"
	)
	preview.queue_free()
	await process_frame


func _test_equipment_placement_bounds() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.front_row.clear_squads()
	var left := _minion_definition(&"equipment_top_card")
	var right := _minion_definition(&"equipment_lower_card")
	var squad := SquadData.from_cards(
		[left, right], SquadData.TwoCardLayout.COMPACT
	)
	var slot: BoardSlot = main.front_row.add_squad(squad, 0)
	await process_frame
	var top_card := slot.get_card_view(squad.get_effect_source())
	var lower_card := slot.get_card_view(right)
	var overlay := main.front_row.placement_overlay as Control
	var overlay_inverse := overlay.get_global_transform_with_canvas().affine_inverse()
	var top_center := overlay_inverse * (
		top_card.get_global_transform_with_canvas() * Vector2(49.5, 55.0)
	)
	var top_art_edge := overlay_inverse * (
		top_card.get_global_transform_with_canvas() * Vector2(14.0, 55.0)
	)
	var top_art_bottom := overlay_inverse * (
		top_card.get_global_transform_with_canvas() * Vector2(49.5, 90.0)
	)
	var lower_center := overlay_inverse * (
		lower_card.get_global_transform_with_canvas() * Vector2(79.0, 55.0)
	)
	_expect(
		main.front_row._find_equipment_target_slot(top_center) == slot
		and main.front_row._find_equipment_target_slot(top_art_edge) == null
		and main.front_row._find_equipment_target_slot(top_art_bottom) == null
		and main.front_row._find_equipment_target_slot(lower_center) == null,
		"装备指示物必须完整位于小队最上层卡牌立绘内，侧边、底边和下层卡不可放置"
	)
	main.queue_free()
	await process_frame


func _test_equipment_follows_top_card_after_stacking() -> void:
	var collection := OwnedCardCollection.new()
	var first := collection.create_card(_minion_definition(&"equipped_before_stack"))
	var second := collection.create_card(_minion_definition(&"top_after_stack"))
	var item := collection.create_card(_equipment_definition(&"stacked_indicator"))
	var squad := SquadData.from_owned_card(first)
	squad.equip_item(item, Vector2(49.5, 55.0))
	var slot := preload("res://scenes/ui/BoardSlot.tscn").instantiate() as BoardSlot
	root.add_child(slot)
	slot.set_squad_data(squad)
	await process_frame
	squad.insert_card(second.card_data, 1, SquadData.TwoCardLayout.COMPACT)
	squad.bind_owned_card(second.card_data, second)
	slot.set_squad_data(squad)
	await process_frame
	var top_card := slot.get_card_view(second.card_data)
	var indicator := slot.get_equipment_indicator()
	var icon_center_on_top: Vector2 = (
		indicator.position + EquipmentIndicatorStyle.DISPLAY_SIZE * 0.5
		- top_card.position
	)
	_expect(
		squad.get_effect_source() == second.card_data
		and icon_center_on_top.is_equal_approx(Vector2(49.5, 55.0)),
		"真实小队叠卡后指示物跟随新顶牌，完整留在其立绘区域内"
	)
	squad.bring_card_to_top(first.card_data)
	slot.set_squad_data(squad)
	await process_frame
	var first_card := slot.get_card_view(first.card_data)
	icon_center_on_top = (
		indicator.position + EquipmentIndicatorStyle.DISPLAY_SIZE * 0.5
		- first_card.position
	)
	_expect(
		squad.get_effect_source() == first.card_data
		and icon_center_on_top.is_equal_approx(Vector2(49.5, 55.0)),
		"再次切换小队最上层卡牌时装备指示物仍跟随立绘"
	)
	slot.queue_free()
	await process_frame


func _test_main_drag_transformation_round_trip() -> void:
	root.size = Vector2i(1280, 720)
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.active_card_type_filters.assign([CardData.CardType.EQUIPMENT])
	main.current_collection_page = 0
	main._build_collection_cards()
	await process_frame
	var item_slot: Control
	for slot: Control in main._get_collection_card_slots():
		if slot.has_meta("owned_card"):
			item_slot = slot
			break
	var owned_item := item_slot.get_meta("owned_card") as OwnedCard if item_slot != null else null
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	var target_slot: BoardSlot
	for owned_card: OwnedCard in main.owned_card_collection.get_cards():
		if owned_card.card_data.card_type == CardData.CardType.MINION:
			target_slot = main.front_row.add_squad(
				SquadData.from_owned_card(owned_card),
				0
			)
			break
	_expect(
		owned_item != null and target_slot != null,
		"主场景提供可拖动的物品实例和装备目标小队"
	)
	if owned_item == null or target_slot == null:
		main.queue_free()
		await process_frame
		return
	var item_card_view := item_slot.get_child(0) as CardView
	var click_press := InputEventMouseButton.new()
	click_press.button_index = MOUSE_BUTTON_LEFT
	click_press.pressed = true
	click_press.position = Vector2(40.0, 60.0)
	item_card_view._gui_input(click_press)
	var click_release := InputEventMouseButton.new()
	click_release.button_index = MOUSE_BUTTON_LEFT
	click_release.pressed = false
	click_release.position = Vector2(40.0, 60.0)
	item_card_view._gui_input(click_release)
	await process_frame
	_expect(
		main._click_carry_data.get("kind") == &"equipment_card"
		and main._click_carry_data.get("owned_card") == owned_item,
		"装备牌单击松开后进入点击携带状态，不要求长按"
	)
	main._cancel_click_carry()
	await process_frame
	var equipment_drag := {
		"kind": &"equipment_card",
		"card_data": owned_item.card_data,
		"owned_card": owned_item,
		"source_type": &"collection",
		"source_slot": item_slot,
		"grab_local_position": Vector2(44.0, 62.0),
		"preview_offset": Vector2.ZERO,
	}
	var equipment_drag_visual := CardView.create_drag_visual(equipment_drag)
	root.add_child(equipment_drag_visual)
	equipment_drag["drag_visual"] = equipment_drag_visual
	var target_card := target_slot.get_card_view(target_slot.get_squad_data().get_effect_source())
	var target_position: Vector2 = (
		main.front_row.placement_overlay.get_global_transform_with_canvas().affine_inverse()
		* (target_card.get_global_transform_with_canvas() * Vector2(49.5, 55.0))
	)
	var expected_indicator_position: Vector2 = (
		target_slot.get_global_transform_with_canvas().affine_inverse()
		* (
			target_card.get_global_transform_with_canvas()
			* (Vector2(49.5, 55.0) + BattlefieldRow.EQUIPMENT_DROP_TRAVEL)
		)
	)
	equipment_drag_visual.global_position = (
		main.front_row.placement_overlay.get_global_transform_with_canvas()
		* target_position
	)
	var previewed: bool = main.front_row.preview_card_drop(target_position, equipment_drag)
	var transformed_while_hovering := equipment_drag_visual.is_equipment_indicator_mode()
	var release_center := equipment_drag_visual.get_equipment_indicator_visual_global_center()
	main.front_row.commit_card_drop(target_position, equipment_drag)
	var placed_visual := target_slot.get_equipment_indicator().get_node("IndicatorVisual") as TextureRect
	_expect((placed_visual.get_global_transform_with_canvas() * Vector2(15.0, 15.0)).distance_to(release_center) < 0.1,
		"放下第一帧与手持图像的屏幕中心一致，不从左上方飞入")
	await process_frame
	equipment_drag_visual.queue_free()
	var equipped_ghost := _find_collection_slot_for_owned_card(main, owned_item)
	var indicator := target_slot.get_equipment_indicator()
	var indicator_shadow := indicator.get_node_or_null("IndicatorShadow") as TextureRect
	var indicator_visual := indicator.get_node_or_null("IndicatorVisual") as TextureRect
	var indicator_rest_position: Vector2 = indicator.position
	_expect(
		indicator_visual != null
		and indicator_visual.position.y < 0.0
		and indicator_shadow.position != EquipmentIndicatorStyle.SHADOW_OFFSET,
		"装备指示物成功落到卡牌时，从拿起高度开始向下放置"
	)
	var indicator_drag_data := (
		indicator.call("build_drag_data", Vector2(12.0, 12.0)) as Dictionary
		if indicator != null
		else {}
	)
	if indicator != null:
		var source_visual := indicator.get_node("IndicatorVisual") as TextureRect
		var pickup_center := source_visual.get_global_transform_with_canvas() * Vector2(15.0, 15.0)
		var raised_center := indicator.get_global_transform_with_canvas() * Vector2(15.0, 9.0)
		var offset_preview := CardView.create_drag_visual(indicator_drag_data)
		root.add_child(offset_preview)
		offset_preview.global_position = indicator.get_global_transform_with_canvas() * Vector2(12.0, 12.0)
		offset_preview.set_equipment_indicator_mode(true, false)
		_expect(
			offset_preview.get_equipment_indicator_visual_global_center().distance_to(pickup_center) < 0.1,
			"原生拖拽接续指示物当前可见位置，包括已经抬起的偏移"
		)
		offset_preview.continue_equipment_pickup(indicator_drag_data["indicator_lifted_grab_local_position"])
		await create_timer(CardDragPreview.EQUIPMENT_TRANSITION_DURATION + 0.03).timeout
		_expect(offset_preview.get_equipment_indicator_visual_global_center().distance_to(raised_center) < 0.1,
			"原生拖拽完成剩余抬起后，保留抬起位置与鼠标的偏移")
		offset_preview.queue_free()
		var click_preview := main._create_click_carry_preview(
			indicator_drag_data,
			indicator.get_global_transform_with_canvas() * Vector2(12.0, 12.0)
		) as CardDragPreview
		_expect(
			click_preview.get_equipment_indicator_visual_global_center().distance_to(pickup_center) < 0.1,
			"单击携带第一帧保留原图像位置，不瞬移到鼠标"
		)
		await create_timer(CardDragPreview.EQUIPMENT_TRANSITION_DURATION + 0.03).timeout
		click_preview.global_position += Vector2(40.0, 20.0)
		_expect(click_preview.get_equipment_indicator_visual_global_center().distance_to(raised_center + Vector2(40.0, 20.0)) < 0.1,
			"单击携带完成抬起后按鼠标位移跟随，保持抓取偏移")
		click_preview.queue_free()
	_expect(
		previewed and transformed_while_hovering,
		"装备牌的鼠标进入可装备卡面时，手中预览立即变成指示物"
	)
	_expect(
		target_slot.get_squad_data().get_equipped_item() == owned_item
		and target_slot.get_squad_data().get_equipment_indicator_position().distance_to(
			expected_indicator_position
		) < 0.1,
		"松手后装备绑定到小队，并记录从鼠标松开处向下落的卡面位置"
	)
	_expect(
		indicator != null
		and (indicator.position + EquipmentIndicatorStyle.DISPLAY_SIZE * 0.5).distance_to(
			expected_indicator_position
		) < 0.1
		and indicator_drag_data.get("kind") == &"equipment_indicator"
		and indicator_drag_data.get("owned_card") == owned_item
		and equipped_ghost != null
		and bool(equipped_ghost.get_meta("is_deployed_ghost", false)),
		"落地指示物位于松开位置下方，并继续携带原物品实例"
	)
	await create_timer(indicator.DROP_DURATION + 0.03).timeout
	_expect(
		indicator_visual.position.is_equal_approx(Vector2.ZERO)
		and indicator_shadow.position.is_equal_approx(
			EquipmentIndicatorStyle.SHADOW_OFFSET
		),
		"装备指示物落地后回到卡面，并把阴影收近"
	)
	indicator.call("show_pointer_hover_feedback")
	await create_timer(indicator.HOVER_LIFT_DURATION + 0.03).timeout
	_expect(
		indicator_visual.position.is_equal_approx(Vector2.ZERO)
		and indicator_shadow.position.is_equal_approx(EquipmentIndicatorStyle.SHADOW_OFFSET),
		"装备经拖拽落地后，鼠标未离开指示物时不会立刻重新抬起"
	)
	_expect(
		indicator.z_index == EquipmentIndicatorStyle.INDICATOR_Z_INDEX
		and EquipmentIndicatorStyle.INDICATOR_Z_INDEX
			> CardView.CARD_LAYER_Z_STEP * SquadData.MAX_CARD_COUNT
		and BattlefieldRow.DROP_PREVIEW_Z_INDEX
			+ EquipmentIndicatorStyle.INDICATOR_Z_INDEX
			< CardDragPreview.DRAG_PREVIEW_Z_INDEX,
		"目标预览中的装备指示物位于卡牌虚影上方、鼠标携带实体下方"
	)
	target_slot.set_stack_target_feedback(1.0)
	var stack_indicator_snapshot := target_slot.get_node_or_null(
		"StackFeedbackLayer/SquadLiftLayer/StackTargetSnapshotLayer/EquipmentIndicatorSnapshot"
	) as TextureRect
	_expect(
		target_slot.has_stack_target_snapshots()
		and stack_indicator_snapshot != null
		and stack_indicator_snapshot.texture == indicator_visual.texture,
		"已装备小队切换为目标颤动快照时，装备指示物进入同一快照"
	)
	target_slot.set_stack_target_feedback(0.0)
	var equipped_minion := target_slot.get_squad_data().horizontal_cards[0]
	target_slot._on_card_mouse_entered(equipped_minion)
	_expect(
		indicator.position.is_equal_approx(
			indicator_rest_position - Vector2(0.0, target_slot.CARD_LIFT_OFFSET)
		)
		and indicator_shadow != null
		and indicator_shadow.position == EquipmentIndicatorStyle.SHADOW_OFFSET,
		"随从悬停上跳时，装备指示物同步上跳且静止阴影贴近图标"
	)
	target_slot.reset_hover_feedback()
	var pointer_exit := InputEventMouseMotion.new()
	pointer_exit.position = indicator.get_global_rect().end + Vector2(20.0, 20.0)
	indicator._input(pointer_exit)
	indicator.call("show_pointer_hover_feedback")
	await create_timer(indicator.HOVER_LIFT_DURATION + 0.03).timeout
	_expect(
		indicator_visual != null
		and indicator_visual.position.is_equal_approx(
			Vector2(0.0, -indicator.HOVER_LIFT_OFFSET)
		)
		and indicator_shadow.position.is_equal_approx(
			EquipmentIndicatorStyle.LIFTED_SHADOW_OFFSET
		),
		"鼠标指向装备指示物时，图标向上跳起并把阴影拉远"
	)
	indicator.call("clear_pointer_hover_feedback")
	await create_timer(indicator.DROP_DURATION + 0.03).timeout
	_expect(
		indicator_visual.position.is_equal_approx(Vector2.ZERO)
		and indicator_shadow.position.is_equal_approx(
			EquipmentIndicatorStyle.SHADOW_OFFSET
		),
		"鼠标离开装备指示物时，图标向下落回且阴影重新贴近"
	)
	target_slot.lock_drag_subject(equipped_minion)
	var equipped_card_view := target_slot.get_card_view(equipped_minion)
	var minion_drag := equipped_card_view._build_drag_data(Vector2(49.5, 68.0))
	var minion_drag_visual := CardView.create_drag_visual(minion_drag)
	root.add_child(minion_drag_visual)
	var preview_card := minion_drag_visual.get_source_card_view() as CardView
	_expect(
		preview_card != null
		and preview_card.get_node_or_null("AttachedEquipmentIndicator") != null,
		"拖动已装备的单卡随从时，装备指示物进入同一拖拽快照并随鼠标移动"
	)
	minion_drag_visual.queue_free()
	target_slot.unlock_drag_subject()
	var source_squad := target_slot.get_squad_data()
	var move_result := source_squad.duplicate_squad()
	var move_drag := {
		"kind": &"card",
		"card_data": equipped_minion,
		"owned_card": source_squad.get_owned_card(equipped_minion),
		"source_type": &"board",
		"source_row": main.front_row,
		"source_slot": target_slot,
		"squad_data": source_squad,
		"drop_intent": {
			"operation": &"new_squad",
			"squad_index": 0,
			"result_squad": move_result,
		},
	}
	var moved_with_equipment: bool = bool(main._transfer_drop_intent(
		move_drag,
		main.back_row
	))
	target_slot = main.selected_board_slot
	await process_frame
	indicator = target_slot.get_equipment_indicator()
	indicator_drag_data = (
		indicator.call("build_drag_data", Vector2(20.0, 20.0)) as Dictionary
		if indicator != null
		else {}
	)
	var moved_equipped_ghost := _find_collection_slot_for_owned_card(main, owned_item)
	_expect(
		moved_with_equipment
		and target_slot.get_squad_data().get_equipped_item() == owned_item
		and indicator != null
		and moved_equipped_ghost != null
		and bool(moved_equipped_ghost.get_meta("is_deployed_ghost", false)),
		"已装备单卡跨排移动时保留同一装备实例，不会消失或提前解锁装备位"
	)
	var indicator_source_position: Vector2 = indicator.get_global_rect().get_center()
	var invalid_release_position := Vector2(1180.0, 360.0)
	await _send_mouse_motion(indicator_source_position, Vector2.ZERO, 0)
	await _send_left_button(indicator_source_position, true)
	await _send_mouse_motion(
		indicator_source_position + Vector2(15.0, 0.0),
		Vector2(15.0, 0.0),
		MOUSE_BUTTON_MASK_LEFT
	)
	var native_indicator_drag := root.gui_get_drag_data() as Dictionary
	var native_indicator_visual := native_indicator_drag.get("drag_visual") as CardDragPreview
	await _send_mouse_motion(
		indicator_source_position + Vector2(16.0, 0.0),
		Vector2(1.0, 0.0),
		MOUSE_BUTTON_MASK_LEFT
	)
	# headless 的 push_input 不会更新 Viewport.get_mouse_position()；直接调用的正是
	# Main 在实际运行中由 _input / _process 持续执行的同一条坐标刷新路径。
	main._update_native_equipment_drag_preview(
		indicator_source_position + Vector2(16.0, 0.0)
	)
	var began_as_indicator: bool = (
		native_indicator_drag.get("kind") == &"equipment_indicator"
		and is_instance_valid(native_indicator_visual)
		and native_indicator_visual.is_equipment_indicator_mode()
	)
	await _send_mouse_motion(
		invalid_release_position,
		invalid_release_position - indicator_source_position,
		MOUSE_BUTTON_MASK_LEFT
	)
	var became_full_card_outside: bool = (
		is_instance_valid(native_indicator_visual)
		and not native_indicator_visual.is_equipment_indicator_mode()
	)
	await _send_left_button(invalid_release_position, false)
	var invalid_drop_was_rejected := not root.gui_is_drag_successful()
	await process_frame
	await process_frame
	var restored_card_slot := _find_collection_slot_for_owned_card(main, owned_item)
	_expect(
		began_as_indicator,
		"原生拖拽从场上指示物形态开始"
	)
	_expect(
		became_full_card_outside,
		"原生拖拽离开可装备卡面后立即变回完整装备牌"
	)
	_expect(
		invalid_drop_was_rejected,
		"战斗区与收藏区之外的区域不会接收装备牌"
	)
	_expect(
		target_slot.get_squad_data().get_equipped_item() == null
		and target_slot.get_equipment_indicator() == null
		and restored_card_slot != null
		and not bool(restored_card_slot.get_meta("is_deployed_ghost", false)),
		"无效区域松手后自动卸下，并从松手位置动画返还收藏"
	)
	main.queue_free()
	await process_frame


func _test_click_carry_drop_hover_reentry() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.active_card_type_filters.assign([CardData.CardType.EQUIPMENT])
	main.current_collection_page = 0
	main._build_collection_cards()
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	var item_slot: Control
	for slot: Control in main._get_collection_card_slots():
		if slot.has_meta("owned_card"):
			item_slot = slot
			break
	var owned_item := item_slot.get_meta("owned_card") as OwnedCard if item_slot != null else null
	var target_slot: BoardSlot
	for owned_card: OwnedCard in main.owned_card_collection.get_cards():
		if owned_card.card_data.card_type == CardData.CardType.MINION:
			target_slot = main.front_row.add_squad(SquadData.from_owned_card(owned_card), 0)
			break
	if owned_item == null or target_slot == null:
		_expect(false, "单击携带测试需要收藏装备与场上随从")
		main.queue_free()
		await process_frame
		return
	var item_view := item_slot.get_child(0) as CardView
	var click_press := InputEventMouseButton.new()
	click_press.button_index = MOUSE_BUTTON_LEFT
	click_press.pressed = true
	click_press.position = Vector2(40.0, 60.0)
	item_view._gui_input(click_press)
	var click_release := InputEventMouseButton.new()
	click_release.button_index = MOUSE_BUTTON_LEFT
	click_release.pressed = false
	click_release.position = click_press.position
	item_view._gui_input(click_release)
	await process_frame
	var target_card := target_slot.get_primary_card_view()
	var pointer_position: Vector2 = (
		target_card.get_global_transform_with_canvas() * Vector2(49.5, 55.0)
	)
	var carried_by_click: bool = main._click_carry_data.get("owned_card") == owned_item
	main._commit_click_carry(pointer_position)
	await process_frame
	var indicator := target_slot.get_equipment_indicator()
	_expect(
		carried_by_click
		and target_slot.get_squad_data().get_equipped_item() == owned_item
		and indicator != null,
		"单击携带装备后，点击随从卡面可完成指示物落地"
	)
	if indicator != null:
		var visual := indicator.get_node("IndicatorVisual") as TextureRect
		var shadow := indicator.get_node("IndicatorShadow") as TextureRect
		await create_timer(indicator.DROP_DURATION + 0.03).timeout
		indicator.call("_on_mouse_entered")
		await create_timer(indicator.HOVER_LIFT_DURATION + 0.03).timeout
		_expect(
			visual.position.is_equal_approx(Vector2.ZERO)
			and shadow.position.is_equal_approx(EquipmentIndicatorStyle.SHADOW_OFFSET),
			"单击携带落地后，即使鼠标仍指向指示物也保持放下状态"
		)
		var pointer_exit := InputEventMouseMotion.new()
		pointer_exit.position = indicator.get_global_rect().end + Vector2(20.0, 20.0)
		indicator.call("_input", pointer_exit)
		indicator.call("_on_mouse_entered")
		await create_timer(indicator.HOVER_LIFT_DURATION + 0.03).timeout
		_expect(
			visual.position.is_equal_approx(Vector2(0.0, -indicator.HOVER_LIFT_OFFSET))
			and shadow.position.is_equal_approx(EquipmentIndicatorStyle.LIFTED_SHADOW_OFFSET),
			"单击携带落地后，鼠标真正离开再进入才允许抬起"
		)
	main.queue_free()
	await process_frame


func _test_owned_minion_ghost_and_conflict_return() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.front_row.clear_squads()
	main.back_row.clear_squads()

	var deployed_minion: OwnedCard = main.owned_card_collection.create_card(
		_minion_definition(&"ghosted_minion")
	)
	main._sync_legacy_collection_cards()
	main.active_card_type_filters.assign([CardData.CardType.MINION])
	main.current_collection_page = main.get_collection_spread_count() - 1
	main._build_collection_cards()
	var deployed_source_slot := _find_collection_slot_for_owned_card(main, deployed_minion)
	var deployed: bool = bool(main._transfer_card(
		{
			"kind": &"card",
			"card_data": deployed_minion.card_data,
			"owned_card": deployed_minion,
			"source_type": &"collection",
			"source_slot": deployed_source_slot,
		},
		&"board",
		main.back_row,
		0
	))
	var deployed_ghost := _find_collection_slot_for_owned_card(main, deployed_minion)
	var deployed_squad: SquadData = (
		main.back_row.get_squads()[0].get_squad_data()
		if not main.back_row.get_squads().is_empty()
		else null
	)
	_expect(
		deployed
		and deployed_squad != null
		and deployed_squad.get_owned_card(deployed_minion.card_data) == deployed_minion
		and deployed_ghost != null
		and bool(deployed_ghost.get_meta("is_deployed_ghost", false)),
		"随从上场保留OwnedCard实例，因此收藏立即显示对应虚影"
	)

	var source_minion: OwnedCard = main.owned_card_collection.create_card(
		_minion_definition(&"equipped_source")
	)
	var target_minion: OwnedCard = main.owned_card_collection.create_card(
		_minion_definition(&"equipped_target")
	)
	var source_item: OwnedCard = main.owned_card_collection.create_card(
		_equipment_definition(&"returned_source_item")
	)
	var target_item: OwnedCard = main.owned_card_collection.create_card(
		_equipment_definition(&"returned_target_item")
	)
	main._sync_legacy_collection_cards()
	var source_squad := SquadData.from_owned_card(source_minion)
	var target_squad := SquadData.from_owned_card(target_minion)
	source_squad.equip_item(source_item, Vector2(22.0, 40.0))
	target_squad.equip_item(target_item, Vector2(72.0, 88.0))
	var target_slot: BoardSlot = main.front_row.add_squad(target_squad, 0)
	var source_slot: BoardSlot = main.front_row.add_squad(source_squad, 1)
	main.active_card_type_filters.assign([CardData.CardType.EQUIPMENT])
	main.current_collection_page = main.get_collection_spread_count() - 1
	var result_squad := target_squad.duplicate_squad()
	result_squad.insert_card(
		source_minion.card_data,
		1,
		SquadData.TwoCardLayout.COMPACT
	)
	result_squad.bind_owned_card(source_minion.card_data, source_minion)
	result_squad.merge_equipment_from(source_squad)
	var merged: bool = bool(main._transfer_drop_intent(
		{
			"kind": &"card",
			"card_data": source_minion.card_data,
			"owned_card": source_minion,
			"source_type": &"board",
			"source_row": main.front_row,
			"source_slot": source_slot,
			"squad_data": source_squad,
			"drop_intent": {
				"operation": &"merge_card",
				"card_index": 1,
				"target_slot": target_slot,
				"result_squad": result_squad,
			},
		},
		main.front_row
	))
	var source_item_slot := _find_collection_slot_for_owned_card(main, source_item)
	var target_item_slot := _find_collection_slot_for_owned_card(main, target_item)
	await process_frame
	await process_frame
	var source_return_animating := (
		(source_item_slot.get_child(0) as CardView).is_layout_animating()
		if source_item_slot != null
		else false
	)
	var target_return_animating := (
		(target_item_slot.get_child(0) as CardView).is_layout_animating()
		if target_item_slot != null
		else false
	)
	_expect(
		merged
		and target_slot.get_squad_data().get_equipped_item() == null
		and not is_instance_valid(source_slot)
		and source_item_slot != null
		and target_item_slot != null
		and not bool(source_item_slot.get_meta("is_deployed_ghost", false))
		and not bool(target_item_slot.get_meta("is_deployed_ghost", false))
		and source_return_animating
		and target_return_animating,
		"两张已装备卡合并时，两件装备立即解除并分别动画返回收藏"
	)
	main.queue_free()
	await process_frame


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


func _find_collection_slot_for_owned_card(main: Node, owned_card: OwnedCard) -> Control:
	for slot: Control in main._get_collection_card_slots():
		if slot.get_meta("owned_card", null) == owned_card:
			return slot
	return null


func _empty_rows() -> Dictionary:
	return {
		&"player_front": [],
		&"player_back": [],
		&"enemy_front": [],
		&"enemy_back": [],
	}


func _minion_definition(card_id: StringName) -> CardData:
	var definition := CardData.new()
	definition.id = card_id
	definition.display_name = String(card_id)
	definition.card_type = CardData.CardType.MINION
	definition.runes.assign([
		CardData.ElementType.FIRE,
		CardData.ElementType.WATER,
		CardData.ElementType.WOOD,
	])
	return definition


func _equipment_definition(card_id: StringName) -> CardData:
	var definition := CardData.new()
	definition.id = card_id
	definition.display_name = String(card_id)
	definition.card_type = CardData.CardType.EQUIPMENT
	return definition


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	failures += 1
	push_error("FAIL: %s" % message)
