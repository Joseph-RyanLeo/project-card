class_name TwistedVeinRuntime
extends RefCounted

## 矿脉内容的事件响应。控制器负责时钟、弹道和死亡队列，本类只决定已确认效果。
## 所有跨战变化写入账本；钱包、休眠与符文覆盖只活在当前战斗里。
var controller: Node
var wallets: Array[int] = [0, 15]
var mining_totals: Array[int] = [0, 0]
var mineral_events: int = 0
var mining_events: int = 0
var stolen_from_player: int = 0
const TONGUE_SLEEP_SECONDS: float = 3.0 # 舌蜥攻击命中后双方休眠时长
const FIRE_CONVERSION_COUNT: int = 2 # 余火精灵突击最多转换的有效非火符文数量
var helmet_used: Dictionary = {}
var fatigue_next: Dictionary = {}

func initialize(value: Node, context: Dictionary) -> void:
	controller = value
	wallets[0] = maxi(int(context.get("player_gold", 0)), 0)
	var totals: Array = context.get("mining_totals", [0, 0])
	for side: int in 2: mining_totals[side] = int(totals[side]) if side < totals.size() else 0

func add_fatigue(state: BattleSquadState, amount: int) -> void:
	var stacks := state.add_buff_stacks(BattleRules.FATIGUE_BUFF_ID, amount)
	controller.buff_stacks_changed.emit(state, BattleRules.FATIGUE_BUFF_ID, stacks)
	if not fatigue_next.has(state): fatigue_next[state] = {"next_time": controller.elapsed_seconds + 1.0, "paused_at": -1.0}

func active(state: BattleSquadState, key: StringName, equipment: bool = false, allow_dead: bool = false) -> bool:
	if state == null or state.squad_data == null or state.is_banished or state.has_effective_shadow() or state.has_runtime_keyword(&"silenced"):
		return false
	if not allow_dead and (not state.alive or state.current_health <= 0.0): return false
	var item: OwnedCard = state.squad_data.get_equipped_item()
	var card: CardData = item.card_data if equipment and item != null else (null if equipment else state.get_effect_source())
	return card != null and card.is_available and card.content_effect == key

func has_lamp_aura(state: BattleSquadState) -> bool:
	if state == null: return false
	for holder: BattleSquadState in controller.get_living_states(state.side):
		if active(holder, &"portable_mine_lamp", true) and (holder == state or holder in controller._get_adjacent_allies(state)):
			return true
	return false

func has_infinite_mining(state: BattleSquadState) -> bool:
	return active(state, &"crystal_shard_beetle") or active(state, &"rusted_pickhand") or active(state, &"gold_sprite")

func mining_target_count(state: BattleSquadState) -> int:
	return 2 if active(state, &"gold_sprite") else 1

func execute_trigger(state: BattleSquadState, key: StringName, trigger: int, equipment: bool) -> bool:
	var dead := trigger == BattleEffectDefinition.Trigger.LAST_WISH
	if not active(state, key, equipment, dead): return false
	match key:
		&"miserly_mine_owner":
			var amount := mining_totals[0] + mining_totals[1]
			add_modifier(state, BattleModifier.Stat.REINFORCEMENT, amount, key)
			gain_health(state, amount, key)
		&"golden_golem": remove_emblem_for_reinforcement(state)
		&"rallying_mine_bell": summon_from_bell(state)
		&"mining_disaster_wraith":
			var events: Array[BattleEffectEvent] = []
			for target: BattleSquadState in controller.get_all_states():
				if target.alive and target.current_health > 0.0 and not target.has_effective_shadow():
					events.append(make_event(state, target, 2, CardData.ActionType.RANGED, true, "矿难怨灵回响"))
			controller.resolve_content_batch(events)
			spawn_random_resource(false)
		&"miser": steal_gold(state)
		&"frenzied_gold_panner":
			for neighbor: BattleSquadState in controller.get_death_neighbors(state):
				controller.launch_content_effect(make_event(state, neighbor, state.death_action_value, CardData.ActionType.MELEE, false, "淘金者遗愿"), false)
		&"ember_spirit": convert_element_to_fire(state)
		&"minecart_soul": controller.execute_content_action(state, dead)
		&"clearing_machine": controller.execute_effect_mining(state, 2, 2.0)
		&"ghostface_beetle":
			for neighbor: BattleSquadState in controller.get_death_neighbors(state): gain_health(neighbor, 2, key)
		&"mine_wailer":
			var killer := state.pending_kill_source
			if killer != null and killer.alive and killer.current_health > 0.0:
				add_fatigue(killer, 2)
		&"ember_residue":
			if dead: spawn_random_resource(true)
			else:
				state.current_health = 0.0
				state.pending_kill_source = state
				controller.preserve_source_projectiles_for_death_chain(state)
				controller._finalize_batch()
		&"crystal_shell_beetle": spawn_random_resource(true)
		&"mine_lamp_wisp":
			var killer := state.pending_kill_source
			if killer != null: killer.runtime_base_target_multiplier *= 2.0
		&"ghost_pick": controller.execute_effect_mining(state, 1)
		&"crystal_shard_pouch":
			var shard: CardData = controller._random_shard_definition()
			if shard != null: controller.resolve_direct_shard_harvest(state, shard)
	return true

func add_modifier(state: BattleSquadState, stat: int, amount: float, effect: StringName) -> void:
	if is_zero_approx(amount): return
	var modifier := BattleModifier.new()
	modifier.stat = stat as BattleModifier.Stat
	modifier.mode = BattleModifier.Mode.ADD
	modifier.value = amount
	modifier.effect_id = effect
	modifier.source_runtime_id = state.runtime_id
	modifier.contribution_sources.append({"source_name": String(effect), "source_card_name": state.get_effect_source().display_name, "source_status": "resolved", "amount": amount})
	state.modifiers.add_modifier(modifier)

func gain_health(state: BattleSquadState, amount: float, effect: StringName) -> void:
	add_modifier(state, BattleModifier.Stat.MAX_HEALTH, amount, effect)
	state.apply_healing_exact(amount, state)

func make_event(source: BattleSquadState, target: BattleSquadState, amount: float, action_type: CardData.ActionType, typed_damage: bool, label: String) -> BattleEffectEvent:
	var event := BattleEffectEvent.new()
	event.source = source
	event.target = target
	event.anchor = target
	event.action_type = action_type
	event.exact_amount = amount
	event.uses_attack_type_multiplier = typed_damage
	event.can_trigger_element_chain = false
	event.visual_kind = &"magic_attack" if action_type == CardData.ActionType.MAGIC else &"ranged_attack"
	event.log_qualifier = label
	event.formula = BattleFormulaData.create(label, action_type, amount, 1.0, 1.0, source, target)
	return event

func on_mining(event: BattleEffectEvent) -> void:
	# 记录成功开采当刻的邻居，避免后续召唤插入改变本次监听者。
	var adjacent_allies: Array[BattleSquadState] = controller._get_adjacent_allies(event.source)
	mining_events += 1
	mining_totals[event.source.side] += 1
	var mineral: bool = event.resource_target.owned_card.card_data.resource_type == CardData.ResourceType.MINERAL
	if mineral: mineral_events += 1
	var owner := BattleEffectOwnerRef.for_state(event.source, BattleEffectDefinition.OwnerKind.OWNING_PLAYER)
	controller.record_pending_run_reward(owner, BattleRunRewardLedger.KIND_MINING_COUNT, 1, &"successful_mining", event.source.runtime_id, roundi(controller.elapsed_seconds * 1000000.0))
	# 条件法术先结算，再派发开采监听；两次双开采有两份独立事件。
	for spell: OwnedCard in controller._get_all_prepared_spell_instances():
		if spell == null or spell.card_data == null: continue
		var key := spell.card_data.content_effect
		if not ((key == &"mine_collapse" and mineral_events >= 2) or (key == &"soul_of_forging" and mining_events >= 1)): continue
		if not controller.notify_spell_triggered(spell.instance_id, 0): continue
		controller._present_nonpausing_spell(spell)
		if key == &"mine_collapse":
			var events: Array[BattleEffectEvent] = []
			for target: BattleSquadState in controller.get_all_states():
				if target.alive and target.current_health > 0.0 and not target.has_effective_shadow():
					events.append(make_event(null, target, 2.0, CardData.ActionType.MAGIC, false, "矿道坍塌"))
			controller.resolve_content_batch(events)
			spawn_random_resource(false)
		else:
			for target: BattleSquadState in controller.get_all_states():
				if not target.alive or target.current_health <= 0.0 or target.has_effective_shadow(): continue
				target.apply_armor_exact(2.0)
				if target.squad_data.get_equipped_item() != null: add_modifier(target, BattleModifier.Stat.ACTION_VALUE, 2.0, key)
	controller.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ADJACENT_ALLY_MINED, {"actor": event.source, "adjacent_allies": adjacent_allies})
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	for state: BattleSquadState in controller.get_all_states():
		if active(state, &"guard_remains"): state.sleep_source_until.erase(BattleSquadState.INITIAL_CONTENT_SLEEP_SOURCE)
		if active(state, &"crystal_shell_broodmother") and state.side == event.source.side:
			controller.summon_content_minion(state, load("res://resources/cards/crystal_shell_beetle.tres"))
	if active(event.source, &"crystal_shard_beetle"):
		add_modifier(event.source, BattleModifier.Stat.ACTION_VALUE, 1, &"crystal_shard_beetle")
		gain_health(event.source, 1, &"crystal_shard_beetle")

func on_gold(actor: BattleSquadState, amount: int) -> void:
	if actor == null or amount <= 0: return
	wallets[actor.side] += amount
	for state: BattleSquadState in controller.get_all_states():
		if active(state, &"greed_demon"): add_modifier(state, BattleModifier.Stat.ACTION_VALUE, amount, &"greed_demon")
		if active(state, &"greedy_acolyte") and actor.alive and actor.current_health > 0.0 and not actor.has_effective_shadow():
			# 明确治疗赚金币者，允许敌人和休眠响应；沿用治疗的牌型、强化、元素和事件结算。
			controller.execute_targeted_healing(state, actor)

func apply_gold_loss(side: int, requested: int) -> int:
	var amount := mini(wallets[side], maxi(requested, 0))
	wallets[side] -= amount
	return amount

func steal_gold(actor: BattleSquadState) -> void:
	var opposing := 1 - actor.side
	if wallets[opposing] < 2: return
	wallets[opposing] -= 2
	if opposing == BattleSquadState.Side.PLAYER:
		stolen_from_player += 2
		var loss_owner := BattleEffectOwnerRef.for_state(actor, BattleEffectDefinition.OwnerKind.OWNING_PLAYER)
		# 扣款归玩家而非盗贼：用参数保留受损方，战后胜利退款也进入同一账本。
		controller.record_pending_run_reward(loss_owner, BattleRunRewardLedger.KIND_PLAYER_THEFT, 2, &"miser_theft", actor.runtime_id, roundi(controller.elapsed_seconds * 1000000.0))
	controller.record_pending_run_reward(BattleEffectOwnerRef.for_state(actor, BattleEffectDefinition.OwnerKind.OWNING_PLAYER), BattleRunRewardLedger.KIND_GOLD, 2, &"miser_theft", actor.runtime_id, roundi(controller.elapsed_seconds * 1000000.0))

func finish(result: int) -> void:
	if stolen_from_player > 0 and result in [1, 3]:
		# Result枚举在控制器中为NONE/PLAYER_VICTORY/PLAYER_DEFEAT/DRAW。
		controller.run_reward_ledger.record_player_refund(stolen_from_player, controller.battle_instance_id)
	for state: BattleSquadState in controller.get_all_states():
		var item: OwnedCard = state.squad_data.get_equipped_item()
		if item != null and item.card_data.equipment_durability > 0 and state.battle_participated:
			controller.owned_card_change_ledger.record_content_change(BattleEffectOwnerRef.for_state(state, BattleEffectDefinition.OwnerKind.EQUIPMENT_INSTANCE), BattleOwnedCardChangeLedger.KIND_EQUIPMENT_DURABILITY, {"amount": 1}, controller.battle_instance_id)

func remove_emblem_for_reinforcement(state: BattleSquadState) -> void:
	var owned := state.squad_data.get_effect_source_instance()
	if owned == null: return
	var slots: Array[int] = []
	for index: int in owned.emblem_slots.size():
		if not owned.emblem_slots[index].is_empty(): slots.append(index)
	if slots.is_empty(): return
	var index: int = slots[controller._random.randi_range(0, slots.size() - 1)]
	controller.record_pending_owned_card_slot_change(BattleEffectOwnerRef.for_owned_card_in_state(state, owned), BattleOwnedCardChangeLedger.KIND_SET_EMBLEM_SLOT, index, {}, &"golden_golem", state.runtime_id, roundi(controller.elapsed_seconds * 1000000.0))
	owned.set_emblem_slot(index, {})
	controller._sync_emblem_registration_visibility()
	add_modifier(state, BattleModifier.Stat.REINFORCEMENT, 10, &"golden_golem")

func convert_element_to_fire(state: BattleSquadState) -> void:
	var candidates: Array[Dictionary] = []
	for slot: Dictionary in state.get_active_rune_slots():
		if int(slot.get("element", -1)) < 0 or int(slot.element) == CardData.ElementType.FIRE: continue
		candidates.append(slot)
	# 随机取出后移除候选，保证不重复选同一槽；覆盖只存战斗状态，不改拥有卡或贴纸。
	for _index: int in mini(FIRE_CONVERSION_COUNT, candidates.size()):
		var index: int = controller._random.randi_range(0, candidates.size() - 1)
		var selected: Dictionary = candidates[index]
		candidates.remove_at(index)
		state.set_runtime_rune_override(selected.card, int(selected.rune_index), CardData.ElementType.FIRE)
	controller._apply_visible_fire_rune_reinforcement()

func summon_from_bell(source: BattleSquadState) -> void:
	var rarity := CardData.Rarity.I if controller._random.randi_range(1, 100) <= 60 else CardData.Rarity.II
	var pool: Array[CardData] = []
	for card: CardData in controller._reward_card_catalog:
		if card.card_type == CardData.CardType.MINION and card.pack_id == &"twisted_vein" and card.rarity == rarity and card.is_available and not card.is_derived and card.content_effect != &"rallying_mine_bell": pool.append(card)
	if not pool.is_empty(): controller.summon_content_minion(source, pool[controller._random.randi_range(0, pool.size() - 1)])

func spawn_random_resource(shard_only: bool, side: int = -1) -> void:
	var pool: Array[CardData] = []
	for card: CardData in controller._reward_card_catalog:
		if card.card_type != CardData.CardType.RESOURCE or not card.is_available: continue
		if shard_only:
			if card.id in [&"fire_element_shard", &"water_element_shard", &"wood_element_shard", &"light_element_shard", &"dark_element_shard"]: pool.append(card)
		elif card.resource_type == CardData.ResourceType.MINERAL: pool.append(card)
	if not pool.is_empty(): controller.spawn_content_resource(pool[controller._random.randi_range(0, pool.size() - 1)], controller._random.randi_range(0, 1) if side < 0 else side)

func on_hit(event: BattleEffectEvent) -> void:
	if not event.is_base_action or event.missed or not event.is_damage() or event.target == null or event.source == null: return
	var actor := event.source
	var target := event.target
	if active(actor, &"subterranean_blindfish"):
		add_modifier(target, BattleModifier.Stat.TARGET_PRIORITY, 2, &"subterranean_blindfish")
	if active(actor, &"rusted_pickhand"):
		var owned := target.squad_data.get_vitals_source_instance()
		if owned != null:
			var amount := minf(1.0, maxf(owned.get_base_stat_with_permanent_growth(OwnedCard.STAT_BASE_ARMOR), 0.0))
			if amount > 0.0: controller._record_resource_permanent_growth(target, BattlePermanentGrowthLedger.STAT_BASE_ARMOR, -amount, &"rusted_pickhand", roundi(controller.elapsed_seconds * 1000000.0), false)
			target.destroy_armor_exact(1.0, actor, event)
		elif target.get_vitals_source() != null:
			target.runtime_permanent_armor_growth = maxf(target.runtime_permanent_armor_growth - 1.0, -float(target.get_vitals_source().armor))
			target.destroy_armor_exact(1.0, actor, event)
	if active(actor, &"rockwall_tongue_lizard") and target.alive and target.current_health > 0.0:
		var key := StringName("tongue_sleep:%d" % actor.runtime_id)
		var until_time: float = controller.elapsed_seconds + TONGUE_SLEEP_SECONDS
		actor.apply_sleep(key, until_time)
		target.apply_sleep(key, until_time)

func prevents_damage(event: BattleEffectEvent) -> bool:
	if not event.is_base_action or event.element_type >= 0 or not active(event.target, &"dwarven_mining_helmet", true): return false
	if event.action_type not in [CardData.ActionType.RANGED, CardData.ActionType.MAGIC]: return false
	var key := "%s:%d" % [event.target.squad_data.get_equipped_item().instance_id, event.action_type]
	if helmet_used.has(key): return false
	helmet_used[key] = true
	return true

func next_delay(now: float) -> float:
	var delay := INF
	for state: BattleSquadState in fatigue_next:
		if not state.alive or state.current_health <= 0.0: continue
		var timer: Dictionary = fatigue_next[state]
		if state.is_banished or state.has_effective_shadow():
			if float(timer.paused_at) < 0.0: timer.paused_at = now
			continue
		if float(timer.paused_at) >= 0.0:
			timer.next_time = float(timer.next_time) + now - float(timer.paused_at)
			timer.paused_at = -1.0
		delay = minf(delay, maxf(float(timer.next_time) - now, 0.0))
	return delay

func process_due() -> void:
	for state: BattleSquadState in fatigue_next.keys():
		if not state.alive:
			fatigue_next.erase(state)
			continue
		var timer: Dictionary = fatigue_next[state]
		if state.is_banished or state.has_effective_shadow() or controller.elapsed_seconds + 0.0001 < float(timer.next_time): continue
		timer.next_time = float(timer.next_time) + BattleRules.FATIGUE_DAMAGE_INTERVAL_SECONDS
		var event := make_event(null, state, state.get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) * (controller.silvermoon.fatigue_multiplier(state) if controller.silvermoon != null else 1.0), CardData.ActionType.MELEE, false, "疲劳")
		event.pierces_armor = true
		event.is_environment_damage = true
		controller.launch_content_effect(event, false)
