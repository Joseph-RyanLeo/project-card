class_name BattleEffectCatalog
extends RefCounted

## 把 D2-1 JSON 转成运行时可验证的严格效果定义；不负责把效果挂到真实卡牌。

var definitions: Dictionary = {}
var card_effect_ids: Dictionary = {}
var errors: Array[String] = []


static func load_from_file(path: String) -> BattleEffectCatalog:
	var result := BattleEffectCatalog.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.errors.append("无法读取效果数据：%s" % path)
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		result.errors.append("效果数据根节点必须是对象：%s" % path)
		return result
	result._parse_root(parsed as Dictionary)
	return result


func is_valid() -> bool:
	return errors.is_empty()


func get_definition(effect_id: StringName) -> BattleEffectDefinition:
	return definitions.get(effect_id) as BattleEffectDefinition


func _parse_root(data: Dictionary) -> void:
	if int(data.get("schema_version", -1)) != 2:
		errors.append("仅支持 schema_version=2")
	var cards: Variant = data.get("cards")
	if typeof(cards) != TYPE_ARRAY:
		errors.append("cards 必须是数组")
		return
	for card_index: int in (cards as Array).size():
		var card_value: Variant = cards[card_index]
		if typeof(card_value) != TYPE_DICTIONARY:
			errors.append("cards[%d] 必须是对象" % card_index)
			continue
		var card := card_value as Dictionary
		var card_id := StringName(card.get("card_id", ""))
		var ids: Array[StringName] = []
		var effects: Variant = card.get("effects")
		if typeof(effects) != TYPE_ARRAY:
			errors.append("cards[%d].effects 必须是数组" % card_index)
			continue
		for effect_index: int in (effects as Array).size():
			var effect_value: Variant = effects[effect_index]
			if typeof(effect_value) != TYPE_DICTIONARY:
				errors.append("cards[%d].effects[%d] 必须是对象" % [card_index, effect_index])
				continue
			var path := "cards[%d].effects[%d]" % [card_index, effect_index]
			var definition := BattleEffectDefinition.from_dictionary(effect_value as Dictionary, path, errors)
			if definition == null:
				continue
			if definitions.has(definition.effect_id):
				errors.append("%s.effect_id 重复：%s" % [path, definition.effect_id])
				continue
			if card_id == &"" or not String(definition.effect_id).begins_with("%s.effect." % card_id):
				errors.append("%s.effect_id 不属于 card_id=%s" % [path, card_id])
				continue
			definitions[definition.effect_id] = definition
			ids.append(definition.effect_id)
		card_effect_ids[card_id] = ids
	_validate_relations()


func _validate_relations() -> void:
	for definition_value: Variant in definitions.values():
		var definition := definition_value as BattleEffectDefinition
		for relation: Dictionary in definition.related_effects:
			var related_id := StringName(relation.get("effect_id", ""))
			if not definitions.has(related_id):
				errors.append("%s 关联了不存在的效果 %s" % [definition.effect_id, related_id])
