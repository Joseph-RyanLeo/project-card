extends Control

## BattlefieldRow 上方的 Godot 拖放接收层。
## 该节点只转发坐标和拖拽数据；布局、容量和堆叠是否合法由 BattlefieldRow 决定。

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
	# 只在当前拖拽确实可由战场接收时拦截鼠标，避免透明覆盖层挡住普通交互。
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
		# 单卡开始移动后，两排都会持续显示附近合法目标；离开其中一排时
		# 只清理该排的放置虚影，目标颤动统一在拖拽结束时关闭。
		battlefield_row.clear_drop_preview(false)
