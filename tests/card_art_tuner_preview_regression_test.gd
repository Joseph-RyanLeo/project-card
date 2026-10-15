extends "res://tests/stage_4_drag_drop_test.gd"

## 复用原有4倍像素、3D、偏移与键盘回归，只运行与调整器相关的用例。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_card_art_tuner_preview()
	print("卡面调整器既有预览回归：%d失败" % _failure_count)
	quit(_failure_count)
