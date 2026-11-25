class_name EnemyLineupEditor
extends Control

signal trial_requested(lineup: Dictionary, day: int, tutorial: bool, seed_value: int)
signal custom_enemy_requested

const Catalog = preload("res://scripts/flow/enemy_lineup_catalog.gd")
const Builder = preload("res://scripts/flow/enemy_encounter_builder.gd")
const Metrics = preload("res://scripts/tools/enemy_lineup_metrics.gd")
const Table = preload("res://scripts/tools/enemy_lineup_table.gd")
const MAX_SEED := 999999999 # 与战斗实验室种子输入一致
const UPDATE_SECONDS := 0.16 # 连续桌面操作合并为一笔指标和撤销更新
const MAX_UNDO := 24 # 每套阵容当前编辑会话保留的撤销步骤数
const RARITY_NAMES := ["I", "II", "III", "IV", "V"]

var draft_path := Catalog.DRAFT_PATH
var export_path := Catalog.EXPORT_PATH
var registry: Dictionary = {}
var content: Dictionary = {}
var _published: Dictionary = {}
var _drafts: Dictionary = {}
var _sessions: Dictionary = {}
var _lineups: Array = []
var _working: Dictionary = {}
var _day := 1
var _tutorial := false
var _loading := false
var _references: Array[Dictionary] = []
var _reference_seed := -1
var _visual_baseline: Dictionary = {}
var _undo: Array[Dictionary] = []
var workspace: Table

var level_picker: OptionButton
var lineup_picker: OptionButton
var name_edit: LineEdit
var hint_edit: LineEdit
var seed_edit: SpinBox
var _metrics: RichTextLabel
var _summary: Button
var _status: Label
var _copy_button: Button
var _test_button: Button
var _management: Control
var _detail: Control
var _measure_dirty := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	registry = Builder.load_card_definitions()
	content = Catalog.load_base_content()
	var published := Catalog.read_document(Catalog.FORMAL_PATH)
	if published.get("version") == 1 and published.get("levels") is Dictionary: _published = published.levels
	var saved := Catalog.read_document(draft_path)
	if saved.get("version") == 1 and saved.get("levels") is Dictionary: _drafts = saved.levels
	workspace = Table.new()
	workspace.name = "LineupVisualWorkspace"
	add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.setup(registry)
	_build_interface()
	_select_level(0)
	var refresh := Timer.new()
	refresh.wait_time = UPDATE_SECONDS
	refresh.autostart = true
	refresh.timeout.connect(_sync_display)
	add_child(refresh)
	visibility_changed.connect(func():
		if visible: _sync_display()
		else:
			workspace.cancel_shape()
			_detail.hide()
			workspace.table._close_card_inspection(true)
			workspace.table._close_toolbox_inspection(false))


func _build_interface() -> void:
	var toolbar := HBoxContainer.new()
	toolbar.position = Vector2(24, 341) # 编辑桌返回键位于法术板与工具箱之间的空桌缘
	toolbar.z_index = 2401
	add_child(toolbar)
	_button(toolbar, "返回实验室", hide)

	_management = PanelContainer.new()
	_management.name = "LineupBlueBookmarkPage"
	_management.position = Vector2(46, 42) # 管理表单放在蓝签左页内
	_management.size = Vector2(366, 262)
	_management.z_index = 80
	_management.hide()
	workspace.table.get_node("%BookPanel").add_child(_management)
	var page := VBoxContainer.new()
	_management.add_child(page)
	_label(page, "阵容管理")
	var level_row := HBoxContainer.new()
	page.add_child(level_row)
	level_picker = OptionButton.new()
	level_row.add_child(level_picker)
	for tutorial: bool in [false, true]:
		var days := 4 if tutorial else ShortMazeRunState.DAYS * 3 + 4
		for day: int in range(1, days + 1):
			level_picker.add_item(Catalog.level_name(day, tutorial))
			level_picker.set_item_metadata(level_picker.item_count - 1, {"day": day, "tutorial": tutorial})
	level_picker.item_selected.connect(_select_level)
	lineup_picker = OptionButton.new()
	lineup_picker.fit_to_longest_item = false
	lineup_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lineup_picker.item_selected.connect(_select_lineup)
	level_row.add_child(lineup_picker)
	name_edit = _line_edit(page, "阵容名称", 0)
	name_edit.text_changed.connect(func(value: String): _change_text("name", value))
	hint_edit = _line_edit(page, "路线提示", 0)
	hint_edit.text_changed.connect(func(value: String): _change_text("hint", value))
	var seed_row := HBoxContainer.new()
	page.add_child(seed_row)
	_label(seed_row, "试打种子")
	seed_edit = SpinBox.new()
	seed_edit.max_value = MAX_SEED
	seed_edit.value = 12345
	seed_edit.value_changed.connect(func(value: float):
		workspace.seed_value = roundi(value)
		_capture_changes()
		if not _working.is_empty() and not _working.has("visual"): _load_table()
		else: _schedule_measure())
	seed_row.add_child(seed_edit)
	var edit_row := HBoxContainer.new()
	page.add_child(edit_row)
	_copy_button = _button(edit_row, "复制阵容", _duplicate_lineup)
	_button(edit_row, "从空阵容开始", _duplicate_lineup.bind(true))
	_button(edit_row, "撤销布置", _undo_table)
	_button(edit_row, "移除草稿", _remove_lineup)
	var actions := HBoxContainer.new()
	page.add_child(actions)
	_button(actions, "保存", _save_draft)
	_test_button = _button(actions, "试打", _request_trial)
	_button(actions, "导出发布配置", _export_level)
	_button(actions, "回自定义敌方", func():
		hide()
		custom_enemy_requested.emit())
	_status = _label(page, "")
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	_summary = _button(self, "", _toggle_details)
	_summary.name = "LineupLiveMetrics"
	_summary.position = Vector2(1082, 556) # 原玩家头像区域的右下角指标卡
	_summary.size = Vector2(184, 130)
	_summary.tooltip_text = "右键查看指标明细"
	_summary.z_index = 2402
	_summary.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_toggle_details()
			_summary.accept_event())
	_detail = PanelContainer.new()
	_detail.name = "LineupMetricDetails"
	_detail.position = Vector2(648, 175) # 明细展开到指标板左上侧，避免出屏
	_detail.size = Vector2(610, 365)
	_detail.z_index = 3950
	var body := VBoxContainer.new()
	_detail.add_child(body)
	_button(body, "收起指标", _detail.hide)
	_metrics = RichTextLabel.new()
	_metrics.bbcode_enabled = true
	_metrics.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_metrics.add_theme_constant_override("table_h_separation", 24) # 指标、当前值、参考值三列间距
	body.add_child(_metrics)
	add_child(_detail)
	_detail.hide()


func _toggle_details() -> void:
	_detail.visible = not _detail.visible


func close_active_layer() -> bool:
	var table: Control = workspace.table
	if workspace.shape_is_open(): workspace.cancel_shape()
	elif not table._click_carry_data.is_empty(): table._cancel_click_carry()
	elif table._rune_scraper_mode: table._finish_rune_scraper_mode()
	elif is_instance_valid(table._inspection_overlay): table._close_card_inspection()
	elif is_instance_valid(table._toolbox_overlay): table._close_toolbox_inspection()
	elif _detail.visible: _detail.hide()
	else: hide()
	return true


func _select_level(index: int) -> void:
	_capture_changes()
	var level: Dictionary = level_picker.get_item_metadata(index)
	_day = int(level.day)
	_tutorial = level.tutorial
	var key := Catalog.level_key(_day, _tutorial)
	if not _sessions.has(key):
		var source: Variant = _drafts.get(key, _reference_lineups())
		_sessions[key] = source.duplicate(true) if source is Array else _reference_lineups()
	_lineups = _sessions[key]
	_reference_seed = -1
	_rebuild_lineup_picker(0)
	_status.text = ""


func _load_table() -> void:
	var was_loading := _loading
	_loading = true
	var encounter: Dictionary = {}
	var resources := ResourceBoardState.new()
	var legacy := not _working.has("visual")
	if not _working.is_empty():
		var seed_value := roundi(seed_edit.value)
		var path := Catalog.path_for(_working, _day, _tutorial)
		path["battle_seed"] = seed_value
		var builder := Builder.new()
		var snapshot: Dictionary = builder.build(path, registry, Catalog.rune_reveals(content, _day, _tutorial), Catalog.emblem_count(content, _day, _tutorial)) if legacy else _working.visual.encounter
		encounter = builder.restore(snapshot, registry)
		if not _tutorial: Builder.place_level_resources(path, registry, resources)
	workspace.load_lineup(encounter, resources, _tutorial, roundi(seed_edit.value), legacy)
	_visual_baseline = workspace.capture_visual()
	_loading = was_loading
	_schedule_measure()


func _capture_changes() -> void:
	if _loading or _working.is_empty() or not is_instance_valid(workspace) or _visual_baseline.is_empty(): return
	var visual := workspace.capture_visual()
	if visual == _visual_baseline: return
	_undo.append(_visual_baseline)
	if _undo.size() > MAX_UNDO: _undo.pop_front()
	_visual_baseline = visual
	_working["visual"] = visual
	_schedule_measure()


func _undo_table() -> void:
	_capture_changes()
	if _undo.is_empty(): return
	_working["visual"] = _undo.pop_back()
	_load_table()


func _sync_display() -> void:
	if not is_visible_in_tree() or not is_instance_valid(workspace): return
	var table: Control = workspace.table
	_management.visible = table.collection_bookmark_active and not table.is_page_turning() and not table._escape_menu_pause_requested
	workspace.pack_picker.visible = not table.collection_bookmark_active
	_capture_changes()
	if _measure_dirty:
		_measure_dirty = false
		_update_measure()


func _schedule_measure() -> void:
	_measure_dirty = true


func _reference_lineups() -> Array:
	var formal: Variant = _published.get(Catalog.level_key(_day, _tutorial), [])
	if formal is Array and not formal.is_empty():
		return formal.duplicate(true)
	var results: Array = []
	for path: Dictionary in Catalog.base_paths(content, _day, _tutorial):
		results.append(Catalog.lineup_from_path(path, "原阵容 %d" % (results.size() + 1)))
	return results


func _rebuild_lineup_picker(index: int) -> void:
	lineup_picker.clear()
	for lineup: Dictionary in _lineups:
		lineup_picker.add_item(String(lineup.get("name", "")))
	lineup_picker.select(index if index < _lineups.size() else -1)
	_select_lineup(index)


func _select_lineup(index: int) -> void:
	_capture_changes()
	_working = _lineups[index] if index >= 0 and index < _lineups.size() else {}
	_copy_button.disabled = _working.is_empty()
	_loading = true
	name_edit.text = _working.get("name", "")
	hint_edit.text = _working.get("hint", "")
	name_edit.editable = not _working.is_empty()
	hint_edit.editable = not _working.is_empty()
	_loading = false
	_undo.clear()
	_load_table()


func _duplicate_lineup(blank: bool = false) -> void:
	_capture_changes()
	if _lineups.size() >= Catalog.MAX_LINEUPS:
		_status.text = "本关最多保存 %d 套阵容" % Catalog.MAX_LINEUPS
		return
	var copy := {} if blank else _working.duplicate(true)
	if copy.is_empty(): copy = Catalog.lineup_from_path({}, "新阵容")
	copy.id = "draft_%x" % Time.get_ticks_usec()
	var stem := String(copy.name) + " 副本" if not blank and not _working.is_empty() else String(copy.name)
	copy.name = stem
	var number := 2
	while _lineups.any(func(lineup: Dictionary) -> bool: return lineup.name == copy.name):
		copy.name = "%s %d" % [stem, number]
		number += 1
	_lineups.append(copy)
	_rebuild_lineup_picker(_lineups.size() - 1)


func _remove_lineup() -> void:
	_capture_changes()
	if lineup_picker.selected < 0: return
	var index := lineup_picker.selected
	_lineups.remove_at(index)
	_rebuild_lineup_picker(mini(index, _lineups.size() - 1))


func _change_text(key: String, value: String) -> void:
	if _loading or _working.is_empty(): return
	_working[key] = value
	if key == "name" and lineup_picker.selected >= 0:
		lineup_picker.set_item_text(lineup_picker.selected, value)
	_schedule_measure()


func _prepare(lineup: Dictionary, value: int = -1) -> Dictionary:
	return Metrics.prepare(lineup, registry, content, _day, _tutorial, roundi(seed_edit.value) if value < 0 else value)


func _update_measure() -> void:
	var seed_value := roundi(seed_edit.value)
	if seed_value != _reference_seed:
		_references.clear()
		for lineup: Dictionary in _reference_lineups():
			var reference := _prepare(lineup, seed_value)
			if not reference.has("error"): _references.append(Metrics.measure(reference))
		_reference_seed = seed_value
	var prepared := _prepare(_working)
	_test_button.disabled = _working.is_empty() or prepared.has("error")
	if not _test_button.disabled and _working.has("visual"): workspace.update_chaos_preview(prepared.formation)
	var result := {} if _test_button.disabled else Metrics.measure(prepared)
	var lines := PackedStringArray(["[b]阵容指标[/b]", "参考来自 %d 套正式阵容，使用相同种子。" % _references.size(), ""])
	if result.is_empty(): lines.append("当前阵容 · " + String(prepared.get("error", "")))
	var rows := PackedStringArray(["[table=3][cell][b]指标[/b][/cell][cell][b]当前[/b][/cell][cell][b]关卡参考[/b][/cell]"])
	for metric: Array in [
		["dps", "理论 DPS", true], ["healing", "每秒治疗", true], ["defense", "每秒防御", true],
		["durability", "生命＋护甲", false], ["health", "生命", false], ["armor", "护甲", false],
		["front", "前排耐久", false], ["back", "后排耐久", false],
		["visible_emblems", "显现纹章", false], ["emblems", "已贴纹章", false],
		["visible_wounds", "显现伤势", false], ["wounds", "已贴伤势", false], ["wound_levels", "显现伤势等级合计", false],
		["runes", "显现符文", false], ["patterned", "有牌型小队", false], ["spell_count", "法术张数", false],
	]:
		rows.append(_metric_row(metric[1], result.get(metric[0]), _reference_values(metric[0]), metric[2]))
	rows.append(_metric_row("[b]法术稀有度[/b]"))
	for tier: int in RARITY_NAMES.size():
		rows.append(_metric_row(RARITY_NAMES[tier], result.spell_rarities[tier] if not result.is_empty() else null, _reference_values("spell_rarities", tier)))
	var patterns: Dictionary = result.get("patterns", {}).duplicate()
	for reference: Dictionary in _references: patterns.merge(reference.patterns)
	if not patterns.is_empty():
		rows.append(_metric_row("[b]各牌型小队数[/b]"))
		for pattern_name: String in patterns:
			var counts: Array[float] = []
			for reference: Dictionary in _references: counts.append(float(reference.patterns.get(pattern_name, 0)))
			rows.append(_metric_row(pattern_name, null if result.is_empty() else result.patterns.get(pattern_name, 0), counts))
	rows.append("[/table]")
	lines.append("".join(rows))
	lines.append("")
	lines.append("理论 DPS 按小队行动值、牌型倍率和开场冷却计算。")
	if not result.is_empty():
		lines.append("")
		lines.append("[b]小队明细[/b]")
		for entry: Dictionary in prepared.formation:
			var squad := entry.squad_data as SquadData
			var per_squad := Metrics.measure({"formation": [entry], "spells": []})
			lines.append("%s %d · %s · DPS %.2f · 耐久 %d · 纹章 %d · 伤势 %d · %s" % [
				"前排" if entry.row_key == &"enemy_front" else "后排", int(entry.formation_index) + 1,
				squad.get_effect_source().display_name, per_squad.dps, per_squad.durability,
				per_squad.visible_emblems, per_squad.visible_wounds, squad.get_rune_pattern_result().get_pattern_name()])
	_metrics.text = "\n".join(lines)
	var range_dps := _format_range(_reference_values("dps"), true)
	var range_life := _format_range(_reference_values("durability"), false)
	_summary.text = "阵容指标　当前 / 参考\nDPS  %s / %s\n耐久  %s / %s\n纹章 %d 伤势 %d\n牌型 %d 法术 %d" % [
		_number(result.get("dps", 0.0), true), range_dps, _number(result.get("durability", 0), false), range_life,
		result.get("visible_emblems", 0), result.get("visible_wounds", 0), result.get("patterned", 0), result.get("spell_count", 0)]


func _reference_values(key: String, tier: int = -1) -> Array[float]:
	var values: Array[float] = []
	for reference: Dictionary in _references:
		values.append(float(reference[key] if tier < 0 else reference[key][tier]))
	return values


func _metric_row(title: String, number: Variant = null, range_values: Array[float] = [], decimal: bool = false) -> String:
	var current := _number(number, decimal) if number != null else "—"
	var reference := _format_range(range_values, decimal)
	if title.begins_with("[b]"):
		current = ""
		reference = ""
	elif number != null and not range_values.is_empty() and (float(number) < float(range_values.min()) - 0.005 or float(number) > float(range_values.max()) + 0.005):
		current = "[color=#f2c583]%s[/color]" % current
	return "[cell]%s[/cell][cell]%s[/cell][cell]%s[/cell]" % [title, current, reference]


func _format_range(values: Array[float], decimal: bool) -> String:
	if values.is_empty(): return "暂无参考"
	var low := _number(values.min(), decimal)
	var high := _number(values.max(), decimal)
	return low if low == high else "%s～%s" % [low, high]


func _number(value: float, decimal: bool) -> String:
	return "%.2f" % value if decimal else str(roundi(value))


func _pool_error(minimum: int) -> String:
	if _lineups.size() < minimum: return "本关至少需要 %d 套阵容" % minimum
	var names := {}
	var ids := {}
	for lineup: Dictionary in _lineups:
		var label := String(lineup.get("name", "")).strip_edges()
		if names.has(label) or ids.has(lineup.get("id")): return "同关卡的阵容名称和编号须各自唯一"
		names[label] = true
		ids[lineup.get("id")] = true
		var selection := _prepare(lineup)
		if selection.has("error"): return "%s · %s" % [label, selection.error]
	return ""


func _save_draft() -> bool:
	_capture_changes()
	var error := _pool_error(1)
	if not error.is_empty():
		_status.text = error
		return false
	var next := _drafts.duplicate(true)
	next[Catalog.level_key(_day, _tutorial)] = _lineups.duplicate(true)
	var write_error := Catalog.write_document(draft_path, next)
	if write_error != OK:
		_status.text = "草稿保存失败（%d）" % write_error
		return false
	_drafts = next
	_status.text = "%s · 已保存 %d 套阵容" % [Catalog.level_name(_day, _tutorial), _lineups.size()]
	return true


func _export_level() -> void:
	_capture_changes()
	var error := _pool_error(Catalog.ENCOUNTER_CHOICES)
	if not error.is_empty():
		_status.text = error
		return
	var levels := _published.duplicate(true)
	var previous := Catalog.read_document(export_path)
	if previous.get("version") == 1 and previous.get("levels") is Dictionary: levels.merge(previous.levels, true)
	levels[Catalog.level_key(_day, _tutorial)] = _lineups.duplicate(true)
	var write_error := Catalog.write_document(export_path, levels)
	_status.text = "已导出 · " + ProjectSettings.globalize_path(export_path) if write_error == OK else "导出失败（%d）" % write_error
	_status.tooltip_text = _status.text


func _request_trial() -> void:
	_capture_changes()
	var prepared := _prepare(_working)
	if prepared.has("error"):
		_status.text = prepared.error
		return
	hide()
	trial_requested.emit(_working.duplicate(true), _day, _tutorial, roundi(seed_edit.value))


func _button(parent: Control, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _label(parent: Control, title: String) -> Label:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	return label


func _line_edit(parent: Control, title: String, width: float) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = title
	edit.custom_minimum_size.x = width
	parent.add_child(edit)
	return edit
