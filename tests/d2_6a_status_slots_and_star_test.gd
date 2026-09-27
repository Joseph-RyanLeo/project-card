extends SceneTree

const CardSlotLayout = preload("res://scripts/data/card_slot_layout.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const BattleController = preload("res://scripts/battle/battle_controller.gd")
const BattleSquadState = preload("res://scripts/battle/battle_squad_state.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const CelestialIndicator = preload("res://scripts/data/celestial_indicator.gd")
const SquadData = preload("res://scripts/data/squad_data.gd")
const EquipmentIndicatorStyle = preload("res://scripts/ui/equipment_indicator_style.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_test_default_and_custom_slot_layout()
	_test_saved_layout_skips_default_enumeration()
	await _test_real_status_texture_rendering()
	_test_star_transfer_accumulates_in_battle_copy()
	print("D2-6A status slot and star accumulation checks: %d failures" % failures)
	quit(failures)


func _test_default_and_custom_slot_layout() -> void:
	var card := CardData.new()
	var expected_counts: Array[Vector2i] = [
		Vector2i(2, 2), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4), Vector2i(3, 5),
	]
	var defaults_match := true
	var default_slot_counts_match := true
	var layout_rng := RandomNumberGenerator.new()
	layout_rng.seed = 20260924
	for rarity_index: int in expected_counts.size():
		card.rarity = rarity_index as CardData.Rarity
		var sampled_layout := CardSlotLayout.create_random_layout(card, layout_rng)
		defaults_match = defaults_match and CardSlotLayout.resolve_counts(card) == expected_counts[rarity_index]
		defaults_match = defaults_match and CardSlotLayout.is_valid_layout(card, sampled_layout)
		default_slot_counts_match = default_slot_counts_match and (
			CardSlotLayout.get_slot_definitions(card).size()
			== expected_counts[rarity_index].x + expected_counts[rarity_index].y
		)
	_expect(
		defaults_match and default_slot_counts_match,
		"I至V品级默认槽数正确，实例随机布局和无实例显示布局均符合槽数规则"
	)
	card.rarity = CardData.Rarity.I
	card.wound_slot_count = 4
	card.emblem_slot_count = 4
	var definitions := CardSlotLayout.get_slot_definitions(card)
	var expected_positions := [
		Vector2(-2, 39), Vector2(-2, 55), Vector2(-2, 71), Vector2(-2, 87),
		Vector2(86, 53), Vector2(86, 37), Vector2(86, 21), Vector2(86, 5),
	]
	var matches := definitions.size() == expected_positions.size()
	for index: int in mini(definitions.size(), expected_positions.size()):
		matches = matches and definitions[index]["position"] == expected_positions[index]
	_expect(matches, "默认8槽位置保留左上到右下视觉坐标与右侧反向编号")

	card.wound_slot_count = 2
	card.emblem_slot_count = 2
	card.slot_layout = [
		CardSlotLayout.Kind.EMBLEM,
		CardSlotLayout.Kind.WOUND,
		-1, -1,
		CardSlotLayout.Kind.WOUND,
		CardSlotLayout.Kind.EMBLEM,
		-1, -1,
	]
	definitions = CardSlotLayout.get_slot_definitions(card)
	_expect(
		definitions.size() == 4
		and int(definitions[0]["kind"]) == CardSlotLayout.Kind.EMBLEM
		and int(definitions[1]["kind"]) == CardSlotLayout.Kind.WOUND
		and definitions[2]["position"] == Vector2(86, 53),
		"卡牌可用slot_layout覆盖默认类别并保留槽位编号"
	)


func _test_saved_layout_skips_default_enumeration() -> void:
	var definition := CardData.new()
	definition.card_type = CardData.CardType.MINION
	definition.rarity = CardData.Rarity.I
	var owned := OwnedCard.new()
	owned.card_data = definition
	owned.slot_layout = [CardSlotLayout.Kind.EMBLEM, CardSlotLayout.Kind.WOUND, -1, -1,
		CardSlotLayout.Kind.WOUND, CardSlotLayout.Kind.EMBLEM, -1, -1]
	CardSlotLayout._stable_layout_cache.clear()
	var saved_layout_stayed_unchanged := true
	for _iteration: int in 10:
		saved_layout_stayed_unchanged = saved_layout_stayed_unchanged and (
			CardSlotLayout.get_slot_definitions(definition, owned).size() == 4
			and CardSlotLayout._stable_layout_cache.is_empty()
		)
	_expect(saved_layout_stayed_unchanged, "重复读取有效实例布局不枚举或填充默认布局缓存")
	var first_default := CardSlotLayout.get_stable_layout(definition)
	var cache_warmed := CardSlotLayout._stable_layout_cache.size() == 1
	first_default[0] = 99
	var repeated_default := CardSlotLayout.get_stable_layout(definition)
	_expect(
		cache_warmed
		and CardSlotLayout._stable_layout_cache.size() == 1
		and repeated_default[0] != 99
		and CardSlotLayout.is_valid_layout(definition, repeated_default),
		"默认布局只缓存首次备用结果，调用方拿到副本且无法污染缓存"
	)


func _test_real_status_texture_rendering() -> void:
	var definition := load("res://resources/cards/berserker_vanguard.tres") as CardData
	var owned := OwnedCard.new()
	owned.initialize(definition, &"status_slot_test", 0)
	var layout_definitions := CardSlotLayout.get_slot_definitions(definition, owned)
	var emblem_position := Vector2.ZERO
	var wound_position := Vector2.ZERO
	for slot: Dictionary in layout_definitions:
		if int(slot.kind) == CardSlotLayout.Kind.EMBLEM and emblem_position == Vector2.ZERO:
			owned.emblem_slots[int(slot.storage_index)] = {"emblem_id": &"火把"}
			emblem_position = slot.position
		elif int(slot.kind) == CardSlotLayout.Kind.WOUND and wound_position == Vector2.ZERO:
			owned.wound_slots[int(slot.storage_index)] = {"wound_id": &"中毒Ⅰ", "level": 1}
			wound_position = slot.position
	var view := load("res://scenes/ui/CardView.tscn").instantiate() as CardView
	root.add_child(view)
	view.set_card_data(definition)
	view.set_owned_card(owned)
	await process_frame
	var layer := view.get_node("StatusSlotLayer") as Control
	var first_status := layer.get_child(0) as TextureRect
	var second_status := layer.get_child(1) as TextureRect
	_expect(
		layer.visible
		and layer.get_child_count() == 2
		and [first_status.position, second_status.position].has(emblem_position)
		and [first_status.position, second_status.position].has(wound_position),
		"真实卡牌按OwnedCard布局绘制已有纹章与伤势"
	)
	_expect(
		first_status.texture != null
		and second_status.texture != null,
		"CSV对应的火把与中毒Ⅰ使用原生14×14贴纸纹理"
	)
	var emblem_slot_index := -1
	var wound_slot_index := -1
	for slot: Dictionary in layout_definitions:
		if int(slot.kind) == CardSlotLayout.Kind.EMBLEM and int(slot.storage_index) == 0:
			emblem_slot_index = int(slot.slot_index)
		elif int(slot.kind) == CardSlotLayout.Kind.WOUND and int(slot.storage_index) == 0:
			wound_slot_index = int(slot.slot_index)
	var emblem_visual := layer.get_node("Status_%d" % emblem_slot_index) as TextureRect
	var wound_visual := layer.get_node("Status_%d" % wound_slot_index) as TextureRect
	var emblem_visual_id := emblem_visual.get_instance_id()
	var wound_visual_id := wound_visual.get_instance_id()
	view.set_battle_status_slot_states([0], [0])
	var dimming_applied := (
		is_equal_approx(emblem_visual.modulate.a, 0.45)
		and is_equal_approx(wound_visual.modulate.a, 0.35)
	)
	view.set_battle_status_slot_states([0], [0])
	_expect(
		dimming_applied
		and emblem_visual.get_instance_id() == emblem_visual_id
		and wound_visual.get_instance_id() == wound_visual_id,
		"纹章消耗和伤势遮蔽合并刷新，并复用既有贴纸节点"
	)
	var rune_overrides := {0: CardData.ElementType.WATER}
	view.set_battle_rune_element_overrides(rune_overrides)
	var rune_visual_id := (view.rune_row.get_child(0).get_child(0) as TextureRect).get_instance_id()
	view.set_battle_rune_element_overrides(rune_overrides)
	_expect(
		(view.rune_row.get_child(0).get_child(0) as TextureRect).get_instance_id() == rune_visual_id,
		"重复提交相同符文元素覆盖不会重建符文节点"
	)
	view.set_battle_rune_element_overrides({0: CardData.ElementType.FIRE})
	_expect(
		(view.rune_row.get_child(0).get_child(0) as TextureRect).texture
		== view._get_rune_texture(CardData.ElementType.FIRE),
		"变化的符文元素覆盖仍立即更新实际显示"
	)
	view.clear_battle_rune_element_overrides()
	view.set_battle_rune_element_overrides(rune_overrides)
	view.set_battle_status_slot_states([0], [0])
	var replacement := OwnedCard.new()
	replacement.initialize(definition, &"status_slot_test_switch", 1)
	replacement.slot_layout = owned.slot_layout.duplicate()
	replacement.emblem_slots = owned.emblem_slots.duplicate(true)
	replacement.wound_slots = owned.wound_slots.duplicate(true)
	view.set_owned_card(replacement)
	_expect(
		view._battle_rune_element_overrides.is_empty()
		and is_equal_approx(emblem_visual.modulate.a, 1.0)
		and is_equal_approx(wound_visual.modulate.a, 1.0),
		"切换OwnedCard实例清除旧战斗覆盖并恢复新实例贴纸亮度"
	)
	view.set_owned_card(owned)
	var original_wound_texture := wound_visual.texture
	owned.wound_slots[0] = {"wound_id": &"中毒Ⅱ", "level": 2}
	view.set_owned_card(owned)
	var wound_replacement_rendered := (
		wound_visual.get_instance_id() == wound_visual_id
		and wound_visual.texture != original_wound_texture
	)
	owned.wound_slots[0] = {"wound_id": &"中毒Ⅰ", "level": 1}
	view.set_owned_card(owned)
	view.set_battle_status_slot_states([], [])
	var battle_dimming_cleared := (
		is_equal_approx(emblem_visual.modulate.a, 1.0)
		and is_equal_approx(wound_visual.modulate.a, 1.0)
	)
	owned.emblem_slots[0] = {}
	owned.wound_slots[0] = {}
	view.set_owned_card(owned)
	await process_frame
	_expect(
		battle_dimming_cleared
		and wound_replacement_rendered
		and layer.visible
		and layer.get_child_count() == 0,
		"战斗清理恢复贴纸亮度，伤势替换更新纹理且移除后显示空槽提示"
	)
	var attachment_bounds := CardView.get_attachment_center_bounds(
		EquipmentIndicatorStyle.get_texture(definition),
		EquipmentIndicatorStyle.DISPLAY_SIZE
	)
	_expect(
		CardView.ATTACHMENT_PLACEMENT_POSITION == Vector2(8, -4)
		and CardView.ATTACHMENT_PLACEMENT_SIZE == Vector2(81, 105)
		and attachment_bounds.position.x >= CardView.ATTACHMENT_PLACEMENT_POSITION.x
		and attachment_bounds.position.y >= CardView.ATTACHMENT_PLACEMENT_POSITION.y
		and attachment_bounds.end.x <= CardView.ATTACHMENT_PLACEMENT_POSITION.x + CardView.ATTACHMENT_PLACEMENT_SIZE.x
		and attachment_bounds.end.y <= CardView.ATTACHMENT_PLACEMENT_POSITION.y + CardView.ATTACHMENT_PLACEMENT_SIZE.y,
		"装备与日月星指示物的可见中心限制在用户确认的81×105白色区域"
	)
	view.queue_free()
	await process_frame


func _test_star_transfer_accumulates_in_battle_copy() -> void:
	var star_owner := SquadData.from_card(_card(&"star_owner"))
	var star := CelestialIndicator.new()
	star.kind = CelestialIndicator.Kind.STAR
	star.instance_id = &"accumulating_star"
	star_owner.attach_indicator(star, Vector2(40, 60), 1)
	var first_recipient := SquadData.from_card(_card(&"first_recipient"))
	var second_recipient := SquadData.from_card(_card(&"second_recipient"))
	var enemy := SquadData.from_card(_card(&"enemy"))
	var battle := BattleController.new()
	root.add_child(battle)
	battle.start_battle(
		[
			_entry(star_owner, 0),
			_entry(first_recipient, 1),
			_entry(second_recipient, 2),
		],
		[_entry(enemy, 0, true)],
		987,
		false
	)
	var source_state := battle.player_states[0] as BattleSquadState
	source_state.current_health = 0.0
	battle._finalize_batch()
	var first_state := battle.player_states[1] as BattleSquadState
	var first_indicator := first_state.squad_data.indicator_attachments[0]["indicator"] as CelestialIndicator
	_expect(
		first_indicator.star_transfer_count == 1
		and first_state.get_display_action_value() == 4,
		"星星首次传播为基础+1并额外累计1"
	)
	first_state.current_health = 0.0
	battle._finalize_batch()
	var second_state := battle.player_states[2] as BattleSquadState
	var second_indicator := second_state.squad_data.indicator_attachments[0]["indicator"] as CelestialIndicator
	_expect(
		second_indicator.star_transfer_count == 2
		and second_state.get_display_action_value() == 5,
		"星星第二次传播保留累计并额外累计2，不重置为+2"
	)
	var original_indicator := star_owner.indicator_attachments[0]["indicator"] as CelestialIndicator
	_expect(
		original_indicator.star_transfer_count == 0
		and star_owner.has_indicator(CelestialIndicator.Kind.STAR),
		"星星传播只修改战斗副本，战前归属与初始+1保持不变"
	)
	battle.free()


func _card(card_id: StringName) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = String(card_id)
	card.base_value = 2
	card.max_health = 100
	card.cooldown_seconds = 9.9
	return card


func _entry(squad: SquadData, index: int, enemy: bool = false) -> Dictionary:
	return {
		"squad_data": squad,
		"row_key": &"enemy_front" if enemy else &"player_front",
		"formation_index": index,
	}


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
