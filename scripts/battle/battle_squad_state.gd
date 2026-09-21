class_name BattleSquadState
extends RefCounted

## 单个小队的一场战斗临时状态。
## current_health/current_armor 保存精确值；displayed_* 只保存卡面整数。

const BattleRules = preload("res://scripts/battle/battle_rules.gd")

signal integer_settlement_committed(event: Dictionary)
signal health_lost_accumulated(event: Dictionary)

enum Side { PLAYER, ENEMY }

const CHANNEL_HEALTH_DAMAGE: StringName = &"health_damage"
const CHANNEL_ARMOR_DAMAGE: StringName = &"armor_damage"
const CHANNEL_HEALING: StringName = &"healing"
const CHANNEL_ARMOR_GAIN: StringName = &"armor_gain"

var squad_data: SquadData
var runtime_id: int = 0 # 本场战斗内的稳定实例编号，不作为跨战斗收藏身份
var side: int = Side.PLAYER
var row_key: StringName = &""
var formation_index: int = 0
var current_health = 0:
	set(value):
		current_health = value
		if not _precise_write:
			# 生命上限降低不再截断当前生命，所以卡面必须能显示
			# 暂时高于新上限的真实生命，只受全局生命数值上限限制。
			displayed_health = clampi(roundi(value), 0, CardData.MAXIMUM_HEALTH)
var current_armor = 0:
	set(value):
		current_armor = value
		if not _precise_write:
			displayed_armor = clampi(roundi(value), 0, CardData.MAXIMUM_ARMOR)
var displayed_health: int = 0
var displayed_armor: int = 0
var cooldown_progress: float = 0.0 # 0表示刚重置，1表示普通行动已经就绪
var remaining_cooldown: float = 0.0:
	set(value):
		remaining_cooldown = maxf(value, 0.0)
		if not _syncing_cooldown:
			var interval := get_action_interval()
			cooldown_progress = clampf(1.0 - remaining_cooldown / interval, 0.0, 1.0) if interval > 0.0 else 1.0
var alive: bool = true
var buff_stacks: Dictionary = {} # 本场战斗的临时 Buff 层数，键使用稳定标识
var modifiers := BattleModifierContainer.new()
var fractional_accumulators: Dictionary = {
	CHANNEL_HEALTH_DAMAGE: 0.0,
	CHANNEL_ARMOR_DAMAGE: 0.0,
	CHANNEL_HEALING: 0.0,
	CHANNEL_ARMOR_GAIN: 0.0,
}
var pending_kill_source: BattleSquadState
var pending_kill_event: BattleEffectEvent
var logical_left: float = 0.0
var logical_right: float = 0.0
var logical_center: float = 0.0
var runtime_base_cooldown_override: float = -1.0 # 负数表示使用卡牌基础冷却；战斗实验室可注入最长99秒的测试值
var battle_damage_dealt: float = 0.0
var battle_damage_dealt_by_action: Dictionary = {} # 行动类型→实际伤害；结算卡面据此分开展示多种攻击方式
var battle_damage_taken: float = 0.0
var battle_healing_done: float = 0.0
var battle_armor_granted: float = 0.0
var battle_health_lost: float = 0.0 # 本场累计生命伤害；治疗与重新入场均不回退
var runtime_action_type_override: int = -1 # 负数读取原卡行动方式；非负值只在本场战斗覆盖，不写回CardData
var masked_rune_slots: Dictionary = {} # 本场被遮蔽的符文槽；键由卡牌实例与槽位组成，值保留显示所需定位
var battle_active_injury_ids: Array[StringName] = [] # 由后续伤势系统注入的本场生效伤势身份；D2-4不自行生成伤势
var battle_injury_levels: Dictionary = {} # 伤势身份→等级；遮蔽优先级依据实例槽位等级而非名称猜测
var injury_mask_sources: Dictionary = {} # 伤势身份→遮蔽运行实例集合；多个来源独立到期
var runtime_keyword_sources: Dictionary = {} # 临时关键词→效果实例集合；每个来源独立撤销，不改写共享卡牌资源
var moon_shadowed: bool = false
var moon_restore_time: float = INF
var life_generation: int = 0 # 每次重新入场递增，用于区分已经失效的旧退场动画

var _precise_write: bool = false
var _syncing_cooldown: bool = false


func initialize(
	value: SquadData,
	battle_side: int,
	row: StringName,
	index: int,
	base_cooldown_override: float = -1.0
) -> void:
	squad_data = value.duplicate_squad() if value != null else null
	side = battle_side
	row_key = row
	formation_index = index
	runtime_base_cooldown_override = base_cooldown_override
	_set_exact_health(value.get_effective_max_health() if value != null else 0)
	_set_exact_armor(value.get_effective_base_armor() if value != null else 0)
	displayed_health = clampi(roundi(current_health), 0, get_max_health())
	displayed_armor = clampi(roundi(current_armor), 0, CardData.MAXIMUM_ARMOR)
	cooldown_progress = 0.0
	modifiers.clear()
	reset_action_cooldown()
	alive = current_health > 0.0
	life_generation = 0
	buff_stacks.clear()
	clear_precise_runtime()
	moon_shadowed = squad_data != null and squad_data.has_indicator(CelestialIndicator.Kind.MOON)
	moon_restore_time = INF
	_load_owned_card_injuries()
	clear_battle_statistics()


func clear_precise_runtime() -> void:
	for channel: StringName in fractional_accumulators.keys():
		fractional_accumulators[channel] = 0.0
	pending_kill_source = null
	pending_kill_event = null
	runtime_action_type_override = -1
	masked_rune_slots.clear()
	battle_active_injury_ids.clear()
	battle_injury_levels.clear()
	injury_mask_sources.clear()
	runtime_keyword_sources.clear()


func clear_battle_statistics() -> void:
	battle_damage_dealt = 0.0
	battle_damage_dealt_by_action.clear()
	battle_damage_taken = 0.0
	battle_healing_done = 0.0
	battle_armor_granted = 0.0
	battle_health_lost = 0.0


func revive_at_current_maximum(health_amount: float) -> bool:
	# 重新入场只恢复已确认的生命与基础护甲；冷却、强化和符文遮蔽
	# 保持本场当前状态，避免替未确认规则擅自重置。
	if get_vitals_source() == null or squad_data == null:
		return false
	var restored_health := minf(maxf(health_amount, 0.0), float(get_max_health()))
	if restored_health <= 0.0:
		return false
	_set_exact_health(restored_health)
	_set_exact_armor(float(squad_data.get_effective_base_armor()))
	displayed_health = clampi(roundi(current_health), 0, get_max_health())
	displayed_armor = clampi(roundi(current_armor), 0, CardData.MAXIMUM_ARMOR)
	for channel: StringName in fractional_accumulators:
		fractional_accumulators[channel] = 0.0
	pending_kill_source = null
	pending_kill_event = null
	alive = true
	life_generation += 1
	return true


func get_battle_statistics() -> Dictionary:
	return {
		"damage_dealt": battle_damage_dealt,
		"damage_dealt_by_action": battle_damage_dealt_by_action.duplicate(true),
		"damage_taken": battle_damage_taken,
		"healing_done": battle_healing_done,
		"armor_granted": battle_armor_granted,
	}


func get_action_source() -> CardData:
	return squad_data.get_action_source() if squad_data != null else null


func get_vitals_source() -> CardData:
	return squad_data.get_vitals_source() if squad_data != null else null


func get_effect_source() -> CardData:
	return squad_data.get_effect_source() if squad_data != null else null


func get_effective_action_type() -> CardData.ActionType:
	if runtime_action_type_override >= 0:
		return runtime_action_type_override as CardData.ActionType
	return squad_data.get_effective_action_type() if squad_data != null else CardData.ActionType.MELEE


func set_runtime_action_type(value: CardData.ActionType) -> void:
	runtime_action_type_override = int(value)


func clear_runtime_action_type() -> void:
	runtime_action_type_override = -1


func get_max_health() -> int:
	var base := float(squad_data.get_effective_max_health()) if squad_data != null else 0.0
	return clampi(roundi(base + modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH)), 0, CardData.MAXIMUM_HEALTH)


func get_target_weight() -> int:
	var base := float(CardData.get_base_target_priority_for_action(get_effective_action_type()))
	# 通用基础权重最低为1；明确写出“最低0”的卡牌效果可以把最终权重降到0。
	return maxi(roundi(base + modifiers.get_additive(BattleModifier.Stat.TARGET_PRIORITY)), 0)


func get_target_action_type_preference() -> int:
	var source := get_action_source()
	return source.preferred_target_action_type if source != null else -1


func has_targeting_keyword(keyword: StringName) -> bool:
	if has_runtime_keyword(keyword):
		return true
	if squad_data == null:
		return false
	for card: CardData in squad_data.horizontal_cards:
		if card != null and card.has_keyword(keyword):
			return true
	var item := squad_data.get_equipped_item()
	return item != null and item.card_data != null and item.card_data.has_keyword(keyword)


func get_exact_action_amount() -> float:
	if get_action_source() == null or squad_data == null:
		return 0.0
	var modified_base := clampi(
		roundi(float(squad_data.get_effective_action_base_value()) + modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE)),
		0,
		CardData.MAXIMUM_BASE_VALUE
	)
	var base_result := BattleRules.calculate_exact_action_amount(modified_base, get_rune_pattern_result().pattern_type)
	return base_result * maxf(0.0, 1.0 + modifiers.get_additive(BattleModifier.Stat.ACTION_MULTIPLIER))


func get_active_rune_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if squad_data == null:
		return result
	for slot: Dictionary in squad_data.get_visible_rune_slots():
		var card := slot.get("card") as CardData
		var rune_index := int(slot.get("rune_index", -1))
		if not masked_rune_slots.has(_rune_slot_key(card, rune_index)):
			result.append(slot)
	return result


func get_active_runes() -> Array[CardData.ElementType]:
	var result: Array[CardData.ElementType] = []
	for slot: Dictionary in get_active_rune_slots():
		result.append(slot["element"] as CardData.ElementType)
	return result


func get_rune_pattern_result() -> RunePatternResult:
	return RunePatternRules.identify(get_active_runes())


func mask_rune_slot(card: CardData, rune_index: int) -> bool:
	if card == null or rune_index < 0:
		return false
	var key := _rune_slot_key(card, rune_index)
	if masked_rune_slots.has(key):
		return false
	for slot: Dictionary in get_active_rune_slots():
		if slot.get("card") == card and int(slot.get("rune_index", -1)) == rune_index:
			masked_rune_slots[key] = {
				"card": card,
				"rune_index": rune_index,
			}
			return true
	return false


func unmask_rune_slot(card: CardData, rune_index: int) -> bool:
	return masked_rune_slots.erase(_rune_slot_key(card, rune_index))


func set_battle_active_injuries(injury_ids: Array[StringName], injury_levels: Dictionary = {}) -> void:
	battle_active_injury_ids.clear()
	battle_injury_levels.clear()
	injury_mask_sources.clear()
	for injury_id: StringName in injury_ids:
		if injury_id != &"" and not battle_active_injury_ids.has(injury_id):
			battle_active_injury_ids.append(injury_id)
			battle_injury_levels[injury_id] = maxi(int(injury_levels.get(injury_id, 0)), 0)


func _load_owned_card_injuries() -> void:
	if squad_data == null:
		return
	var injury_ids: Array[StringName] = []
	var levels: Dictionary = {}
	for card_data: CardData in squad_data.horizontal_cards:
		var owned_card := squad_data.get_owned_card(card_data)
		if owned_card == null:
			continue
		for slot_index: int in owned_card.wound_slots.size():
			var wound := owned_card.wound_slots[slot_index]
			if (wound.get("wound_id", &"") as StringName).is_empty():
				continue
			var injury_key := StringName("%s:wound:%d" % [owned_card.instance_id, slot_index])
			injury_ids.append(injury_key)
			levels[injury_key] = maxi(int(wound.get("level", 0)), 0)
	set_battle_active_injuries(injury_ids, levels)


func get_unmasked_active_injuries() -> Array[StringName]:
	var result: Array[StringName] = []
	for injury_id: StringName in battle_active_injury_ids:
		var sources := injury_mask_sources.get(injury_id, {}) as Dictionary
		if sources.is_empty():
			result.append(injury_id)
	return result


func has_unmasked_active_injury() -> bool:
	return not get_unmasked_active_injuries().is_empty()


func mask_injury(injury_id: StringName, source_instance_id: int) -> bool:
	if injury_id == &"" or source_instance_id <= 0 or not battle_active_injury_ids.has(injury_id):
		return false
	var sources := injury_mask_sources.get(injury_id, {}) as Dictionary
	sources[source_instance_id] = true
	injury_mask_sources[injury_id] = sources
	return true


func unmask_injury(injury_id: StringName, source_instance_id: int) -> bool:
	if not injury_mask_sources.has(injury_id):
		return false
	var sources := injury_mask_sources[injury_id] as Dictionary
	var removed := sources.erase(source_instance_id)
	if sources.is_empty():
		injury_mask_sources.erase(injury_id)
	else:
		injury_mask_sources[injury_id] = sources
	return removed


func is_injury_masked(injury_id: StringName) -> bool:
	return not (injury_mask_sources.get(injury_id, {}) as Dictionary).is_empty()


func grant_runtime_keyword(keyword: StringName, source_instance_id: int) -> bool:
	if keyword.is_empty() or source_instance_id <= 0:
		return false
	var sources := runtime_keyword_sources.get(keyword, {}) as Dictionary
	sources[source_instance_id] = true
	runtime_keyword_sources[keyword] = sources
	return true


func revoke_runtime_keyword(keyword: StringName, source_instance_id: int) -> void:
	var sources := runtime_keyword_sources.get(keyword, {}) as Dictionary
	sources.erase(source_instance_id)
	if sources.is_empty():
		runtime_keyword_sources.erase(keyword)
	else:
		runtime_keyword_sources[keyword] = sources


func has_runtime_keyword(keyword: StringName) -> bool:
	return not (runtime_keyword_sources.get(keyword, {}) as Dictionary).is_empty()


func get_masked_rune_indices_by_card() -> Dictionary:
	var result: Dictionary = {}
	for slot_value: Variant in masked_rune_slots.values():
		var slot := slot_value as Dictionary
		var card := slot.get("card") as CardData
		if card == null:
			continue
		if not result.has(card):
			result[card] = []
		(result[card] as Array).append(int(slot.get("rune_index", -1)))
	for card_value: Variant in result:
		(result[card_value] as Array).sort()
	return result


func _rune_slot_key(card: CardData, rune_index: int) -> String:
	return "%d:%d" % [card.get_instance_id() if card != null else 0, rune_index]


func get_action_amount() -> int:
	return roundi(get_exact_action_amount())


func get_display_action_value() -> int:
	if get_action_source() == null or squad_data == null:
		return 0
	# 卡面显示“这次普通行动的基础数值”，包含效果修正与尚未消费的强化；牌型倍率仍在结算公式中展示。
	return clampi(roundi(
		float(squad_data.get_effective_action_base_value())
		+ modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE)
		+ modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)
	), 0, 999)


func get_zeal_layers() -> int:
	return (
		roundi(modifiers.get_additive(BattleModifier.Stat.ZEAL))
		+ (squad_data.get_equipment_zeal_delta() if squad_data != null else 0)
	)


func get_action_interval() -> float:
	var source := get_action_source()
	var uses_override := runtime_base_cooldown_override >= 0.0
	var base_cooldown := (
		runtime_base_cooldown_override
		if uses_override
		else (source.cooldown_seconds if source != null else BattleRules.MINIMUM_COOLDOWN_SECONDS)
	)
	return BattleRules.get_action_interval(
		base_cooldown,
		get_zeal_layers(),
		BattleRules.MAXIMUM_ACTION_INTERVAL_SECONDS if uses_override else BattleRules.MAXIMUM_COOLDOWN_SECONDS
	)


func reset_action_cooldown() -> void:
	cooldown_progress = 0.0
	_sync_remaining_cooldown()


func advance_action_cooldown(seconds: float) -> void:
	var interval := get_action_interval()
	if interval <= 0.0:
		cooldown_progress = 1.0
	else:
		cooldown_progress = clampf(cooldown_progress + maxf(seconds, 0.0) / interval, 0.0, 1.0)
	_sync_remaining_cooldown()


func refresh_cooldown_after_modifier_change() -> void:
	# 进度不变，只把剩余显示时间换算到新的行动间隔。
	_sync_remaining_cooldown()


func is_action_ready(epsilon: float = 0.0001) -> bool:
	return remaining_cooldown <= epsilon or cooldown_progress >= 1.0 - epsilon


func apply_damage_exact(amount: float, source_state: BattleSquadState = null, event: BattleEffectEvent = null, pierces_armor: bool = false) -> Dictionary:
	var damage := maxf(amount, 0.0)
	var armor_damage := 0.0
	if not pierces_armor:
		armor_damage = minf(current_armor, damage)
		_set_exact_armor(current_armor - armor_damage)
		damage -= armor_damage
	var health_before: float = float(current_health)
	var health_damage := damage
	_set_exact_health(current_health - health_damage)
	if armor_damage > 0.0:
		_accumulate(CHANNEL_ARMOR_DAMAGE, armor_damage, source_state, event)
	if health_damage > 0.0:
		battle_health_lost += health_damage
		_accumulate(CHANNEL_HEALTH_DAMAGE, health_damage, source_state, event)
		health_lost_accumulated.emit({
			"state": self,
			"amount": health_damage,
			"accumulated_health_loss": battle_health_lost,
			"source": source_state,
			"effect_event": event,
		})
	if health_before > 0.0 and current_health <= 0.0 and pending_kill_event == null:
		pending_kill_source = source_state
		pending_kill_event = event
	if current_armor <= 0.0:
		displayed_armor = 0
	if current_health <= 0.0:
		displayed_health = 0
	else:
		_ensure_living_health_is_visible()
	var total_damage := armor_damage + health_damage
	# 所有普通攻击、疲劳直伤与效果伤害最终都经过这里。把统计放在实际
	# 扣减入口，避免某类调用绕过 BattleController 后出现卡面承伤漏记。
	if total_damage > 0.0:
		battle_damage_taken += total_damage
		if source_state != null:
			var source_action_type := (
				event.action_type
				if event != null
				else source_state.get_effective_action_type()
			)
			source_state.record_damage_dealt(source_action_type, total_damage)
	return {"armor_damage": armor_damage, "health_damage": health_damage, "total": total_damage}


func apply_direct_health_damage_exact(amount: float, source_state: BattleSquadState = null, event: BattleEffectEvent = null) -> float:
	return float(apply_damage_exact(amount, source_state, event, true)["health_damage"])


func apply_healing_exact(amount: float, source_state: BattleSquadState = null, event: BattleEffectEvent = null) -> float:
	var before: float = float(current_health)
	var effective := minf(maxf(amount, 0.0), maxf(float(get_max_health()) - current_health, 0.0))
	_set_exact_health(current_health + effective)
	if effective > 0.0:
		_accumulate(CHANNEL_HEALING, effective, source_state, event)
	if before <= 0.0 and current_health > 0.0:
		displayed_health = clampi(floori(current_health + 0.000001), 0, get_max_health())
		pending_kill_source = null
		pending_kill_event = null
	if current_health >= float(get_max_health()):
		displayed_health = clampi(roundi(current_health), 0, CardData.MAXIMUM_HEALTH)
	else:
		_ensure_living_health_is_visible()
	return effective


func apply_armor_exact(amount: float, source_state: BattleSquadState = null, event: BattleEffectEvent = null) -> float:
	var effective := minf(maxf(amount, 0.0), maxf(float(CardData.MAXIMUM_ARMOR) - current_armor, 0.0))
	_set_exact_armor(current_armor + effective)
	if effective > 0.0:
		_accumulate(CHANNEL_ARMOR_GAIN, effective, source_state, event)
	if current_armor >= float(CardData.MAXIMUM_ARMOR):
		displayed_armor = CardData.MAXIMUM_ARMOR
	return effective


func apply_damage(amount: int) -> int:
	return roundi(float(apply_damage_exact(float(maxi(amount, 0)))["total"]))


func apply_direct_health_damage(amount: int) -> int:
	return roundi(apply_direct_health_damage_exact(float(maxi(amount, 0))))


func apply_healing(amount: int) -> int:
	return roundi(apply_healing_exact(float(maxi(amount, 0))))


func apply_armor(amount: int) -> int:
	return roundi(apply_armor_exact(float(maxi(amount, 0))))


func finalize_batch_survival() -> void:
	if current_health > 0.0:
		pending_kill_source = null
		pending_kill_event = null
		_ensure_living_health_is_visible()
	else:
		displayed_health = 0


func force_boundary_sync() -> void:
	if current_health <= 0.0:
		displayed_health = 0
	elif current_health >= float(get_max_health()):
		displayed_health = clampi(roundi(current_health), 0, CardData.MAXIMUM_HEALTH)
	else:
		_ensure_living_health_is_visible()
	if current_armor <= 0.0:
		displayed_armor = 0
	elif current_armor >= float(CardData.MAXIMUM_ARMOR):
		displayed_armor = CardData.MAXIMUM_ARMOR


func add_buff_stacks(buff_id: StringName, amount: int = 1) -> int:
	var next_stacks := maxi(get_buff_stacks(buff_id) + amount, 0)
	if next_stacks == 0:
		buff_stacks.erase(buff_id)
	else:
		buff_stacks[buff_id] = next_stacks
	return next_stacks


func get_buff_stacks(buff_id: StringName) -> int:
	return int(buff_stacks.get(buff_id, 0))


func _sync_remaining_cooldown() -> void:
	_syncing_cooldown = true
	remaining_cooldown = maxf((1.0 - cooldown_progress) * get_action_interval(), 0.0)
	_syncing_cooldown = false


func _accumulate(channel: StringName, amount: float, source_state: BattleSquadState, event: BattleEffectEvent) -> void:
	var next := float(fractional_accumulators.get(channel, 0.0)) + amount
	var committed := floori(next + 0.0000001)
	fractional_accumulators[channel] = next - float(committed)
	if event != null and event.formula != null:
		event.formula.fractional_remainder = float(fractional_accumulators[channel])
	if committed <= 0:
		return
	match channel:
		CHANNEL_HEALTH_DAMAGE:
			displayed_health = maxi(displayed_health - committed, 0)
			_ensure_living_health_is_visible()
		CHANNEL_ARMOR_DAMAGE:
			displayed_armor = maxi(displayed_armor - committed, 0)
		CHANNEL_HEALING:
			displayed_health = mini(displayed_health + committed, get_max_health())
		CHANNEL_ARMOR_GAIN:
			displayed_armor = mini(displayed_armor + committed, CardData.MAXIMUM_ARMOR)
	integer_settlement_committed.emit({"state": self, "channel": channel, "amount": committed, "source": source_state, "effect_event": event, "remainder": float(fractional_accumulators[channel])})


func record_damage_dealt(action_type: CardData.ActionType, amount: float) -> void:
	var effective := maxf(amount, 0.0)
	if effective <= 0.0:
		return
	battle_damage_dealt += effective
	var action_key := int(action_type)
	battle_damage_dealt_by_action[action_key] = (
		float(battle_damage_dealt_by_action.get(action_key, 0.0)) + effective
	)


func _ensure_living_health_is_visible() -> void:
	# 精确生命可以是 0～1 的小数；仍存活时卡面至少显示 1，避免出现“0 血活着”。
	if current_health > 0.0 and displayed_health <= 0:
		displayed_health = 1


func _set_exact_health(value) -> void:
	_precise_write = true
	current_health = value
	_precise_write = false


func _set_exact_armor(value) -> void:
	_precise_write = true
	current_armor = value
	_precise_write = false
