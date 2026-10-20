class_name CelestialIndicatorController
extends Control

## 指示物共用点按与原生拖动的投放入口；日月星归属小队，哨位归属区域。
const BOARD_TEXTURE: Texture2D = preload("res://assets/ui/board_revision_20261019/indicator_tray.png")
const TRAY_SIZE := Vector2(195, 189) # 指示物板按用户原图195×189像素显示
const TRAY_PADDING := Vector2(20, 42) # 指示物在新卡板内的首格左上角
const TRAY_ITEM_GAP: float = 52.0 # 指示物库存格横向中心间距
const TRAY_ROW_GAP: float = 48.0 # 指示物库存格纵向中心间距
const INDICATOR_START_POSITIONS: Array[Vector2] = [Vector2(47, 81), Vector2(83, 78), Vector2(121, 72)] # 月亮、星星、太阳初始位置对齐原稿，玩家手动摆放仍随实例保存
const DROP_TRAVEL := Vector2(0, 6) # 放置时从手持图像中心向下落到卡面的距离
const INVENTORY_GAP: float = 2.0 # 库存内指示物与哨位之间的最小留白
var main: Node
var items: Array[CelestialIndicator] = []
var next_attachment_order: int = 1
var _tray: Control
var _tray_board: TextureRect
var _tray_views: Dictionary = {}
var _tray_positions: Dictionary = {} # 实例ID→临时卡板内的左上角位置，进入存档
var _last_positions: Dictionary = {}
var _data: Dictionary = {}
var _preview: CelestialDragPreview
var _native: bool = false
var _native_pointer := Vector2.ZERO

func initialize(owner_main: Node) -> void:
	main = owner_main
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = CardDragPreview.DRAG_PREVIEW_Z_INDEX - 1
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tray_board = TextureRect.new()
	_tray_board.name = "CelestialIndicatorTrayBoard"
	_tray_board.texture = BOARD_TEXTURE
	_tray_board.position = Vector2(5, main.COLLECTION_WORLD_TOP) # 与收藏共用世界顶边，整体上移3像素
	_tray_board.size = TRAY_SIZE
	_tray_board.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tray_board.stretch_mode = TextureRect.STRETCH_KEEP
	_tray_board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tray_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tray_board.z_index = -1
	main.world_content.add_child(_tray_board)
	_tray = Control.new()
	_tray.position = _tray_board.position
	_tray.size = TRAY_SIZE
	_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.world_content.add_child(_tray)
	# 当前开发场景提供各一枚用于操作；不作为正式英雄初始库存规则。
	for kind: int in CelestialIndicator.Kind.values():
		var item := CelestialIndicator.new()
		item.kind = kind as CelestialIndicator.Kind
		item.instance_id = StringName("demo_indicator_%d" % kind)
		items.append(item)
		_tray_positions[item.instance_id] = _default_indicator_position(item)
	_sync_tray()

func capture_state() -> Dictionary:
	var encoded: Array[Dictionary] = []
	for item: CelestialIndicator in items:
		encoded.append(item.capture_state())
	var tray_positions: Dictionary = {}
	for item: CelestialIndicator in items:
		var point := _tray_positions.get(item.instance_id, _default_indicator_position(item)) as Vector2
		tray_positions[String(item.instance_id)] = [point.x, point.y]
	return {
		"items": encoded,
		"next_attachment_order": next_attachment_order,
		"tray_positions": tray_positions,
	}

func restore_state(state: Dictionary) -> void:
	cancel_carry()
	items.clear()
	_tray_positions.clear()
	for value: Dictionary in state.get("items", []):
		var item := CelestialIndicator.from_state(value)
		if item != null:
			items.append(item)
	var encoded_positions := state.get("tray_positions", {}) as Dictionary
	for index: int in items.size():
		var item := items[index]
		var point_value: Variant = encoded_positions.get(String(item.instance_id), null)
		if point_value is Array and (point_value as Array).size() == 2:
			var point := Vector2(float(point_value[0]), float(point_value[1]))
			if point.is_finite():
				_tray_positions[item.instance_id] = _clamp_tray_position(item, point)
		if not _tray_positions.has(item.instance_id):
			_tray_positions[item.instance_id] = _default_indicator_position(item)
	next_attachment_order = maxi(1, int(state.get("next_attachment_order", 1)))
	_last_positions.clear()
	_sync_tray()

func _rows() -> Array:
	return [main.front_row, main.back_row]

func _deployed_ids() -> Dictionary:
	var result: Dictionary = {}
	for row: BattlefieldRow in _rows():
		for slot: BoardSlot in row.get_squads():
			for attachment: Dictionary in slot.get_squad_data().indicator_attachments:
				result[(attachment["indicator"] as CelestialIndicator).instance_id] = true
	return result

func _sync_tray() -> void:
	if main == null or _tray == null:
		return
	var deployed := _deployed_ids()
	var retained: Dictionary = {}
	for index: int in items.size():
		var item := items[index]
		if deployed.has(item.instance_id):
			continue
		retained[item.instance_id] = true
		var view := _tray_views.get(item.instance_id) as CelestialIndicatorView
		if not is_instance_valid(view):
			view = CelestialIndicatorView.new()
			view.indicator_data = item
			view.drag_enabled = true
			_tray.add_child(view)
			view.click_carry_requested.connect(begin_click_carry)
			view.position = _tray_positions.get(item.instance_id, _default_indicator_position(item)) as Vector2
			_tray_views[item.instance_id] = view
			if _last_positions.has(item.instance_id):
				view.play_drop_feedback(_last_positions[item.instance_id])
		else:
			view.position = _tray_positions.get(item.instance_id, _default_indicator_position(item)) as Vector2
	for id: Variant in _tray_views.keys():
		if not retained.has(id):
			(_tray_views[id] as Control).queue_free()
			_tray_views.erase(id)
	for id: StringName in _tray_views:
		var view := _tray_views[id] as Control
		var point := find_inventory_position(view.size, view.position, id)
		if point.is_finite():
			_tray_positions[id] = point
			view.position = point

func _process(_delta: float) -> void:
	if main == null:
		return
	var preparing: bool = main.current_phase == main.GamePhase.PREPARE
	_tray.visible = preparing
	if not preparing:
		_tray_board.visible = false
		if not _data.is_empty():
			cancel_carry()
		return
	_tray_board.visible = true
	for row: BattlefieldRow in _rows():
		for slot: BoardSlot in row.get_squads():
			for attachment: Dictionary in slot.get_squad_data().indicator_attachments:
				var id: StringName = (attachment["indicator"] as CelestialIndicator).instance_id
				var view := slot.get_celestial_indicator(id)
				if is_instance_valid(view):
					_last_positions[id] = view._indicator_visual.get_global_transform_with_canvas() * (view.size * 0.5)

func begin_click_carry(data: Dictionary, pointer: Vector2) -> void:
	if main.current_phase != main.GamePhase.PREPARE or not _data.is_empty() or not main._click_carry_data.is_empty():
		return
	_data = data
	_native = false
	_preview = CelestialDragPreview.new()
	_preview.configure(data)
	main.add_child(_preview)
	_preview.global_position = pointer
	_preview.continue_pickup()
	(data["source_view"] as Control).visible = false

func _notification(what: int) -> void:
	if main == null:
		return
	if what == NOTIFICATION_DRAG_BEGIN:
		var value: Variant = get_viewport().gui_get_drag_data()
		if value is Dictionary and value.get("kind") in [&"celestial_indicator", &"sentry_indicator"]:
			_data = value
			_native = true
			_native_pointer = get_viewport().get_mouse_position()
			_preview = _data["preview"] as CelestialDragPreview
			mouse_filter = Control.MOUSE_FILTER_STOP
	elif what == NOTIFICATION_DRAG_END and _native:
		if not _data.is_empty():
			_end_carry(get_viewport().gui_is_drag_successful())
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_native = false

func _input(event: InputEvent) -> void:
	if _data.is_empty():
		return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		var was_native := _native
		cancel_carry()
		if was_native and get_viewport().gui_is_dragging():
			get_viewport().gui_cancel_drag()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if _native:
			_native_pointer = event.position
			return
		_preview.global_position = event.position
	elif _native and event is InputEventMouseButton:
		_native_pointer = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		finish_drop(event.position)
		get_viewport().set_input_as_handled()

func _can_drop_data(_point: Vector2, value: Variant) -> bool:
	if _data.is_empty() or not value is Dictionary or value.get("kind") not in [&"celestial_indicator", &"sentry_indicator"]:
		return false
	# 使用同一Viewport中输入事件记录的指针；GUI预检和提交不能另取一套坐标。
	return not _resolve_drop_target(_get_carry_pointer_position()).is_empty()

func _drop_data(_point: Vector2, _value: Variant) -> void:
	finish_drop()

func _find_target(
	center: Vector2,
	item: CelestialIndicator,
	pointer_global: Vector2
) -> Dictionary:
	var texture := CelestialIndicatorStyle.get_texture(item.kind)
	var display_size := texture.get_size()
	for row: BattlefieldRow in _rows():
		for slot: BoardSlot in row._get_visible_real_slots():
			var squad := slot.get_squad_data()
			if squad.has_indicator(item.kind) and slot != _data.get("source_slot"):
				continue
			var card := slot.get_card_view(squad.get_effect_source())
			if card == null:
				continue
			var card_transform := card.get_global_transform_with_canvas()
			var center_card_position := card_transform.affine_inverse() * center
			if not Rect2(Vector2.ZERO, card.card_size).has_point(center_card_position):
				continue
			var start_center := card_transform.affine_inverse() * center
			var snapped_center := CardView.find_nearest_attachment_center(
				texture,
				display_size,
				start_center,
				DROP_TRAVEL
			)
			if snapped_center.is_finite():
				return {"slot": slot, "position": snapped_center}
	return {}


func _default_indicator_position(item: CelestialIndicator) -> Vector2:
	return INDICATOR_START_POSITIONS[item.kind]


func _default_tray_position(index: int) -> Vector2:
	return Vector2(
		TRAY_PADDING.x + (index % 3) * TRAY_ITEM_GAP,
		TRAY_PADDING.y + floori(float(index) / 3.0) * TRAY_ROW_GAP
	)


func get_inventory_host() -> Control:
	return _tray


func get_inventory_slot_position(index: int, exclude_id: StringName = &"") -> Vector2:
	return find_inventory_position(Vector2(44, 49), _default_tray_position(index), exclude_id)


func find_inventory_position(item_size: Vector2, requested: Vector2, exclude_id: StringName) -> Vector2:
	var obstacles: Array[Rect2] = []
	for id: StringName in _tray_views:
		var view := _tray_views[id] as Control
		if id != exclude_id and is_instance_valid(view) and not view.is_queued_for_deletion():
			obstacles.append(Rect2(_tray_positions.get(id, view.position), view.size).grow(INVENTORY_GAP))
	if main.maze_controller != null and is_instance_valid(main.maze_controller._sentry_bar):
		for child: Node in main.maze_controller._sentry_bar.get_children():
			if child is EquipmentIndicator and StringName(child.sentry_data.get("instance_id", "")) != exclude_id:
				obstacles.append(Rect2(child.position, child.size).grow(INVENTORY_GAP))
	var maximum := TRAY_SIZE - item_size
	var wanted := requested.clamp(Vector2.ZERO, maximum)
	var xs: Array[float] = [wanted.x, 0.0, maximum.x]
	var ys: Array[float] = [wanted.y, 0.0, maximum.y]
	for bounds: Rect2 in obstacles:
		xs.append(clampf(bounds.position.x - item_size.x, 0, maximum.x))
		xs.append(clampf(bounds.end.x, 0, maximum.x))
		ys.append(clampf(bounds.position.y - item_size.y, 0, maximum.y))
		ys.append(clampf(bounds.end.y, 0, maximum.y))
	var best := Vector2.INF
	var distance := INF
	for x: float in xs:
		for y: float in ys:
			var candidate := Rect2(Vector2(x, y), item_size)
			var blocked := false
			for bounds: Rect2 in obstacles:
				if candidate.intersects(bounds):
					blocked = true
					break
			if not blocked and wanted.distance_squared_to(candidate.position) < distance:
				best = candidate.position
				distance = wanted.distance_squared_to(best)
	return best


func _clamp_tray_position(item: CelestialIndicator, point: Vector2) -> Vector2:
	var size := CelestialIndicatorStyle.get_texture(item.kind).get_size()
	return Vector2(
		clampf(point.x, 0.0, TRAY_SIZE.x - size.x),
		clampf(point.y, 0.0, TRAY_SIZE.y - size.y)
	)


func _find_tray_target(center: Vector2, item: CelestialIndicator) -> Dictionary:
	var local_center := _tray.get_global_transform_with_canvas().affine_inverse() * center
	if not Rect2(Vector2.ZERO, TRAY_SIZE).has_point(local_center):
		return {}
	var size := CelestialIndicatorStyle.get_texture(item.kind).get_size()
	var position := find_inventory_position(size, local_center - size * 0.5, item.instance_id)
	if not position.is_finite(): return {}
	var bounds := Rect2(position, size)
	if Rect2(Vector2.ZERO, TRAY_SIZE).encloses(bounds):
		return {"position": position}
	return {}


func _get_carry_center() -> Vector2:
	if is_instance_valid(_preview):
		return _preview.get_visual_center()
	var texture: Texture2D = _data.get("texture") if _data.has("texture") else CelestialIndicatorStyle.get_texture((_data["indicator"] as CelestialIndicator).kind)
	var texture_size := texture.get_size()
	var grab := _data.get("lifted_grab", texture_size * 0.5) as Vector2
	var scale := _data.get("scale", Vector2.ONE) as Vector2
	return _native_pointer + (texture_size * 0.5 - grab) * scale


func _get_carry_pointer_position() -> Vector2:
	return _native_pointer if _native else _preview.global_position

func _resolve_drop_target(pointer: Vector2) -> Dictionary:
	# 两种手势都先解析同一个合法目标，预检期间不改变归属或存档。
	if _data.is_empty() or main.current_phase != main.GamePhase.PREPARE:
		return {}
	if _data.get("kind") == &"sentry_indicator":
		return main.maze_controller.resolve_sentry_drop(String(_data.instance_id), _get_carry_center()) if main.maze_controller != null else {}
	var item := _data["indicator"] as CelestialIndicator
	var center := _get_carry_center()
	var target := _find_target(center, item, pointer)
	return target if not target.is_empty() else _find_tray_target(center, item)

func finish_drop(pointer: Vector2 = Vector2.INF) -> void:
	if _data.is_empty():
		return
	if pointer.is_finite():
		if _native:
			_native_pointer = pointer
		else:
			_preview.global_position = pointer
	else:
		pointer = _get_carry_pointer_position()
	var target := _resolve_drop_target(pointer)
	if target.is_empty():
		_end_carry(false)
		return
	if _data.get("kind") == &"sentry_indicator":
		var id := String(_data.instance_id)
		var committed: bool = main.maze_controller.drop_sentry_at(id, _get_carry_center())
		_end_carry(committed)
		return
	var item := _data["indicator"] as CelestialIndicator
	var center := _get_carry_center()
	var slot := target.get("slot") as BoardSlot
	var old_slot := _data.get("source_slot") as BoardSlot
	var order := next_attachment_order
	if is_instance_valid(old_slot):
		for attachment: Dictionary in old_slot.get_squad_data().indicator_attachments:
			if (attachment["indicator"] as CelestialIndicator).instance_id == item.instance_id and target.get("slot") == old_slot:
				order = int(attachment["order"])
		old_slot.get_squad_data().detach_indicator(item.instance_id)
		old_slot.set_squad_data(old_slot.get_squad_data())
	_last_positions[item.instance_id] = center
	if is_instance_valid(slot):
		slot.get_squad_data().attach_indicator(item, target["position"], order)
		next_attachment_order += 1
		slot.set_squad_data(slot.get_squad_data())
		slot.get_celestial_indicator(item.instance_id).play_drop_feedback(center)
	else:
		_tray_positions[item.instance_id] = target["position"]
	_end_carry(true)
	_sync_tray()
	if not is_instance_valid(slot) and _tray_views.has(item.instance_id):
		var tray_view := _tray_views[item.instance_id] as CelestialIndicatorView
		tray_view.position = _tray_positions.get(item.instance_id, tray_view.position) as Vector2
		tray_view.play_drop_feedback(center)
	main._on_battlefield_squads_changed()

func _end_carry(committed: bool) -> void:
	var center := _get_carry_center() if not _data.is_empty() else Vector2.INF
	var view := _data.get("source_view") as Control
	if is_instance_valid(view) and not view.is_queued_for_deletion():
		view.visible = true
		if not committed and center.is_finite():
			view.play_return_feedback.call_deferred(center)
	if not _native and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	_data = {}
	_native = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func cancel_carry() -> void:
	_end_carry(false)

func animate_star_transfer(item: CelestialIndicator, source: BattleSquadState, target: BattleSquadState) -> void:
	var source_slot := main._battle_state_slots.get(source) as BoardSlot
	var target_slot := main._battle_state_slots.get(target) as BoardSlot
	if not is_instance_valid(target_slot):
		return
	var center := target_slot.get_global_transform_with_canvas() * Vector2(49.5, 60)
	if is_instance_valid(source_slot):
		var view := source_slot.get_celestial_indicator(item.instance_id)
		if is_instance_valid(view):
			center = view._indicator_visual.get_global_transform_with_canvas() * (view.size * 0.5)
		source_slot.refresh_celestial_indicators(source.squad_data)
	target_slot.refresh_celestial_indicators(target.squad_data)
	var target_view := target_slot.get_celestial_indicator(item.instance_id)
	if target_view != null:
		target_view.drag_enabled = false
		target_view.play_drop_feedback(center)
