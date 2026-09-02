class_name BattleEffectEvent
extends RefCounted

## 一次原始战斗效果。数值再小也会生成事件并立即写入结构化日志。

enum EffectKind { DAMAGE, HEALING, ARMOR, PLACEHOLDER }

var group_id: int = 0
var logical_layer: int = 0
var sequence_index: int = 0
var timestamp: float = 0.0
var source: BattleSquadState
var target: BattleSquadState
var anchor: BattleSquadState
var action_type: CardData.ActionType = CardData.ActionType.MELEE
var effect_kind: EffectKind = EffectKind.DAMAGE
var element_type: int = -1
var element_count: int = 0
var exact_amount: float = 0.0
var effective_amount: float = 0.0
var armor_amount: float = 0.0
var health_amount: float = 0.0
var pierces_armor: bool = false
var is_base_action: bool = false
var is_continuous: bool = false
var is_finisher: bool = false
var can_trigger_element_chain: bool = true
var formula: BattleFormulaData
var visual_kind: StringName = &""
var log_qualifier: String = ""


func is_damage() -> bool:
	return effect_kind == EffectKind.DAMAGE


func is_benefit() -> bool:
	return effect_kind in [EffectKind.HEALING, EffectKind.ARMOR]
