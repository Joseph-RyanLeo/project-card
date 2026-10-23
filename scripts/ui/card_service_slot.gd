extends PanelContainer

## 强化和商店共用的借用卡位；原部署保留虚影，取消或退出归还原位。
signal card_selected(data: Dictionary)
signal card_returned
const SLOT_SIZE := Vector2(130, 155) # 卡牌空槽及外侧投放范围
const CARD_POSITION := Vector2(15, 8) # 卡牌轮廓在空槽内的位置
const CARD_SIZE := Vector2(99, 136) # 空槽按真实卡牌大小画出轮廓
var use_board_art: bool = false # 使用新棋盘自带的凹槽时，隐藏旧空槽轮廓和文字
var accepts_card: Callable
var resolve_card_view: Callable
var _empty_outline: Panel
var _card_view: CardView
var _selected_card: OwnedCard
var release_card_view: Callable
var allow_deployment: bool = false # 强化结果页允许从槽内直接重新部署

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
	if not is_node_ready():
		_selected_card = owned
		return
	_empty_outline.visible = owned == null and not use_board_art and not allow_deployment
	if owned == null:
		return_card(false)
		return
	if is_instance_valid(_card_view) and _card_view.get_owned_card() == owned:
		return
	return_card(false)
	_selected_card = owned
	_card_view = resolve_card_view.call(owned) if resolve_card_view.is_valid() else null
	if not is_instance_valid(_card_view):
		_empty_outline.visible = not use_board_art and not allow_deployment
		return
	_card_view.clear_pointer_hover_feedback()
	_card_view._reset_interaction_visual()
	_card_view.set_card_data(owned.card_data)
	_card_view.set_owned_card(owned)
	if owned.card_data.card_type == CardData.CardType.MINION:
		_card_view.set_squad_attribute_preview_from_squad(SquadData.from_owned_card(owned))
	else: _card_view.set_squad_attribute_preview()
	_card_view.set_attribute_source_state(true, true, true, 1.0)
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

func return_card(notify: bool = true, release_position: Vector2 = Vector2.INF) -> void:
	var view := _card_view
	var owned := _selected_card
	_card_view = null
	_selected_card = null
	if is_instance_valid(view):
		view.set_service_stickers_detached(false)
		var entry := release_position if release_position.is_finite() else view.get_global_transform_with_canvas().origin
		view.queue_free()
		if release_card_view.is_valid(): release_card_view.call_deferred(owned, entry)
	if is_instance_valid(_empty_outline): _empty_outline.visible = not use_board_art and not allow_deployment
	if notify: card_returned.emit()

func enrich_drag_data(data: Dictionary, _card: CardData) -> Dictionary:
	var result := data.duplicate()
	if _selected_card != null and _selected_card.card_data.card_type == CardData.CardType.MINION:
		# 单卡仍计算自身贴纸、伤势、符文与永久成长，不带原小队的装备或光环。
		result["squad_data"] = SquadData.from_owned_card(_selected_card)
	return result

static func board_drag_data(data: Dictionary) -> Dictionary:
	if data.get("source_type") != &"card_service": return data
	var service := data.get("source_slot") as Control
	if not is_instance_valid(service) or not service.allow_deployment or not is_instance_valid(service._card_view): return data
	var origin: Dictionary = service._card_view.get_meta("service_origin", {})
	if origin.is_empty(): return data
	var result := data.duplicate()
	result.merge(origin, true)
	result["service_slot"] = service
	return result

static func get_entry_position(data: Dictionary) -> Vector2:
	# 必须在移入卡槽前读取，原卡的父节点和布局随后会改变。
	var visual: Variant = data.get("drag_visual")
	return (visual as CardDragPreview).get_card_global_position() if is_instance_valid(visual) else Vector2.INF

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


func _notification(what: int) -> void:
	# 收板换父节点也会退出场景树；只有真正销毁卡槽才释放借用卡，往返不重建卡面。
	if what == NOTIFICATION_PREDELETE: return_card(false)

func _can_drop_data(_point: Vector2, data: Variant) -> bool:
	return data is Dictionary and accepts_card.is_valid() and accepts_card.call(data)

func _drop_data(_point: Vector2, data: Variant) -> void:
	if _can_drop_data(Vector2.ZERO, data):
		card_selected.emit(data)
