extends Control

const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/ui/CardView.tscn")

enum GamePhase {
	PREPARE,
	BATTLE,
	RESULT,
}

var current_phase: GamePhase = GamePhase.PREPARE
var selected_card: CardData

@export var hand_cards: Array[CardData] = []
@export var card_preview_scale: float = 3.0
@export var hand_card_scale: float = 1.2

@onready var phase_label: Label = %PhaseLabel
@onready var play_area_label: Label = %PlayAreaLabel
@onready var card_preview_frame: Control = %CardPreviewFrame
@onready var selected_card_view: CardView = %SelectedCardView
@onready var hand_card_row: HBoxContainer = %HandCardRow
@onready var start_battle_button: Button = %StartBattleButton


func _ready() -> void:
	start_battle_button.pressed.connect(_on_start_battle_button_pressed)
	_apply_card_preview_scale()
	_build_hand_cards()
	_select_first_hand_card()
	_update_phase_label()


func _on_start_battle_button_pressed() -> void:
	match current_phase:
		GamePhase.PREPARE:
			current_phase = GamePhase.BATTLE
		GamePhase.BATTLE:
			current_phase = GamePhase.RESULT
		GamePhase.RESULT:
			current_phase = GamePhase.PREPARE
	_update_phase_label()


func _update_phase_label() -> void:
	match current_phase:
		GamePhase.PREPARE:
			phase_label.text = "准备阶段"
			start_battle_button.text = "开始战斗"
		GamePhase.BATTLE:
			phase_label.text = "战斗阶段"
			start_battle_button.text = "结束战斗"
		GamePhase.RESULT:
			phase_label.text = "结算阶段"
			start_battle_button.text = "回到准备"


func _apply_card_preview_scale() -> void:
	var scaled_size := selected_card_view.card_size * card_preview_scale
	card_preview_frame.custom_minimum_size = scaled_size
	card_preview_frame.size = scaled_size
	selected_card_view.position = Vector2.ZERO
	selected_card_view.scale = Vector2(card_preview_scale, card_preview_scale)


func _build_hand_cards() -> void:
	for child: Node in hand_card_row.get_children():
		child.queue_free()

	for hand_card: CardData in hand_cards:
		var slot := Control.new()
		slot.custom_minimum_size = selected_card_view.card_size * hand_card_scale
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var card_view := CARD_VIEW_SCENE.instantiate() as CardView
		card_view.position = Vector2.ZERO
		card_view.scale = Vector2(hand_card_scale, hand_card_scale)
		card_view.set_card_data(hand_card)
		card_view.card_clicked.connect(_on_hand_card_clicked)

		slot.add_child(card_view)
		hand_card_row.add_child(slot)


func _select_first_hand_card() -> void:
	if hand_cards.is_empty():
		_select_card(null)
		return

	_select_card(hand_cards[0])


func _on_hand_card_clicked(card_data: CardData) -> void:
	_select_card(card_data)


func _select_card(card_data: CardData) -> void:
	selected_card = card_data

	if selected_card == null:
		play_area_label.text = "手牌/收藏区没有绑定测试卡牌"
		selected_card_view.set_card_data(null)
		return

	play_area_label.text = "当前选中：%s。右键卡牌可以切换符文/效果文本" % selected_card.display_name
	selected_card_view.set_card_data(selected_card)
