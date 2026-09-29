class_name DeveloperConsole
extends Panel

signal command_submitted(command: String)

const PANEL_SIZE := Vector2(420.0, 190.0) # 控制台在游戏画面中的宽高

var _output: RichTextLabel
var _command_input: LineEdit


func _ready() -> void:
	position = Vector2(430.0, 500.0) # 控制台靠近画面下方并保持在画布内
	size = PANEL_SIZE
	custom_minimum_size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("211d21")
	panel_style.border_color = Color("d1aa58")
	panel_style.set_border_width_all(2)
	add_theme_stylebox_override("panel", panel_style)
	_build_contents()
	append_output("开发控制台已开启。输入 help 查看命令。")


func set_open(value: bool) -> void:
	visible = value
	if value and is_instance_valid(_command_input):
		_command_input.grab_focus()


func append_output(message: String) -> void:
	if not is_instance_valid(_output):
		return
	_output.append_text(message.c_escape() + "\n")
	_output.scroll_to_line(maxi(0, _output.get_line_count() - 1))


func _build_contents() -> void:
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 8.0
	layout.offset_top = 6.0
	layout.offset_right = -8.0
	layout.offset_bottom = -7.0
	layout.add_theme_constant_override("separation", 5) # 标题、历史输出与输入框的间距
	add_child(layout)
	var title := Label.new()
	title.text = "开发控制台 · F2 开关 · Esc 关闭"
	layout.add_child(title)
	_output = RichTextLabel.new()
	_output.bbcode_enabled = false
	_output.scroll_active = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.custom_minimum_size = Vector2(0.0, 110.0) # 保留最近命令结果的可读高度
	layout.add_child(_output)
	_command_input = LineEdit.new()
	_command_input.placeholder_text = "wound add 中毒Ⅰ"
	_command_input.text_submitted.connect(_on_command_submitted)
	_command_input.gui_input.connect(_on_input_gui_event)
	layout.add_child(_command_input)


func _on_command_submitted(command: String) -> void:
	var trimmed := command.strip_edges()
	if trimmed.is_empty():
		return
	append_output("> " + trimmed)
	command_submitted.emit(trimmed)
	_command_input.clear()


func _on_input_gui_event(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		set_open(false)
