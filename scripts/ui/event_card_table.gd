extends Control

## 牌堆、模态三选一、落位演出共用真实事件牌；正式选择仍由协调器保存。
signal path_chosen(id: String)
const CardView = preload("res://scripts/ui/event_card_view.gd")
const Art = preload("res://scripts/ui/tabletop_art.gd")
const Header = preload("res://scripts/ui/tabletop_header.gd")
const Dust = preload("res://scripts/ui/event_landing_dust.gd")
const TABLE_SIZE := Vector2(902, 351) # 新事件棋盘原生大小
const SELECTED_POSITION := Vector2(116, 108) # 描述状态的事件牌左上角
const DECK_POSITION := Vector2(368, 88) # 中央牌堆的原稿位置
const CHOICE_SCALE: float = 2.0 # 模态三张牌固定按原图2倍展示
const CHOICE_GAP: float = 36.0 # 三张放大牌之间的水平空隙
const DEAL_SECONDS: float = 0.32 # 每张牌从牌堆飞至屏幕中央的时长
const DEAL_INTERVAL: float = 0.10 # 三张牌依次飞出的时间差
const FLIP_SECONDS: float = 0.14 # 翻牌收拢和展开各自的时长
const BOARD_SECONDS: float = 0.30 # 旧棋盘退场和描述棋盘落下的时长
const MOVE_SECONDS: float = 0.34 # 选中牌缩回原生尺寸并落入左侧卡位的时长
const DETAIL_SECONDS: float = 0.38 # 描述和操作选项逐渐浮现的时长
const DIM_ALPHA: float = 0.70 # 三选一时除候选牌及暗示外的背景压暗程度
var main: Control
var cards: Array[Button] = []
var detail_body: VBoxContainer
var busy: bool = false
var _paths: Array[Dictionary] = []
var _board: Control
var _modal: Control
var _dim: ColorRect
var _deck: Button
var _hints: Array[Label] = []

func _board_surface() -> Control:
	var board := Control.new()
	board.size = TABLE_SIZE
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	Art.art(board, "event_board.png", Vector2.ZERO)
	var header := Header.new()
	header.main = main
	board.add_child(header)
	return board

func show_choices(paths: Array[Dictionary], _animate: bool) -> void:
	custom_minimum_size = TABLE_SIZE
	size = TABLE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paths = paths.duplicate(true)
	_board = _board_surface()
	_deck = Button.new()
	_deck.name = "EventDeck"
	_deck.position = DECK_POSITION
	_deck.size = Vector2(166, 153) # 整个牌堆含下方叠牌厚度均可点击
	_deck.tooltip_text = "点击牌堆，抽取三张事件牌"
	for state: String in ["normal", "hover", "pressed", "focus"]:
		_deck.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_board.add_child(_deck)
	Art.art(_deck, "event_deck.png", Vector2.ZERO)
	_deck.pressed.connect(_deal)

func _deal() -> void:
	if busy or is_instance_valid(_modal): return
	busy = true
	main._cancel_click_carry()
	main._close_toolbox_inspection(false)
	_deck.disabled = true
	_modal = Control.new()
	_modal.name = "EventChoiceOverlay"
	_modal.top_level = true
	_modal.position = Vector2.ZERO
	_modal.size = Vector2(1280, 720) # 模态层使用逻辑画布，不随世界视角移动
	_modal.z_as_relative = false
	_modal.z_index = 2800 # 三张牌高于背景暗幕，仍低于检视与Esc菜单
	add_child(_modal)
	_dim = ColorRect.new()
	_dim.size = _modal.size
	_dim.color = Color(0, 0, 0, 0)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.add_child(_dim)
	var dim_tween := create_tween()
	dim_tween.tween_property(_dim, "color:a", DIM_ALPHA, DEAL_SECONDS + DEAL_INTERVAL * 2)
	var card_size := CardView.CARD_SIZE * CHOICE_SCALE
	var total_width := card_size.x * _paths.size() + CHOICE_GAP * (_paths.size() - 1)
	var start := Vector2((1280.0 - total_width) * 0.5, (720.0 - card_size.y) * 0.5)
	for index: int in _paths.size():
		var card := CardView.new()
		card.name = "EventChoice%d" % index
		card.definition = _paths[index]
		_modal.add_child(card)
		card.pivot_offset = Vector2.ZERO
		card.position = _board.global_position + DECK_POSITION
		card.scale = Vector2.ONE
		card.disabled = true
		card.pressed.connect(_choose.bind(index))
		cards.append(card)
		var destination := start + Vector2(index * (card_size.x + CHOICE_GAP), 0)
		var hint := Label.new()
		hint.name = "EventHint%d" % index
		hint.text = String(_paths[index].hint)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.position = destination + Vector2(0, card_size.y + 14) # 普通暗示跟随各牌显示在下方
		hint.size = Vector2(card_size.x, 72) # 每张牌的文字暗示最多显示三行
		hint.add_theme_font_size_override("font_size", 16) # 三选一暗示字号
		hint.modulate.a = 0.0
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_modal.add_child(hint)
		_hints.append(hint)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(card, "position", destination, DEAL_SECONDS).set_delay(index * DEAL_INTERVAL).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "scale", Vector2.ONE * CHOICE_SCALE, DEAL_SECONDS).set_delay(index * DEAL_INTERVAL)
		tween.tween_property(hint, "modulate:a", 1.0, DEAL_SECONDS).set_delay(index * DEAL_INTERVAL)
	var unlock := create_tween()
	unlock.tween_interval(DEAL_SECONDS + (_paths.size() - 1) * DEAL_INTERVAL)
	unlock.tween_callback(_unlock_cards)

func _unlock_cards() -> void:
	busy = false
	for card: Button in cards: card.disabled = false

func _choose(index: int) -> void:
	if busy: return
	busy = true
	for card: Button in cards: card.disabled = true
	var selected: Button = cards[index]
	# 选中瞬间开始退场；候选牌仍位于独立屏幕层，不跟着旧棋盘飞走。
	var leave := create_tween().set_parallel(true)
	leave.tween_property(_board, "position:y", -TABLE_SIZE.y - 16, BOARD_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	for other: int in cards.size():
		if other == index: continue
		leave.tween_property(cards[other], "position", cards[other].position + Vector2(-700 if other < index else 700, -420), BOARD_SECONDS)
		leave.tween_property(cards[other], "rotation", -0.45 if other < index else 0.45, BOARD_SECONDS)
		leave.tween_property(cards[other], "modulate:a", 0.0, BOARD_SECONDS)
	for hint: Label in _hints: leave.tween_property(hint, "modulate:a", 0.0, FLIP_SECONDS)
	var pivot := CardView.CARD_SIZE * 0.5
	selected.position += pivot * selected.scale
	selected.pivot_offset = pivot
	selected.position -= pivot
	var flip := create_tween()
	flip.tween_property(selected, "scale:x", 0.0, FLIP_SECONDS)
	flip.tween_callback(func(): selected.face_up = true)
	flip.tween_property(selected, "scale:x", CHOICE_SCALE, FLIP_SECONDS)
	await flip.finished
	var description := _board_surface()
	description.name = "IncomingEventBoard"
	description.position.y = -TABLE_SIZE.y - 16
	Art.art(description, "event_description.png", Vector2(311, 57))
	var arrive := create_tween().set_parallel(true)
	arrive.tween_property(description, "position:y", 0.0, BOARD_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	arrive.tween_property(_dim, "color:a", 0.0, BOARD_SECONDS)
	await arrive.finished
	var move := create_tween().set_parallel(true)
	move.tween_property(selected, "position", global_position + SELECTED_POSITION, MOVE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	move.tween_property(selected, "scale", Vector2.ONE, MOVE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move.finished
	# 提交后协调器会重建描述状态；烟尘交给描述页，避免旧页释放时中断。
	path_chosen.emit(String(selected.definition.path_id))

func show_selected(path: Dictionary, reveal: bool = false) -> void:
	custom_minimum_size = TABLE_SIZE
	size = TABLE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board = _board_surface()
	Art.art(_board, "event_description.png", Vector2(311, 57))
	var card := CardView.new()
	card.name = "SelectedEventCard"
	card.definition = path
	card.face_up = true
	card.disabled = true
	add_child(card)
	card.position = SELECTED_POSITION
	var scroll := ScrollContainer.new()
	scroll.name = "EventDescription"
	scroll.position = Vector2(368, 70) # 文字限制在纸张内部，左侧保留纸签装饰
	scroll.size = Vector2(466, 207) # 长介绍与选项在纸面内滚动，不撑大棋盘
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	detail_body = VBoxContainer.new()
	detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_body.add_theme_constant_override("separation", 8) # 描述和选项的垂直间隔
	scroll.add_child(detail_body)
	if reveal:
		var dust := Dust.new()
		dust.position = SELECTED_POSITION - Vector2(80, 70) # 粒子范围围绕牌边，避免烟团盖满卡图
		add_child(dust)
		detail_body.modulate.a = 0.0
		var fade := create_tween()
		fade.tween_interval(0.10)
		fade.tween_property(detail_body, "modulate:a", 1.0, DETAIL_SECONDS)
