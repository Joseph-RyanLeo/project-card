extends Control

## 局后选卡与展览馆共用只读检视；页面只传入卡面和实例，不在此写入存档。
const Style = preload("res://scripts/ui/menu_style.gd")
const Save = preload("res://scripts/data/run_save_service.gd")
const CARD = preload("res://scenes/ui/CardView.tscn")
const INSPECT_SCALE := 4.0 # 右键单卡检视固定4倍显示
const INSPECTION_OPEN_SECONDS := 0.28 # 卡片从原位放大到4倍的时长
const INSPECTION_CLOSE_SECONDS := 0.22 # 取消检视时卡牌缩回原位、蒙版淡出的时长
const DETAILS_ROW_SECONDS := 0.13 # 每行详情弹出并显现的时长
const DETAILS_ROW_STAGGER := 0.035 # 相邻详情行出现的间隔
const DETAILS_ROW_START_SCALE := 0.94 # 详情行从略小的尺寸弹出，不改动容器负责的排版位置
const INSPECTION_DIM_ALPHA := 0.68 # 检视时仍保留底层界面的蒙版深度
signal derived_preview_requested(source: CardData)
var derived_provider: Callable
var progress: RefCounted
var show_run_score := true
var _inspecting_base := false
var _inspection: Control
var _inspection_tween: Tween


func _label(parent: Node, title: String, at: Vector2, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = title
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _decode(card: Dictionary) -> OwnedCard:
	var decoded: Dictionary = Save.new()._decode_collection_state({"cards": [card]}, {}, false, false, Save.SCHEMA_VERSION, false, false)
	var owned := OwnedCard.new()
	owned.restore_state(decoded.state.cards[0])
	return owned


func _card_view(parent: Node, card: Dictionary, at: Vector2, factor: float) -> CardView:
	var view := CARD.instantiate() as CardView
	view.set_snapshot_mode(true)
	view.configure_drag_source(false)
	var owned := _decode(card)
	view.set_card_data(owned.card_data)
	view.set_owned_card(owned)
	parent.add_child(view)
	view.position = at
	view.scale = Vector2.ONE * factor

	return view


func basic_view(parent: Node, card: CardData, at: Vector2) -> CardView:
	var view := CARD.instantiate() as CardView
	view.set_snapshot_mode(true)
	view.configure_drag_source(false)
	view.set_card_data(card)
	parent.add_child(view)
	view.position = at
	preload("res://scripts/ui/collection_card_hover.gd").bind_read_only(view)
	var hit := view.get_node("ReadOnlyHoverHit") as Control
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.gui_input.connect(func(event: InputEvent):
		if not is_instance_valid(view) or not view.is_inside_tree(): return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			hit.accept_event()
			inspect_definition(view), CONNECT_DEFERRED)
	return view

func inspect_definition(view: CardView) -> void:
	if not is_instance_valid(view) or not view.is_inside_tree(): return
	var basic := OwnedCard.new()
	basic.card_data = view.card_data
	inspect_card(view, basic, true)


func _history_text(owned: OwnedCard) -> String:
	var source := owned.acquisition_source
	var kind := String(source.get("kind", ""))
	var origin := String({"initial": "起始物资", "starting": "起始物资", "starting_supplies": "起始物资", "pack": "卡包", "shop": "商店", "event": "事件", "battle_reward": "战斗奖励", "card_effect": "卡牌效果"}.get(kind, "未知"))
	if not String(source.get("name", "")).is_empty(): origin += " · " + String(source.name)
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var time := Time.get_datetime_string_from_unix_time(owned.acquired_at + bias).replace("T", " ") if owned.acquired_at > 0 else "未知"
	var hero := "伊奥恩" if owned.recruited_by == "ioann_warden" else (owned.recruited_by if not owned.recruited_by.is_empty() else "未知")
	var lines: Array[String] = ["获得：" + time, "来源：" + origin, "征召英雄：" + hero]
	const STAT_NAMES := {"damage_dealt": "伤害", "healing_done": "治疗", "armor_granted": "提供护甲", "damage_taken": "承受伤害", "kills": "击杀", "battles": "参战", "deaths": "阵亡", "mining_successes": "成功开采", "gold_generated": "产出金币"}
	var stats: Array[String] = []
	for key: String in STAT_NAMES:
		if owned.lifetime_stats.has(key):
			var value := float(owned.lifetime_stats[key])
			stats.append("%s %s" % [STAT_NAMES[key], str(int(value)) if value == floor(value) else str(snappedf(value, 0.01))])
	lines.append("战绩：" + ("，".join(stats) if not stats.is_empty() else "尚无记录"))
	return "\n".join(lines)


func _card_identity(card: Dictionary) -> String:
	var owned := _decode(card)
	var appearance := "%s / %s" % [CardAppearance.SURFACE_LABELS[int(owned.surface_finish)], CardAppearance.ART_LABELS[int(owned.art_finish)]]
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var time := Time.get_datetime_string_from_unix_time(owned.acquired_at + bias).replace("T", " ") if owned.acquired_at > 0 else "时间未知"
	return "%s（%s，%s获得）" % [owned.card_data.display_name, appearance, time]


func close_inspection(animated: bool = true) -> bool:
	if not is_instance_valid(_inspection): return false
	# 动画完成前保留检视引用，让显示壳继续消费Esc，避免连按时误退主菜单。
	if animated and _inspection.get_meta("closing", false): return true
	if _inspection_tween != null and _inspection_tween.is_valid(): _inspection_tween.kill()
	var overlay := _inspection
	var surface := overlay.get_node_or_null("CollectionInspectionSurface") as InspectionCardSurface
	if not animated or surface == null:
		overlay.hide()
		overlay.queue_free()
		_inspection = null
		_inspection_tween = null
		return true
	overlay.set_meta("opening", false)
	overlay.set_meta("closing", true)
	overlay.input_handler = func(_event: InputEvent): return true
	surface.tilt_locked = true
	surface.set_process(false)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspection_tween = overlay.create_tween().set_parallel(true)
	_inspection_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_inspection_tween.tween_property(surface, "position", overlay.get_meta("return_position"), INSPECTION_CLOSE_SECONDS)
	_inspection_tween.tween_property(surface, "scale", overlay.get_meta("return_scale"), INSPECTION_CLOSE_SECONDS)
	_inspection_tween.tween_method(surface.set_pointer_force, surface.force, Vector2.ZERO, INSPECTION_CLOSE_SECONDS)
	_inspection_tween.tween_property(overlay, "modulate:a", 0.0, INSPECTION_CLOSE_SECONDS)
	_inspection_tween.chain().tween_callback(func():
		overlay.hide()
		overlay.queue_free()
		_inspection = null
		_inspection_tween = null)
	return true


func inspect_card(source: CardView, owned: OwnedCard, basic: bool = false) -> void:
	_inspecting_base = basic
	close_inspection(false)
	var origin := source.get_global_transform_with_canvas() as Transform2D
	var initial_force := Vector2.ZERO
	var shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if shell != null:
		var hover: Control = shell.get_collection_hover_surface()
		if hover.source == source: initial_force = hover.force
		hover.release_collection()
	var overlay := preload("res://scripts/ui/card_inspection_overlay.gd").new()
	overlay.name = "CollectionInspection"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 200 # 检视覆盖滚动网格和左栏按钮
	overlay.set_meta("opening", true)
	add_child(overlay)
	_inspection = overlay
	overlay.close_requested.connect(close_inspection)
	var dim := ColorRect.new()
	dim.name = "InspectionDim"
	dim.color = Color(0, 0, 0, 0) # 由动画渐入半透明暗色蒙版，不替换底层场景
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	var view := CARD.instantiate() as CardView
	view.copy_snapshot_from(source)
	view.set_snapshot_mode(true)
	view.configure_drag_source(false)
	overlay.add_child(view)
	var surface := preload("res://scripts/ui/inspection_card_surface.gd").new()
	surface.name = "CollectionInspectionSurface"
	surface.render_scale = 4.0 # 大卡合成至少4倍精度
	overlay.add_child(surface)
	surface.setup(view, Callable(), view.get_sticker_tooltip)
	surface.position = origin * -surface.content_padding
	surface.scale = origin.get_scale()
	overlay.set_meta("return_position", surface.position)
	overlay.set_meta("return_scale", surface.scale)
	surface.tilt_locked = true
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.set_pointer_force(initial_force)
	var backing := Panel.new()
	backing.name = "InspectionInfoBacking"
	backing.position = Vector2(620, 32) # 详情区独立深色底板，避免背后的筛选文字与详情重叠
	backing.size = Vector2(610, 590) # 保留四周留白的详情底板尺寸
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backing.add_theme_stylebox_override("panel", Style.panel(Color(0.06, 0.085, 0.12, 0.96), Color(0.5, 0.43, 0.31, 0.55)))
	backing.modulate.a = 0
	overlay.add_child(backing)
	var right := Control.new()
	right.name = "InspectionDetails"
	right.position = Vector2(640, 50) # 大卡右侧的信息区起点
	right.size = Vector2(550, 570) # 信息区范围
	overlay.add_child(right)
	var title := _label(right, owned.card_data.display_name, Vector2.ZERO, 32)
	var subtitle := _label(right, "%s级 · %s · %s" % [owned.card_data.get_rarity_name(), owned.card_data.get_card_type_name(), owned.card_data.get_faction_name()], Vector2(0, 52), 20)
	for label: Label in [title, subtitle]: label.add_theme_font_override("font", preload("res://scripts/ui/card_text_display_settings.gd").readable_font())
	var tabs := TabBar.new()
	tabs.name = "InspectionTabs"
	tabs.position = Vector2(0, 94) # 详情与计分页签位置
	tabs.size = Vector2(550, 42) # 给两个页签明确宽度，避免压缩成滚动箭头
	tabs.add_theme_font_override("font", preload("res://scripts/ui/card_text_display_settings.gd").readable_font())
	tabs.add_tab("卡牌详情")
	if not basic: tabs.add_tab("积分构成")
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(tabs)
	var headers: Array = [title, subtitle, tabs]
	if derived_provider.is_valid():
		var derived: Array = derived_provider.call(owned.card_data)
		if not derived.is_empty():
			tabs.size.x = 280 # 给衍生入口留出右半行
			var related := Style.button(right, "衍生预览 · %d种" % derived.size(), "DerivedPreviewButton", func(): derived_preview_requested.emit(owned.card_data))
			related.position = Vector2(300, 94) # 详情页签旁的生成结果入口
			related.custom_minimum_size = Vector2(250, 42) # 与页签对齐的紧凑按钮
			related.size = related.custom_minimum_size
			related.add_theme_font_size_override("font_size", 18)
			headers.append(related)
	var scroll := ScrollContainer.new()
	scroll.name = "CardDetails"
	scroll.position = Vector2(0, 145) # 页签下的独立滚动正文
	scroll.size = Vector2(550, 395) # 长详情和计分说明的可视高度
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "DetailRows"
	body.custom_minimum_size.x = 510 # 正文换行宽度
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var close := Style.button(overlay, "关闭检视", "CloseCollectionInspection", close_inspection)
	close.position = Vector2(940, 640) # 关闭按钮位置
	close.custom_minimum_size.x = 240 # 关闭按钮宽度
	close.size = close.custom_minimum_size
	headers.append(close)
	for node: Control in headers: node.modulate.a = 0
	tabs.tab_changed.connect(func(index: int): scroll.scroll_vertical = 0; _populate_detail_rows(body, owned, index))
	_inspection_tween = overlay.create_tween().set_parallel(true)
	var opening := _inspection_tween
	opening.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	opening.tween_property(surface, "position", Vector2(48, 16), INSPECTION_OPEN_SECONDS)
	opening.tween_property(surface, "scale", Vector2.ONE * INSPECT_SCALE, INSPECTION_OPEN_SECONDS)
	opening.tween_method(surface.set_pointer_force, initial_force, Vector2.ZERO, INSPECTION_OPEN_SECONDS)
	opening.tween_property(dim, "color:a", INSPECTION_DIM_ALPHA, INSPECTION_OPEN_SECONDS)
	opening.chain().tween_callback(func():
		overlay.set_meta("opening", false)
		backing.create_tween().tween_property(backing, "modulate:a", 1.0, DETAILS_ROW_SECONDS)
		surface.tilt_locked = false
		surface.mouse_filter = Control.MOUSE_FILTER_STOP
		tabs.mouse_filter = Control.MOUSE_FILTER_STOP
		tabs.current_tab = 0
		_populate_detail_rows(body, owned, 0, headers))


func _populate_detail_rows(body: VBoxContainer, owned: OwnedCard, index: int, header: Array = []) -> void:
	for child: Node in body.get_children(): child.free()
	var text := _detail_text(owned) if index == 0 else _score_text(owned)
	var rows: Array = header.duplicate()
	for line: String in text.split("\n"):
		var row := _label(body, line, Vector2.ZERO, 20)
		row.add_theme_font_override("font", preload("res://scripts/ui/card_text_display_settings.gd").readable_font())
		row.custom_minimum_size.x = 510 # 每行按右侧信息区宽度换行
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.modulate.a = 0
		rows.append(row)
	_reveal_detail_rows(rows)


func _reveal_detail_rows(rows: Array) -> void:
	for index: int in rows.size():
		var row := rows[index] as Control
		if not is_instance_valid(row): continue
		# VBoxContainer始终独占行位置；Tween只修改不参与排版的显示属性。
		row.scale = Vector2.ONE * DETAILS_ROW_START_SCALE
		var reveal := row.create_tween().set_parallel(true)
		reveal.tween_property(row, "scale", Vector2.ONE, DETAILS_ROW_SECONDS).set_delay(index * DETAILS_ROW_STAGGER).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		reveal.tween_property(row, "modulate:a", 1.0, DETAILS_ROW_SECONDS).set_delay(index * DETAILS_ROW_STAGGER)


func _score_text(owned: OwnedCard) -> String:
	var score := preload("res://scripts/data/run_score_service.gd").card_score(owned)
	var parts: Dictionary = score.parts
	var text := "单卡基础积分：%d\n\n品级：%d\n卡面工艺：%d\n卡图工艺：%d\n纹章／伤势／贴纸：%d\n已揭晓／覆盖符文：%d\n单卡牌型：%d" % [int(score.total), int(parts.grade), int(parts.surface), int(parts.art), int(parts.stickers), int(parts.runes), int(parts.pattern)]
	var summary: Dictionary = progress.run.get("summary", {})
	if show_run_score and not summary.is_empty():
		text += "\n\n本局倍率：%.1f\n参与整局倍率后的分值：%.1f" % [float(summary.multiplier_tenths) / 10.0, int(score.total) * float(summary.multiplier_tenths) / 10.0]
	text += "\n\n最终积分在整局总基础分乘倍率后统一向下取整，单卡不单独取整或再次入账。"
	return text


func _detail_text(owned: OwnedCard) -> String:
	var card := owned.card_data
	if _inspecting_base:
		var text := "基础图鉴 · 不代表已收藏实例\n"
		if card.card_type == CardData.CardType.MINION:
			var actions: Array[String] = []
			for action: int in (card.acquisition_action_types if not card.acquisition_action_types.is_empty() else [card.action_type]): actions.append(CardData.get_action_type_name_for(action as CardData.ActionType))
			text += "种族：%s　行动：%s\n数值 %d · 生命 %d · 护甲 %d\n" % [card.get_race_name(), " / ".join(actions), card.base_value, card.max_health, card.armor]
		var front := card.get_effect_text_for_row(&"player_front")
		var back := card.get_effect_text_for_row(&"player_back")
		text += "\n卡牌效果\n" + (front if not front.is_empty() else "无额外效果")
		if back != front and not back.is_empty(): text += "\n后排：" + back
		return text
	var lines: Array[String] = ["卡面：%s　卡图：%s" % [CardAppearance.SURFACE_LABELS[int(owned.surface_finish)], CardAppearance.ART_LABELS[int(owned.art_finish)]]]
	if card.card_type == CardData.CardType.MINION:
		lines.append("种族：%s　行动：%s" % [card.get_race_name(), CardData.get_action_type_name_for((owned.resolved_action_type if owned.resolved_action_type >= 0 else int(card.action_type)) as CardData.ActionType)])
	if card.card_type == CardData.CardType.MINION: lines.append("数值 %d · 生命 %d · 护甲 %d" % [owned.get_effective_base_value(), owned.get_effective_max_health(), owned.get_effective_base_armor()])
	if card.card_type == CardData.CardType.SPELL: lines.append("%s · 剩余次数：%s（入藏恢复全新次数）" % [card.get_spell_type_name(), "无限" if card.spell_durability_unlimited else str(owned.spell_durability)])
	if card.card_type == CardData.CardType.EQUIPMENT:
		lines.append("%s · 剩余耐久：%d" % [card.get_equipment_type_name(), owned.equipment_durability])
		lines.append("装备修正：数值 %+d · 生命 %+d · 护甲 %+d · 热诚 %s" % [card.equipment_action_delta, card.equipment_health_delta, card.equipment_armor_delta, ("+" if card.equipment_zeal_delta > 0 else "") + str(card.equipment_zeal_delta)])
	if not owned.permanent_growth.is_empty():
		var growth: Array[String] = []
		for key: String in ["base_value", "max_health", "base_armor"]:
			if owned.permanent_growth.has(key): growth.append("%s +%s" % [{"base_value": "数值", "max_health": "生命", "base_armor": "护甲"}[key], str(owned.permanent_growth[key])])
		if not growth.is_empty(): lines.append("永久成长：" + " / ".join(growth))
	lines.append("")
	lines.append("卡牌效果")
	var front := owned.get_effect_text_for_row(&"player_front")
	var back := owned.get_effect_text_for_row(&"player_back")
	lines.append(front if not front.is_empty() else "无额外效果")
	if back != front and not back.is_empty(): lines.append("后排：" + back)
	var runes: Array[String] = []
	for index: int in owned.rune_revealed.size():
		runes.append(card.get_element_type_name(owned.get_effective_rune(index)) if owned.rune_revealed[index] or not owned.rune_stickers[index].is_empty() else "未揭晓")
	lines.append("\n符文：" + " / ".join(runes))
	for pair: Array in [["纹章", owned.emblem_slots], ["伤势", owned.wound_slots], ["元素贴纸", owned.rune_stickers]]:
		var names: Array[String] = []
		for sticker: Dictionary in pair[1]:
			if not sticker.is_empty(): names.append(String(sticker.get("emblem_id", sticker.get("wound_id", ""))))
		if not names.is_empty(): lines.append(pair[0] + "：" + "、".join(names))
	lines.append("\n获得与累计战绩")
	lines.append(_history_text(owned))
	return "\n".join(lines)
