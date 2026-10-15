class_name IronwallRuntime
extends RefCounted

## 铁壁铭刻的内容规则。复用控制器的时钟、弹道、召唤与事务，不另建战斗循环。
const BEER_CHARGE_SECONDS: float = 0.5 # 啤酒机每次回响减少相邻矮人的剩余冷却
const LOGISTICS_PERIOD: float = 5.0 # 后勤机器人共用骰强化的触发周期
const MUG_PERIOD: float = 3.0 # 啤酒杯强化周期
const PENDANT_PERIOD: float = 10.0 # 铁心吊坠保护周期
const SENTRY_SLEEP_SECONDS: float = 30.0 # 警戒机械开战休眠的持续秒数
const SENTRY_SLEEP_SOURCE: StringName = &"ironwall_sentry_entry"
const ANVIL_STUN_SECONDS: float = 2.0 # 符文铁砧主目标眩晕时长
var controller: Node
var initial_vitals: Dictionary = {}
var repairs: Dictionary = {}
var repair_uses: Array[int] = [0, 0]
var periods: Array[Dictionary] = []
var protection_actions: Array[BattleSquadState] = []
var protection_losses: Array[BattleSquadState] = []
var repeats: Array[Dictionary] = []
var vengeance: Dictionary = {}
var blessed_sides: Array[int] = []
var temporary_emblems: Array[Dictionary] = []
var temporary_items: Array[Dictionary] = []
var syncing: bool = false

func initialize(value: Node, preview: bool = false) -> void:
	controller = value
	for state: BattleSquadState in controller.get_all_states(): initialize_state(state, preview)
	sync_auras()

func active(state: BattleSquadState, key: StringName, equipment: bool = false, dead: bool = false) -> bool:
	return controller.twisted_vein.active(state, key, equipment, dead)

func add(state: BattleSquadState, stat: int, amount: float, key: StringName, source: BattleSquadState = null) -> void:
	if is_zero_approx(amount): return
	if source == null: source = state
	var owned: OwnedCard = source.squad_data.get_effect_source_instance()
	var item: OwnedCard = source.squad_data.get_equipped_item()
	if item != null and item.card_data.content_effect == key: owned = item
	var definition: CardData = owned.card_data if owned != null else source.get_effect_source()
	var modifier = BattleModifier.new()
	modifier.stat = stat as BattleModifier.Stat
	modifier.value = amount
	modifier.effect_id = key
	modifier.source_runtime_id = source.runtime_id
	modifier.contribution_sources.append({"source_name": definition.display_name, "source_card_name": definition.display_name, "source_card_id": String(definition.id), "source_owned_card_instance_id": String(owned.instance_id) if owned != null else "", "source_status": "resolved", "amount": amount})
	state.modifiers.add_modifier(modifier)

func initialize_state(state: BattleSquadState, preview: bool = false) -> void:
	if not preview:
		if active(state, &"bomb_apprentice") or active(state, &"swordshield_master"): state.grant_protection(&"ironwall_native", 1)
		if active(state, &"sentry_machine"): state.apply_sleep(SENTRY_SLEEP_SOURCE, controller.elapsed_seconds + SENTRY_SLEEP_SECONDS)
		if active(state, &"legion_aegis", true): state.grant_protection(&"legion_aegis", 2)
		for entry: Array in [[&"logistics_robot", LOGISTICS_PERIOD, false], [&"beer_mug", MUG_PERIOD, true], [&"ironheart_pendant", PENDANT_PERIOD, true]]:
			if active(state, entry[0], entry[2]): periods.append({"state": state, "key": entry[0], "period": entry[1], "next": controller.elapsed_seconds + entry[1], "equipment": entry[2]})
	initial_vitals[state] = {"health": state.current_health, "armor": state.current_armor, "base_health": base_health(state)}
	state.damage_taken.connect(on_damage_taken.bind(state))
	state.armor_gained.connect(on_armor_gained.bind(state))
	state.protection_changed.connect(on_protection_changed.bind(state))
	if active(state, &"swordshield_master"): state.set_runtime_action_type(CardData.ActionType.DEFENSE)

func base_health(state: BattleSquadState) -> float:
	var owned: OwnedCard = state.squad_data.get_vitals_source_instance()
	return (owned.get_base_stat_with_permanent_growth(&"max_health") if owned != null else float(state.get_vitals_source().max_health)) + state.get_active_rune_stat_bonus(&"max_health")

func on_armor_gained(amount: float, state: BattleSquadState) -> void:
	if amount > 0.0 and active(state, &"walking_fighter"): add(state, BattleModifier.Stat.ACTION_VALUE, 1, &"walking_fighter")

func on_damage_taken(amount: float, _source: BattleSquadState, _event: BattleEffectEvent, state: BattleSquadState) -> void:
	if amount <= 0.0 or not state.alive: return
	if active(state, &"thunderstorm_infantry", false, true):
		add(state, BattleModifier.Stat.ZEAL, 1, &"thunderstorm_infantry")
		convert_thunderstorm_zeal(state)
		state.refresh_cooldown_after_modifier_change()
	if active(state, &"sentry_machine", false, true):
		state.expire_sleep_sources(controller.elapsed_seconds)
		if not state.sleep_source_until.has(SENTRY_SLEEP_SOURCE): return
		# 只消费本卡初始休眠；自然到期或已被伤害唤醒后不再发保护。
		state.sleep_source_until.erase(SENTRY_SLEEP_SOURCE)
		for ally: BattleSquadState in controller.get_living_states(state.side):
			if ally.row_key == state.row_key and ally.current_health > 0.0 and not ally.is_banished:
				ally.grant_protection(&"sentry_machine", 1)

func convert_thunderstorm_zeal(state: BattleSquadState) -> void:
	while state.get_zeal_layers() >= 10:
		add(state, BattleModifier.Stat.ZEAL, -10, &"thunderstorm_consumed")
		add(state, BattleModifier.Stat.REINFORCEMENT, 10, &"thunderstorm_infantry")
		state.refresh_cooldown_after_modifier_change()

func protection_count(state: BattleSquadState) -> int:
	var count = 0
	for n: int in state.protection_charges_by_source.values(): count += n
	return count

func on_protection_changed(before: int, after: int, state: BattleSquadState) -> void:
	if active(state, &"swordshield_master"):
		state.set_runtime_action_type(CardData.ActionType.DEFENSE if after > 0 else CardData.ActionType.MELEE)
		if before > 0 and after == 0 and not protection_actions.has(state): protection_actions.append(state)
	if before > 0 and after == 0: protection_losses.append(state)

func sync_auras() -> void:
	if syncing: return
	syncing = true
	for state: BattleSquadState in controller.get_all_states():
		var masked = state.has_effective_shadow() or state.has_runtime_keyword(&"silenced")
		controller.silvermoon.set_aura(state, BattleModifier.Stat.ACTION_VALUE, -state.squad_data.get_ironwall_squad_bonus(&"base_value") if masked else 0, &"ironwall_masked_value")
		controller.silvermoon.set_aura(state, BattleModifier.Stat.MAX_HEALTH, -state.squad_data.get_ironwall_squad_bonus(&"max_health") if masked else 0, &"ironwall_masked_health")
		if active(state, &"thunderstorm_infantry"):
			convert_thunderstorm_zeal(state)
	syncing = false

func execute_trigger(state: BattleSquadState, key: StringName, trigger: int, equipment: bool, _context: Dictionary) -> bool:
	if not active(state, key, equipment, trigger == BattleEffectDefinition.Trigger.LAST_WISH): return false
	match key:
		&"formation_commander":
			var neighbors: Array[BattleSquadState] = controller.get_death_neighbors(state) if trigger == BattleEffectDefinition.Trigger.LAST_WISH else controller._get_adjacent_allies(state)
			for ally: BattleSquadState in neighbors:
				if ally.current_health > 0.0 and not ally.is_banished and ally.squad_data.get_card_count() > 1: ally.grant_protection(&"formation_commander", 1)
		&"mobilization_machine":
			for ally: BattleSquadState in controller._get_adjacent_allies(state): grant_temporary_emblem(ally)
		&"armament_apprentice": improve_equipment(state)
		&"scout":
			for ally: BattleSquadState in controller._get_adjacent_allies(state):
				if ally.current_health > 0.0 and not ally.is_banished and ally.get_effective_action_type() == CardData.ActionType.RANGED: add(ally, BattleModifier.Stat.REINFORCEMENT, 1, key, state)
		&"walking_fighter": state.set_runtime_action_type(CardData.ActionType.DEFENSE if state.get_effective_action_type() == CardData.ActionType.MELEE else CardData.ActionType.MELEE)
		&"inscription_scholar":
			for ally: BattleSquadState in controller.get_living_states(state.side):
				if not ally.is_banished and ally.squad_data.get_equipped_item() != null:
					add(ally, BattleModifier.Stat.REINFORCEMENT, 1, key, state)
					ally.apply_armor_exact(1, state)
		&"field_beer_machine":
			for ally: BattleSquadState in controller._get_adjacent_allies(state):
				if ally.has_effective_race(CardData.RaceType.DWARF): controller._charge_state(ally, BEER_CHARGE_SECONDS)
		&"sentry_pistol": independent_damage(state, random_enemy(state.side), roll(state, 6), CardData.ActionType.RANGED, true, "哨位短铳")
		&"bomb_apprentice": controller.summon_content_minion(state, load("res://resources/cards/booby_mine.tres"))
		&"unstable_explosive_robot": independent_damage(state, random_enemy(state.side), roll(state, 10), CardData.ActionType.MAGIC, false, "自爆机械人遗愿")
		&"booby_mine": independent_damage(state, state.pending_kill_source, roll(state, 10), CardData.ActionType.MAGIC, false, "诡雷遗愿")
		&"anvilbone_ledger":
			var killer = state.pending_kill_source
			if killer != null and killer.alive and not killer.is_banished:
				if not vengeance.has(killer): vengeance[killer] = []
				(vengeance[killer] as Array).append({"left": 3, "groups": {}})
	return true

func roll(state: BattleSquadState, sides: int) -> int:
	return int(controller._roll_probability(state, sides).get("total", 0))

func random_enemy(side: int) -> BattleSquadState:
	var pool: Array[BattleSquadState] = controller.get_living_states(1 - side)
	return pool[controller._random.randi_range(0, pool.size() - 1)] if not pool.is_empty() else null

func independent_damage(source: BattleSquadState, target: BattleSquadState, amount: float, type: CardData.ActionType, typed: bool, label: String) -> void:
	if target == null or not target.alive or target.current_health <= 0.0 or target.is_banished: return
	controller.launch_content_effect(controller.twisted_vein.make_event(source, target, amount, type, typed, label))

func prepare_action(actor: BattleSquadState, mining: bool, type: int) -> Dictionary:
	if active(actor, &"tower_shield", true) and not mining and roll(actor, 6) < 4:
		actor.reset_action_cooldown()
		return {"failed": true}
	var bonus = 0
	var rolls: Array[Dictionary] = []
	if actor.squad_data.get_card_count() > 1:
		for source: BattleSquadState in controller._get_adjacent_allies(actor):
			if source.squad_data.get_card_count() > 1 and active(source, &"phalanx_officer"):
				var amount = roll(source, 4)
				bonus += amount
				rolls.append(roll_source(source, amount))
	if not mining and type == CardData.ActionType.RANGED:
		if active(actor, &"standard_quiver", true):
			var uses = actor.get_buff_stacks(&"standard_quiver_used")
			if uses < 3:
				actor.add_buff_stacks(&"standard_quiver_used", 1)
				add(actor, BattleModifier.Stat.REINFORCEMENT, 2, &"standard_quiver")
	return {"bonus": bonus, "sources": rolls}

func roll_source(source: BattleSquadState, amount: int) -> Dictionary:
	var owned: OwnedCard = source.squad_data.get_effect_source_instance()
	return {"source_name": source.get_effect_source().display_name, "source_card_name": source.get_effect_source().display_name, "source_card_id": String(source.get_effect_source().id), "source_owned_card_instance_id": String(owned.instance_id) if owned != null else "", "source_runtime_id": source.runtime_id, "trigger_name": "行动前1d4", "amount": amount, "source_status": "resolved"}

func on_action_launched(action: Dictionary) -> void:
	var actor = action.get("actor") as BattleSquadState
	var event = action.get("base_event") as BattleEffectEvent
	if event == null or event.is_equipment_repeat or event.is_link_copy or event.resource_target != null: return
	var count = 2 if event.action_type == CardData.ActionType.RANGED and active(actor, &"repeater_gun", true) else (1 if event.action_type == CardData.ActionType.MAGIC and active(actor, &"blackiron_staff", true) else 0)
	for _i: int in count:
		repeats.append({"actor": actor, "target": event.target, "type": event.action_type, "scale": 0.4 if count == 2 else 1.0, "reselect": count == 1})

func adjust_hit(event: BattleEffectEvent) -> void:
	if event.source != null and event.action_type == CardData.ActionType.RANGED and active(event.source, &"array_heavy_crossbow", true): event.pierces_armor = true
	if not event.is_damage(): return
	var multiplier = 1.0
	if active(event.target, &"tower_shield", true) and not event.is_environment_damage and event.log_qualifier != "疲劳": multiplier *= 0.5
	if vengeance.has(event.target) and event.source != null and event.is_attack_action_damage and not event.is_continuous:
		for entry: Dictionary in vengeance[event.target]:
			if entry.groups.has(event.group_id): multiplier *= 2
			elif int(entry.left) > 0: multiplier *= 2
	if not is_equal_approx(multiplier, 1.0) and event.formula != null:
		event.formula.other_multipliers.append({"name": "铁壁承伤", "value": multiplier})

func on_hit(event: BattleEffectEvent) -> void:
	if vengeance.has(event.target) and event.is_attack_action_damage and not event.is_continuous and event.effective_amount > 0.0:
		for entry: Dictionary in vengeance[event.target]:
			if int(entry.left) > 0 and not entry.groups.has(event.group_id):
				entry.left -= 1
				entry.groups[event.group_id] = true
	if event.is_base_action and not event.missed and active(event.source, &"runic_anvil", true) and event.target.alive and event.target.current_health > 0.0 and not event.target.is_banished:
		event.target.apply_sleep(&"runic_anvil_stun", controller.elapsed_seconds + ANVIL_STUN_SECONDS)
		event.target.apply_armor_exact(5, event.source)
	sync_auras()
	resolve_protection_losses()

func resolve_protection_losses() -> void:
	var losses = protection_losses.duplicate()
	protection_losses.clear()
	for victim: BattleSquadState in losses:
		for source: BattleSquadState in controller.get_living_states(victim.side):
			if active(source, &"legion_aegis", true): independent_damage(source, random_enemy(victim.side), 2, CardData.ActionType.MAGIC, false, "军团圣盾")
	var actions = protection_actions.duplicate()
	protection_actions.clear()
	for state: BattleSquadState in actions:
		if state.alive and state.current_health > 0.0 and not state.is_banished and protection_count(state) == 0:
			controller.execute_immediate_action(state, CardData.ActionType.MELEE)
		elif state.current_health <= 0.0: state.clear_runtime_action_type()

func on_unit_defeated(state: BattleSquadState) -> void:
	if not state.has_effective_race(CardData.RaceType.CONSTRUCT): return
	# 退场腾位并重排后读取当前邻居，与通用友军死亡监听使用同一时序。
	for source: BattleSquadState in controller.get_all_states():
		if not active(source, &"recycling_robot"): continue
		for ally: BattleSquadState in controller._get_adjacent_allies(source):
			if ally.current_health > 0.0 and not ally.is_banished: add(ally, BattleModifier.Stat.REINFORCEMENT, 2, &"recycling_robot", source)

func begin_repairs(defeated: Array[BattleSquadState]) -> void:
	# 先让同批死亡全部失活，阿诺与造物同时死亡时不会开始修复。
	for state: BattleSquadState in defeated:
		if not state.has_effective_race(CardData.RaceType.CONSTRUCT) or repair_uses[state.side] >= 5: continue
		var arno: BattleSquadState
		for source: BattleSquadState in controller.get_living_states(state.side):
			if active(source, &"ironhand_arno"): arno = source; break
		if arno == null or float(initial_vitals[state].base_health) <= 0: continue
		repair_uses[state.side] += 1
		state.is_repairing = true
		repairs[state] = {"source": arno, "until": controller.elapsed_seconds + float(initial_vitals[state].base_health)}
	for state: BattleSquadState in repairs.keys():
		if not active(repairs[state].source, &"ironhand_arno"):
			state.is_repairing = false
			repairs.erase(state)
			controller.repair_interrupted.emit(state)

func next_delay(now: float) -> float:
	var delay = 0.0 if not repeats.is_empty() or not protection_actions.is_empty() or not protection_losses.is_empty() else INF
	for entry: Dictionary in repairs.values(): delay = minf(delay, maxf(entry.until - now, 0))
	for entry: Dictionary in periods:
		if active(entry.state, entry.key, entry.equipment): delay = minf(delay, maxf(entry.next - now, 0))
	return delay

func advance_paused_timers(delta: float) -> void:
	for entry: Dictionary in periods:
		if not active(entry.state, entry.key, entry.equipment): entry.next += delta

func process_due() -> void:
	sync_auras()
	for state: BattleSquadState in repairs.keys():
		if repairs[state].until > controller.elapsed_seconds + 0.0001: continue
		repairs.erase(state)
		state.is_repairing = false
		state.alive = true
		state.life_generation += 1
		state.current_health = initial_vitals[state].health
		state.current_armor = initial_vitals[state].armor
		state.pending_kill_source = null
		state.pending_kill_event = null
		state.reset_action_cooldown()
		controller._register_formation_emblems()
		controller.recalculate_logical_layout()
		controller.effect_runtime.recheck_continuous_conditions()
		controller.squad_revived.emit(state)
	for entry: Dictionary in periods:
		if not active(entry.state, entry.key, entry.equipment) or entry.next > controller.elapsed_seconds + 0.0001: continue
		entry.next += entry.period
		var state: BattleSquadState = entry.state
		match StringName(entry.key):
			&"logistics_robot":
				var amount = roll(state, 4)
				for ally: BattleSquadState in controller._get_adjacent_allies(state):
					if ally.squad_data.get_card_count() > 1: add(ally, BattleModifier.Stat.REINFORCEMENT, amount, entry.key, state)
			&"beer_mug": add(state, BattleModifier.Stat.REINFORCEMENT, 1, entry.key)
			&"ironheart_pendant": state.grant_protection(entry.key, 1)
	var queued = repeats.duplicate()
	repeats.clear()
	for entry: Dictionary in queued:
		if not entry.actor.alive or entry.actor.is_banished: continue
		if not entry.reselect and (entry.target == null or not entry.target.alive or entry.target.is_banished): continue
		controller.execute_immediate_action(entry.actor, entry.type, 0, {}, false, {"equipment_repeat": true, "locked_target": entry.target, "reselect_target": entry.reselect, "action_scale": entry.scale, "skip_mining": true})
	resolve_protection_losses()

func release_spell(spell: OwnedCard, side: int) -> bool:
	var key = spell.card_data.content_effect
	if key not in [&"skirmish_formation", &"rally_formation", &"ancestral_blessing"]: return false
	var allies: Array[BattleSquadState] = controller.get_living_states(side)
	if key != &"ancestral_blessing":
		if allies.is_empty(): return true
		for state: BattleSquadState in allies:
			if (state.squad_data.get_card_count() == 1) != (key == &"skirmish_formation"): return true
	if not controller.notify_spell_triggered(spell.instance_id, 0): return true
	if key == &"ancestral_blessing": blessed_sides.append(side)
	else:
		for state: BattleSquadState in allies:
			if key == &"skirmish_formation": add(state, BattleModifier.Stat.ZEAL, 4, key)
			else:
				add(state, BattleModifier.Stat.ACTION_VALUE, 2, key)
				state.apply_armor_exact(4)
		for source: BattleSquadState in allies:
			if active(source, &"augustus_ironwall"):
				for state: BattleSquadState in allies: state.grant_protection(&"augustus_ironwall", 2)
	sync_auras()
	return true

func on_mining(event: BattleEffectEvent) -> void:
	if active(event.source, &"sapper_shovel", true): controller.summon_content_minion(event.source, load("res://resources/cards/booby_mine.tres"))
	if active(event.source, &"ore_appraiser"):
		controller.record_pending_run_reward(BattleEffectOwnerRef.for_state(event.source, BattleEffectDefinition.OwnerKind.OWNING_PLAYER), BattleRunRewardLedger.KIND_GOLD, 1, &"ore_appraiser", event.source.runtime_id, roundi(controller.elapsed_seconds * 1000000))

func harvest_scrap(event: BattleEffectEvent) -> void:
	var pool: Array[BattleSquadState] = controller.get_living_states(event.source.side).filter(func(s: BattleSquadState) -> bool: return s.squad_data.get_equipped_item() == null and not s.is_banished)
	if pool.is_empty(): return
	var target: BattleSquadState = pool[controller._random.randi_range(0, pool.size() - 1)]
	var candidates: Array[CardData] = []
	for card: CardData in controller._reward_card_catalog:
		if not card.is_available or card.is_derived or card.card_type != CardData.CardType.EQUIPMENT or card.rarity > CardData.Rarity.IV: continue
		if card.rarity == CardData.Rarity.IV and ((event.source.side == 0 and int(controller._player_owned_card_ids.get(card.id, 0)) > 0) or controller.get_living_states(event.source.side).any(func(s: BattleSquadState) -> bool: return s.squad_data.get_equipped_item() != null and s.squad_data.get_equipped_item().card_data.id == card.id)): continue
		if card.has_keyword(&"squad_equipment") and target.squad_data.get_card_count() == 1: continue
		candidates.append(card)
	if candidates.is_empty(): return
	var owned = OwnedCard.new()
	var selector = OrdinaryShopService.new()
	selector.load_config()
	var counts: Dictionary = controller._player_owned_card_ids if event.source.side == 0 else {}
	if event.source.side == 1:
		for state: BattleSquadState in controller.get_all_states():
			if state.side != 1: continue
			for card: CardData in state.squad_data.horizontal_cards: counts[card.id] = int(counts.get(card.id, 0)) + 1
			var item: OwnedCard = state.squad_data.get_equipped_item()
			if item != null: counts[item.card_data.id] = int(counts.get(item.card_data.id, 0)) + 1
	var definition: CardData = selector.draw_card_candidate(candidates, controller._random, counts)
	owned.initialize(definition, StringName("%s:ironwall_item:%d" % [controller.battle_instance_id, controller._next_reward_instance_sequence]), 0, controller._random)
	controller._next_reward_instance_sequence += 1
	if not target.squad_data.equip_item(owned): return
	temporary_items.append({"state": target, "item": owned})
	target.apply_armor_exact(definition.equipment_armor_delta)
	target.apply_healing_exact(maxi(definition.equipment_health_delta, 0))
	controller._register_card_effects(target, definition, true)
	initialize_equipment_period(target, definition.content_effect)
	controller.mining_actions_remaining_by_runtime_id[target.runtime_id] = int(controller.mining_actions_remaining_by_runtime_id.get(target.runtime_id, 0)) + definition.mining_uses
	if definition.content_effect == &"legion_aegis": target.grant_protection(&"legion_aegis", 2)
	sync_auras()

func initialize_equipment_period(state: BattleSquadState, key: StringName) -> void:
	if key in [&"beer_mug", &"ironheart_pendant"]:
		var period = MUG_PERIOD if key == &"beer_mug" else PENDANT_PERIOD
		periods.append({"state": state, "key": key, "period": period, "next": controller.elapsed_seconds + period, "equipment": true})

func improve_equipment(state: BattleSquadState) -> void:
	var item = state.squad_data.get_equipped_item()
	if item == null: return
	var owner = BattleEffectOwnerRef.for_owned_card_in_state(state, item)
	if roll(state, 10) == 1:
		if not temporary_items.any(func(e: Dictionary) -> bool: return e.item == item): controller.owned_card_change_ledger.record_equipment_consumption(owner, &"armament_apprentice", state.runtime_id, roundi(controller.elapsed_seconds * 1000000), controller.battle_instance_id)
		state.squad_data.unequip_item()
		state.current_armor = maxf(state.current_armor - item.card_data.equipment_armor_delta, 0)
		state.protection_charges_by_source.erase(&"legion_aegis")
		controller.effect_runtime.recheck_continuous_conditions()
	else:
		if not temporary_items.any(func(e: Dictionary) -> bool: return e.item == item): controller.record_pending_permanent_growth(owner, &"base_value", 1, &"armament_apprentice", state.runtime_id, roundi(controller.elapsed_seconds * 1000000))
		item.apply_permanent_growth(&"base_value", 1)

func grant_temporary_emblem(state: BattleSquadState) -> void:
	if state.is_banished: return
	var empty: Array[Dictionary] = []
	var upgrades: Array[Dictionary] = []
	var definitions = EmblemLibraryData.get_definitions()
	for card: CardData in state.squad_data.horizontal_cards:
		var owned = state.squad_data.get_owned_card(card)
		if owned == null: continue
		for index: int in state.squad_data.get_visible_emblem_slot_indices(card):
			var slot = owned.emblem_slots[index]
			if slot.is_empty(): empty.append({"owned": owned, "index": index})
			else:
				var current = String(slot.get("emblem_id", ""))
				var next = current.trim_suffix("Ⅰ") + "Ⅱ" if current.ends_with("Ⅰ") else (current.trim_suffix("Ⅱ") + "Ⅲ" if current.ends_with("Ⅱ") else "")
				if definitions.any(func(d: Dictionary) -> bool: return String(d.id) == next): upgrades.append({"owned": owned, "index": index, "upgrade": StringName(next)})
	var options = empty if not empty.is_empty() else upgrades
	if options.is_empty(): return
	var selected: Dictionary = options[controller._random.randi_range(0, options.size() - 1)]
	var id: StringName
	if selected.has("upgrade"): id = selected.upgrade
	else:
		var roll_value: int = controller._random.randi_range(1, 100)
		var rarity = 0 if roll_value <= 85 else (1 if roll_value <= 98 else 2)
		var pool: Array = definitions.filter(func(d: Dictionary) -> bool: return int(d.get("rarity", -1)) == rarity and d.get("target", "") != "rune")
		if pool.is_empty(): return
		id = pool[controller._random.randi_range(0, pool.size() - 1)].id
	temporary_emblems.append({"owned": selected.owned, "index": selected.index, "before": selected.owned.emblem_slots[selected.index].duplicate(true)})
	var health_before = state.get_max_health()
	var armor_before = state.squad_data.get_effective_base_armor()
	selected.owned.set_emblem_slot(selected.index, {"emblem_id": id, "instance_id": StringName("ironwall:%s:%d" % [controller.battle_instance_id, temporary_emblems.size()])})
	state.apply_healing_exact(maxi(state.get_max_health() - health_before, 0))
	state.apply_armor_exact(maxi(state.squad_data.get_effective_base_armor() - armor_before, 0))
	controller._register_formation_emblems()

func finish(result: int) -> void:
	for state: BattleSquadState in controller.get_all_states():
		var won: bool = (result in [1, 3]) == (state.side == 0)
		if not won: continue
		if active(state, &"anvilbone_ledger", true): grow(state, 1, 2, &"anvilbone_ledger")
		if state.battle_participated and state.battle_ever_defeated and not state.battle_summoned:
			for side: int in blessed_sides:
				if side == state.side: grow(state, 1, 1, &"ancestral_blessing")
	restore_temporary()

func grow(state: BattleSquadState, value: int, health: int, key: StringName) -> void:
	for entry: Array in [[state.squad_data.get_action_source_instance(), &"base_value", value], [state.squad_data.get_vitals_source_instance(), &"max_health", health]]:
		if entry[0] != null: controller.record_pending_permanent_growth(BattleEffectOwnerRef.for_owned_card_in_state(state, entry[0]), entry[1], entry[2], key, state.runtime_id, roundi(controller.elapsed_seconds * 1000000))

func restore_temporary() -> void:
	for i: int in range(temporary_emblems.size() - 1, -1, -1):
		var entry = temporary_emblems[i]
		entry.owned.set_emblem_slot(entry.index, entry.before)
	temporary_emblems.clear()
	for entry: Dictionary in temporary_items: entry.state.squad_data.unequip_item()
	temporary_items.clear()

func cleanup() -> void:
	restore_temporary()
	for state: BattleSquadState in initial_vitals:
		if state.damage_taken.is_connected(on_damage_taken.bind(state)): state.damage_taken.disconnect(on_damage_taken.bind(state))
		if state.armor_gained.is_connected(on_armor_gained.bind(state)): state.armor_gained.disconnect(on_armor_gained.bind(state))
		if state.protection_changed.is_connected(on_protection_changed.bind(state)): state.protection_changed.disconnect(on_protection_changed.bind(state))
		state.is_repairing = false
	initial_vitals.clear()
	repairs.clear()
	periods.clear()
	repeats.clear()
	vengeance.clear()
	protection_actions.clear()
	protection_losses.clear()
