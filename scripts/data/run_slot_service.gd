class_name RunSlotService
extends RefCounted

const SLOT_COUNT: int = 3
const SaveService = preload("res://scripts/data/run_save_service.gd")

var directory: String = "user://"
var selected_slot: int = 0
var last_used_slot: int = -1


func get_slot_path(index: int) -> String:
	if index < 0 or index >= SLOT_COUNT:
		return ""
	var filename := "project_card_run.json" if index == 0 else "project_card_run_%d.json" % (index + 1)
	return directory.path_join(filename)


func load_selection() -> void:
	var config := ConfigFile.new()
	if config.load(directory.path_join("run_slots.cfg")) == OK:
		selected_slot = clampi(int(config.get_value("slots", "selected", 0)), 0, SLOT_COUNT - 1)
		last_used_slot = clampi(int(config.get_value("slots", "last_used", selected_slot)), -1, SLOT_COUNT - 1)


func select_slot(index: int) -> Error:
	return _save_selection(index, last_used_slot)


func mark_slot_used(index: int) -> Error:
	return _save_selection(index, index)


func _save_selection(index: int, last: int) -> Error:
	if get_slot_path(index).is_empty(): return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	config.set_value("slots", "selected", index)
	config.set_value("slots", "last_used", last)
	var error := config.save(directory.path_join("run_slots.cfg"))
	if error == OK:
		selected_slot = index
		last_used_slot = last
	return error


func describe_slot(index: int) -> String:
	var path := get_slot_path(index)
	if not has_slot(index):
		return "空存档 · 进入后创建"
	var result := SaveService.new().load_checkpoint(path)
	if not result.get("success", false):
		return "存档无法读取 · 可选择后删除"
	var checkpoint: Dictionary = result.checkpoint
	var meta: Variant = checkpoint.get("profile_progress", {})
	var meta_progress := preload("res://scripts/data/profile_progress.gd").new()
	if checkpoint.has("profile_progress") and (not meta is Dictionary or not meta_progress.restore_state(meta)):
		return "存档无法读取 · 可选择后删除"
	var stage: String = meta_progress.run.stage if checkpoint.has("profile_progress") else "active"
	if stage != "active":
		return "%s · 积分 %d" % [{"summary": "局后总结", "selection": "待完成选卡", "preview": "待确认收藏", "hub": "局外休整"}.get(stage, "未知阶段"), int((meta.get("profile", {}) as Dictionary).get("points", 0))]
	var maze: Dictionary = checkpoint.get("short_maze", {})
	var run: Dictionary = maze.get("run", {})
	var progress := "第 %d 天" % int(run.get("day", 1)) if not run.is_empty() else "已保存的游戏"
	var gold := int((checkpoint.get("reward_state", {}) as Dictionary).get("gold", 0))
	var local_offset := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var read_path := path if FileAccess.file_exists(path) else path + ".bak"
	var saved_at := Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(read_path) + local_offset).replace("T", " ")
	return "本局 · %s · 积分 %d\n金币 %d · 保存 %s" % [progress, int(meta_progress.profile.points), gold, saved_at]


func delete_slot(index: int) -> Error:
	var path := get_slot_path(index)
	if path.is_empty():
		return ERR_INVALID_PARAMETER
	for suffix: String in [".tmp", ".bak", ".diagnostics.jsonl", ""]:
		if not FileAccess.file_exists(path + suffix):
			continue
		var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
		if error != OK:
			return error
	return OK


func has_slot(index: int) -> bool:
	var path := get_slot_path(index)
	return not path.is_empty() and (FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"))


func can_skip_tutorial() -> bool:
	# 唯一跨档查询：实际完成教程的现存档允许后建档选择跳过；不复制其进度。
	for index: int in SLOT_COUNT:
		var result := SaveService.new().load_checkpoint(get_slot_path(index))
		if not result.get("success", false): continue
		var state: Variant = result.checkpoint.get("profile_progress", {})
		var progress := preload("res://scripts/data/profile_progress.gd").new()
		if state is Dictionary and progress.restore_state(state) and progress.profile.tutorial.actually_completed:
			return true
	return false


func get_continue_slot() -> int:
	if has_slot(last_used_slot): return last_used_slot
	for index: int in SLOT_COUNT:
		if has_slot(index): return index
	return -1
