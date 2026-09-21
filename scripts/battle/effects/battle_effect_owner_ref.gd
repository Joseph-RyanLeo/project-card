class_name BattleEffectOwnerRef
extends RefCounted

## 战斗内的来源/结果归属引用。runtime_id 负责本场定位，owned_card_instance_id
## 负责跨战斗写回；两者不能互相替代。

const OwnedCard = preload("res://scripts/data/owned_card.gd")

var runtime_id: int = 0
var owner_kind: BattleEffectDefinition.OwnerKind = BattleEffectDefinition.OwnerKind.AFFECTED_COMBAT_UNIT
var state: BattleSquadState
var card_data: CardData
var owned_card: OwnedCard
var owned_card_instance_id: StringName = &""
var card_index: int = -1


static func for_state(
	value: BattleSquadState,
	kind: BattleEffectDefinition.OwnerKind = BattleEffectDefinition.OwnerKind.AFFECTED_COMBAT_UNIT
) -> BattleEffectOwnerRef:
	var result := BattleEffectOwnerRef.new()
	result.state = value
	result.owner_kind = kind
	result.runtime_id = value.runtime_id if value != null else 0
	if value != null:
		match kind:
			BattleEffectDefinition.OwnerKind.MINION_CARD_INSTANCE:
				result.card_data = value.get_effect_source()
			BattleEffectDefinition.OwnerKind.EQUIPMENT_INSTANCE:
				if value.squad_data != null:
					result.owned_card = value.squad_data.get_equipped_item()
					if result.owned_card != null:
						result.card_data = result.owned_card.card_data
			BattleEffectDefinition.OwnerKind.ACTION_PROVIDER_CARD:
				result.card_data = value.get_action_source()
			BattleEffectDefinition.OwnerKind.ARMOR_PROVIDER_CARD:
				result.card_data = value.get_vitals_source()
		if result.card_data != null and value.squad_data != null:
			result.card_index = value.squad_data.horizontal_cards.find(result.card_data)
			if result.owned_card == null:
				result.owned_card = value.squad_data.get_owned_card(result.card_data)
			if result.owned_card != null:
				result.owned_card_instance_id = result.owned_card.instance_id
	return result


func is_valid() -> bool:
	if state != null:
		return state.runtime_id == runtime_id
	return runtime_id > 0


func is_alive() -> bool:
	return state != null and state.alive and state.current_health > 0.0


func stable_key() -> String:
	return "%d:%d:%d:%s" % [owner_kind, runtime_id, card_index, owned_card_instance_id]
