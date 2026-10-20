extends PanelContainer

## 强化和商店临时保管真实卡面；拥有权保留，结束时归还来源节点。
signal card_selected(data: Dictionary)
signal card_returned
const CARD_SCENE := preload("res://scenes/ui/CardView.tscn")
const SLOT_SIZE := Vector2(130, 155) # 卡牌空槽及外侧投放范围
const CARD_POSITION := Vector2(15, 8) # 卡牌轮廓在空槽内的位置
const CARD_SIZE := Vector2(99, 136) # 空槽按真实卡牌大小画出轮廓
var use_board_art: bool = false # 使用新棋盘自带的凹槽时，隐藏旧空槽轮廓和文字
var accepts_card: Callable
var resolve_card_view: Callable
var _empty_outline: Panel
var _card_view: CardView
var _selected_card: OwnedCard
var _source: Dictionary = {}
var _source_ghost: CardView

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = SLOT_SIZE
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var host := Control.new()
	host.custom_minimum_size = SLOT_SIZE
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	_empty_outline = Panel.new()
	_empty_outline.name = "EmptyCardOutline"
	_empty_outline.position = CARD_POSITION
	_empty_outline.size = CARD_SIZE
	_empty_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("15181c", 0.65) # 卡牌凹槽底色与透明度
	style.border_color = Color("bba974", 0.85) # 卡牌空槽轮廓颜色与透明度
	style.set_border_width_all(2) # 空槽轮廓像素宽度
	style.set_corner_radius_all(5) # 空槽轮廓圆角
	_empty_outline.add_theme_stylebox_override("panel", style)
	host.add_child(_empty_outline)
	var hint := Label.new()
	hint.text = "+\n拖入卡牌"
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_outline.add_child(hint)
	show_card(_selected_card)

func show_card(owned: OwnedCard) -> void:
	_selected_card = owned
	if not is_node_ready():
		return
	_empty_outline.visible = owned == null and not use_board_art
	if owned == null:
		return_card(false)
		return
	if is_instance_valid(_card_view) and _card_view.get_owned_card() == owned:
		return
	return_card(false)
	_selected_card = owned
	_card_view = resolve_card_view.call(owned) if resolve_card_view.is_valid() else null
	if not is_instance_valid(_card_view):
		_empty_outline.visible = not use_board_art
		return
	var source_slot := _card_view._drag_source_slot
	if is_instance_valid(source_slot) and source_slot.has_method("reset_hover_feedback"):
		source_slot.reset_hover_feedback()
	_card_view.clear_pointer_hover_feedback()
	_card_view._reset_interaction_visual()
	_source = {"parent": _card_view.get_parent(), "index": _card_view.get_index(), "position": _card_view.position, "scale": _card_view.scale, "z": _card_view.z_index, "alpha": 1.0, "marker": _card_view.show_new_card_marker, "filter": _card_view.mouse_filter, "enabled": _card_view._drag_enabled, "type": _card_view._drag_source_type, "row": _card_view._drag_source_row, "slot": _card_view._drag_source_slot}
	if _source.type == &"collection":
		(_source.parent as Control).modulate.a = 1.0
	_create_source_ghost()
	_card_view.set_meta("card_service_slot", self)
	_card_view.reparent(_empty_outline.get_parent(), false)
	_card_view.set_layout_position(CARD_POSITION)
	_card_view.scale = Vector2.ONE
	_card_view.set_resting_z_index(1)
	_card_view.modulate.a = 1.0
	_card_view.visible = true
	_card_view.show_new_card_marker = false
	_card_view._refresh_new_card_dot()
	_card_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_view.configure_drag_source(true, &"card_service", null, self)
	_empty_outline.visible = false

func rebind_collection_source(parent: Control) -> void:
	# 收藏翻页重建来源容器，卡面仍留在槽内；回来时归还到当前页的空位置。
	if _source.get("type") != &"collection": return
	_source["parent"] = parent
	_source["index"] = 0
	_source["slot"] = parent
	_create_source_ghost()


func return_card(notify: bool = true) -> void:
	_clear_source_ghost()
	var view := _card_view
	_card_view = null
	_selected_card = null
	if is_instance_valid(view):
		view.set_service_stickers_detached(false)
		view.set_as_top_level(false)
		view.remove_meta("card_service_slot")
		var parent := _source.get("parent") as Node
		if is_instance_valid(parent) and not parent.is_queued_for_deletion():
			view.reparent(parent, false)
			parent.move_child(view, mini(int(_source.index), parent.get_child_count() - 1))
			view.set_layout_position(_source.position)
			view.scale = _source.scale
			view.set_resting_z_index(_source.z)
			view.modulate.a = _source.alpha
			view.show_new_card_marker = _source.marker
			view._refresh_new_card_dot()
			view.mouse_filter = _source.filter
			view.configure_drag_source(_source.enabled, _source.type, _source.row, _source.slot)
		else:
			view.queue_free()
	_source.clear()
	if is_instance_valid(_empty_outline): _empty_outline.visible = not use_board_art
	if notify: card_returned.emit()

func _clear_source_ghost() -> void:
	if is_instance_valid(_source_ghost):
		if _source_ghost.get_parent() != null:
			_source_ghost.get_parent().remove_child(_source_ghost)
		_source_ghost.queue_free()
	_source_ghost = null

func _create_source_ghost() -> void:
	_clear_source_ghost()
	if _source.get("type") != &"collection" or not is_instance_valid(_card_view): return
	var parent := _source.get("parent") as Control
	if not is_instance_valid(parent): return
	_source_ghost = CARD_SCENE.instantiate() as CardView
	_source_ghost.set_card_data(_card_view.card_data)
	_source_ghost.set_owned_card(_card_view.get_owned_card())
	_source_ghost.set_snapshot_mode(true)
	_source_ghost.showing_effect = _card_view.showing_effect
	parent.add_child(_source_ghost)
	_source_ghost.pivot_offset = _card_view.card_size * 0.5
	_source_ghost.set_layout_position(_source.position)
	_source_ghost.scale = _source.scale
	_source_ghost.modulate.a = CardView.COLLECTION_DRAG_GHOST_ALPHA

static func get_entry_position(data: Dictionary) -> Vector2:
	# 必须在刷新界面前读取；刷新会搬动原卡或重建强化槽的父容器。
	var visual := data.get("drag_visual") as CardDragPreview
	return visual.get_card_global_position() if is_instance_valid(visual) else Vector2.INF

func animate_entry_from_global_position(entry_position: Vector2) -> void:
	if not entry_position.is_finite() or not is_instance_valid(_card_view): return
	var view := _card_view
	# Container在帧尾排版。先让卡面按画布坐标停在松手处，避免父容器
	# 尚在(0,0)时换算起点；父容器排好后再沿用已有的卡牌位移Tween。
	view.set_as_top_level(true)
	view.position = entry_position
	await get_tree().process_frame
	if not is_instance_valid(view) or view != _card_view: return
	view.set_as_top_level(false)
	view.animate_from_global_position(entry_position)


func _exit_tree() -> void:
	return_card(false)

func _can_drop_data(_point: Vector2, data: Variant) -> bool:
	return data is Dictionary and accepts_card.is_valid() and accepts_card.call(data)

func _drop_data(_point: Vector2, data: Variant) -> void:
	if _can_drop_data(Vector2.ZERO, data):
		card_selected.emit(data)
