extends SceneTree

## 用真实场景和 1/16 时间倍率检查整个归位过程的层级。
var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var slot: Control = main._get_collection_card_slots()[0]
	var card: CardView
	for child in slot.get_children():
		if child is CardView:
			card = child
	assert(card != null)
	var original_z := card.z_index
	Engine.time_scale = 1.0 / 16.0
	main._animate_collection_card_entry(card, card.global_position + Vector2(200, 100))
	await process_frame
	await process_frame
	var samples := 0
	while card.is_layout_animating():
		if card.z_index != CardDragPreview.DRAG_PREVIEW_Z_INDEX:
			failures += 1
			push_error("慢速归位尚未结束就恢复了层级")
			break
		samples += 1
		await process_frame
	await process_frame
	if samples == 0 or card.z_index != original_z:
		failures += 1
		push_error("归位动画未运行或结束后层级未恢复")
	Engine.time_scale = 1.0
	main.queue_free()
	await process_frame
	print("Slow collection return: %d samples, %d failures" % [samples, failures])
	quit(failures)
