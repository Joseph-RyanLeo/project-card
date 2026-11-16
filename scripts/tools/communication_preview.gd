extends Control

## F6独立预览两种展示组件，不连接玩家存档。
const Style = preload("res://scripts/ui/menu_style.gd")
const Hint = preload("res://scripts/ui/task_hint_overlay.gd")
const Toast = preload("res://scripts/ui/gameplay_teaching_toast.gd")
var _toast: Control
var _menu: Control
var _dialog: Control

func _ready() -> void:
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	theme = Style.make_theme()
	Style.add_background(self)
	var body := VBoxContainer.new()
	body.position = Vector2(440, 240) # 预览操作区的位置
	body.add_theme_constant_override("separation", 18) # 预览按钮之间的间距
	add_child(body)
	var title := Label.new()
	title.text = "角色对白与玩法教学预览"
	body.add_child(title)
	Style.button(body, "播放场外角色对白", "PlayDialogue", _play_dialogue)
	Style.button(body, "显示玩法教学提示", "ShowTeaching", _show_teaching)
	var note := Label.new()
	note.text = "点击教学提示条可打开对应条目。Esc打开或关闭菜单。"
	note.add_theme_font_size_override("font_size", 15) # 预览操作说明字号
	body.add_child(note)
	_toast = Toast.new()
	add_child(_toast)
	_toast.entry_requested.connect(_open_teaching)
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 4000 # 预览暂停菜单高于角色头像
	add_child(menu_layer)
	_menu = preload("res://scripts/ui/escape_pause_menu.gd").new()
	_menu.teaching_entries_provider = TaskCatalog.teaching_entries
	_menu.escape_pressed.connect(_toggle_menu)
	_menu.return_requested.connect(_close_menu)
	menu_layer.add_child(_menu)

func _play_dialogue() -> void:
	if is_instance_valid(_dialog): return
	_dialog = Hint.new()
	_dialog.content = {
		"dialogue": [
			{"speaker": "后勤机器人", "text": "补给已经送到，祝你一路顺利！", "portrait": preload("res://assets/card_art/ironwall_inscription/logistics_robot.png")},
			{"speaker": "玛格丽特", "text": "拿好工具，咱们出发。", "portrait": preload("res://assets/card_art/anvil_margaret.png")},
		],
		"instruction": "",
		"dim": false,
	}
	_dialog.confirmed.connect(_dialog.dismiss)
	add_child(_dialog)

func _show_teaching() -> void:
	var key := "tutorial:step:rune_basics"
	_toast.notify(key, TaskCatalog.teaching_hint(key).title)

func _open_teaching(key: String) -> void:
	_menu.open_teaching(key)
	get_tree().paused = true

func _toggle_menu() -> void:
	if _menu.is_menu_open():
		if not _menu.close_subpage(): _close_menu()
	else:
		_menu.open_menu()
		get_tree().paused = true

func _close_menu() -> void:
	_menu.close_menu()
	get_tree().paused = false
