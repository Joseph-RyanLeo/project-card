class_name BattlefieldRow
extends PanelContainer

signal board_slot_clicked(row: BattlefieldRow, slot: BoardSlot)
signal card_dropped(
	row: BattlefieldRow,
	insert_index: int,
	data: Dictionary,
	card_global_position: Vector2
)
signal card_click_carry_requested(
	data: Dictionary,
	pointer_global_position: Vector2
)

const BOARD_SLOT_SCENE: PackedScene = preload("res://scenes/ui/BoardSlot.tscn")
const BATTLEFIELD_UNIT_COUNT: int = 21 # 单排可使用的战场单元总容量
const BATTLEFIELD_UNIT_WIDTH: int = 33 # 一个战场单元对应的像素宽度
const SINGLE_CARD_UNIT_COUNT: int = 3 # 当前一张未堆叠卡牌占用的战场单元数
const SINGLE_CARD_WIDTH: int = SINGLE_CARD_UNIT_COUNT * BATTLEFIELD_UNIT_WIDTH # 单卡显示宽度，由单元数和单元宽度计算，不单独修改
const SQUAD_GAP: int = 18 # 同一排相邻卡牌（以后为相邻小队）之间的固定间距
const FULL_ROW_CARD_COUNT: int = 7 # 当前满排未堆叠单卡数量
const FULL_ROW_DISPLAY_WIDTH: int = (
	FULL_ROW_CARD_COUNT * SINGLE_CARD_WIDTH
	+ (FULL_ROW_CARD_COUNT - 1) * SQUAD_GAP
) # 满排显示宽度的派生值，不单独修改

@export var row_title: String = "前排" # 显示在该战场行左上角的名称

@onready var row_title_label: Label = %RowTitleLabel
@onready var row_display_area: Control = %RowDisplayArea
@onready var squad_row: HBoxContainer = %SquadRow
@onready var placement_overlay: Control = %PlacementOverlay

var _drag_enabled: bool = false
var _preview_slot: BoardSlot
var _preview_insert_index: int = -1
var _hidden_source_slot: BoardSlot
var _active_drag_preview_offset: Vector2 = Vector2.ZERO
var _active_drag_visual: CardDragPreview


func _ready() -> void:
	row_title_label.text = row_title
	row_display_area.custom_minimum_size.x = FULL_ROW_DISPLAY_WIDTH
	squad_row.add_theme_constant_override("separation", SQUAD_GAP)
	placement_overlay.set("battlefield_row", self)


func get_squad_container() -> HBoxContainer:
	return squad_row


func get_card_count() -> int:
	return _get_real_slots().size()


func has_capacity_for_single_card() -> bool:
	return (get_card_count() + 1) * SINGLE_CARD_UNIT_COUNT <= BATTLEFIELD_UNIT_COUNT


func add_card(card_data: CardData, insert_index: int) -> BoardSlot:
	var slot := BOARD_SLOT_SCENE.instantiate() as BoardSlot
	squad_row.add_child(slot)
	slot.set_card_data(card_data)
	slot.slot_clicked.connect(_on_occupied_slot_clicked)
	slot.click_carry_requested.connect(_on_click_carry_requested)
	slot.configure_drag_source(_drag_enabled, self)
	_place_card_slot(slot, insert_index)
	return slot


func remove_card_slot(slot: BoardSlot) -> CardData:
	if slot.get_parent() != squad_row:
		return null

	var previous_positions := _capture_visible_slot_positions()
	var card_data := slot.get_card_data()
	squad_row.remove_child(slot)
	slot.queue_free()
	_animate_layout_next_frame(previous_positions)
	return card_data


func get_slot_index(slot: BoardSlot) -> int:
	if slot.get_parent() != squad_row or slot.is_preview():
		return -1

	return _get_real_slots().find(slot)


func move_card_slot(slot: BoardSlot, insert_index: int) -> void:
	if slot.get_parent() != squad_row or slot.is_preview():
		return

	var previous_positions := _capture_visible_slot_positions()
	_place_card_slot(slot, insert_index)
	_animate_layout_next_frame(previous_positions)


func _place_card_slot(slot: BoardSlot, insert_index: int) -> void:
	var remaining_slots := _get_real_slots()
	remaining_slots.erase(slot)
	var clamped_index := clampi(insert_index, 0, remaining_slots.size())
	if clamped_index == remaining_slots.size():
		squad_row.move_child(slot, squad_row.get_child_count() - 1)
	else:
		_move_child_before(slot, remaining_slots[clamped_index])


func set_drag_enabled(value: bool) -> void:
	_drag_enabled = value
	for slot: BoardSlot in _get_real_slots():
		slot.configure_drag_source(_drag_enabled, self)

	if not _drag_enabled:
		_finish_card_drag()


func can_receive_card_drag(data: Variant) -> bool:
	return _drag_enabled and _is_card_drag_data(data)


func preview_card_drop(at_position: Vector2, data: Variant) -> bool:
	if not _can_accept_card_drag(data):
		clear_drop_preview()
		return false

	var insert_index := _find_insert_index(at_position.x)
	if _preview_slot != null and _preview_insert_index == insert_index:
		return true

	var previous_positions := _capture_visible_slot_positions()
	if _preview_slot == null:
		_preview_slot = BOARD_SLOT_SCENE.instantiate() as BoardSlot
		squad_row.add_child(_preview_slot)
		_preview_slot.set_preview_card((data as Dictionary)["card_data"] as CardData)

	_preview_insert_index = insert_index
	_move_preview_slot(insert_index)
	_animate_layout_next_frame(previous_positions)
	return true


func commit_card_drop(at_position: Vector2, data: Variant) -> void:
	if not preview_card_drop(at_position, data):
		return

	var insert_index := _preview_insert_index
	var drag_data := data as Dictionary
	var pointer_global_position := (
		placement_overlay.get_global_transform_with_canvas()
		* at_position
	)
	var preview_offset: Vector2 = drag_data.get(
		"preview_offset",
		Vector2.ZERO
	)
	var drag_visual := drag_data.get("drag_visual") as CardDragPreview
	var card_global_position := (
		drag_visual.get_card_global_position()
		if is_instance_valid(drag_visual)
		else pointer_global_position - preview_offset
	)
	if (
		drag_data.get("source_type") == &"board"
		and drag_data.get("source_row") == self
		and drag_data.get("source_slot") == _hidden_source_slot
	):
		_replace_preview_with_hidden_source(insert_index)
	else:
		clear_drop_preview()
		_restore_hidden_source_slot()
	card_dropped.emit(
		self,
		insert_index,
		drag_data,
		card_global_position
	)


func _replace_preview_with_hidden_source(insert_index: int) -> void:
	var source_slot := _hidden_source_slot
	if not is_instance_valid(source_slot) or _preview_slot == null:
		clear_drop_preview()
		_restore_hidden_source_slot()
		return

	squad_row.remove_child(_preview_slot)
	_preview_slot.queue_free()
	_preview_slot = null
	_preview_insert_index = -1
	_place_card_slot(source_slot, insert_index)
	source_slot.visible = true
	_hidden_source_slot = null


func clear_drop_preview() -> void:
	if _preview_slot == null:
		return

	var previous_positions := _capture_visible_slot_positions()
	squad_row.remove_child(_preview_slot)
	_preview_slot.queue_free()
	_preview_slot = null
	_preview_insert_index = -1
	_animate_layout_next_frame(previous_positions)


func _on_occupied_slot_clicked(slot: BoardSlot) -> void:
	board_slot_clicked.emit(self, slot)


func _on_click_carry_requested(
	data: Dictionary,
	pointer_global_position: Vector2
) -> void:
	card_click_carry_requested.emit(data, pointer_global_position)


func _notification(what: int) -> void:
	if not is_node_ready():
		return

	if what == NOTIFICATION_DRAG_BEGIN:
		_begin_card_drag(get_viewport().gui_get_drag_data())
	elif what == NOTIFICATION_DRAG_END:
		var return_global_position: Variant = null
		if (
			is_instance_valid(_hidden_source_slot)
			and not get_viewport().gui_is_drag_successful()
		):
			return_global_position = (
				_active_drag_visual.get_card_global_position()
				if is_instance_valid(_active_drag_visual)
				else (
					get_viewport().get_mouse_position()
					- _active_drag_preview_offset
				)
			)
		_finish_card_drag(return_global_position)


func _begin_card_drag(data: Variant) -> void:
	_finish_card_drag()
	if not can_receive_card_drag(data):
		return

	var drag_data := data as Dictionary
	if drag_data.get("source_type") != &"board" or drag_data.get("source_row") != self:
		return

	var source_slot := drag_data.get("source_slot") as BoardSlot
	if source_slot == null or source_slot.get_parent() != squad_row:
		return

	var previous_positions := _capture_visible_slot_positions()
	_hidden_source_slot = source_slot
	_active_drag_preview_offset = drag_data.get(
		"preview_offset",
		Vector2.ZERO
	)
	_active_drag_visual = drag_data.get("drag_visual") as CardDragPreview
	_hidden_source_slot.visible = false
	_animate_layout_next_frame(previous_positions)


func _finish_card_drag(return_global_position: Variant = null) -> void:
	clear_drop_preview()
	_restore_hidden_source_slot(return_global_position)
	_active_drag_preview_offset = Vector2.ZERO
	_active_drag_visual = null


func _restore_hidden_source_slot(
	return_global_position: Variant = null
) -> void:
	if (
		is_instance_valid(_hidden_source_slot)
		and _hidden_source_slot.get_parent() == squad_row
	):
		var previous_positions := _capture_visible_slot_positions()
		var restored_slot := _hidden_source_slot
		restored_slot.visible = true
		_animate_layout_next_frame(previous_positions)
		if return_global_position is Vector2:
			_animate_restored_slot_return.call_deferred(
				restored_slot,
				return_global_position as Vector2
			)
	_hidden_source_slot = null


func _animate_restored_slot_return(
	slot_value: Variant,
	return_global_position: Vector2
) -> void:
	await get_tree().process_frame
	if not is_instance_valid(slot_value):
		return

	var slot := slot_value as BoardSlot
	if (
		slot != null
		and not slot.is_queued_for_deletion()
		and slot.visible
		and slot.get_parent() == squad_row
	):
		slot.animate_from_global_position(return_global_position)


func _can_accept_card_drag(data: Variant) -> bool:
	if not can_receive_card_drag(data):
		return false

	var drag_data := data as Dictionary
	if drag_data.get("source_type") == &"board" and drag_data.get("source_row") == self:
		return true

	return has_capacity_for_single_card()


func _is_card_drag_data(data: Variant) -> bool:
	if not data is Dictionary:
		return false

	var drag_data := data as Dictionary
	return (
		drag_data.get("kind") == &"card"
		and drag_data.get("card_data") is CardData
		and drag_data.get("source_type") in [&"hand", &"board"]
	)


func _find_insert_index(pointer_x: float) -> int:
	var visible_slots := _get_visible_real_slots()
	for index: int in visible_slots.size():
		var slot := visible_slots[index]
		if pointer_x < slot.position.x + slot.size.x * 0.5:
			return index

	return visible_slots.size()


func _move_preview_slot(insert_index: int) -> void:
	var visible_slots := _get_visible_real_slots()
	if insert_index >= visible_slots.size():
		squad_row.move_child(_preview_slot, squad_row.get_child_count() - 1)
	else:
		_move_child_before(_preview_slot, visible_slots[insert_index])


func _move_child_before(child: Node, target: Node) -> void:
	var target_index := target.get_index()
	if child.get_index() < target_index:
		target_index -= 1
	squad_row.move_child(child, target_index)


func _get_real_slots() -> Array[BoardSlot]:
	var slots: Array[BoardSlot] = []
	for child: Node in squad_row.get_children():
		var slot := child as BoardSlot
		if slot != null and not slot.is_preview():
			slots.append(slot)
	return slots


func _get_visible_real_slots() -> Array[BoardSlot]:
	var slots: Array[BoardSlot] = []
	for slot: BoardSlot in _get_real_slots():
		if slot.visible:
			slots.append(slot)
	return slots


func _capture_visible_slot_positions() -> Dictionary:
	var positions := {}
	for slot: BoardSlot in _get_visible_real_slots():
		positions[slot] = slot.card_view.global_position
	return positions


func _animate_layout_next_frame(previous_positions: Dictionary) -> void:
	if previous_positions.is_empty():
		return

	await get_tree().process_frame
	for slot_value: Variant in previous_positions:
		if not is_instance_valid(slot_value):
			continue

		var slot := slot_value as BoardSlot
		if slot != null and slot.visible and slot.get_parent() == squad_row:
			slot.animate_from_global_position(previous_positions[slot_value])
