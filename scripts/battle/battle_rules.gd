class_name BattleRules
extends RefCounted

## 战斗数值与元素策略的单一配置入口。

const MINIMUM_COOLDOWN_SECONDS: float = CardData.MINIMUM_COOLDOWN_SECONDS # 所有基础值和后续冷却修正结算后的最低有效冷却（秒）
const MAXIMUM_COOLDOWN_SECONDS: float = CardData.MAXIMUM_COOLDOWN_SECONDS # 所有基础值和后续冷却修正结算后的最高有效冷却（秒）
const FATIGUE_BUFF_ID: StringName = &"fatigue" # 疲劳在统一战斗 Buff 容器中的稳定标识
const FATIGUE_START_SECONDS: float = 30.0 # 战斗经过多少秒后首次获得疲劳并立即承受疲劳伤害
const FATIGUE_STACK_INTERVAL_SECONDS: float = 2.0 # 疲劳开始后每隔多少秒增加一层
const FATIGUE_DAMAGE_INTERVAL_SECONDS: float = 1.0 # 疲劳开始后每隔多少秒结算一次直伤
const FATIGUE_DAMAGE_PER_STACK: int = 1 # 每层疲劳在每次结算时造成的无视护甲生命伤害
const LOGICAL_ROW_WIDTH: float = 832.0 # 每排用于投影、邻接和遮挡的逻辑宽度
const LOGICAL_SQUAD_GAP: float = 18.0 # 逻辑小队之间的固定间距，不能读取动画坐标
const FRONT_COVER_THRESHOLD: float = 0.5 # 后排宽度被前排实体覆盖超过该比例才降低权重

const BASE_ELEMENT_EFFECTS: Dictionary = {
	CardData.ElementType.FIRE: {"enabled": false, "action_value_per_rune": 0.0, "benefit_target": &"leftmost"},
	CardData.ElementType.WATER: {"enabled": false, "cooldown_ratio_per_rune": 0.0, "benefit_target": &"leftmost"},
	CardData.ElementType.LIGHT: {"enabled": false, "target_weight_per_rune": 0.0, "benefit_target": &"leftmost"},
	CardData.ElementType.DARK: {"enabled": false, "target_weight_per_rune": 0.0, "benefit_target": &"leftmost"},
	CardData.ElementType.WOOD: {"enabled": false, "max_health_per_rune": 0.0, "benefit_target": &"rightmost"},
} # 五元素基础收益的统一关闭入口，本阶段不得改变任何实际数值

const FIRE_CONFIG: Dictionary = {
	2: {"ticks": 3, "interval": 1.0, "tick_multiplier": 0.133, "finisher_multiplier": 0.0},
	3: {"ticks": 3, "interval": 1.0, "tick_multiplier": 0.20, "finisher_multiplier": 0.0},
	4: {"ticks": 4, "interval": 1.0, "tick_multiplier": 0.20, "finisher_multiplier": 0.0},
	5: {"ticks": 5, "interval": 1.0, "tick_multiplier": 0.16, "finisher_multiplier": 0.20},
} # 火的独立持续次数、间隔、每跳倍率与五火终结倍率
const WATER_CONFIG: Dictionary = {
	2: {"left": 1, "right": 1, "random_one_side": true, "multiplier": 0.40},
	3: {"left": 1, "right": 1, "random_one_side": false, "multiplier": 0.30},
	4: {"left": 1, "right": 1, "random_one_side": false, "multiplier": 0.40},
	5: {"left": 2, "right": 2, "random_one_side": false, "multiplier": 0.25},
} # 水的左右邻居数量、二水随机侧与单目标倍率
const DARK_CONFIG: Dictionary = {
	2: {"count": 1, "multiplier": 0.40},
	3: {"count": 1, "multiplier": 0.60},
	4: {"count": 2, "multiplier": 0.40},
	5: {"count": 3, "multiplier": 1.0 / 3.0},
} # 暗只追加攻击，基础主行动始终完整执行一次
const LIGHT_CONFIG: Dictionary = {
	2: {"count": 1, "multiplier": 0.40},
	3: {"count": 2, "multiplier": 0.30},
	4: {"count": 3, "multiplier": 0.80 / 3.0},
	5: {"count": 5, "multiplier": 0.20},
} # 光的折射次数与每次倍率
const WOOD_CONFIG: Dictionary = {
	2: {"multiplier": 0.40, "pierces_armor": false, "upgrade_primary": false},
	3: {"multiplier": 0.65, "pierces_armor": true, "upgrade_primary": false},
	4: {"multiplier": 0.90, "pierces_armor": true, "upgrade_primary": false},
	5: {"multiplier": 1.00, "pierces_armor": true, "upgrade_primary": true},
} # 木的跨排倍率、穿甲门槛与五木主行动升级开关

const STRAIGHT_BONUS_CONFIG: Dictionary = {
	"dark": {"count": 1, "multiplier": 1.0},
	"water": {"left": 1, "right": 1, "random_one_side": true, "multiplier": 1.0},
	"wood": {"multiplier": 1.0, "pierces_armor": true, "upgrade_primary": false},
	"light": {"count": 1, "multiplier": 1.0},
	"fire": {"ticks": 3, "interval": 1.0, "tick_multiplier": 0.5, "finisher_multiplier": 0.0, "can_trigger_element_chain": false},
} # 顺子额外生成四次 1.0B 即时效果和 3 秒共 1.5B 持续效果；全部不再触发元素连锁

const SAME_ELEMENT_TWO_PAIR_EFFECT_COUNT: int = 3 # 同花两对使用对应元素的三条档效果

const DEFAULT_EFFECT_STRATEGY: Dictionary = {
	"inherit_target": true,
	"retarget": false,
	"allow_repeat": false,
	"water_cross_side_fill": false,
	"dark_transfer_on_death": false,
	"continuous_stack_mode": &"independent",
	"wood_projection": &"closest_horizontal_center",
	"cover_mode": &"front_entity_union_over_half",
} # 特殊卡牌以后只覆盖这些策略，不改底层分层流程

const PATTERN_MULTIPLIERS: Dictionary = {
	RunePatternResult.PatternType.CHAOS: 1.0,
	RunePatternResult.PatternType.PAIR: 1.5,
	RunePatternResult.PatternType.THREE_OF_A_KIND: 2.0,
	RunePatternResult.PatternType.TWO_PAIR: 2.0,
	RunePatternResult.PatternType.SAME_ELEMENT_TWO_PAIR: 2.0,
	RunePatternResult.PatternType.FULL_HOUSE: 2.5,
	RunePatternResult.PatternType.FOUR_OF_A_KIND: 2.5,
	RunePatternResult.PatternType.FIVE_OF_A_KIND: 3.0,
	RunePatternResult.PatternType.STRAIGHT: 3.0,
} # 九种 Demo 牌型唯一的基础倍率表


static func get_pattern_multiplier(pattern_type: RunePatternResult.PatternType) -> float:
	return float(PATTERN_MULTIPLIERS.get(pattern_type, 1.0))


static func calculate_action_amount(
	base_value: int,
	pattern_type: RunePatternResult.PatternType
) -> int:
	# roundi 统一执行四舍五入，五种行动都必须经过这一入口。
	var capped_base_value := clampi(base_value, 0, CardData.MAXIMUM_BASE_VALUE)
	return maxi(
		roundi(float(capped_base_value) * get_pattern_multiplier(pattern_type)),
		0
	)


static func get_effective_cooldown(cooldown_seconds: float) -> float:
	# 冷却缩减等效果以后也必须经过此入口，不能突破统一下限。
	return clampf(
		cooldown_seconds,
		MINIMUM_COOLDOWN_SECONDS,
		MAXIMUM_COOLDOWN_SECONDS
	)


static func calculate_exact_action_amount(
	base_value: int,
	pattern_type: RunePatternResult.PatternType
) -> float:
	var capped_base_value := clampi(base_value, 0, CardData.MAXIMUM_BASE_VALUE)
	return float(capped_base_value) * get_pattern_multiplier(pattern_type)


static func get_element_config(element: CardData.ElementType, count: int) -> Dictionary:
	match element:
		CardData.ElementType.FIRE:
			return (FIRE_CONFIG.get(count, {}) as Dictionary).duplicate(true)
		CardData.ElementType.WATER:
			return (WATER_CONFIG.get(count, {}) as Dictionary).duplicate(true)
		CardData.ElementType.DARK:
			return (DARK_CONFIG.get(count, {}) as Dictionary).duplicate(true)
		CardData.ElementType.LIGHT:
			return (LIGHT_CONFIG.get(count, {}) as Dictionary).duplicate(true)
		CardData.ElementType.WOOD:
			return (WOOD_CONFIG.get(count, {}) as Dictionary).duplicate(true)
		_:
			return {}


static func build_effect_strategy(overrides: Dictionary = {}) -> Dictionary:
	# 特殊卡牌以后只提交差异字段；未知键不会污染底层策略。
	var strategy := DEFAULT_EFFECT_STRATEGY.duplicate(true)
	for key: Variant in overrides:
		if strategy.has(key):
			strategy[key] = overrides[key]
	return strategy
