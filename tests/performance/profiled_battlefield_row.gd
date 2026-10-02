extends "res://scripts/ui/battlefield_row.gd"

var diagnostic_samples: Array[Dictionary] = []
var diagnostic_stage := "startup"

func diagnostic_record(tag: String, began: int) -> void:
	diagnostic_samples.append({"stage": diagnostic_stage, "tag": tag, "ms": (Time.get_ticks_usec() - began) / 1000.0, "frame": Engine.get_process_frames()})

func preview_card_drop(
	at_position: Vector2,
	data: Variant,
	force_recalculate: bool = false
) -> bool:
	var began := Time.get_ticks_usec()
	var result = super.preview_card_drop(at_position, data, force_recalculate)
	diagnostic_record("preview_card_drop", began)
	return result

func _preview_equipment_drop(at_position: Vector2, drag_data: Dictionary) -> bool:
	var began := Time.get_ticks_usec()
	var result = super._preview_equipment_drop(at_position, drag_data)
	diagnostic_record("_preview_equipment_drop", began)
	return result

func _show_intent_preview(
	intent: Dictionary,
	drag_data: Dictionary = {},
	reservation_moved: bool = false
) -> void:
	var began := Time.get_ticks_usec()
	super._show_intent_preview(intent, drag_data, reservation_moved)
	diagnostic_record("_show_intent_preview", began)

func _sync_dragged_card_preview_highlights(drag_data: Dictionary) -> void:
	var began := Time.get_ticks_usec()
	super._sync_dragged_card_preview_highlights(drag_data)
	diagnostic_record("_sync_dragged_card_preview_highlights", began)

func update_stack_target_feedback_global(
	pointer_global_position: Vector2,
	data: Dictionary
) -> void:
	var began := Time.get_ticks_usec()
	super.update_stack_target_feedback_global(pointer_global_position, data)
	diagnostic_record("update_stack_target_feedback_global", began)
