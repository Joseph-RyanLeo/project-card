extends "res://tests/d2_6a_status_slots_and_star_test.gd"

## 仅运行本次涉及的槽位与真实卡面检查；星星转移属于独立战斗专项。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	_test_default_and_custom_slot_layout()
	_test_saved_layout_skips_default_enumeration()
	await _test_real_status_texture_rendering()
	print("随从槽位卡面回归：%d失败" % failures)
	quit(failures)
