extends "res://tests/d2_7_ordinary_shop_test.gd"

## 复用真实卡池、保底、实例获取与随机状态测试；当前商店输入由UI专项验证。
func _run() -> void:
	_test_real_card_pools_and_guarantees()
	_test_real_sticker_pool_and_uniqueness()
	_test_instance_acquisition_state()
	_test_service_rng_and_state_roundtrip()
	print("Card acquisition pool failures: ", failures)
	quit(1 if failures else 0)
