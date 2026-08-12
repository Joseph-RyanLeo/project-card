extends Control

const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/ui/CardView.tscn")
# 手牌放大到最大交互比例时，也要容纳左侧 8px、顶部 4px、
# 右侧 5px 的越界图标，避免 ScrollContainer 把它们裁掉。
const HAND_CARD_SAFE_PADDING := Vector2(14, 11) # 手牌槽四周预留空间，避免放大和越界图标被裁切

enum GamePhase {
	PREPARE,
	BATTLE,
	RESULT,
}

var current_phase: GamePhase = GamePhase.PREPARE
var selected_card: CardData
var selected_board_row: BattlefieldRow
var selected_board_slot: BoardSlot
var _hand_preview_slot: Control
var _hand_preview_insert_index: int = -1
var _click_carry_data: Dictionary = {}
var _click_carry_preview: Control
var _hand_layout_animation_revision: int = 0
var _active_hand_entry_animations: int = 0
var _battlefield_clock_check_queued: bool = false

@export var hand_cards: Array[CardData] = [] # 初始真实手牌及其排列顺序
@export var card_preview_scale: float = 2.0 # 左侧选中卡牌大预览的缩放倍率
@export var hand_card_scale: float = 1.0 # 手牌区域中卡牌的基础缩放倍率

@onready var phase_label: Label = %PhaseLabel
@onready var play_area_label: Label = %PlayAreaLabel
@onready var card_preview_frame: Control = %CardPreviewFrame
@onready var selected_card_view: CardView = %SelectedCardView
@onready var front_row: BattlefieldRow = %FrontRow
@onready var back_row: BattlefieldRow = %BackRow
@onready var hand_scroll: ScrollContainer = (
	$RootMargin/Layout/HandPanel/HandContent/HandScroll
)
@onready var hand_card_row: HBoxContainer = %HandCardRow
@onready var hand_drop_zone: Control = %HandDropZone
@onready var start_battle_button: Button = %StartBattleButton
@onready var card_art_tuner_button: Button = %CardArtTunerButton
@onready var drag_mode_button: Button = %DragModeButton


func _ready() -> void:
	if not _battlefield_has_active_rune_effects():
		CardView.reset_active_rune_flow()
	start_battle_button.pressed.connect(_on_start_battle_button_pressed)
	card_art_tuner_button.pressed.connect(_on_card_art_tuner_button_pressed)
	drag_mode_button.toggled.connect(_on_drag_mode_toggled)
	hand_drop_zone.connect("card_dropped", _on_hand_card_dropped)
	hand_drop_zone.connect("card_drag_hovered", _on_hand_card_drag_hovered)
	hand_drop_zone.connect("card_drag_exited", _clear_hand_drop_preview)
	_connect_board_rows()
	_apply_card_preview_scale()
	_build_hand_cards()
	_select_first_hand_card()
	_update_phase_label()
	_on_drag_mode_toggled(drag_mode_button.button_pressed)


func _on_drag_mode_toggled(prefer_minion: bool) -> void:
	drag_mode_button.text = (
		"拖拽：优先随从" if prefer_minion else "拖拽：优先小队"
	)
	for row: BattlefieldRow in [front_row, back_row]:
		row.set_prefer_minion(prefer_minion)


func _on_card_art_tuner_button_pressed() -> void:
	_cancel_click_carry()
	get_tree().change_scene_to_file("res://scenes/tools/CardArtTuner.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and is_node_ready():
		_clear_hand_drop_preview()


func _input(event: InputEvent) -> void:
	if _click_carry_data.is_empty():
		return

	if event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion
		_update_click_carry(motion_event.position)
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_commit_click_carry(mouse_event.position)
			get_viewport().set_input_as_handled()
		elif (
			mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_RIGHT
		):
			_cancel_click_carry()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			_cancel_click_carry()
			get_viewport().set_input_as_handled()


func _on_start_battle_button_pressed() -> void:
	_cancel_click_carry()
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
	_refresh_drag_availability()


func _connect_board_rows() -> void:
	for row: BattlefieldRow in [front_row, back_row]:
		row.board_slot_clicked.connect(_on_board_slot_clicked)
		row.card_dropped.connect(_on_board_card_dropped)
		row.squads_changed.connect(_on_battlefield_squads_changed)
		row.card_click_carry_requested.connect(
			_on_click_carry_requested
		)


func _on_battlefield_squads_changed() -> void:
	if _battlefield_clock_check_queued:
		return
	_battlefield_clock_check_queued = true
	_reset_rune_flow_if_no_battlefield_effects.call_deferred()


func _reset_rune_flow_if_no_battlefield_effects() -> void:
	_battlefield_clock_check_queued = false
	# 跨排移动会先移除后加入；延迟到事务结束再检查，避免中途误重置。
	if not _battlefield_has_active_rune_effects():
		CardView.reset_active_rune_flow()


func _battlefield_has_active_rune_effects() -> bool:
	for row: BattlefieldRow in [front_row, back_row]:
		for slot: BoardSlot in row.get_squads():
			for card_view: CardView in slot.get_card_views():
				if not card_view.get_highlighted_rune_indices().is_empty():
					return true
	return false


func _apply_card_preview_scale() -> void:
	var scaled_size := selected_card_view.card_size * card_preview_scale
	card_preview_frame.custom_minimum_size = scaled_size
	card_preview_frame.size = scaled_size
	selected_card_view.position = Vector2.ZERO
	selected_card_view.scale = Vector2(card_preview_scale, card_preview_scale)


func _build_hand_cards(
	entering_card: CardData = null,
	entry_global_position: Variant = null
) -> void:
	# 使重建前仍在等待下一帧的旧布局回调立即失效。
	_hand_layout_animation_revision += 1
	_hand_preview_slot = null
	_hand_preview_insert_index = -1
	for child: Node in hand_card_row.get_children():
		hand_card_row.remove_child(child)
		child.queue_free()

	for hand_card: CardData in hand_cards:
		var slot := _create_hand_card_slot(hand_card)
		var card_view := slot.get_child(0) as CardView
		hand_card_row.add_child(slot)
		if hand_card == entering_card and entry_global_position is Vector2:
			_animate_hand_card_entry.call_deferred(
				card_view,
				entry_global_position as Vector2
			)


func _create_hand_card_slot(
	card_data: CardData,
	is_preview: bool = false
) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = (
		selected_card_view.card_size * hand_card_scale
		+ HAND_CARD_SAFE_PADDING * 2.0
	)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.set_meta("is_hand_preview", is_preview)

	var card_view := CARD_VIEW_SCENE.instantiate() as CardView
	card_view.position = (
		HAND_CARD_SAFE_PADDING
		+ selected_card_view.card_size
		* (hand_card_scale - 1.0)
		* 0.5
	)
	card_view.scale = Vector2(hand_card_scale, hand_card_scale)
	card_view.set_card_data(card_data)
	if is_preview:
		card_view.modulate.a = 0.4
		card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_view.configure_drag_source(false)
	else:
		card_view.card_clicked.connect(_on_hand_card_clicked)
		card_view.click_carry_requested.connect(
			_on_click_carry_requested
		)
		card_view.hand_source_visibility_changing.connect(
			_on_hand_source_visibility_changing
		)
		card_view.configure_drag_source(
			current_phase == GamePhase.PREPARE,
			&"hand",
			null,
			slot
		)

	slot.add_child(card_view)
	return slot


func _select_first_hand_card() -> void:
	if hand_cards.is_empty():
		_select_card(null)
		return

	_select_card(hand_cards[0])


func _on_hand_card_clicked(card_data: CardData) -> void:
	selected_board_row = null
	selected_board_slot = null
	_select_card(card_data)
	_refresh_drag_availability()


func _on_board_slot_clicked(row: BattlefieldRow, slot: BoardSlot) -> void:
	selected_board_row = row
	selected_board_slot = slot
	_select_card(slot.get_last_clicked_card())
	play_area_label.text = "已选择场上卡牌：%s。准备阶段可拖动换序、换排或收回手牌" % selected_card.display_name
	_refresh_drag_availability()


func _on_click_carry_requested(
	drag_data: Dictionary,
	pointer_global_position: Vector2
) -> void:
	if (
		current_phase != GamePhase.PREPARE
		or not _click_carry_data.is_empty()
		or not _is_card_drag_data(drag_data)
	):
		return

	# 点击携带不会触发 Godot 的原生 DRAG_BEGIN；在这里主动完成与
	# 原生拖拽相同的战场悬停清理，避免上一张卡保持鼠标指向状态。
	for row: BattlefieldRow in [front_row, back_row]:
		row.reset_all_hover_feedback()
	_click_carry_data = drag_data.duplicate()
	_click_carry_preview = _create_click_carry_preview(
		_click_carry_data,
		pointer_global_position
	)
	_click_carry_data["drag_visual"] = _click_carry_preview
	_hide_click_carry_source()
	_update_click_carry(pointer_global_position)


func _create_click_carry_preview(
	drag_data: Dictionary,
	pointer_global_position: Vector2
) -> Control:
	var preview_root := CardView.create_drag_visual(drag_data)
	add_child(preview_root)
	preview_root.global_position = pointer_global_position
	return preview_root


func _hide_click_carry_source() -> void:
	var source_type := _click_carry_data.get("source_type") as StringName
	if source_type == &"hand":
		var source_slot := _click_carry_data.get("source_slot") as Control
		if (
			is_instance_valid(source_slot)
			and source_slot.get_parent() == hand_card_row
		):
			var previous_positions := _capture_hand_card_positions()
			source_slot.visible = false
			_animate_hand_layout_next_frame(previous_positions)
	elif source_type == &"board":
		var source_row := (
			_click_carry_data.get("source_row") as BattlefieldRow
		)
		if is_instance_valid(source_row):
			source_row._begin_card_drag(_click_carry_data)


func _update_click_carry(pointer_global_position: Vector2) -> void:
	if _click_carry_data.is_empty():
		return

	if is_instance_valid(_click_carry_preview):
		_click_carry_preview.global_position = pointer_global_position
	for row: BattlefieldRow in [front_row, back_row]:
		row.update_stack_target_feedback_global(
			pointer_global_position,
			_click_carry_data
		)

	var target_row := _find_board_row_at(pointer_global_position)
	if target_row != null:
		for row: BattlefieldRow in [front_row, back_row]:
			if row != target_row:
				row.clear_drop_preview(false)
		hand_drop_zone.clear_drop_preview()
		target_row.preview_card_drop(
			_to_row_drop_position(target_row, pointer_global_position),
			_click_carry_data
		)
	elif hand_drop_zone.get_global_rect().has_point(pointer_global_position):
		front_row.clear_drop_preview(false)
		back_row.clear_drop_preview(false)
		hand_drop_zone.preview_card_drop(
			pointer_global_position,
			_click_carry_data
		)
	else:
		_clear_click_drop_feedback(false)


func _commit_click_carry(pointer_global_position: Vector2) -> void:
	if _click_carry_data.is_empty():
		return

	_update_click_carry(pointer_global_position)
	var committed := false
	var target_row := _find_board_row_at(pointer_global_position)
	if target_row != null:
		var row_position := _to_row_drop_position(
			target_row,
			pointer_global_position
		)
		if (
			target_row.has_active_drop_preview()
			or target_row.preview_card_drop(row_position, _click_carry_data)
		):
			target_row.commit_card_drop(row_position, _click_carry_data)
			committed = true
	elif hand_drop_zone.get_global_rect().has_point(pointer_global_position):
		if hand_drop_zone.preview_card_drop(
			pointer_global_position,
			_click_carry_data
		):
			hand_drop_zone.commit_card_drop(
				pointer_global_position,
				_click_carry_data
			)
			committed = true

	_finish_click_carry(committed)


func _cancel_click_carry() -> void:
	if not _click_carry_data.is_empty():
		_finish_click_carry(false)


func _finish_click_carry(committed: bool) -> void:
	var drag_data := _click_carry_data
	_click_carry_data = {}
	var return_global_position: Variant = null
	if (
		not committed
		and is_instance_valid(_click_carry_preview)
	):
		var drag_visual := _click_carry_preview as CardDragPreview
		if drag_visual != null:
			return_global_position = drag_visual.get_card_global_position()
	_clear_click_drop_feedback()
	for row: BattlefieldRow in [front_row, back_row]:
		row.stop_stack_target_feedback()

	if is_instance_valid(_click_carry_preview):
		_click_carry_preview.queue_free()
	_click_carry_preview = null

	var source_type := drag_data.get("source_type") as StringName
	if source_type == &"hand":
		var source_slot := drag_data.get("source_slot") as Control
		if (
			is_instance_valid(source_slot)
			and source_slot.get_parent() == hand_card_row
			and not source_slot.visible
		):
			var previous_positions := _capture_hand_card_positions()
			source_slot.visible = true
			_animate_hand_layout_next_frame(previous_positions)
			if (
				not committed
				and return_global_position is Vector2
				and source_slot.get_child_count() > 0
			):
				_animate_hand_card_entry.call_deferred(
					source_slot.get_child(0) as CardView,
					return_global_position as Vector2
				)
	elif source_type == &"board":
		var source_row := drag_data.get("source_row") as BattlefieldRow
		if is_instance_valid(source_row):
			source_row._finish_card_drag(return_global_position)


func _clear_click_drop_feedback(clear_stack_feedback: bool = true) -> void:
	for row: BattlefieldRow in [front_row, back_row]:
		row.clear_drop_preview(clear_stack_feedback)
	hand_drop_zone.clear_drop_preview()


func _find_board_row_at(
	pointer_global_position: Vector2
) -> BattlefieldRow:
	for row: BattlefieldRow in [front_row, back_row]:
		var local_position := _to_row_drop_position(
			row,
			pointer_global_position
		)
		if Rect2(Vector2.ZERO, row.placement_overlay.size).has_point(
			local_position
		):
			return row
	return null


func _to_row_drop_position(
	row: BattlefieldRow,
	pointer_global_position: Vector2
) -> Vector2:
	return (
		row.placement_overlay
		.get_global_transform_with_canvas()
		.affine_inverse()
		* pointer_global_position
	)


func _on_board_card_dropped(
	target_row: BattlefieldRow,
	insert_index: int,
	drag_data: Dictionary,
	card_global_position: Vector2
) -> void:
	if drag_data.has("drop_intent"):
		_transfer_drop_intent(
			drag_data,
			target_row,
			card_global_position
		)
		return
	_transfer_card(
		drag_data,
		&"board",
		target_row,
		insert_index,
		card_global_position
	)


func _on_hand_card_dropped(
	drag_data: Dictionary,
	card_global_position: Vector2
) -> void:
	if drag_data.get("kind") == &"squad":
		_clear_hand_drop_preview()
		_transfer_squad_to_hand(drag_data, card_global_position)
		return
	if drag_data.get("source_type") == &"hand":
		_commit_hand_reorder(drag_data, card_global_position)
		return

	var insert_index := clampi(
		_hand_preview_insert_index,
		0,
		hand_cards.size()
	)
	_clear_hand_drop_preview()
	_transfer_card(
		drag_data,
		&"hand",
		null,
		insert_index,
		card_global_position
	)


func _on_hand_card_drag_hovered(
	pointer_global_position: Vector2,
	drag_data: Dictionary
) -> void:
	if current_phase != GamePhase.PREPARE or not _is_card_drag_data(drag_data):
		_clear_hand_drop_preview()
		return
	if drag_data.get("kind") == &"squad":
		_clear_hand_drop_preview()
		return

	var visible_slots := _get_visible_hand_card_slots()
	var insert_index := visible_slots.size()
	for index: int in visible_slots.size():
		var slot := visible_slots[index]
		if pointer_global_position.x < slot.get_global_rect().get_center().x:
			insert_index = index
			break

	if (
		_hand_preview_slot != null
		and _hand_preview_insert_index == insert_index
	):
		return

	var previous_positions := _capture_hand_card_positions()
	if _hand_preview_slot == null:
		_hand_preview_slot = _create_hand_card_slot(
			drag_data["card_data"] as CardData,
			true
		)
		hand_card_row.add_child(_hand_preview_slot)

	_hand_preview_insert_index = insert_index
	_move_hand_preview_slot(insert_index)
	_animate_hand_layout_next_frame(previous_positions)


func _commit_hand_reorder(
	drag_data: Dictionary,
	card_global_position: Variant = null
) -> void:
	if _hand_preview_insert_index < 0:
		return

	var source_slot := drag_data.get("source_slot") as Control
	var real_slots := _get_hand_card_slots()
	var source_index := real_slots.find(source_slot)
	var card_data := drag_data.get("card_data") as CardData
	if (
		source_index < 0
		or card_data == null
		or source_index >= hand_cards.size()
		or hand_cards[source_index] != card_data
	):
		_clear_hand_drop_preview()
		return

	var insert_index := clampi(
		_hand_preview_insert_index,
		0,
		hand_cards.size() - 1
	)
	_clear_hand_drop_preview()
	hand_cards.remove_at(source_index)
	hand_cards.insert(insert_index, card_data)
	_move_hand_card_slot(source_slot, insert_index)
	if card_global_position is Vector2 and source_slot.get_child_count() > 0:
		_animate_hand_card_entry.call_deferred(
			source_slot.get_child(0) as CardView,
			card_global_position as Vector2
		)
	selected_board_row = null
	selected_board_slot = null
	_select_card(card_data)
	play_area_label.text = "已调整 %s 在手牌中的顺序" % card_data.display_name


func _clear_hand_drop_preview() -> void:
	if _hand_preview_slot == null:
		return

	var previous_positions := _capture_hand_card_positions()
	hand_card_row.remove_child(_hand_preview_slot)
	_hand_preview_slot.queue_free()
	_hand_preview_slot = null
	_hand_preview_insert_index = -1
	_animate_hand_layout_next_frame(previous_positions)


func _move_hand_preview_slot(insert_index: int) -> void:
	var visible_slots := _get_visible_hand_card_slots()
	if insert_index >= visible_slots.size():
		hand_card_row.move_child(
			_hand_preview_slot,
			hand_card_row.get_child_count() - 1
		)
	else:
		_move_hand_child_before(
			_hand_preview_slot,
			visible_slots[insert_index]
		)


func _move_hand_card_slot(slot: Control, insert_index: int) -> void:
	var remaining_slots := _get_hand_card_slots()
	remaining_slots.erase(slot)
	var clamped_index := clampi(insert_index, 0, remaining_slots.size())
	if clamped_index == remaining_slots.size():
		hand_card_row.move_child(slot, hand_card_row.get_child_count() - 1)
	else:
		_move_hand_child_before(slot, remaining_slots[clamped_index])


func _move_hand_child_before(child: Control, target: Control) -> void:
	var target_index := target.get_index()
	if child.get_index() < target_index:
		target_index -= 1
	hand_card_row.move_child(child, target_index)


func _get_hand_card_slots() -> Array[Control]:
	var slots: Array[Control] = []
	for child: Node in hand_card_row.get_children():
		var slot := child as Control
		if (
			slot != null
			and not slot.is_queued_for_deletion()
			and not bool(slot.get_meta("is_hand_preview", false))
		):
			slots.append(slot)
	return slots


func _get_visible_hand_card_slots() -> Array[Control]:
	var slots: Array[Control] = []
	for slot: Control in _get_hand_card_slots():
		if slot.visible:
			slots.append(slot)
	return slots


func _transfer_card(
	drag_data: Dictionary,
	target_type: StringName,
	target_row: BattlefieldRow = null,
	insert_index: int = 0,
	entry_global_position: Variant = null
) -> bool:
	if current_phase != GamePhase.PREPARE or not _is_card_drag_data(drag_data):
		return false

	var card_data := drag_data["card_data"] as CardData
	var source_type := drag_data["source_type"] as StringName
	if target_type == &"board" and target_row == null:
		return false

	if source_type == &"hand":
		if target_type != &"board" or not target_row.has_capacity_for_single_card():
			return false

		var hand_index := hand_cards.find(card_data)
		if hand_index < 0:
			return false

		hand_cards.remove_at(hand_index)
		selected_board_slot = target_row.add_card(card_data, insert_index)
		selected_board_row = target_row
		_build_hand_cards()
		if entry_global_position is Vector2:
			_animate_board_card_entry.call_deferred(
				selected_board_slot,
				entry_global_position as Vector2
			)
	elif source_type == &"board":
		var source_row := drag_data.get("source_row") as BattlefieldRow
		var source_slot := drag_data.get("source_slot") as BoardSlot
		if (
			not is_instance_valid(source_row)
			or not is_instance_valid(source_slot)
			or source_row.get_slot_index(source_slot) < 0
			or not source_slot.get_squad_data().contains(card_data)
		):
			return false

		if target_type == &"hand":
			if not source_row.remove_card_from_squad(source_slot, card_data):
				return false
			var returned_card := card_data

			var hand_insert_index := clampi(
				insert_index,
				0,
				hand_cards.size()
			)
			hand_cards.insert(hand_insert_index, returned_card)
			selected_board_row = null
			selected_board_slot = null
			_build_hand_cards(returned_card, entry_global_position)
		elif target_type == &"board":
			if source_row == target_row:
				if source_slot.get_squad_data().get_card_count() > 1:
					source_row.remove_card_from_squad(source_slot, card_data)
					selected_board_slot = target_row.add_card(card_data, insert_index)
				else:
					if target_row.get_slot_index(source_slot) != insert_index:
						target_row.move_card_slot(source_slot, insert_index)
					selected_board_slot = source_slot
				selected_board_row = target_row
				if entry_global_position is Vector2:
					_animate_board_card_entry.call_deferred(
						selected_board_slot,
						entry_global_position as Vector2
					)
			else:
				if not target_row.has_capacity_for_single_card():
					return false

				if not source_row.remove_card_from_squad(source_slot, card_data):
					return false

				selected_board_slot = target_row.add_card(card_data, insert_index)
				selected_board_row = target_row
				if entry_global_position is Vector2:
					_animate_board_card_entry.call_deferred(
						selected_board_slot,
						entry_global_position as Vector2
					)
		else:
			return false
	else:
		return false

	_select_card(card_data)
	if target_type == &"hand":
		play_area_label.text = "已将 %s 收回手牌；可再次拖到前排或后排" % card_data.display_name
	else:
		play_area_label.text = "已将 %s 放入%s" % [card_data.display_name, target_row.row_title]
	_refresh_drag_availability()
	_on_battlefield_squads_changed()
	return true


func _transfer_drop_intent(
	drag_data: Dictionary,
	target_row: BattlefieldRow,
	entry_global_position: Variant = null
) -> bool:
	if current_phase != GamePhase.PREPARE or target_row == null:
		return false
	var intent := drag_data.get("drop_intent") as Dictionary
	if intent == null or intent.is_empty():
		return false
	var kind := drag_data.get("kind") as StringName
	if kind == &"squad":
		return _transfer_whole_squad(
			drag_data,
			target_row,
			int(intent.get("squad_index", 0)),
			entry_global_position
		)
	if kind != &"card":
		return false

	var card_data := drag_data.get("card_data") as CardData
	var source_type := drag_data.get("source_type") as StringName
	var source_row := drag_data.get("source_row") as BattlefieldRow
	var source_slot := drag_data.get("source_slot") as BoardSlot
	var target_slot := intent.get("target_slot") as BoardSlot
	var result_squad := intent.get("result_squad") as SquadData
	if card_data == null or result_squad == null or not result_squad.is_valid():
		return false
	var operation := intent.get("operation") as StringName
	if operation not in [&"new_squad", &"merge_card"]:
		return false
	if operation == &"merge_card" and (
		not is_instance_valid(target_slot)
		or target_row.get_slot_index(target_slot) < 0
	):
		return false
	if (
		operation == &"merge_card"
		and target_slot != source_slot
		and not target_slot.get_squad_data().can_accept_external_card_at(
			int(intent.get("card_index", 0))
		)
	):
		return false

	if source_type == &"hand":
		var hand_index := hand_cards.find(card_data)
		if hand_index < 0:
			return false
		hand_cards.remove_at(hand_index)
	elif source_type == &"board":
		if (
			not is_instance_valid(source_row)
			or not is_instance_valid(source_slot)
			or source_row.get_slot_index(source_slot) < 0
			or not source_slot.get_squad_data().contains(card_data)
		):
			return false
	else:
		return false

	if operation == &"new_squad":
		if (
			source_type == &"board"
			and source_row == target_row
			and source_slot.get_squad_data().get_card_count() == 1
		):
			source_slot.get_squad_data().bring_card_to_top(card_data)
			target_row.move_squad_slot(
				source_slot,
				int(intent.get("squad_index", 0)),
				is_instance_valid(drag_data.get("drag_visual"))
			)
			selected_board_slot = source_slot
		elif source_type == &"board":
			source_row.remove_card_from_squad(source_slot, card_data)
			selected_board_slot = target_row.add_squad(
				result_squad,
				int(intent.get("squad_index", 0))
			)
		else:
			selected_board_slot = target_row.add_squad(
				result_squad,
				int(intent.get("squad_index", 0))
			)
	elif operation == &"merge_card":
		if source_type == &"board" and source_slot != target_slot:
			source_row.remove_card_from_squad(source_slot, card_data)
		target_slot.set_squad_data(result_squad)
		target_slot.configure_drag_source(true, target_row)
		selected_board_slot = target_slot
	else:
		return false

	if source_type == &"hand":
		_build_hand_cards()
	selected_board_row = target_row
	_select_card(card_data)
	var preview_glow_states := drag_data.get(
		"preview_glow_states", {}
	) as Dictionary
	if not preview_glow_states.is_empty() and is_instance_valid(selected_board_slot):
		for preview_card: CardData in preview_glow_states.keys():
			var dropped_card_view := selected_board_slot.get_card_view(preview_card)
			if dropped_card_view != null:
				dropped_card_view.fade_preview_glow_state(
					preview_glow_states[preview_card] as Dictionary
				)
	if entry_global_position is Vector2 and is_instance_valid(selected_board_slot):
		_animate_board_card_entry.call_deferred(
			selected_board_slot,
			entry_global_position as Vector2
		)
	play_area_label.text = "已将 %s 放入%s的小队" % [card_data.display_name, target_row.row_title]
	_refresh_drag_availability()
	_on_battlefield_squads_changed()
	return true


func _transfer_whole_squad(
	drag_data: Dictionary,
	target_row: BattlefieldRow,
	insert_index: int,
	entry_global_position: Variant = null
) -> bool:
	var source_row := drag_data.get("source_row") as BattlefieldRow
	var source_slot := drag_data.get("source_slot") as BoardSlot
	var squad_data := drag_data.get("squad_data") as SquadData
	if (
		not is_instance_valid(source_row)
		or not is_instance_valid(source_slot)
		or source_row.get_slot_index(source_slot) < 0
		or source_slot.get_squad_data() != squad_data
	):
		return false
	if source_row == target_row:
		target_row.move_squad_slot(source_slot, insert_index)
		selected_board_slot = source_slot
	else:
		if not target_row.has_capacity_for_squad(squad_data):
			return false
		source_row.remove_squad_slot(source_slot)
		selected_board_slot = target_row.add_squad(squad_data, insert_index)
	selected_board_row = target_row
	_select_card(squad_data.get_effect_source())
	if entry_global_position is Vector2 and is_instance_valid(selected_board_slot):
		_animate_board_card_entry.call_deferred(selected_board_slot, entry_global_position)
	play_area_label.text = "已整体移动小队到%s" % target_row.row_title
	_refresh_drag_availability()
	_on_battlefield_squads_changed()
	return true


func _transfer_squad_to_hand(
	drag_data: Dictionary,
	entry_global_position: Variant = null
) -> bool:
	if current_phase != GamePhase.PREPARE:
		return false
	var source_row := drag_data.get("source_row") as BattlefieldRow
	var source_slot := drag_data.get("source_slot") as BoardSlot
	if (
		not is_instance_valid(source_row)
		or not is_instance_valid(source_slot)
		or source_row.get_slot_index(source_slot) < 0
	):
		return false
	var squad_data := source_row.remove_squad_slot(source_slot)
	if squad_data == null:
		return false
	for card_data: CardData in squad_data.horizontal_cards:
		hand_cards.append(card_data)
	selected_board_row = null
	selected_board_slot = null
	var entering_card := squad_data.horizontal_cards[0]
	_build_hand_cards(entering_card, entry_global_position)
	_select_card(entering_card)
	play_area_label.text = "已按水平顺序拆开小队并追加回手牌"
	_refresh_drag_availability()
	_on_battlefield_squads_changed()
	return true


func _is_card_drag_data(data: Variant) -> bool:
	if not data is Dictionary:
		return false

	var drag_data := data as Dictionary
	if drag_data.get("source_type") not in [&"hand", &"board"]:
		return false
	if drag_data.get("kind") == &"card":
		return drag_data.get("card_data") is CardData
	if drag_data.get("kind") == &"squad":
		return drag_data.get("squad_data") is SquadData
	return false


func _refresh_drag_availability() -> void:
	var drag_enabled := current_phase == GamePhase.PREPARE
	for row: BattlefieldRow in [front_row, back_row]:
		row.set_drag_enabled(drag_enabled)

	for hand_slot: Control in _get_hand_card_slots():
		for child: Node in hand_slot.get_children():
			var card_view := child as CardView
			if card_view != null:
				card_view.configure_drag_source(
					drag_enabled,
					&"hand",
					null,
					hand_slot
				)

	hand_drop_zone.set("drop_enabled", drag_enabled)


func _on_hand_source_visibility_changing() -> void:
	_animate_hand_layout_next_frame(_capture_hand_card_positions())


func _capture_hand_card_positions() -> Dictionary:
	var positions := {}
	for hand_slot: Control in _get_visible_hand_card_slots():
		if hand_slot.get_child_count() == 0:
			continue

		var card_view := hand_slot.get_child(0) as CardView
		if card_view != null and not card_view.is_queued_for_deletion():
			positions[card_view] = card_view.global_position
	return positions


func _animate_hand_layout_next_frame(previous_positions: Dictionary) -> void:
	_hand_layout_animation_revision += 1
	var animation_revision := _hand_layout_animation_revision
	if previous_positions.is_empty():
		return

	await get_tree().process_frame
	# 快速拖动可能在一帧内请求多次重排，只执行最后一次请求。
	if animation_revision != _hand_layout_animation_revision:
		return

	for card_view_value: Variant in previous_positions:
		if not is_instance_valid(card_view_value):
			continue

		var card_view := card_view_value as CardView
		if (
			card_view != null
			and not card_view.is_queued_for_deletion()
			and card_view.is_visible_in_tree()
		):
			card_view.animate_from_global_position(
				previous_positions[card_view_value]
			)


func _animate_hand_card_entry(
	card_view_value: Variant,
	entry_global_position: Vector2
) -> void:
	await get_tree().process_frame
	if not is_instance_valid(card_view_value):
		return

	var card_view := card_view_value as CardView
	if card_view == null or card_view.is_queued_for_deletion():
		return

	# 飞回手牌的卡仍属于 HandScroll；动画期间临时解除滚动区裁切并
	# 提到拖拽层，既能在手牌区外完整显示，也不会从其他手牌中间穿过。
	var resting_z_index := card_view.z_index
	_active_hand_entry_animations += 1
	hand_scroll.clip_contents = false
	card_view.set_resting_z_index(CardDragPreview.DRAG_PREVIEW_Z_INDEX)
	card_view.animate_from_global_position(entry_global_position)
	await get_tree().create_timer(CardView.LAYOUT_TWEEN_DURATION).timeout

	if is_instance_valid(card_view) and not card_view.is_queued_for_deletion():
		card_view.set_resting_z_index(resting_z_index)
	_active_hand_entry_animations = maxi(_active_hand_entry_animations - 1, 0)
	if _active_hand_entry_animations == 0 and is_instance_valid(hand_scroll):
		hand_scroll.clip_contents = true


func _animate_board_card_entry(
	slot_value: Variant,
	entry_global_position: Vector2
) -> void:
	await get_tree().process_frame
	if not is_instance_valid(slot_value):
		return

	var slot := slot_value as BoardSlot
	if (
		slot != null
		and not slot.is_queued_for_deletion()
		and slot.get_parent() != null
	):
		slot.animate_from_global_position(entry_global_position)


func _select_card(card_data: CardData) -> void:
	selected_card = card_data

	if selected_card == null:
		play_area_label.text = "手牌/收藏区没有绑定测试卡牌"
		selected_card_view.set_card_data(null)
		return

	play_area_label.text = "当前选中：%s。准备阶段可按住卡牌拖动放置" % selected_card.display_name
	selected_card_view.set_card_data(selected_card)
