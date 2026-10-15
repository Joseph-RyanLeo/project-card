class_name BattleEffectEvent
extends RefCounted

const BattleResourceStateScript = preload("res://scripts/battle/battle_resource_state.gd")

## 一次原始战斗效果。数值再小也会生成事件并立即写入结构化日志。

enum EffectKind { DAMAGE, HEALING, ARMOR, PLACEHOLDER }

var group_id: int = 0
var logical_layer: int = 0
var sequence_index: int = 0
var timestamp: float = 0.0
var source: BattleSquadState
var target: BattleSquadState
var resource_target: RefCounted
var waits_for_death_chain: bool = false # 遗愿及明确保留的在途行动完成前暂缓胜负检查
var suppresses_echo: bool = false # 遗愿行动和附加开采不产生回响
var mining_followup_damage: float = 0.0 # 清障机成功开采后从资源发出的基础法术伤害
var origin_resource: RefCounted # 派生弹道的视觉起点资源
var is_environment_damage: bool = false # 环境穿甲只绕过护甲，不触发晶皮哨兵穿甲即死
var is_mining: bool = false # 开采行动的主事件；命中资源时击碎而非造成普通1点伤害
var anchor: BattleSquadState
var source_emblem_instance_id: StringName = &"" # 纹章生成事件保留纹章实例身份
var source_owned_card_instance_id: StringName = &"" # 纹章所在OwnedCard，不等同于效果目标小队
var action_type: CardData.ActionType = CardData.ActionType.MELEE
var effect_kind: EffectKind = EffectKind.DAMAGE
var element_type: int = -1
var element_count: int = 0
var exact_amount: float = 0.0
var effective_amount: float = 0.0
var armor_amount: float = 0.0
var health_amount: float = 0.0
var pierces_armor: bool = false
var dual_melee_ranged: bool = false # 瑟兰同一快照的双标签，命中时只择较高倍率
var is_silvermoon_repeat: bool = false # 树种追加行动不递归触发自身
var is_link_copy: bool = false # 完整行动复制不重复消耗链接
var is_equipment_repeat: bool = false # 本装备产生的追加行动不能递归触发自身
var is_attack_action_damage: bool = false # 主行动与非持续元素伤害属于完整攻击行动
var is_base_action: bool = false
var is_continuous: bool = false
var is_finisher: bool = false
var can_trigger_element_chain: bool = true
var missed: bool = false
var uses_attack_type_multiplier: bool = false
var attack_type_multiplier: float = 1.0
var target_had_armor_on_impact: bool = false
var launch_sequence: int = -1
var projectile_speed_variant: int = 0
var projectile_impact_delay: float = 0.0
var impact_time: float = 0.0
var formula: BattleFormulaData
var visual_kind: StringName = &""
var log_qualifier: String = ""
var sentry_absorbed: float = 0.0
var sentry_remaining: float = 0.0
var sentry_region: String = ""
var fractional_channel_snapshots: Array[Dictionary] = []


func is_damage() -> bool:
	return effect_kind == EffectKind.DAMAGE


func is_benefit() -> bool:
	return effect_kind in [EffectKind.HEALING, EffectKind.ARMOR]
