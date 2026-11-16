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
const MENU_PANEL_SIZE := Vector2(440, 580) # 对局暂停首页尺寸，容纳放弃入口
const TOOLS_PANEL_SIZE := Vector2(440, 648) # 调试子页尺寸，完整落在720p画布内
const MENU_BUTTON_SIZE := Vector2(360, 40) # 暂停与工具页按钮尺寸
const TOOL_BUTTON_PADDING: int = 4 # 调试子页按钮上下留白，保证全部工具落在720p画布内
const MENU_BUTTON_SEPARATION: int = 8 # 暂停菜单按钮间距
const TASK_PANEL_SIZE := Vector2(380, 580) # 本局任务侧栏与暂停首页等高
const TASK_PANEL_GAP: float = 16.0 # 暂停首页与任务侧栏之间的间隔
var task_text_provider: Callable
var teaching_entries_provider: Callable
var selected_teaching_key: String = ""
var _info: Control
var _tasks: Control
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
	_add_button(home, "玩法教学", "TutorialHelpButton", open_teaching)
	_add_button(home, "开发工具", "DeveloperToolsButton", open_tools)
	var back := _add_button(home, "保存并返回主菜单", "ReturnToMainMenuButton", main_menu_requested.emit)
	back.visible = get_tree().get_first_node_in_group(&"game_display_shell") != null
	var abandon := _add_button(home, "放弃本局…", "AbandonRunButton", _confirm_abandon)
	abandon.visible = back.visible
	_tasks = _build_task_info()
	_tools = _panel("DeveloperToolsPanel", TOOLS_PANEL_SIZE)
	_tools.theme = theme.duplicate()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var compact := theme.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		compact.content_margin_top = TOOL_BUTTON_PADDING
		compact.content_margin_bottom = TOOL_BUTTON_PADDING
		_tools.theme.set_stylebox(state, "Button", compact)
	var tools := _body(_tools, "开发工具")
	for entry: Array in preload("res://scripts/ui/developer_tool_catalog.gd").ENTRIES:
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
	_settings.pixel_edge_aa_changed.connect(func(enabled: bool):
		if shell != null: show_settings_save_result(shell.set_pixel_edge_aa_preference(enabled)))
	_menu.add_child(_settings)
	if shell != null:
		_settings.sync_values(shell._preferences.volume, shell.current_display_mode, shell._preferences.pixel_edge_aa)
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
	close_subpage()
	_home.hide()
	_tasks.hide()
	_tools.hide()
	var shell := get_tree().get_first_node_in_group(&"game_display_shell")
	_settings.sync_values(
		_settings.volume_slider.value,
		shell.current_display_mode if shell != null else 1,
		shell._preferences.pixel_edge_aa if shell != null else false,
		shell != null
	)
	_settings.show()


func open_tools() -> void:
	close_subpage()
	_home.hide()
	_tasks.hide()
	_settings.hide()
	_tools.show()


func close_subpage() -> bool:
	var changed: bool = _settings.visible or _tools.visible or (is_instance_valid(_info) and _info.name == "TutorialHelpPage")
	if is_instance_valid(_info):
		_info.hide()
		_info.queue_free()
		_info = null
	_settings.hide()
	_tools.hide()
	_home.show()
	_tasks.show()
	(_tasks.find_child("TaskInfoText", true, false) as Label).text = task_text_provider.call(false) if task_text_provider.is_valid() else "本局未携带任务。"
	return changed


func open_teaching(key: String = "") -> void:
	_menu.show()
	close_subpage()
	_home.hide()
	_tasks.hide()
	_info = _panel("TutorialHelpPage", Vector2(1100, 650)) # 教学目录与正文并排显示的页面尺寸
	var body := _body(_info, "玩法教学")
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20) # 目录与正文的水平间距
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	var index_scroll := ScrollContainer.new()
	index_scroll.custom_minimum_size = Vector2(300, 500) # 目录宽度与滚动区域高度
	index_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(index_scroll)
	var index := VBoxContainer.new()
	index.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	index.add_theme_constant_override("separation", 6) # 教学目录的按钮间隔
	index_scroll.add_child(index)
	var content_scroll := ScrollContainer.new()
	content_scroll.name = "TeachingContentScroll"
	content_scroll.custom_minimum_size = Vector2(740, 500) # 正文宽度，长教学可单独滚动
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(content_scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 716 # 为正文滚动条预留的宽度
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8) # 牌型说明与元素表的垂直间距
	content_scroll.add_child(content)
	var text := Label.new()
	text.name = "TaskInfoText"
	text.add_theme_font_size_override("font_size", 20) # 教学详情正文字号
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(text)
	var table := VBoxContainer.new()
	table.name = "TeachingElementTable"
	table.hide()
	content.add_child(table)
	var entries: Array = teaching_entries_provider.call() if teaching_entries_provider.is_valid() else []
	selected_teaching_key = ""
	var buttons := ButtonGroup.new()
	for entry: Dictionary in entries:
		var select := func():
			selected_teaching_key = entry.key
			var gap := "\n" if entry.has("table") else "\n\n"
			text.text = entry.title + gap + entry.text
			_show_teaching_table(table, entry)
			content_scroll.scroll_vertical = 0
		var button := Style.button(index, entry.title, "Teaching_" + String(entry.key).validate_node_name(), select)
		button.custom_minimum_size = Vector2(280, 44) # 目录每一项的最小尺寸
		button.add_theme_font_size_override("font_size", 17) # 目录标题字号
		button.toggle_mode = true
		button.button_group = buttons
		if entry.key == key or (key.is_empty() and selected_teaching_key.is_empty()):
			button.set_pressed_no_signal(true)
			select.call()
			index_scroll.ensure_control_visible.call_deferred(button)
	if selected_teaching_key.is_empty(): text.text = "暂无玩法教学。" if entries.is_empty() else "请从左侧选择玩法教学。"
	_add_button(body, "返回", "TaskHelpBackButton", return_requested.emit)


func _show_teaching_table(container: VBoxContainer, entry: Dictionary) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
	var table: Dictionary = entry.get("table", {})
	container.visible = not table.is_empty()
	if table.is_empty(): return
	var featured: Array[int] = []
	# JSON 数字读成浮点数；先转成整数，和表格列号使用相同类型。
	for index: Variant in entry.featured_columns:
		featured.append(int(index))
	var heading := Label.new()
	heading.text = table.title
	heading.add_theme_font_size_override("font_size", 20) # 元素表标题字号
	container.add_child(heading)
	var caption := Label.new()
	caption.text = table.caption
	if not featured.is_empty(): caption.text += "表中标亮的档位适用于当前牌型。"
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 16) # 元素表注释字号
	container.add_child(caption)
	var grid := GridContainer.new()
	grid.columns = table.columns.size() + 1
	grid.add_theme_constant_override("h_separation", 3) # 元素表列间距
	grid.add_theme_constant_override("v_separation", 2) # 元素表行间距
	container.add_child(grid)
	var headers: Array = ["元素"] + table.columns
	for column: int in headers.size():
		_add_teaching_cell(grid, headers[column], column, true, featured.has(column - 1))
	for row: Array in table.rows:
		for column: int in row.size():
			_add_teaching_cell(grid, row[column], column, false, featured.has(column - 1))


func _add_teaching_cell(grid: GridContainer, value: String, column: int, header: bool, featured: bool) -> void:
	var cell := PanelContainer.new()
	cell.custom_minimum_size.x = 42 if column == 0 else 122 # 首列仅放元素名，其余列为规则正文预留宽度
	if column > 0: cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := Color("433422") if featured else Color("252f3c") if header or column == 0 else Color("1e2733") # 档位高亮、表头与普通格的底色
	var box := Style.panel(fill, Color("ba955b") if featured else Color("39424b")) # 高亮与普通表格边线颜色
	box.set_border_width_all(1) # 表格细边线宽度
	box.set_content_margin_all(5) # 单元格文字左右留白
	box.content_margin_top = 3 # 单元格上方留白
	box.content_margin_bottom = 3 # 单元格下方留白
	cell.add_theme_stylebox_override("panel", box)
	grid.add_child(cell)
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if header or column == 0: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15) # 元素效果单元格字号
	label.add_theme_color_override("font_color", Color("fff0c2") if featured else Color("e4d7c0")) # 重点档位和普通正文颜色
	cell.add_child(label)


func _build_task_info() -> Control:
	var panel := _panel("RunTasksPage", TASK_PANEL_SIZE)
	panel.position = _home.position + Vector2(_home.size.x + TASK_PANEL_GAP, 0)
	var body := _body(panel, "本局任务")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(348, 500) # 任务侧栏独立滚动正文的尺寸
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var text := Label.new()
	text.name = "TaskInfoText"
	text.custom_minimum_size.x = 326 # 留出任务正文滚动条的宽度
	text.add_theme_font_size_override("font_size", 18) # 任务侧栏正文字号
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.text = task_text_provider.call(false) if task_text_provider.is_valid() else "当前没有任务。"
	scroll.add_child(text)
	return panel


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
