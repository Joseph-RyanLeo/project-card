extends "res://tests/battle_start_time_bar_test.gd"


func observe_hover(button: Button) -> Dictionary:
	var visual: Control = button.get_node("ButtonVisual")
	var offsets: Dictionary = {}
	for index: int in 16:
		await create_timer(0.025).timeout
		offsets[visual.position] = true
	return offsets


func verify_button_motion() -> void:
	var button: Button = main.start_battle_button
	var visual: Control = button.get_node("ButtonVisual")
	await move_pointer(Vector2(950, 660))
	await move_pointer(button.get_global_rect().get_center())
	var offsets := await observe_hover(button)
	check(offsets.size() > 1, "首次进入实际播放颤抖")
	check(not button.is_processing() and visual.position == Vector2.ZERO, "单次颤抖结束后停止更新并归位")
	var still := true
	for index: int in 12:
		await create_timer(0.025).timeout
		still = still and visual.position == Vector2.ZERO and not button.is_processing()
	check(still, "鼠标持续停留不会循环颤抖")
	await move_pointer(button.get_global_rect().get_center() + Vector2(2, 0))
	await create_timer(0.1).timeout
	check(not button.is_processing(), "按钮内部移动不重播")
	await move_pointer(Vector2(950, 660))
	await move_pointer(button.get_global_rect().get_center())
	offsets = await observe_hover(button)
	check(offsets.size() > 1, "移开后再次进入重新播放一次")
	check(not button.is_processing() and visual.position == Vector2.ZERO, "再次播放也正常停止")
	await move_pointer(Vector2(950, 660))
	await move_pointer(button.get_global_rect().get_center())
	await create_timer(0.04).timeout
	await move_pointer(Vector2(950, 660))
	check(not button.is_processing() and visual.position == Vector2.ZERO, "颤抖中途移开立即归位")
	await super.verify_button_motion()
