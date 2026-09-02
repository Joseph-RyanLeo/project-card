class_name BattleLab
extends Control

## 可视化战斗实验室：编辑测试输入、驱动正式控制器、观察分层事件，
## 并把同一份场景用于保存、自动断言和批量组合回归。

signal close_requested

const BattleLabScenario = preload("res://scripts/tools/battle_lab_scenario.gd")
const BattleController = preload("res://scripts/battle/battle_controller.gd")
const BattleLogEntry = preload("res://scripts/battle/battle_log_entry.gd")
const BattleFormulaPresenter = preload("res://scripts/battle/battle_formula_presenter.gd")
const BOARD_SLOT_SCENE: PackedScene = preload("res://scenes/ui/BoardSlot.tscn")
const BATTLE_LOG_FONT: Font = preload("res://assets/fonts/chill_7.ttf")
const SCENARIO_SAVE_PATH := "user://battle_lab_scenario.json"
const ACTION_NAMES: Array[String] = ["近战", "远程", "法术", "治疗", "防御"]
const ELEMENT_NAMES: Array[String] = ["火", "水", "木", "光", "暗"]
const PRESET_IDS: Array[StringName] = [&"light_water", &"wood_fire", &"fire_heal", &"water_boundary", &"light_targets"]
const PRESET_NAMES: Array[String] = ["3光＋2水", "2木＋2火", "五火治疗", "五水边界", "五光目标不足"]
const SPEED_VALUES: Array[float] = [1.0, 2.0, 3.0] # 实验室连续播放可选择的战斗时间倍率
const SIDE_PANEL_WIDTH: float = 278.0 # 敌我配置栏各自占用的固定宽度
const CARD_PREVIEW_SCALE: float = 0.50 # 正式卡面缩放到实验室四排都能同时观察、文字仍较易辨认的比例
const CARD_PREVIEW_CONTENT_HEIGHT: float = 150.0 # 含 136 像素卡面与牌型标签的正式小队视觉高度
const FORMULA_POPUP_MIN_WIDTH: float = 210.0 # 实验室公式弹窗的最小阅读宽度
const FORMULA_POPUP_MAX_WIDTH: float = 340.0 # 实验室公式弹窗允许的最大内容宽度
const FORMULA_POPUP_MAX_HEIGHT: float = 300.0 # 实验室公式弹窗允许的最大内容高度
const FORMULA_POPUP_CONTENT_PADDING := Vector2(18.0, 18.0) # 弹窗两侧各 9 像素内边距的合计尺寸
const FORMULA_POPUP_MOUSE_GAP: float = 10.0 # 公式弹窗与鼠标之间的垂直间距

var scenario: BattleLabScenario
var battle_controller: BattleController
var _side_controls: Dictionary = {}
var _selected_slot: Dictionary = {"player": 0, "enemy": 0}
var _loading_editor: bool = false
var _playing: bool = false
var _paused: bool = true
var _speed_index: int = 0
var _log_entries: Array[BattleLogEntry] = []
var _log_by_group: Dictionary = {}
var _trace_lines: Array[String] = []

var scenario_name_edit: LineEdit
var preset_option: OptionButton
var seed_spin: SpinBox
var max_batches_spin: SpinBox
var expected_option: OptionButton
var speed_button: Button
var pause_button: Button
var status_label: Label
var validation_label: Label
var battle_log_text: RichTextLabel
var trace_text: RichTextLabel
var report_text: RichTextLabel
var state_rows: Dictionary = {}
var formula_popup: PanelContainer
var formula_popup_text: RichTextLabel


func _ready() -> void:
	var lab_theme := Theme.new()
	lab_theme.default_font = BATTLE_LOG_FONT
	lab_theme.default_font_size = 14
	theme = lab_theme
	_build_interface()
	battle_controller = BattleController.new() as BattleController
	battle_controller.name = "BattleLabController"
	add_child(battle_controller)
	battle_controller.states_changed.connect(_on_states_changed)
	battle_controller.effect_resolved.connect(_on_effect_resolved)
	battle_controller.battle_finished.connect(_on_battle_finished)
	scenario = BattleLabScenario.create_default()
	_load_scenario_into_controls()
	set_process(true)


func _process(delta: float) -> void:
	if _playing and not _paused and battle_controller.is_running():
		battle_controller.advance_time(delta * SPEED_VALUES[_speed_index])
		_refresh_status()


func _exit_tree() -> void:
	if is_instance_valid(battle_controller):
		battle_controller.clear_battle()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("10161d")
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	var root_layout := VBoxContainer.new()
	root_layout.add_theme_constant_override("separation", 8)
	margin.add_child(root_layout)
	root_layout.add_child(_build_top_bar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	body.add_child(_build_side_editor("player", "我方阵容"))
	body.add_child(_build_battle_observer())
	body.add_child(_build_side_editor("enemy", "敌方阵容"))
	root_layout.add_child(body)
	root_layout.add_child(_build_output_tabs())
	_build_formula_popup()


func _build_top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size.y = 38.0
	bar.add_theme_constant_override("separation", 7)
	var back := Button.new()
	back.text = "← 返回主界面"
	back.custom_minimum_size.x = 132.0
	back.pressed.connect(func() -> void: close_requested.emit())
	bar.add_child(back)
	var title := Label.new()
	title.text = "战斗实验室"
	title.add_theme_font_size_override("font_size", 22)
	title.custom_minimum_size.x = 132.0
	bar.add_child(title)
	scenario_name_edit = LineEdit.new()
	scenario_name_edit.placeholder_text = "场景名称"
	scenario_name_edit.custom_minimum_size.x = 165.0
	bar.add_child(scenario_name_edit)
	preset_option = OptionButton.new()
	preset_option.custom_minimum_size.x = 132.0
	for index: int in PRESET_NAMES.size():
		preset_option.add_item(PRESET_NAMES[index], index)
	bar.add_child(preset_option)
	var apply_preset := Button.new()
	apply_preset.text = "应用预设"
	apply_preset.pressed.connect(_on_apply_preset_pressed)
	bar.add_child(apply_preset)
	var save_button := Button.new()
	save_button.text = "保存配置"
	save_button.pressed.connect(_save_scenario)
	bar.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "载入配置"
	load_button.pressed.connect(_load_saved_scenario)
	bar.add_child(load_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	return bar


func _build_side_editor(side_key: String, title_text: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = SIDE_PANEL_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color("19232d")
	style.border_color = Color("425466")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(9.0)
	panel.add_theme_stylebox_override("panel", style)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 5)
	panel.add_child(layout)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)

	var slot_selector := OptionButton.new()
	for index: int in BattleLabScenario.SIDE_SLOT_COUNT:
		slot_selector.add_item("小队 %d" % (index + 1), index)
	layout.add_child(_labeled_row("编辑对象", slot_selector))
	var enabled := CheckBox.new()
	enabled.text = "启用该小队"
	layout.add_child(enabled)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "小队名称"
	layout.add_child(_labeled_row("名称", name_edit))

	var row_option := OptionButton.new()
	row_option.add_item("前排", 0)
	row_option.add_item("后排", 1)
	var position_spin := _make_spin(0.0, 3.0, 1.0)
	var row_line := HBoxContainer.new()
	row_line.add_child(_fixed_label("排与位置", 72.0))
	row_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_line.add_child(row_option)
	position_spin.custom_minimum_size.x = 64.0
	row_line.add_child(position_spin)
	layout.add_child(row_line)

	var action_option := OptionButton.new()
	for index: int in ACTION_NAMES.size():
		action_option.add_item(ACTION_NAMES[index], index)
	layout.add_child(_labeled_row("行动方式", action_option))
	var base_spin := _make_spin(0.0, 99.0, 1.0)
	var cooldown_spin := _make_spin(0.5, 9.9, 0.1)
	layout.add_child(_double_spin_row("基础", base_spin, "冷却", cooldown_spin))
	var health_spin := _make_spin(1.0, 999.0, 1.0)
	var armor_spin := _make_spin(0.0, 999.0, 1.0)
	layout.add_child(_double_spin_row("生命", health_spin, "护甲", armor_spin))

	var rune_caption := Label.new()
	rune_caption.text = "可见符文顺序（无会被压缩）"
	rune_caption.add_theme_color_override("font_color", Color("d9c878"))
	layout.add_child(rune_caption)
	var rune_row := HBoxContainer.new()
	rune_row.add_theme_constant_override("separation", 3)
	var rune_options: Array[OptionButton] = []
	for _index: int in BattleLabScenario.MAX_VISIBLE_RUNES:
		var option := OptionButton.new()
		option.add_item("无", 0)
		for element_index: int in ELEMENT_NAMES.size():
			option.add_item(ELEMENT_NAMES[element_index], element_index + 1)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rune_options.append(option)
		rune_row.add_child(option)
	layout.add_child(rune_row)
	var summary := Label.new()
	summary.text = "牌型：混乱"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_color_override("font_color", Color("9fd6ac"))
	layout.add_child(summary)

	_side_controls[side_key] = {
		"slot": slot_selector,
		"enabled": enabled,
		"name": name_edit,
		"row": row_option,
		"position": position_spin,
		"action": action_option,
		"base": base_spin,
		"cooldown": cooldown_spin,
		"health": health_spin,
		"armor": armor_spin,
		"runes": rune_options,
		"summary": summary,
	}
	slot_selector.item_selected.connect(_on_slot_selected.bind(side_key))
	enabled.toggled.connect(func(_value: bool) -> void: _on_editor_changed(side_key))
	name_edit.text_changed.connect(func(_value: String) -> void: _on_editor_changed(side_key))
	row_option.item_selected.connect(func(_value: int) -> void: _on_editor_changed(side_key))
	position_spin.value_changed.connect(func(_value: float) -> void: _on_editor_changed(side_key))
	action_option.item_selected.connect(func(_value: int) -> void: _on_editor_changed(side_key))
	for spin: SpinBox in [base_spin, cooldown_spin, health_spin, armor_spin]:
		spin.value_changed.connect(func(_value: float) -> void: _on_editor_changed(side_key))
	for option: OptionButton in rune_options:
		option.item_selected.connect(func(_value: int) -> void: _on_editor_changed(side_key))
	return panel


func _build_battle_observer() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111a22")
	style.border_color = Color("695d37")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override("panel", style)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 5)
	panel.add_child(layout)

	var setup_row := HBoxContainer.new()
	seed_spin = _make_spin(0.0, 999999999.0, 1.0)
	seed_spin.custom_minimum_size.x = 118.0
	max_batches_spin = _make_spin(1.0, 999.0, 1.0)
	max_batches_spin.custom_minimum_size.x = 72.0
	expected_option = OptionButton.new()
	expected_option.add_item("任意结果", 0)
	expected_option.add_item("预期我方胜利", BattleController.Result.PLAYER_VICTORY)
	expected_option.add_item("预期我方失败", BattleController.Result.PLAYER_DEFEAT)
	expected_option.add_item("预期平局", BattleController.Result.DRAW)
	setup_row.add_child(_fixed_label("种子", 38.0))
	setup_row.add_child(seed_spin)
	setup_row.add_child(_fixed_label("批次上限", 64.0))
	setup_row.add_child(max_batches_spin)
	expected_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_row.add_child(expected_option)
	layout.add_child(setup_row)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 5)
	for button_data: Dictionary in [
		{"text": "开始", "call": _start_battle},
		{"text": "重置同种子", "call": _start_battle},
		{"text": "单步批次", "call": _step_batch},
	]:
		var button := Button.new()
		button.text = String(button_data["text"])
		button.pressed.connect(button_data["call"] as Callable)
		controls.add_child(button)
	pause_button = Button.new()
	pause_button.text = "暂停"
	pause_button.pressed.connect(_toggle_pause)
	controls.add_child(pause_button)
	speed_button = Button.new()
	speed_button.text = "速度 1×"
	speed_button.pressed.connect(_cycle_speed)
	controls.add_child(speed_button)
	var new_seed := Button.new()
	new_seed.text = "新种子"
	new_seed.pressed.connect(_use_new_seed)
	controls.add_child(new_seed)
	var assertion := Button.new()
	assertion.text = "运行并校验"
	assertion.pressed.connect(_run_assertion)
	controls.add_child(assertion)
	var matrix := Button.new()
	matrix.text = "批量组合"
	matrix.pressed.connect(_run_combination_matrix)
	controls.add_child(matrix)
	layout.add_child(controls)

	status_label = Label.new()
	status_label.text = "尚未开始"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	layout.add_child(status_label)
	validation_label = Label.new()
	validation_label.text = "配置就绪"
	validation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	validation_label.add_theme_color_override("font_color", Color("9fd6ac"))
	layout.add_child(validation_label)

	for row_key: String in ["enemy_back", "enemy_front", "player_front", "player_back"]:
		var row_panel := PanelContainer.new()
		row_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = Color("1a2833") if row_key.begins_with("enemy") else Color("1b2d2a")
		row_style.set_corner_radius_all(3)
		row_style.set_content_margin_all(4.0)
		row_panel.add_theme_stylebox_override("panel", row_style)
		var row_layout := HBoxContainer.new()
		row_layout.add_theme_constant_override("separation", 4)
		var caption := Label.new()
		caption.text = {"enemy_back": "敌后", "enemy_front": "敌前", "player_front": "我前", "player_back": "我后"}[row_key]
		caption.custom_minimum_size.x = 35.0
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row_layout.add_child(caption)
		var cards := HBoxContainer.new()
		cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards.add_theme_constant_override("separation", 4)
		cards.alignment = BoxContainer.ALIGNMENT_CENTER
		row_layout.add_child(cards)
		row_panel.add_child(row_layout)
		layout.add_child(row_panel)
		state_rows[row_key] = cards
	return panel


func _build_output_tabs() -> Control:
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.y = 205.0
	battle_log_text = _make_output_text("结构化日志")
	trace_text = _make_output_text("分层轨迹")
	report_text = _make_output_text("自动校验")
	tabs.add_child(battle_log_text)
	tabs.add_child(trace_text)
	tabs.add_child(report_text)
	battle_log_text.meta_hover_started.connect(_on_log_meta_hover_started)
	battle_log_text.meta_hover_ended.connect(_on_log_meta_hover_ended)
	return tabs


func _build_formula_popup() -> void:
	formula_popup = PanelContainer.new()
	formula_popup.name = "BattleLabFormulaPopup"
	formula_popup.visible = false
	formula_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	formula_popup.z_index = 4000
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.043, 0.98)
	style.border_color = Color(0.86, 0.73, 0.39, 0.95)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(9.0)
	formula_popup.add_theme_stylebox_override("panel", style)
	add_child(formula_popup)
	formula_popup_text = RichTextLabel.new()
	formula_popup_text.fit_content = false
	formula_popup_text.add_theme_font_override("normal_font", BATTLE_LOG_FONT)
	formula_popup_text.add_theme_font_size_override("normal_font_size", 12)
	formula_popup_text.add_theme_color_override("default_color", Color("e8eee5"))
	formula_popup.add_child(formula_popup_text)


func _load_scenario_into_controls() -> void:
	_loading_editor = true
	scenario_name_edit.text = scenario.scenario_name
	seed_spin.value = scenario.random_seed
	max_batches_spin.value = scenario.max_batches
	_speed_index = _closest_speed_index(scenario.speed_multiplier)
	speed_button.text = "速度 %d×" % int(SPEED_VALUES[_speed_index])
	expected_option.select(0)
	if scenario.expected_result >= 0:
		_select_option_by_id(expected_option, scenario.expected_result)
	for side_key: String in ["player", "enemy"]:
		_selected_slot[side_key] = 0
		var controls := _side_controls[side_key] as Dictionary
		(controls["slot"] as OptionButton).select(0)
	_loading_editor = false
	_load_editor("player")
	_load_editor("enemy")
	_validate_current_scenario()
	_refresh_state_view()


func _load_editor(side_key: String) -> void:
	var specs := _get_side_specs(side_key)
	var spec := specs[int(_selected_slot[side_key])]
	var controls := _side_controls[side_key] as Dictionary
	_loading_editor = true
	(controls["enabled"] as CheckBox).button_pressed = bool(spec.get("enabled", false))
	(controls["name"] as LineEdit).text = String(spec.get("name", "实验小队"))
	(controls["row"] as OptionButton).select(1 if String(spec.get("row", "front")) == "back" else 0)
	(controls["position"] as SpinBox).value = int(spec.get("position", 0))
	_select_option_by_id(controls["action"] as OptionButton, int(spec.get("action", CardData.ActionType.MELEE)))
	(controls["base"] as SpinBox).value = int(spec.get("base_value", 10))
	(controls["cooldown"] as SpinBox).value = float(spec.get("cooldown", 2.0))
	(controls["health"] as SpinBox).value = int(spec.get("health", 100))
	(controls["armor"] as SpinBox).value = int(spec.get("armor", 0))
	var runes: Array = spec.get("runes", []) as Array
	var rune_options := controls["runes"] as Array[OptionButton]
	for index: int in rune_options.size():
		var selected_id := int(runes[index]) + 1 if index < runes.size() else 0
		_select_option_by_id(rune_options[index], selected_id)
	_loading_editor = false
	_refresh_editor_summary(side_key)


func _commit_editor(side_key: String) -> void:
	if _loading_editor or scenario == null:
		return
	var controls := _side_controls[side_key] as Dictionary
	var runes: Array[int] = []
	for option: OptionButton in controls["runes"] as Array[OptionButton]:
		var element := option.get_selected_id() - 1
		if element >= 0:
			runes.append(element)
	var spec := {
		"enabled": (controls["enabled"] as CheckBox).button_pressed,
		"name": (controls["name"] as LineEdit).text,
		"row": "back" if (controls["row"] as OptionButton).selected == 1 else "front",
		"position": roundi((controls["position"] as SpinBox).value),
		"action": (controls["action"] as OptionButton).get_selected_id(),
		"base_value": roundi((controls["base"] as SpinBox).value),
		"cooldown": (controls["cooldown"] as SpinBox).value,
		"health": roundi((controls["health"] as SpinBox).value),
		"armor": roundi((controls["armor"] as SpinBox).value),
		"runes": runes,
	}
	_get_side_specs(side_key)[int(_selected_slot[side_key])] = spec


func _commit_global_controls() -> void:
	_commit_editor("player")
	_commit_editor("enemy")
	scenario.scenario_name = scenario_name_edit.text
	scenario.random_seed = roundi(seed_spin.value)
	scenario.speed_multiplier = SPEED_VALUES[_speed_index]
	scenario.max_batches = roundi(max_batches_spin.value)
	scenario.expected_result = -1 if expected_option.selected == 0 else expected_option.get_selected_id()


func _on_slot_selected(slot_index: int, side_key: String) -> void:
	if _loading_editor:
		return
	_commit_editor(side_key)
	_selected_slot[side_key] = slot_index
	_load_editor(side_key)


func _on_editor_changed(side_key: String) -> void:
	if _loading_editor:
		return
	_commit_editor(side_key)
	_refresh_editor_summary(side_key)
	_validate_current_scenario()
	_return_to_configuration_preview()


func _refresh_editor_summary(side_key: String) -> void:
	var controls := _side_controls[side_key] as Dictionary
	var spec := _get_side_specs(side_key)[int(_selected_slot[side_key])]
	var squad: SquadData = BattleLabScenario._build_squad(spec, "preview")
	var pattern := squad.get_rune_pattern_result()
	var rune_names: Array[String] = []
	for rune: CardData.ElementType in pattern.visible_runes:
		rune_names.append(ELEMENT_NAMES[rune])
	(controls["summary"] as Label).text = "牌型：%s　可见：%s　堆叠：%d 卡" % [pattern.get_pattern_name(), "".join(rune_names) if not rune_names.is_empty() else "无", squad.get_card_count()]


func _validate_current_scenario() -> bool:
	if scenario == null:
		return false
	var errors := scenario.validate()
	if errors.is_empty():
		validation_label.text = "配置就绪：正式规则可运行"
		validation_label.add_theme_color_override("font_color", Color("9fd6ac"))
		return true
	validation_label.text = "；".join(errors)
	validation_label.add_theme_color_override("font_color", Color("f19a8a"))
	return false


func _start_battle() -> void:
	_commit_global_controls()
	if not _validate_current_scenario():
		return
	_clear_outputs()
	battle_controller.start_battle(scenario.build_player_formation(), scenario.build_enemy_formation(), scenario.random_seed, false)
	_playing = true
	_paused = false
	pause_button.text = "暂停"
	_refresh_state_view()
	_refresh_status()


func _toggle_pause() -> void:
	if not _playing:
		_start_battle()
		return
	_paused = not _paused
	pause_button.text = "继续" if _paused else "暂停"
	_refresh_status()


func _step_batch() -> void:
	if not _playing or battle_controller.get_all_states().is_empty():
		_start_battle()
	_paused = true
	pause_button.text = "继续"
	if battle_controller.is_running():
		battle_controller.resolve_next_batch()
	_refresh_state_view()
	_refresh_status()


func _cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % SPEED_VALUES.size()
	speed_button.text = "速度 %d×" % int(SPEED_VALUES[_speed_index])
	if scenario != null:
		scenario.speed_multiplier = SPEED_VALUES[_speed_index]


func _use_new_seed() -> void:
	seed_spin.value = int(Time.get_ticks_usec() % 1000000000)
	if scenario != null:
		scenario.random_seed = roundi(seed_spin.value)


func _on_apply_preset_pressed() -> void:
	scenario = BattleLabScenario.create_preset(PRESET_IDS[preset_option.selected])
	_load_scenario_into_controls()
	_clear_outputs()
	status_label.text = "已应用预设：%s" % scenario.scenario_name


func _save_scenario() -> void:
	_commit_global_controls()
	var file := FileAccess.open(SCENARIO_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		validation_label.text = "保存失败：无法写入用户目录"
		return
	file.store_string(JSON.stringify(scenario.to_dictionary(), "\t"))
	validation_label.text = "已保存：%s" % SCENARIO_SAVE_PATH
	validation_label.add_theme_color_override("font_color", Color("9fd6ac"))


func _load_saved_scenario() -> void:
	if not FileAccess.file_exists(SCENARIO_SAVE_PATH):
		validation_label.text = "尚未保存过实验室配置"
		return
	var file := FileAccess.open(SCENARIO_SAVE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not (parsed is Dictionary):
		validation_label.text = "载入失败：配置文件格式无效"
		return
	scenario = BattleLabScenario.from_dictionary(parsed as Dictionary)
	_load_scenario_into_controls()
	_clear_outputs()
	validation_label.text = "已载入：%s" % scenario.scenario_name


func _on_states_changed() -> void:
	_refresh_state_view()
	_refresh_status()


func _on_effect_resolved(event: BattleEffectEvent) -> void:
	var entry := _log_by_group.get(event.group_id) as BattleLogEntry
	if entry == null:
		entry = BattleLogEntry.new()
		entry.group_id = event.group_id
		entry.timestamp = event.timestamp
		entry.source = event.source
		_log_by_group[event.group_id] = entry
		_log_entries.append(entry)
	entry.add_event(event)
	_trace_lines.append(_format_trace_line(event))
	_refresh_log_text()
	trace_text.text = "\n".join(_trace_lines)


func _on_battle_finished(_result: BattleController.Result) -> void:
	_playing = false
	_paused = true
	pause_button.text = "继续"
	_refresh_state_view()
	_refresh_status()


func _refresh_log_text() -> void:
	var lines: Array[String] = []
	for entry: BattleLogEntry in _log_entries:
		lines.append("[color=#7faec9][t=%s][/color] %s" % [BattleLogEntry.format_number(entry.timestamp), entry.to_bbcode()])
	battle_log_text.text = "\n".join(lines)


func _refresh_status() -> void:
	if battle_controller == null:
		return
	var result_name := _result_name(battle_controller.current_result)
	var play_state := "已暂停" if _paused and battle_controller.is_running() else ("播放中" if battle_controller.is_running() else "已结束")
	status_label.text = "%s　时间 %.2fs　批次 %d　种子 %d　结果 %s" % [play_state, battle_controller.elapsed_seconds, battle_controller.batch_count, scenario.random_seed if scenario != null else 0, result_name]


func _refresh_state_view() -> void:
	for row_value: Variant in state_rows.values():
		_clear_children(row_value as Control)
	if scenario == null:
		return
	if battle_controller != null and not battle_controller.get_all_states().is_empty():
		var live_by_row: Dictionary = {}
		for state: BattleSquadState in battle_controller.get_all_states():
			var row_key := String(state.row_key)
			if not live_by_row.has(row_key):
				live_by_row[row_key] = []
			(live_by_row[row_key] as Array).append(state)
		for row_key: String in live_by_row:
			var states := live_by_row[row_key] as Array
			states.sort_custom(func(left: BattleSquadState, right: BattleSquadState) -> bool: return left.formation_index < right.formation_index)
			for state: BattleSquadState in states:
				(state_rows[row_key] as HBoxContainer).add_child(_make_squad_visual(state.squad_data, state))
		return
	var preview_formations: Array[Dictionary] = []
	preview_formations.append_array(scenario.build_enemy_formation())
	preview_formations.append_array(scenario.build_player_formation())
	preview_formations.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_row := String(left["row_key"])
		var right_row := String(right["row_key"])
		return left_row < right_row if left_row != right_row else int(left["formation_index"]) < int(right["formation_index"])
	)
	for entry: Dictionary in preview_formations:
		var row_key := String(entry["row_key"])
		(state_rows[row_key] as HBoxContainer).add_child(_make_squad_visual(entry["squad_data"] as SquadData))


func _make_squad_visual(squad: SquadData, state: BattleSquadState = null) -> Control:
	var wrapper := Control.new()
	var visual_width := float(squad.get_display_width()) * CARD_PREVIEW_SCALE
	wrapper.custom_minimum_size = Vector2(visual_width, CARD_PREVIEW_CONTENT_HEIGHT * CARD_PREVIEW_SCALE)
	wrapper.set_meta("unscaled_squad_width", squad.get_display_width())
	var slot := BOARD_SLOT_SCENE.instantiate() as BoardSlot
	slot.name = "VirtualSquad"
	slot.scale = Vector2.ONE * CARD_PREVIEW_SCALE
	slot.set_squad_data(squad)
	wrapper.add_child(slot)
	if state == null:
		wrapper.tooltip_text = _format_configuration_tooltip(squad)
		return wrapper
	var continuous_count := 0
	for status: Dictionary in battle_controller.active_continuous_effects:
		if status.get("target") == state:
			continuous_count += 1
	wrapper.tooltip_text = _format_state_tooltip(state, continuous_count)
	if not state.alive:
		slot.modulate = Color(1.0, 0.42, 0.42, 0.62)
	slot.call_deferred("set_battle_status", state.displayed_health, state.displayed_armor, state.remaining_cooldown, state.get_buff_stacks(BattleRules.FATIGUE_BUFF_ID))
	return wrapper


func _format_configuration_tooltip(squad: SquadData) -> String:
	var action_source := squad.get_action_source()
	var vitals_source := squad.get_vitals_source()
	return "%s｜%s｜%d 卡｜实际宽度 %d\n基础 %d　冷却 %.1f　生命 %d　护甲 %d" % [action_source.display_name, ACTION_NAMES[action_source.action_type], squad.get_card_count(), squad.get_display_width(), action_source.base_value, action_source.cooldown_seconds, vitals_source.max_health, vitals_source.armor]


func _format_state_tooltip(state: BattleSquadState, continuous_count: int) -> String:
	var remainders := state.fractional_accumulators
	return "%s｜%s\n精确生命 %.2f/%d　护甲 %.2f　冷却 %.2f\n小数余量：伤 %.2f／破甲 %.2f／治疗 %.2f／加甲 %.2f\n持续状态 %d　Buff %s\n逻辑范围 %.1f～%.1f" % [state.get_action_source().display_name, "存活" if state.alive else "退场", float(state.current_health), state.get_max_health(), float(state.current_armor), state.remaining_cooldown, float(remainders.get(BattleSquadState.CHANNEL_HEALTH_DAMAGE, 0.0)), float(remainders.get(BattleSquadState.CHANNEL_ARMOR_DAMAGE, 0.0)), float(remainders.get(BattleSquadState.CHANNEL_HEALING, 0.0)), float(remainders.get(BattleSquadState.CHANNEL_ARMOR_GAIN, 0.0)), continuous_count, state.buff_stacks, state.logical_left, state.logical_right]


func _return_to_configuration_preview() -> void:
	if battle_controller != null and not battle_controller.get_all_states().is_empty():
		battle_controller.clear_battle()
		_playing = false
		_paused = true
		pause_button.text = "暂停"
		_clear_outputs()
		status_label.text = "配置已修改，等待开始"
	_refresh_state_view()


func _run_assertion() -> void:
	_start_battle()
	if not _playing:
		return
	_paused = true
	var executed := 0
	while battle_controller.is_running() and executed < scenario.max_batches:
		battle_controller.resolve_next_batch()
		executed += 1
	var problems := _collect_invariant_problems(battle_controller)
	if battle_controller.is_running():
		problems.append("达到 %d 批次上限后仍未结束" % scenario.max_batches)
	if scenario.expected_result >= 0 and battle_controller.current_result != scenario.expected_result:
		problems.append("预期%s，实际%s" % [_result_name(scenario.expected_result), _result_name(battle_controller.current_result)])
	var heading := "[color=#9fd6ac]PASS[/color]" if problems.is_empty() else "[color=#f19a8a]FAIL[/color]"
	report_text.text = "%s　%s\n执行批次：%d　最终时间：%.2f\n%s" % [heading, scenario.scenario_name, executed, battle_controller.elapsed_seconds, "未发现状态异常" if problems.is_empty() else "\n".join(problems)]
	_playing = false
	_refresh_state_view()
	_refresh_status()


func _run_combination_matrix() -> void:
	var runner := BattleController.new() as BattleController
	runner.name = "BattleLabMatrixRunner"
	add_child(runner)
	var total := 0
	var passed := 0
	var failures: Array[String] = []
	for action_type: int in CardData.ActionType.values():
		for element_type: int in CardData.ElementType.values():
			for count: int in range(2, 6):
				total += 1
				var matrix_scenario := BattleLabScenario.create_preset(&"water_boundary")
				var runes: Array[int] = []
				for _index: int in count:
					runes.append(element_type)
				matrix_scenario.player_squads[0]["action"] = action_type
				matrix_scenario.player_squads[0]["runes"] = runes
				matrix_scenario.random_seed = 100000 + action_type * 1000 + element_type * 100 + count
				runner.start_battle(matrix_scenario.build_player_formation(), matrix_scenario.build_enemy_formation(), matrix_scenario.random_seed, false)
				var batches := 0
				while runner.is_running() and batches < matrix_scenario.max_batches:
					runner.resolve_next_batch()
					batches += 1
				var problems := _collect_invariant_problems(runner)
				if runner.is_running():
					problems.append("未在上限内结束")
				if problems.is_empty():
					passed += 1
				else:
					failures.append("%s/%s/%d枚：%s" % [ACTION_NAMES[action_type], ELEMENT_NAMES[element_type], count, "；".join(problems)])
	runner.clear_battle()
	remove_child(runner)
	runner.free()
	report_text.text = "批量矩阵：5 种行动 × 5 种元素 × 2～5 枚\n[color=%s]%d / %d 通过[/color]\n%s" % ["#9fd6ac" if passed == total else "#f19a8a", passed, total, "所有组合满足生命、护甲、有限数值与结束条件。" if failures.is_empty() else "\n".join(failures)]


func _collect_invariant_problems(controller: BattleController) -> Array[String]:
	var problems: Array[String] = []
	for state: BattleSquadState in controller.get_all_states():
		if not is_finite(float(state.current_health)) or not is_finite(float(state.current_armor)):
			problems.append("%s 出现非有限生命或护甲" % state.get_action_source().display_name)
		if float(state.current_armor) < -0.0001 or float(state.current_armor) > CardData.MAXIMUM_ARMOR + 0.0001:
			problems.append("%s 护甲越界：%s" % [state.get_action_source().display_name, state.current_armor])
		if float(state.current_health) > state.get_max_health() + 0.0001:
			problems.append("%s 生命超过上限" % state.get_action_source().display_name)
	return problems


func _on_log_meta_hover_started(meta: Variant) -> void:
	var parts := String(meta).split(":")
	if parts.size() != 3 or parts[0] != "formula":
		return
	var entry := _log_by_group.get(int(parts[1])) as BattleLogEntry
	var formula := entry.get_formula(int(parts[2])) if entry != null else null
	if formula == null:
		return
	var content := BattleFormulaPresenter.format_popup(formula)
	formula_popup_text.text = content
	var desired_size := BattleFormulaPresenter.measure_popup_size(content, formula_popup_text.get_theme_font("normal_font"), formula_popup_text.get_theme_font_size("normal_font_size"), FORMULA_POPUP_MIN_WIDTH, FORMULA_POPUP_MAX_WIDTH, FORMULA_POPUP_MAX_HEIGHT, FORMULA_POPUP_CONTENT_PADDING)
	var viewport_size := get_viewport_rect().size
	var safe_size := Vector2(minf(desired_size.x, viewport_size.x), minf(desired_size.y, viewport_size.y))
	formula_popup.size = safe_size
	formula_popup_text.scroll_active = desired_size.y > safe_size.y
	var mouse := get_viewport().get_mouse_position()
	var desired_position := mouse + Vector2(-safe_size.x * 0.5, -safe_size.y - FORMULA_POPUP_MOUSE_GAP)
	formula_popup.position = Vector2(clampf(desired_position.x, 0.0, maxf(viewport_size.x - safe_size.x, 0.0)), clampf(desired_position.y, 0.0, maxf(viewport_size.y - safe_size.y, 0.0)))
	formula_popup.visible = true


func _on_log_meta_hover_ended(_meta: Variant) -> void:
	formula_popup.visible = false


func _clear_outputs() -> void:
	_log_entries.clear()
	_log_by_group.clear()
	_trace_lines.clear()
	battle_log_text.text = ""
	trace_text.text = ""
	report_text.text = ""
	formula_popup.visible = false


func _format_trace_line(event: BattleEffectEvent) -> String:
	var source_name := event.source.get_action_source().display_name if event.source != null and event.source.get_action_source() != null else "系统"
	var target_name := event.target.get_action_source().display_name if event.target != null and event.target.get_action_source() != null else "未知目标"
	var element_name := ELEMENT_NAMES[event.element_type] if event.element_type >= 0 and event.element_type < ELEMENT_NAMES.size() else "基础"
	return "[t=%s][层%d:%s] %s → %s　%s %s　实际生效 %s" % [BattleLogEntry.format_number(event.timestamp), event.logical_layer, element_name, source_name, target_name, event.log_qualifier, BattleLogEntry.format_number(event.exact_amount), BattleLogEntry.format_number(event.effective_amount)]


func _result_name(result: int) -> String:
	match result:
		BattleController.Result.PLAYER_VICTORY: return "我方胜利"
		BattleController.Result.PLAYER_DEFEAT: return "我方失败"
		BattleController.Result.DRAW: return "平局"
		_: return "未结束"


func _get_side_specs(side_key: String) -> Array[Dictionary]:
	return scenario.player_squads if side_key == "player" else scenario.enemy_squads


func _labeled_row(label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_fixed_label(label_text, 72.0))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _double_spin_row(left_label: String, left_spin: SpinBox, right_label: String, right_spin: SpinBox) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_fixed_label(left_label, 38.0))
	left_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_spin)
	row.add_child(_fixed_label(right_label, 38.0))
	right_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right_spin)
	return row


func _fixed_label(text_value: String, width: float) -> Label:
	var label := Label.new()
	label.text = text_value
	label.custom_minimum_size.x = width
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _make_spin(minimum: float, maximum: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.allow_greater = false
	spin.allow_lesser = false
	return spin


func _make_output_text(tab_name: String) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.name = tab_name
	text.bbcode_enabled = true
	text.meta_underlined = true
	text.fit_content = false
	text.scroll_active = true
	text.scroll_following = true
	text.selection_enabled = true
	text.add_theme_font_override("normal_font", BATTLE_LOG_FONT)
	text.add_theme_font_size_override("normal_font_size", 12)
	return text


func _select_option_by_id(option: OptionButton, item_id: int) -> void:
	for index: int in option.item_count:
		if option.get_item_id(index) == item_id:
			option.select(index)
			return


func _closest_speed_index(speed: float) -> int:
	var result := 0
	var distance := INF
	for index: int in SPEED_VALUES.size():
		var next_distance := absf(SPEED_VALUES[index] - speed)
		if next_distance < distance:
			distance = next_distance
			result = index
	return result


func _clear_children(parent: Control) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
