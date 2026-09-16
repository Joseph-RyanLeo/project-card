class_name BattleProjectileTiming
extends RefCounted

## 弹道逻辑时间与视觉位移共用的纯计算。
## 战斗控制器决定随机变体和命中时刻，渲染器只按同一组参数播放。

enum TravelSpeedVariant {
	FAST_THEN_SLOW,
	ACCELERATE_THEN_SLOW,
	SLOW_THEN_FAST,
}

const TRAVEL_SPEED_VARIANT_COUNT: int = 3
const SOLVER_STEPS: int = 26 # 二分求解命中时刻的迭代次数，越高越接近视觉曲线


static func remap_travel_progress(
	time_progress: float,
	speed_variant: int,
	variation_strength: float
) -> float:
	var t := clampf(time_progress, 0.0, 1.0)
	var shaped_progress := t
	match speed_variant:
		TravelSpeedVariant.FAST_THEN_SLOW:
			# 速度峰值靠前：12t(1-t)^2 的积分。
			shaped_progress = 6.0 * t * t - 8.0 * pow(t, 3.0) + 3.0 * pow(t, 4.0)
		TravelSpeedVariant.ACCELERATE_THEN_SLOW:
			# 速度峰值在中间：30t^2(1-t)^2 的积分。
			shaped_progress = 10.0 * pow(t, 3.0) - 15.0 * pow(t, 4.0) + 6.0 * pow(t, 5.0)
		TravelSpeedVariant.SLOW_THEN_FAST:
			# 速度峰值靠后：12t^2(1-t) 的积分。
			shaped_progress = 4.0 * pow(t, 3.0) - 3.0 * pow(t, 4.0)
		_:
			shaped_progress = t
	return lerpf(t, shaped_progress, clampf(variation_strength, 0.0, 1.0))


static func calculate_impact_delay(profile: Dictionary, speed_variant: int) -> float:
	var duration := maxf(float(profile.get("duration", 0.0)), 0.0)
	var terminal_progress := (
		1.0
		+ float(profile.get("trail_length", 0.0))
		+ float(profile.get("trail_softness", 0.0))
	)
	var required_progress := 1.0 / maxf(terminal_progress, 1.0)
	var low := 0.0
	var high := 1.0
	for _step: int in SOLVER_STEPS:
		var middle := (low + high) * 0.5
		if remap_travel_progress(
			middle,
			speed_variant,
			float(profile.get("speed_variation_strength", 0.0))
		) < required_progress:
			low = middle
		else:
			high = middle
	return high * duration
