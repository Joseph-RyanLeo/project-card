extends Control

## 独立准备桌复用 Main 的牌堆、落点、检视、工具箱和法术栏。此节点只管理编辑数据。
const GameTable = preload("res://scenes/Main.tscn")
const Builder = preload("res://scripts/flow/enemy_encounter_builder.gd")
const Layout = preload("res://scripts/data/resource_hex_layout.gd")
const SAVE = preload("res://scripts/data/run_save_service.gd")
const BLOCK_ID := &"lineup_resource_block"
const SHAPE_MODAL_ALPHA := 0.40 # 编辑拼图期间压暗桌面的程度

var table: Control
var pack_picker: OptionButton
var registry: Dictionary
var seed_value := 12345
var tutorial := false
var _palette: Array[OwnedCard] = []
var _filtered: Array[OwnedCard] = []
var _palette_sequence := 0
var _pack: StringName
var _sticker_page := 0
var _sticker_sequence := 0
var _sticker_pages: Array[Dictionary] = []
var _sticker_page_button: Button
var _sticker_previous: Button
var _sticker_next: Button
var _refilling_stickers := false
var _shape_modal: Control
var _shape_card: OwnedCard
var _shape_cells: Array[Vector2i] = []
var _shape_confirm: Button
var _shape_count: Label
var _shape_grid: Control


func setup(definitions: Dictionary) -> void:
	registry = definitions
	table = GameTable.instantiate()
	table.name = "LineupBattleTable"
	table.lineup_workspace = self
	add_child(table)
	table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for item: Control in [table.ordinary_shop_entry_button, table.start_battle_button, table.battle_seed_panel, table.player_avatar_button, table.enemy_avatar]:
		item.hide()
	table._tabletop_park_button.hide()
	table.menu_bookmark_button.hide()
	table._escape_pause_menu.set_process_input(false)
	table.get_node("%EnemyBoardSection").hide()
	for row: BattlefieldRow in [table.front_row, table.back_row]:
		row.row_title = "敌方前排" if row == table.front_row else "敌方后排"
		var caption := Label.new()
		caption.text = "前排" if row == table.front_row else "后排"
		caption.position = Vector2(-9, row.position.y + 29) # 两字排布在左侧木边，避开视口裁切与卡槽
		caption.add_theme_font_size_override("font_size", 10) # 小字与资源板标题同级
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.get_parent().add_child(caption)
	table.scraper_count = 1
	table.emblem_library.set_scraper_count(table.scraper_count)
	table.player_resource_tray.authored_drop = resource_resolution
	table.player_resource_tray.authored_context_click = _resource_context_click
	table.recent_bookmark_button.tooltip_text = "阵容管理"
	_build_pack_filter()
	_build_sticker_pages()


func load_lineup(encounter: Dictionary, resources: ResourceBoardState, is_tutorial: bool, seed: int, legacy: bool) -> void:
	cancel_shape()
	table._close_card_inspection(true)
	table._close_toolbox_inspection(false)
	table._cancel_click_carry()
	tutorial = is_tutorial
	seed_value = seed
	table.resource_board_state = ResourceBoardState.new()
	table.prepared_spell_instance_ids.clear()
	table._restore_row_from_snapshot(table.front_row, [])
	table._restore_row_from_snapshot(table.back_row, [])
	table.owned_card_collection = OwnedCardCollection.new()
	_palette.clear()
	for owned: OwnedCard in encounter.get("owned", []):
		table.owned_card_collection.add_existing(owned)
		if legacy:
			for index: int in owned.rune_revealed.size():
				if not owned.rune_revealed[index]: continue
				owned.rune_revealed[index] = false
				owned.set_rune_sticker(index, {"emblem_id": "混沌贴纸", "instance_id": "%s:rune:%d" % [owned.instance_id, index], "element": owned.resolved_runes[index], "temporary": false, "element_sticker": true})
	for side: Dictionary in [{"row": table.front_row, "key": &"enemy_front"}, {"row": table.back_row, "key": &"enemy_back"}]:
		table._restore_row_from_snapshot(side.row, encounter.get("rows", {}).get(side.key, []))
	for spell: OwnedCard in encounter.get("spells", []): table.prepared_spell_instance_ids.append(spell.instance_id)
	table.resource_board_state.disabled_by_side.player.assign(resources.disabled_by_side.enemy)
	for owned: OwnedCard in resources.get_level_resource_cards("enemy"):
		table.owned_card_collection.add_existing(owned)
		table.resource_board_state.deployments.player[String(owned.instance_id)] = resources.deployments.enemy[String(owned.instance_id)].duplicate(true)
	_build_palette()
	table._sync_legacy_collection_cards()
	table._build_collection_cards()
	table._refresh_spell_preparation_tray()
	table._refresh_drag_availability()
	_set_sticker_page(_sticker_page)


func _build_palette() -> void:
	var block := CardData.new()
	block.id = BLOCK_ID
	block.display_name = "资源占位卡"
	block.card_type = CardData.CardType.RESOURCE
	block.max_health = 0
	block.art_texture = table.player_resource_tray.DISABLED_TEXTURE
	block.effect_text = "拖到资源区，标记一个禁用格。右键格子可移除。"
	var definitions: Array = registry.values()
	definitions.sort_custom(func(a: CardData, b: CardData) -> bool: return a.rarity > b.rarity if a.rarity != b.rarity else String(a.id) < String(b.id))
	definitions.push_front(block)
	for card: CardData in definitions:
		var actions: Array = card.acquisition_action_types if card.card_type == CardData.CardType.MINION and not card.acquisition_action_types.is_empty() else [card.action_type]
		for action: int in actions: _palette.append(_new_palette_card(card, action))


func _new_palette_card(card: CardData, action: int) -> OwnedCard:
	_palette_sequence += 1
	var owned := OwnedCard.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(card.id))
	owned.initialize(card, StringName("lineup_palette_%06d" % _palette_sequence), _palette_sequence, rng)
	if card.card_type == CardData.CardType.MINION:
		owned.set_acquired_action_type(action)
	table.owned_card_collection.add_existing(owned)
	return owned


func refill_palette() -> void:
	# 上场的实例留在桌上，原收藏位立即补一张同定义、同行动的空白副本。
	var templates := {}
	for index: int in _palette.size():
		var owned := _palette[index]
		if _is_placed(owned):
			_palette[index] = _new_palette_card(owned.card_data, owned.resolved_action_type)
		templates[_palette[index]] = true
	# 原拖放入口先解除部署，刷新收藏时一起清理离场的编辑实例。
	for owned: OwnedCard in table.owned_card_collection.get_cards():
		if not templates.has(owned) and not _is_placed(owned):
			table.owned_card_collection.remove_by_instance_id(owned.instance_id)


func _is_placed(owned: OwnedCard) -> bool:
	return table._is_spell_prepared(owned) or table._is_owned_card_deployed(owned)


func filtered_palette() -> Array[CardData]:
	_filtered.clear()
	var cards: Array[CardData] = []
	for owned: OwnedCard in _palette:
		var card := owned.card_data
		if not _pack.is_empty() and card.pack_id != _pack: continue
		if not table._card_matches_collection_filters(card, owned.resolved_action_type): continue
		_filtered.append(owned)
		cards.append(card)
	return cards


func palette_card_at(index: int) -> OwnedCard:
	return _filtered[index] if index >= 0 and index < _filtered.size() else null


func _build_pack_filter() -> void:
	var picker := OptionButton.new()
	pack_picker = picker
	picker.name = "LineupPackFilter"
	picker.add_item("全部卡包")
	picker.set_item_metadata(0, &"")
	picker.fit_to_longest_item = false
	picker.position = Vector2(78, -25) # 卡包筛选在收藏纸页上缘，与原筛选区错开
	picker.size = Vector2(150, 22)
	picker.z_index = 45
	var packs := {}
	for definition: CardData in registry.values():
		if not definition.pack_id.is_empty(): packs[definition.pack_id] = true
	for id: StringName in packs:
		picker.add_item(CardPackRegistry.get_display_name(id))
		picker.set_item_metadata(picker.item_count - 1, id)
	picker.item_selected.connect(func(index: int):
		_pack = picker.get_item_metadata(index)
		table.current_collection_page = 0
		table._build_collection_cards())
	table.get_node("%BookPanel").add_child(picker)


func _build_sticker_pages() -> void:
	var fusion_ids := {}
	for recipe: Dictionary in EmblemFusionRecipes.RECIPES: fusion_ids[recipe.result] = true
	var basic: Array[Dictionary] = []
	var fused: Array[Dictionary] = []
	var runes: Array[Dictionary] = []
	var wounds: Array[Dictionary] = []
	for definition: Dictionary in table.emblem_library.get_definitions():
		if definition.get("status_kind") == "wound":
			wounds.append(definition)
		elif definition.get("target") == "rune":
			if Builder.RUNE_MARKERS.has(String(definition.id)): runes.append(definition)
		elif fusion_ids.has(definition.id):
			fused.append(definition)
		else:
			basic.append(definition)
	_add_sticker_pages("基础纹章", basic)
	_add_sticker_pages("合成纹章", fused)
	# 先排占2×2格的符文贴纸，余下单格继续放伤势，避免多翻一页。
	runes.append_array(wounds)
	_add_sticker_pages("符文贴纸", runes, "伤势")
	table.emblem_library.inventory_changed.connect(_replenish_stickers.call_deferred)
	var position := Vector2(6, 40) # 翻页控件紧凑排在工具箱左页内
	var arrow_size := Vector2(12, 12) # 左右箭头的原生像素尺寸
	_sticker_previous = _label_button(table.emblem_library, "‹", position, arrow_size, func(): _set_sticker_page(_sticker_page - 1))
	_sticker_page_button = _label_button(table.emblem_library, "", position + Vector2(15, 0), Vector2(48, 12), func(): _set_sticker_page(_sticker_page + 1))
	_sticker_next = _label_button(table.emblem_library, "›", position + Vector2(66, 0), arrow_size, func(): _set_sticker_page(_sticker_page + 1))
	for control: Button in [_sticker_previous, _sticker_page_button, _sticker_next]:
		control.add_theme_font_size_override("font_size", 7) # 工具箱展开时原生像素文字随画布放大
		control.z_index = 80
		control.hide()
	set_process(true)


func _add_sticker_pages(title: String, definitions: Array[Dictionary], wound_title: String = "") -> void:
	var inventory := EmblemStickerInventory.new()
	var page: Array[Dictionary] = []
	for definition: Dictionary in definitions:
		var state := _make_sticker_state(definition, String(definition.id))
		if not inventory.add(state):
			_sticker_pages.append({"title": title, "definitions": page})
			inventory = EmblemStickerInventory.new()
			page = []
			inventory.add(state)
			if not wound_title.is_empty() and definition.get("status_kind") == "wound": title = wound_title
		page.append(definition)
	if not page.is_empty(): _sticker_pages.append({"title": title, "definitions": page})


func _process(_delta: float) -> void:
	var expanded: bool = table._inspection_library_expanded or is_instance_valid(table._toolbox_overlay)
	for control: Button in [_sticker_previous, _sticker_page_button, _sticker_next]: control.visible = expanded


func _set_sticker_page(page: int) -> void:
	var pages := _sticker_pages.size()
	_sticker_page = posmod(page, pages)
	_sticker_page_button.text = "%s %d/%d" % [_sticker_pages[_sticker_page].title, _sticker_page + 1, pages]
	_refilling_stickers = true
	table.emblem_library.restore_inventory_state([])
	_refilling_stickers = false
	_replenish_stickers()


func _replenish_stickers() -> void:
	if _refilling_stickers or not is_instance_valid(table): return
	_refilling_stickers = true
	var current: Array = table.emblem_library.get_inventory_state()
	var missing: Array[Dictionary] = []
	for definition: Dictionary in _sticker_pages[_sticker_page].definitions:
		var id := String(definition.id)
		if current.any(func(item: Dictionary) -> bool: return String(item.get("emblem_id", item.get("wound_id", ""))) == id): continue
		_sticker_sequence += 1
		missing.append(_make_sticker_state(definition, "lineup_sticker_%d" % _sticker_sequence))
	if not missing.is_empty(): table.emblem_library.receive_stickers(missing)
	_refilling_stickers = false


func _make_sticker_state(definition: Dictionary, instance_id: String) -> Dictionary:
	var id := String(definition.id)
	var state := {"instance_id": instance_id, "source": "lineup", "temporary": false}
	if definition.get("status_kind") == "wound":
		state["wound_id"] = id
		state["kind"] = "wound"
		state["level"] = int(definition.get("level", 3 if id.ends_with("Ⅲ") else 2 if id.ends_with("Ⅱ") else 1))
	else:
		state["emblem_id"] = id
		state["element_sticker"] = definition.get("target") == "rune"
	return state


func sample_rune(owned: OwnedCard, index: int) -> int:
	# 与正式遭遇按同样的成员顺序初始化。混沌标记显示本次试打会使用的值。
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for row: BattlefieldRow in [table.front_row, table.back_row]:
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			for card: CardData in squad.horizontal_cards:
				var member := squad.get_owned_card(card)
				if member == null: continue
				var sample := OwnedCard.new()
				sample.initialize(member.card_data, &"lineup_rune_preview", 0, rng)
				if member == owned: return int(sample.resolved_runes[index])
	return 0


func capture_visual() -> Dictionary:
	var rows := {&"enemy_front": table._duplicate_row_squads(table.front_row), &"enemy_back": table._duplicate_row_squads(table.back_row)}
	var owned: Array[OwnedCard] = []
	for row: StringName in rows:
		for squad: SquadData in rows[row]:
			for card: CardData in squad.horizontal_cards:
				var member := squad.get_owned_card(card)
				if member != null: owned.append(member)
			owned.append_array(squad.get_equipped_items())
	var spells: Array[OwnedCard] = table._get_prepared_spell_instances()
	owned.append_array(spells)
	var states: Array[Dictionary] = []
	for instance: OwnedCard in owned:
		var state := instance.capture_state()
		# 混沌的试打预览值不属于布置数据，切种子不会产生撤销步骤。
		for sticker: Dictionary in state.rune_stickers:
			if sticker.get("emblem_id") == "混沌贴纸": sticker["element"] = CardData.ElementType.FIRE
		states.append(state)
	var serializer := SAVE.new()
	var board: ResourceBoardState = table.resource_board_state
	var resources: Array[Dictionary] = []
	for id: String in board.deployments.player:
		var instance: OwnedCard = table.owned_card_collection.get_by_instance_id(StringName(id))
		if instance == null: continue
		var placement: Dictionary = board.deployments.player[id]
		resources.append({"card_id": String(instance.card_data.id), "shape": placement.shape.duplicate(true), "anchor": placement.anchor.duplicate()})
	var blocked: Array = board.capture_state().disabled_by_side.player
	return {"encounter": {
		"status_slot_migration_version": SAVE.STATUS_SLOT_MIGRATION_VERSION,
		"collection": serializer._encode_collection_state({"cards": states}),
		"rows": serializer._encode_rows(rows),
		"spell_ids": Array(spells.map(func(spell: OwnedCard) -> String: return String(spell.instance_id))),
	}, "resources": resources, "blocked": blocked}


func update_chaos_preview(formation: Array) -> void:
	for entry: Dictionary in formation:
		var squad: SquadData = entry.squad_data
		for card: CardData in squad.horizontal_cards:
			var resolved := squad.get_owned_card(card)
			if resolved == null: continue
			var owned: OwnedCard = table.owned_card_collection.get_by_instance_id(resolved.instance_id)
			if owned == null: continue
			var changed := false
			for index: int in owned.rune_stickers.size():
				var sticker: Dictionary = owned.rune_stickers[index]
				if sticker.get("emblem_id") != "混沌贴纸" or sticker.element == resolved.resolved_runes[index]: continue
				sticker["element"] = resolved.resolved_runes[index]
				changed = true
			if changed: table._refresh_owned_card_status_visuals(owned)


func resource_resolution(_owned: OwnedCard, cell: Vector2i) -> Dictionary:
	return {"valid": not tutorial and _cell_available(cell), "editor_cell": cell, "has_target": true}


func _cell_available(cell: Vector2i, except_id: StringName = &"") -> bool:
	var board: ResourceBoardState = table.resource_board_state
	if not Layout.is_valid_cell(cell) or cell in board.disabled_by_side.player: return false
	for id: String in board.deployments.player:
		if id == String(except_id): continue
		var placement: Dictionary = board.deployments.player[id]
		var relative := cell - Vector2i(placement.anchor[0], placement.anchor[1])
		if [relative.x, relative.y] in placement.shape: return false
	return true


func begin_resource_drop(owned: OwnedCard, cell: Vector2i) -> bool:
	if tutorial or not _cell_available(cell): return false
	if owned.card_data.id == BLOCK_ID:
		table.resource_board_state.disabled_by_side.player.append(cell)
		table._refresh_resource_preparation_trays()
		return true
	_begin_shape(owned, [cell])
	return true


func _resource_context_click(cell: Vector2i) -> bool:
	var board: ResourceBoardState = table.resource_board_state
	if cell in board.disabled_by_side.player:
		board.disabled_by_side.player.erase(cell)
		table._refresh_resource_preparation_trays()
		return true
	var id: StringName = table.player_resource_tray._piece_by_cell.get(cell, &"")
	var owned: OwnedCard = table.owned_card_collection.get_by_instance_id(id)
	if owned == null: return false
	var placement: Dictionary = board.deployments.player[String(id)]
	var cells: Array[Vector2i] = []
	for piece: Array in placement.shape: cells.append(Vector2i(placement.anchor[0] + piece[0], placement.anchor[1] + piece[1]))
	_begin_shape(owned, cells)
	return true


func _begin_shape(owned: OwnedCard, cells: Array[Vector2i]) -> void:
	cancel_shape()
	_shape_card = owned
	_shape_cells.assign(cells)
	_shape_modal = ColorRect.new()
	_shape_modal.name = "LineupResourceShapeEditor"
	_shape_modal.color = Color(0, 0, 0, SHAPE_MODAL_ALPHA)
	_shape_modal.z_index = 4015
	_shape_modal.gui_input.connect(_shape_input)
	add_child(_shape_modal)
	_shape_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shape_grid = Control.new()
	_shape_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tray: Control = table.player_resource_tray
	_shape_grid.position = _shape_modal.get_global_transform_with_canvas().affine_inverse() * (tray.get_global_transform_with_canvas() * tray.LAYOUT_ORIGIN)
	_shape_grid.size = Vector2(Layout.BOARD_SIZE)
	_shape_modal.add_child(_shape_grid)
	_shape_grid.draw.connect(_draw_shape_grid)
	var strip := PanelContainer.new()
	strip.position = Vector2(793, 110) # 形状提示与按钮位于资源板左侧
	_shape_modal.add_child(strip)
	var controls := VBoxContainer.new()
	strip.add_child(controls)
	_shape_count = Label.new()
	controls.add_child(_shape_count)
	_shape_confirm = _label_button(controls, "确定形状", Vector2.ZERO, Vector2.ZERO, confirm_shape)
	_label_button(controls, "取消", Vector2.ZERO, Vector2.ZERO, cancel_shape)
	_refresh_shape()


func _shape_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	var point: Vector2 = event.position - _shape_grid.position
	for cell: Vector2i in Layout.valid_cells():
		if table.player_resource_tray._contains_hex_point(Layout.center(cell), point):
			select_shape_cell(cell)
			return


func select_shape_cell(cell: Vector2i) -> bool:
	if _shape_card == null or not _cell_available(cell, _shape_card.instance_id): return false
	var candidate := _shape_cells.duplicate()
	if cell in candidate:
		candidate.erase(cell)
	else:
		if candidate.size() >= int(_shape_card.card_data.rarity) + 1: return false
		candidate.append(cell)
	if not candidate.is_empty() and not Layout.is_connected_shape(candidate): return false
	_shape_cells.assign(candidate)
	_refresh_shape()
	return true


func _draw_shape_grid() -> void:
	for cell: Vector2i in Layout.valid_cells():
		if not _cell_available(cell, _shape_card.instance_id): continue
		var center := Layout.center(cell)
		var points := PackedVector2Array([Vector2(-8, -15), Vector2(8, -15), Vector2(16, 0), Vector2(8, 15), Vector2(-8, 15), Vector2(-16, 0)])
		for index: int in points.size(): points[index] += center
		_shape_grid.draw_colored_polygon(points, Color("947643") if cell in _shape_cells else Color("344f58"))
		points.append(points[0])
		_shape_grid.draw_polyline(points, Color("f1ce83") if cell in _shape_cells else Color("85a4a5"), 1.0)


func _refresh_shape() -> void:
	var need := int(_shape_card.card_data.rarity) + 1
	_shape_confirm.disabled = _shape_cells.size() != need
	_shape_count.text = "%s · 选取相连格 %d/%d" % [_shape_card.card_data.display_name, _shape_cells.size(), need]
	_shape_grid.queue_redraw()


func confirm_shape() -> void:
	if _shape_card == null or _shape_cells.size() != int(_shape_card.card_data.rarity) + 1: return
	var shape := Layout.normalize_shape(_shape_cells)
	var sorted: Array[Vector2i] = _shape_cells.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
	var anchor := sorted[0] - shape[0]
	if not table.resource_board_state.try_deploy("player", String(_shape_card.instance_id), shape, anchor, shape[0]): return
	_shape_card.resource_shape.assign(shape)
	cancel_shape()
	table._build_collection_cards()


func cancel_shape() -> void:
	if is_instance_valid(_shape_modal):
		_shape_modal.hide()
		_shape_modal.queue_free()
	_shape_modal = null
	_shape_card = null
	_shape_cells.clear()


func shape_is_open() -> bool:
	return is_instance_valid(_shape_modal)


func _label_button(parent: Control, text: String, position: Vector2, extent: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = position
	button.custom_minimum_size = extent
	button.pressed.connect(action)
	parent.add_child(button)
	return button
