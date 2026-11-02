class_name EscapePauseMenu
extends Control

signal escape_pressed
signal tool_requested(tool: StringName)
signal return_requested
signal diagnostic_export_requested
signal restore_requested
signal target_priority_display_changed(enabled: bool)
signal main_menu_requested
signal abandon_requested

const Style = preload("res://scripts/ui/menu_style.gd")
const SettingsPanel = preload("res://scripts/ui/game_settings_panel.gd")
const MENU_PANEL_SIZE := Vector2(440, 450) # 对局暂停首页尺寸，容纳放弃入口
const TOOLS_PANEL_SIZE := Vector2(440, 648) # 调试子页尺寸，完整落在720p画布内
const MENU_BUTTON_SIZE := Vector2(360, 40) # 暂停与工具页按钮尺寸
const TOOL_BUTTON_PADDING: int = 4 # 调试子页按钮上下留白，保证全部工具落在720p画布内
const MENU_BUTTON_SEPARATION: int = 8 # 暂停菜单按钮间距
var _menu: Control
var _home: PanelContainer
var _tools: PanelContainer
var _settings: Control
var _restore_button: Button
var _target_priority_check: CheckButton


func _ready() -> void:
	add_to_group(&"escape_pause_menus")
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Style.make_theme()
	_build_controls()


func _panel(node_name: String, dimensions: Vector2) -> PanelContainer:
	var result := PanelContainer.new()
	result.name = node_name
	result.position = (Vector2(1280, 720) - dimensions) * 0.5
	result.size = dimensions
	_menu.add_child(result)
	return result


func _body(parent: Control, title: String) -> VBoxContainer:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", MENU_BUTTON_SEPARATION)
	parent.add_child(body)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(label)
	return body


func _build_controls() -> void:
	var shortcut := Button.new()
	shortcut.name = "EscapeMenuButton"
	shortcut.text = "Esc"
	shortcut.tooltip_text = "打开暂停菜单"
	shortcut.size = Vector2(42, 30) # 桌面左上角Esc快捷按钮尺寸
	shortcut.pressed.connect(escape_pressed.emit)
	add_child(shortcut)
	_menu = Control.new()
	_menu.name = "EscapeMenuOverlay"
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_menu)
	var dim := ColorRect.new()
	dim.name = "PauseDim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72) # 暂停时底层桌面的压暗程度
	_menu.add_child(dim)
	_home = _panel("PauseMenuPanel", MENU_PANEL_SIZE)
	var home := _body(_home, "游戏已暂停")
	_add_button(home, "继续游戏", "ContinueGameButton", return_requested.emit)
	_add_button(home, "设置", "PauseSettingsButton", open_settings)
	_add_button(home, "开发工具", "DeveloperToolsButton", open_tools)
	var back := _add_button(home, "保存并返回主菜单", "ReturnToMainMenuButton", main_menu_requested.emit)
	back.visible = get_tree().get_first_node_in_group(&"game_display_shell") != null
	var abandon := _add_button(home, "放弃本局…", "AbandonRunButton", _confirm_abandon)
	abandon.visible = back.visible
	_tools = _panel("DeveloperToolsPanel", TOOLS_PANEL_SIZE)
	_tools.theme = theme.duplicate()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var compact := theme.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		compact.content_margin_top = TOOL_BUTTON_PADDING
		compact.content_margin_bottom = TOOL_BUTTON_PADDING
		_tools.theme.set_stylebox(state, "Button", compact)
	var tools := _body(_tools, "开发工具")
	for entry: Array in [
		["攻击特效调试器", "AttackEffectLabButton", &"attack_effect_lab"],
		["开包特效调整器", "PackEffectTunerButton", &"pack_effect_tuner"],
		["卡包凹凸调试", "PackReliefPreviewButton", &"pack_relief_preview"],
		["卡面调整器", "CardArtTunerButton", &"card_art_tuner"],
		["卡名字体调试", "CardFontLabButton", &"card_font_lab"],
		["战斗实验室", "BattleLabButton", &"battle_lab"],
	]:
		_add_button(tools, entry[0], entry[1], tool_requested.emit.bind(entry[2]))
	_target_priority_check = CheckButton.new()
	_target_priority_check.name = "ShowBattleTargetPriority"
	_target_priority_check.text = "显示受击优先级"
	_target_priority_check.toggled.connect(target_priority_display_changed.emit)
	tools.add_child(_target_priority_check)
	_add_button(tools, "导出诊断日志", "ExportRunDiagnosticsButton", diagnostic_export_requested.emit)
	_restore_button = _add_button(tools, "还原", "RestoreStartupButton", restore_requested.emit)
	_restore_button.disabled = true
	_add_button(tools, "返回", "ToolsBackButton", close_subpage)
	_settings = SettingsPanel.new()
	_settings.name = "PauseSettings"
	var shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if shell != null: _settings.text_settings_path = shell.text_settings_path()
	_settings.closed.connect(close_subpage)
	_settings.display_changed.connect(func(mode: int):
		if shell != null: show_settings_save_result(shell.change_display_preference(mode)))
	_menu.add_child(_settings)
	if shell != null: _settings.sync_values(shell._preferences.volume, shell.current_display_mode)
	_settings.hide()
	_tools.hide()
	_menu.hide()


func _add_button(parent: Control, title: String, node_name: String, action: Callable) -> Button:
	var result := Style.button(parent, title, node_name, action)
	result.custom_minimum_size = MENU_BUTTON_SIZE
	result.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return result


func _confirm_abandon() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.name = "AbandonConfirmation"
	dialog.title = "确认放弃本局"
	dialog.dialog_text = "将按当前状态结束本局并保存结算。\n进入第3天后可计分和选卡；前两天放弃仍保留已实际获得的发现。\n普通保存退出可稍后继续本局。"
	dialog.ok_button_text = "确认放弃并结算"
	dialog.cancel_button_text = "继续本局"
	dialog.confirmed.connect(abandon_requested.emit)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(650, 230)) # 放弃说明与明确确认按钮的弹窗尺寸


func is_menu_open() -> bool:
	return _menu.visible


func open_menu() -> void:
	close_subpage()
	_menu.show()


func close_menu() -> void:
	_menu.hide()
	close_subpage()


func open_settings() -> void:
	_home.hide()
	_tools.hide()
	var shell := get_tree().get_first_node_in_group(&"game_display_shell")
	_settings.sync_values(_settings.volume_slider.value, shell.current_display_mode if shell != null else 1, shell != null)
	_settings.show()


func open_tools() -> void:
	_home.hide()
	_settings.hide()
	_tools.show()


func close_subpage() -> bool:
	var changed: bool = _settings.visible or _tools.visible
	_settings.hide()
	_tools.hide()
	_home.show()
	return changed


func sync_card_text_display_mode() -> void:
	if is_instance_valid(_settings): _settings.sync_text_mode()


func show_settings_save_result(error: Error) -> void:
	_settings.show_save_result(error)


func set_restore_available(value: bool) -> void:
	_restore_button.disabled = not value
	_restore_button.tooltip_text = "恢复本次启动时的界面和运行状态" if value else "启动状态尚未捕获"


func set_target_priority_display_enabled(enabled: bool) -> void:
	_target_priority_check.set_pressed_no_signal(enabled)


func _input(event: InputEvent) -> void:
	if get_viewport().is_input_handled(): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		escape_pressed.emit()
		get_viewport().set_input_as_handled()
