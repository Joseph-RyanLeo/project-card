extends "res://scripts/ui/read_only_card_inspector.gd"

## 资源、贴纸和生成源预览共用双页排版；所有状态都只属于当前页面。
signal return_requested
const Catalog = preload("res://scripts/data/gallery_catalog.gd")
const Unknown = preload("res://scripts/ui/gallery_unknown_card.gd")
const PAGE_SIZE := Vector2(580, 526) # 与收藏册保持相同单页尺寸
const COLUMNS := 4 # 每行四种独立图鉴条目，不展示实际收藏位
const ROWS := 3 # 每页三行，双页最多二十四种条目
const COLUMN_STEP := 134.0 # 相邻独立图鉴条目的横向距离
const ROW_STEP := 154.0 # 与收藏册卡面行距一致
const SILHOUETTE_SHADER := "shader_type canvas_item; void fragment(){ vec4 pixel = texture(TEXTURE, UV); COLOR = vec4(vec3(0.20, 0.25, 0.31), pixel.a); }"
var catalog: RefCounted
var mode := 1 # 1为资源，2为贴纸，3为生成源预览
var derived_cards: Array[CardData] = []
var source_name := ""
var page_index := 0
var entries: Array = []
var views: Array[CardView] = []
var _pages: Array[Control] = []
var _nodes: Array[Node] = []
var _category: OptionButton
var _search: LineEdit
var _counter: Label
var _page_label: Label
var _empty: Label
var _previous: Button
var _next: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_run_score = false
	if catalog == null: catalog = Catalog.new()
	if mode == 3:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var dim := ColorRect.new()
		dim.color = Color(0.02, 0.03, 0.05, 1.0) # 生成源预览遮住下层检视，避免信息重叠
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
		_label(self, source_name + " · 衍生卡预览", Vector2(48, 24), 28)
		_label(self, "仅预览基础版本 · 查看不会增加发现或收藏", Vector2(48, 78), 18)
		var back := Style.button(self, "返回生成源", "DerivedReturn", return_requested.emit)
		back.position = Vector2(990, 64) # 沿用图鉴返回入口位置
		back.size = Vector2(240, 44) # 生成源返回按钮尺寸
	else:
		_category = OptionButton.new()
		_category.name = "ReferenceCategory"
		_category.position = Vector2(48, 72) # 分类与收藏册筛选栏对齐
		_category.size = Vector2(310, 36) # 资源标题／贴纸类别宽度
		_category.add_theme_font_size_override("font_size", 17)
		for title: String in (["资源图鉴 · 基础版本"] if mode == 1 else ["纹章图鉴", "伤势图鉴", "元素贴纸图鉴"]): _category.add_item(title)
		_category.disabled = mode == 1
		_category.item_selected.connect(_refresh)
		add_child(_category)
		_search = LineEdit.new()
		_search.name = "ReferenceSearch"
		_search.position = Vector2(374, 72) # 已发现范围搜索起点
		_search.size = Vector2(600, 36) # 保留右侧返回按钮区域
		_search.placeholder_text = "搜索已发现名称／效果"
		_search.add_theme_font_size_override("font_size", 17)
		_search.text_changed.connect(_refresh)
		add_child(_search)
	for side: int in 2:
		var page := Panel.new()
		page.position = Vector2(48 + side * 604, 120) # 双页位置与卡牌收藏册一致
		page.size = PAGE_SIZE
		page.add_theme_stylebox_override("panel", Style.panel(Color("182027"), Color("74634b")))
		add_child(page)
		_pages.append(page)
		_label(page, "资源图鉴" if mode == 1 else ("贴纸图鉴" if mode == 2 else "衍生卡 · 基础版本"), Vector2(28, 13), 16)
	_empty = _label(self, "本档尚无可展示的条目", Vector2(420, 330), 22)
	_empty.size = Vector2(440, 90) # 空结果提示居中
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter = _label(self, "", Vector2(50, 670), 15)
	_previous = _button("上一页", "ReferencePrevious", Vector2(818, 660), change_page.bind(-1))
	_page_label = _label(self, "", Vector2(946, 666), 18)
	_page_label.size = Vector2(154, 36) # 页码固定宽度
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next = _button("下一页", "ReferenceNext", Vector2(1108, 660), change_page.bind(1))
	_refresh()

func _button(title: String, id: String, at: Vector2, action: Callable) -> Button:
	var button := Style.button(self, title, id, action)
	button.position = at
	button.custom_minimum_size = Vector2(124, 44) # 紧凑翻页按钮大小
	button.size = button.custom_minimum_size
	button.add_theme_font_size_override("font_size", 18)
	return button

func _refresh(_value: Variant = null) -> void:
	page_index = 0
	if mode == 1: entries = catalog.visible_resources(progress.profile, _search.text)
	elif mode == 2: entries = catalog.visible_stickers(progress.profile, ["emblem", "wound", "rune"][_category.selected], _search.text)
	else: entries = derived_cards.duplicate()
	_draw_page()

func page_count() -> int:
	return ceili(float(entries.size()) / (COLUMNS * ROWS * 2))

func change_page(direction: int) -> void:
	if is_instance_valid(_inspection): return
	page_index = clampi(page_index + direction, 0, maxi(0, page_count() - 1))
	_draw_page()

func _draw_page() -> void:
	close_inspection(false)
	var shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if shell != null: shell.get_collection_hover_surface().release_collection()
	for node: Node in _nodes: node.free()
	_nodes.clear()
	views.clear()
	var first := page_index * COLUMNS * ROWS * 2
	var shown := entries.slice(first, first + COLUMNS * ROWS * 2)
	for index: int in shown.size():
		var parent := _pages[index / (COLUMNS * ROWS)]
		var local := index % (COLUMNS * ROWS)
		var at := Vector2(28 + (local % COLUMNS) * COLUMN_STEP, 54 + (local / COLUMNS) * ROW_STEP)
		if mode == 2: _sticker(parent, shown[index], at)
		else:
			var card := shown[index] as CardData
			if mode == 3 or catalog.resource_discovered(card, progress.profile):
				var view := basic_view(parent, card, at)
				_nodes.append(view)
				views.append(view)
			else:
				var hint := Unknown.new()
				parent.add_child(hint)
				hint.setup(card)
				hint.position = at
				_nodes.append(hint)
	var count := page_count()
	_page_label.text = "第 %d / %d 页" % [page_index + 1 if count else 0, count]
	_previous.disabled = page_index == 0
	_next.disabled = count == 0 or page_index + 1 >= count
	_empty.visible = entries.is_empty()
	if mode == 1:
		var known := 0
		for card: CardData in catalog.resources:
			if catalog.resource_discovered(card, progress.profile): known += 1
		_counter.text = "资源发现 %d / %d · 右键 4×检视" % [known, catalog.resources.size()]
	elif mode == 2:
		var known := 0
		for entry: Dictionary in catalog.stickers:
			if catalog.sticker_discovered(entry, progress.profile): known += 1
		_counter.text = "贴纸发现 %d / %d · 右键查看详情" % [known, catalog.stickers.size()]
	else: _counter.text = "衍生卡不设收藏位 · Esc 返回上一层"

func _sticker(parent: Control, entry: Dictionary, at: Vector2) -> void:
	var known: bool = catalog.sticker_discovered(entry, progress.profile)
	var tile := Panel.new()
	tile.name = "KnownSticker" if known else "UnknownSticker"
	tile.position = at
	tile.size = Vector2(112, 136) # 贴纸条目与卡面保持相近体积
	tile.add_theme_stylebox_override("panel", Style.panel(Color("141a21"), Color("494332")))
	parent.add_child(tile)
	_nodes.append(tile)
	var icon := TextureRect.new()
	icon.texture = catalog.sticker_texture(entry)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon.texture != null:
		icon.scale = Vector2.ONE * (2 if entry.category == "rune" else 3) # 元素贴纸二倍、纹章伤势三倍整数放大
		icon.position = ((tile.size - icon.texture.get_size() * icon.scale) * 0.5).floor()
	if not known:
		var material := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = SILHOUETTE_SHADER
		material.shader = shader
		icon.material = material
	else:
		icon.position.y = 24 # 已发现贴纸图案上移，为名称及稀有度留白
		var title := _label(tile, entry.name, Vector2(4, 90), 16)
		title.size.x = 104 # 中文名称在条目内居中
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if entry.rarity >= 0:
			var rarity := _label(tile, ["I", "II", "III", "IV", "V"][entry.rarity] + "级", Vector2(4, 113), 14)
			rarity.size.x = 104 # 品级文字居中
			rarity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tile.tooltip_text = catalog.sticker_text(entry)
		tile.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				tile.accept_event()
				inspect_sticker.call_deferred(entry))
	tile.add_child(icon)

func inspect_sticker(entry: Dictionary) -> void:
	if not catalog.sticker_open(entry, progress.profile) or not catalog.sticker_discovered(entry, progress.profile): return
	close_inspection(false)
	var overlay := preload("res://scripts/ui/card_inspection_overlay.gd").new()
	overlay.name = "StickerInspection"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 200 # 贴纸详情覆盖双页
	add_child(overlay)
	_inspection = overlay
	overlay.close_requested.connect(close_inspection)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8) # 贴纸详情蒙版浓度
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	var panel := Panel.new()
	panel.position = Vector2(180, 110) # 贴纸详情居中位置
	panel.size = Vector2(920, 480) # 贴纸详情可读区域
	panel.add_theme_stylebox_override("panel", Style.panel(Color("182027"), Color("74634b")))
	overlay.add_child(panel)
	var image := TextureRect.new()
	image.texture = catalog.sticker_texture(entry)
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.position = Vector2(45, 70) # 大图与正文分栏
	image.scale = Vector2.ONE * 6 # 保持整数倍像素放大
	panel.add_child(image)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(260, 40) # 右侧独立滚动详情起点
	scroll.size = Vector2(610, 350) # 长效果文本可滚动
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var text := _label(scroll, catalog.sticker_text(entry), Vector2.ZERO, 24)
	text.add_theme_font_override("font", preload("res://scripts/ui/card_text_display_settings.gd").readable_font())
	text.custom_minimum_size.x = 570 # 可读字体正文换行宽度
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var close := _button("关闭详情", "StickerClose", Vector2(900, 610), close_inspection)
	remove_child(close)
	overlay.add_child(close)

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or is_instance_valid(_inspection): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		change_page(-1 if event.keycode == KEY_PAGEUP else 1)
		get_viewport().set_input_as_handled()
