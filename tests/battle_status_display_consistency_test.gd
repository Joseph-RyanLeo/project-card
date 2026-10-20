extends SceneTree

## 正式卡牌、真实开场与主场景的状态显示回归；不改写共享CardData。
const MAIN := preload("res://scenes/Main.tscn")
const MainScript := preload("res://scripts/main.gd")
const CARD_VIEW := preload("res://scenes/ui/CardView.tscn")
var failures := 0
var assertions := 0
var main: MainScript

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func add_card(id: String, row: BattlefieldRow) -> OwnedCard:
	var owned := main.owned_card_collection.create_card(load("res://resources/cards/%s.tres" % id))
	row.add_squad(SquadData.from_owned_card(owned), row.get_squad_count())
	return owned

func state_for(owned: OwnedCard) -> BattleSquadState:
	return main._find_battle_state_for_squad(main._find_squad_for_owned_card(owned))

func view_for(state: BattleSquadState) -> CardView:
	var slot: BoardSlot = main._battle_state_slots[state]
	return slot.get_card_view(state.squad_data.horizontal_cards[0])

func status_visual(view: CardView, kind: int, index: int) -> TextureRect:
	for definition: Dictionary in CardSlotLayout.get_slot_definitions(view.card_data, view.get_owned_card()):
		if int(definition.kind) == kind and int(definition.storage_index) == index:
			return view._status_slot_layer.get_node_or_null("Status_%d" % int(definition.slot_index)) as TextureRect
	return null

func check_emblems(state: BattleSquadState, label: String) -> void:
	var view := view_for(state)
	var owned := view.get_owned_card()
	for index: int in owned.emblem_slots.size():
		var visual := status_visual(view, CardSlotLayout.Kind.EMBLEM, index)
		var id := StringName(owned.emblem_slots[index].get("emblem_id", ""))
		check((visual == null) == id.is_empty(), label + "槽位%d有无一致" % index)
		if visual != null and not id.is_empty():
			check(visual.texture == StatusIndicatorStyle.get_texture(CardSlotLayout.Kind.EMBLEM, id), label + "槽位%d纹理一致" % index)

func inspect(state: BattleSquadState) -> CardView:
	var source := view_for(state)
	main._open_card_inspection(source.card_data, source.get_owned_card(), source)
	await process_frame
	return main._inspection_card_view

func close_inspection() -> void:
	main._close_card_inspection()
	await create_timer(0.35, true).timeout

func capture(filename: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():
		return
	await create_timer(0.3, true).timeout
	await RenderingServer.frame_post_draw
	var directory := "res://docs/previews/battle_status_display_20261019"
	DirAccess.make_dir_recursive_absolute(directory)
	check(root.get_texture().get_image().save_png(directory + "/" + filename) == OK, "保存实际渲染图" + filename)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	main = MAIN.instantiate()
	main.run_save_path = "/private/tmp/project-card-status-display-save.json"
	root.add_child(main)
	await process_frame
	await process_frame
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]:
		row.clear_squads()
	var tree := add_card("moonlight_treant", main.front_row)
	add_card("mobilization_machine", main.front_row)
	var scout := add_card("scout", main.front_row)
	for index: int in scout.emblem_slots.size():
		scout.set_emblem_slot(index, {"emblem_id": &"盾牌Ⅰ", "instance_id": StringName("upgrade:%d" % index)})
	var golem := add_card("golden_golem", main.back_row)
	golem.set_emblem_slot(0, {"emblem_id": &"火把", "instance_id": &"remove:torch"})
	var spirit := add_card("ember_spirit", main.back_row)
	spirit.resolved_runes.assign([CardData.ElementType.WATER, CardData.ElementType.WOOD, CardData.ElementType.LIGHT])
	spirit.rune_revealed.assign([true, true, true])
	var enemy := add_card("ironhand_arno", main.enemy_front_row)
	enemy.set_emblem_slot(0, {"emblem_id": &"盾牌Ⅲ", "instance_id": &"spent:shield"})
	enemy.set_wound_slot(0, {"wound_id": &"中毒Ⅰ", "level": 1})
	for owned: OwnedCard in [scout, golem, spirit, enemy]:
		main._refresh_owned_card_status_visuals(owned)
	await process_frame
	await process_frame
	check(main.start_battle(1013, false), "主场景正式开战")
	await process_frame
	var controller := main.battle_controller
	var tree_state := state_for(tree)
	var scout_state := state_for(scout)
	var golem_state := state_for(golem)
	var spirit_state := state_for(spirit)
	var enemy_state := controller.enemy_states[0]
	enemy = enemy_state.squad_data.get_effect_source_instance()
	check(controller.ironwall.temporary_emblems.size() == 2, "动员实际给两名邻居新增或升级纹章")
	check(tree.emblem_slots.any(func(s: Dictionary) -> bool: return not s.is_empty()), "树人实际获得本场纹章")
	check(scout.emblem_slots.any(func(s: Dictionary) -> bool: return s.get("emblem_id") == &"盾牌Ⅱ"), "满槽邻居实际升级纹章")
	check(golem.emblem_slots[0].is_empty() and golem_state.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 10, "魔像实际移除纹章并获得强化")
	check_emblems(tree_state, "树人新增")
	check_emblems(scout_state, "侦察兵升级")
	check_emblems(golem_state, "魔像移除")
	var inspected := await inspect(tree_state)
	check(inspected._status_slot_signature[3] == view_for(tree_state)._status_slot_signature[3], "检视与小卡纹章内容一致")
	await close_inspection()
	check(spirit_state.runtime_rune_overrides.size() == 2, "余火实际将两个符文临时转火")
	var spirit_view := view_for(spirit_state)
	inspected = await inspect(spirit_state)
	check(inspected._battle_rune_element_overrides == spirit_view._battle_rune_element_overrides, "检视沿用真实临时元素")
	check(inspected.get_highlighted_rune_indices() == spirit_view.get_highlighted_rune_indices(), "检视牌型流光与实际转火牌型一致")
	for index: int in 3:
		check(inspected._get_display_rune_element(index) == spirit_view._get_display_rune_element(index), "检视符文%d实际绘制元素一致" % index)
	await close_inspection()
	var spirit_card := spirit_state.squad_data.horizontal_cards[0]
	check(spirit_state.mask_rune_slot(spirit_card, 0), "真实遮蔽符文")
	main._on_battle_states_changed()
	inspected = await inspect(spirit_state)
	check(inspected.get_battle_masked_rune_indices() == spirit_view.get_battle_masked_rune_indices(), "检视符文遮蔽与小卡一致")
	check(inspected.get_highlighted_rune_indices() == spirit_view.get_highlighted_rune_indices(), "遮蔽后检视牌型流光与实际一致")
	check(not inspected.rune_row.get_child(0).get_child(0).visible, "检视实际隐藏被遮蔽符文图案")
	await close_inspection()
	var event := controller.twisted_vein.make_event(tree_state, enemy_state, 1, CardData.ActionType.MELEE, true, "盾牌显示回归")
	event.is_base_action = true
	controller._apply_effect_event(event)
	check(not controller.get_spent_emblem_slots_by_card(enemy_state).is_empty(), "盾牌Ⅲ实际消费近战免疫")
	var injury_id := StringName("%s:wound:0" % enemy.instance_id)
	check(enemy_state.mask_injury(injury_id, 777), "真实遮蔽伤势")
	main._on_battle_states_changed()
	var enemy_view := view_for(enemy_state)
	inspected = await inspect(enemy_state)
	check(inspected._battle_spent_emblem_slots == enemy_view._battle_spent_emblem_slots, "检视保留已耗尽纹章状态")
	check(inspected._battle_masked_wound_slots == enemy_view._battle_masked_wound_slots, "检视保留伤势遮蔽状态")
	var inspected_shield := status_visual(inspected, CardSlotLayout.Kind.EMBLEM, 0)
	check(inspected_shield != null and is_equal_approx(inspected_shield.modulate.a, 0.45), "检视实际盾牌图标变暗")
	await close_inspection()
	var snapshot := CARD_VIEW.instantiate() as CardView
	snapshot.set_card_data(enemy_view.card_data)
	snapshot.set_owned_card(enemy)
	snapshot.copy_runtime_display_state_from(enemy_view)
	root.add_child(snapshot)
	check(snapshot._battle_spent_emblem_slots == enemy_view._battle_spent_emblem_slots, "动画快照保留耗尽纹章")
	check(snapshot._battle_masked_wound_slots == enemy_view._battle_masked_wound_slots, "动画快照保留遮蔽伤势")
	check(snapshot._target_priority_preview == enemy_view._target_priority_preview, "动画快照保留实际受击权重")
	check(is_equal_approx(status_visual(snapshot, CardSlotLayout.Kind.EMBLEM, 0).modulate.a, 0.45), "快照实际盾牌图案变暗")
	check(is_equal_approx(status_visual(snapshot, CardSlotLayout.Kind.WOUND, 0).modulate.a, 0.35), "快照实际伤势图案变暗")
	snapshot.copy_runtime_display_state_from(spirit_view)
	check(snapshot.get_highlighted_rune_indices() == spirit_view.get_highlighted_rune_indices(), "动画快照保留实际牌型流光")
	snapshot.queue_free()
	var stable_visual := status_visual(view_for(scout_state), CardSlotLayout.Kind.EMBLEM, 0)
	var stable_id := stable_visual.get_instance_id() if stable_visual != null else 0
	main._on_battle_states_changed()
	check(stable_id != 0 and status_visual(view_for(scout_state), CardSlotLayout.Kind.EMBLEM, 0).get_instance_id() == stable_id, "相同状态刷新复用图标节点")
	controller.ironwall.restore_temporary()
	main._on_battle_states_changed()
	check(tree.emblem_slots.all(func(s: Dictionary) -> bool: return s.is_empty()), "本场新增纹章撤销")
	check(scout.emblem_slots.all(func(s: Dictionary) -> bool: return s.get("emblem_id") == &"盾牌Ⅰ"), "本场升级恢复原等级")
	check_emblems(tree_state, "撤销新增")
	check_emblems(scout_state, "撤销升级")
	controller.ironwall.grant_temporary_emblem(tree_state)
	main._on_battle_states_changed()
	check_emblems(tree_state, "原位再次新增")
	await capture("battlefield.png")
	inspected = await inspect(tree_state)
	check(inspected._status_slot_signature[3] == view_for(tree_state)._status_slot_signature[3], "再次新增后检视与小卡一致")
	await capture("inspection.png")
	await close_inspection()
	controller.ironwall.restore_temporary()
	main.queue_free()
	await process_frame
	await process_frame
	print("战斗状态显示一致性：%d条断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
