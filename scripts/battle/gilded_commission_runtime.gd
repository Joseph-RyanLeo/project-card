extends RefCounted

## 镀金委托的跨小队效果。永久变化仍写入正式战斗账本。
const JAM_SECONDS := 10.0 # 信号干扰持续到战斗时钟的第10秒
const DAMILI_LIMIT := 4 # 达米莉每次入场的荣耀次数上限
const DOORBOARD_THRESHOLD := 25 # 门板基础生命必须严格大于此值
const MOGRIS_SECONDS := 45.0 # 莫格里斯的存活门槛和奖励独立计时
const GRAVE_PREFIX := "gravekeeper_seen:"
const INSECT_PROGRESS := &"insect_blade_summons"
const INSECT_REQUIRED := 10 # 虫刃解锁回响所需的实际召唤次数
const ENCORE_COOLDOWN := 0.1 # 每方位移触发安可曲的最短逻辑时钟间隔

var _controller: WeakRef
var _dialers: Array[BattleSquadState] = []
var _elemental_burst_sides: Dictionary = {}
var _jam_ends: Dictionary = {}
var _nature_sides: Dictionary = {}
var _mogris_checks: Array[BattleSquadState] = []
var _mogris_rewards: Array[Dictionary] = []
var _kalis_pool: Array[OwnedCard] = []
var _encore_last_time: Dictionary = {}
var _opening_potions_by_actor: Dictionary = {}
var _spell_missions: Array[OwnedCard] = []
var _collection_ids: Dictionary = {}


func initialize(controller: Node, collection: Array[OwnedCard]) -> void:
	_controller = weakref(controller)
	for owned: OwnedCard in collection:
		if owned != null: _collection_ids[owned.instance_id] = true
	_spell_missions = collection.filter(func(item: OwnedCard) -> bool: return item != null and item.tracks_mission(OwnedCard.MissionGoal.SPELLS))
	var deployed := {}
	for state: BattleSquadState in controller.get_all_states():
		on_joined(state)
		for definition: CardData in state.squad_data.horizontal_cards:
			var member := state.squad_data.get_owned_card(definition)
			if member != null: deployed[member.instance_id] = true
	if controller.player_states.any(func(state: BattleSquadState) -> bool: return state.get_effect_source().content_effect == &"kalis_summoner"):
		_kalis_pool = collection.filter(func(card: OwnedCard) -> bool:
			return card.card_data.card_type == CardData.CardType.MINION and not card.card_data.is_derived and not deployed.has(card.instance_id))


func on_joined(state: BattleSquadState) -> void:
	if state.squad_data.horizontal_cards.any(func(card: CardData) -> bool: return card.content_effect == &"dialer_beep"):
		_dialers.append(state)
	if _elemental_burst_sides.has(state.side): _double_rune_stats(state)
	if _jam_ends.has(state.side): _set_jam(state, -10)
	if not state.battle_summoned and state.get_effect_source().content_effect == &"mogris_old_oak":
		var owner := state.squad_data.get_effect_source_instance()
		if owner != null and not owner.progress_by_source.has(&"mogris_survived"): _mogris_checks.append(state)


func rush(source: BattleSquadState, key: StringName) -> bool:
	var c = _controller.get_ref()
	if not c.twisted_vein.active(source, key): return false
	var owner := source.squad_data.get_effect_source_instance()
	if owner == null: return false
	match key:
		&"mogris_old_oak":
			if not owner.progress_by_source.has(&"mogris_survived") or source.buff_stacks.has(&"mogris_unlock_pending"): return false
			_mogris_rewards.append({"source": source, "at": c.elapsed_seconds + MOGRIS_SECONDS})
		&"nyx_contract_demon":
			if int(owner.progress_by_source.get(OwnedCard.NYX_ROADS_PROGRESS, 0)) < OwnedCard.NYX_ROADS_REQUIRED: return false
			for ally: BattleSquadState in c.get_living_states(source.side):
				c.ironwall.add(ally, BattleModifier.Stat.ZEAL, 6.0, key, source)
				ally.refresh_cooldown_after_modifier_change()
	return true


func snapshot_opening_potions() -> void:
	var c = _controller.get_ref()
	for actor: BattleSquadState in c.player_states:
		if actor.squad_data.get_helmet() == null: continue
		var item := actor.squad_data.get_equipped_item()
		if item != null and String(item.card_data.content_effect).begins_with("event_"):
			_opening_potions_by_actor[actor.runtime_id] = item


func helmet_rush(actor: BattleSquadState) -> bool:
	var c = _controller.get_ref()
	if actor.side != BattleSquadState.Side.PLAYER or not _living(actor) or actor.has_effective_shadow() or actor.has_runtime_keyword(&"silenced"): return false
	var item := actor.squad_data.get_equipped_item()
	if item == null and c._opening_resolving:
		item = _opening_potions_by_actor.get(actor.runtime_id) as OwnedCard
	if item == null: return false
	var owner := BattleEffectOwnerRef.for_state(actor, BattleEffectDefinition.OwnerKind.OWNING_PLAYER)
	return c.record_pending_run_reward(owner, BattleRunRewardLedger.KIND_OWNED_CARD_AWARD, 1, &"balin_helmet", actor.runtime_id, roundi(c.elapsed_seconds * 1000000.0), {
		"card_id": item.card_data.id,
		"temporary_equipment_growth": item.permanent_growth.duplicate(),
		"temporary_equipment_durability": item.equipment_durability,
		"temporary_equipment_progress": item.progress_by_source.duplicate(),
	})


func can_replay_rush(source: BattleSquadState, key: StringName) -> bool:
	var card := source.squad_data.get_effect_source_instance()
	match key:
		&"balin_helmet":
			return source.side == BattleSquadState.Side.PLAYER and source.squad_data.get_equipped_item() != null
		&"mogris_old_oak":
			return card != null and card.progress_by_source.has(&"mogris_survived") and not source.buff_stacks.has(&"mogris_unlock_pending")
		&"nyx_contract_demon":
			return card != null and int(card.progress_by_source.get(OwnedCard.NYX_ROADS_PROGRESS, 0)) >= OwnedCard.NYX_ROADS_REQUIRED
	return true


func on_player_spell() -> void:
	for item: OwnedCard in _spell_missions:
		_record_mission_point(item, BattleEffectOwnerRef.for_owned_card_in_state(null, item), OwnedCard.MissionGoal.SPELLS)


func on_mission_action(actor: BattleSquadState, goal: int) -> void:
	if actor == null or actor.side != BattleSquadState.Side.PLAYER or actor.squad_data == null: return
	var item := actor.squad_data.get_equipped_item()
	if item == null or not item.tracks_mission(goal): return
	var owner := BattleEffectOwnerRef.for_state(actor, BattleEffectDefinition.OwnerKind.EQUIPMENT_INSTANCE)
	_record_mission_point(item, owner, goal)


func _record_mission_point(item: OwnedCard, owner: BattleEffectOwnerRef, goal: int) -> void:
	var c = _controller.get_ref()
	if item.mission_complete(): return
	var current := int(item.progress_by_source.get(OwnedCard.MISSION_PROGRESS, 0))
	if owner.state == null:
		if c.player_states.is_empty(): return
		owner.state = c.player_states[0]
		owner.runtime_id = owner.state.runtime_id
		owner.owner_kind = BattleEffectDefinition.OwnerKind.EQUIPMENT_INSTANCE
	if item.tracks_mission(goal): _record_progress(owner, OwnedCard.MISSION_PROGRESS, current + 1, &"secret_mission")


func on_movement(side: int) -> void:
	var c = _controller.get_ref()
	if c.elapsed_seconds - float(_encore_last_time.get(side, -INF)) + 0.000001 < ENCORE_COOLDOWN: return
	for spell: OwnedCard in c._get_all_prepared_spell_instances():
		if spell.card_data.content_effect != &"starsinger_encore" or int(c._spell_side_by_instance.get(spell.instance_id, -1)) != side: continue
		var choices: Array[Dictionary] = c.effect_runtime.available_rush_groups(side)
		choices.append_array(_native_rush_choices(side))
		if choices.is_empty() or not c.notify_spell_triggered(spell.instance_id, 0): continue
		_encore_last_time[side] = c.elapsed_seconds
		c._present_nonpausing_spell(spell)
		var chosen: Dictionary = choices[c._random.randi_range(0, choices.size() - 1)]
		if chosen.has("apply"):
			c._apply_native_rush_with_repeat(chosen.actor, chosen.apply)
		else:
			c.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.RUSH, {"actor": chosen.actor, "binding_ids": chosen.binding_ids, "retrigger_rush": true})
		break


func _native_rush_choices(side: int) -> Array[Dictionary]:
	var c = _controller.get_ref()
	var choices: Array[Dictionary] = []
	for actor: BattleSquadState in c.get_living_states(side):
		if _living(actor) and actor.equipped_card_is(&"blood_oath_whip") and not actor.has_effective_shadow() and not actor.has_runtime_keyword(&"silenced"):
			choices.append({"actor": actor, "apply": c._apply_blood_oath_rush.bind(actor)})
	for registration: Dictionary in c._emblem_registrations:
		var actor := registration.get("state") as BattleSquadState
		if not _living(actor) or actor.side != side or not c._is_emblem_registration_visible(registration): continue
		var definition: Dictionary = registration.get("definition", {})
		var affects_self := definition.has("reinforcement") or definition.has("rush_charge") or bool(definition.get("rush_convert_rightmost_rune", false))
		var affects_neighbors := definition.has("adjacent_protection") or definition.has("adjacent_reinforcement") or definition.has("adjacent_rush_charge")
		if affects_self or (affects_neighbors and not c._get_adjacent_allies(actor).is_empty()):
			choices.append({"actor": actor, "apply": c._apply_emblem_rush.bind(actor, registration, true)})
	for registration: Dictionary in c._wound_registrations:
		var actor := registration.get("state") as BattleSquadState
		if not _living(actor) or actor.side != side or not actor.get_unmasked_active_injuries().has(registration.get("instance_id", &"")): continue
		var amount := int((registration.get("definition", {}) as Dictionary).get("rush_reinforcement", 0))
		if amount > 0:
			choices.append({"actor": actor, "apply": c._replay_wound_rush.bind(actor, registration, amount)})
	return choices


func prevents_damage(target: BattleSquadState, amount: float) -> bool:
	var c = _controller.get_ref()
	return amount > 0.0 and _nature_sides.has(target.side) and c.elapsed_seconds < 10.0 and int(c._roll_probability(target, 6).total) >= 5


func on_summoned(created: BattleSquadState) -> void:
	var c = _controller.get_ref()
	for state: BattleSquadState in c.get_living_states(created.side):
		if not c.twisted_vein.active(state, &"insect_blade", true): continue
		var owner := BattleEffectOwnerRef.for_state(state, BattleEffectDefinition.OwnerKind.EQUIPMENT_INSTANCE)
		var current := int(owner.owned_card.progress_by_source.get(INSECT_PROGRESS, 0))
		if current < INSECT_REQUIRED: _record_progress(owner, INSECT_PROGRESS, current + 1, &"insect_blade")
	on_movement(created.side)


func equipment_trigger(source: BattleSquadState, key: StringName, dead: bool) -> bool:
	var c = _controller.get_ref()
	if not c.twisted_vein.active(source, key, true, dead): return false
	var item := source.squad_data.get_equipped_item()
	var targets: Array[BattleSquadState] = c.get_living_states(1 - source.side).filter(_living)
	if targets.is_empty(): return false
	if key == &"insect_blade":
		if dead or int(item.progress_by_source.get(INSECT_PROGRESS, 0)) < INSECT_REQUIRED: return false
		var distinct := targets.size() >= 2
		for index: int in 2:
			var target_index: int = c._random.randi_range(0, targets.size() - 1)
			var target := targets[target_index]
			if distinct: targets.remove_at(target_index)
			_launch_fixed_damage(source, target, 2.0, "虫刃回响", &"ranged_attack")
		return true
	if not dead: return false
	for kind: StringName in item.progress_by_source:
		if not String(kind).begins_with(GRAVE_PREFIX): continue
		targets = c.get_living_states(1 - source.side).filter(_living)
		if targets.is_empty(): break
		_launch_fixed_damage(source, targets[c._random.randi_range(0, targets.size() - 1)], 1.0, "守墓人的笔记", &"magic_attack")
	return true


func _launch_fixed_damage(source: BattleSquadState, target: BattleSquadState, amount: float, label: String, visual: StringName) -> void:
	var c = _controller.get_ref()
	var event: BattleEffectEvent = c.twisted_vein.make_event(source, target, amount, CardData.ActionType.RANGED, false, label)
	event.fixed_damage = true
	event.visual_kind = visual
	c.launch_content_effect(event)


func _record_progress(owner: BattleEffectOwnerRef, key: StringName, value: int, effect: StringName) -> void:
	var c = _controller.get_ref()
	if owner.state.side == BattleSquadState.Side.PLAYER and not owner.state.battle_summoned and (not owner.owned_card.is_temporary_equipment() or (effect == &"secret_mission" and _collection_ids.has(owner.owned_card_instance_id))):
		if not c.owned_card_change_ledger.record_progress_value(owner, key, value, effect, c.battle_instance_id, roundi(c.elapsed_seconds * 1000000.0), true): return
	owner.owned_card.progress_by_source[key] = value


func upgrades_pair(state: BattleSquadState) -> bool:
	var c = _controller.get_ref()
	if c == null: return false
	for source: BattleSquadState in _dialers:
		if source.side == state.side and c.twisted_vein.active(source, &"dialer_beep"): return true
	return false


func sargon_echo(source: BattleSquadState) -> bool:
	var c = _controller.get_ref()
	if c == null or not c.twisted_vein.active(source, &"sargon_harmonizer"): return false
	var action := source.get_effective_action_type()
	var extra := int(c._roll_probability(source, 6).total) >= 5
	var at := roundi(c.elapsed_seconds * 1000000.0)
	for target: BattleSquadState in c.get_all_states():
		if not _living(target) or target.get_effective_action_type() != action: continue
		c._record_resource_permanent_growth(target, OwnedCard.STAT_MAX_HEALTH, 1.0, &"sargon_harmonizer", at)
		if extra: c._record_resource_permanent_growth(target, OwnedCard.STAT_BASE_VALUE, 1.0, &"sargon_harmonizer", at)
	return true


func on_defeated(defeated: BattleSquadState) -> void:
	var c = _controller.get_ref()
	if c == null: return
	for state: BattleSquadState in c.get_all_states():
		if state == defeated or not state.equipped_card_is(&"gravekeepers_notes"): continue
		var owner := BattleEffectOwnerRef.for_state(state, BattleEffectDefinition.OwnerKind.EQUIPMENT_INSTANCE)
		for member: CardData in defeated.squad_data.horizontal_cards:
			var key := StringName(GRAVE_PREFIX + String(member.id))
			if not owner.owned_card.progress_by_source.has(key): _record_progress(owner, key, 1, &"gravekeepers_notes")
	var killer := defeated.pending_kill_source
	if killer != null and killer.side != defeated.side and c.twisted_vein.active(killer, &"damili_bloodthorn"):
		# life_generation 随复活递增，同一条命只允许四次荣耀。
		var key := StringName("damili_glory:%d" % killer.life_generation)
		var count := int(killer.buff_stacks.get(key, 0))
		if count < DAMILI_LIMIT:
			killer.buff_stacks[key] = count + 1
			for ally: BattleSquadState in c.get_living_states(killer.side):
				if not _living(ally): continue
				c.ironwall.add(ally, BattleModifier.Stat.ACTION_VALUE, 1.0, &"damili_bloodthorn", killer)
				ally.apply_healing_exact(2.0, killer)
	for neighbor: BattleSquadState in c.get_death_neighbors(defeated):
		if not c.twisted_vein.active(neighbor, &"doorboard"): continue
		var owner := BattleEffectOwnerRef.for_state(neighbor, BattleEffectDefinition.OwnerKind.MINION_CARD_INSTANCE)
		if owner.owned_card == null: continue
		if c.record_pending_permanent_growth(owner, OwnedCard.STAT_MAX_HEALTH, 1.0, &"doorboard", neighbor.runtime_id, roundi(c.elapsed_seconds * 1000000.0)):
			var before := neighbor.get_max_health()
			owner.owned_card.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 1.0)
			if owner.owned_card == neighbor.squad_data.get_vitals_source_instance():
				neighbor.apply_max_health_increase(before, 1.0, true)
	if not c.twisted_vein.active(defeated, &"doorboard", false, true): return
	var card := defeated.squad_data.get_effect_source_instance()
	if card == null: return
	var health := defeated.get_display_base_stats(defeated.get_active_rune_slots()).y
	if card != defeated.squad_data.get_vitals_source_instance():
		var solo := SquadData.from_owned_card(card)
		health = solo.get_display_base_health(solo.get_vitals_source(), solo.get_visible_rune_stat_bonus(OwnedCard.STAT_MAX_HEALTH))
	if health <= DOORBOARD_THRESHOLD: return
	var targets: Array[BattleSquadState] = c.get_death_neighbors(defeated).filter(_living)
	if not targets.is_empty():
		var target: BattleSquadState = targets[c._random.randi_range(0, targets.size() - 1)]
		var before := target.get_max_health()
		c.ironwall.add(target, BattleModifier.Stat.MAX_HEALTH, health, &"doorboard", defeated)
		target.apply_max_health_increase(before, health)


func fill_vacated_slots(defeated: Array[BattleSquadState]) -> void:
	var c = _controller.get_ref()
	if _kalis_pool.is_empty(): return
	for victim: BattleSquadState in defeated:
		if victim.is_repairing or victim.side != BattleSquadState.Side.PLAYER: continue
		for state: BattleSquadState in c.get_living_states(victim.side):
			if state.row_key != victim.row_key or state.buff_stacks.has(&"kalis_used") or not c.twisted_vein.active(state, &"kalis_summoner"): continue
			var original := _kalis_pool[c._random.randi_range(0, _kalis_pool.size() - 1)]
			if c.summon_content_minion(state, original.card_data, original, victim.formation_index) != null:
				state.buff_stacks[&"kalis_used"] = 1
				break


func release_opening_spell(spell: OwnedCard, side: int) -> bool:
	var key := spell.card_data.content_effect
	if key not in [&"commoner_hero", &"ultimate_harmony", &"elemental_burst", &"signal_jamming", &"nature_guard"]: return false
	var c = _controller.get_ref()
	var allies: Array[BattleSquadState] = c.get_living_states(side).filter(_living)
	var harmonizers: Array[BattleSquadState] = []
	if key == &"ultimate_harmony":
		harmonizers = allies.filter(func(state: BattleSquadState) -> bool: return state.get_rune_pattern_result().pattern_type == RunePatternResult.PatternType.STRAIGHT)
		if harmonizers.is_empty(): return true
	if not c.notify_spell_triggered(spell.instance_id, 0): return true
	match key:
		&"commoner_hero":
			for ally: BattleSquadState in allies:
				if ally.get_effect_source().rarity == CardData.Rarity.I: _add_spell_growth(ally, spell, 3, 5)
		&"ultimate_harmony":
			for source: BattleSquadState in harmonizers:
				var action := int(c._roll_probability(source, 6).total)
				var health := int(c._roll_probability(source, 10).total)
				for neighbor: BattleSquadState in c._get_adjacent_allies(source):
					if _living(neighbor): _add_spell_growth(neighbor, spell, action, health)
		&"elemental_burst":
			_elemental_burst_sides[side] = true
			for ally: BattleSquadState in allies: _double_rune_stats(ally)
		&"signal_jamming":
			var target_side := 1 - side
			_jam_ends[target_side] = JAM_SECONDS
			for target: BattleSquadState in c.get_all_states():
				if target.side == target_side: _set_jam(target, -10)
		&"nature_guard":
			_nature_sides[side] = true
	return true


func _add_spell_growth(target: BattleSquadState, spell: OwnedCard, action: int, health: int) -> void:
	var before := target.get_max_health()
	for stat: int in [BattleModifier.Stat.ACTION_VALUE, BattleModifier.Stat.MAX_HEALTH]:
		var modifier := BattleModifier.new()
		modifier.stat = stat as BattleModifier.Stat
		modifier.value = action if stat == BattleModifier.Stat.ACTION_VALUE else health
		modifier.effect_id = spell.card_data.id
		modifier.contribution_sources.append({"source_name": spell.card_data.display_name, "source_card_id": String(spell.card_data.id), "amount": modifier.value, "source_status": "resolved"})
		target.modifiers.add_modifier(modifier)
	target.apply_max_health_increase(before, health)


func _double_rune_stats(state: BattleSquadState) -> void:
	var c = _controller.get_ref()
	if state.rune_base_multiplier > 1: return
	var health := state.get_max_health()
	var health_bonus := state.get_active_rune_stat_bonus(&"max_health")
	var armor := state.get_active_rune_stat_bonus(&"base_armor")
	state.rune_base_multiplier = 2
	state.apply_max_health_increase(health, health_bonus, true)
	state.current_armor += state.get_active_rune_stat_bonus(&"base_armor") - armor
	state.refresh_cooldown_after_modifier_change()
	c._apply_visible_fire_rune_reinforcement(state, true)


func next_delay(now: float) -> float:
	var next := INF
	for end: float in _jam_ends.values():
		next = minf(next, maxf(end - now, 0.0))
	if not _mogris_checks.is_empty(): next = minf(next, maxf(MOGRIS_SECONDS - now, 0.0))
	for reward: Dictionary in _mogris_rewards: next = minf(next, maxf(float(reward.at) - now, 0.0))
	return next


func process_due() -> void:
	var c = _controller.get_ref()
	for side: int in _jam_ends.keys():
		if c.elapsed_seconds + 0.000001 < float(_jam_ends[side]): continue
		_jam_ends.erase(side)
		for state: BattleSquadState in c.get_all_states():
			if state.side == side: _set_jam(state, 0)
	if c.elapsed_seconds + 0.000001 >= MOGRIS_SECONDS:
		for state: BattleSquadState in _mogris_checks:
			if state.alive and state.current_health > 0.0 and not state.battle_ever_defeated:
				var owner := BattleEffectOwnerRef.for_state(state, BattleEffectDefinition.OwnerKind.MINION_CARD_INSTANCE)
				if owner.owned_card != null: _record_progress(owner, &"mogris_survived", 1, &"mogris_old_oak")
		# 保留本场锁定标记，防止后来重新触发突击提前解锁。
		for state: BattleSquadState in _mogris_checks: state.buff_stacks[&"mogris_unlock_pending"] = 1
		_mogris_checks.clear()
	for reward: Dictionary in _mogris_rewards.duplicate():
		if c.elapsed_seconds + 0.000001 < float(reward.at): continue
		_mogris_rewards.erase(reward)
		var source: BattleSquadState = reward.source
		for ally: BattleSquadState in c.get_living_states(source.side):
			if not _living(ally): continue
			var before := ally.get_max_health()
			c.ironwall.add(ally, BattleModifier.Stat.ACTION_VALUE, 5.0, &"mogris_old_oak", source)
			c.ironwall.add(ally, BattleModifier.Stat.MAX_HEALTH, 10.0, &"mogris_old_oak", source)
			ally.apply_max_health_increase(before, 10.0)


func _set_jam(state: BattleSquadState, amount: int) -> void:
	state.gilded_zeal_penalty = amount
	state.refresh_cooldown_after_modifier_change()


func _living(state: BattleSquadState) -> bool:
	return state != null and state.alive and state.current_health > 0.0 and not state.is_banished
