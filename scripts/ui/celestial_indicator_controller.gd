class_name CelestialIndicatorController
extends Control

## 日月星的库存与准备操作入口；场上归属保存在 SquadData，战斗只使用阵容副本。
const TRAY_POSITION := Vector2(878, 374) # 临时卡板位于我方人物图标下方，并向下留出操作间距
const TRAY_SIZE := Vector2(180, 92) # 临时卡板的占位范围，正式素材和边界待确认
const TRAY_PADDING := Vector2(12, 25) # 指示物在临时卡板内的默认内边距
const TRAY_ITEM_GAP: float = 51.0 # 仅用于首次摆放各枚库存指示物的水平间距
const DROP_TRAVEL := Vector2(0, 6) # 放置时从手持图像中心向下落到卡面的距离
var main: Node
var items: Array[CelestialIndicator] = []
var next_attachment_order: int = 1
var _tray: Control
var _tray_board: Panel
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
	_tray_board = Panel.new()
	_tray_board.name = "CelestialIndicatorTrayBoard"
	_tray_board.position = TRAY_POSITION
	_tray_board.size = TRAY_SIZE
	_tray_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tray_board.z_index = -1
	var board_style := StyleBoxFlat.new()
	board_style.bg_color = Color(0.12, 0.16, 0.18, 0.82)
	board_style.border_color = Color(0.75, 0.63, 0.35, 0.9)
	board_style.set_border_width_all(2)
	board_style.corner_radius_top_left = 4
	board_style.corner_radius_top_right = 4
	board_style.corner_radius_bottom_left = 4
	board_style.corner_radius_bottom_right = 4
	_tray_board.add_theme_stylebox_override("panel", board_style)
	main.player_avatar_button.get_parent().add_child(_tray_board)
	_tray = Control.new()
	_tray.position = TRAY_POSITION
	_tray.size = TRAY_SIZE
	_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.player_avatar_button.get_parent().add_child(_tray)
	# 当前开发场景提供各一枚用于操作；不作为正式英雄初始库存规则。
	for kind: int in CelestialIndicator.Kind.values():
		var item := CelestialIndicator.new()
		item.kind = kind as CelestialIndicator.Kind
		item.instance_id = StringName("demo_indicator_%d" % kind)
		items.append(item)
		_tray_positions[item.instance_id] = _default_tray_position(items.size() - 1)
	_sync_tray()

func capture_state() -> Dictionary:
	var encoded: Array[Dictionary] = []
	for item: CelestialIndicator in items:
		encoded.append(item.capture_state())
	var tray_positions: Dictionary = {}
	for item: CelestialIndicator in items:
		var point := _tray_positions.get(item.instance_id, _default_tray_position(0)) as Vector2
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
			_tray_positions[item.instance_id] = _default_tray_position(index)
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
			view.position = _tray_positions.get(item.instance_id, _default_tray_position(index)) as Vector2
			_tray_views[item.instance_id] = view
			if _last_positions.has(item.instance_id):
				view.play_drop_feedback(_last_positions[item.instance_id])
		else:
			view.position = _tray_positions.get(item.instance_id, _default_tray_position(index)) as Vector2
	for id: Variant in _tray_views.keys():
		if not retained.has(id):
			(_tray_views[id] as Control).queue_free()
			_tray_views.erase(id)

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
	_sync_tray()
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
		if value is Dictionary and value.get("kind") == &"celestial_indicator":
			_data = value
			_native = true
			_native_pointer = get_viewport().get_mouse_position()
			_preview = _data["preview"] as CelestialDragPreview
			mouse_filter = Control.MOUSE_FILTER_STOP
	elif what == NOTIFICATION_DRAG_END and _native:
		if not _data.is_empty():
			finish_drop()
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_native = false

func _input(event: InputEvent) -> void:
	if _data.is_empty():
		return
	if event is InputEventMouseMotion:
		if _native:
			_native_pointer = event.position
			return
		_preview.global_position = event.position
	elif _native and event is InputEventMouseButton:
		_native_pointer = event.position
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			finish_drop()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_carry()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_carry()
		get_viewport().set_input_as_handled()

func _can_drop_data(_point: Vector2, value: Variant) -> bool:
	return value is Dictionary and value.get("kind") == &"celestial_indicator"

func _drop_data(_point: Vector2, _value: Variant) -> void:
	finish_drop()

func _find_target(center: Vector2, item: CelestialIndicator) -> Dictionary:
	var half := CelestialIndicatorStyle.get_texture(item.kind).get_size() * 0.5
	for row: BattlefieldRow in _rows():
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			if squad.has_indicator(item.kind) and slot != _data.get("source_slot"):
				continue
			var card := slot.get_card_view(squad.get_effect_source())
			var point := card.get_global_transform_with_canvas().affine_inverse() * center
			var bounds := Rect2(card.art_area_position + half, card.art_area_size - half * 2.0)
			if bounds.has_point(point) and bounds.has_point(point + DROP_TRAVEL):
				return {"slot": slot, "position": point + DROP_TRAVEL}
	return {}


func _default_tray_position(index: int) -> Vector2:
	return Vector2(TRAY_PADDING.x + index * TRAY_ITEM_GAP, TRAY_PADDING.y)


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
	var position := _clamp_tray_position(item, local_center - size * 0.5)
	var bounds := Rect2(position, size)
	if Rect2(Vector2.ZERO, TRAY_SIZE).encloses(bounds):
		return {"position": position}
	return {}


func _get_carry_center() -> Vector2:
	if not _native and is_instance_valid(_preview):
		return _preview.get_visual_center()
	var texture_size := CelestialIndicatorStyle.get_texture((_data["indicator"] as CelestialIndicator).kind).get_size()
	var grab := _data.get("grab", texture_size * 0.5) as Vector2
	var scale := _data.get("scale", Vector2.ONE) as Vector2
	return _native_pointer + (texture_size * 0.5 - grab) * scale

func finish_drop() -> void:
	if _data.is_empty():
		return
	var item := _data["indicator"] as CelestialIndicator
	var center := _get_carry_center() if not _data.is_empty() else get_viewport().get_mouse_position()
	var target := _find_target(center, item) if main.current_phase == main.GamePhase.PREPARE else {}
	var tray_target := _find_tray_target(center, item) if main.current_phase == main.GamePhase.PREPARE else {}
	var old_slot := _data.get("source_slot") as BoardSlot
	var order := next_attachment_order
	if is_instance_valid(old_slot):
		for attachment: Dictionary in old_slot.get_squad_data().indicator_attachments:
			if (attachment["indicator"] as CelestialIndicator).instance_id == item.instance_id and target.get("slot") == old_slot:
				order = int(attachment["order"])
		old_slot.get_squad_data().detach_indicator(item.instance_id)
		old_slot.set_squad_data(old_slot.get_squad_data())
	_last_positions[item.instance_id] = center
	if not target.is_empty():
		var slot := target["slot"] as BoardSlot
		slot.get_squad_data().attach_indicator(item, target["position"], order)
		next_attachment_order += 1
		slot.set_squad_data(slot.get_squad_data())
		slot.get_celestial_indicator(item.instance_id).play_drop_feedback(center)
	elif not tray_target.is_empty():
		_tray_positions[item.instance_id] = tray_target["position"]
	var source_view := _data.get("source_view") as Control
	if is_instance_valid(source_view) and not source_view.is_queued_for_deletion():
		source_view.visible = true
	if not _native and is_instance_valid(_preview):
		_preview.queue_free()
	_data = {}
	_preview = null
	_sync_tray()
	if target.is_empty() and _tray_views.has(item.instance_id):
		var tray_view := _tray_views[item.instance_id] as CelestialIndicatorView
		tray_view.position = _tray_positions.get(item.instance_id, tray_view.position) as Vector2
		tray_view.play_drop_feedback(center)
	main._on_battlefield_squads_changed()

func cancel_carry() -> void:
	var view := _data.get("source_view") as Control
	if is_instance_valid(view) and not view.is_queued_for_deletion():
		view.visible = true
	if not _native and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	_data = {}
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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
