class_name EmblemRecipeDiscovery
extends RefCounted

## 永久记录独立于一局存档；临时见闻只跟随当前局，取消也算见过配方。
const DEFAULT_PATH := "user://emblem_recipe_discovery.json"
var save_path := DEFAULT_PATH
var discovered: Array[String] = []
var encountered: Array[String] = []

func load_discoveries() -> void:
	discovered.clear()
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		for value: Variant in parsed:
			if value is String and value not in discovered:
				discovered.append(value)

func is_known(recipe_id: String) -> bool:
	return recipe_id in discovered or recipe_id in encountered

func encounter(recipe_id: String) -> void:
	if recipe_id not in encountered:
		encountered.append(recipe_id)

func discover(recipe_id: String) -> bool:
	encounter(recipe_id)
	if recipe_id in discovered:
		return true
	var next := discovered.duplicate()
	next.append(recipe_id)
	# 先写临时文件再替换，避免中断写入清空已有发现。
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(next))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path + ".tmp"), ProjectSettings.globalize_path(save_path)) != OK:
		return false
	discovered.assign(next)
	return true
