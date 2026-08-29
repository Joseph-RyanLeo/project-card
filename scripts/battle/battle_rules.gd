class_name BattleRules
extends RefCounted

## 阶段 7 的基础战斗数值配置。
## 牌型倍率与整数取整只在这里定义，行动控制器不再各自维护规则副本。

const MINIMUM_COOLDOWN_SECONDS: float = CardData.MINIMUM_COOLDOWN_SECONDS # 所有基础值和后续冷却修正结算后的最低有效冷却（秒）
const MAXIMUM_COOLDOWN_SECONDS: float = CardData.MAXIMUM_COOLDOWN_SECONDS # 所有基础值和后续冷却修正结算后的最高有效冷却（秒）
const FATIGUE_BUFF_ID: StringName = &"fatigue" # 疲劳在统一战斗 Buff 容器中的稳定标识
const FATIGUE_START_SECONDS: float = 30.0 # 战斗经过多少秒后首次获得疲劳并立即承受疲劳伤害
const FATIGUE_STACK_INTERVAL_SECONDS: float = 2.0 # 疲劳开始后每隔多少秒增加一层
const FATIGUE_DAMAGE_INTERVAL_SECONDS: float = 1.0 # 疲劳开始后每隔多少秒结算一次直伤
const FATIGUE_DAMAGE_PER_STACK: int = 1 # 每层疲劳在每次结算时造成的无视护甲生命伤害

const PATTERN_MULTIPLIERS: Dictionary = {
	RunePatternResult.PatternType.CHAOS: 1.0,
	RunePatternResult.PatternType.PAIR: 1.5,
	RunePatternResult.PatternType.THREE_OF_A_KIND: 2.0,
	RunePatternResult.PatternType.TWO_PAIR: 2.0,
	RunePatternResult.PatternType.SAME_ELEMENT_TWO_PAIR: 2.2,
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
