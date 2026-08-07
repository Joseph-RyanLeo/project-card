class_name BoardSlot
extends PanelContainer

signal slot_clicked(slot: BoardSlot)
signal click_carry_requested(data: Dictionary, pointer_global_position: Vector2)

const CARD_SIZE := Vector2(99, 136) # 当前单张裸卡在棋盘中的固定尺寸
const PREVIEW_ALPHA: float = 0.4 # 棋盘插入虚影的不透明度
const LAYOUT_TWEEN_DURATION: float = 0.15 # 卡牌随 Container 新布局让位或恢复的动画时长（秒）

var _card_data: CardData
var _preview_card_data: CardData
var _layout_tween: Tween

@onready var card_view: CardView = %CardView


func _ready() -> void:
	card_view.card_clicked.connect(_on_card_view_clicked)
	card_view.click_carry_requested.connect(_on_click_carry_requested)
	_refresh()


func _gui_input(event: InputEvent) -> void:
	if is_preview() and event is InputEventMouse:
		accept_event()


func set_card_data(value: CardData) -> void:
	_card_data = value
	_preview_card_data = null

	if is_node_ready():
		_refresh()


func get_card_data() -> CardData:
	return _card_data


func is_empty() -> bool:
	return _card_data == null


func set_preview_card(value: CardData) -> void:
	_card_data = null
	_preview_card_data = value

	if is_node_ready():
		_refresh()


func is_preview() -> bool:
	return _preview_card_data != null


func configure_drag_source(enabled: bool, source_row: Node = null) -> void:
	card_view.configure_drag_source(
		enabled and not is_preview(),
		&"board",
		source_row,
		self
	)


func animate_from_global_position(previous_global_position: Vector2) -> void:
	if not visible or is_preview():
		return

	if _layout_tween != null and _layout_tween.is_valid():
		_layout_tween.kill()

	var current_global_position := card_view.global_position
	card_view.position += previous_global_position - current_global_position
	_layout_tween = create_tween()
	_layout_tween.set_trans(Tween.TRANS_QUAD)
	_layout_tween.set_ease(Tween.EASE_OUT)
	_layout_tween.tween_property(
		card_view,
		"position",
		Vector2.ZERO,
		LAYOUT_TWEEN_DURATION
	)


func is_layout_animating() -> bool:
	return (
		_layout_tween != null
		and _layout_tween.is_valid()
		and _layout_tween.is_running()
	)


func _refresh() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	card_view.visible = not is_empty() or is_preview()
	card_view.modulate.a = PREVIEW_ALPHA if is_preview() else 1.0
	card_view.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
		if is_preview()
		else Control.MOUSE_FILTER_STOP
	)
	card_view.set_card_data(
		_preview_card_data if is_preview() else _card_data
	)


func _on_card_view_clicked(_card_data_value: CardData) -> void:
	if not is_preview():
		slot_clicked.emit(self)


func _on_click_carry_requested(
	data: Dictionary,
	pointer_global_position: Vector2
) -> void:
	if not is_preview():
		click_carry_requested.emit(data, pointer_global_position)
