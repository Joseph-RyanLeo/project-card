class_name EscapePauseMenu
extends Control

signal escape_pressed
signal teaching_book_closed
signal modal_visibility_changed
signal tool_requested(tool: StringName)
signal return_requested
signal diagnostic_export_requested
signal restore_requested
signal target_priority_display_changed(enabled: bool)
signal main_menu_requested
signal abandon_requested

const Style = preload("res://scripts/ui/menu_style.gd")
const SettingsPanel = preload("res://scripts/ui/game_settings_panel.gd")
const MENU_BUTTON_SIZE := Vector2(236, 30) # 收藏菜单按钮的最小尺寸
const MENU_BUTTON_SEPARATION: int = 5 # 收藏菜单按钮间距
const BOOK_GUTTER: float = 16.0 # 左右页之间保留书脊
const BOOK_DIM := Color(0.015, 0.02, 0.025, 0.72) # 暂停首页与独立教程书以外区域的暗幕颜色
const MENU_DIM_SECONDS := 0.30 # 红签翻页时背景压暗与回亮的过渡时长
var book_rect: Rect2
var book_bounds: Rect2
var book_art: Array[TextureRect] = []
var book_world_origin := Vector2.ZERO
var task_text_provider: Callable
var teaching_entries_provider: Callable
var battle_shortcut_handler: Callable
var selected_teaching_key: String = ""
var _info: Control
var _tasks: Control
var _menu: Control
var _menu_backdrop: Control
var _menu_dim_tween: Tween
var _transition_shield: Control
var _teaching_book: Control
var _book_art_positions: Array[Vector2] = []
var _home: PanelContainer
var _tools: PanelContainer
var _settings: Control
var _restore_button: Button
var _target_priority_check: CheckButton
var _captured_menu_panels: Array[Control] = []


func _ready() -> void:
	add_to_group(&"escape_pause_menus")
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Style.make_book_theme()
	for source: TextureRect in book_art:
		_book_art_positions.append(source.global_position - book_world_origin)
	_build_controls()
	get_viewport().gui_focus_changed.connect(_keep_focus_in_book)


func _panel(node_name: String, area: Rect2, parent: Control) -> PanelContainer:
	var result := PanelContainer.new()
	result.name = node_name
	result.position = area.position
	result.size = area.size
	parent.add_child(result)
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


func _add_book_backdrop(parent: Control) -> ColorRect:
	var dim := ColorRect.new()
	dim.name = "BookBackdrop"
	dim.color = BOOK_DIM if not book_art.is_empty() else Color.TRANSPARENT
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(dim)
	return dim


func _modal_overlay(node_name: String) -> Control:
	var overlay := Control.new()
	overlay.name = node_name
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	return overlay


func _build_teaching_book() -> Control:
	var overlay := _modal_overlay("InspectionTeachingBook")
	_add_book_backdrop(overlay)
	for index: int in book_art.size():
		var source := book_art[index]
		var art := TextureRect.new()
		art.name = source.name
		art.texture = source.texture
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.position = _book_art_positions[index]
		art.size = source.size
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(art)
	return overlay


func _build_menu_backdrop() -> Control:
	var backdrop := Control.new()
	backdrop.name = "MenuBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	if not book_bounds.has_area():
		return backdrop
	# 四块暗幕围住同一本实景书，纸叠、筛选栏和卷页继续在原来的画布绘制。
	var left := book_bounds.position.x
	var top := book_bounds.position.y
	var right := book_bounds.end.x
	var bottom := book_bounds.end.y
	var edges := [Rect2(0, 0, 0, top), Rect2(0, bottom, 0, 0),
		Rect2(0, top, left, bottom - top), Rect2(right, top, 0, bottom - top)]
	var far_anchors := [Vector2(1, 0), Vector2.ONE, Vector2.ZERO, Vector2(1, 0)]
	for index: int in edges.size():
		var edge: Rect2 = edges[index]
		var shade := ColorRect.new()
		shade.color = BOOK_DIM
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.anchor_right = far_anchors[index].x
		shade.anchor_bottom = far_anchors[index].y
		shade.offset_left = edge.position.x
		shade.offset_top = edge.position.y
		shade.offset_right = edge.end.x if shade.anchor_right == 0.0 else 0.0
		shade.offset_bottom = edge.end.y if shade.anchor_bottom == 0.0 else 0.0
		backdrop.add_child(shade)
	return backdrop


func _build_controls() -> void:
	_menu_backdrop = _build_menu_backdrop()
	_menu_backdrop.modulate.a = 0.0
	_transition_shield = Control.new()
	_transition_shield.name = "BookTransitionShield"
	_transition_shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_transition_shield)
	_transition_shield.hide()
	_transition_shield.visibility_changed.connect(modal_visibility_changed.emit)
	_menu = _modal_overlay("EscapeMenuOverlay")
	_menu.visibility_changed.connect(modal_visibility_changed.emit)
	var half_width := (book_rect.size.x - BOOK_GUTTER) * 0.5
	_home = _panel("PauseMenuPanel", Rect2(book_rect.position, Vector2(half_width, book_rect.size.y)), _menu)
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
	_tools = _panel("DeveloperToolsPanel", book_rect, _menu)
	var tools := _body(_tools, "开发工具")
	var tool_grid := GridContainer.new()
	tool_grid.columns = 2
	tool_grid.add_theme_constant_override("h_separation", BOOK_GUTTER)
	tool_grid.add_theme_constant_override("v_separation", MENU_BUTTON_SEPARATION)
	tools.add_child(tool_grid)
	for entry: Array in preload("res://scripts/ui/developer_tool_catalog.gd").ENTRIES:
		_add_button(tool_grid, entry[0], entry[1], tool_requested.emit.bind(entry[2]))
	_add_button(tool_grid, "任务重玩", "ReplayTaskButton", tool_requested.emit.bind(&"task_replay")).visible = back.visible
	_add_button(tool_grid, "导出诊断日志", "ExportRunDiagnosticsButton", diagnostic_export_requested.emit)
	_restore_button = _add_button(tool_grid, "还原", "RestoreStartupButton", restore_requested.emit)
	_restore_button.disabled = true
	for button: Control in tool_grid.get_children():
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_priority_check = CheckButton.new()
	_target_priority_check.name = "ShowBattleTargetPriority"
	_target_priority_check.text = "显示受击优先级"
	_target_priority_check.toggled.connect(target_priority_display_changed.emit)
	tools.add_child(_target_priority_check)
	_add_button(tools, "返回", "ToolsBackButton", close_subpage)
	_settings = SettingsPanel.new()
	_settings.name = "PauseSettings"
	_settings.embedded_rect = book_rect
	var shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if shell != null: _settings.text_settings_path = shell.text_settings_path()
	_settings.closed.connect(close_subpage)
	_settings.display_changed.connect(func(mode: int):
		if shell != null: show_settings_save_result(shell.change_display_preference(mode)))
	_settings.pixel_edge_aa_changed.connect(func(enabled: bool):
		if shell != null: show_settings_save_result(shell.set_pixel_edge_aa_preference(enabled)))
	_settings.crt_changed.connect(func(enabled: bool, strength: float):
		if shell != null: show_settings_save_result(shell.set_crt_preference(enabled, strength)))
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


func is_transitioning() -> bool:
	return _transition_shield.visible


func set_transitioning(active: bool) -> void:
	_transition_shield.visible = active


func is_teaching_book_open() -> bool:
	return is_instance_valid(_teaching_book)


func blocks_gameplay() -> bool:
	return is_menu_open() or is_transitioning() or is_teaching_book_open()


func active_overlay() -> Control:
	if is_teaching_book_open(): return _teaching_book
	if is_menu_open(): return _menu
	if is_transitioning(): return _transition_shield
	return null


func _keep_focus_in_book(focused: Control) -> void:
	var overlay := active_overlay()
	if overlay != null and focused != null and not overlay.is_ancestor_of(focused): focused.release_focus()


func _move_book_focus(backward: bool) -> void:
	var buttons: Array[Control] = []
	for control: Control in active_overlay().find_children("*", "Control", true, false):
		if not control.is_visible_in_tree() or control.focus_mode != Control.FOCUS_ALL: continue
		if control is BaseButton and control.disabled: continue
		buttons.append(control)
	if buttons.is_empty(): return
	var current := buttons.find(get_viewport().gui_get_focus_owner())
	var next := current + 1
	if backward: next = current - 1 if current >= 0 else buttons.size() - 1
	buttons[posmod(next, buttons.size())].grab_focus()


func set_menu_dim(active: bool, animate: bool = false) -> void:
	if is_instance_valid(_menu_dim_tween): _menu_dim_tween.kill()
	var opacity := 1.0 if active else 0.0
	if not animate:
		_menu_backdrop.modulate.a = opacity
		return
	_menu_dim_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_menu_dim_tween.tween_property(_menu_backdrop, "modulate:a", opacity, MENU_DIM_SECONDS)


func open_menu() -> void:
	set_menu_dim(true)
	prepare_menu_page()
	show_prepared_menu()


func prepare_menu_page(teaching_key: String = "") -> void:
	close_subpage()
	if not teaching_key.is_empty():
		_show_teaching_page(teaching_key)


func show_prepared_menu() -> void:
	_menu.show()


func close_menu(animate: bool = false) -> void:
	_menu.hide()
	set_menu_dim(false, animate)
	if not animate:
		close_subpage()


func capture_menu_spread(paper_rect: Rect2) -> SubViewport:
	var spread := SubViewport.new()
	spread.name = "PauseMenuSpread"
	spread.size = Vector2i(paper_rect.size)
	spread.disable_3d = true
	spread.transparent_bg = true
	spread.gui_disable_input = true
	spread.render_target_update_mode = SubViewport.UPDATE_ONCE
	var content := Control.new()
	content.theme = theme
	content.position = -paper_rect.position
	content.size = _menu.size
	spread.add_child(content)
	for panel: Control in [_home, _tasks, _tools, _settings, _info]:
		if is_instance_valid(panel) and panel.visible:
			panel.reparent(content, false)
			_captured_menu_panels.append(panel)
	return spread


func restore_captured_menu() -> void:
	for panel: Control in _captured_menu_panels:
		panel.reparent(_menu, false)
	_captured_menu_panels.clear()


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
	_settings.sync_crt(
		shell._preferences.crt_enabled if shell != null else false,
		shell._preferences.crt_strength if shell != null else 0.0,
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
	set_menu_dim(true)
	_menu.show()
	close_subpage()
	_show_teaching_page(key)


func _show_teaching_page(key: String) -> void:
	_home.hide()
	_tasks.hide()
	_info = _build_teaching_page(_menu, key, return_requested.emit)


func open_teaching_book(key: String) -> void:
	if is_teaching_book_open(): return
	_teaching_book = _build_teaching_book()
	_build_teaching_page(_teaching_book, key, teaching_book_closed.emit)
	modal_visibility_changed.emit()


func close_teaching_book() -> void:
	if not is_teaching_book_open(): return
	_teaching_book.hide()
	_teaching_book.queue_free()
	_teaching_book = null
	modal_visibility_changed.emit()


func _build_teaching_page(parent: Control, key: String, on_return: Callable) -> Control:
	var page := _panel("TutorialHelpPage", book_rect, parent)
	var body := _body(page, "玩法教学")
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", BOOK_GUTTER)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	var index_scroll := ScrollContainer.new()
	index_scroll.custom_minimum_size.x = 220 # 左侧教学目录及滚动条宽度
	index_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(index_scroll)
	var index := VBoxContainer.new()
	index.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	index.add_theme_constant_override("separation", 6) # 教学目录的按钮间隔
	index_scroll.add_child(index)
	var content_scroll := ScrollContainer.new()
	content_scroll.name = "TeachingContentScroll"
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(content_scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = book_rect.size.x - 252 - BOOK_GUTTER # 正文宽度，减去目录、分隔和滚动条
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8) # 牌型说明与元素表的垂直间距
	content_scroll.add_child(content)
	var text := Label.new()
	text.name = "TaskInfoText"
	text.add_theme_font_size_override("font_size", 16) # 教学详情正文字号
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
		button.custom_minimum_size = Vector2(198, 28) # 目录每一项的最小尺寸
		button.add_theme_font_size_override("font_size", 15) # 目录标题字号
		button.toggle_mode = true
		button.button_group = buttons
		if entry.key == key or (key.is_empty() and selected_teaching_key.is_empty()):
			button.set_pressed_no_signal(true)
			select.call()
			index_scroll.ensure_control_visible.call_deferred(button)
	if selected_teaching_key.is_empty(): text.text = "暂无玩法教学。" if entries.is_empty() else "请从左侧选择玩法教学。"
	_add_button(body, "返回", "TaskHelpBackButton", on_return)
	return page


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
	cell.custom_minimum_size.x = 42 if column == 0 else 86 # 首列仅放元素名，其余列为规则正文预留宽度
	if column > 0: cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := Color("e9cf9a") if featured else Color("cda783") if header or column == 0 else Color("e6c39e") # 档位高亮、表头与普通格的纸色
	var box := Style.panel(fill, Color("95653d") if featured else Color("af8564")) # 高亮与普通表格边线颜色
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
	cell.add_child(label)


func _build_task_info() -> Control:
	var panel := _panel("RunTasksPage", Rect2(_home.position + Vector2(_home.size.x + BOOK_GUTTER, 0), _home.size), _menu)
	var body := _body(panel, "本局任务")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var text := Label.new()
	text.name = "TaskInfoText"
	text.custom_minimum_size.x = panel.size.x - theme.get_stylebox("panel", "PanelContainer").get_minimum_size().x - 10.0 # 留出任务正文滚动条的宽度
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
	if get_viewport().is_input_handled() or not is_visible_in_tree(): return
	if is_transitioning():
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		escape_pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_TAB and blocks_gameplay():
		_move_book_focus(event.shift_pressed)
		get_viewport().set_input_as_handled()
	elif not blocks_gameplay() and battle_shortcut_handler.is_valid() and battle_shortcut_handler.call(event):
		get_viewport().set_input_as_handled()
