class_name HeroProgressState
extends RefCounted

## 英雄的本局经验和天赋选择；不负责卡牌、奖励演出或具体天赋效果。
## 经验曲线必须由正式配置传入，不能用测试数值补齐缺失的设计。
const TALENT_LEVELS: Array[int] = [1, 4, 7, 10]

var experience: int = 0
var level: int = 1
var selected_talents: Dictionary = {}
var pending_talent_levels: Array[int] = []
var committed_experience_awards: Array[String] = []

var _level_thresholds: Array[int] = []
var _talent_choices: Dictionary = {}


func initialize(level_thresholds: Array[int], talent_choices: Dictionary) -> bool:
	if level_thresholds.size() < TALENT_LEVELS.back() or level_thresholds[0] != 0:
		return false
	for index: int in range(1, level_thresholds.size()):
		if level_thresholds[index] <= level_thresholds[index - 1]:
			return false
	var validated_choices: Dictionary = {}
	var known_ids: Array[String] = []
	for talent_level: int in TALENT_LEVELS:
		var choices: Variant = talent_choices.get(str(talent_level))
		if not choices is Array or choices.size() != 4:
			return false
		var ids: Array[String] = []
		for id_value: Variant in choices:
			if not id_value is String or id_value.is_empty() or id_value in known_ids:
				return false
			ids.append(id_value)
			known_ids.append(id_value)
		validated_choices[str(talent_level)] = ids
	_level_thresholds.assign(level_thresholds)
	_talent_choices = validated_choices
	experience = 0
	level = 1
	selected_talents.clear()
	pending_talent_levels.assign([1])
	committed_experience_awards.clear()
	return true


func grant_experience(award_id: String, amount: int) -> bool:
	if _level_thresholds.is_empty() or award_id.is_empty() or amount < 0:
		return false
	if award_id in committed_experience_awards:
		return false
	# 先写入完整经验，再生成全部待选等级，选择第一项时已是最终等级。
	experience += amount
	level = _level_for_experience(experience)
	committed_experience_awards.append(award_id)
	_rebuild_pending_talent_levels()
	return true


func get_pending_choices() -> Array[String]:
	var result: Array[String] = []
	if not pending_talent_levels.is_empty():
		result.assign(_talent_choices[str(pending_talent_levels[0])])
	return result


func choose_talent(talent_id: String) -> bool:
	if pending_talent_levels.is_empty() or talent_id not in get_pending_choices():
		return false
	var talent_level: int = pending_talent_levels.pop_front()
	selected_talents[str(talent_level)] = talent_id
	return true


func has_talent(talent_id: String) -> bool:
	return talent_id in selected_talents.values()


func capture_state() -> Dictionary:
	return {
		"experience": experience,
		"level": level,
		"selected_talents": selected_talents.duplicate(true),
		"pending_talent_levels": pending_talent_levels.duplicate(),
		"committed_experience_awards": committed_experience_awards.duplicate(),
	}


func restore_state(snapshot: Dictionary) -> bool:
	if _level_thresholds.is_empty():
		return false
	var saved_experience: Variant = snapshot.get("experience")
	var saved_level: Variant = snapshot.get("level")
	var saved_selected: Variant = snapshot.get("selected_talents")
	var saved_pending: Variant = snapshot.get("pending_talent_levels")
	var saved_awards: Variant = snapshot.get("committed_experience_awards")
	if not _is_whole_number(saved_experience) or not _is_whole_number(saved_level):
		return false
	if int(saved_experience) < 0 or int(saved_level) != _level_for_experience(int(saved_experience)):
		return false
	if not saved_selected is Dictionary or not saved_pending is Array or not saved_awards is Array:
		return false
	var candidate_selected: Dictionary = {}
	var candidate_pending: Array[int] = []
	var selection_gap := false
	for talent_level: int in TALENT_LEVELS:
		var key := str(talent_level)
		if talent_level > int(saved_level):
			if saved_selected.has(key):
				return false
			continue
		if not saved_selected.has(key):
			selection_gap = true
			candidate_pending.append(talent_level)
			continue
		var talent_id: Variant = saved_selected[key]
		if selection_gap or not talent_id is String or talent_id not in _talent_choices[key]:
			return false
		candidate_selected[key] = talent_id
	if saved_selected.size() != candidate_selected.size() or saved_pending.size() != candidate_pending.size():
		return false
	for index: int in saved_pending.size():
		if not _is_whole_number(saved_pending[index]) or int(saved_pending[index]) != candidate_pending[index]:
			return false
	var candidate_awards: Array[String] = []
	for award_id: Variant in saved_awards:
		if not award_id is String or award_id.is_empty() or award_id in candidate_awards:
			return false
		candidate_awards.append(award_id)
	# 全部验证通过后一次替换；损坏存档不能污染当前本局状态。
	experience = int(saved_experience)
	level = int(saved_level)
	selected_talents = candidate_selected
	pending_talent_levels = candidate_pending
	committed_experience_awards = candidate_awards
	return true


func _level_for_experience(amount: int) -> int:
	var result := 1
	for index: int in range(1, _level_thresholds.size()):
		if amount < _level_thresholds[index]:
			break
		result = index + 1
	return result


func _rebuild_pending_talent_levels() -> void:
	pending_talent_levels.clear()
	for talent_level: int in TALENT_LEVELS:
		if talent_level <= level and not selected_talents.has(str(talent_level)):
			pending_talent_levels.append(talent_level)


func _is_whole_number(value: Variant) -> bool:
	# Godot 的 JSON 数字读取为 float，须允许整数值的 float，但拒绝小数和字符串。
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))
