extends "res://scripts/ui/read_only_card_inspector.gd"

## 完整卡牌收藏册只读取ProfileProgress；分类、筛选和翻页都只更新当前可见双页。
signal return_requested
const Catalog = preload("res://scripts/data/gallery_catalog.gd")
const ReferenceBook = preload("res://scripts/ui/gallery_reference_book.gd")
const Unknown = preload("res://scripts/ui/gallery_unknown_card.gd")
const PAGE_SIZE := Vector2(580, 526) # 已确认的单页宽高，保留三行卡与留白
const BOOK_ORIGIN := Vector2(48, 120) # 双页收藏册左上角
const PAGE_GAP := 24.0 # 中央书脊留白
const ROWS_PER_PAGE := 3 # 每侧三行，一张双页展示六种卡
const ROW_HEIGHT := 154.0 # 相邻两行卡面顶边距离
const COLUMN_X := [28.0, 178.0, 304.0, 430.0] # 基础卡、收藏位一二三的横向起点
const ROW_TOP := 54.0 # 页眉到首行卡面的留白
const FILTER_HEIGHT := 36.0 # 顶部分类、筛选和搜索控件高度
const FILTER_FONT_SIZE := 17 # 顶部控件字号，给中文分类名称留出空间
var slot_index: int
var catalog := Catalog.new()
var shown_cards: Array[CardData] = []
var views: Dictionary = {}
var page_index := 0
var filtered_cards: Array[CardData] = []
var _pack: StringName
var _pack_ids: Array[StringName] = []
var _pages: Array[Control] = []
var _row_nodes: Array[Node] = []
var _pack_filter: OptionButton
var _race_filter: OptionButton
var _type_filter: OptionButton
var _search: LineEdit
var _progress_label: Label
var _page_label: Label
var _previous: Button
var _next: Button
var _clear: Button
var _empty: Label
var _sections: TabBar
var _card_controls: Array[Control] = []
var _reference: Control
var _derived_preview: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.make_theme()
	var popup_panel := Style.panel(Color("161e2a"), Color("74634b"))
	popup_panel.set_content_margin_all(6) # 下拉菜单边缘留白，与顶部紧凑控件一致
	theme.set_stylebox("panel", "PopupMenu", popup_panel)
	theme.set_stylebox("hover", "PopupMenu", Style.panel(Color("30333b"), Color("74634b")))
	theme.set_font_size("font_size", "PopupMenu", FILTER_FONT_SIZE)
	theme.set_color("font_color", "PopupMenu", Style.GOLD)
	theme.set_color("font_hover_color", "PopupMenu", Color("fff0c2"))
	show_run_score = false
	Style.add_background(self)
	_label(self, "展览馆 · 存档 %d" % (slot_index + 1), Vector2(48, 18), 30)
	_progress_label = _label(self, "", Vector2(50, 670), 15)
	var back := Style.button(self, "返回大厅", "GalleryReturnButton", return_requested.emit)
	back.position = Vector2(990, 64) # 顶部返回入口，与系统显示模式错开
	back.custom_minimum_size = Vector2(240, 44) # 返回按钮紧凑尺寸
	back.size = back.custom_minimum_size
	_build_filters()
	for side: int in 2:
		var page := Panel.new()
		page.name = "BookPage%d" % side
		page.position = BOOK_ORIGIN + Vector2(side * (PAGE_SIZE.x + PAGE_GAP), 0)
		page.size = PAGE_SIZE
		page.mouse_filter = Control.MOUSE_FILTER_PASS
		page.add_theme_stylebox_override("panel", Style.panel(Color("182027"), Color("74634b")))
		add_child(page)
		_pages.append(page)
		for col: int in 4:
			_label(page, "基础图鉴" if col == 0 else "收藏位 %d" % col, Vector2(COLUMN_X[col], 13), 16)
		var divider := ColorRect.new()
		divider.color = Color("494332")
		divider.position = Vector2(148, 14) # 基础图鉴和三个实际实例之间的分隔线位置
		divider.size = Vector2(1, PAGE_SIZE.y - 28) # 细线上下留白
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(divider)
	_empty = _label(self, "", Vector2(420, 330), 22)
	_empty.size = Vector2(440, 90) # 空结果提示在双页中部居中，避免贴近卡位标题
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_clear = _navigation_button("清除筛选", "GalleryClearFilters", Vector2(632, 660), clear_filters)
	_clear.custom_minimum_size.x = 154 # 清除筛选比翻页按钮略宽
	_clear.size.x = 154
	_previous = _navigation_button("上一页", "GalleryPreviousPage", Vector2(818, 660), change_page.bind(-1))
	_page_label = _label(self, "", Vector2(946, 666), 18)
	_page_label.size = Vector2(154, 36) # 页码区固定宽度，双位数页码也不会挤压按钮
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next = _navigation_button("下一页", "GalleryNextPage", Vector2(1108, 660), change_page.bind(1))
	derived_provider = func(card: CardData): return catalog.derived_for(card, progress.profile)
	derived_preview_requested.connect(_open_derived)
	_card_controls.assign([_pack_filter, _race_filter, _type_filter, _search, _progress_label, _empty, _clear, _previous, _page_label, _next])
	_card_controls.append_array(_pages)
	_sections = TabBar.new()
	_sections.name = "GallerySections"
	_sections.position = Vector2(370, 18) # 标题右侧三个图鉴入口
	_sections.size = Vector2(604, 38) # 三个页签横向区域
	for title: String in ["卡牌收藏册", "资源图鉴", "贴纸图鉴"]: _sections.add_tab(title)
	add_child(_sections)
	_sections.tab_changed.connect(_change_section)
	_filter_changed()

func _change_section(index: int) -> void:
	close_inspection(false)
	var shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if shell != null: shell.get_collection_hover_surface().release_collection()
	if is_instance_valid(_reference):
		_reference.free()
		_reference = null
	for control: Control in _card_controls: control.visible = index == 0
	if index == 0: return
	_reference = ReferenceBook.new()
	_reference.progress = progress
	_reference.catalog = catalog
	_reference.mode = index
	add_child(_reference)

func _open_derived(source: CardData) -> void:
	var linked := catalog.derived_for(source, progress.profile)
	if linked.is_empty() or not is_instance_valid(_inspection): return
	_inspection.set_process_input(false)
	_derived_preview = ReferenceBook.new()
	_derived_preview.name = "DerivedPreview"
	_derived_preview.progress = progress
	_derived_preview.catalog = catalog
	_derived_preview.mode = 3
	_derived_preview.source_name = source.display_name
	_derived_preview.derived_cards = linked
	_derived_preview.z_index = 400 # 生成结果覆盖源卡检视
	_derived_preview.return_requested.connect(_close_derived)
	add_child(_derived_preview)

func _close_derived() -> void:
	if is_instance_valid(_derived_preview):
		_derived_preview.close_inspection(false)
		_derived_preview.free()
		_derived_preview = null
	if is_instance_valid(_inspection): _inspection.set_process_input(true)
	var shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if shell != null: shell.get_collection_hover_surface().release_collection()

func close_inspection(animated: bool = true) -> bool:
	if is_instance_valid(_derived_preview):
		if animated:
			if not _derived_preview.close_inspection(): _close_derived()
			return true
		_close_derived()
	if is_instance_valid(_reference):
		var closed: bool = _reference.close_inspection(animated)
		if closed: return true
	return super.close_inspection(animated)

func _build_filters() -> void:
	_pack_ids = catalog.unlocked_packs(progress.profile)
	_pack_filter = _option("GalleryPackFilter", Vector2(48, 72), 250)
	for pack: StringName in _pack_ids: _pack_filter.add_item("卡包：" + CardPackRegistry.get_display_name(pack))
	if _pack_ids.is_empty():
		_pack_filter.add_item("尚无已开放卡包")
		_pack_filter.disabled = true
	else:
		_pack = _pack_ids[0]
	_pack_filter.item_selected.connect(func(index: int):
		_pack = _pack_ids[index]
		_filter_changed())
	_race_filter = _option("GalleryRaceFilter", Vector2(310, 72), 170)
	_race_filter.add_item("全部种族")
	var names := ["人类", "精灵", "矮人", "造物", "元素", "亡灵", "魔族", "野兽", "植物", "无种族"]
	for race: int in CardData.RaceType.values(): _race_filter.add_item(names[race])
	_race_filter.item_selected.connect(_filter_changed)
	_type_filter = _option("GalleryTypeFilter", Vector2(492, 72), 170)
	_type_filter.add_item("全部类型")
	for type: int in [CardData.CardType.MINION, CardData.CardType.EQUIPMENT, CardData.CardType.SPELL]:
		_type_filter.add_item({CardData.CardType.MINION: "随从", CardData.CardType.EQUIPMENT: "物品", CardData.CardType.SPELL: "法术"}[type])
	_type_filter.item_selected.connect(_filter_changed)
	_search = LineEdit.new()
	_search.name = "GallerySearch"
	_search.position = Vector2(674, 72) # 搜索框与顶部筛选排在同一行
	_search.size = Vector2(300, FILTER_HEIGHT) # 搜索框宽度容纳“已发现”范围提示
	_search.placeholder_text = "搜索已发现卡名／效果"
	_search.add_theme_font_size_override("font_size", FILTER_FONT_SIZE)
	_search.text_changed.connect(_filter_changed)
	add_child(_search)

func _option(node_name: String, at: Vector2, width: float) -> OptionButton:
	var filter := OptionButton.new()
	filter.name = node_name
	filter.position = at
	filter.size = Vector2(width, FILTER_HEIGHT)
	filter.fit_to_longest_item = false
	filter.add_theme_font_size_override("font_size", FILTER_FONT_SIZE)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := Style.panel(Color("161e2a"), Color("74634b"))
		style.set_content_margin_all(6) # 紧凑控件内距，不使用普通菜单的16px留白
		filter.add_theme_stylebox_override(state, style)
	add_child(filter)
	return filter

func _navigation_button(title: String, node_name: String, at: Vector2, action: Callable) -> Button:
	var button := Style.button(self, title, node_name, action)
	button.position = at
	button.custom_minimum_size = Vector2(124, 44) # 底部翻页按钮紧凑宽高
	button.size = button.custom_minimum_size
	button.add_theme_font_size_override("font_size", 18) # 导航字号与页码接近
	return button

func _filter_changed(_value: Variant = null) -> void:
	page_index = 0
	filtered_cards = catalog.filtered_cards(progress.profile, _pack, _race_filter.selected - 1, _type_filter.selected - 1, _search.text)
	_draw_page()

func clear_filters() -> void:
	_race_filter.select(0)
	_type_filter.select(0)
	_search.clear()
	_filter_changed()

func page_count() -> int:
	return ceili(float(filtered_cards.size()) / (ROWS_PER_PAGE * 2))

func change_page(direction: int) -> void:
	if is_instance_valid(_inspection) or is_instance_valid(_derived_preview): return
	var target := clampi(page_index + direction, 0, maxi(0, page_count() - 1))
	if target == page_index: return
	page_index = target
	_draw_page()

func _draw_page() -> void:
	close_inspection(false)
	var shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if shell != null: shell.get_collection_hover_surface().release_collection()
	for node: Node in _row_nodes: node.free()
	_row_nodes.clear()
	views.clear()
	var first := page_index * ROWS_PER_PAGE * 2
	shown_cards.assign(filtered_cards.slice(first, first + ROWS_PER_PAGE * 2))
	for index: int in shown_cards.size():
		var side := index / ROWS_PER_PAGE
		var row := index % ROWS_PER_PAGE
		_build_row(_pages[side], shown_cards[index], ROW_TOP + row * ROW_HEIGHT)
	var total := page_count()
	_page_label.text = "第 %d / %d 页" % [page_index + 1 if total > 0 else 0, total]
	_previous.disabled = page_index == 0
	_next.disabled = total == 0 or page_index + 1 >= total
	_clear.disabled = _race_filter.selected == 0 and _type_filter.selected == 0 and _search.text.is_empty()
	_empty.visible = shown_cards.is_empty()
	_empty.text = "没有符合筛选的卡牌\n可清除筛选后继续浏览" if not _pack_ids.is_empty() else "本档尚无可展示的卡牌目录"
	var package := "本包发现 %d / %d · " % [catalog.count_discovered(progress.profile, _pack), catalog.count_total(_pack)] if not _pack.is_empty() else ""
	_progress_label.text = package + "全册发现 %d / %d" % [catalog.count_discovered(progress.profile), catalog.count_total()]

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or is_instance_valid(_inspection) or is_instance_valid(_reference): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		change_page(-1 if event.keycode == KEY_PAGEUP else 1)
		get_viewport().set_input_as_handled()

func _build_row(page: Control, card: CardData, y: float) -> void:
	var id := String(card.id)
	var known: bool = catalog.discovered(card, progress.profile)
	var slots: Array = progress.profile.collection.get(id, [])
	for column: int in 4:
		var at := Vector2(COLUMN_X[column], y)
		if column == 0:
			if known:
				var view := basic_view(page, card, at)
				_row_nodes.append(view)
				views[id + ":base"] = view
			else:
				var hint := Unknown.new()
				hint.name = "UnknownCard"
				page.add_child(hint)
				_row_nodes.append(hint)
				hint.position = at
				hint.setup(card)
		elif column <= slots.size():
			var view := _card_view(page, slots[column - 1], at, 1.0)
			_row_nodes.append(view)
			_bind_card(view, view.get_owned_card(), id + ":%d" % column)
		else:
			var empty := Panel.new()
			empty.name = "EmptyCollectionSlot"
			empty.position = at
			empty.size = Vector2(99, 136) # 空位边框沿用真实卡原生尺寸
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			empty.add_theme_stylebox_override("panel", Style.panel(Color("141a21"), Color("34383b")))
			page.add_child(empty)
			_row_nodes.append(empty)
			_label(empty, "空位", Vector2(32, 55), 16).modulate = Color("6c716f")

func _bind_card(view: CardView, owned: OwnedCard, key: String) -> void:
	views[key] = view
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preload("res://scripts/ui/collection_card_hover.gd").bind_read_only(view)
	var hit := view.get_node("ReadOnlyHoverHit") as Control
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.gui_input.connect(func(event: InputEvent):
		if not is_instance_valid(view) or not view.is_inside_tree(): return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			inspect_card(view, owned)
			hit.accept_event(), CONNECT_DEFERRED)
