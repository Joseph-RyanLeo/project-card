class_name BattlefieldRow
extends PanelContainer

signal placement_requested(row: BattlefieldRow, insert_index: int)
signal board_slot_clicked(row: BattlefieldRow, slot: BoardSlot)

const BOARD_SLOT_SCENE: PackedScene = preload("res://scenes/ui/BoardSlot.tscn")
const BATTLEFIELD_UNIT_COUNT: int = 21
const BATTLEFIELD_UNIT_WIDTH: int = 33
const SINGLE_CARD_UNIT_COUNT: int = 3
const SINGLE_CARD_WIDTH: int = SINGLE_CARD_UNIT_COUNT * BATTLEFIELD_UNIT_WIDTH
const SQUAD_GAP: int = 18
const FULL_ROW_CARD_COUNT: int = 7
const FULL_ROW_DISPLAY_WIDTH: int = (
	FULL_ROW_CARD_COUNT * SINGLE_CARD_WIDTH
	+ (FULL_ROW_CARD_COUNT - 1) * SQUAD_GAP
)

@export var row_title: String = "前排"

@onready var row_title_label: Label = %RowTitleLabel
@onready var row_display_area: Control = %RowDisplayArea
@onready var squad_row: HBoxContainer = %SquadRow
@onready var placement_overlay: Control = %PlacementOverlay

var _placement_enabled: bool = false
var _placement_targets: Array[BoardSlot] = []


func _ready() -> void:
	row_title_label.text = row_title
	row_display_area.custom_minimum_size.x = FULL_ROW_DISPLAY_WIDTH
	squad_row.add_theme_constant_override("separation", SQUAD_GAP)


func get_squad_container() -> HBoxContainer:
	return squad_row


func get_card_count() -> int:
	return squad_row.get_child_count()


func has_capacity_for_single_card() -> bool:
	return (get_card_count() + 1) * SINGLE_CARD_UNIT_COUNT <= BATTLEFIELD_UNIT_COUNT


func add_card(card_data: CardData, insert_index: int) -> BoardSlot:
	var slot := BOARD_SLOT_SCENE.instantiate() as BoardSlot
	squad_row.add_child(slot)
	squad_row.move_child(slot, clampi(insert_index, 0, squad_row.get_child_count() - 1))
	slot.set_card_data(card_data)
	slot.slot_clicked.connect(_on_occupied_slot_clicked)
	_rebuild_placement_targets()
	return slot


func remove_card_slot(slot: BoardSlot) -> CardData:
	if slot.get_parent() != squad_row:
		return null

	var card_data := slot.get_card_data()
	squad_row.remove_child(slot)
	slot.queue_free()
	_rebuild_placement_targets()
	return card_data


func get_slot_index(slot: BoardSlot) -> int:
	return slot.get_index() if slot.get_parent() == squad_row else -1


func set_placement_enabled(value: bool) -> void:
	if _placement_enabled == value:
		return

	_placement_enabled = value
	_rebuild_placement_targets()


func _on_occupied_slot_clicked(slot: BoardSlot) -> void:
	board_slot_clicked.emit(self, slot)


func _rebuild_placement_targets() -> void:
	for target: BoardSlot in _placement_targets:
		placement_overlay.remove_child(target)
		target.queue_free()
	_placement_targets.clear()

	if not _placement_enabled:
		return

	var target_count := get_card_count() + 1
	for insert_index: int in target_count:
		var target := BOARD_SLOT_SCENE.instantiate() as BoardSlot
		target.set_meta("insert_index", insert_index)
		target.set_compact_empty(get_card_count() > 0)
		target.slot_clicked.connect(_on_placement_target_clicked)
		placement_overlay.add_child(target)
		_placement_targets.append(target)

	call_deferred("_layout_placement_targets")


func _layout_placement_targets() -> void:
	if _placement_targets.is_empty():
		return

	var occupied_slots := squad_row.get_children()
	if occupied_slots.is_empty():
		var only_target := _placement_targets[0]
		only_target.position = (row_display_area.size - only_target.size) * 0.5
		return

	for insert_index: int in _placement_targets.size():
		var target := _placement_targets[insert_index]
		var center_x: float

		if insert_index == 0:
			var first_slot := occupied_slots[0] as Control
			center_x = first_slot.position.x - SQUAD_GAP * 0.5
		elif insert_index == occupied_slots.size():
			var last_slot := occupied_slots[-1] as Control
			center_x = last_slot.position.x + last_slot.size.x + SQUAD_GAP * 0.5
		else:
			var left_slot := occupied_slots[insert_index - 1] as Control
			var right_slot := occupied_slots[insert_index] as Control
			center_x = (left_slot.position.x + left_slot.size.x + right_slot.position.x) * 0.5

		target.position = Vector2(roundf(center_x - target.size.x * 0.5), 0.0)


func _on_placement_target_clicked(target: BoardSlot) -> void:
	placement_requested.emit(self, int(target.get_meta("insert_index", 0)))
