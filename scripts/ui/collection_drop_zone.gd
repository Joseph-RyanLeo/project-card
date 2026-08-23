extends Control

## 收藏区域的拖放接收层。
## 它只接收从我方战场放回的卡牌/小队；收藏自身的卡牌不会被它接收，
## 因而玩家无法通过拖放调整收藏顺序。真实回收事务仍由 Main 提交。

signal card_dropped(data: Dictionary, card_global_position: Vector2)

const HIGHLIGHT_COLOR := Color(0.48, 0.9, 0.66, 0.95) # 场上卡可放回收藏时，收藏区域边框的高亮颜色

var drop_enabled: bool = false
var _accepting_current_drag: bool = false
var _highlighted: bool = false


func _ready() -> void:
	mouse_exited.connect(_on_mouse_exited)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return preview_card_drop(global_position + at_position, data)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	commit_card_drop(global_position + at_position, data)


func preview_card_drop(
	_pointer_global_position: Vector2,
	data: Variant
) -> bool:
	var can_drop := _is_card_drag(data)
	_set_highlighted(can_drop)
	return can_drop


# 先复用 preview_card_drop 做同一套合法性检查，再把实体卡当前视觉位置交给 Main 做飞入动画。
func commit_card_drop(
	pointer_global_position: Vector2,
	data: Variant
) -> void:
	if not preview_card_drop(pointer_global_position, data):
		return

	_set_highlighted(false)
	var drag_data := data as Dictionary
	var preview_offset: Vector2 = drag_data.get("preview_offset", Vector2.ZERO)
	var drag_visual := drag_data.get("drag_visual") as CardDragPreview
	card_dropped.emit(
		drag_data,
		drag_visual.get_card_global_position()
		if is_instance_valid(drag_visual)
		else pointer_global_position - preview_offset
	)


func clear_drop_preview() -> void:
	_set_highlighted(false)


func _notification(what: int) -> void:
	# 拖拽开始时才启用鼠标拦截，平时不遮挡下方收藏。
	if what == NOTIFICATION_DRAG_BEGIN:
		var drag_data: Variant = get_viewport().gui_get_drag_data()
		_accepting_current_drag = _is_card_drag(drag_data)
		mouse_filter = (
			Control.MOUSE_FILTER_STOP
			if _accepting_current_drag
			else Control.MOUSE_FILTER_IGNORE
		)
	elif what == NOTIFICATION_DRAG_END:
		_accepting_current_drag = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_highlighted(false)


func _draw() -> void:
	if _highlighted:
		draw_rect(Rect2(Vector2.ZERO, size), HIGHLIGHT_COLOR, false, 3.0)


func _is_card_drag(data: Variant) -> bool:
	if not drop_enabled or not data is Dictionary:
		return false

	var drag_data := data as Dictionary
	if drag_data.get("source_type") != &"board":
		return false
	if drag_data.get("kind") == &"card":
		return drag_data.get("card_data") is CardData
	if drag_data.get("kind") == &"squad":
		return drag_data.get("squad_data") is SquadData
	return false


func _set_highlighted(value: bool) -> void:
	if _highlighted == value:
		return

	_highlighted = value
	queue_redraw()


func _on_mouse_exited() -> void:
	_set_highlighted(false)
