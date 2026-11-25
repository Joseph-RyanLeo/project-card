class_name DeveloperConsole
extends Panel

signal command_submitted(command: String)

const PANEL_SIZE := Vector2(1080.0, 610.0) # 开发面板在 1280×720 画布中的宽高
const INSET := 20.0 # 面板内容与边框的距离
const COLUMN_WIDTH := 320.0 # 左侧检索结果的宽度
const ROW_GAP := 10 # 表单行与按钮之间的距离
const CARD_PREVIEW_SCALE := 2.0 # 右侧示例的卡面倍率
const CARD_PREVIEW := preload("res://scenes/ui/CardView.tscn")
const SPELL_LIGHT_TRAY := preload("res://scripts/ui/spell_preparation_tray.gd")
const SPELL_LIGHT_SAMPLE_CARDS: Array[CardData] = [
	preload("res://resources/cards/side_by_side.tres"),
	preload("res://resources/cards/battle_fury.tres"),
	preload("res://resources/cards/volley_order.tres"),
]

var host: Control
var _tabs: TabContainer
var _tasks: OptionButton
var _start_task_test: Button
var _stop_task_test: Button
var _task_test_state: Label
var _output: RichTextLabel
var _command_input: LineEdit
var _event_query: LineEdit
var _events: ItemList
var _event_details: RichTextLabel
var _event_state: Label
var _event_help: Label
var _deal: Button
var _retry: Button
var _stop: Button
var _dice_option: OptionButton
var _dice_point: OptionButton
var _data_kind: OptionButton
var _data_query: LineEdit
var _data_items: ItemList
var _data_catalog: Array[Dictionary] = []
var _data_scope: Label
var _gold: LineEdit
var _card_options: VBoxContainer
var _count: SpinBox
var _surface: OptionButton
var _art: OptionButton
var _add: Button
var _enemy_resource: Button
var _card_preview_column: VBoxContainer
var _card_preview_caption: Label
var _card_preview_stage: Control
var _card_preview: InspectionCardSurface
var _spell_light_tab: int
var _spell_light_controls: Dictionary[String, HSlider] = {}
var _spell_light_tray: Control
var _spell_light_column: OptionButton
var _spell_light_add: Button
var _spell_light_remove: Button
var _spell_light_release: Button
var _spell_light_count: Label
var _spell_light_samples: Array[OwnedCard] = []
var _spell_light_next_id := 0
var _feedback: Label


func _ready() -> void:
	position = (Vector2(1280, 720) - PANEL_SIZE) * 0.5
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("211d21")
	style.border_color = Color("d1aa58")
	style.set_border_width_all(2)
	add_theme_stylebox_override("panel", style)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, INSET)
	layout.add_theme_constant_override("separation", ROW_GAP)
	add_child(layout)
	var heading := _row(layout)
	var title := _label(heading, "开发面板")
	title.add_theme_font_size_override("font_size", 24) # 开发面板主标题字号
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(heading, "关闭 · F2", set_open.bind(false))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_tabs)
	_build_events()
	_build_data()
	_build_commands()
	_build_spell_light()
	_build_tasks()
	_tabs.tab_changed.connect(_focus_page)
	_feedback = _label(layout, "")
	_feedback.custom_minimum_size.y = 38 # 容纳最多两行操作结果
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.add_theme_color_override("font_color", Color("e7ca96"))
	append_output("输入 help 查看命令。")


func set_open(value: bool) -> void:
	visible = value
	if not value or _tabs == null: return
	_refresh_events()
	_refresh_data()
	_refresh_task_tests()
	_data_scope.text = "正在编辑测试副本" if host._developer_event_test.is_active() else "正在编辑当前对局"
	_gold.text = str(host.run_reward_state.gold)
	_focus_page(_tabs.current_tab)


func open_spell_light_preview() -> void:
	_tabs.current_tab = _spell_light_tab
	set_open(true)


func open_task_replay() -> void:
	_tabs.current_tab = _tabs.get_tab_count() - 1
	set_open(true)
	_tasks.grab_focus()


func _focus_page(index: int) -> void:
	if index == _spell_light_tab:
		_spell_light_column.grab_focus()
		return
	match index:
		0: _event_query.grab_focus()
		1:
			_data_query.grab_focus()
			_refresh_card_preview()
		2: _command_input.grab_focus()


func _page(title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = title
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14) # 分页内容外边距
	_tabs.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", ROW_GAP)
	margin.add_child(layout)
	return layout


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_GAP)
	parent.add_child(row)
	return row


func _column(parent: Control, width: float = 0.0) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = width
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", ROW_GAP)
	parent.add_child(column)
	return column


func _label(parent: Control, value: String) -> Label:
	var label := Label.new()
	label.text = value
	parent.add_child(label)
	return label


func _field(parent: Control, hint: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = hint
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field


func _list(parent: Control) -> ItemList:
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(list)
	return list


func _button(parent: Control, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 34 # 统一可点击按钮的最小高度
	var colors := {"normal": Color("30282b"), "hover": Color("49382e"), "pressed": Color("584335"), "disabled": Color("252224")}
	for state: String in colors:
		var style := StyleBoxFlat.new()
		style.bg_color = colors[state]
		style.border_color = Color("65503d") if state != "disabled" else Color("3c3435")
		style.set_border_width_all(1)
		style.content_margin_left = 10 # 按钮文字左右留白
		style.content_margin_right = 10
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _options(parent: Control, values: Array = []) -> OptionButton:
	var choice := OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.fit_to_longest_item = false
	choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for value: String in values: choice.add_item(value)
	parent.add_child(choice)
	return choice


func _build_events() -> void:
	var page := _page("事件测试")
	var content := _row(page)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var picker := _column(content, COLUMN_WIDTH)
	_event_query = _field(picker, "按事件名或 ID 搜索")
	_event_query.text_changed.connect(func(_value: String): _refresh_events())
	_events = _list(picker)
	_events.item_selected.connect(func(_index: int): _refresh_event_controls())
	_events.item_activated.connect(func(_index: int): _start_event())
	var details := _column(content, COLUMN_WIDTH)
	_label(details, "事件内容")
	_event_details = RichTextLabel.new()
	_event_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_event_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_event_details)
	var actions := _column(content)
	var event_debug := CheckButton.new()
	event_debug.name = "ShowEventDebugDetails"
	event_debug.text = "显示事件精确概率、条件和隐藏项"
	event_debug.toggled.connect(func(enabled: bool):
		if host.maze_controller != null: host.maze_controller.set_event_debug_details(enabled))
	actions.add_child(event_debug)
	_event_state = _label(actions, "")
	_event_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_deal = _button(actions, "发出所选事件牌", _start_event)
	_event_help = _label(actions, "")
	_event_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(actions, "指定骰点")
	_dice_option = _options(actions)
	_dice_option.item_selected.connect(func(_index: int): _refresh_dice_points())
	_dice_point = _options(actions)
	_dice_point.item_selected.connect(_set_test_roll)
	_retry = _button(actions, "回到点选项前", func(): _finish_event_action(host._developer_event_test.retry(), "已恢复点选项前的状态。"))
	_stop = _button(actions, "退出测试并恢复原局", func(): _finish_event_action(host._developer_event_test.stop(), "已恢复测试前的对局。"))


func _refresh_events() -> void:
	var old: Variant = _selected_value(_events)
	var items: Array[Dictionary] = []
	if host.maze_controller != null:
		for entry: Dictionary in host.maze_controller.developer_event_catalog():
			var name_text := String(entry.get("name", entry.hint))
			items.append({"label": "%s  ·  %s" % [name_text, entry.path_id], "name": name_text, "id": entry.path_id, "value": entry})
	_fill_list(_events, items, _event_query.text, old)
	_refresh_event_controls()


func _refresh_event_controls() -> void:
	var session: RefCounted = host._developer_event_test
	var active: bool = session.is_active()
	var selected: Variant = _selected_value(_events)
	var maze: ShortMazeController = host.maze_controller
	_event_details.text = maze.developer_event_details(selected) if maze != null and selected is Dictionary else "没有匹配的事件。"
	_event_details.scroll_to_line(0)
	var blocked := maze.developer_event_test_blocker(selected) if maze != null and selected is Dictionary else ""
	_deal.disabled = active or selected == null or not blocked.is_empty()
	_retry.disabled = not session.can_retry()
	_stop.disabled = not active
	_event_help.text = blocked if not active and not blocked.is_empty() else "翻牌时自动记录重试点。要加金币或道具，可以在启动测试后打开「局内调整」。"
	var current: Dictionary = maze.run.selected_path if maze != null else {}
	_event_state.text = "测试中 · %s" % session.event_id if active else (String(selected.get("name", selected.hint)) if selected != null else "选择要测试的事件")
	if not session.task_id.is_empty(): _event_state.text = "任务重玩进行中"
	if active and current.get("path_id") == session.event_id:
		_event_state.text = "测试中 · %s" % current.get("name", session.event_id)
	_dice_option.clear()
	if active and current.get("path_id") == session.event_id and current.get("reward") == "story" and not current.has("story_result"):
		for index: int in current.options.size():
			var option := maze.story_events.runtime_option(current, index)
			if not option.has("roll_sides"): continue
			_dice_option.add_item(String(option.label), index)
			var item := _dice_option.item_count - 1
			_dice_option.set_item_metadata(item, int(option.get("roll_max", option.roll_sides)))
			if session.forced_option == index: _dice_option.select(item)
	_dice_option.disabled = _dice_option.item_count == 0
	if _dice_option.disabled: _dice_option.add_item("翻开有骰子的事件后可设置")
	_refresh_dice_points()


func _refresh_dice_points() -> void:
	_dice_point.clear()
	_dice_point.add_item("随机点数", 0)
	_dice_point.disabled = _dice_option.disabled
	if _dice_point.disabled: return
	var limit := int(_dice_option.get_selected_metadata())
	for point: int in range(1, limit + 1): _dice_point.add_item("%d 点" % point, point)
	var session: RefCounted = host._developer_event_test
	if session.forced_option == _dice_option.get_selected_id(): _dice_point.select(session.forced_roll)


func _set_test_roll(_index: int) -> void:
	var session: RefCounted = host._developer_event_test
	session.forced_option = _dice_option.get_selected_id()
	session.forced_roll = _dice_point.get_selected_id()
	_feedback.text = "已为此选项指定 %d 点。" % session.forced_roll if session.forced_roll > 0 else "此选项使用随机点数。"


func _start_event() -> void:
	if _deal.disabled: return
	var selected := _selected_value(_events) as Dictionary
	_finish_event_action(host._developer_event_test.start(selected), "事件牌已发出，点击牌堆开始测试。")


func _build_tasks() -> void:
	var page := _page("任务重玩")
	_label(page, "选择已接入的任务，从开局开始重玩。")
	_tasks = _options(page)
	for task: Dictionary in TaskCatalog.all().values():
		if not task.implemented: continue
		_tasks.add_item("%s · %s" % [task.code, task.source["名称"]])
		_tasks.set_item_metadata(_tasks.item_count - 1, task.id)
	_task_test_state = _label(page, "")
	_start_task_test = _button(page, "开始测试", func():
		_finish_event_action(host._developer_event_test.start_task(String(_tasks.get_selected_metadata())), "已开启独立任务测试。"))
	_stop_task_test = _button(page, "退出测试并恢复原局", func():
		_finish_event_action(host._developer_event_test.stop(), "已恢复测试前的对局。"))


func _refresh_task_tests() -> void:
	var session: RefCounted = host._developer_event_test
	_start_task_test.disabled = session.is_active() or host.maze_controller == null or host.current_phase == host.GamePhase.BATTLE
	_stop_task_test.disabled = not session.is_active()
	_task_test_state.text = "测试中 · " + String(TaskCatalog.get_task(session.task_id).get("source", {}).get("名称", session.task_id)) if not session.task_id.is_empty() else "测试进度与奖励仅保存到测试副本。"


func _finish_event_action(error: String, success: String) -> void:
	_feedback.text = success if error.is_empty() else error
	if error.is_empty(): set_open(false)
	else:
		_refresh_event_controls()
		_refresh_task_tests()


func _build_data() -> void:
	var page := _page("局内调整")
	_data_scope = _label(page, "")
	_data_scope.add_theme_color_override("font_color", Color("e7ca96"))
	var gold_row := _row(page)
	_label(gold_row, "当前局金币")
	_gold = _field(gold_row, "输入目标余额")
	var apply_gold := _button(gold_row, "应用金币", _apply_gold)
	apply_gold.name = "ApplyGold"
	_gold.text_submitted.connect(func(_value: String): _apply_gold())
	var content := _row(page)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var picker := _column(content, COLUMN_WIDTH)
	_data_kind = _options(picker, ["卡牌", "贴纸", "伤势"])
	_data_kind.item_selected.connect(func(_index: int): _refresh_data())
	_data_query = _field(picker, "按名称或 ID 搜索")
	_data_query.text_changed.connect(func(_value: String): _filter_data())
	_data_items = _list(picker)
	_data_items.item_selected.connect(func(_index: int): _refresh_data_controls())
	var actions := _column(content)
	_card_options = _column(actions)
	_card_options.size_flags_vertical = Control.SIZE_FILL
	var count_row := _row(_card_options)
	_label(count_row, "数量")
	_count = SpinBox.new()
	_count.min_value = 1
	_count.max_value = 100
	_count.value = 1
	count_row.add_child(_count)
	var surface_row := _row(_card_options)
	_label(surface_row, "卡面工艺")
	_surface = _options(surface_row, CardAppearance.SURFACE_LABELS)
	_surface.item_selected.connect(func(_index: int): _refresh_card_preview())
	var art_row := _row(_card_options)
	_label(art_row, "卡图外观")
	_art = _options(art_row, CardAppearance.ART_LABELS)
	_art.item_selected.connect(func(_index: int): _refresh_card_preview())
	_add = _button(actions, "加入收藏", _add_selected)
	_enemy_resource = _button(actions, "部署到敌方资源板", _deploy_selected_resource)
	_card_preview_column = _column(content, COLUMN_WIDTH)
	_card_preview_caption = _label(_card_preview_column, "")
	_card_preview_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_preview_stage = Control.new()
	_card_preview_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_preview_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_preview_column.add_child(_card_preview_stage)
	_card_preview_stage.resized.connect(_center_card_preview)


func _refresh_data() -> void:
	_data_catalog.clear()
	if _data_kind.selected == 0:
		for card: CardData in host._build_card_definition_registry().values():
			_data_catalog.append({"label": "%s  ·  %s" % [card.display_name, card.id], "name": card.display_name, "id": card.id, "value": card})
	else:
		var kind := "wound" if _data_kind.selected == 2 else "emblem"
		for entry: Dictionary in host.emblem_library.get_definitions():
			if entry.get("status_kind", "emblem") == kind:
				var name_text := String(entry.get("name", entry.id))
				_data_catalog.append({"label": name_text, "name": name_text, "id": entry.id, "value": entry})
	_filter_data()


func _filter_data() -> void:
	_fill_list(_data_items, _data_catalog, _data_query.text, _selected_value(_data_items))
	_refresh_data_controls()


func _apply_gold() -> void:
	_feedback.text = host._set_developer_gold(_gold.text)


func _refresh_data_controls() -> void:
	var selected: Variant = _selected_value(_data_items)
	_card_options.visible = _data_kind.selected == 0
	_add.text = "加入收藏" if _card_options.visible else "加入工具箱"
	_add.disabled = selected == null
	_enemy_resource.visible = selected is CardData and selected.card_type == CardData.CardType.RESOURCE
	_refresh_card_preview()


func _refresh_card_preview() -> void:
	_card_preview_column.visible = _data_kind.selected == 0
	if not _card_preview_column.visible or not visible or _tabs.current_tab != 1: return
	var definition := _selected_value(_data_items) as CardData
	if definition == null:
		if is_instance_valid(_card_preview): _card_preview.hide()
		_card_preview_caption.text = "没有可预览的卡牌。"
		return
	var surface := _surface.selected as CardAppearance.Surface
	var art := _art.selected as CardAppearance.Art
	_card_preview_caption.text = "卡面示例 · %s\n%s／%s（移动鼠标看工艺）" % [definition.display_name, CardAppearance.SURFACE_LABELS[surface], CardAppearance.ART_LABELS[art]]
	var owned := _card_preview.card.get_owned_card() if is_instance_valid(_card_preview) else null
	if owned == null or owned.card_data != definition:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		owned = OwnedCard.new()
		owned.initialize(definition, &"developer_card_preview", 0, rng)
	owned.surface_finish = surface
	owned.art_finish = art
	if not is_instance_valid(_card_preview):
		var card := CARD_PREVIEW.instantiate() as CardView
		card.set_card_data(definition)
		card.set_owned_card(owned)
		card.set_snapshot_mode(true)
		_card_preview_stage.add_child(card)
		_card_preview = InspectionCardSurface.new()
		_card_preview_stage.add_child(_card_preview)
		_card_preview.scale = Vector2.ONE * CARD_PREVIEW_SCALE
		_card_preview.setup(card, Callable(), Callable())
		_card_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_preview.viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		_card_preview.visibility_changed.connect(func(): _card_preview.set_process(_card_preview.is_visible_in_tree()))
		_center_card_preview()
	else:
		if _card_preview.card.card_data != definition: _card_preview.card.set_card_data(definition)
		_card_preview.card.set_owned_card(owned)
		_card_preview.show()


func _center_card_preview() -> void:
	if is_instance_valid(_card_preview):
		_card_preview.position = ((_card_preview_stage.size - _card_preview.size * CARD_PREVIEW_SCALE) * 0.5).round()


func _add_selected() -> void:
	var selected: Variant = _selected_value(_data_items)
	if selected is CardData:
		_feedback.text = host._add_developer_cards(selected, int(_count.value), _surface.selected as CardAppearance.Surface, _art.selected as CardAppearance.Art)
	elif selected is Dictionary:
		_feedback.text = host._add_developer_wound(selected) if _data_kind.selected == 2 else host._add_developer_sticker(selected)


func _deploy_selected_resource() -> void:
	var definition := _selected_value(_data_items) as CardData
	if definition != null: _feedback.text = host._add_enemy_test_resource(definition)


func _fill_list(list: ItemList, items: Array[Dictionary], query: String, previous: Variant) -> void:
	list.clear()
	var keyword := query.strip_edges().to_lower()
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.label < b.label)
	var selection := -1
	var exact_match := 0
	for item: Dictionary in items:
		var name_text := String(item.name).to_lower()
		var id := String(item.id).to_lower()
		if not keyword.is_empty() and keyword not in name_text and keyword not in id: continue
		var index := list.add_item(item.label)
		list.set_item_metadata(index, item.value)
		if typeof(item.value) == typeof(previous) and item.value == previous: selection = index
		if keyword == name_text or keyword == id: exact_match = index
	if list.item_count > 0: list.select(selection if selection >= 0 else exact_match)


func _selected_value(list: ItemList) -> Variant:
	var indices := list.get_selected_items()
	return null if indices.is_empty() else list.get_item_metadata(indices[0])


func _build_commands() -> void:
	var layout := _page("命令")
	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_output)
	_command_input = _field(layout, "输入 help 查看命令")
	_command_input.text_submitted.connect(_on_command_submitted)
	_command_input.gui_input.connect(_on_input_gui_event)


func _build_spell_light() -> void:
	_spell_light_tab = _tabs.get_tab_count()
	var page := _page("法术光效")
	var content := _row(page)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var parameters := _column(content, 450)
	var hint := _label(parameters, "幅度按首枚令牌计算，后续每多一枚的增幅逐渐减小。")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var settings := host.spell_header_light_settings as SpellHeaderLightSettings
	for field: Dictionary in SpellHeaderLightSettings.FIELDS:
		var row := _row(parameters)
		var title := _label(row, field.label)
		title.custom_minimum_size.x = 146 # 保证四个参数名称与滑条对齐
		var slider := HSlider.new()
		slider.name = field.key
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.min_value = field.min
		slider.max_value = field.max
		slider.step = field.step
		slider.tooltip_text = "默认 %s %s" % [field.default, field.unit]
		row.add_child(slider)
		var spin := SpinBox.new()
		spin.custom_minimum_size.x = 106 # 数值栏需容纳小数、单位与步进按钮
		spin.suffix = field.unit
		spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(spin)
		slider.share(spin)
		slider.value_changed.connect(settings.set_value.bind(String(field.key)))
		_spell_light_controls[field.key] = slider
	settings.changed.connect(_sync_spell_light_controls)
	_sync_spell_light_controls()
	var saves := _row(parameters)
	_button(saves, "保存参数", _save_spell_light_settings)
	_button(saves, "恢复默认", _reset_spell_light_settings)

	var preview := _column(content, 450)
	var stage := Panel.new()
	stage.custom_minimum_size.y = SPELL_LIGHT_TRAY.TRAY_SIZE.y
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color("171517")
	stage.add_theme_stylebox_override("panel", backdrop)
	preview.add_child(stage)
	_spell_light_tray = SPELL_LIGHT_TRAY.new()
	_spell_light_tray.header_light_settings = settings
	_spell_light_tray.z_index = 1 # 托盘自身的底图在 -1 层，提升后仍显示在预览底色上
	_spell_light_tray.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	stage.add_child(_spell_light_tray)
	_spell_light_tray.set_drop_enabled(false)
	_spell_light_tray.set_process(false)
	stage.resized.connect(func(): _spell_light_tray.position = ((stage.size - SPELL_LIGHT_TRAY.TRAY_SIZE) * 0.5).round())

	var actions := _row(preview)
	_spell_light_column = _options(actions, SPELL_LIGHT_TRAY.COLUMN_NAMES)
	_spell_light_column.item_selected.connect(func(_index: int) -> void: _refresh_spell_light_preview())
	_spell_light_add = _button(actions, "放入令牌", _change_spell_light_preview.bind(1, false))
	_spell_light_remove = _button(actions, "移走令牌", _change_spell_light_preview.bind(-1, false))
	_spell_light_release = _button(actions, "释放一枚", _change_spell_light_preview.bind(-1, true))
	_spell_light_count = _label(preview, "")
	for column: int in SPELL_LIGHT_SAMPLE_CARDS.size():
		for index: int in column + 1:
			_add_spell_light_sample(column)
	_refresh_spell_light_preview()


func _sync_spell_light_controls() -> void:
	var settings := host.spell_header_light_settings as SpellHeaderLightSettings
	for key: String in _spell_light_controls:
		_spell_light_controls[key].value = settings.get_value(key)


func _save_spell_light_settings() -> void:
	var error: Error = host.spell_header_light_settings.save()
	_feedback.text = "已保存法术光效参数，下次启动时继续使用。" if error == OK else "法术光效参数保存失败（%s）。" % error_string(error)


func _reset_spell_light_settings() -> void:
	host.spell_header_light_settings.reset_defaults()
	_feedback.text = "当前已使用默认值，点击保存参数可记住这次调整。"


func _add_spell_light_sample(column: int) -> void:
	_spell_light_next_id += 1
	var sample := OwnedCard.new()
	sample.initialize(SPELL_LIGHT_SAMPLE_CARDS[column], StringName("spell_light_preview_%d" % _spell_light_next_id), _spell_light_next_id)
	_spell_light_samples.append(sample)


func _change_spell_light_preview(delta: int, release: bool) -> void:
	var column := _spell_light_column.selected
	if delta > 0:
		_add_spell_light_sample(column)
	else:
		for index: int in range(_spell_light_samples.size() - 1, -1, -1):
			var sample := _spell_light_samples[index]
			if sample.card_data.get_spell_preparation_column() != column:
				continue
			if release:
				_spell_light_tray.play_spell_release(sample.instance_id, BattleController.OPENING_SPELL_PRESENTATION_SECONDS)
			_spell_light_samples.remove_at(index)
			break
	_refresh_spell_light_preview()


func _refresh_spell_light_preview() -> void:
	_spell_light_tray.set_prepared_cards(_spell_light_samples)
	var counts: Array[int] = [0, 0, 0]
	for sample: OwnedCard in _spell_light_samples:
		counts[sample.card_data.get_spell_preparation_column()] += 1
	_spell_light_count.text = "即时 %d　　条件 %d　　准备 %d" % counts
	_spell_light_add.disabled = _spell_light_samples.size() >= host.spell_preparation_capacity
	_spell_light_remove.disabled = counts[_spell_light_column.selected] == 0
	_spell_light_release.disabled = _spell_light_remove.disabled


func append_output(message: String, show_from_start: bool = false) -> void:
	if not is_instance_valid(_output): return
	var first_line := maxi(0, _output.get_line_count() - 1)
	_output.add_text(message + "\n")
	_output.scroll_to_line(first_line if show_from_start else maxi(0, _output.get_line_count() - 1))


func _on_command_submitted(command: String) -> void:
	var trimmed := command.strip_edges()
	if trimmed.is_empty(): return
	append_output("> " + trimmed)
	command_submitted.emit(trimmed)
	_command_input.clear()


func _on_input_gui_event(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		set_open(false)
