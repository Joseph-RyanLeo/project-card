extends RefCounted

## 任务卡牌的实际效果；本场变形结果由Main接入现有结算事务，不直接写磁盘。
const ECHO_REQUIRED := 10 # 熄灭青灯转换为摇曳青灯所需回响次数
const WISH_REQUIRED := 4 # 摇曳青灯转换为炽烈青灯所需遗愿次数
const LANTERN_PROGRESS := &"task_lantern_triggers"
var _controller: WeakRef
var equipment_results: Dictionary = {}
var ally_deaths: int
var gallery_equipment_count: int
var _counted_deaths: Dictionary = {}
var _seen_rushes: Dictionary = {}
var _repeated_rush_bindings: Dictionary = {}


func initialize(controller: Node, previous_deaths: int, discovered_equipment: int = 0) -> void:
	_controller = weakref(controller)
	ally_deaths = previous_deaths
	gallery_equipment_count = discovered_equipment


func on_rush_applied(event: BattleRuntimeEvent, listeners: Array[BattleEffectOwnerRef], neighbors: Array[BattleSquadState]) -> void:
	var c = _controller.get_ref()
	var actor := event.source.state
	if c == null or actor == null: return
	var group := String(event.definition.effect_group)
	if group.is_empty(): group = String(event.definition.effect_id)
	var is_repeat := bool(event.payload.get("seraphina_repeat", false))
	var key := "%d:%s:%s:%d" % [event.root_event_id, event.source.stable_key(), group, int(is_repeat)]
	if not _seen_rushes.has(key):
		_seen_rushes[key] = true
		_add_rush_progress(listeners, event.logical_time_us)
	if is_repeat: return
	var binding_id := int(event.payload.get("rush_binding_id", 0))
	var repeat_key := "%d:%d" % [event.root_event_id, binding_id]
	if binding_id <= 0 or _repeated_rush_bindings.has(repeat_key) or not _has_completed_neighbor(listeners, neighbors): return
	_repeated_rush_bindings[repeat_key] = true
	var repeat: BattleRuntimeEvent = c.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.RUSH, {"actor": actor, "binding_id": binding_id, "retrigger_rush": true, "seraphina_repeat": true}, event)
	# 第二次执行沿用原事件链，只解除原突击的同名递归拦截。
	repeat.tags.erase(StringName("effect:%s" % event.definition.effect_id))


func rush_listeners(actor: BattleSquadState) -> Array[BattleEffectOwnerRef]:
	var listeners: Array[BattleEffectOwnerRef] = []
	var c = _controller.get_ref()
	if c == null: return listeners
	for state: BattleSquadState in c.get_living_states(actor.side):
		if not c.twisted_vein.active(state, &"seraphina_starsinger"): continue
		var card := state.squad_data.get_effect_source_instance()
		if card != null: listeners.append(BattleEffectOwnerRef.for_owned_card_in_state(state, card))
	return listeners


func observe_rush(actor: BattleSquadState, at: int) -> void:
	_add_rush_progress(rush_listeners(actor), at)


func _add_rush_progress(listeners: Array[BattleEffectOwnerRef], at: int) -> void:
	var c = _controller.get_ref()
	if c == null: return
	for owner: BattleEffectOwnerRef in listeners:
		var card := owner.owned_card
		var progress := int(card.progress_by_source.get(OwnedCard.SERAPHINA_PROGRESS, 0))
		if progress >= OwnedCard.SERAPHINA_REQUIRED: continue
		if owner.state.side == BattleSquadState.Side.PLAYER and not owner.state.battle_summoned:
			if not c.owned_card_change_ledger.record_progress_value(owner, OwnedCard.SERAPHINA_PROGRESS, progress + 1, &"seraphina_starsinger", c.battle_instance_id, at, true): continue
		card.progress_by_source[OwnedCard.SERAPHINA_PROGRESS] = progress + 1


func doubles_rush(actor: BattleSquadState) -> bool:
	var c = _controller.get_ref()
	if c == null: return false
	return _has_completed_neighbor(rush_listeners(actor), c._get_adjacent_allies(actor))


func _has_completed_neighbor(listeners: Array[BattleEffectOwnerRef], neighbors: Array[BattleSquadState]) -> bool:
	for owner: BattleEffectOwnerRef in listeners:
		if owner.state in neighbors and int(owner.owned_card.progress_by_source.get(OwnedCard.SERAPHINA_PROGRESS, 0)) >= OwnedCard.SERAPHINA_REQUIRED:
			return true
	return false


func on_defeated(state: BattleSquadState) -> void:
	if state.side == BattleSquadState.Side.PLAYER and not _counted_deaths.has(state.runtime_id):
		_counted_deaths[state.runtime_id] = true
		ally_deaths += 1


func execute_trigger(state: BattleSquadState, key: StringName, trigger: int) -> bool:
	var c = _controller.get_ref()
	if c == null or state == null: return false
	var dead := trigger == BattleEffectDefinition.Trigger.LAST_WISH
	if key == &"sargon_harmonizer":
		return trigger == BattleEffectDefinition.Trigger.ECHO and c.gilded != null and c.gilded.sargon_echo(state)
	if key in [&"mogris_old_oak", &"nyx_contract_demon"]:
		return trigger == BattleEffectDefinition.Trigger.RUSH and c.gilded != null and c.gilded.rush(state, key)
	if key == &"balin_helmet":
		return trigger == BattleEffectDefinition.Trigger.RUSH and c.gilded != null and c.gilded.helmet_rush(state)
	if key in [&"gravekeepers_notes", &"insect_blade"]:
		return c.gilded != null and c.gilded.equipment_trigger(state, key, dead)
	if key == &"hild_allrounder":
		if trigger != BattleEffectDefinition.Trigger.RUSH or not c.twisted_vein.active(state, key): return false
		for ally: BattleSquadState in c.get_living_states(state.side):
			if ally.current_health <= 0.0: continue
			var pattern := ally.get_rune_pattern_result()
			var elements := {}
			for index: int in pattern.participating_indices:
				elements[pattern.visible_runes[index]] = true
			if elements.size() < 2: continue
			var bonus := elements.size() if pattern.pattern_type == RunePatternResult.PatternType.STRAIGHT else mini(elements.size(), 2)
			c.ironwall.add(ally, BattleModifier.Stat.ACTION_VALUE, bonus, key, state)
			var previous_max := ally.get_max_health()
			c.ironwall.add(ally, BattleModifier.Stat.MAX_HEALTH, bonus, key, state)
			ally.apply_max_health_increase(previous_max, bonus)
		return true
	if key == &"balin_ashslag":
		if not dead or not c.twisted_vein.active(state, key, false, true): return false
		_resolve_balin_wish(state)
		return true
	if key == &"edwin_ash":
		if trigger != BattleEffectDefinition.Trigger.RUSH or not c.twisted_vein.active(state, key): return false
		for ally: BattleSquadState in c._get_adjacent_allies(state):
			if not ally.alive or ally.current_health <= 0.0 or ally.is_banished: continue
			# 消灭仍触发遗愿；只替换本次新增伤势的结果，不绕过死亡流程。
			c._death_wound_checked[ally.runtime_id] = true
			var owner := BattleEffectOwnerRef.for_state(state, BattleEffectDefinition.OwnerKind.MINION_CARD_INSTANCE)
			c._record_resource_wound_heal(ally, owner, &"edwin_ash", roundi(c.elapsed_seconds * 1000000.0))
			c.ironwall.grant_permanent_emblem(ally)
			ally.current_health = 0.0
			ally.pending_kill_source = state
		c._finalize_batch()
		return true
	var item := state.squad_data.get_equipped_item()
	if item == null or not c.twisted_vein.active(state, item.card_data.content_effect, true, dead): return false
	match item.card_data.id:
		&"extinguished_lantern":
			if trigger != BattleEffectDefinition.Trigger.ECHO: return false
			var events: Array[BattleEffectEvent] = []
			for target: BattleSquadState in c.get_all_states():
				if target.alive and target.current_health > 0.0 and not target.is_banished:
					events.append(c.twisted_vein.make_event(state, target, 1, CardData.ActionType.MAGIC, false, "熄灭青灯回响"))
			c.resolve_content_batch(events)
			_advance(state, item, ECHO_REQUIRED, &"flickering_lantern")
		&"flickering_lantern":
			if not dead: return false
			for ally: BattleSquadState in c.get_death_neighbors(state):
				var owner := BattleEffectOwnerRef.for_state(ally, BattleEffectDefinition.OwnerKind.ARMOR_PROVIDER_CARD)
				if c.record_pending_permanent_growth(owner, OwnedCard.STAT_BONUS_MAX_HEALTH, 2.0, &"flickering_lantern", state.runtime_id, roundi(c.elapsed_seconds * 1000000.0)):
					c.twisted_vein.gain_health(ally, 2.0, &"flickering_lantern")
			_advance(state, item, WISH_REQUIRED, &"blazing_lantern")
		&"blazing_lantern":
			if not dead: return false
			# 每点伤害独立分配，沿用当前存活敌军和既有伤害／弹道结算。
			var amount: int = ally_deaths if state.side == BattleSquadState.Side.PLAYER else c._death_history.filter(func(entry: Dictionary): return entry.state.side == state.side).size()
			for index: int in amount:
				var targets: Array = c.get_living_states(1 - state.side)
				if targets.is_empty(): break
				c.ironwall.independent_damage(state, targets[c._random.randi_range(0, targets.size() - 1)], 1, CardData.ActionType.MAGIC, false, "炽烈青灯遗愿")
		_:
			return false
	return true


func _resolve_balin_wish(state: BattleSquadState) -> void:
	var c = _controller.get_ref()
	if state.side != BattleSquadState.Side.PLAYER or gallery_equipment_count < 2: return
	var card_owner := BattleEffectOwnerRef.for_state(state, BattleEffectDefinition.OwnerKind.MINION_CARD_INSTANCE)
	var player := BattleEffectOwnerRef.for_state(state, BattleEffectDefinition.OwnerKind.OWNING_PLAYER)
	var at := roundi(c.elapsed_seconds * 1000000.0)
	var gold := 0
	var growth := {OwnedCard.STAT_MAX_HEALTH: 0, OwnedCard.STAT_BASE_VALUE: 0}
	var shop: OrdinaryShopService
	for _index: int in floori(gallery_equipment_count / 2.0):
		var roll := int(c._roll_probability(state, 20).total)
		if roll > 5: gold += 1
		if roll > 10: growth[OwnedCard.STAT_MAX_HEALTH] += 1
		if roll > 15: growth[OwnedCard.STAT_BASE_VALUE] += 1
		if roll != 20: continue
		c._record_resource_wound_heal(state, card_owner, &"balin_ashslag", at)
		if shop == null:
			shop = OrdinaryShopService.new()
			shop.load_config()
		var pool := EmblemLibraryData.get_definitions().filter(func(item: Dictionary) -> bool:
			return not item.get("event_only", false) and item.get("target", "emblem") != "rune" and int(item.get("rarity", -1)) in [CardData.Rarity.I, CardData.Rarity.II, CardData.Rarity.III])
		var emblem := shop._draw_sticker(pool, c._random)
		if emblem.is_empty(): continue
		var id := "%s:balin:%d:%d" % [c.battle_instance_id, state.runtime_id, c.run_reward_ledger.get_entries().size()]
		c.record_pending_run_reward(player, BattleRunRewardLedger.KIND_RANDOM_EMBLEM_INSTANCE, 1, &"balin_ashslag", state.runtime_id, at, {"emblem_id": emblem.id, "emblem_instance_id": id, "source": "balin_ashslag"})
	if gold > 0: c.record_pending_run_reward(player, BattleRunRewardLedger.KIND_GOLD, gold, &"balin_ashslag", state.runtime_id, at)
	if card_owner.owned_card == null: return
	for stat: StringName in growth:
		if growth[stat] > 0 and c.record_pending_permanent_growth(card_owner, stat, growth[stat], &"balin_ashslag", state.runtime_id, at):
			card_owner.owned_card.apply_permanent_growth(stat, growth[stat])


func _advance(state: BattleSquadState, item: OwnedCard, threshold: int, next_id: StringName) -> void:
	var c = _controller.get_ref()
	var count := int(item.progress_by_source.get(LANTERN_PROGRESS, 0)) + 1
	item.progress_by_source[LANTERN_PROGRESS] = count
	if count >= threshold:
		var previous_armor := item.card_data.equipment_armor_delta
		item.card_data = load("res://resources/cards/%s.tres" % next_id)
		item._battlefield_card = null
		item.progress_by_source[LANTERN_PROGRESS] = 0
		if state.alive: state.apply_armor_exact(maxi(item.card_data.equipment_armor_delta - previous_armor, 0))
		state.refresh_cooldown_after_modifier_change()
	if state.side == BattleSquadState.Side.PLAYER:
		equipment_results[String(item.instance_id)] = {"card_id": String(item.card_data.id), "progress": item.progress_by_source.duplicate(true)}


func commit_to_collection(collection: OwnedCardCollection) -> bool:
	for id: String in equipment_results:
		var owned := collection.get_by_instance_id(StringName(id))
		if owned == null: continue # 本场已被明确消耗／移出的装备不会重新生成。
		var result: Dictionary = equipment_results[id]
		var snapshot := owned.capture_state()
		snapshot.card_data = load("res://resources/cards/%s.tres" % result.card_id)
		snapshot.progress_by_source = result.progress.duplicate(true)
		if not owned.restore_state(snapshot): return false
		owned._battlefield_card = null
	return true
