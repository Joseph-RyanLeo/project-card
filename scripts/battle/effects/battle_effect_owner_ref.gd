class_name BattleEffectOwnerRef
extends RefCounted

## 战斗内的来源/结果归属引用。D2-3 只保证本场唯一，跨战斗永久身份留给 D2-5。

var runtime_id: int = 0
var owner_kind: BattleEffectDefinition.OwnerKind = BattleEffectDefinition.OwnerKind.AFFECTED_COMBAT_UNIT
var state: BattleSquadState
var card_data: CardData
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
			BattleEffectDefinition.OwnerKind.ACTION_PROVIDER_CARD:
				result.card_data = value.get_action_source()
			BattleEffectDefinition.OwnerKind.ARMOR_PROVIDER_CARD:
				result.card_data = value.get_vitals_source()
		if result.card_data != null and value.squad_data != null:
			result.card_index = value.squad_data.horizontal_cards.find(result.card_data)
	return result


func is_valid() -> bool:
	if state != null:
		return state.runtime_id == runtime_id
	return runtime_id > 0


func is_alive() -> bool:
	return state != null and state.alive and state.current_health > 0.0


func stable_key() -> String:
	return "%d:%d:%d" % [owner_kind, runtime_id, card_index]
