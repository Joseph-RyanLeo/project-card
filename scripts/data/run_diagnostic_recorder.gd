extends RefCounted

## 最近操作的只读状态差异日志，与本局存档分开保存，不参与玩法恢复。
const MAX_EVENTS := 600 # 导出最多保留的近期事件数量
const MAX_JOURNAL_BYTES := 4 * 1024 * 1024 # 单个自动日志文件的容量上限，另保留一个轮转文件
const MAX_ENGINE_LOG_BYTES := 96 * 1024 # 每份引擎日志只读取末尾的字节数

var events: Array[Dictionary] = []
var persistence_error: Error = OK
var journal_path := ""
var session_id := ""
var _previous: Dictionary = {}
var _sequence := 0
var unreadable_lines := 0


func initialize(path: String) -> void:
	journal_path = path
	session_id = "%s-%s" % [Time.get_datetime_string_from_system(true), Time.get_ticks_usec()]
	for source: String in [path + ".previous", path]:
		if not FileAccess.file_exists(source): continue
		var file := FileAccess.open(source, FileAccess.READ)
		if file == null: continue
		while not file.eof_reached():
			var line := file.get_line()
			if line.is_empty(): continue
			var parser := JSON.new()
			if parser.parse(line) != OK:
				unreadable_lines += 1
				continue
			var entry: Variant = parser.data
			if entry is Dictionary and entry.get("schema_version") == 1:
				events.append(entry)
				if events.size() > MAX_EVENTS: events.pop_front()
		file.close()


func observe(kind: String, state: Dictionary, detail: Dictionary = {}, force: bool = false) -> void:
	var changes: Dictionary = {}
	for section: String in state:
		var before: Variant = _previous.get(section)
		var after: Variant = state[section]
		if before == after: continue
		if section == "cards" and before is Dictionary:
			var card_changes: Dictionary = {}
			var ids: Dictionary = {}
			for id: String in before: ids[id] = true
			for id: String in after: ids[id] = true
			for id: String in ids:
				if before.get(id) != after.get(id):
					card_changes[id] = {"before": before.get(id), "after": after.get(id)}
			changes[section] = card_changes
		else:
			changes[section] = {"before": before, "after": after}
	_previous = state.duplicate(true)
	if changes.is_empty() and not force: return
	_sequence += 1
	var entry := {
		"schema_version": 1, "session_id": session_id, "sequence": _sequence,
		"version": String(ProjectSettings.get_setting("application/config/version", "unknown")),
		"utc": Time.get_datetime_string_from_system(true), "ticks_ms": Time.get_ticks_msec(),
		"kind": kind, "detail": detail.duplicate(true), "changes": changes,
	}
	events.append(entry)
	if events.size() > MAX_EVENTS: events.pop_front()
	_append(entry)


func _append(entry: Dictionary) -> void:
	if journal_path.is_empty(): return
	if FileAccess.file_exists(journal_path):
		var existing := FileAccess.open(journal_path, FileAccess.READ)
		if existing != null:
			var length := existing.get_length()
			existing.close()
			if length >= MAX_JOURNAL_BYTES:
				var previous := ProjectSettings.globalize_path(journal_path + ".previous")
				if FileAccess.file_exists(previous): DirAccess.remove_absolute(previous)
				persistence_error = DirAccess.rename_absolute(ProjectSettings.globalize_path(journal_path), previous)
				if persistence_error != OK: return
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(journal_path) else FileAccess.WRITE
	var file := FileAccess.open(journal_path, mode)
	if file == null:
		persistence_error = FileAccess.get_open_error()
		return
	file.seek_end()
	file.store_line(JSON.stringify(entry))
	file.flush()
	persistence_error = file.get_error()
	file.close()


func save_last_battle(record: Dictionary) -> void:
	var file := FileAccess.open(journal_path + ".battle.json", FileAccess.WRITE)
	if file == null:
		persistence_error = FileAccess.get_open_error()
		return
	file.store_string(JSON.stringify({"version": ProjectSettings.get_setting("application/config/version"), "session_id": session_id, "battle": record}))
	file.flush()
	persistence_error = file.get_error()
	file.close()


func build_document(current: Dictionary, save_path: String) -> Dictionary:
	var logs: Array[Dictionary] = []
	var log_path := String(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	var directory := log_path.get_base_dir()
	var names := DirAccess.get_files_at(directory)
	names.sort()
	var rotated: Array[String] = []
	for filename: String in names:
		if filename.begins_with("godot") and filename.ends_with(".log") and directory.path_join(filename) != log_path:
			rotated.append(directory.path_join(filename))
	for index: int in range(maxi(0, rotated.size() - 2), rotated.size()):
		logs.append(_read_log_tail(rotated[index]))
	logs.append(_read_log_tail(log_path))
	return {
		"schema_version": 1, "kind": "project_card_run_diagnostics",
		"metadata": {"version": ProjectSettings.get_setting("application/config/version"), "godot": Engine.get_version_info(), "os": OS.get_name(), "utc": Time.get_datetime_string_from_system(true), "session_id": session_id},
		"recording": {"max_events": MAX_EVENTS, "automatic_write_error": error_string(persistence_error), "history_is_bounded": true, "unreadable_history_lines": unreadable_lines},
		"recent_events": events.duplicate(true), "current_state": current.duplicate(true),
		"saved_checkpoint": _read_json(save_path), "last_completed_battle": _read_json(journal_path + ".battle.json"),
		"engine_logs": logs,
	}


func save_export(path: String, document: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(document))
	file.flush()
	var result := file.get_error()
	file.close()
	return result


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _read_log_tail(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"file": path.get_file(), "available": false}
	var truncated := file.get_length() > MAX_ENGINE_LOG_BYTES
	file.seek(maxi(0, file.get_length() - MAX_ENGINE_LOG_BYTES))
	var bytes := file.get_buffer(MAX_ENGINE_LOG_BYTES)
	if truncated:
		var newline := bytes.find(10)
		bytes = bytes.slice(newline + 1) if newline >= 0 else PackedByteArray()
	var content := bytes.get_string_from_utf8()
	file.close()
	return {"file": path.get_file(), "available": true, "truncated": truncated, "text": content}
