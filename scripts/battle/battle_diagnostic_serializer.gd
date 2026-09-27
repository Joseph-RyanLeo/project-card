class_name BattleDiagnosticSerializer
extends RefCounted

## 将已冻结的单场记录写成可比较的 UTF-8 JSON；不访问战斗对象。

const SCHEMA_VERSION: int = 1
const FINGERPRINT_PATHS: Array[String] = [
	"res://scripts/main.gd",
	"res://scripts/battle/battle_controller.gd",
	"res://scripts/battle/battle_rules.gd",
	"res://scripts/battle/battle_formula_data.gd",
	"res://scripts/battle/battle_effect_event.gd",
	"res://scripts/battle/battle_squad_state.gd",
	"res://scripts/battle/effects/battle_effect_runtime.gd",
	"res://scripts/battle/effects/battle_effect_definition.gd",
	"res://scripts/battle/battle_diagnostic_recorder.gd",
	"res://scripts/battle/battle_diagnostic_serializer.gd",
]


static func build_document(record: Dictionary) -> Dictionary:
	var version_value: Variant = ProjectSettings.get_setting("application/config/version", "unknown")
	var project_version := String(version_value)
	if project_version.is_empty():
		project_version = "unknown"
	var version_info := Engine.get_version_info()
	var fingerprint := _content_fingerprint()
	return {
		"schema_version": SCHEMA_VERSION,
		"metadata": {
			"project_name": String(ProjectSettings.get_setting("application/config/name", "unknown")),
			"project_version": project_version,
			"project_version_status": "configured" if project_version != "unknown" else "unknown",
			"build_identifier": "unknown",
			"build_identifier_status": "unknown",
			"git_commit": "unknown",
			"working_tree_state": "unknown",
			"working_tree_status_reason": "Godot runtime does not query Git; a content fingerprint is included instead",
			"content_fingerprint": fingerprint,
			"godot_version": version_info,
			"exported_at": Time.get_datetime_string_from_system(true),
			"exported_at_unix_seconds": Time.get_unix_time_from_system(),
			"encoding": "UTF-8",
		},
		"battle": record.duplicate(true),
	}


static func to_json(document: Dictionary) -> String:
	return JSON.stringify(document, "\t", true, true)


static func save_to_path(record: Dictionary, path: String) -> Dictionary:
	if path.strip_edges().is_empty():
		return {"success": false, "reason": "empty_path", "path": path}
	var output_path := path if path.to_lower().ends_with(".json") else "%s.json" % path
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return {
			"success": false,
			"reason": "open_failed",
			"error": FileAccess.get_open_error(),
			"path": output_path,
		}
	var document := build_document(record)
	file.store_string(to_json(document))
	var error := file.get_error()
	file.close()
	if error != OK:
		return {"success": false, "reason": "write_failed", "error": error, "path": output_path}
	return {"success": true, "path": output_path, "document": document}


static func _content_fingerprint() -> Dictionary:
	var context := HashingContext.new()
	var error := context.start(HashingContext.HASH_SHA256)
	if error != OK:
		return {
			"algorithm": "SHA-256",
			"status": "unavailable",
			"reason": "HashingContext.start failed: %d" % error,
			"files": FINGERPRINT_PATHS.duplicate(),
		}
	var included: Array[String] = []
	var missing: Array[String] = []
	for path: String in FINGERPRINT_PATHS:
		if not FileAccess.file_exists(path):
			missing.append(path)
			continue
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			missing.append(path)
			continue
		context.update(path.to_utf8_buffer())
		context.update(PackedByteArray([0]))
		context.update(bytes)
		included.append(path)
	if included.is_empty():
		return {
			"algorithm": "SHA-256",
			"status": "unavailable",
			"reason": "no fingerprint source files could be read",
			"files": [],
			"missing_files": missing,
		}
	return {
		"algorithm": "SHA-256",
		"status": "partial" if not missing.is_empty() else "available",
		"value": context.finish().hex_encode(),
		"files": included,
		"missing_files": missing,
	}
