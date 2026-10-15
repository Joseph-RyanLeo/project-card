class_name SilvermoonRuntime
extends RefCounted

## 银月内容只负责规则决策；时间、弹道、死亡、随机源和永久结算仍由通用控制器执行。
const KNIGHT_STUN_SECONDS: float = 1.0 # 骑士前排突击的眩晕时长
const ELEMENT_OPENING_SECONDS: float = 10.0 # 元素前排热诚加成从开战起持续的秒数
const MOVE_COOLDOWN: float = 0.1 # 每张位移监听卡的独立内部冷却秒数
const VEIL_SECONDS: float = 3.0 # 暮光面纱放逐时长
const STARFIRE_PERIOD: float = 3.0 # 星火术周期；无目标也进入下一个周期
const NIGHTFALL_ADVANCE_SECONDS: float = 10.0 # 黑夜把尚未开始的疲劳风暴提前的秒数
var controller: Node
var last_movement: Dictionary = {}
var layout_snapshot: Dictionary = {}
var links: Dictionary = {} # 每个祭祀小队最多保留一条攻击行动链接
var banishments: Dictionary = {}
var periodic_spells: Dictionary = {}
var spell_counts: Dictionary = {}
var used_spells: Dictionary = {}
var shadow_beneficiaries: Dictionary = {}
var prophecies: Array[Dictionary] = []
var extra_actions: Array[BattleSquadState] = []
var pending_seed_actions: Dictionary = {} # 弹道批次完成后才追加；不抢在原行动命中之前
var syncing: bool = false

func initialize(value: Node, preview: bool = false) -> void:
	controller = value
	for state: BattleSquadState in controller.get_all_states():
		if not preview: initialize_state(state)
	controller.kill_resolved.connect(_on_kill)
	sync_auras()
	capture_layout()

func initialize_state(state: BattleSquadState) -> void:
	if active(state, &"moon_hawk"):
		state.apply_sleep(&"silvermoon_entry", controller.elapsed_seconds + 30.0)
	elif active(state, &"moonshadow_stoneguard"):
		state.apply_sleep(&"silvermoon_entry", controller.elapsed_seconds + 10.0)

func active(state: BattleSquadState, key: StringName, equipment: bool = false, allow_dead: bool = false) -> bool:
	if state == null or state.is_banished or state.has_effective_shadow() or state.has_runtime_keyword(&"silenced"): return false
	if not allow_dead and (not state.alive or state.current_health <= 0.0): return false
	var item: OwnedCard = state.squad_data.get_equipped_item()
	var card: CardData = item.card_data if equipment and item != null else (null if equipment else state.get_effect_source())
	return card != null and card.is_available and card.content_effect == key

func eligible(side: int) -> Array[BattleSquadState]:
	return controller.get_living_states(side).filter(func(s: BattleSquadState) -> bool: return s.current_health > 0.0 and not s.has_effective_shadow())

func random_target(side: int) -> BattleSquadState:
	var pool := eligible(side)
	return pool[controller._random.randi_range(0, pool.size() - 1)] if not pool.is_empty() else null

func add(state: BattleSquadState, stat: int, amount: float, key: StringName) -> void:
	controller.twisted_vein.add_modifier(state, stat, amount, key)

func set_aura(state: BattleSquadState, stat: int, amount: float, key: StringName) -> void:
	for modifier: BattleModifier in state.modifiers.modifiers:
		if modifier.effect_id == key and modifier.stat == stat:
			if not is_equal_approx(modifier.value, amount):
				modifier.value = amount
				state.refresh_cooldown_after_modifier_change()
			return
	if not is_zero_approx(amount):
		add(state, stat, amount, key)
		state.refresh_cooldown_after_modifier_change()

func sync_auras() -> void:
	if syncing: return
	syncing = true
	var states: Array[BattleSquadState] = controller.get_all_states()
	for state: BattleSquadState in states:
		var balanced := active(state, &"il_ancient_speaker") or active(state, &"twilight_knight") or active(state, &"twilight_guard") or active(state, &"twilight_elemental") or active(state, &"starmoon_leopard")
		if balanced:
			var key := state.get_effect_source().content_effect
			var back: bool = controller.is_back_row(state.row_key)
			var front_type := CardData.ActionType.DEFENSE if key in [&"il_ancient_speaker", &"twilight_guard"] else (CardData.ActionType.MAGIC if key == &"twilight_elemental" else CardData.ActionType.MELEE)
			var back_type := CardData.ActionType.HEAL if key == &"twilight_guard" else CardData.ActionType.MAGIC
			state.set_runtime_action_type(back_type if back else front_type)
		else:
			if state.get_effect_source().pack_id == &"silvermoon_chapter": state.clear_runtime_action_type()
		var guard_front: bool = active(state, &"twilight_guard") and not controller.is_back_row(state.row_key)
		if guard_front: state.grant_runtime_keyword(&"dazzling", -17002)
		else: state.revoke_runtime_keyword(&"dazzling", -17002)
		set_aura(state, BattleModifier.Stat.ZEAL, 10 if active(state, &"twilight_elemental") and not controller.is_back_row(state.row_key) and controller.elapsed_seconds < ELEMENT_OPENING_SECONDS else 0, &"silvermoon_element_zeal")
		set_aura(state, BattleModifier.Stat.ZEAL, 4 if active(state, &"starmoon_leopard") and not controller.is_back_row(state.row_key) else 0, &"silvermoon_leopard_zeal")
		set_aura(state, BattleModifier.Stat.ACTION_VALUE, 1 if active(state, &"starmoon_leopard") and controller.is_back_row(state.row_key) else 0, &"silvermoon_leopard_value")
		set_aura(state, BattleModifier.Stat.ACTION_VALUE, 1 if active(state, &"sunmoon_amulet", true) and not controller.is_back_row(state.row_key) else 0, &"silvermoon_amulet_value")
		set_aura(state, BattleModifier.Stat.ZEAL, 2 if active(state, &"sunmoon_amulet", true) and controller.is_back_row(state.row_key) else 0, &"silvermoon_amulet_zeal")
	syncing = false

func execute_trigger(state: BattleSquadState, key: StringName, _trigger: int, equipment: bool, context: Dictionary) -> bool:
	if not active(state, key, equipment): return false
	match key:
		&"darkmoon_judge":
			for target: BattleSquadState in controller.get_all_states():
				if target.alive and target.current_health > 0.0 and not target.is_banished and target.current_health < state.current_health:
					controller.twisted_vein.add_fatigue(target, 1)
		&"moonlight_treant":
			var slots := state.get_active_rune_slots()
			if not slots.is_empty():
				state.set_runtime_rune_override(slots[0].card, slots[0].rune_index, CardData.ElementType.DARK)
				state.refresh_cooldown_after_modifier_change()
		&"twilight_knight": knight_rush(state)
		&"il_ancient_speaker": balance_growth(state)
		&"starlight_weaver":
			var owner := BattleEffectOwnerRef.for_state(state, BattleEffectDefinition.OwnerKind.OWNING_PLAYER)
			controller._record_resource_card_award(owner, load("res://resources/cards/moondew.tres"), key, state, roundi(controller.elapsed_seconds * 1000000.0))
		&"silvermoon_apprentice":
			var pool: Array[BattleSquadState] = []
			pool.append(state)
			for target: BattleSquadState in pool:
				if not target.alive or target.is_banished: continue
				var light := 0
				var dark := 0
				for slot: Dictionary in target.get_active_rune_slots():
					if int(slot.get("element", -1)) == CardData.ElementType.LIGHT: light += 1
					if int(slot.get("element", -1)) == CardData.ElementType.DARK: dark += 1
				if light > 0: permanent_health(target, light, state, key)
				add(target, BattleModifier.Stat.REINFORCEMENT, dark * 2, key)
		&"stargazer":
			var owner := BattleEffectOwnerRef.for_state(state, BattleEffectDefinition.OwnerKind.OWNING_PLAYER)
			for id: String in ["victory_prophecy", "failure_prophecy"]:
				controller._record_resource_card_award(owner, load("res://resources/cards/%s.tres" % id), &"stargazer", state, roundi(controller.elapsed_seconds * 1000000.0))
		&"moon_dancer":
			var neighbors: Array[BattleSquadState] = controller._get_adjacent_allies(state).filter(func(s: BattleSquadState) -> bool: return not s.is_banished)
			if not neighbors.is_empty(): swap(state, neighbors[controller._random.randi_range(0, neighbors.size() - 1)])
		&"dancer_handbell": swap_other_row(state)
		&"moon_singer":
			var action: Dictionary = context.get("action", {})
			var target: BattleSquadState = action.get("target")
			if target != null and target.alive and not target.is_banished: swap_other_row(target)
	return true

func knight_rush(source: BattleSquadState) -> void:
	var pool := eligible(1 - source.side)
	for _index: int in mini(3, pool.size()):
		var target: BattleSquadState = pool.pop_at(controller._random.randi_range(0, pool.size() - 1))
		if controller.is_back_row(source.row_key):
			controller.twisted_vein.add_fatigue(target, 1)
		else:
			target.apply_sleep(StringName("twilight_knight:%d" % source.runtime_id), controller.elapsed_seconds + KNIGHT_STUN_SECONDS)


func permanent_health(target: BattleSquadState, amount: int, source: BattleSquadState, key: StringName) -> void:
	var owner := BattleEffectOwnerRef.for_state(target, BattleEffectDefinition.OwnerKind.ARMOR_PROVIDER_CARD)
	if controller.record_pending_permanent_growth(owner, &"max_health", amount, key, source.runtime_id, roundi(controller.elapsed_seconds * 1000000.0)):
		# 账本负责跨战归属；本场生命层立即可见，不改写共享定义或收藏实例。
		controller.twisted_vein.gain_health(target, amount, key)

func balance_growth(source: BattleSquadState) -> void:
	for target: BattleSquadState in controller.get_all_states():
		if not target.alive or target.is_banished or target.current_health <= 0.0: continue
		var net_light := 0
		for slot: Dictionary in target.get_active_rune_slots():
			if int(slot.get("element", -1)) == CardData.ElementType.LIGHT: net_light += 1
			elif int(slot.get("element", -1)) == CardData.ElementType.DARK: net_light -= 1
		if net_light > 0:
			permanent_health(target, net_light * 2, source, &"il_ancient_speaker")
		elif net_light < 0:
			var owner := BattleEffectOwnerRef.for_state(target, BattleEffectDefinition.OwnerKind.ACTION_PROVIDER_CARD)
			if controller.record_pending_permanent_growth(owner, &"base_value", -net_light, &"il_ancient_speaker", source.runtime_id, roundi(controller.elapsed_seconds * 1000000.0)):
				target.runtime_permanent_action_growth += -net_light

func legal_swap(a: BattleSquadState, b: BattleSquadState) -> bool:
	if a == b or not a.alive or not b.alive or a.side != b.side or a.is_banished or b.is_banished: return false
	if a.row_key == b.row_key: return true
	for pair: Array in [[a, b], [b, a]]:
		var used := 0
		for state: BattleSquadState in controller.get_all_states():
			if state.alive and state.side == a.side and state.row_key == pair[0].row_key: used += state.squad_data.get_unit_count()
		if used - pair[0].squad_data.get_unit_count() + pair[1].squad_data.get_unit_count() > 21: return false
	return true

func swap(a: BattleSquadState, b: BattleSquadState) -> bool:
	if not legal_swap(a, b): return false
	var row := a.row_key
	var index := a.formation_index
	a.row_key = b.row_key
	a.formation_index = b.formation_index
	b.row_key = row
	b.formation_index = index
	controller.recalculate_logical_layout() # 已在布局重算末尾同步光环，避免每次换位执行两遍
	controller.formation_changed.emit()
	controller.states_changed.emit()
	return true

func swap_other_row(target: BattleSquadState) -> bool:
	var candidates: Array[BattleSquadState] = []
	var equal: Array[BattleSquadState] = []
	for other: BattleSquadState in controller.get_living_states(target.side):
		if other.row_key == target.row_key or not legal_swap(target, other): continue
		candidates.append(other)
		if other.squad_data.get_unit_count() == target.squad_data.get_unit_count(): equal.append(other)
	if not equal.is_empty(): candidates = equal
	return swap(target, candidates[controller._random.randi_range(0, candidates.size() - 1)]) if not candidates.is_empty() else false

func capture_layout() -> void:
	layout_snapshot.clear()
	for state: BattleSquadState in controller.get_all_states():
		if state.alive: layout_snapshot[state] = [state.row_key, state.logical_center]

func on_layout_changed() -> void:
	if controller.battle_instance_id.is_empty():
		capture_layout()
		return
	var sides: Dictionary = {}
	var knights: Array[BattleSquadState] = []
	for state: BattleSquadState in controller.get_all_states():
		if not state.alive or not layout_snapshot.has(state): continue
		var before: Array = layout_snapshot[state]
		if before[0] != state.row_key and active(state, &"twilight_knight"):
			knights.append(state)
		if before[0] != state.row_key or not is_equal_approx(float(before[1]), state.logical_center): sides[state.side] = true
	capture_layout()
	for knight: BattleSquadState in knights:
		controller._apply_emblem_rush_effects(knight)
		controller._apply_wound_rush_effects(knight)
		var rush: BattleRuntimeEvent = controller.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.RUSH, {"actor": knight, "retrigger_rush": true})
		# 只排空本次换排的突击链；同帧再换排前，先按当前排完整结算。
		controller.effect_runtime.process_due_for_root(controller.elapsed_seconds, rush.root_event_id)
	for side: int in sides:
		for listener: BattleSquadState in controller.get_all_states():
			var dancer := listener.side == side and active(listener, &"moon_dancer")
			var hawk := listener.side != side and active(listener, &"moon_hawk")
			if not dancer and not hawk: continue
			var owner := listener.squad_data.get_effect_source_instance()
			var id: StringName = owner.instance_id if owner != null else StringName(str(listener.runtime_id))
			if controller.elapsed_seconds - float(last_movement.get(id, -INF)) < MOVE_COOLDOWN - 0.000001: continue
			last_movement[id] = controller.elapsed_seconds
			if dancer: add(listener, BattleModifier.Stat.ACTION_VALUE, 1, &"moon_dancer_movement")
			else:
				var target := random_target(1 - listener.side)
				if target != null: controller.launch_content_effect(controller.twisted_vein.make_event(listener, target, 2, CardData.ActionType.MAGIC, false, "月鹰位移"))

func on_spell(spell: OwnedCard, side: int) -> void:
	if spell == null: return
	for weaver: BattleSquadState in controller.get_living_states(side):
		if not active(weaver, &"silvermoon_priest"): continue
		var pool := eligible(1 - side)
		if pool.size() < 2: continue
		var a: BattleSquadState = pool.pop_at(controller._random.randi_range(0, pool.size() - 1))
		var b: BattleSquadState = pool[controller._random.randi_range(0, pool.size() - 1)]
		links[weaver.runtime_id] = [a, b]

func on_action_launched(action: Dictionary) -> void:
	var event := action.get("base_event") as BattleEffectEvent
	if event == null or event.is_link_copy or not event.is_base_action or not event.is_damage(): return

	var target := action.get("target") as BattleSquadState
	if target == null: return
	var copies: Array[BattleSquadState] = []
	for id: int in links.keys():
		var pair: Array = links[id]
		if not pair[0].alive or not pair[1].alive or pair[0].is_banished or pair[1].is_banished:
			links.erase(id)
			continue
		if target == pair[0] or target == pair[1]:
			copies.append(pair[1] if target == pair[0] else pair[0])
			links.erase(id)
	for other: BattleSquadState in copies: controller.execute_linked_action(action, other)

func before_hit(event: BattleEffectEvent) -> bool:
	if event.target == null or event.target.is_banished: return true
	if not event.is_base_action or not event.is_damage() or event.source == null: return false
	if event.action_type == CardData.ActionType.RANGED and not event.dual_melee_ranged and active(event.target, &"night_cloak", true):
		var guaranteed: bool = controller.twisted_vein.has_lamp_aura(event.source)
		if not guaranteed and int(controller._roll_probability(event.target, 6).get("total", 0)) > 4: return true
	if controller.is_back_row(event.target.row_key):
		var guarded := false
		for guard: BattleSquadState in controller.get_living_states(event.target.side):
			if active(guard, &"twilight_guard") and controller.is_back_row(guard.row_key): guarded = true
		if guarded and not controller.twisted_vein.has_lamp_aura(event.source) and int(controller._roll_probability(event.target, 10).get("total", 0)) == 10:
			event.can_trigger_element_chain = false
			event.log_qualifier = "晨昏守卫：1d10=10，无效此次攻击"
			return true
	return false

func impact_bonus(event: BattleEffectEvent) -> void:
	if event.is_base_action and event.is_damage() and active(event.source, &"darkmoon_archer") and event.target.current_health < float(event.target.get_max_health()) * 0.5:
		event.formula.final_flat_bonus += 3.0
		event.formula.exact_result = event.formula.calculate_result()
		event.exact_amount = event.formula.exact_result

func on_hit(event: BattleEffectEvent) -> void:
	if event.missed or not event.is_base_action or event.target == null or event.source == null: return
	if active(event.source, &"star_chant_apprentice"):
		for adjacent: BattleSquadState in controller._get_adjacent_allies(event.target):
			if not adjacent.is_banished: controller.launch_content_effect(controller.twisted_vein.make_event(event.source, adjacent, 1, CardData.ActionType.MAGIC, true, "星咏学徒回响"))
	if event.is_damage() and event.source.side != event.target.side and active(event.target, &"twilight_guard", false, true) and not controller.is_back_row(event.target.row_key):
		if event.source.alive and not event.source.is_banished:
			var retaliation: BattleEffectEvent = controller.twisted_vein.make_event(event.target, event.source, 2, CardData.ActionType.MAGIC, false, "晨昏守卫反伤")
			retaliation.waits_for_death_chain = event.target.current_health <= 0.0
			controller.launch_content_effect(retaliation)

func _on_kill(killer: BattleSquadState, _victim: BattleSquadState, _event: BattleEffectEvent) -> void:
	if active(killer, &"shadowstep_assassin"): killer.grant_protection(&"shadowstep_assassin", 1)

func on_mining(event: BattleEffectEvent) -> void:
	if not active(event.source, &"moondew_collector"): return
	var pool: Array[BattleSquadState] = eligible(event.source.side).filter(func(s: BattleSquadState) -> bool: return not s.is_sleeping(controller.elapsed_seconds))
	var best := -INF
	for target: BattleSquadState in pool: best = maxf(best, target.get_display_action_value())
	pool = pool.filter(func(s: BattleSquadState) -> bool: return s.get_display_action_value() == best)
	var target: BattleSquadState = controller.choose_weighted_target(pool)
	if target != null: controller._charge_state(target, 0.5)

func harvest_moondew(event: BattleEffectEvent) -> void:
	for target: BattleSquadState in controller.get_living_states(event.resource_target.side):
		match controller._random.randi_range(0, 2):
			0: controller.twisted_vein.gain_health(target, 2, &"moondew")
			1: add(target, BattleModifier.Stat.ACTION_VALUE, 1, &"moondew")
			2: add(target, BattleModifier.Stat.ZEAL, 1, &"moondew")

func release_spell(spell: OwnedCard, side: int) -> bool:
	var key := spell.card_data.content_effect
	if not key in [&"solar_eclipse", &"moonfire", &"starlight_fragments", &"victory_prophecy", &"failure_prophecy"]: return false
	if not controller.notify_spell_triggered(spell.instance_id, 0): return true
	match key:
		&"victory_prophecy", &"failure_prophecy": prophecies.append({"spell": spell, "side": side, "key": key})
		&"solar_eclipse":
			for state: BattleSquadState in controller.get_all_states():
				if not state.alive or state.is_banished: continue
				for slot: Dictionary in state.get_active_rune_slots():
					if int(slot.get("element", -1)) != CardData.ElementType.LIGHT: continue
					state.runtime_rune_overrides[state._rune_slot_key(slot.card, int(slot.rune_index))] = CardData.ElementType.DARK
					spell_damage(side, 1, random_target(1 - side), "日蚀")
		&"moonfire":
			var targets := eligible(1 - side)
			var highest := 0.0
			for target: BattleSquadState in targets: highest = maxf(highest, target.current_health)
			targets = targets.filter(func(s: BattleSquadState) -> bool: return is_equal_approx(s.current_health, highest))
			spell_damage(side, 6, controller.choose_weighted_target(targets), "月火术")
		&"starlight_fragments":
			var targets: Array[BattleSquadState] = controller.get_living_states(1 - side)
			var lowest := 100
			for target: BattleSquadState in targets: lowest = mini(lowest, target.get_target_weight())
			targets = targets.filter(func(s: BattleSquadState) -> bool: return s.get_target_weight() == lowest)
			if not targets.is_empty():
				var target: BattleSquadState = targets[controller._random.randi_range(0, targets.size() - 1)]
				controller._clear_emblem_shadows_for_state(target)
				target.moon_shadowed = false
				target.moon_restore_time = INF
				add(target, BattleModifier.Stat.TARGET_PRIORITY, 5, key)
				spell_damage(side, 2, target, "星芒碎屑")
	return true

func spell_damage(_side: int, amount: float, target: BattleSquadState, label: String) -> void:
	if target != null: controller.launch_content_effect(controller.twisted_vein.make_event(null, target, amount, CardData.ActionType.MAGIC, true, label))

func trigger(spell: OwnedCard) -> bool:
	var count := int(spell_counts.get(spell.instance_id, 0))
	if not controller.notify_spell_triggered(spell.instance_id, count): return false
	spell_counts[spell.instance_id] = count + 1
	controller._present_nonpausing_spell(spell)
	return true

func release_prepared_spell(spell: OwnedCard, side: int) -> bool:
	match spell.card_data.content_effect:
		&"starfire":
			# 只有首次释放参加准备队列，后续周期从首次准备完成时开始。
			periodic_spells[spell.instance_id] = controller.elapsed_seconds + STARFIRE_PERIOD
			var target := random_target(1 - side)
			if target != null and trigger(spell): spell_damage(side, 1, target, "星火术")
		&"nightfall":
			used_spells[spell.instance_id] = true
			if controller.elapsed_seconds < controller.fatigue_start_seconds and trigger(spell):
				controller.fatigue_start_seconds = maxf(controller.elapsed_seconds, controller.fatigue_start_seconds - NIGHTFALL_ADVANCE_SECONDS)
				controller._next_fatigue_damage_seconds = minf(controller._next_fatigue_damage_seconds, controller.fatigue_start_seconds)
		_:
			return false
	return true

func check_health_spells() -> void:
	for spell: OwnedCard in controller._get_all_prepared_spell_instances():
		if used_spells.has(spell.instance_id): continue
		var key := spell.card_data.content_effect
		if not key in [&"moon_tears", &"silvermoon_breath"]: continue
		var side: int = controller._spell_side_by_instance.get(spell.instance_id, 0)
		var pool: Array[BattleSquadState] = controller.get_living_states(side)
		var hp := 0.0
		var maximum := 0.0
		for target: BattleSquadState in pool:
			hp += maxf(target.current_health, 0)
			maximum += target.get_max_health()
		if maximum <= 0.0 or hp >= maximum * 0.5: continue
		used_spells[spell.instance_id] = true
		if not trigger(spell): continue
		if key == &"moon_tears":
			while controller.spawn_content_resource(load("res://resources/cards/moondew.tres"), side) != null: pass
		else:
			for target: BattleSquadState in pool:
				var event: BattleEffectEvent = controller.twisted_vein.make_event(null, target, 4, CardData.ActionType.HEAL, false, "银月之息")
				event.effect_kind = BattleEffectEvent.EffectKind.HEALING
				controller.launch_content_effect(event, false)

func prelethal(event: BattleEffectEvent) -> bool:
	var target := event.target
	if target == null or not target.alive or target.is_banished: return false
	var health_damage := event.exact_amount if event.pierces_armor else maxf(event.exact_amount - target.current_armor, 0)
	if health_damage < target.current_health or target.current_health <= 0.0: return false
	for spell: OwnedCard in controller._get_all_prepared_spell_instances():
		if int(controller._spell_side_by_instance.get(spell.instance_id, 0)) != target.side: continue
		var key := spell.card_data.content_effect
		if key == &"moonshadow" and not shadow_beneficiaries.has(target):
			shadow_beneficiaries[target] = true
			if trigger(spell):
				controller.lethal_response_depth += 1
				controller.execute_immediate_action(target, target.get_effective_action_type(), 0, {}, false, {"native_only": true})
				controller.preserve_source_projectiles_for_death_chain(target)
				controller.lethal_response_depth -= 1
		elif key == &"twilight_veil" and not used_spells.has(spell.instance_id):
			used_spells[spell.instance_id] = true
			if trigger(spell):
				target.is_banished = true
				banishments[target] = controller.elapsed_seconds + VEIL_SECONDS
				sync_auras()
				controller.effect_runtime.recheck_continuous_conditions()
				controller.effect_runtime.process_due(controller.elapsed_seconds)
				return true
	return false

func fatigue_multiplier(target: BattleSquadState) -> float:
	return 0.5 if active(target, &"twilight_elemental") and controller.is_back_row(target.row_key) else 1.0

func next_delay(now: float) -> float:
	var result := INF
	for until: float in banishments.values(): result = minf(result, maxf(until - now, 0))
	for spell: OwnedCard in controller._get_all_prepared_spell_instances():
		if periodic_spells.has(spell.instance_id): result = minf(result, maxf(float(periodic_spells[spell.instance_id]) - now, 0))
	if now < ELEMENT_OPENING_SECONDS and controller.get_all_states().any(func(s: BattleSquadState) -> bool: return active(s, &"twilight_elemental")): result = minf(result, ELEMENT_OPENING_SECONDS - now)
	if not extra_actions.is_empty(): result = 0.0
	return result

func advance_paused_timers(delta: float) -> void:
	for state: BattleSquadState in banishments:
		for scheduled: BattleRuntimeEvent in controller.effect_runtime.queue._events:
			if scheduled.kind == BattleRuntimeEvent.Kind.EXPIRE and scheduled.effect_instance != null and scheduled.effect_instance.source.state == state:
				scheduled.logical_time_us += roundi(delta * 1000000.0)
				scheduled.effect_instance.expires_at_us = scheduled.logical_time_us
		for key: Variant in state.sleep_source_until: state.sleep_source_until[key] += delta
		if is_finite(state.moon_restore_time): state.moon_restore_time += delta
		if controller._minimum_health_until.has(state): controller._minimum_health_until[state] += delta
		for status: Dictionary in controller.active_continuous_effects:
			if status.get("target") == state: status.next_time += delta
		for status: Dictionary in controller._wound_periodic_effects:
			if status.get("state") == state: status.next_time += delta
	controller.effect_runtime.queue._events.sort_custom(BattleRuntimeEvent.is_before)

func process_due() -> void:
	for state: BattleSquadState in banishments.keys():
		if float(banishments[state]) <= controller.elapsed_seconds + 0.0001:
			banishments.erase(state)
			state.is_banished = false
			state.apply_healing_exact(float(state.get_max_health()) * 0.3)
			controller.effect_runtime.recheck_continuous_conditions()
	sync_auras()
	for spell: OwnedCard in controller._get_all_prepared_spell_instances():
		var key := spell.card_data.content_effect
		var side: int = controller._spell_side_by_instance.get(spell.instance_id, 0)
		if key == &"starfire" and periodic_spells.has(spell.instance_id) and controller.elapsed_seconds + 0.0001 >= float(periodic_spells[spell.instance_id]):
			periodic_spells[spell.instance_id] = float(periodic_spells[spell.instance_id]) + STARFIRE_PERIOD
			var target := random_target(1 - side)
			if target != null and trigger(spell): spell_damage(side, 1, target, "星火术")
	check_health_spells()
	var queued := extra_actions.duplicate()
	extra_actions.clear()
	for actor: BattleSquadState in queued:
		if actor.alive and not actor.is_banished: controller.execute_immediate_action(actor, actor.get_effective_action_type(), 0, {}, false, {"silvermoon_repeat": true})

func finish(result: int) -> void:
	for prophecy: Dictionary in prophecies:
		var won: bool = (result in [1, 3]) == (prophecy.side == 0)
		if (prophecy.key == &"victory_prophecy") != won: continue
		var pool: Array[BattleSquadState] = controller.get_all_states().filter(func(s: BattleSquadState) -> bool: return s.side == prophecy.side)
		if pool.is_empty(): continue
		controller.record_pending_run_reward(BattleEffectOwnerRef.for_state(pool[0], BattleEffectDefinition.OwnerKind.OWNING_PLAYER), BattleRunRewardLedger.KIND_GOLD, 3 if won else 1, prophecy.key, pool[0].runtime_id, roundi(controller.elapsed_seconds * 1000000.0))
	prophecies.clear()
	cleanup()

func cleanup() -> void:
	if is_instance_valid(controller) and controller.kill_resolved.is_connected(_on_kill): controller.kill_resolved.disconnect(_on_kill)
	# 清理反向引用，避免 RefCounted 通过状态与控制器形成保留环。
	links.clear()
	extra_actions.clear()
	pending_seed_actions.clear()


func on_action_complete(action: Dictionary) -> void:
	var event := action.get("base_event") as BattleEffectEvent
	var actor := action.get("actor") as BattleSquadState
	if event == null or event.is_link_copy or event.is_silvermoon_repeat or event.suppresses_echo: return
	if active(actor, &"moonshadow_seed", true) and controller.elapsed_seconds >= controller.fatigue_start_seconds: extra_actions.append(actor)

func on_projectile_batch_complete(batch_id: int) -> void:
	var actions: Array = pending_seed_actions.get(batch_id, [])
	pending_seed_actions.erase(batch_id)
	for action: Dictionary in actions: on_action_complete(action)
