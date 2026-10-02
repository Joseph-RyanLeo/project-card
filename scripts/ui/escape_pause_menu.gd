class_name EscapePauseMenu
extends Control

signal escape_pressed
signal tool_requested(tool: StringName)
signal return_requested
signal restore_requested
signal target_priority_display_changed(enabled: bool)

const MENU_PANEL_SIZE := Vector2(360.0, 390.0) # 暂停菜单面板宽高
const MENU_BUTTON_SIZE := Vector2(260.0, 38.0) # 暂停菜单按钮宽高
const MENU_BUTTON_SEPARATION: int = 8 # 菜单各按钮之间的垂直间距
const ESCAPE_BUTTON_POSITION := Vector2(0.0, 0.0) # 位于左上角

var _menu: Control
var _restore_button: Button
var _target_priority_check: CheckButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_controls()


func _build_controls() -> void:
	var shortcut := Button.new()
	shortcut.name = "EscapeMenuButton"
	shortcut.text = "Esc"
	shortcut.tooltip_text = "打开暂停菜单"
	shortcut.position = ESCAPE_BUTTON_POSITION
	shortcut.size = Vector2(42.0, 30.0)
	shortcut.pressed.connect(_on_escape_pressed)
	add_child(shortcut)

	_menu = Control.new()
	_menu.name = "EscapeMenuOverlay"
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.visible = false
	add_child(_menu)

	var dim := ColorRect.new()
	dim.name = "PauseDim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.36, 0.38, 0.40, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "PauseMenuPanel"
	panel.position = (Vector2(1280.0, 720.0) - MENU_PANEL_SIZE) * 0.5
	panel.size = MENU_PANEL_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.add_child(panel)

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 36.0
	layout.offset_top = 22.0
	layout.offset_right = -36.0
	layout.offset_bottom = -22.0
	layout.add_theme_constant_override("separation", MENU_BUTTON_SEPARATION)
	panel.add_child(layout)

	var title := Label.new()
	title.text = "暂停菜单"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	layout.add_child(title)
	_add_menu_button(layout, "攻击特效调试器", &"attack_effect_lab")
	_add_menu_button(layout, "卡面调整器", &"card_art_tuner")
	_add_menu_button(layout, "战斗实验室", &"battle_lab")
	_target_priority_check = CheckButton.new()
	_target_priority_check.name = "ShowBattleTargetPriority"
	_target_priority_check.text = "显示受击优先级"
	_target_priority_check.tooltip_text = "在上场小队上显示当前受击抽选权重"
	_target_priority_check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_target_priority_check.toggled.connect(target_priority_display_changed.emit)
	layout.add_child(_target_priority_check)
	_add_menu_button(layout, "返回", &"return")
	_restore_button = _add_menu_button(layout, "还原", &"restore")
	_restore_button.disabled = true
	_restore_button.tooltip_text = "还原基准待确认"


func _add_menu_button(parent: VBoxContainer, label: String, action: StringName) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = MENU_BUTTON_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(_on_menu_action.bind(action))
	parent.add_child(button)
	return button


func is_menu_open() -> bool:
	return _menu.visible


func open_menu() -> void:
	_menu.visible = true


func close_menu() -> void:
	_menu.visible = false


func set_restore_available(value: bool) -> void:
	if not is_instance_valid(_restore_button):
		return
	_restore_button.disabled = not value
	_restore_button.tooltip_text = "恢复本次启动时的界面和运行状态" if value else "启动状态尚未捕获"


func set_target_priority_display_enabled(enabled: bool) -> void:
	if is_instance_valid(_target_priority_check):
		_target_priority_check.set_pressed_no_signal(enabled)


func _input(event: InputEvent) -> void:
	if get_viewport().is_input_handled():
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			escape_pressed.emit()
			get_viewport().set_input_as_handled()


func _on_escape_pressed() -> void:
	escape_pressed.emit()


func _on_menu_action(action: StringName) -> void:
	match action:
		&"attack_effect_lab", &"card_art_tuner", &"battle_lab":
			tool_requested.emit(action)
		&"return":
			return_requested.emit()
		&"restore":
			restore_requested.emit()
