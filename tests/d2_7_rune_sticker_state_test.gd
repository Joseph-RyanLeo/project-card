extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if value:
		print("PASS: " + message)
	else:
		failures += 1
		push_error(message)

func pattern(elements: Array[int], wildcard: int = -1, chaos: int = -1) -> RunePatternResult:
	var slots: Array[Dictionary] = []
	for index: int in elements.size():
		slots.append({"element": elements[index], "sticker_id": &"万能贴纸" if index == wildcard else (&"混沌贴纸" if index == chaos else &"")})
	return RunePatternRules.identify_slots(slots)

func _run() -> void:
	var full_house := pattern([1, 1, 0, 0, 0], 2)
	check(full_house.pattern_type == RunePatternResult.PatternType.FULL_HOUSE and full_house.visible_runes[2] == CardData.ElementType.WATER, "水水万能火火按左侧优先组成三水二火")
	var four := pattern([1, 1, 1, 0, 0], 3)
	check(four.pattern_type == RunePatternResult.PatternType.FOUR_OF_A_KIND, "万能优先组成四条")
	var left_pair := pattern([2, 3, 1, 0, 2], 3)
	check(left_pair.visible_runes[3] == CardData.ElementType.WATER, "同牌型按实际参与符文位置取左侧，不按元素枚举")
	check(pattern([1, 1, 0], -1, 0).participating_indices.size() == 2, "混沌仍按当前元素正常参与牌型识别")
	var has_chaos_bonus_field := false
	for property: Dictionary in pattern([1, 1, 0], -1, 0).get_property_list():
		if property.get("name", "") == "sticker_multiplier_bonus":
			has_chaos_bonus_field = true
	check(not has_chaos_bonus_field, "牌型结果不再携带混沌倍率附加值")
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var owned: OwnedCard
	for value: OwnedCard in main.owned_card_collection.get_cards():
		if value.card_data.card_type == CardData.CardType.MINION:
			owned = value
			break
	var id := owned.instance_id
	var original: int = owned.card_data.runes[0]
	var sticker := {"instance_id": &"unit_rune", "emblem_id": &"火贴纸", "element": 0, "temporary": false}
	owned.set_rune_sticker(0, sticker)
	var snap := owned.capture_state()
	owned.set_rune_sticker(0, {})
	check(owned.restore_state(snap) and owned.get_effective_rune(0) == CardData.ElementType.FIRE, "战前快照独立保留符文贴纸")
	main.emblem_library.return_sticker({"instance_id": &"returned_seed", "emblem_id": &"种子", "saved_progress": 2})
	main._next_developer_emblem_instance = 101
	check(main.save_run_to_path("/private/tmp/project-card-rune-state.json") == OK, "符文及返还工作包保存成功")
	owned.set_rune_sticker(0, {})
	main.emblem_library._returned.clear()
	check(main.load_run_from_path("/private/tmp/project-card-rune-state.json"), "符文贴纸存档可以实际载入")
	owned = main.owned_card_collection.get_by_instance_id(id)
	check(owned.get_effective_rune(0) == CardData.ElementType.FIRE and owned.card_data.runes[0] == original, "载入保留实例覆盖且底层符文未被改写")
	check(main.emblem_library._returned.size() == 1 and int(main.emblem_library._returned[0].saved_progress) == 2 and main._next_developer_emblem_instance == 101, "返还贴纸身份、种子进度和实例序号通过存档恢复")
	main._open_card_inspection(owned.card_data, owned)
	await process_frame
	var card: CardView = main._inspection_card_view
	var highlights: Array[int] = [0]
	card.set_rune_pattern_highlights(highlights)
	check(card.is_rune_scheduled_for_active_animation(0), "参与牌型的符文贴纸加入现有全局闪耀周期")
	check(card.rune_row.get_child(0).get_child(0).texture.get_size() == Vector2(27, 27), "实际卡面使用贴纸原生27像素纹理")
	check(card.get_sticker_tooltip(Vector2(19, 119)).contains("火贴纸"), "卡面贴纸提示包含名称及效果说明")
	check(EmblemLibraryData.get_wound_tooltip(&"中毒Ⅰ").contains("每2秒损失1点生命值"), "伤势卡面提示读取CSV规范描述")
	check(EmblemLibraryData.get_wound_definitions().size() == 27, "本地资料目录包含27条伤势提示")
	check(RuneStickerStyle.get_emblem_id(5) == &"万能贴纸" and RuneStickerStyle.get_emblem_id(6) == &"混沌贴纸", "第六枚彩色贴纸对应万能，第七枚问号贴纸对应混沌")
	main._close_card_inspection()
	main.queue_free()
	await process_frame
	print("Rune sticker state failures: ", failures)
	quit(1 if failures else 0)
