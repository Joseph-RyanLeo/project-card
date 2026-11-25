class_name CardInspectionOverlay
extends Control

## 游戏内大卡牌检视的输入外壳。
## 置为 ALWAYS 后，即使战斗因检视暂停，Esc 和背景关闭仍能被处理。

const TOOLBOX_EDGE_WIDTH: float = 14.0 # 窗口左缘的触发宽度，按游戏逻辑像素计算
const TOOLBOX_EDGE_DWELL_SECONDS: float = 0.16 # 鼠标进入左缘后展开工具箱所需的停留时长

signal close_requested
var cancel_carry_if_active: Callable
var input_handler: Callable
var open_toolbox_from_edge: Callable
var pointer_position := Vector2.ZERO
var _toolbox_edge_timer: Timer
var _pointer_at_toolbox_edge := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	if open_toolbox_from_edge.is_valid():
		_toolbox_edge_timer = Timer.new()
		_toolbox_edge_timer.one_shot = true
		_toolbox_edge_timer.wait_time = TOOLBOX_EDGE_DWELL_SECONDS
		_toolbox_edge_timer.timeout.connect(open_toolbox_from_edge)
		add_child(_toolbox_edge_timer)
		get_window().mouse_exited.connect(clear_toolbox_edge)


func _input(event: InputEvent) -> void:
	if get_viewport().is_input_handled(): return
	var pause_menu := get_tree().get_first_node_in_group(&"escape_pause_menus")
	if pause_menu != null and pause_menu.blocks_gameplay(): return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		pointer_position = event.position
		if _toolbox_edge_timer != null:
			_track_toolbox_edge(event)
	if input_handler.is_valid() and bool(input_handler.call(event)):
		get_viewport().set_input_as_handled()
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


func _track_toolbox_edge(event: InputEventMouse) -> void:
	var local_pointer := get_global_transform_with_canvas().affine_inverse() * event.position
	var edge := Rect2(0.0, 0.0, TOOLBOX_EDGE_WIDTH, size.y)
	if not edge.has_point(local_pointer):
		clear_toolbox_edge()
		return
	if event is InputEventMouseButton or event.button_mask != 0:
		_toolbox_edge_timer.stop()
	elif not _pointer_at_toolbox_edge:
		_toolbox_edge_timer.start()
	_pointer_at_toolbox_edge = true


func clear_toolbox_edge() -> void:
	_pointer_at_toolbox_edge = false
	if _toolbox_edge_timer != null: _toolbox_edge_timer.stop()
