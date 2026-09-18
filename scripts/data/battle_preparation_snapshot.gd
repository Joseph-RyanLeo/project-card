class_name BattlePreparationSnapshot
extends RefCounted

## 点击开战后、任何战斗效果前保存的内存快照。
## 阵容副本保留 OwnedCard 引用，收藏状态则保存这些实例当时的可变数据；恢复时
## 先回滚实例状态，再重建四排阵容，避免从战后 CardData 差额猜永久变化。

const OwnedCardCollection = preload("res://scripts/data/owned_card_collection.gd")

var battle_instance_id: StringName = &""
var battle_seed: int = 0
var _collection_state: Dictionary = {}
var _row_squads: Dictionary = {}
var _prepared_spell_instance_ids: Array[StringName] = []


func initialize(
	instance_id: StringName,
	seed: int,
	owned_collection: OwnedCardCollection,
	rows: Dictionary,
	prepared_spell_instance_ids: Array[StringName] = []
) -> bool:
	if instance_id.is_empty() or owned_collection == null:
		return false
	var validated_spell_ids: Array[StringName] = []
	var seen_spell_ids: Dictionary = {}
	for spell_instance_id: StringName in prepared_spell_instance_ids:
		var owned_spell = owned_collection.get_by_instance_id(spell_instance_id)
		if (
			spell_instance_id.is_empty()
			or seen_spell_ids.has(spell_instance_id)
			or owned_spell == null
			or owned_spell.card_data.card_type != CardData.CardType.SPELL
			or owned_spell.spell_durability <= 0
		):
			return false
		seen_spell_ids[spell_instance_id] = true
		validated_spell_ids.append(spell_instance_id)
	battle_instance_id = instance_id
	battle_seed = seed
	_collection_state = owned_collection.capture_state()
	_prepared_spell_instance_ids.assign(validated_spell_ids)
	_row_squads.clear()
	for row_key: Variant in rows:
		var copied_squads: Array[SquadData] = []
		for squad_value: Variant in rows[row_key] as Array:
			var squad := squad_value as SquadData
			if squad != null:
				copied_squads.append(squad.duplicate_squad())
		_row_squads[row_key] = copied_squads
	return true


func is_empty() -> bool:
	return battle_instance_id.is_empty() or _collection_state.is_empty()


func restore_collection(owned_collection: OwnedCardCollection) -> bool:
	return owned_collection != null and owned_collection.restore_state(_collection_state)


func get_collection_state_for_save() -> Dictionary:
	return _collection_state.duplicate(true)


func get_row_squads(row_key: StringName) -> Array[SquadData]:
	var result: Array[SquadData] = []
	for squad_value: Variant in _row_squads.get(row_key, []) as Array:
		var squad := squad_value as SquadData
		if squad != null:
			result.append(squad.duplicate_squad())
	return result


func get_prepared_spell_instance_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_prepared_spell_instance_ids)
	return result
