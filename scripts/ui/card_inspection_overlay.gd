class_name CardInspectionOverlay
extends Control

## 游戏内大卡牌检视的输入外壳。
## 置为 ALWAYS 后，即使战斗因检视暂停，Esc 和背景关闭仍能被处理。

signal close_requested
var cancel_carry_if_active: Callable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP


func _input(event: InputEvent) -> void:
	if get_viewport().is_input_handled():
		return
	# 在卡面或按钮消费鼠标/键盘事件前关闭，避免检视中控件吞掉 Escape 与右键。
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if cancel_carry_if_active.is_valid() and bool(cancel_carry_if_active.call()):
			get_viewport().set_input_as_handled()
			return
		close_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			if cancel_carry_if_active.is_valid() and bool(cancel_carry_if_active.call()):
				get_viewport().set_input_as_handled()
				return
			close_requested.emit()
			get_viewport().set_input_as_handled()
