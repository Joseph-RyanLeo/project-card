extends RefCounted

## 每场演出各持有一个实例，共用连点判定及Tween加速规则。
const DOUBLE_CLICK_SECONDS := 0.32 # 两次左键按下被视为连续点击的最大间隔（秒）
const SPEED_STEP := 1.5 # 每次连续点击增加的播放倍率
const MAX_SPEED := 8.0 # 连点加速允许达到的最高播放倍率

var speed := 1.0
var _last_click_msec := -1000

func register_click(tween: Tween) -> void:
	var now := Time.get_ticks_msec()
	if float(now - _last_click_msec) / 1000.0 <= DOUBLE_CLICK_SECONDS:
		speed = minf(speed + SPEED_STEP, MAX_SPEED)
		apply_to(tween)
	_last_click_msec = now

func apply_to(tween: Tween) -> void:
	if is_instance_valid(tween):
		tween.set_speed_scale(speed)
