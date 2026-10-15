extends "res://scripts/battle/battle_controller.gd"

## 只观察正式调度入口，不替换时间推进、伤害或死亡处理。
var pending_poison_deadlines: Array[float] = []
func _get_next_event_delay() -> float:
	for status: Dictionary in _wound_periodic_effects:
		var state: BattleSquadState = status.state
		if state.alive and state.current_health <= 0.0 and is_finite(float(status.next_time)):
			pending_poison_deadlines.append(float(status.next_time))
	return super._get_next_event_delay()
