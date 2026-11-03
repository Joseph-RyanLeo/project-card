extends "res://scripts/ui/read_only_card_inspector.gd"

signal new_run_requested
signal gallery_requested
signal settings_requested
signal return_requested
signal collection_action_requested(action: StringName)
signal selection_requested(choices: Array)

const Candidate = preload("res://scripts/ui/collection_candidate_card.gd")
const COMPARE_SCALE := 2.0 # 替换时四张卡并排使用整数2倍显示
var slot_index: int
var _book: GridContainer
var _scroll: ScrollContainer
var _cells: Dictionary = {}
var _shown_ids: Array = []
var _count: Label
var _details: ScrollContainer
var _rarity_filter: OptionButton
var _action_filter: OptionButton
var _search: LineEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.make_theme()
	Style.add_background(self)
	_label(self, "存档 %d · %s" % [slot_index + 1, {"hub": "局外大厅", "summary": "局后总结", "selection": "本次收藏", "preview": "集合预览"}[progress.run.stage]], Vector2(60, 48), 32)
	_label(self, "积分余额 %d" % progress.profile.points, Vector2(64, 100), 22)
	var menu := VBoxContainer.new()
	menu.position = Vector2(60, 190) # 左栏操作起点
	menu.add_theme_constant_override("separation", 14) # 左栏操作间距
	add_child(menu)
	if progress.run.stage == "hub":
		Style.button(menu, "开始新一局", "NewRunButton", new_run_requested.emit)
		Style.button(menu, "展览馆", "GalleryButton", gallery_requested.emit)
		var shop := Style.button(menu, "迷宫商店", "MazeShopButton", Callable())
		shop.disabled = true
		shop.tooltip_text = "尚未开放"
		Style.button(menu, "设置", "HubSettingsButton", settings_requested.emit)
	elif progress.run.stage == "summary":
		_build_summary(menu)
	else:
		_count = _label(self, "", Vector2(370, 102), 20)
		_build_candidate_filters()
		_label(self, "左键选择／取消 · 右键4×检视 · 滚轮浏览" if progress.run.stage == "selection" else "右键4×检视 · 返回选卡可修改 · 滚轮浏览", Vector2(370, 136), 14)
		if progress.run.stage == "selection":
			Style.button(menu, "集合预览", "CollectionPreviewButton", collection_action_requested.emit.bind(&"show_preview"))
		else:
			Style.button(menu, "返回选卡", "CollectionBackButton", collection_action_requested.emit.bind(&"return_to_selection"))
			Style.button(menu, "最终确认收藏", "CollectionConfirmButton", collection_action_requested.emit.bind(&"confirm_collection"))
		_scroll = ScrollContainer.new()
		_scroll.name = "CandidateScroll"
		_scroll.position = Vector2(370, 158) # 滚动候选区位置
		_scroll.size = Vector2(850, 510) # 保留底部留白，滚轮连续浏览
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.scroll_deadzone = 8 # 避免轻触移动被误判为滚动
		add_child(_scroll)
		_book = GridContainer.new()
		_book.columns = 5 # 原生1倍卡每行五张
		_book.add_theme_constant_override("h_separation", 6) # 卡位横向间距
		_book.add_theme_constant_override("v_separation", 12) # 卡位纵向间距
		_scroll.add_child(_book)
		_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float):
			var shell := get_tree().get_first_node_in_group(&"game_display_shell")
			if shell != null and shell.get_collection_hover_surface().read_only: shell.get_collection_hover_surface().release_collection())
		_draw_cards()
	Style.button(menu, "返回主菜单", "HubReturnButton", return_requested.emit)


func _build_summary(menu: Control) -> void:
	var summary: Dictionary = progress.run.get("summary", {})
	_label(self, {"cleared": "迷宫通关", "failed": "本局失败", "abandoned": "主动放弃"}.get(summary.get("outcome", ""), "本局结束"), Vector2(420, 175), 30)
	_label(self, "本局积分 +%d · 已自动入账" % int(summary.get("total", 0)), Vector2(420, 225), 28)
	var text := "基础分 %d × 倍率 %.1f → %d\n已完成 %d 天 · Boss／半层通关 %d 次\n通关剩余保护 %d" % [int(summary.get("base", 0)), float(summary.get("multiplier_tenths", 10)) / 10.0, int(summary.get("total", 0)), int(summary.get("completed_days", 0)), int(summary.get("bosses", 0)), int(summary.get("protection", 0))]
	if not summary.get("eligible", true): text += "\n前两天主动放弃不计分、不可选卡；已实际获得的发现已保存。"
	_label(self, text, Vector2(420, 282), 20)
	Style.button(menu, "查看得分详情", "ScoreDetailsButton", func(): _details.visible = not _details.visible)
	Style.button(menu, "本次收藏", "SummaryCollectionButton", collection_action_requested.emit.bind(&"show_selection"))
	_details = ScrollContainer.new()
	_details.name = "ScoreDetails"
	_details.position = Vector2(415, 385) # 明细滚动区起点
	_details.size = Vector2(810, 245) # 明细高度；保持底部导航可见
	add_child(_details)
	_details.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := GridContainer.new()
	rows.name = "ScoreImageGrid"
	rows.columns = 2 # 得分详情两列图片条目，滚轮连续浏览
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("h_separation", 12) # 图片条目列间距
	rows.add_theme_constant_override("v_separation", 12) # 图片条目行间距
	_details.add_child(rows)
	for card: Dictionary in summary.get("cards", []):
		var parts: Dictionary = card.parts
		var info := "%s%s · %d分\n品级%d / 卡面%d / 卡图%d\n贴纸%d / 符文%d / 牌型%d" % [card.name, "（耗尽）" if card.exhausted else "", int(card.total), int(parts.grade), int(parts.surface), int(parts.art), int(parts.stickers), int(parts.runes), int(parts.pattern)]
		var picture := _score_tile(rows, info)
		var snapshot: Dictionary = card.get("snapshot", progress.run.candidates.get(card.instance_id, {}))
		if not snapshot.is_empty():
			var visual := _card_view(picture, snapshot, Vector2(1, 4), 1.0)
			visual.name = "ScoreCard_" + String(card.instance_id)
		else:
			var definition := load("res://resources/cards/%s.tres" % card.card_id) as CardData
			var visual := CARD.instantiate() as CardView
			visual.set_snapshot_mode(true)
			visual.set_card_data(definition)
			picture.add_child(visual)
			visual.position = Vector2(1, 4) # 旧总结缺实例快照时显示定义图，不补造外观与符文
	for item: Dictionary in summary.get("toolbox", []):
		var picture := _score_tile(rows, "工具箱 · %s\n基础积分 %d" % [item.name, int(item.total)])
		var state: Dictionary = item.get("sticker", {})
		var id := StringName(state.get("emblem_id", state.get("wound_id", item.name)))
		var texture := RuneStickerStyle.get_texture_by_id(id)
		if texture == null: texture = StatusIndicatorStyle.get_texture(CardSlotLayout.Kind.WOUND if state.has("wound_id") else CardSlotLayout.Kind.EMBLEM, id)
		if texture == null: texture = StatusIndicatorStyle.get_texture(CardSlotLayout.Kind.WOUND, id)
		_score_icon(picture, texture)
	var gold_picture := _score_tile(rows, "剩余金币 · %d\n1:1计入基础积分" % int(summary.get("gold", 0)))
	_score_icon(gold_picture, preload("res://assets/ui/board_revision_20261019/gold_icon.png"))
	_details.hide()


func _score_tile(parent: Control, text: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 160) # 得分图片条目的最小宽高
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := Style.panel(Color(0.06, 0.085, 0.12, 0.94), Color(0.5, 0.43, 0.31))
	style.set_content_margin_all(10) # 图片条目内距
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10) # 图片与得分说明的间隔
	panel.add_child(row)
	var picture := Control.new()
	picture.name = "ScorePicture"
	picture.custom_minimum_size = Vector2(100, 144) # 容纳1倍卡牌及整数倍贴纸
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(picture)
	var label := _label(row, text, Vector2.ZERO, 17)
	label.custom_minimum_size.x = 230 # 图片右侧说明换行宽度
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return picture


func _score_icon(parent: Control, texture: Texture2D) -> void:
	if texture == null: return
	var icon := TextureRect.new()
	icon.name = "ScoreStickerImage"
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var factor := maxf(1.0, floorf(64.0 / maxf(texture.get_width(), texture.get_height()))) # 图标不超过64px，保持整数倍像素
	icon.scale = Vector2.ONE * factor
	parent.add_child(icon)
	icon.position = ((parent.custom_minimum_size - texture.get_size() * factor) * 0.5).floor()


func _candidate_ids() -> Array:
	if progress.run.stage == "preview": return progress.run.selection.map(func(choice: Dictionary): return choice.candidate_id)
	return progress.run.candidates.keys()


func _visible_ids() -> Array:
	return _candidate_ids().filter(func(id: String): return _matches_filters(_cells[id].view.get_owned_card()))


func _matches_filters(owned: OwnedCard) -> bool:
	var card := owned.card_data
	if _rarity_filter.selected > 0 and int(card.rarity) != _rarity_filter.selected - 1: return false
	if _action_filter.selected > 0:
		var action: int = owned.resolved_action_type if owned.resolved_action_type >= 0 else int(card.action_type)
		if card.card_type != CardData.CardType.MINION or action != _action_filter.selected - 1: return false
	var query := _search.text.strip_edges().to_lower()
	if query.is_empty(): return true
	return (card.display_name + " " + owned.get_effect_text_for_row(&"player_front") + " " + owned.get_effect_text_for_row(&"player_back")).to_lower().contains(query)


func _build_candidate_filters() -> void:
	var controls := HBoxContainer.new()
	controls.name = "CandidateFilters"
	controls.position = Vector2(684, 90) # 筛选和搜索放在候选区右上角
	controls.add_theme_constant_override("separation", 8) # 筛选控件间距
	add_child(controls)
	_rarity_filter = OptionButton.new()
	_rarity_filter.name = "CandidateRarityFilter"
	_rarity_filter.add_item("全部品级")
	for grade: String in ["I", "II", "III", "IV", "V"]: _rarity_filter.add_item(grade + "级")
	_action_filter = OptionButton.new()
	_action_filter.name = "CandidateActionFilter"
	_action_filter.add_item("全部行动")
	for action: int in CardData.ActionType.values(): _action_filter.add_item(CardData.get_action_type_name_for(action as CardData.ActionType))
	for filter: OptionButton in [_rarity_filter, _action_filter]:
		filter.custom_minimum_size = Vector2(140, 38) # 下拉筛选的紧凑尺寸
		filter.add_theme_font_size_override("font_size", 18) # 筛选字号
		for state: String in ["normal", "hover", "pressed", "focus"]:
			var style := Style.panel(Color("161e2a"), Style.GOLD)
			style.content_margin_top = 6 # 紧凑筛选按钮的上下留白
			style.content_margin_bottom = 6 # 紧凑筛选按钮的上下留白
			filter.add_theme_stylebox_override(state, style)
		controls.add_child(filter)
		filter.item_selected.connect(_filter_changed)
	_search = LineEdit.new()
	_search.name = "CandidateSearch"
	_search.placeholder_text = "搜索卡名／效果"
	_search.custom_minimum_size = Vector2(228, 38) # 搜索框宽度与筛选保持同高
	_search.add_theme_font_size_override("font_size", 18) # 搜索框字号
	controls.add_child(_search)
	_search.text_changed.connect(_filter_changed)


func _filter_changed(_value: Variant = null) -> void:
	close_inspection(false)
	var shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if shell != null: shell.get_collection_hover_surface().release_collection()
	_scroll.scroll_vertical = 0
	_draw_cards()


func _choice(id: String) -> Dictionary:
	for choice: Dictionary in progress.run.selection:
		if choice.candidate_id == id: return choice
	return {}


func _draw_cards() -> void:
	var ids := _candidate_ids()
	if ids != _shown_ids or _book.get_child_count() == 0:
		for child: Node in _book.get_children(): child.free()
		_cells.clear()
		_shown_ids = ids.duplicate()
		for id: String in ids:
			var cell := Candidate.new()
			cell.name = "Candidate_" + id
			_book.add_child(cell)
			cell.setup(_decode(progress.run.candidates[id]))
			cell.chosen.connect(_choose_card.bind(id), CONNECT_DEFERRED)
			cell.inspected.connect(_inspect.bind(id), CONNECT_DEFERRED)
			_cells[id] = cell
	var visible_ids := _visible_ids()
	_count.text = "已选%d/8 · 显示%d/%d" % [progress.run.selection.size(), visible_ids.size(), ids.size()]
	for id: String in _cells:
		var card: Dictionary = progress.run.candidates[id]
		_cells[id].visible = visible_ids.has(id)
		_cells[id].sync_choice(_choice(id), progress.profile.collection.get(card.card_id, []).size())
	var empty := _book.get_node_or_null("EmptyCandidates") as Label
	if empty == null:
		empty = _label(_book, "", Vector2.ZERO, 22)
		empty.name = "EmptyCandidates"
	empty.text = ("本次未选择卡牌" if progress.run.stage == "preview" else "没有可入藏的卡牌") if ids.is_empty() else "没有符合筛选的卡牌"
	empty.visible = visible_ids.is_empty()


func _choose_card(id: String) -> void:
	if progress.run.stage != "selection": return
	if not _choice(id).is_empty():
		_remove_choice(id)
		return
	if progress.run.selection.size() >= 8: return
	var slot := _first_free_slot(String(progress.run.candidates[id].card_id))
	if slot >= 0: _add_choice(id, slot)
	else: _compare(id)


func _compare(id: String) -> void:
	close_inspection(false)
	var shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if shell != null: shell.get_collection_hover_surface().release_collection()
	var card: Dictionary = progress.run.candidates[id]
	var dialog := preload("res://scripts/ui/card_inspection_overlay.gd").new()
	dialog.name = "CollectionComparison"
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.z_index = 200 # 原生画布比较层，随720p／2K显示壳一致缩放
	add_child(dialog)
	_inspection = dialog
	dialog.close_requested.connect(close_inspection)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.68) # 比较时保留背景的变暗蒙版
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(dim)
	var frame := Panel.new()
	frame.position = Vector2(40, 24) # 比较区在720p逻辑画布中的留白
	frame.size = Vector2(1200, 672) # 接近全屏的四卡比较区域
	frame.add_theme_stylebox_override("panel", Style.panel(Color("161e2a"), Style.GOLD))
	dialog.add_child(frame)
	var body := Control.new()
	body.name = "ComparisonBody"
	body.position = Vector2(55, 60) # 比较正文位于标题下方
	body.size = Vector2(1170, 610) # 正文范围，四张卡始终按逻辑2倍绘制
	dialog.add_child(body)
	_label(dialog, "选择替换位置 · 新旧收藏对比", Vector2(70, 30), 24)
	var slots: Array = progress.profile.collection.get(card.card_id, [])
	for index: int in 4:
		var at := Vector2(30 + index * 270, 35) # 原生2倍卡的四列位置
		_label(body, "本局候选" if index == 0 else "已有收藏位 %d" % index, at - Vector2(0, 30), 20)
		if index > slots.size():
			_label(body, "空位", at + Vector2(50, 90), 22)
			continue
		var encoded: Dictionary = card if index == 0 else slots[index - 1]
		var view := _card_view(body, encoded, at, COMPARE_SCALE)
		view.name = "ComparisonCard%d" % index
		preload("res://scripts/ui/collection_card_hover.gd").bind_read_only(view)
		var owned := _decode(encoded)
		var history := ScrollContainer.new()
		history.position = at + Vector2(-5, 290) # 卡下方直接显示效果和实例历史，替代翻面按钮
		history.size = Vector2(245, 170) # 长效果、战绩可独立滚动
		history.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body.add_child(history)
		var info := _label(history, _detail_text(owned), Vector2.ZERO, 15)
		info.custom_minimum_size.x = 225 # 为滚动条留出宽度
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var choice := _choice(id)
	if progress.run.stage == "selection":
		if not choice.is_empty():
			var remove := Style.button(body, "取消选择", "DeselectCandidateButton", func(): _remove_choice(id); dialog.queue_free())
			remove.position = Vector2(25, 510) # 检视底部操作位置
		else:
			var free_slot := _first_free_slot(String(card.card_id))
			if free_slot >= 0:
				var select := Style.button(body, "选择入藏 → 空位%d" % (free_slot + 1), "SelectCandidateButton", func(): _add_choice(id, free_slot); dialog.queue_free())
				select.disabled = progress.run.selection.size() >= 8
				select.position = Vector2(25, 510) # 空位入藏按钮位置
			else:
				for index: int in slots.size():
					if _target_used(String(card.card_id), index): continue
					var replace := Style.button(body, "替换此位…", "ReplaceSlot%dButton" % index, _confirm_replace.bind(id, index, dialog))
					replace.disabled = progress.run.selection.size() >= 8
					replace.position = Vector2(295 + index * 270, 510) # 各旧收藏卡正下方明确替换入口
					replace.custom_minimum_size.x = 230 # 替换按钮宽度
					replace.size = replace.custom_minimum_size
			if progress.run.selection.size() >= 8: _label(body, "已选满8张，请先取消其他选择。", Vector2(25, 505), 18)
	var close := Style.button(dialog, "关闭比较", "CloseComparisonButton", close_inspection)
	close.position = Vector2(910, 630) # 关闭入口与替换按钮同属底部操作区
	close.custom_minimum_size = Vector2(240, 42) # 关闭按钮紧凑尺寸
	close.size = close.custom_minimum_size


func _target_used(kind: String, slot: int) -> bool:
	for choice: Dictionary in progress.run.selection:
		if progress.run.candidates[choice.candidate_id].card_id == kind and int(choice.slot) == slot: return true
	return false


func _first_free_slot(kind: String) -> int:
	var size: int = progress.profile.collection.get(kind, []).size()
	for slot: int in range(size, 3):
		if not _target_used(kind, slot): return slot
	return -1


func _confirm_replace(id: String, slot: int, inspection: Control) -> void:
	var card: Dictionary = progress.run.candidates[id]
	var old: Dictionary = progress.profile.collection[card.card_id][slot]
	var dialog := ConfirmationDialog.new()
	dialog.name = "ReplaceConfirmation"
	dialog.theme = theme
	dialog.title = "再次确认替换关系"
	dialog.dialog_text = "新卡：%s\n将替换收藏位%d的旧卡：%s\n最终确认收藏成功后，旧卡永久移出；现在仍可返回改选。" % [_card_identity(card), slot + 1, _card_identity(old)]
	dialog.ok_button_text = "确认这组替换"
	dialog.cancel_button_text = "保留旧卡"
	inspection.add_child(dialog)
	dialog.confirmed.connect(func(): _add_choice(id, slot); inspection.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(850, 240)) # 明确新旧实例与固定位置的二次确认尺寸


func _add_choice(id: String, slot: int) -> void:
	var choices: Array = progress.run.selection.duplicate(true)
	var kind: String = progress.run.candidates[id].card_id
	var slots: Array = progress.profile.collection.get(kind, [])
	var choice := {"candidate_id": id, "slot": slot}
	if slot < slots.size(): choice.merge({"replacement_confirmed": true, "replaced_id": slots[slot].archive_id})
	choices.append(choice)
	selection_requested.emit(choices)


func _remove_choice(id: String) -> void:
	var choices: Array = progress.run.selection.filter(func(choice: Dictionary): return choice.candidate_id != id).duplicate(true)
	# 取消选择后空位重新按左到右填入；若有待替换卡，优先改入空位，保留旧收藏。
	var kind: String = progress.run.candidates[id].card_id
	var next: int = progress.profile.collection.get(kind, []).size()
	for choice: Dictionary in choices:
		if progress.run.candidates[choice.candidate_id].card_id != kind: continue
		if next >= 3: break
		choice.slot = next
		choice.erase("replaced_id")
		choice.erase("replacement_confirmed")
		next += 1
	selection_requested.emit(choices)


func _inspect(id: String) -> void:
	inspect_card(_cells[id].view, _decode(progress.run.candidates[id]))
