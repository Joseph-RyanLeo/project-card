class_name BattleEventQueue
extends RefCounted

## 队列只使用整数微秒和显式序号排序，不依赖帧率或 Dictionary 遍历顺序。

const MICROSECONDS_PER_SECOND: int = 1_000_000

var _events: Array[BattleRuntimeEvent] = []
var _next_event_id: int = 1
var _next_stable_order: int = 1


func clear() -> void:
	_events.clear()
	_next_event_id = 1
	_next_stable_order = 1


func schedule(event: BattleRuntimeEvent, parent: BattleRuntimeEvent = null) -> BattleRuntimeEvent:
	event.event_id = _next_event_id
	_next_event_id += 1
	event.stable_order = _next_stable_order
	_next_stable_order += 1
	if parent != null:
		event.parent_event_id = parent.event_id
		event.root_event_id = parent.root_event_id if parent.root_event_id > 0 else parent.event_id
	else:
		event.root_event_id = event.event_id
	_events.append(event)
	_events.sort_custom(BattleRuntimeEvent.is_before)
	return event


func pop_due(logical_time_us: int) -> Array[BattleRuntimeEvent]:
	var result: Array[BattleRuntimeEvent] = []
	while not _events.is_empty() and _events[0].logical_time_us <= logical_time_us:
		var event: BattleRuntimeEvent = _events.pop_front()
		if not event.cancelled:
			result.append(event)
	return result


func pop_next_due(logical_time_us: int) -> BattleRuntimeEvent:
	while not _events.is_empty() and _events[0].logical_time_us <= logical_time_us:
		var event: BattleRuntimeEvent = _events.pop_front()
		if not event.cancelled:
			return event
	return null


func get_next_time_us() -> int:
	return _events[0].logical_time_us if not _events.is_empty() else -1


func cancel_instance(instance_id: int) -> void:
	for event: BattleRuntimeEvent in _events:
		if event.effect_instance != null and event.effect_instance.instance_id == instance_id:
			event.cancelled = true


func size() -> int:
	return _events.size()


static func seconds_to_us(seconds: float) -> int:
	return maxi(roundi(seconds * float(MICROSECONDS_PER_SECOND)), 0)


static func us_to_seconds(microseconds: int) -> float:
	return float(microseconds) / float(MICROSECONDS_PER_SECOND)
