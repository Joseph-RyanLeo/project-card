extends Control

signal start_requested(slot: int)
signal settings_requested
signal quit_requested

const MENU_POSITION := Vector2(72, 244) # 左侧菜单位置，右侧保留迷宫入口和冒险者
const BUTTON_SIZE := Vector2(296, 48) # 主菜单按钮宽高
const BUTTON_GAP: int = 12 # 按钮之间的垂直间距
const PANEL_RECT := Rect2(350, 126, 580, 468) # 存档选择面板的位置和尺寸
const GOLD := Color("dcb77d") # 菜单文字与边框的暖金色

var slots: RunSlotService
var _slot_overlay: Control
var _slot_buttons: Array[Button] = []
var _delete_button: Button
var _selection_label: Label
var _status: Label
var _delete_dialog: ConfirmationDialog
var _busy := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = preload("res://scripts/ui/menu_style.gd").make_theme()
	preload("res://scripts/ui/menu_style.gd").add_background(self)
	var title := _label(self, str(ProjectSettings.get_setting("application/config/name")), Vector2(72, 128), 40)
	title.name = "GameTitle"
	var names: Dictionary = ProjectSettings.get_setting("application/config/name_localized", {})
	var subtitle := _label(self, str(names.get("en", "")), Vector2(76, 192), 20) # 英文标题位于中文下方，菜单上方留出空隙
	subtitle.name = "GameSubtitle"
	var menu := VBoxContainer.new()
	menu.position = MENU_POSITION
	menu.add_theme_constant_override("separation", BUTTON_GAP)
	add_child(menu)
	_button(menu, "开始游戏", "StartButton", _start_selected)
	_button(menu, "选择存档", "SlotsButton", open_slots)
	_button(menu, "设置", "SettingsButton", settings_requested.emit)
	_button(menu, "退出游戏", "QuitButton", quit_requested.emit)
	_selection_label = _label(self, "", Vector2(76, 558), 16)
	_status = _label(self, "", Vector2(72, 610), 16)
	_status.size = Vector2(530, 76) # 长错误信息在左下角换行，避免溢出画面
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_slots()
	refresh()


func _button(parent: Node, text: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_color_override("font_color", GOLD)
	button.add_theme_color_override("font_hover_color", Color("fff0c2"))
	button.add_theme_color_override("font_disabled_color", Color("817869"))
	button.add_theme_stylebox_override("normal", _style(Color(0.055, 0.07, 0.10, 0.88), Color("79674c")))
	button.add_theme_stylebox_override("hover", _style(Color("30333b"), GOLD))
	button.add_theme_stylebox_override("pressed", _style(Color("474031"), GOLD))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, GOLD))
	if callback.is_valid():
		button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2) # 像素风面板边框厚度
	style.content_margin_left = 16 # 按钮文字与边框的水平留白
	style.content_margin_right = 16
	return style


func _label(parent: Node, text: String, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _build_slots() -> void:
	_slot_overlay = Control.new()
	_slot_overlay.name = "SlotOverlay"
	_slot_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_slot_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7) # 存档面板打开时压暗背景
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_overlay.add_child(dim)
	var panel := Panel.new()
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	panel.add_theme_stylebox_override("panel", _style(Color("161e2a"), GOLD))
	_slot_overlay.add_child(panel)
	_label(panel, "选择存档", Vector2(32, 22), 32)
	var rows := VBoxContainer.new()
	rows.position = Vector2(32, 84) # 三个存档行的起始位置
	rows.size.x = PANEL_RECT.size.x - 64
	rows.add_theme_constant_override("separation", 12) # 存档行间距
	panel.add_child(rows)
	for index: int in RunSlotService.SLOT_COUNT:
		var button := _button(rows, "", "Slot%d" % (index + 1), _select_slot.bind(index))
		button.custom_minimum_size.y = 82 # 每个存档行容纳编号、进度和保存时间
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 16) # 存档摘要字号
		button.toggle_mode = true
		_slot_buttons.append(button)
	var actions := HBoxContainer.new()
	actions.position = Vector2(32, 384) # 存档面板底部操作行位置
	actions.add_theme_constant_override("separation", 10) # 底部两个按钮的间距
	panel.add_child(actions)
	_delete_button = _button(actions, "删除", "DeleteSlotButton", _request_delete)
	_delete_button.custom_minimum_size.x = 160 # 底部删除按钮宽度
	var enter := _button(actions, "进入", "EnterSlotButton", _start_selected)
	enter.custom_minimum_size.x = 160 # 进入所选档位按钮宽度
	var back := _button(actions, "返回", "BackButton", close_slots)
	back.custom_minimum_size.x = 160 # 底部返回按钮宽度
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "删除存档"
	_delete_dialog.ok_button_text = "删除"
	_delete_dialog.cancel_button_text = "取消"
	_delete_dialog.confirmed.connect(_delete_selected)
	add_child(_delete_dialog)
	_slot_overlay.hide()


func refresh() -> void:
	var target := slots.get_continue_slot()
	find_child("StartButton", true, false).text = "开始游戏" if target < 0 else "继续游戏"
	_selection_label.text = "继续：存档 %d" % (target + 1) if target >= 0 else "尚无存档"
	for index: int in _slot_buttons.size():
		_slot_buttons[index].text = "存档 %d   %s" % [index + 1, slots.describe_slot(index)]
		_slot_buttons[index].set_pressed_no_signal(index == slots.selected_slot)
	_delete_button.disabled = not slots.has_slot(slots.selected_slot)


func open_slots() -> void:
	refresh()
	_slot_overlay.show()
	_slot_buttons[slots.selected_slot].grab_focus()


func close_slots() -> void:
	_slot_overlay.hide()


func _select_slot(index: int) -> void:
	var error := slots.select_slot(index)
	refresh()
	if error != OK:
		show_error("无法保存存档选择（错误码 %d）" % error)
		return


func _start_selected() -> void:
	if _busy:
		return
	_busy = true
	_status.text = "正在进入存档……"
	var target := slots.selected_slot if _slot_overlay.visible else slots.get_continue_slot()
	start_requested.emit(0 if target < 0 else target)


func show_error(message: String) -> void:
	_busy = false
	close_slots()
	_status.text = message


func reset() -> void:
	_busy = false
	_status.text = ""
	close_slots()
	refresh()
	show()


func _request_delete() -> void:
	_delete_dialog.dialog_text = "确定删除存档 %d？本局、积分、发现、解锁与收藏将全部清除，删除后无法恢复。" % (slots.selected_slot + 1)
	_delete_dialog.popup_centered()


func _delete_selected() -> void:
	var error := slots.delete_slot(slots.selected_slot)
	refresh()
	if error != OK:
		show_error("删除失败（错误码 %d）" % error)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and _slot_overlay.visible:
		close_slots()
		get_viewport().set_input_as_handled()
