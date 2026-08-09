class_name BoardSlot
extends SquadView

signal slot_clicked(slot: BoardSlot)

var card_view: CardView:
	get:
		return get_primary_card_view()


func _ready() -> void:
	super()
	squad_clicked.connect(_on_squad_clicked)


func set_card_data(value: CardData) -> void:
	set_squad_data(SquadData.from_card(value))


func is_empty() -> bool:
	return squad_data == null or squad_data.horizontal_cards.is_empty()


func _on_squad_clicked(_squad_view: SquadView, _card_data: CardData) -> void:
	if not is_preview():
		slot_clicked.emit(self)
