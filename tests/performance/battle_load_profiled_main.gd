extends "res://scripts/main.gd"

## 调用正式实现，只统计各路径耗时，不替代规则或渲染。
var load_profile: Dictionary = {}

func _measure(tag: String, began: int) -> void:
	var entry: Dictionary = load_profile.get(tag, {"calls": 0, "total_us": 0, "max_us": 0})
	var elapsed := Time.get_ticks_usec() - began
	entry.calls += 1
	entry.total_us += elapsed
	entry.max_us = maxi(entry.max_us, elapsed)
	load_profile[tag] = entry

func _sync_battle_formation_positions() -> void:
	var began := Time.get_ticks_usec()
	super._sync_battle_formation_positions()
	_measure("换位卡槽同步", began)

func _on_battle_states_changed() -> void:
	var began := Time.get_ticks_usec()
	super._on_battle_states_changed()
	_measure("卡面状态同步", began)

func _handle_battle_projectile_launched(event: BattleEffectEvent) -> void:
	var began := Time.get_ticks_usec()
	super._handle_battle_projectile_launched(event)
	_measure("弹道创建", began)

func _flush_run_diagnostic() -> void:
	var began := Time.get_ticks_usec()
	super._flush_run_diagnostic()
	_measure("本局诊断采集", began)

func _refresh_battle_log_text() -> void:
	var began := Time.get_ticks_usec()
	super._refresh_battle_log_text()
	_measure("日志显示", began)
