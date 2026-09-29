extends Control

## 准备栏只显示 OwnedCard 实例的图标；实例仍由收藏统一持有。

signal drop_requested(data: Dictionary, insertion_index: int)
signal click_carry_requested(data: Dictionary, pointer_global_position: Vector2)
signal inspection_requested(card_view: CardView, card_data: CardData, owned_card: OwnedCard)

const SPELL_ICON_SCRIPT: Script = preload("res://scripts/ui/spell_preparation_icon.gd")
const SPELL_ICON_STYLE = preload("res://scripts/ui/spell_preparation_icon_style.gd")
const CARD_VIEW_SCRIPT: Script = preload("res://scripts/ui/card_view.gd")
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/ui/CardView.tscn")
const COLUMN_NAMES: Array[String] = ["即时", "条件", "准备"]
const BOARD_TEXTURE: Texture2D = preload("res://assets/card_ui/spells/source/preparation_board.png")
const TRAY_SIZE := Vector2(193.0, 310.0) # 法术板按用户原图193×310像素显示
const BOARD_BACKGROUND_Z_INDEX: int = -225 # 根节点层级150时有效层级为-75，夹在锦缎-80与木板-70之间
const COLUMN_WIDTH: float = 52.0 # 三类法术各自的滚动列宽
const COLUMN_STEP: float = 58.0 # 三列图标之间的水平间距
const ICON_STEP: float = 21.0 # 同类图标步长为图标高度的一半
const ICON_POSITION := Vector2(5.0, 0.0) # 图标在各滚动列内的左侧留白
const PANEL_INSET: float = 8.0 # 图标栏相对外框的内边距
const TITLE_HEIGHT: float = 18.0 # 法术准备标题行高度
const COLUMN_HEADER_HEIGHT: float = 12.0 # 即时、条件、准备列标题高度
const LIST_TOP: float = 37.0 # 三列图标滚动区在面板中的顶部位置
const LIST_HEIGHT: float = 263.0 # 三列图标的可见高度
const INSERTION_MARKER_COLOR := Color("f7d882") # 拖动排序时插入线颜色
const INSERTION_GHOST_ALPHA: float = 0.42 # 目标位置法术图标虚影的透明度
const DROP_TRANSITION_DURATION: float = 0.16 # 卡牌落入准备栏并转为图标的动画时长
const SORT_TRANSITION_DURATION: float = 0.12 # 同列排序时图标滑向新位置的动画时长
const HOVER_REVEAL_OFFSET: float = SPELL_ICON_SCRIPT.ICON_SIZE.y - ICON_STEP # 下方图标只补足悬停图标与半图标步长的差值

var _prepared_cards: Array[OwnedCard] = []
var _icons_by_instance_id: Dictionary = {}
var _columns: Array[Control] = []
var _scrolls: Array[ScrollContainer] = []
var _lists: Array[Control] = []
var _drop_enabled: bool = true
var _capacity: int = 10
var _accepting_current_drag: bool = false
var _drop_transitions: Dictionary = {}
var _insertion_marker: Control
var _insertion_ghost: TextureRect
var _drop_index_resolver: Callable
var _preview_instance_id: StringName = &""
var _preview_index: int = -1
var _preview_order: Array[OwnedCard] = []
var _target_positions: Dictionary = {}
var _hovered_instance_id: StringName = &""
var _carried_instance_id: StringName = &""
var _hover_card_popup: CardView


func _ready() -> void:
	_build_columns()
	_refresh_cards()


func set_prepared_cards(cards: Array[OwnedCard]) -> void:
	_prepared_cards.assign(cards)
	if is_inside_tree():
		_refresh_cards()


func set_capacity(capacity: int) -> void:
	_capacity = maxi(capacity, 0)


func set_drop_index_resolver(resolver: Callable) -> void:
	_drop_index_resolver = resolver


func set_drop_enabled(enabled: bool) -> void:
	_drop_enabled = enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not enabled:
		_carried_instance_id = &""
		_clear_insertion_preview()
		clear_hover_card()
	for icon: Control in _icons_by_instance_id.values():
		icon.call("set_drag_enabled", enabled)


func _build_columns() -> void:
	size = TRAY_SIZE
	custom_minimum_size = TRAY_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := TextureRect.new()
	background.texture = BOARD_TEXTURE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.z_index = BOARD_BACKGROUND_Z_INDEX
	add_child(background)
	var title := Label.new()
	title.text = "法术准备"
	title.position = Vector2(PANEL_INSET, 1.0)
	title.size = Vector2(TRAY_SIZE.x - PANEL_INSET * 2.0, TITLE_HEIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 9)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	for column_index: int in COLUMN_NAMES.size():
		var column := Control.new()
		column.position = Vector2(PANEL_INSET + column_index * COLUMN_STEP, 0.0)
		column.size = Vector2(COLUMN_WIDTH, TRAY_SIZE.y)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(column)
		var header := Label.new()
		header.text = COLUMN_NAMES[column_index]
		header.position = Vector2(0.0, TITLE_HEIGHT + 2.0)
		header.size = Vector2(COLUMN_WIDTH, COLUMN_HEADER_HEIGHT)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_theme_font_size_override("font_size", 8)
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(header)
		var scroll := ScrollContainer.new()
		scroll.position = Vector2(0.0, LIST_TOP)
		scroll.size = Vector2(COLUMN_WIDTH, LIST_HEIGHT)
		scroll.custom_minimum_size = scroll.size
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.mouse_filter = Control.MOUSE_FILTER_PASS
		column.add_child(scroll)
		var icon_list := Control.new()
		icon_list.custom_minimum_size = Vector2(COLUMN_WIDTH, LIST_HEIGHT)
		icon_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scroll.add_child(icon_list)
		_columns.append(column)
		_scrolls.append(scroll)
		_lists.append(icon_list)
	_insertion_marker = Control.new()
	_insertion_marker.name = "SpellInsertionMarker"
	_insertion_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_insertion_marker.visible = false
	_insertion_marker.z_index = 10
	_insertion_marker.draw.connect(_draw_insertion_marker)
	add_child(_insertion_marker)
	_insertion_ghost = TextureRect.new()
	_insertion_ghost.name = "SpellInsertionGhost"
	_insertion_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_insertion_ghost.stretch_mode = TextureRect.STRETCH_SCALE
	_insertion_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_insertion_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_insertion_ghost.size = SPELL_ICON_SCRIPT.ICON_SIZE
	_insertion_ghost.modulate.a = INSERTION_GHOST_ALPHA
	_insertion_ghost.visible = false
	_insertion_ghost.z_index = 9
	add_child(_insertion_ghost)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not _drop_enabled or not data is Dictionary:
		_clear_insertion_preview()
		return false
	var drag_data := data as Dictionary
	var owned := drag_data.get("owned_card") as OwnedCard
	var valid: bool = (
		owned != null
		and owned.card_data != null
		and owned.card_data.card_type == CardData.CardType.SPELL
		and owned.card_data.get_spell_preparation_column() >= 0
		and owned.spell_durability > 0
		and drag_data.get("source_type") in [&"collection", &"spell_preparation"]
		and _is_inside_drop_area(at_position)
	)
	if not valid:
		_clear_insertion_preview()
		return false
	var already_prepared := false
	for card: OwnedCard in _prepared_cards:
		if card.instance_id == owned.instance_id:
			already_prepared = true
			break
	if not already_prepared and _prepared_cards.size() >= _capacity:
		_clear_insertion_preview()
		return false
	var index := _insertion_index(at_position, owned)
	if _drop_index_resolver.is_valid():
		index = int(_drop_index_resolver.call(owned, index))
	if index < 0:
		_clear_insertion_preview()
		return false
	_update_insertion_preview(owned, index)
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary:
			var owned := (data as Dictionary).get("owned_card") as OwnedCard
			if owned != null:
				begin_card_carry(owned.instance_id)
		_accepting_current_drag = _drop_enabled and _is_spell_drag_data(data)
		mouse_filter = Control.MOUSE_FILTER_STOP if _accepting_current_drag else Control.MOUSE_FILTER_IGNORE
	elif what == NOTIFICATION_DRAG_END:
		_accepting_current_drag = false
		mouse_filter = Control.MOUSE_FILTER_STOP if _drop_enabled else Control.MOUSE_FILTER_IGNORE
		_clear_insertion_preview()
		end_card_carry()


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		_clear_insertion_preview()
		return
	var drag_data := data as Dictionary
	drop_requested.emit(
		drag_data,
		_preview_index
	)
	_clear_insertion_preview()


func insertion_index_for_global_position(global_point: Vector2, data: Dictionary = {}) -> int:
	return _insertion_index(
		get_global_transform_with_canvas().affine_inverse() * global_point,
		data.get("owned_card") as OwnedCard
	)


func is_drop_position_global(global_point: Vector2) -> bool:
	var local_point := get_global_transform_with_canvas().affine_inverse() * global_point
	return _is_inside_drop_area(local_point)


func animate_drop_transition(data: Dictionary, instance_id: StringName) -> bool:
	var icon := _icons_by_instance_id.get(instance_id) as Control
	var drag_preview := data.get("drag_visual") as CardDragPreview
	if icon == null or not is_instance_valid(drag_preview):
		return false
	var source_visual := drag_preview.get_card_visual() as TextureRect
	if source_visual == null:
		return false
	_stop_drop_transition(instance_id)
	var transition_layer := get_parent() as Control
	if transition_layer == null:
		return false
	var transition: CardDragPreview = CARD_VIEW_SCRIPT.create_drag_visual(data)
	transition.name = "SpellDropTransition"
	transition_layer.add_child(transition)
	var layer_transform := transition_layer.get_global_transform_with_canvas()
	var source_transform := source_visual.get_global_transform_with_canvas()
	var source_root_transform := drag_preview.get_global_transform_with_canvas()
	_apply_visual_transform(transition, layer_transform.affine_inverse() * source_root_transform)
	var transition_visual := transition.get_card_visual() as TextureRect
	if transition_visual == null:
		transition.queue_free()
		return false
	_apply_visual_transform(
		transition_visual,
		source_root_transform.affine_inverse() * source_transform
	)
	transition.prepare_spell_preparation_transition()
	var target_rect := icon.get_global_rect()
	var target_top_left := layer_transform.affine_inverse() * target_rect.position
	var target_bottom_right := layer_transform.affine_inverse() * target_rect.end
	var end_scale := Vector2(
		(target_bottom_right.x - target_top_left.x) / maxf(1.0, transition_visual.size.x * transition_visual.scale.x),
		(target_bottom_right.y - target_top_left.y) / maxf(1.0, transition_visual.size.y * transition_visual.scale.y)
	)
	var end_position := target_top_left - transition_visual.position * end_scale
	icon.modulate.a = 0.0
	drag_preview.visible = false
	transition.z_index = 1000
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(transition, "position", end_position, DROP_TRANSITION_DURATION)
	tween.tween_property(transition, "scale", end_scale, DROP_TRANSITION_DURATION)
	tween.tween_property(transition, "rotation", 0.0, DROP_TRANSITION_DURATION)
	tween.tween_property(transition_visual, "rotation_degrees", 0.0, DROP_TRANSITION_DURATION)
	tween.tween_property(transition_visual, "modulate:a", 0.0, DROP_TRANSITION_DURATION)
	tween.tween_property(icon, "modulate:a", 1.0, DROP_TRANSITION_DURATION)
	tween.finished.connect(func() -> void:
		if is_instance_valid(transition):
			transition.queue_free()
		if _icons_by_instance_id.get(instance_id) == icon and is_instance_valid(icon):
			icon.modulate.a = 1.0
		_drop_transitions.erase(instance_id)
		_drop_transitions.erase(StringName("visual_%s" % instance_id))
	)
	_drop_transitions[instance_id] = tween
	_drop_transitions[StringName("visual_%s" % instance_id)] = transition
	return true


func _apply_visual_transform(control: Control, value: Transform2D) -> void:
	control.position = value.origin
	control.rotation = value.get_rotation()
	control.scale = value.get_scale()


func _stop_drop_transition(instance_id: StringName) -> void:
	var previous_transition := _drop_transitions.get(instance_id) as Tween
	if is_instance_valid(previous_transition) and previous_transition.is_running():
		previous_transition.kill()
	var existing_visual: Variant = _drop_transitions.get(StringName("visual_%s" % instance_id))
	if is_instance_valid(existing_visual):
		existing_visual.queue_free()
	_drop_transitions.erase(instance_id)
	_drop_transitions.erase(StringName("visual_%s" % instance_id))
	var icon := _icons_by_instance_id.get(instance_id) as Control
	if is_instance_valid(icon):
		icon.modulate.a = 1.0


func _insertion_index(at_position: Vector2, owned: OwnedCard) -> int:
	var column_index := owned.card_data.get_spell_preparation_column() if owned != null else _column_at_position(at_position)
	if column_index < 0 or column_index >= _lists.size():
		return _prepared_cards.size()
	var list := _lists[column_index]
	var list_local := list.get_global_transform_with_canvas().affine_inverse() * (get_global_transform_with_canvas() * at_position)
	var row_position_y := list_local.y
	var same_column_count := 0
	var before_count := 0
	for card: OwnedCard in _prepared_cards:
		var card_column := card.card_data.get_spell_preparation_column()
		if card_column < column_index:
			before_count += 1
		elif card_column == column_index:
			same_column_count += 1
	var target_row := clampi(floori((row_position_y + ICON_STEP * 0.5) / ICON_STEP), 0, same_column_count)
	var insertion_index := before_count + target_row
	var previous_index := _prepared_cards.find(owned) if owned != null else -1
	if previous_index >= 0 and previous_index < insertion_index:
		insertion_index -= 1
	var candidate_count := _prepared_cards.size() - (1 if previous_index >= 0 else 0)
	return clampi(insertion_index, 0, candidate_count)


func _column_at_position(at_position: Vector2) -> int:
	if not _is_inside_drop_area(at_position):
		return -1
	return clampi(floori((at_position.x - PANEL_INSET) / COLUMN_STEP), 0, _columns.size() - 1)


func _is_inside_drop_area(at_position: Vector2) -> bool:
	return (
		at_position.x >= PANEL_INSET
		and at_position.x <= size.x - PANEL_INSET
		and at_position.y >= LIST_TOP
		and at_position.y <= size.y
	)


func _is_spell_drag_data(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var owned := (data as Dictionary).get("owned_card") as OwnedCard
	return (
		owned != null
		and owned.card_data != null
		and owned.card_data.card_type == CardData.CardType.SPELL
		and owned.card_data.get_spell_preparation_column() >= 0
		and owned.spell_durability > 0
		and (data as Dictionary).get("source_type") in [&"collection", &"spell_preparation"]
	)


func _refresh_cards() -> void:
	var visible_ids: Dictionary = {}
	var cards_by_column: Array[Array] = [[], [], []]
	for owned: OwnedCard in _prepared_cards:
		if owned == null or owned.card_data == null:
			continue
		var column_index := owned.card_data.get_spell_preparation_column()
		if column_index < 0 or column_index >= cards_by_column.size():
			continue
		cards_by_column[column_index].append(owned)
		visible_ids[owned.instance_id] = true
	for instance_id: StringName in _icons_by_instance_id.keys():
		if not visible_ids.has(instance_id):
			_stop_drop_transition(instance_id)
			var old_icon := _icons_by_instance_id[instance_id] as Control
			if is_instance_valid(old_icon):
				if old_icon.has_meta("sort_tween"):
					var old_sort_tween := old_icon.get_meta("sort_tween") as Tween
					if is_instance_valid(old_sort_tween) and old_sort_tween.is_running():
						old_sort_tween.kill()
				old_icon.queue_free()
			_icons_by_instance_id.erase(instance_id)
	_target_positions.clear()
	for column_index: int in cards_by_column.size():
		var icon_list := _lists[column_index]
		var cards: Array = cards_by_column[column_index]
		var content_height := maxf(LIST_HEIGHT, (cards.size() - 1) * ICON_STEP + SPELL_ICON_SCRIPT.ICON_SIZE.y)
		if column_index == _hovered_column_index() and _hovered_row_index(column_index) < cards.size() - 1:
			content_height += HOVER_REVEAL_OFFSET
		icon_list.custom_minimum_size = Vector2(COLUMN_WIDTH, content_height)
		icon_list.size = icon_list.custom_minimum_size
		for card_index: int in cards.size():
			var owned := cards[card_index] as OwnedCard
			var icon := _icons_by_instance_id.get(owned.instance_id) as Control
			if icon == null or not is_instance_valid(icon):
				icon = SPELL_ICON_SCRIPT.new() as Control
				icon.call("configure", owned, self)
				icon.connect("click_carry_requested", _on_icon_click_carry_requested)
				icon.connect("inspection_requested", _on_icon_inspection_requested)
				icon_list.add_child(icon)
				_icons_by_instance_id[owned.instance_id] = icon
			else:
				icon.call("configure", owned, self)
			var hover_offset := (
				HOVER_REVEAL_OFFSET
				if column_index == _hovered_column_index() and card_index > _hovered_row_index(column_index)
				else 0.0
			)
			var target_position := Vector2(ICON_POSITION.x, card_index * ICON_STEP + hover_offset)
			_target_positions[owned.instance_id] = target_position
			if icon.get_parent() != icon_list:
				var old_global := icon.get_global_transform_with_canvas() * Vector2.ZERO
				icon.reparent(icon_list)
				icon.position = icon_list.get_global_transform_with_canvas().affine_inverse() * old_global
			icon.call("set_drag_enabled", _drop_enabled)
			icon.z_index = card_index
			icon_list.move_child(icon, card_index)
			_animate_icon_to_position(icon, target_position)
		_update_scroll_position(column_index)
	if not _hovered_instance_id.is_empty() and not visible_ids.has(_hovered_instance_id):
		clear_hover_card()
	elif not _preview_instance_id.is_empty():
		_update_insertion_preview_layout()


func _process(_delta: float) -> void:
	if _drop_enabled and _carried_instance_id.is_empty() and _preview_instance_id.is_empty():
		_update_hover_from_pointer()


func _set_hovered_instance(instance_id: StringName) -> void:
	if not _drop_enabled or instance_id == _hovered_instance_id or not _carried_instance_id.is_empty():
		return
	var icon := _icons_by_instance_id.get(instance_id) as Control
	var owned := icon.get("owned_card") as OwnedCard if is_instance_valid(icon) else null
	if owned == null or owned.card_data == null:
		return
	_hovered_instance_id = instance_id
	if not is_instance_valid(_hover_card_popup):
		_hover_card_popup = CARD_VIEW_SCENE.instantiate() as CardView
		_hover_card_popup.name = "SpellPreparationHoverCard"
		_hover_card_popup.configure_drag_source(false)
		_hover_card_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hover_card_popup.z_index = 1000
		add_child(_hover_card_popup)
	_hover_card_popup.set_card_data(owned.card_data)
	_hover_card_popup.set_owned_card(owned)
	_hover_card_popup.visible = true
	call_deferred("_set_mouse_filter_recursive", _hover_card_popup)
	_position_hover_card_popup()
	_refresh_cards()


func clear_hover_card() -> void:
	if _hovered_instance_id.is_empty() and not is_instance_valid(_hover_card_popup):
		return
	_hovered_instance_id = &""
	if is_instance_valid(_hover_card_popup):
		_hover_card_popup.visible = false
	_refresh_cards()


func begin_card_carry(instance_id: StringName) -> void:
	_carried_instance_id = instance_id
	clear_hover_card()
	var icon := _icons_by_instance_id.get(instance_id) as Control
	if is_instance_valid(icon):
		var tween := icon.get_meta("sort_tween") as Tween if icon.has_meta("sort_tween") else null
		if is_instance_valid(tween) and tween.is_running():
			tween.kill()
		icon.position = _target_positions.get(instance_id, icon.position) as Vector2


func end_card_carry() -> void:
	_carried_instance_id = &""
	clear_hover_card()


func _position_hover_card_popup() -> void:
	if not is_instance_valid(_hover_card_popup):
		return
	var icon := _icons_by_instance_id.get(_hovered_instance_id) as Control
	if not is_instance_valid(icon):
		return
	var tray_transform := get_global_transform_with_canvas()
	var icon_global := icon.get_global_rect()
	var icon_local_top_left := tray_transform.affine_inverse() * icon_global.position
	_hover_card_popup.position = icon_local_top_left + Vector2(icon.size.x + 5.0, 0.0)
	_hover_card_popup.size = Vector2(99.0, 136.0)


func _set_mouse_filter_recursive(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in control.get_children():
		if child is Control:
			_set_mouse_filter_recursive(child as Control)


func _hovered_column_index() -> int:
	var icon := _icons_by_instance_id.get(_hovered_instance_id) as Control
	var owned := icon.get("owned_card") as OwnedCard if is_instance_valid(icon) else null
	return owned.card_data.get_spell_preparation_column() if owned != null and owned.card_data != null else -1


func _hovered_row_index(column_index: int) -> int:
	if column_index < 0 or column_index >= _lists.size():
		return -1
	var row_index := 0
	for owned: OwnedCard in _prepared_cards:
		if owned.card_data.get_spell_preparation_column() != column_index:
			continue
		if owned.instance_id == _hovered_instance_id:
			return row_index
		row_index += 1
	return -1


func _update_hover_from_pointer() -> void:
	var pointer := get_viewport().get_mouse_position()
	var next_instance_id: StringName = &""
	for column_index: int in _lists.size():
		for card_index: int in range(_prepared_cards.size() - 1, -1, -1):
			var owned := _prepared_cards[card_index]
			if owned.card_data.get_spell_preparation_column() != column_index:
				continue
			var target_position := _target_positions.get(owned.instance_id, Vector2.ZERO) as Vector2
			var list_transform := _lists[column_index].get_global_transform_with_canvas()
			var icon_rect := Rect2(
				list_transform * target_position,
				SPELL_ICON_SCRIPT.ICON_SIZE
			)
			if icon_rect.has_point(pointer):
				next_instance_id = owned.instance_id
				break
		if not next_instance_id.is_empty():
			break
	if next_instance_id.is_empty():
		if not (is_instance_valid(_hover_card_popup) and _hover_card_popup.get_global_rect().has_point(pointer)):
			clear_hover_card()
	else:
		_set_hovered_instance(next_instance_id)


func _animate_icon_to_position(icon: Control, target_position: Vector2) -> void:
	var previous_target: Vector2 = icon.get_meta("sort_target", Vector2.INF) as Vector2
	if previous_target.is_equal_approx(target_position):
		return
	icon.set_meta("sort_target", target_position)
	var previous: Tween = icon.get_meta("sort_tween") as Tween if icon.has_meta("sort_tween") else null
	if is_instance_valid(previous) and previous.is_running():
		previous.kill()
	if icon.position.is_equal_approx(target_position) or not icon.is_inside_tree():
		icon.position = target_position
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(icon, "position", target_position, SORT_TRANSITION_DURATION)
	icon.set_meta("sort_tween", tween)


func _update_scroll_position(column_index: int) -> void:
	var scroll := _scrolls[column_index]
	var target_scroll := clampi(scroll.scroll_vertical, 0, maxi(0, int(_lists[column_index].size.y - scroll.size.y)))
	if target_scroll != scroll.scroll_vertical:
		scroll.scroll_vertical = target_scroll


func _on_icon_click_carry_requested(data: Dictionary, pointer_global_position: Vector2) -> void:
	var owned := data.get("owned_card") as OwnedCard
	if owned != null:
		begin_card_carry(owned.instance_id)
	click_carry_requested.emit(data, pointer_global_position)


func _on_icon_inspection_requested(card_data: CardData, owned_card: OwnedCard) -> void:
	clear_hover_card()
	inspection_requested.emit(null, card_data, owned_card)


func _update_insertion_preview(owned: OwnedCard, insertion_index: int) -> void:
	_preview_instance_id = owned.instance_id
	_preview_index = insertion_index
	_preview_order.clear()
	for card: OwnedCard in _prepared_cards:
		if card.instance_id != owned.instance_id:
			_preview_order.append(card)
	_preview_order.insert(clampi(insertion_index, 0, _preview_order.size()), owned)
	_update_insertion_preview_layout()
	var column_index := owned.card_data.get_spell_preparation_column()
	var row_index := insertion_index - _count_before_column(column_index)
	var list_position := Vector2(ICON_POSITION.x, row_index * ICON_STEP)
	var list_transform := _lists[column_index].get_global_transform_with_canvas()
	var ghost_global := list_transform * list_position
	var tray_transform := get_global_transform_with_canvas()
	_insertion_ghost.texture = (_icons_by_instance_id.get(owned.instance_id) as TextureButton).texture_normal if _icons_by_instance_id.has(owned.instance_id) else _get_spell_icon_texture(owned)
	_insertion_ghost.position = tray_transform.affine_inverse() * ghost_global
	_insertion_ghost.visible = true
	var marker_global := list_transform * Vector2(0.0, row_index * ICON_STEP - 1.0)
	_insertion_marker.position = Vector2(
		PANEL_INSET + column_index * COLUMN_STEP + 4.0,
		(tray_transform.affine_inverse() * marker_global).y
	)
	_insertion_marker.size = Vector2(COLUMN_WIDTH - 8.0, 2.0)
	_insertion_marker.visible = true
	_insertion_marker.queue_redraw()


func _update_insertion_preview_layout() -> void:
	var next_y_by_column := [0.0, 0.0, 0.0]
	var bottom_by_column := [0.0, 0.0, 0.0]
	_target_positions.clear()
	for card: OwnedCard in _preview_order:
		var column_index := card.card_data.get_spell_preparation_column()
		_target_positions[card.instance_id] = Vector2(
			ICON_POSITION.x,
			next_y_by_column[column_index]
		)
		bottom_by_column[column_index] = next_y_by_column[column_index] + SPELL_ICON_SCRIPT.ICON_SIZE.y
		next_y_by_column[column_index] += ICON_STEP
		if card.instance_id == _preview_instance_id:
			next_y_by_column[column_index] += HOVER_REVEAL_OFFSET
	for column_index: int in bottom_by_column.size():
		var content_height := maxf(LIST_HEIGHT, bottom_by_column[column_index])
		_lists[column_index].custom_minimum_size = Vector2(COLUMN_WIDTH, content_height)
		_lists[column_index].size = _lists[column_index].custom_minimum_size
	for card: OwnedCard in _preview_order:
		if card.instance_id == _preview_instance_id and card.instance_id == _carried_instance_id:
			continue
		var icon := _icons_by_instance_id.get(card.instance_id) as Control
		if is_instance_valid(icon):
			_animate_icon_to_position(icon, _target_positions[card.instance_id])
	for column_index: int in _scrolls.size():
		_update_scroll_position(column_index)


func _get_spell_icon_texture(owned: OwnedCard) -> Texture2D:
	var trigger_column: int = SPELL_ICON_STYLE.source_column_for_trigger(
		owned.card_data.spell_trigger_kind
	)
	return SPELL_ICON_STYLE.get_texture(trigger_column, owned.card_data.rarity)


func _clear_insertion_preview() -> void:
	var had_preview := not _preview_instance_id.is_empty()
	_preview_instance_id = &""
	_preview_index = -1
	_preview_order.clear()
	_hide_insertion_marker()
	if is_instance_valid(_insertion_ghost):
		_insertion_ghost.visible = false
	if had_preview:
		_refresh_cards()


func _count_before_column(column_index: int) -> int:
	var count := 0
	for card: OwnedCard in _prepared_cards:
		if card.card_data.get_spell_preparation_column() < column_index:
			count += 1
	return count


func _hide_insertion_marker() -> void:
	if is_instance_valid(_insertion_marker):
		_insertion_marker.visible = false


func _draw_insertion_marker() -> void:
	if is_instance_valid(_insertion_marker):
		_insertion_marker.draw_rect(Rect2(Vector2.ZERO, _insertion_marker.size), INSERTION_MARKER_COLOR)
