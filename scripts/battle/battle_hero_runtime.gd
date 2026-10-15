class_name BattleHeroRuntime
extends RefCounted

## 伊奥恩一级／四级天赋。只操作战斗状态，永久发奖由迷宫结算提交。
## 使用控制器的同一随机源与逻辑时钟；不启动第二个计时器。
const ShopService = preload("res://scripts/data/ordinary_shop_service.gd")
var level: int = 1
var talents: Array[String] = []
var sentries: Array[Dictionary] = []
var spell_awards: Array[String] = []
var fortify_complete: bool = false
var fortify_eligible: bool = false
var _controller: WeakRef
var _next_break_time: float = INF
var _rules: Dictionary = {}
var _next_modifier_id: int = -40000000


func initialize(controller: Node, context: Dictionary) -> void:
	_controller = weakref(controller)
	_rules = context.rules
	_next_break_time = float(_talent("sentry_break").interval_seconds)
	level = int(context.get("level", 1))
	talents.assign(context.get("talents", []))
	sentries.assign((context.get("sentries", []) as Array).duplicate(true))
	fortify_complete = bool(context.get("fortify_complete", false))
	var defense_count := 0
	for state: BattleSquadState in controller.player_states:
		state.direct_damage_guard = controller.try_protect_direct_damage
		if state.row_key == &"player_front" and state.squad_data.horizontal_cards.size() == 1 and state.get_effective_action_type() == CardData.ActionType.DEFENSE:
			defense_count += 1
	fortify_eligible = has("sentry_fortify") and defense_count >= int(_talent("sentry_fortify").independent_defense_minions)


func has(id: String) -> bool:
	return id in talents


func opening_passives() -> void:
	if not has("sentry_guard"):
		return
	var c = _controller.get_ref()
	for sentry: Dictionary in sentries:
		for target: BattleSquadState in c.get_living_states(BattleSquadState.Side.PLAYER):
			if target.row_key == &"player_front":
				_emit(target, float(level) * float(_talent("sentry_guard").armor_per_hero_level), CardData.ActionType.DEFENSE, BattleEffectEvent.EffectKind.ARMOR, "哨位：护", false)


func opening_rush() -> void:
	if not has("sentry_spell"):
		return
	var c = _controller.get_ref()
	var service := ShopService.new()
	if not service.load_config():
		return
	var candidates: Array[CardData] = []
	for card: CardData in c._reward_card_catalog:
		if card.is_available and not card.is_derived and card.card_type == CardData.CardType.SPELL and card.get_effective_faction() == CardFaction.Id.RADIANT_ALLIANCE:
			if card.rarity != CardData.Rarity.IV or not c._player_owned_card_ids.has(card.id):
				candidates.append(card)
	var counts: Dictionary = c._reward_held_card_counts()
	for sentry: Dictionary in sentries:
		var card := service._draw_by_rarity_weights(candidates, c._random, CardData.Rarity.I, counts)
		if card == null:
			break
		spell_awards.append(String(card.id))
		counts[card.id] = int(counts.get(card.id, 0)) + 1
		if card.rarity == CardData.Rarity.IV:
			candidates.erase(card)


func next_delay(now: float) -> float:
	return maxf(_next_break_time - now, 0.0) if has("sentry_break") and not sentries.is_empty() else INF


func process_due(now: float) -> void:
	if next_delay(now) > 0.0001:
		return
	_next_break_time += float(_talent("sentry_break").interval_seconds)
	# 每次重新取存活候选；前一枚造成死亡后，下一枚不能继续命中尸体。
	for sentry: Dictionary in sentries.duplicate(true):
		var target := _random_living(BattleSquadState.Side.ENEMY)
		if target == null:
			break
		_emit(target, float(level) * float(_talent("sentry_break").damage_per_hero_level), CardData.ActionType.RANGED, BattleEffectEvent.EffectKind.DAMAGE, "哨位：破", true)
		var c = _controller.get_ref()
		c._finalize_batch()


func share_damage(event: BattleEffectEvent) -> void:
	if event.target.side != BattleSquadState.Side.PLAYER or event.exact_amount <= 0.0 or event.log_qualifier == "疲劳":
		return
	var region := ""
	match event.action_type:
		CardData.ActionType.MELEE: region = "front"
		CardData.ActionType.RANGED: region = "back"
		CardData.ActionType.MAGIC: region = "spells"
	if region.is_empty():
		return
	for sentry: Dictionary in sentries:
		if sentry.region != region:
			continue
		var amount := minf(event.exact_amount, minf(float(sentry.remaining), float(_talent("sentry_fortify").shared_damage_per_hit) if fortify_complete else float(_rules.sentry.shared_damage_per_hit)))
		sentry.remaining = float(sentry.remaining) - amount
		event.exact_amount -= amount
		event.sentry_absorbed = amount
		event.sentry_remaining = float(sentry.remaining)
		event.sentry_region = region
		if event.formula != null:
			event.formula.final_flat_bonus -= amount
			event.formula.final_flat_bonus_sources.append({"source_name": "哨位分担", "amount": -amount, "source_status": "resolved"})
			event.formula.exact_result = event.exact_amount
		if float(sentry.remaining) <= 0.0:
			_destroy(sentry)
		if has("sentry_needle") and amount > 0.0:
			var target := _random_living(BattleSquadState.Side.ENEMY)
			if target != null:
				_emit(target, amount, event.action_type, BattleEffectEvent.EffectKind.DAMAGE, "哨位：针刺反弹伤害", false)
		return


func try_protect_direct(target: BattleSquadState, amount: float, pierces: bool) -> bool:
	var event := BattleEffectEvent.new()
	event.target = target
	event.exact_amount = amount
	event.pierces_armor = pierces
	return try_protect(event)


func try_protect(event: BattleEffectEvent) -> bool:
	if not event.target.alive or event.target.current_health <= 0.0 or not has("sentry_protection") or sentries.is_empty() or event.target.side != BattleSquadState.Side.PLAYER:
		return false
	var hp_damage := event.exact_amount if event.pierces_armor else maxf(event.exact_amount - event.target.current_armor, 0.0)
	if hp_damage < event.target.current_health or event.exact_amount <= 0.0:
		return false
	var chosen: Dictionary = sentries[0]
	var order: Array = _talent("sentry_protection").capacity_tie_order
	for sentry: Dictionary in sentries:
		if float(sentry.remaining) < float(chosen.remaining) or (is_equal_approx(float(sentry.remaining), float(chosen.remaining)) and order.find(sentry.region) < order.find(chosen.region)):
			chosen = sentry
	_destroy(chosen)
	_emit(event.target, float(_talent("sentry_protection").healing), CardData.ActionType.HEAL, BattleEffectEvent.EffectKind.HEALING, "哨位：保护", false)
	return true


func _destroy(sentry: Dictionary) -> void:
	sentries.erase(sentry)
	if not has("sentry_sharp"):
		return
	var target := _random_living(BattleSquadState.Side.PLAYER)
	if target == null:
		return
	for entry: Array in [[BattleModifier.Stat.ACTION_VALUE, float(level) * float(_talent("sentry_sharp").action_per_hero_level)], [BattleModifier.Stat.MAX_HEALTH, float(level) * float(_talent("sentry_sharp").health_per_hero_level)]]:
		var modifier := BattleModifier.new()
		modifier.stat = entry[0]
		modifier.value = entry[1]
		modifier.source_instance_id = _next_modifier_id
		modifier.effect_id = &"sentry_sharp"
		modifier.contribution_sources.append({"source_name": "哨位：锐", "amount": modifier.value, "source_status": "resolved"})
		target.modifiers.add_modifier(modifier)
		_next_modifier_id -= 1
	# 增加生命是上限提升的同时加值，不是治疗，不消费乡邻与暗蚀。
	var gain := minf(level * float(_talent("sentry_sharp").health_per_hero_level), maxf(float(target.get_max_health()) - target.current_health, 0.0))
	target.current_health += gain
	if gain > 0.0:
		# 增加生命不清算之前尚未跨整数的承伤小数；已有超上限生命也不能倒扣。
		target.displayed_health = mini(target.displayed_health + floori(gain), target.get_max_health())


func _random_living(side: int) -> BattleSquadState:
	var c = _controller.get_ref()
	var candidates: Array[BattleSquadState] = c.get_living_states(side)
	return candidates[c._random.randi_range(0, candidates.size() - 1)] if not candidates.is_empty() else null


func _emit(target: BattleSquadState, amount: float, type: CardData.ActionType, kind: BattleEffectEvent.EffectKind, label: String, multiplier: bool) -> void:
	var c = _controller.get_ref()
	var event := BattleEffectEvent.new()
	event.timestamp = c.elapsed_seconds
	event.group_id = c._take_group_id()
	event.target = target
	event.anchor = target
	event.action_type = type
	event.effect_kind = kind
	event.exact_amount = amount
	event.uses_attack_type_multiplier = multiplier
	event.can_trigger_element_chain = false
	event.log_qualifier = label
	event.visual_kind = &"hero_sentry"
	var effect_name := "伤害" if kind == BattleEffectEvent.EffectKind.DAMAGE else ("护甲" if kind == BattleEffectEvent.EffectKind.ARMOR else "治疗")
	event.formula = BattleFormulaData.create(effect_name, type, amount, 1.0, 1.0, null, target)
	event.formula.base_value_sources.append({"source_name": label, "amount": amount, "source_status": "resolved"})
	c._apply_effect_event(event)


func _talent(id: String) -> Dictionary:
	return _rules.talents[id].confirmed_rules
