extends "res://scripts/battle/battle_controller.gd"

## 保留正式规则调用，仅为负载探针记录调用耗时。
var load_profile: Dictionary = {}

func _measure(tag: String, began: int) -> void:
	var entry: Dictionary = load_profile.get(tag, {"calls": 0, "total_us": 0, "max_us": 0})
	var elapsed := Time.get_ticks_usec() - began
	entry.calls += 1
	entry.total_us += elapsed
	entry.max_us = maxi(entry.max_us, elapsed)
	load_profile[tag] = entry

func recalculate_logical_layout() -> void:
	var began := Time.get_ticks_usec()
	super.recalculate_logical_layout()
	_measure("recalculate_logical_layout", began)

func _resolve_ready_batch() -> void:
	var began := Time.get_ticks_usec()
	super._resolve_ready_batch()
	_measure("_resolve_ready_batch", began)

func _resolve_projectile_impact(event: BattleEffectEvent) -> void:
	var began := Time.get_ticks_usec()
	super._resolve_projectile_impact(event)
	_measure("_resolve_projectile_impact", began)

func _apply_effect_event(event: BattleEffectEvent) -> void:
	var began := Time.get_ticks_usec()
	super._apply_effect_event(event)
	_measure("_apply_effect_event", began)

func _get_next_event_delay() -> float:
	var began := Time.get_ticks_usec()
	var result := super._get_next_event_delay()
	_measure("_get_next_event_delay", began)
	return result
