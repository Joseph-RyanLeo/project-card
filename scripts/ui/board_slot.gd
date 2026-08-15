class_name BoardSlot
extends SquadView

## 战场行中的一个真实小队槽。
## 它复用 SquadView 的显示与交互，只补充“被战场点击”和单卡兼容入口。

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
