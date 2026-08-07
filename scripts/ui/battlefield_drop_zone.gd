extends Control

var battlefield_row: Variant


func _ready() -> void:
	mouse_exited.connect(_on_mouse_exited)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if battlefield_row == null:
		return false

	return battlefield_row.preview_card_drop(at_position, data)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if battlefield_row != null:
		battlefield_row.commit_card_drop(at_position, data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var drag_data: Variant = get_viewport().gui_get_drag_data()
		mouse_filter = (
			Control.MOUSE_FILTER_STOP
			if battlefield_row != null and battlefield_row.can_receive_card_drag(drag_data)
			else Control.MOUSE_FILTER_IGNORE
		)
	elif what == NOTIFICATION_DRAG_END:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_mouse_exited() -> void:
	if battlefield_row != null:
		battlefield_row.clear_drop_preview()
