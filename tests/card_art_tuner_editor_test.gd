extends SceneTree

## 用正式场景和真实临时资源验证发现、筛选、草稿与保存；不改动正式卡牌数值。
const SCENE := preload("res://scenes/tools/CardArtTuner.tscn")
const PROBE_PATH := "res://resources/cards/_card_tuner_discovery_probe.tres"
const FIXTURE_PATH := "/private/tmp/project-card-tuner-edit-fixture.tres"
var failures := 0
var assertions := 0
var tuner: CardArtTuner
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error("FAIL: " + message)
func enter_text(input: LineEdit, value: String) -> void:
	# LineEdit程序赋值不会发出text_changed；发出与用户输入相同的控件信号。
	input.text = value
	input.text_changed.emit(value)
func select_pack(pack: StringName) -> void:
	for index: int in tuner.pack_selector.item_count:
		if tuner.pack_selector.get_item_metadata(index) == pack:
			tuner.pack_selector.select(index)
			tuner.pack_selector.item_selected.emit(index)
			return
	check(false, "存在卡包：" + String(pack))
func select_type(type: int) -> void:
	for index: int in tuner.card_type_selector.item_count:
		if tuner.card_type_selector.get_item_id(index) == type:
			tuner.card_type_selector.select(index)
			tuner.card_type_selector.item_selected.emit(index)
			return
	check(false, "存在种类")
func _run() -> void:
	root.size = Vector2i(1280, 720)
	tuner = SCENE.instantiate()
	root.add_child(tuner)
	await process_frame
	await process_frame
	select_pack(&"ironwall_inscription")
	check(tuner.card_selector.item_count == 38, "铁壁38张自动纳入，包含衍生与缺图卡")
	select_type(CardData.CardType.MINION)
	check(tuner.card_selector.item_count == 21, "铁壁随从筛选21张")
	select_type(CardData.CardType.EQUIPMENT)
	check(tuner.card_selector.item_count == 13, "铁壁装备筛选13张")
	select_type(CardData.CardType.SPELL)
	check(tuner.card_selector.item_count == 3 and not tuner.value_spin_box.editable and not tuner.health_spin_box.editable and not tuner.armor_spin_box.editable, "铁壁法术3张且无通用属性编辑")
	select_type(CardData.CardType.RESOURCE)
	check(tuner.card_selector.item_count == 1 and tuner.card_data.id == &"gear_scrap", "铁壁衍生资源收录")
	check(not tuner.value_spin_box.editable and tuner.health_spin_box.editable and tuner.armor_spin_box.editable, "资源只编辑生命护甲")
	select_pack(&"silvermoon_chapter")
	select_type(CardArtTuner.ALL_CARD_TYPES)
	check(tuner.card_selector.item_count == 37, "银月37张自动纳入")
	select_pack(CardArtTuner.ALL_PACK_ID)
	select_pack(&"")
	check(tuner.card_selector.item_count > 0, "未指定卡包单独可选")
	for index: int in tuner.card_selector.item_count:
		check((load(tuner.card_selector.get_item_metadata(index)) as CardData).pack_id.is_empty(), "未指定卡包不混入有归属卡")
	select_pack(CardArtTuner.ALL_PACK_ID)
	var total := tuner.card_selector.item_count
	check(total == CardArtTuner.discover_card_resource_paths().size() and total > 150, "全部卡包与全部种类")
	enter_text(tuner.search_input, "field_beer_machine")
	check(tuner.card_selector.item_count == 1 and tuner.card_data.id == &"field_beer_machine", "ID搜索")
	enter_text(tuner.search_input, "随军啤酒机")
	check(tuner.card_selector.item_count == 1, "名称搜索")
	enter_text(tuner.search_input, "没有这张卡牌_123")
	check(tuner.card_selector.item_count == 0 and tuner.card_data == null and tuner.save_button.disabled, "空筛选不残留旧卡")
	enter_text(tuner.search_input, "")
	# 在打开的调整器中新增真实资源，刷新后自动发现，不需要再维护名单。
	check(not FileAccess.file_exists(PROBE_PATH), "临时探针不覆盖已有资源")
	if FileAccess.file_exists(PROBE_PATH): tuner.queue_free(); quit(1); return
	var probe := CardData.new()
	probe.id = &"tuner_discovery_probe"
	probe.display_name = "自动发现测试卡"
	probe.pack_id = &"tuner_discovery_test"
	check(ResourceSaver.save(probe, PROBE_PATH) == OK, "新增真实卡牌资源")
	tuner.refresh_catalog_button.pressed.emit()
	select_pack(&"tuner_discovery_test")
	check(tuner.card_selector.item_count == 1 and tuner.card_data.id == probe.id, "新增卡与新增卡包刷新后自动出现")
	select_pack(CardArtTuner.ALL_PACK_ID)
	# 编辑与持久化使用独立临时文件，正式卡牌保持原值。
	var fixture := CardData.new()
	fixture.id = &"tuner_edit_fixture"
	fixture.display_name = "原始名称"
	fixture.base_value = 3
	fixture.max_health = 8
	fixture.armor = 4
	fixture.cooldown_seconds = 6
	fixture.content_effect = &"kept_effect"
	fixture.keywords = [&"kept_keyword"]
	check(ResourceSaver.save(fixture, FIXTURE_PATH) == OK, "保存独立编辑夹具")
	tuner.card_data = load(FIXTURE_PATH)
	var source := tuner.card_data
	var original_bytes := FileAccess.get_file_as_bytes(FIXTURE_PATH)
	enter_text(tuner.name_input, "新的名称")
	tuner.value_spin_box.value = 7
	tuner.health_spin_box.value = 12
	tuner.armor_spin_box.value = 9
	tuner.preview_art_offset = Vector2i(2, -3)
	await process_frame
	check(tuner.preview_card.card_data.display_name == "新的名称" and tuner.preview_card.card_data.base_value == 7 and tuner.preview_card.card_data.max_health == 12 and tuner.preview_card.card_data.armor == 9, "控件实时更新卡面草稿")
	check(source.display_name == "原始名称" and source.base_value == 3 and FileAccess.get_file_as_bytes(FIXTURE_PATH) == original_bytes, "保存前内存定义与磁盘不变")
	tuner.card_data = load("res://resources/cards/field_beer_machine.tres")
	tuner.card_data = source
	check(tuner.name_input.text == "新的名称" and tuner.value_spin_box.value == 7 and tuner.preview_art_offset == Vector2i(2, -3), "切卡保留名称数值与取景草稿")
	tuner.name_input.grab_focus()
	var arrow := InputEventKey.new()
	arrow.keycode = KEY_LEFT
	arrow.pressed = true
	tuner._input(arrow)
	check(tuner.preview_art_offset == Vector2i(2, -3), "编辑文字时方向键不移动立绘")
	tuner.name_input.release_focus()
	tuner._input(arrow)
	check(tuner.preview_art_offset == Vector2i(1, -3), "无输入框焦点时方向键微调")
	tuner.save_button.pressed.emit()
	var persisted := ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as CardData
	check(persisted.display_name == "新的名称" and persisted.base_value == 7 and persisted.max_health == 12 and persisted.armor == 9 and persisted.art_offset == Vector2i(1, -3), "显式保存后磁盘读回五字段")
	check(persisted.id == &"tuner_edit_fixture" and persisted.cooldown_seconds == 6 and persisted.content_effect == &"kept_effect" and persisted.keywords == [&"kept_keyword"], "保存保留稳定ID冷却效果与关键词")
	check(not tuner._has_unsaved_changes(source), "保存清除当前草稿脏标记")
	enter_text(tuner.name_input, "")
	tuner.save_button.pressed.emit()
	persisted = ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as CardData
	check(persisted.display_name == "新的名称" and source.display_name == "新的名称", "空名拒绝保存且保留原值")
	tuner.reload_button.pressed.emit()
	check(tuner.name_input.text == "新的名称" and not tuner._has_unsaved_changes(source), "重新载入放弃草稿")
	# 模拟外部只更改未编辑字段：保存名称不能把最新护甲或规则覆盖回旧版本。
	persisted.armor = 15
	persisted.effect_text = "外部更新规则"
	ResourceSaver.save(persisted, FIXTURE_PATH)
	enter_text(tuner.name_input, "仅修改名称")
	tuner.save_button.pressed.emit()
	persisted = ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as CardData
	check(persisted.display_name == "仅修改名称" and persisted.armor == 15 and persisted.effect_text == "外部更新规则", "只叠加实际编辑字段，保留磁盘新资料")
	var equipment := (load("res://resources/cards/sentry_pistol.tres") as CardData).duplicate() as CardData
	tuner.card_data = equipment
	tuner.value_spin_box.value = -2
	tuner.health_spin_box.value = -3
	tuner.armor_spin_box.value = 11
	await process_frame
	check(tuner.preview_card.card_data.equipment_action_delta == -2 and tuner.preview_card.card_data.equipment_health_delta == -3 and tuner.preview_card.card_data.equipment_armor_delta == 11, "装备编辑正确的修正字段")
	check(equipment.equipment_action_delta == 1 and equipment.equipment_health_delta == 0 and equipment.equipment_armor_delta == 0, "装备预览不污染原资源")
	check(tuner.value_title.text == "数值修正" and tuner.health_title.text == "生命修正", "装备字段标签明确")
	await test_main_save_refresh(source)
	tuner.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROBE_PATH))
	DirAccess.remove_absolute(FIXTURE_PATH)
	print("卡面调整器重构：%d条断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)


func test_main_save_refresh(source: CardData) -> void:
	var display := (load("res://scenes/GameDisplay.tscn") as PackedScene).instantiate() as GameDisplay
	var main = display.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-tuner-main-checkpoint.json"
	root.add_child(display)
	await process_frame
	await process_frame
	var owned: OwnedCard = main.owned_card_collection.create_card(source)
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	main._refresh_preparation_effect_preview()
	display.open_card_art_tuner()
	var embedded: CardArtTuner = display._card_art_tuner
	embedded.card_data = source
	enter_text(embedded.name_input, "主场景新名称")
	embedded.value_spin_box.value = 9
	embedded.save_button.pressed.emit()
	await process_frame
	var matched := false
	for view: CardView in get_nodes_in_group(&"card_views"):
		if main.is_ancestor_of(view) and view.get_owned_card() == owned:
			matched = matched or view.card_data.display_name == "主场景新名称"
	check(matched, "显示壳保存信号刷新真实主场景卡面")
	var found := false
	for state: BattleSquadState in main.battle_controller.player_states:
		if state.get_action_source().id == source.id: found = state.get_display_action_value() == 9
	check(found, "准备阶段保存后重算实际数值预览")
	display.close_card_art_tuner()
	check(main.visible, "保存后正常返回已有主场景")
	display.queue_free()
	await process_frame
	await process_frame
