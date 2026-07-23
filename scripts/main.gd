extends Control

const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/ui/CardView.tscn")

enum GamePhase {
	PREPARE,
	BATTLE,
	RESULT,
}

var current_phase: GamePhase = GamePhase.PREPARE
var selected_card: CardData
var selected_board_row: BattlefieldRow
var selected_board_slot: BoardSlot

@export var hand_cards: Array[CardData] = []
@export var card_preview_scale: float = 3.0
@export var hand_card_scale: float = 1.2

@onready var phase_label: Label = %PhaseLabel
@onready var play_area_label: Label = %PlayAreaLabel
@onready var card_preview_frame: Control = %CardPreviewFrame
@onready var selected_card_view: CardView = %SelectedCardView
@onready var front_row: BattlefieldRow = %FrontRow
@onready var back_row: BattlefieldRow = %BackRow
@onready var hand_card_row: HBoxContainer = %HandCardRow
@onready var return_to_hand_button: Button = %ReturnToHandButton
@onready var start_battle_button: Button = %StartBattleButton


func _ready() -> void:
	start_battle_button.pressed.connect(_on_start_battle_button_pressed)
	return_to_hand_button.pressed.connect(_on_return_to_hand_button_pressed)
	_connect_board_rows()
	_apply_card_preview_scale()
	_build_hand_cards()
	_select_first_hand_card()
	_update_phase_label()
	_refresh_placement_targets()


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
	_refresh_placement_targets()


func _connect_board_rows() -> void:
	for row: BattlefieldRow in [front_row, back_row]:
		row.placement_requested.connect(_on_board_placement_requested)
		row.board_slot_clicked.connect(_on_board_slot_clicked)


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
	selected_board_row = null
	selected_board_slot = null
	_select_card(card_data)
	_refresh_placement_targets()


func _on_board_slot_clicked(row: BattlefieldRow, slot: BoardSlot) -> void:
	selected_board_row = row
	selected_board_slot = slot
	_select_card(slot.get_card_data())
	play_area_label.text = "已选择场上卡牌：%s。点击插入位置可以调整顺序或换排" % selected_card.display_name
	_refresh_placement_targets()


func _on_board_placement_requested(target_row: BattlefieldRow, insert_index: int) -> void:
	if current_phase != GamePhase.PREPARE or selected_card == null:
		return

	var moving_card := selected_card
	if selected_board_slot != null:
		if selected_board_row != target_row and not target_row.has_capacity_for_single_card():
			return

		var source_index := selected_board_row.get_slot_index(selected_board_slot)
		if selected_board_row == target_row and insert_index > source_index:
			insert_index -= 1
		selected_board_row.remove_card_slot(selected_board_slot)
	else:
		var hand_index := hand_cards.find(moving_card)
		if hand_index < 0 or not target_row.has_capacity_for_single_card():
			return
		hand_cards.remove_at(hand_index)
		_build_hand_cards()

	selected_board_slot = target_row.add_card(moving_card, insert_index)
	selected_board_row = target_row
	_select_card(moving_card)
	play_area_label.text = "已将 %s 放入%s，可继续点击插入位置调整" % [moving_card.display_name, target_row.row_title]
	_refresh_placement_targets()


func _on_return_to_hand_button_pressed() -> void:
	if current_phase != GamePhase.PREPARE or selected_board_row == null or selected_board_slot == null:
		return

	var returned_card := selected_board_row.remove_card_slot(selected_board_slot)
	if returned_card == null:
		return

	hand_cards.append(returned_card)
	selected_board_row = null
	selected_board_slot = null
	_build_hand_cards()
	_select_card(returned_card)
	play_area_label.text = "已将 %s 收回手牌，可重新选择位置放置" % returned_card.display_name
	_refresh_placement_targets()


func _refresh_placement_targets() -> void:
	var can_place := current_phase == GamePhase.PREPARE and selected_card != null
	for row: BattlefieldRow in [front_row, back_row]:
		var moving_within_row := selected_board_row == row and selected_board_slot != null
		row.set_placement_enabled(can_place and (row.has_capacity_for_single_card() or moving_within_row))

	return_to_hand_button.disabled = current_phase != GamePhase.PREPARE or selected_board_slot == null


func _select_card(card_data: CardData) -> void:
	selected_card = card_data

	if selected_card == null:
		play_area_label.text = "手牌/收藏区没有绑定测试卡牌"
		selected_card_view.set_card_data(null)
		return

	play_area_label.text = "当前选中：%s。点击棋盘插入位置进行放置" % selected_card.display_name
	selected_card_view.set_card_data(selected_card)
