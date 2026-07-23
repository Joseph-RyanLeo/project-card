class_name BoardSlot
extends PanelContainer

signal slot_clicked(slot: BoardSlot)

const CARD_SIZE := Vector2(99, 136)
const COMPACT_EMPTY_SIZE := Vector2(18, 136)

var _card_data: CardData
var _compact_empty: bool = false

@onready var empty_state_label: Label = %EmptyStateLabel
@onready var card_view: CardView = %CardView


func _ready() -> void:
	card_view.card_clicked.connect(_on_card_view_clicked)
	_refresh()


func _gui_input(event: InputEvent) -> void:
	if not is_empty() or not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		slot_clicked.emit(self)
		accept_event()


func set_card_data(value: CardData) -> void:
	_card_data = value
	_compact_empty = false

	if is_node_ready():
		_refresh()


func get_card_data() -> CardData:
	return _card_data


func is_empty() -> bool:
	return _card_data == null


func set_compact_empty(value: bool) -> void:
	_compact_empty = value

	if is_node_ready():
		_refresh()


func _refresh() -> void:
	var target_size := COMPACT_EMPTY_SIZE if is_empty() and _compact_empty else CARD_SIZE
	custom_minimum_size = target_size
	size = target_size
	card_view.visible = not is_empty()
	empty_state_label.visible = is_empty()
	empty_state_label.text = "+" if _compact_empty else "点击放置"
	card_view.set_card_data(_card_data)


func _on_card_view_clicked(_card_data_value: CardData) -> void:
	slot_clicked.emit(self)
