class_name ResourcePreparationTray
extends Control

## 一方资源板的准备界面；OwnedCard 仍是资源形状的唯一来源。

signal drop_requested(data: Dictionary, resolution: Dictionary)
signal click_carry_requested(data: Dictionary, pointer_global_position: Vector2)

const Layout = preload("res://scripts/data/resource_hex_layout.gd")
const BoardState = preload("res://scripts/data/resource_board_state.gd")
const IndicatorStyle = preload("res://scripts/ui/resource_indicator_style.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/ui/CardView.tscn")
const BOARD_TEXTURE: Texture2D = preload("res://assets/card_ui/resources/resource_board_background.png")
const LAYOUT_TEXTURE: Texture2D = preload("res://assets/card_ui/resources/resource_hex_layout.png")
const DISABLED_TEXTURE: Texture2D = preload("res://assets/card_ui/resources/resource_hex_disabled.png")
const TILE_ATLAS: Texture2D = preload("res://assets/card_ui/resources/resource_hex_tile.png")
const BOARD_SIZE := Vector2(182, 184) # 底板原始像素尺寸
const LAYOUT_ORIGIN := Vector2(6, 12) # 固定栏位在底板中的居中偏移
const CELL_SIZE := Vector2(35, 32) # 单格素材原生尺寸
const HOVER_COLOR := Color(1.0, 0.91, 0.42, 1.0) # 悬停整块拼图的描边颜色
const PREVIEW_VALID := Color(0.35, 1.0, 0.55, 0.58) # 合法落点拼图预览颜色
const PREVIEW_INVALID := Color(1.0, 0.25, 0.2, 0.58) # 非法落点拼图预览颜色

var side: String = "player"
var board_state: BoardState
var _owned_by_id: Dictionary = {}
var _piece_by_cell: Dictionary = {}
var _tile_nodes_by_id: Dictionary = {}
var _icon_nodes_by_id: Dictionary = {}
var _disabled_nodes: Array[TextureRect] = []
var _enabled := true
var _accepting_native_drag := false
var _pressed_instance_id: StringName = &""
var _hover_instance_id: StringName = &""
var _hover_card: CardView
var _preview_data: Dictionary = {}
var _preview_resolution: Dictionary = {}
var _preview_visible := false
var _overlay: Control
var _carry_active := false
var _native_drag_active := false
var _pending_click_data: Dictionary = {}
var _pending_press_position := Vector2.ZERO
var _pending_press_cell: Variant = null
var _battle_health_by_id: Dictionary = {}

func _ready() -> void:
	set_process(true)
	_build_board()
	refresh()

func configure(board: BoardState, owner_side: String) -> void:
	board_state = board
	side = owner_side
	if is_inside_tree(): refresh()

func set_owned_cards(cards: Array[OwnedCard]) -> void:
	_owned_by_id.clear()
	for card in cards:
		if card != null:
			_owned_by_id[String(card.instance_id)] = card
	refresh()

func set_battle_health(states: Array) -> void:
	_battle_health_by_id.clear()
	for state_value: Variant in states:
		var state := state_value as RefCounted
		if state == null: continue
		var owned: OwnedCard = state.get("owned_card") as OwnedCard
		if owned != null: _battle_health_by_id[String(owned.instance_id)] = int(state.get("current_health"))
	refresh()

func clear_battle_health() -> void:
	_battle_health_by_id.clear()
	refresh()

func get_instance_center_global(instance_id: StringName) -> Vector2:
	var placement: Dictionary = board_state.deployments.get(side, {}).get(String(instance_id), {})
	if placement.is_empty(): return global_position + BOARD_SIZE * 0.5
	var anchor := Vector2i(int(placement.anchor[0]), int(placement.anchor[1]))
	var shape: Array = placement.get("shape", [])
	var center := Vector2.ZERO
	for pair in shape: center += Layout.center(anchor + Vector2i(int(pair[0]), int(pair[1])))
	if not shape.is_empty(): center /= float(shape.size())
	return get_global_transform_with_canvas() * (LAYOUT_ORIGIN + center)

func set_board_state(board: BoardState) -> void:
	board_state = board
	refresh()

func set_drop_enabled(enabled: bool) -> void:
	_enabled = enabled
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_PASS
	if not enabled:
		clear_preview()
		_clear_hover_card()

func set_carry_active(active: bool) -> void:
	_carry_active = active
	if active: _set_hover_instance(&"")

func begin_carry(instance_id: StringName) -> void:
	for tile: CanvasItem in _tile_nodes_by_id.get(String(instance_id), []): tile.modulate.a = 0.28
	for icon: CanvasItem in _icon_nodes_by_id.get(String(instance_id), []): icon.modulate.a = 0.28

func refresh() -> void:
	if not is_inside_tree() or board_state == null: return
	_hover_instance_id = &""
	_clear_hover_card()
	for child in get_children():
		if child.name in ["ResourceBoardBackground", "ResourceHexLayout", "ResourceBoardTitle", "ResourceBoardOverlay"]: continue
		child.queue_free()
	_piece_by_cell.clear()
	_tile_nodes_by_id.clear()
	_icon_nodes_by_id.clear()
	_disabled_nodes.clear()
	var background := _ensure_background("ResourceBoardBackground", BOARD_TEXTURE, Vector2.ZERO, BOARD_SIZE)
	background.z_index = -2
	var layout := _ensure_background("ResourceHexLayout", LAYOUT_TEXTURE, LAYOUT_ORIGIN, Vector2(170, 160))
	layout.z_index = -1
	for cell in board_state.disabled_by_side.get(side, []):
		var disabled := TextureRect.new()
		disabled.texture = DISABLED_TEXTURE
		disabled.position = LAYOUT_ORIGIN + Layout.center(cell) - Vector2(17, 16)
		disabled.size = CELL_SIZE
		disabled.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		disabled.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disabled.name = "DisabledHex"
		add_child(disabled)
		_disabled_nodes.append(disabled)
	for instance_id in board_state.deployments.get(side, {}):
		var placement: Dictionary = board_state.deployments[side][instance_id]
		if _battle_health_by_id.has(String(instance_id)) and int(_battle_health_by_id[String(instance_id)]) <= 0:
			continue
		var owned := _owned_by_id.get(String(instance_id)) as OwnedCard
		if owned == null or owned.card_data == null or owned.card_data.card_type != CardData.CardType.RESOURCE:
			continue
		var anchor := Vector2i(int(placement.anchor[0]), int(placement.anchor[1]))
		var piece_cells: Array[Vector2i] = []
		for pair in placement.shape: piece_cells.append(Vector2i(int(pair[0]), int(pair[1])))
		var by_id: Array[TextureRect] = []
		for relative_cell in piece_cells:
			var cell := anchor + relative_cell
			_piece_by_cell[cell] = StringName(String(instance_id))
			var tile := _create_tile(owned, cell)
			add_child(tile)
			by_id.append(tile)
		_tile_nodes_by_id[String(instance_id)] = by_id
		_icon_nodes_by_id[String(instance_id)] = _create_piece_icons(owned, anchor, piece_cells)
	_queue_overlay_redraw()

func is_drop_position_global(point: Vector2) -> bool:
	return get_global_rect().has_point(point)

func resolve_drop(pointer_global_position: Vector2, data: Dictionary) -> Dictionary:
	if not _enabled or board_state == null or not is_drop_position_global(pointer_global_position):
		return {"valid": false}
	var owned := data.get("owned_card") as OwnedCard
	if owned == null or owned.card_data == null or owned.card_data.card_type != CardData.CardType.RESOURCE:
		return {"valid": false}
	if board_state.is_level_resource(side, String(owned.instance_id)):
		return {"valid": false}
	if data.get("source_type") not in [&"collection", &"resource_preparation"]:
		return {"valid": false}
	var shape := owned.resource_shape
	if shape.is_empty(): return {"valid": false}
	var local := get_global_transform_with_canvas().affine_inverse() * pointer_global_position
	var grab_cell: Vector2i = data.get("resource_grab_cell", Vector2i.ZERO)
	var grab_pixel_offset: Vector2 = data.get("resource_grab_pixel_offset", Vector2.ZERO)
	if data.get("source_type") == &"collection":
		var mapped := _map_card_grab_to_shape(shape, data.get("grab_local_position", Vector2(49, 68)))
		grab_cell = mapped.cell
		grab_pixel_offset = mapped.pixel_offset
	var snapped_pointer := local - grab_pixel_offset
	var cell := _nearest_axial_cell(snapped_pointer - LAYOUT_ORIGIN)
	var anchor: Vector2i = cell - grab_cell
	var occupied: Dictionary = {}
	for existing_id in board_state.deployments[side]:
		if String(existing_id) == String(owned.instance_id): continue
		var p: Dictionary = board_state.deployments[side][existing_id]
		var origin := Vector2i(int(p.anchor[0]), int(p.anchor[1]))
		for pair in p.shape: occupied[origin + Vector2i(int(pair[0]), int(pair[1]))] = true
	var disabled: Dictionary = {}
	for disabled_cell in board_state.disabled_by_side[side]: disabled[disabled_cell] = true
	var valid := _is_valid_board_cell(cell) and Layout.can_place(shape, anchor, occupied, disabled)
	return {"has_target": true, "valid": valid, "anchor": anchor, "grab_cell": grab_cell, "grab_pixel_offset": grab_pixel_offset, "target_cell": cell, "instance_id": owned.instance_id}

func commit_drop(data: Dictionary, resolution: Dictionary) -> bool:
	if not bool(resolution.get("valid", false)): return false
	var owned := data.get("owned_card") as OwnedCard
	if owned == null: return false
	var grab: Vector2i = resolution.grab_cell
	var success := board_state.try_deploy(side, String(owned.instance_id), owned.resource_shape, resolution.anchor, grab, resolution.grab_pixel_offset)
	if success:
		clear_preview()
		refresh()
	return success

func update_preview(pointer_global_position: Vector2, data: Dictionary) -> Dictionary:
	_preview_data = data
	_preview_resolution = resolve_drop(pointer_global_position, data)
	_preview_visible = is_drop_position_global(pointer_global_position) and not _preview_resolution.is_empty()
	_queue_overlay_redraw()
	return _preview_resolution

func clear_preview() -> void:
	_preview_visible = false
	_preview_data = {}
	_preview_resolution = {}
	_queue_overlay_redraw()

func _queue_overlay_redraw() -> void:
	if is_instance_valid(_overlay): _overlay.queue_redraw()

func _build_board() -> void:
	name = "ResourcePreparationTray"
	size = BOARD_SIZE
	custom_minimum_size = BOARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 150
	mouse_exited.connect(_on_mouse_exited)
	var title := Label.new()
	title.name = "ResourceBoardTitle"
	title.text = "资源"
	title.position = Vector2(12, 1)
	title.size = Vector2(158, 13)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 8)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	_overlay = Control.new()
	_overlay.name = "ResourceBoardOverlay"
	_overlay.position = Vector2.ZERO
	_overlay.size = BOARD_SIZE
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.z_index = 500
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

func _ensure_background(node_name: String, texture: Texture2D, at: Vector2, draw_size: Vector2) -> TextureRect:
	var found := get_node_or_null(node_name) as TextureRect
	if found == null:
		found = TextureRect.new()
		found.name = node_name
		found.texture = texture
		found.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		found.stretch_mode = TextureRect.STRETCH_KEEP
		found.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		found.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(found)
	found.position = at
	found.size = draw_size
	return found

func _create_tile(owned: OwnedCard, cell: Vector2i) -> TextureRect:
	var tile := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = TILE_ATLAS
	atlas.region = Rect2(IndicatorStyle.get_source_x(int(owned.card_data.rarity)), 0, 35, 32)
	tile.texture = atlas
	tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tile.stretch_mode = TextureRect.STRETCH_KEEP
	tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tile.position = LAYOUT_ORIGIN + Layout.center(cell) - Vector2(17, 16)
	tile.size = CELL_SIZE
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.name = "ResourceHex_%s" % owned.instance_id
	return tile

func _create_piece_icons(owned: OwnedCard, anchor: Vector2i, shape: Array[Vector2i]) -> Array[CanvasItem]:
	var icons: Array[CanvasItem] = []
	var texture := IndicatorStyle.get_icon_atlas_texture(owned.card_data.rarity, int(owned.card_data.resource_type))
	var visible_rect := IndicatorStyle.get_icon_visible_rect(owned.card_data.rarity, int(owned.card_data.resource_type))
	for cell in shape:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.size = texture.get_size()
		var center := LAYOUT_ORIGIN + Layout.center(anchor + cell)
		icon.position = center - Vector2(visible_rect.position) - Vector2(visible_rect.size) * 0.5
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.name = "ResourceKindIcon_%s_%d" % [owned.instance_id, icons.size()]
		add_child(icon)
		icons.append(icon)
	return icons


func _nearest_axial_cell(layout_point: Vector2) -> Vector2i:
	var q_estimate := (layout_point.x - float(Layout.HEX_ORIGIN.x)) / float(Layout.COLUMN_STEP)
	var base := Vector2i(roundi(q_estimate), roundi((layout_point.y - Layout.HEX_ORIGIN.y + 16.0 * q_estimate) / float(Layout.ROW_STEP)))
	var best := base
	var best_distance := INF
	for q_offset in range(-2, 3):
		for r_offset in range(-2, 3):
			var candidate := Vector2i(base.x + q_offset, base.y + r_offset)
			var distance := Layout.center(candidate).distance_squared_to(layout_point)
			if distance < best_distance:
				best = candidate
				best_distance = distance
	return best

func _is_valid_board_cell(cell: Vector2i) -> bool:
	return Layout.is_valid_cell(cell)

func _contains_hex_point(center: Vector2, point: Vector2) -> bool:
	var dx := absf(point.x - center.x)
	var dy := absf(point.y - center.y)
	if dx > 17.5 or dy > 16.0:
		return false
	if dx <= 8.5:
		return true
	return dx <= 17.5 - (9.0 * dy / 16.0)

func _hit_test_piece_cell(local: Vector2) -> Variant:
	var layout_point := local - LAYOUT_ORIGIN
	for cell in _piece_by_cell:
		if _contains_hex_point(Layout.center(cell), layout_point):
			return cell
	return null

func _map_card_grab_to_shape(shape: Array[Vector2i], grab_local: Vector2) -> Dictionary:
	var min_q := shape[0].x
	var max_q := shape[0].x
	var min_r := shape[0].y
	var max_r := shape[0].y
	for cell in shape:
		min_q = mini(min_q, cell.x); max_q = maxi(max_q, cell.x)
		min_r = mini(min_r, cell.y); max_r = maxi(max_r, cell.y)
	var abstract_point := Vector2(lerpf(min_q, max_q, clampf(grab_local.x / 99.0, 0.0, 1.0)), lerpf(min_r, max_r, clampf(grab_local.y / 136.0, 0.0, 1.0)))
	var best := shape[0]
	for cell in shape:
		if Vector2(cell).distance_squared_to(abstract_point) < Vector2(best).distance_squared_to(abstract_point): best = cell
	# 卡面尺寸远大于六边形格；只映射到形状中的抓取格，不把卡面内像素偏移带入拼图。
	return {"cell": best, "pixel_offset": Vector2.ZERO}

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _carry_active or _native_drag_active: return
	if event is InputEventMouseMotion:
		_update_hover_at((event as InputEventMouseMotion).position)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var button := event as InputEventMouseButton
		if button.pressed:
			var hit_cell: Variant = _hit_test_piece_cell(button.position)
			if hit_cell != null and _enabled:
				var instance_id: StringName = _piece_by_cell.get(hit_cell, &"")
				var owned := _owned_by_id.get(String(instance_id)) as OwnedCard
				if owned != null and not board_state.is_level_resource(side, String(instance_id)):
					_pending_press_position = button.position
					_pending_press_cell = hit_cell
					_pending_click_data = _build_piece_drag_data(owned, hit_cell, button.position)
					accept_event()
		elif not _pending_click_data.is_empty() and not _native_drag_active:
			var held_distance := _pending_press_position.distance_to(button.position)
			if held_distance < 10.0:
				var pointer_global := get_global_transform_with_canvas() * button.position
				click_carry_requested.emit(_pending_click_data.duplicate(true), pointer_global)
			_pending_click_data.clear()
			_pending_press_cell = null
			accept_event()

func _build_piece_drag_data(owned: OwnedCard, source_cell: Vector2i, pointer_local: Vector2) -> Dictionary:
	var placement: Dictionary = board_state.deployments[side].get(String(owned.instance_id), {})
	var anchor := Vector2i(int(placement.anchor[0]), int(placement.anchor[1]))
	var relative := source_cell - anchor
	var pixel_offset := pointer_local - (LAYOUT_ORIGIN + Layout.center(source_cell))
	return {"kind": &"card", "card_data": owned.card_data, "owned_card": owned, "source_type": &"resource_preparation", "source_slot": self, "source_tray": self, "resource_grab_cell": relative, "resource_grab_pixel_offset": pixel_offset, "grab_local_position": Vector2(49.5, 68.0), "source_placement": placement.duplicate(true)}

func _get_drag_data(at_position: Vector2) -> Variant:
	if not _enabled: return null
	var hit_cell: Variant = _pending_press_cell if _pending_press_cell != null else _hit_test_piece_cell(at_position)
	if hit_cell == null: return null
	var instance_id: StringName = _piece_by_cell.get(hit_cell, &"")
	var owned := _owned_by_id.get(String(instance_id)) as OwnedCard
	if owned == null or board_state.is_level_resource(side, String(instance_id)): return null
	var data := _build_piece_drag_data(owned, hit_cell, _pending_press_position if _pending_press_cell != null else at_position)
	_pending_click_data.clear()
	_pending_press_cell = null
	var preview := CardView.create_drag_visual(data)
	data["drag_visual"] = preview
	set_drag_preview(preview)
	return data

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary: return false
	var global_point := get_global_transform_with_canvas() * at_position
	var resolution := resolve_drop(global_point, data)
	_preview_data = data
	_preview_resolution = resolution
	_set_drag_visual_mode(data, resolution)
	_preview_visible = true
	_queue_overlay_redraw()
	return bool(resolution.get("valid", false))

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary: return
	var global_point := get_global_transform_with_canvas() * at_position
	var resolution := resolve_drop(global_point, data)
	if bool(resolution.get("valid", false)):
		drop_requested.emit(data, resolution)
	clear_preview()

func _set_drag_visual_mode(data: Dictionary, resolution: Dictionary) -> void:
	var visual := data.get("drag_visual") as CardDragPreview
	var owned := data.get("owned_card") as OwnedCard
	if visual != null and owned != null and bool(resolution.get("has_target", true)):
		visual.set_resource_puzzle_mode(
			true,
			owned.resource_shape,
			int(owned.card_data.rarity),
			resolution.get("grab_cell", Vector2i.ZERO),
			resolution.get("grab_pixel_offset", Vector2.ZERO),
			int(owned.card_data.resource_type),
		)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		_accepting_native_drag = data is Dictionary and (data as Dictionary).get("kind") == &"card"
		_native_drag_active = true
		_pending_click_data.clear()
		_pending_press_cell = null
		if _accepting_native_drag and (data as Dictionary).get("source_type") == &"resource_preparation":
			var source_id := StringName(String((data as Dictionary).get("owned_card").instance_id))
			begin_carry(source_id)
		mouse_filter = Control.MOUSE_FILTER_STOP if _accepting_native_drag else Control.MOUSE_FILTER_IGNORE
	elif what == NOTIFICATION_DRAG_END:
		_accepting_native_drag = false
		_native_drag_active = false
		mouse_filter = Control.MOUSE_FILTER_STOP if _enabled else Control.MOUSE_FILTER_PASS
		clear_preview()
		refresh()

func _draw_overlay() -> void:
	if not _hover_instance_id.is_empty():
		var placement: Dictionary = board_state.deployments.get(side, {}).get(String(_hover_instance_id), {})
		if not placement.is_empty():
			var anchor := Vector2i(placement.anchor[0], placement.anchor[1])
			for pair in placement.shape:
				_draw_hex_outline(LAYOUT_ORIGIN + Layout.center(anchor + Vector2i(pair[0], pair[1])), HOVER_COLOR)
	if _preview_visible:
		var owned := _preview_data.get("owned_card") as OwnedCard
		if owned != null and _preview_resolution.has("anchor"):
			var color := PREVIEW_VALID if bool(_preview_resolution.get("valid", false)) else PREVIEW_INVALID
			for cell in owned.resource_shape:
				var point := LAYOUT_ORIGIN + Layout.center(_preview_resolution.get("anchor", Vector2i.ZERO) + cell)
				_overlay.draw_texture_rect_region(TILE_ATLAS, Rect2(point - Vector2(17, 16), CELL_SIZE), Rect2(IndicatorStyle.get_source_x(int(owned.card_data.rarity)), 0, 35, 32), color)
				var icon_region := IndicatorStyle.get_icon_atlas_texture(owned.card_data.rarity, int(owned.card_data.resource_type)).region
				var icon_used := IndicatorStyle.get_icon_visible_rect(owned.card_data.rarity, int(owned.card_data.resource_type))
				var icon_source := Rect2(icon_region.position + Vector2(icon_used.position), Vector2(icon_used.size))
				var icon_dest := Rect2(point - Vector2(icon_used.size) * 0.5, Vector2(icon_used.size))
				_overlay.draw_texture_rect_region(IndicatorStyle.ICON_ATLAS, icon_dest, icon_source, color)

func _draw_hex_outline(center: Vector2, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(-8.5, -16), center + Vector2(8.5, -16),
		center + Vector2(17.5, 0), center + Vector2(8.5, 16),
		center + Vector2(-8.5, 16), center + Vector2(-17.5, 0),
		center + Vector2(-8.5, -16),
	])
	_overlay.draw_polyline(points, color, 2.0, false)

func _update_hover_at(viewport_point: Vector2) -> void:
	if not get_global_rect().has_point(viewport_point):
		_set_hover_instance(&"")
		return
	var local := get_global_transform_with_canvas().affine_inverse() * viewport_point
	var cell: Variant = _hit_test_piece_cell(local)
	var next_id: StringName = _piece_by_cell.get(cell, &"") if cell != null else &""
	_set_hover_instance(next_id)

func _set_hover_instance(instance_id: StringName) -> void:
	if _hover_instance_id == instance_id: return
	_hover_instance_id = instance_id
	_refresh_hover_card()
	_queue_overlay_redraw()

func _clear_hover_instance(instance_id: StringName) -> void:
	if _hover_instance_id == instance_id:
		_set_hover_instance(&"")

func _refresh_hover_card() -> void:
	_clear_hover_card()
	var owned := _owned_by_id.get(String(_hover_instance_id)) as OwnedCard
	if owned == null: return
	_hover_card = CARD_VIEW_SCENE.instantiate() as CardView
	_hover_card.name = "ResourceHoverCard"
	# 敌方托盘靠近画布左缘，详情卡向右展开；我方托盘靠右，继续向左展开。
	_hover_card.position = Vector2(BOARD_SIZE.x + 8.0, 22.0) if side == "enemy" else Vector2(-108.0, 22.0)
	_hover_card.scale = Vector2.ONE
	_hover_card.set_card_data(owned.card_data)
	_hover_card.set_owned_card(owned)
	_hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hover_host := _find_hover_card_host()
	if hover_host != self:
		var viewport_position := get_global_transform_with_canvas() * _hover_card.position
		hover_host.add_child(_hover_card)
		_hover_card.position = viewport_position
		# 复用Main已有的点击携带覆盖层，同时让Esc暂停模态层仍然位于详情卡上方。
		_hover_card.z_index = -200
	else:
		_hover_card.z_index = 400
		add_child(_hover_card)
	_set_mouse_ignore_recursive(_hover_card)

func _find_hover_card_host() -> Control:
	var ancestor: Node = self
	while ancestor != null:
		var hover_layer := ancestor.get_node_or_null("ClickCarryLayer") as Control
		if hover_layer != null:
			return hover_layer
		ancestor = ancestor.get_parent()
	return self

func _set_mouse_ignore_recursive(node: Node) -> void:
	if node is Control: (node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _set_mouse_ignore_recursive(child)

func _clear_hover_card() -> void:
	if is_instance_valid(_hover_card): _hover_card.queue_free()
	_hover_card = null

func _on_mouse_exited() -> void:
	_set_hover_instance(&"")
	clear_preview()
