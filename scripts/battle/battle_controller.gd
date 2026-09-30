class_name BattleController
extends Node

## 敌我双方共用的自动战斗时间轴与分层批次协调器。
## 目标先按逻辑层统一选完，再执行该层全部效果，场景节点不参与规则判断。

const BattleSquadState = preload("res://scripts/battle/battle_squad_state.gd")
const BattleResourceStateScript = preload("res://scripts/battle/battle_resource_state.gd")
const BattleEffectEvent = preload("res://scripts/battle/battle_effect_event.gd")
const BattleFormulaData = preload("res://scripts/battle/battle_formula_data.gd")
const BattleElementResolver = preload("res://scripts/battle/battle_element_resolver.gd")
const BattleAttackEffectProfiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
const BattleProjectileTiming = preload("res://scripts/battle/battle_projectile_timing.gd")
const BattleEffectRuntime = preload("res://scripts/battle/effects/battle_effect_runtime.gd")
const BattleEffectCatalog = preload("res://scripts/battle/effects/battle_effect_catalog.gd")
const BattlePermanentGrowthLedger = preload("res://scripts/battle/battle_permanent_growth_ledger.gd")
const BattleRunRewardLedger = preload("res://scripts/battle/battle_run_reward_ledger.gd")
const BattleOwnedCardChangeLedger = preload("res://scripts/battle/battle_owned_card_change_ledger.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const EmblemLibraryData = preload("res://scripts/data/emblem_library_data.gd")
const CardPackRegistryScript = preload("res://scripts/data/card_pack_registry.gd")

const EFFECT_DATA_PATH: String = "res://data/demo2/ash_ledger_effect_samples.json"

signal states_changed
signal action_resolved(actor: BattleSquadState, target: BattleSquadState, action_type: CardData.ActionType, amount: int)
signal projectile_launched(event: BattleEffectEvent)
signal effect_resolved(event: BattleEffectEvent)
signal integer_settlement_resolved(event: Dictionary)
signal kill_resolved(killer: BattleSquadState, target: BattleSquadState, event: BattleEffectEvent)
signal squad_defeated(state: BattleSquadState)
signal squad_revived(state: BattleSquadState)
signal buff_stacks_changed(state: BattleSquadState, buff_id: StringName, stacks: int)
signal direct_damage_resolved(state: BattleSquadState, source_id: StringName, amount: int)
signal effect_trace_emitted(entry: BattleEffectTraceEntry)
signal special_effect_resolved(record: Dictionary)
signal permanent_growth_recorded(entry: Dictionary)
signal pending_run_reward_recorded(entry: Dictionary)
signal pending_owned_card_change_recorded(entry: Dictionary)
signal battle_initialized
signal battle_finished(result: Result)
signal indicator_transferred(indicator: CelestialIndicator, source: BattleSquadState, target: BattleSquadState)
signal spell_cast_started(spell: OwnedCard, battle_generation: int, presentation_seconds: float)
signal spell_cast_finished(spell_instance_id: StringName, battle_generation: int)
signal opening_spell_phase_finished(battle_generation: int)

enum Result { NONE, PLAYER_VICTORY, PLAYER_DEFEAT, DRAW }

const COOLDOWN_EPSILON: float = 0.0001 # 同一时间点冷却完成的浮点判断容差（秒）
const OPENING_SPELL_PRESENTATION_SECONDS: float = 0.55 # 开场法术卡面放大与收回的视觉默认时长
const SPELL_MINIMUM_HEALTH_SECONDS: float = 5.0 # 战斗怒火保护持续时间，按确认规则计入战斗时钟

var player_states: Array[BattleSquadState] = []
var enemy_states: Array[BattleSquadState] = []
var player_resource_states: Array[RefCounted] = []
var enemy_resource_states: Array[RefCounted] = []
var _reward_card_catalog: Array[CardData] = []
var _player_owned_card_ids: Dictionary = {}
var mining_actions_remaining_by_runtime_id: Dictionary = {} # 每个小队由自己的有效效果来源和装备提供本场开采次数
var current_result: Result = Result.NONE
var elapsed_seconds: float = 0.0
var batch_count: int = 0
var battle_speed_multiplier: float = 1.0
var performance_trace_enabled: bool = false
var performance_trace_advance_total_usec: int = 0
var use_projectile_timing: bool = false
var active_continuous_effects: Array[Dictionary] = []
var _wound_periodic_effects: Array[Dictionary] = []
var battle_seed: int = 0
var battle_instance_id: StringName = &"" # 一次战前快照对应的稳定身份；战后账本与防重复提交共用
var effect_runtime := BattleEffectRuntime.new()
var effect_catalog: BattleEffectCatalog
var permanent_growth_ledger := BattlePermanentGrowthLedger.new()
var run_reward_ledger := BattleRunRewardLedger.new()
var owned_card_change_ledger := BattleOwnedCardChangeLedger.new()

var _random := RandomNumberGenerator.new()
var _running: bool = false
var _next_fatigue_stack_seconds: float = BattleRules.FATIGUE_START_SECONDS
var _next_fatigue_damage_seconds: float = BattleRules.FATIGUE_START_SECONDS
var _next_group_id: int = 1
var _continuous_followups: Dictionary = {}
var _pending_projectile_contexts: Dictionary = {}
var _pending_projectile_batch_counts: Dictionary = {}
var _next_projectile_batch_id: int = 1
var _next_projectile_launch_sequence: int = 1
var _next_state_runtime_id: int = 1
var _next_local_battle_sequence: int = 1
var _chaos_reward_records: Dictionary = {}
var _emblem_registrations: Array[Dictionary] = [] # 本场可见纹章实例；每条保留OwnedCard与纹章instance_id
var _wound_registrations: Array[Dictionary] = [] # 本场可见触发型伤势实例；每条保留OwnedCard与槽位身份
var _fracture_participation: Array[Dictionary] = [] # 开战时显现且未遮蔽的玩家骨折伤势，阵亡仍计入本场次数
var _temporary_wound_slot_mutations: Array[Dictionary] = [] # 尸毒遗愿产生的槽位升级/新伤势，仅在当前战斗保留
var _next_emblem_keyword_source_id: int = 1
var _next_reward_instance_sequence: int = 1
var _processed_gold_reward_entry_ids: Dictionary = {}
var _processed_spell_event_ids: Dictionary = {}
var _next_probability_roll_sequence: int = 1
var _prepared_spell_instances: Array[OwnedCard] = []
var _enemy_prepared_spell_instances: Array[OwnedCard] = []
var _spell_side_by_instance: Dictionary = {}
var _opening_spell_queue: Array[Dictionary] = []
var _opening_spell_index: int = 0
var _opening_spell_elapsed: float = 0.0
var _opening_spell_presentation_done: bool = true
var _opening_spell_effect_done: bool = true
var _opening_spell_active: bool = false
var _battle_generation: int = 0
var _elapsed_spell_attempted: Dictionary = {} # 按法术实例记录已消耗的准备时刻机会
var _minimum_health_until: Dictionary = {}
var _side_by_side_grants: Array[Dictionary] = []
var _next_spell_modifier_source_id: int = -10000000
var _death_sequence: int = 0
var _death_history: Array[Dictionary] = []


func _ready() -> void:
	effect_catalog = BattleEffectCatalog.load_from_file(EFFECT_DATA_PATH)
	set_process(false)


func _process(delta: float) -> void:
	advance_time(delta * battle_speed_multiplier)


func start_battle(
	player_formation: Array[Dictionary],
	enemy_formation: Array[Dictionary],
	random_seed: int = -1,
	auto_run: bool = true,
	requested_battle_instance_id: StringName = &"",
	prepared_spell_instances: Array[OwnedCard] = [],
	enemy_prepared_spell_instances: Array[OwnedCard] = [],
	player_resources: Array[OwnedCard] = [],
	enemy_resources: Array[OwnedCard] = [],
	reward_card_catalog: Array[CardData] = [],
	player_owned_cards: Array[OwnedCard] = []
) -> void:
	battle_instance_id = _resolve_battle_instance_id(requested_battle_instance_id)
	_battle_generation += 1
	_initialize_battle_state(player_formation, enemy_formation, random_seed)
	_initialize_resource_states(player_resources, enemy_resources)
	_reward_card_catalog.assign(reward_card_catalog)
	_player_owned_card_ids.clear()
	for owned: OwnedCard in player_owned_cards:
		if owned != null and owned.card_data != null:
			_player_owned_card_ids[owned.card_data.id] = true
	mining_actions_remaining_by_runtime_id = _count_mining_actions()
	_prepared_spell_instances.assign(prepared_spell_instances)
	_enemy_prepared_spell_instances.assign(enemy_prepared_spell_instances)
	_spell_side_by_instance.clear()
	for spell: OwnedCard in _prepared_spell_instances:
		if spell != null:
			_spell_side_by_instance[spell.instance_id] = BattleSquadState.Side.PLAYER
	for spell: OwnedCard in _enemy_prepared_spell_instances:
		if spell != null:
			_spell_side_by_instance[spell.instance_id] = BattleSquadState.Side.ENEMY
	battle_initialized.emit()
	_begin_opening_spell_phase(auto_run)
	if _opening_spell_active:
		return
	_finish_opening_spell_phase(auto_run)


func _finish_opening_spell_phase(auto_run: bool) -> void:
	# 先放入战前已获强化，再结算突击窗口；突击内的即时行动会正常读取并消费这批强化。
	_apply_visible_fire_rune_reinforcement()
	_apply_emblem_rush_effects()
	_apply_wound_rush_effects()
	if not effect_runtime.bindings.is_empty():
		var continuous_event := effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.CONTINUOUS)
		# 排空持续触发及其子事件后再排突击；同一时刻其他独立事件保留在队列中。
		effect_runtime.process_due_for_root(elapsed_seconds, continuous_event.root_event_id)
		effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.RUSH)
		effect_runtime.process_due(elapsed_seconds)
	_running = true
	recalculate_logical_layout()
	set_process(auto_run)
	states_changed.emit()
	_check_battle_result()
	opening_spell_phase_finished.emit(_battle_generation)


func _begin_opening_spell_phase(auto_run: bool) -> void:
	_opening_spell_queue.clear()
	var player_spells := _get_opening_spells(_prepared_spell_instances)
	var enemy_spells := _get_opening_spells(_enemy_prepared_spell_instances)
	for index: int in maxi(player_spells.size(), enemy_spells.size()):
		if index < player_spells.size():
			_opening_spell_queue.append({"spell": player_spells[index], "side": BattleSquadState.Side.PLAYER})
		if index < enemy_spells.size():
			_opening_spell_queue.append({"spell": enemy_spells[index], "side": BattleSquadState.Side.ENEMY})
	_opening_spell_index = 0
	_opening_spell_active = not _opening_spell_queue.is_empty()
	if not _opening_spell_active:
		return
	_running = false
	set_process(auto_run)
	_start_next_opening_spell()


func _get_opening_spells(spells: Array[OwnedCard]) -> Array[OwnedCard]:
	var result: Array[OwnedCard] = []
	for spell: OwnedCard in spells:
		if (
			spell != null
			and spell.card_data != null
			and spell.card_data.spell_trigger_kind == CardData.SpellTriggerKind.INSTANT
		):
			result.append(spell)
	return result


func _start_next_opening_spell() -> void:
	if _opening_spell_index >= _opening_spell_queue.size():
		_opening_spell_active = false
		return
	var entry := _opening_spell_queue[_opening_spell_index]
	var spell := entry.get("spell") as OwnedCard
	_opening_spell_elapsed = 0.0
	_opening_spell_effect_done = false
	_opening_spell_presentation_done = (
		spell_cast_started.get_connections().is_empty()
		or DisplayServer.get_name() == "headless"
	)
	spell_cast_started.emit(
		spell,
		_battle_generation,
		OPENING_SPELL_PRESENTATION_SECONDS
	)
	_opening_spell_effect_done = _resolve_opening_spell(spell, int(entry.get("side", BattleSquadState.Side.PLAYER)))
	if not _opening_spell_effect_done:
		# 无合法友军时该次不触发，保持严格规则：不会在开场阶段重试。
		_opening_spell_effect_done = true


func notify_spell_presentation_finished(
	spell_instance_id: StringName,
	battle_generation: int
) -> bool:
	if (
		not _opening_spell_active
		or battle_generation != _battle_generation
		or _opening_spell_index >= _opening_spell_queue.size()
		or (_opening_spell_queue[_opening_spell_index].get("spell") as OwnedCard).instance_id != spell_instance_id
	):
		return false
	_opening_spell_presentation_done = true
	return true


func _advance_opening_spell_phase(delta: float) -> float:
	var time_left := maxf(delta, 0.0)
	while _opening_spell_active and time_left > COOLDOWN_EPSILON:
		var remaining := maxf(OPENING_SPELL_PRESENTATION_SECONDS - _opening_spell_elapsed, 0.0)
		var used := minf(remaining, time_left)
		_opening_spell_elapsed += used
		time_left -= used
		if (
			_opening_spell_elapsed + COOLDOWN_EPSILON < OPENING_SPELL_PRESENTATION_SECONDS
			or not _opening_spell_presentation_done
			or not _opening_spell_effect_done
		):
			return 0.0
		var finished_spell := _opening_spell_queue[_opening_spell_index].get("spell") as OwnedCard
		spell_cast_finished.emit(finished_spell.instance_id, _battle_generation)
		_opening_spell_index += 1
		_start_next_opening_spell()
	if not _opening_spell_active:
		var was_processing := is_processing()
		_finish_opening_spell_phase(was_processing)
		return 0.0
	return 0.0


func prepare_battle_preview(player_formation: Array[Dictionary], enemy_formation: Array[Dictionary], random_seed: int = -1) -> void:
	## 只建立站位并结算持续光环；不会触发突击、推进时间或产生战斗结果。
	battle_instance_id = &""
	_initialize_battle_state(player_formation, enemy_formation, random_seed)
	if not effect_runtime.bindings.is_empty():
		effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.CONTINUOUS)
		effect_runtime.process_due(elapsed_seconds)
	stop_battle()
	recalculate_logical_layout()
	states_changed.emit()


func _initialize_battle_state(player_formation: Array[Dictionary], enemy_formation: Array[Dictionary], random_seed: int) -> void:
	stop_battle()
	_battle_generation += 1
	_release_current_states()
	_next_state_runtime_id = 1
	player_states = _create_states(player_formation, BattleSquadState.Side.PLAYER)
	enemy_states = _create_states(enemy_formation, BattleSquadState.Side.ENEMY)
	current_result = Result.NONE
	elapsed_seconds = 0.0
	batch_count = 0
	_next_group_id = 1
	_next_projectile_batch_id = 1
	_next_projectile_launch_sequence = 1
	active_continuous_effects.clear()
	_wound_periodic_effects.clear()
	_continuous_followups.clear()
	permanent_growth_ledger.clear()
	run_reward_ledger.clear()
	owned_card_change_ledger.clear()
	_chaos_reward_records.clear()
	_emblem_registrations.clear()
	_wound_registrations.clear()
	_fracture_participation.clear()
	_temporary_wound_slot_mutations.clear()
	_next_emblem_keyword_source_id = 1
	_next_reward_instance_sequence = 1
	_processed_gold_reward_entry_ids.clear()
	_processed_spell_event_ids.clear()
	_elapsed_spell_attempted.clear()
	_minimum_health_until.clear()
	_side_by_side_grants.clear()
	_death_sequence = 0
	_death_history.clear()
	_opening_spell_queue.clear()
	_opening_spell_active = false
	_opening_spell_presentation_done = true
	_opening_spell_effect_done = true
	_next_probability_roll_sequence = 1
	_next_fatigue_stack_seconds = BattleRules.FATIGUE_START_SECONDS
	_next_fatigue_damage_seconds = BattleRules.FATIGUE_START_SECONDS
	if random_seed >= 0:
		battle_seed = random_seed
		_random.seed = random_seed
	else:
		_random.randomize()
		battle_seed = _random.seed
	effect_runtime.initialize(self, battle_seed)
	if not effect_runtime.trace_emitted.is_connected(_on_effect_trace_emitted):
		effect_runtime.trace_emitted.connect(_on_effect_trace_emitted)
	if not effect_runtime.direct_effect_resolved.is_connected(_on_runtime_direct_effect_resolved):
		effect_runtime.direct_effect_resolved.connect(_on_runtime_direct_effect_resolved)
	_register_formation_card_effects()
	_register_formation_emblems()
	_register_formation_wounds()
	player_resource_states.clear()
	enemy_resource_states.clear()
	mining_actions_remaining_by_runtime_id.clear()
	_player_owned_card_ids.clear()
	recalculate_logical_layout()


func _initialize_resource_states(player_cards: Array[OwnedCard], enemy_cards: Array[OwnedCard]) -> void:
	player_resource_states.clear()
	enemy_resource_states.clear()
	for pair: Array in [[player_cards, BattleSquadState.Side.PLAYER], [enemy_cards, BattleSquadState.Side.ENEMY]]:
		var destination: Array[RefCounted] = player_resource_states if int(pair[1]) == BattleSquadState.Side.PLAYER else enemy_resource_states
		for card: OwnedCard in pair[0]:
			if card == null or card.card_data == null or card.card_data.card_type != CardData.CardType.RESOURCE:
				continue
			var state := BattleResourceStateScript.new()
			state.initialize(card, int(pair[1]))
			destination.append(state)


func _count_mining_actions() -> Dictionary:
	var counts: Dictionary = {}
	for state: BattleSquadState in get_all_states():
		var uses := 0
		if state.squad_data != null:
			uses += _mining_uses_from_card(state.squad_data.get_effect_source())
			var equipment := state.squad_data.get_equipped_item()
			uses += _mining_uses_from_card(equipment.card_data if equipment != null else null)
		counts[state.runtime_id] = uses
	return counts


func _mining_uses_from_card(card: CardData) -> int:
	if card == null or not card.keywords.has(&"mining"):
		return 0
	return maxi(1, int(card.deferred_effect_hooks.get("mining", {}).get("uses_per_battle", 1)))


func _register_formation_emblems() -> void:
	# 逐小队扫描可见槽位，不依赖行动、生命、护甲的来源卡；同一OwnedCard实例只登记一次。
	for state: BattleSquadState in get_all_states():
		if state.squad_data == null:
			continue
		for card: CardData in state.squad_data.horizontal_cards:
			var owner := state.squad_data.get_owned_card(card)
			if owner == null:
				continue
			for slot_index: int in state.squad_data.get_visible_emblem_slot_indices(card):
				if slot_index < 0 or slot_index >= owner.emblem_slots.size():
					continue
				var slot: Dictionary = owner.emblem_slots[slot_index]
				var emblem_id := StringName(String(slot.get("emblem_id", "")))
				var instance_id := StringName(String(slot.get("instance_id", "")))
				var definition: Dictionary = EmblemLibraryData.BATTLE_EFFECTS.get(emblem_id, {})
				if instance_id.is_empty() or definition.is_empty():
					continue
				var keyword_source_id := _next_emblem_keyword_source_id
				_next_emblem_keyword_source_id += 1
				var registration := {
					"state": state,
					"owner": owner,
					"emblem_id": emblem_id,
					"instance_id": instance_id,
					"keyword_source_id": keyword_source_id,
					"definition": definition,
					"slot_index": slot_index,
					"melee_immunity_used": false,
					"lethal_coin_used": false,
					"seed_valid": true,
					"next_time": float(definition.get("heal_interval", definition.get("armor_interval", INF))),
					"paused_remaining": INF,
					"shadow_until": elapsed_seconds + float(definition.get("shadow_duration", INF)),
					"shadow_paused_remaining": INF,
					"visibility_active": true,
				}
				_emblem_registrations.append(registration)
				var keyword := StringName(String(definition.get("keyword", "")))
				if not keyword.is_empty():
					state.grant_runtime_keyword(keyword, keyword_source_id)
					if keyword == &"emblem_shadow":
						state.emblem_shadow_source_ids[keyword_source_id] = instance_id
				var runtime_race := int(definition.get("runtime_race", -1))
				if runtime_race >= 0:
					state.grant_runtime_race(instance_id, runtime_race as CardData.RaceType)


func _register_formation_wounds() -> void:
	# 伤势和纹章一样只读取显现槽；遮挡、重排和非来源卡不会额外注册。
	for state: BattleSquadState in get_all_states():
		if state.squad_data == null:
			continue
		for slot: Dictionary in state.squad_data.get_visible_wound_slots():
			var card := slot.get("card") as CardData
			var owner := state.squad_data.get_owned_card(card)
			if owner == null:
				continue
			var slot_index := int(slot.get("slot_index", -1))
			if slot_index < 0 or slot_index >= owner.wound_slots.size():
				continue
			var wound_id := StringName(String(owner.wound_slots[slot_index].get("wound_id", "")))
			var wound_instance_id := StringName("%s:wound:%d" % [owner.instance_id, slot_index])
			if wound_id in [&"中毒Ⅰ", &"中毒Ⅱ", &"中毒Ⅲ"]:
				var poison_damage := 1 if wound_id == &"中毒Ⅰ" else (2 if wound_id == &"中毒Ⅱ" else 3)
				_wound_periodic_effects.append({
					"state": state,
					"owner": owner,
					"wound_id": wound_id,
					"instance_id": wound_instance_id,
					"damage": poison_damage,
					"next_time": 2.0,
					"paused_remaining": INF,
					"active": true,
				})
			var definition: Dictionary = EmblemLibraryData.WOUND_BATTLE_EFFECTS.get(wound_id, {})
			if definition.is_empty():
				continue
			var armor_gain_penalty := int(definition.get("armor_gain_penalty", 0))
			var armor_modifier_source_id := 0
			if armor_gain_penalty > 0:
				var armor_modifier := BattleModifier.new()
				armor_modifier.stat = BattleModifier.Stat.ARMOR_GAIN
				armor_modifier.mode = BattleModifier.Mode.ADD
				armor_modifier.value = -float(armor_gain_penalty)
				armor_modifier_source_id = -2000000 - _wound_registrations.size()
				armor_modifier.source_instance_id = armor_modifier_source_id
				armor_modifier.effect_id = StringName("wound_%s" % wound_instance_id)
				armor_modifier.source_runtime_id = state.runtime_id
				armor_modifier.contribution_sources.append({
					"role": "获得护甲减值",
					"amount": -armor_gain_penalty,
					"source_name": String(wound_id),
					"source_card_name": owner.card_data.display_name if owner.card_data != null else "未知来源",
					"source_card_id": String(owner.card_data.id) if owner.card_data != null else "",
					"source_owned_card_instance_id": String(owner.instance_id),
					"source_status": "resolved",
				})
				state.modifiers.add_modifier(armor_modifier)
			var registration := {
				"state": state,
				"owner": owner,
				"wound_id": wound_id,
				"slot_index": slot_index,
				"instance_id": wound_instance_id,
				"definition": definition,
				"armor_modifier_source_id": armor_modifier_source_id,
				"active": true,
				"sleep_until": INF,
			}
			_wound_registrations.append(registration)
			var fracture_battles := int(definition.get("fracture_battles", 0))
			if fracture_battles > 0 and state.side == BattleSquadState.Side.PLAYER and state.get_unmasked_active_injuries().has(wound_instance_id):
				_fracture_participation.append({
					"state": state,
					"owner": owner,
					"wound_id": wound_id,
					"instance_id": wound_instance_id,
					"threshold": fracture_battles,
				})


func _is_emblem_registration_visible(registration: Dictionary) -> bool:
	var state := registration.get("state") as BattleSquadState
	var owner := registration.get("owner") as OwnedCard
	var slot_index := int(registration.get("slot_index", -1))
	if state == null or state.squad_data == null or owner == null or owner.card_data == null:
		return false
	if slot_index < 0 or slot_index >= owner.emblem_slots.size():
		return false
	if not state.squad_data.get_visible_emblem_slot_indices(owner.card_data).has(slot_index):
		return false
	return StringName(String(owner.emblem_slots[slot_index].get("instance_id", ""))) == registration.get("instance_id", &"")


func _sync_emblem_registration_visibility() -> void:
	# 战斗中显现关系变化时，周期纹章及限时影蔽保存剩余时间，不补发遮挡期间的跳数。
	for registration: Dictionary in _emblem_registrations:
		var visible := _is_emblem_registration_visible(registration)
		if visible == bool(registration.get("visibility_active", true)):
			continue
		registration["visibility_active"] = visible
		var state := registration.get("state") as BattleSquadState
		if state == null:
			continue
		var keyword := StringName(String((registration.get("definition", {}) as Dictionary).get("keyword", "")))
		var source_id := int(registration.get("keyword_source_id", 0))
		var instance_id := registration.get("instance_id", &"") as StringName
		if not visible:
			registration["paused_remaining"] = maxf(float(registration.get("next_time", INF)) - elapsed_seconds, 0.0)
			registration["next_time"] = INF
			registration["shadow_paused_remaining"] = maxf(float(registration.get("shadow_until", INF)) - elapsed_seconds, 0.0)
			registration["shadow_until"] = INF
			if not keyword.is_empty():
				state.revoke_runtime_keyword(keyword, source_id)
				state.emblem_shadow_source_ids.erase(source_id)
			state.runtime_race_sources.erase(instance_id)
			continue
		var remaining := float(registration.get("paused_remaining", INF))
		if is_finite(remaining):
			registration["next_time"] = elapsed_seconds + remaining
			registration["paused_remaining"] = INF
		var shadow_remaining := float(registration.get("shadow_paused_remaining", INF))
		if is_finite(shadow_remaining):
			registration["shadow_until"] = elapsed_seconds + shadow_remaining
			registration["shadow_paused_remaining"] = INF
		if not keyword.is_empty() and (keyword != &"emblem_shadow" or is_finite(float(registration.get("shadow_until", INF)))):
			state.grant_runtime_keyword(keyword, source_id)
			if keyword == &"emblem_shadow":
				state.emblem_shadow_source_ids[source_id] = instance_id
		var runtime_race := int((registration.get("definition", {}) as Dictionary).get("runtime_race", -1))
		if runtime_race >= 0:
			state.grant_runtime_race(instance_id, runtime_race as CardData.RaceType)


func _apply_emblem_rush_effects(entering_state: BattleSquadState = null) -> void:
	# 开战和复活沿用RUSH窗口；每次只处理本次入场者的纹章实例。
	for registration: Dictionary in _emblem_registrations:
		var state := registration.get("state") as BattleSquadState
		var definition: Dictionary = registration.get("definition", {})
		if state == null or (entering_state != null and state != entering_state) or not _is_emblem_registration_visible(registration):
			continue
		var reinforcement := int(definition.get("reinforcement", 0))
		if reinforcement > 0 and entering_state == null:
			_add_emblem_reinforcement(state, registration, reinforcement)
		var charge := float(definition.get("rush_charge", 0.0))
		if charge > 0.0:
			_charge_state(state, charge)
		if bool(definition.get("rush_convert_rightmost_rune", false)):
			_convert_rightmost_rune_to_fire(state)
		if int(definition.get("adjacent_protection", 0)) > 0:
			for ally: BattleSquadState in _get_adjacent_allies(state):
				ally.grant_protection(StringName("emblem:%s:protection" % registration.get("instance_id", "")), int(definition.get("adjacent_protection", 0)))
		var adjacent_reinforcement := int(definition.get("adjacent_reinforcement", 0))
		var adjacent_charge := float(definition.get("adjacent_rush_charge", 0.0))
		if adjacent_reinforcement <= 0 and adjacent_charge <= 0.0:
			continue
		for ally: BattleSquadState in _get_adjacent_allies(state):
			if adjacent_reinforcement > 0:
				_add_emblem_reinforcement(ally, registration, adjacent_reinforcement)
			if adjacent_charge > 0.0:
				_charge_state(ally, adjacent_charge)


func _apply_wound_rush_effects(entering_state: BattleSquadState = null) -> void:
	for registration: Dictionary in _wound_registrations:
		var state := registration.get("state") as BattleSquadState
		if state == null or (entering_state != null and state != entering_state) or not state.get_unmasked_active_injuries().has(registration.get("instance_id", &"")):
			continue
		var amount := int((registration.get("definition", {}) as Dictionary).get("rush_reinforcement", 0))
		if amount <= 0:
			continue
		_add_wound_reinforcement(state, registration, amount)


func _add_wound_reinforcement(target: BattleSquadState, registration: Dictionary, amount: int) -> void:
	_add_status_reinforcement(target, registration, amount, "突击", "突击强化")


func _apply_visible_fire_rune_reinforcement() -> void:
	for state: BattleSquadState in get_all_states():
		if state.squad_data == null:
			continue
		var visible_slot_index := 0
		for slot: Dictionary in state.get_active_rune_slots():
			visible_slot_index += 1
			if int(slot.get("element", -1)) != CardData.ElementType.FIRE:
				continue
			var card := slot.get("card") as CardData
			var owner := state.squad_data.get_owned_card(card)
			var rune_index := int(slot.get("rune_index", -1))
			var modifier := BattleModifier.new()
			modifier.stat = BattleModifier.Stat.REINFORCEMENT
			modifier.mode = BattleModifier.Mode.ADD
			modifier.value = 2.0
			modifier.source_instance_id = -3000000 - state.runtime_id * 10 - visible_slot_index
			modifier.effect_id = &"visible_fire_rune"
			modifier.source_runtime_id = state.runtime_id
			modifier.contribution_sources.append({
				"role": "强化",
				"amount": 2,
				"source_name": "火符文",
				"source_card_name": card.display_name if card != null else "未知卡牌",
				"source_card_id": String(card.id) if card != null else "",
				"source_owned_card_instance_id": String(owner.instance_id) if owner != null else "",
				"trigger_name": "开战",
				"source_status": "resolved",
			})
			state.modifiers.add_modifier(modifier)
			state.track_fire_rune_reinforcement(card, rune_index, modifier.source_instance_id)


func _add_status_reinforcement(
	target: BattleSquadState,
	registration: Dictionary,
	amount: int,
	trigger_name: String,
	role: String
) -> void:
	if target == null or amount <= 0:
		return
	var modifier := BattleModifier.new()
	modifier.stat = BattleModifier.Stat.REINFORCEMENT
	modifier.mode = BattleModifier.Mode.ADD
	modifier.value = float(amount)
	modifier.source_instance_id = -1000000 - _wound_registrations.find(registration)
	modifier.effect_id = StringName("wound_%s" % registration.get("instance_id", ""))
	var source := registration.get("state") as BattleSquadState
	modifier.source_runtime_id = source.runtime_id if source != null else target.runtime_id
	var owner := registration.get("owner") as OwnedCard
	modifier.contribution_sources.append({
		"role": role,
		"amount": amount,
		"source_name": String(registration.get("wound_id", "未知伤势")),
		"source_card_name": owner.card_data.display_name if owner != null and owner.card_data != null else "未知来源",
		"source_card_id": String(owner.card_data.id) if owner != null and owner.card_data != null else "",
		"source_owned_card_instance_id": String(owner.instance_id) if owner != null else "",
		"trigger_name": trigger_name,
		"source_status": "resolved" if owner != null else "unknown",
	})
	target.modifiers.add_modifier(modifier)


func _apply_greed_gold_trigger(reward_state: BattleSquadState) -> void:
	if reward_state == null or reward_state.side != BattleSquadState.Side.PLAYER:
		return
	for registration: Dictionary in _wound_registrations:
		var carrying_state := registration.get("state") as BattleSquadState
		if carrying_state == null or carrying_state.side != BattleSquadState.Side.PLAYER:
			continue
		var instance_id := registration.get("instance_id", &"") as StringName
		if not carrying_state.get_unmasked_active_injuries().has(instance_id):
			continue
		var bonus := int((registration.get("definition", {}) as Dictionary).get("gold_reinforcement_bonus", 0))
		if bonus <= 0:
			continue
		var amount := carrying_state.get_action_value_without_reinforcement() + bonus
		_add_status_reinforcement(carrying_state, registration, amount, "获得金币", "贪婪强化")


func _add_emblem_reinforcement(
	target: BattleSquadState,
	registration: Dictionary,
	amount: int,
	trigger_name: String = "突击"
) -> void:
	var modifier := BattleModifier.new()
	modifier.stat = BattleModifier.Stat.REINFORCEMENT
	modifier.mode = BattleModifier.Mode.ADD
	modifier.value = float(amount)
	modifier.source_instance_id = -int(registration.get("keyword_source_id", 0))
	modifier.effect_id = StringName("emblem_%s" % registration.get("instance_id", ""))
	var source := registration.get("state") as BattleSquadState
	modifier.source_runtime_id = source.runtime_id if source != null else target.runtime_id
	var owner := registration.get("owner") as OwnedCard
	modifier.contribution_sources.append({
		"role": "强化",
		"amount": amount,
		"source_name": String(registration.get("emblem_id", "未知纹章")),
		"source_card_name": owner.card_data.display_name if owner != null and owner.card_data != null else "未知来源",
		"source_card_id": String(owner.card_data.id) if owner != null and owner.card_data != null else "",
		"source_owned_card_instance_id": String(owner.instance_id) if owner != null else "",
		"trigger_name": trigger_name,
		"source_status": "resolved" if owner != null else "unknown",
	})
	target.modifiers.add_modifier(modifier)


func _charge_state(target: BattleSquadState, seconds: float) -> void:
	if target == null or not target.alive or seconds <= 0.0:
		return
	target.charge_action_cooldown(seconds)


func _get_adjacent_allies(source: BattleSquadState) -> Array[BattleSquadState]:
	var result: Array[BattleSquadState] = []
	if source == null:
		return result
	for candidate: BattleSquadState in get_all_states():
		if candidate != source and candidate.side == source.side and candidate.row_key == source.row_key and abs(candidate.formation_index - source.formation_index) == 1 and candidate.alive and candidate.current_health > 0.0:
			result.append(candidate)
	return result


func _register_formation_card_effects() -> void:
	if effect_catalog == null:
		effect_catalog = BattleEffectCatalog.load_from_file(EFFECT_DATA_PATH)
	if not effect_catalog.is_valid():
		for error: String in effect_catalog.errors:
			push_error(error)
		return
	for state: BattleSquadState in get_all_states():
		var card := state.get_effect_source()
		_register_card_effects(state, card)
		var equipped_item := (
			state.squad_data.get_equipped_item()
			if state.squad_data != null
			else null
		)
		if equipped_item != null:
			_register_card_effects(state, equipped_item.card_data, true)


func _register_card_effects(
	state: BattleSquadState,
	card: CardData,
	is_equipment: bool = false
) -> void:
	if card == null or not card.is_available:
		return
	for effect_id: StringName in card.effect_ids:
		var definition := effect_catalog.get_definition(effect_id)
		if definition == null:
			push_error("卡牌 %s 绑定了效果目录中不存在的效果：%s" % [card.id, effect_id])
			continue
		if is_equipment and definition.source_owner != BattleEffectDefinition.OwnerKind.EQUIPMENT_INSTANCE:
			push_error("装备 %s 的效果 %s 必须以 equipment_instance 为来源" % [card.id, effect_id])
			continue
		effect_runtime.register_definition(
			definition,
			BattleEffectOwnerRef.for_state(state, definition.source_owner)
		)


func stop_battle() -> void:
	_running = false
	if _opening_spell_active:
		_battle_generation += 1
	_opening_spell_active = false
	_opening_spell_queue.clear()
	set_process(false)
	_pending_projectile_contexts.clear()
	_pending_projectile_batch_counts.clear()


func clear_battle() -> void:
	_battle_generation += 1
	_opening_spell_active = false
	_opening_spell_queue.clear()
	_prepared_spell_instances.clear()
	_enemy_prepared_spell_instances.clear()
	_spell_side_by_instance.clear()
	stop_battle()
	_restore_temporary_wound_slots()
	_release_current_states()
	player_resource_states.clear()
	enemy_resource_states.clear()
	mining_actions_remaining_by_runtime_id.clear()
	_player_owned_card_ids.clear()
	active_continuous_effects.clear()
	_wound_periodic_effects.clear()
	_continuous_followups.clear()
	current_result = Result.NONE
	elapsed_seconds = 0.0
	batch_count = 0
	_next_group_id = 1
	_next_projectile_batch_id = 1
	_next_projectile_launch_sequence = 1
	_next_state_runtime_id = 1
	_next_fatigue_stack_seconds = BattleRules.FATIGUE_START_SECONDS
	_next_fatigue_damage_seconds = BattleRules.FATIGUE_START_SECONDS
	_random = RandomNumberGenerator.new()
	effect_runtime.initialize(self, 0)
	battle_instance_id = &""
	permanent_growth_ledger.clear()
	run_reward_ledger.clear()
	owned_card_change_ledger.clear()
	_chaos_reward_records.clear()
	_emblem_registrations.clear()
	_wound_registrations.clear()
	_fracture_participation.clear()
	_temporary_wound_slot_mutations.clear()
	_next_emblem_keyword_source_id = 1
	_processed_gold_reward_entry_ids.clear()
	_processed_spell_event_ids.clear()
	_next_probability_roll_sequence = 1


func _release_current_states() -> void:
	for state: BattleSquadState in get_all_states():
		state.force_boundary_sync()
		state.clear_precise_runtime()
		if state.integer_settlement_committed.is_connected(_on_integer_settlement_committed):
			state.integer_settlement_committed.disconnect(_on_integer_settlement_committed)
		if state.health_lost_accumulated.is_connected(_on_health_lost_accumulated):
			state.health_lost_accumulated.disconnect(_on_health_lost_accumulated)
	player_states.clear()
	enemy_states.clear()


func is_running() -> bool:
	return _running


func set_battle_speed_multiplier(value: float) -> void:
	battle_speed_multiplier = clampf(value, 0.5, 3.0)


func get_all_states() -> Array[BattleSquadState]:
	var states: Array[BattleSquadState] = []
	states.append_array(player_states)
	states.append_array(enemy_states)
	return states


func get_living_states(side: int) -> Array[BattleSquadState]:
	var living: Array[BattleSquadState] = []
	var source := player_states if side == BattleSquadState.Side.PLAYER else enemy_states
	for state: BattleSquadState in source:
		if state.alive:
			living.append(state)
	return living


func revive_state_at_original_position(
	state: BattleSquadState,
	health_amount: float,
	retrigger_rush: bool = true
) -> bool:
	if state == null or state.alive or state.current_health > 0.0:
		return false
	for candidate: BattleSquadState in get_all_states():
		if (
			candidate != state
			and candidate.alive
			and candidate.side == state.side
			and candidate.row_key == state.row_key
			and candidate.formation_index == state.formation_index
		):
			return false
	if not state.revive_at_current_maximum(health_amount):
		return false
	recalculate_logical_layout()
	var continuous_event := effect_runtime.recheck_continuous_conditions()
	if retrigger_rush:
		_apply_emblem_rush_effects(state)
		_apply_wound_rush_effects(state)
	# 普通复活先排空持续效果复检，再触发突击；法术指定不重触突击时略过该步。
	effect_runtime.process_due_for_root(elapsed_seconds, continuous_event.root_event_id)
	if retrigger_rush:
		effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.RUSH, {"actor": state})
		effect_runtime.process_due(elapsed_seconds)
	squad_revived.emit(state)
	states_changed.emit()
	return true


func record_pending_permanent_growth(
	owner: BattleEffectOwnerRef,
	stat: StringName,
	amount: float,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int
) -> bool:
	if not permanent_growth_ledger.record(
		owner,
		stat,
		amount,
		effect_id,
		source_runtime_id,
		logical_time_us,
		battle_instance_id
	):
		return false
	var entries := permanent_growth_ledger.get_entries()
	permanent_growth_recorded.emit(entries[-1])
	return true


func record_pending_run_reward(
	owner: BattleEffectOwnerRef,
	kind: StringName,
	amount: int,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int,
	parameters: Dictionary = {}
) -> bool:
	if not run_reward_ledger.record(
		owner,
		kind,
		amount,
		effect_id,
		source_runtime_id,
		logical_time_us,
		parameters,
		battle_instance_id
	):
		return false
	var entries := run_reward_ledger.get_entries()
	var reward_entry := entries[-1]
	pending_run_reward_recorded.emit(reward_entry)
	if kind == BattleRunRewardLedger.KIND_GOLD:
		var reward_entry_id := reward_entry.get("entry_id", &"") as StringName
		if not reward_entry_id.is_empty() and not _processed_gold_reward_entry_ids.has(reward_entry_id):
			_processed_gold_reward_entry_ids[reward_entry_id] = true
			_apply_greed_gold_trigger(owner.state)
	return true


func record_pending_wound_battle_counter(
	owner: BattleEffectOwnerRef,
	counter_key: StringName,
	value: int,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int
) -> bool:
	if not owned_card_change_ledger.record_wound_battle_counter(
		owner,
		counter_key,
		value,
		effect_id,
		source_runtime_id,
		logical_time_us,
		battle_instance_id
	):
		return false
	var entries := owned_card_change_ledger.get_entries()
	pending_owned_card_change_recorded.emit(entries[-1])
	return true


func get_emblem_score_contribution(side: int = BattleSquadState.Side.PLAYER) -> int:
	var total := 0
	for registration: Dictionary in _emblem_registrations:
		var state := registration.get("state") as BattleSquadState
		if state != null and state.side == side and _is_emblem_registration_visible(registration):
			total += EmblemLibraryData.get_score_contribution(registration.get("emblem_id", &"") as StringName)
	return total


func get_spent_emblem_slots_by_card(state: BattleSquadState) -> Dictionary:
	var result: Dictionary = {}
	for registration: Dictionary in _emblem_registrations:
		if registration.get("state") != state or not bool(registration.get("melee_immunity_used", false)):
			continue
		var owner := registration.get("owner") as OwnedCard
		if owner == null:
			continue
		var slots: Array[int] = []
		slots.assign(result.get(owner.card_data, []))
		slots.append(int(registration.get("slot_index", -1)))
		result[owner.card_data] = slots
	return result


func record_pending_owned_card_slot_change(
	owner: BattleEffectOwnerRef,
	kind: StringName,
	slot_index: int,
	slot_state: Dictionary,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int
) -> bool:
	if not owned_card_change_ledger.record_slot_change(
		owner,
		kind,
		slot_index,
		slot_state,
		effect_id,
		source_runtime_id,
		logical_time_us,
		battle_instance_id
	):
		return false
	var entries := owned_card_change_ledger.get_entries()
	pending_owned_card_change_recorded.emit(entries[-1])
	return true


func record_pending_random_squad_wound_heal(
	owner: BattleEffectOwnerRef,
	squad_card_instance_ids: Array[StringName],
	masked_wound_slot_keys: Array[StringName],
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int
) -> bool:
	if not owned_card_change_ledger.record_random_squad_wound_heal(
		owner,
		squad_card_instance_ids,
		masked_wound_slot_keys,
		effect_id,
		source_runtime_id,
		logical_time_us,
		battle_instance_id
	):
		return false
	var entries := owned_card_change_ledger.get_entries()
	pending_owned_card_change_recorded.emit(entries[-1])
	return true


func _record_chaos_pattern_participation(
	actor: BattleSquadState,
	pattern: RunePatternResult
) -> int:
	if actor == null or pattern == null or actor.side != BattleSquadState.Side.PLAYER:
		return 0
	var slots := actor.get_active_rune_slots()
	var recorded_count := 0
	for slot_index: int in pattern.participating_indices:
		if slot_index < 0 or slot_index >= slots.size():
			continue
		var slot: Dictionary = slots[slot_index]
		if slot.get("sticker_id", &"") != &"混沌贴纸":
			continue
		var card := slot.get("card") as CardData
		var rune_index := int(slot.get("rune_index", -1))
		var owned := actor.squad_data.get_owned_card(card) if actor.squad_data != null else null
		if owned == null or rune_index < 0 or rune_index >= owned.rune_stickers.size():
			continue
		var sticker: Dictionary = owned.rune_stickers[rune_index]
		var sticker_instance_id := StringName(String(sticker.get("instance_id", "")))
		var element := int(slot.get("element", -1))
		if sticker_instance_id.is_empty() or element < 0 or element > 4 or _chaos_reward_records.has(sticker_instance_id):
			continue
		var owner := BattleEffectOwnerRef.for_owned_card_in_state(actor, owned)
		var effect_id: StringName = &"chaos_rune_reward"
		var logical_time_us := roundi(elapsed_seconds * 1000000.0)
		var recorded := false
		match element:
			CardData.ElementType.WOOD:
				recorded = _record_chaos_team_growth(
					actor,
					BattlePermanentGrowthLedger.STAT_BASE_ARMOR,
					2.0,
					effect_id,
					logical_time_us
				)
			CardData.ElementType.WATER:
				recorded = _record_chaos_team_growth(
					actor,
					BattlePermanentGrowthLedger.STAT_MAX_HEALTH,
					2.0,
					effect_id,
					logical_time_us
				)
			CardData.ElementType.FIRE:
				recorded = _record_chaos_team_growth(
					actor,
					BattlePermanentGrowthLedger.STAT_BASE_VALUE,
					1.0,
					effect_id,
					logical_time_us
				)
			CardData.ElementType.LIGHT:
				var player_owner := BattleEffectOwnerRef.for_state(
					actor,
					BattleEffectDefinition.OwnerKind.OWNING_PLAYER
				)
				recorded = record_pending_run_reward(
					player_owner,
					BattleRunRewardLedger.KIND_GOLD,
					4,
					effect_id,
					actor.runtime_id,
					logical_time_us,
					{"sticker_instance_id": sticker_instance_id}
				)
			CardData.ElementType.DARK:
				var squad_instance_ids: Array[StringName] = []
				for squad_card: CardData in actor.squad_data.horizontal_cards:
					var squad_owned := actor.squad_data.get_owned_card(squad_card)
					if squad_owned != null:
						squad_instance_ids.append(squad_owned.instance_id)
				recorded = record_pending_random_squad_wound_heal(
					owner,
					squad_instance_ids,
					[],
					effect_id,
					actor.runtime_id,
					logical_time_us
				)
		if recorded:
			_chaos_reward_records[sticker_instance_id] = {
				"element": element,
				"owned_card_instance_id": owned.instance_id,
				"rune_index": rune_index,
			}
			recorded_count += 1
	return recorded_count


func _record_chaos_team_growth(
	actor: BattleSquadState,
	stat: StringName,
	amount: float,
	effect_id: StringName,
	logical_time_us: int
) -> bool:
	if actor == null or actor.squad_data == null:
		return false
	var team_cards: Array[OwnedCard] = []
	for card_data: CardData in actor.squad_data.horizontal_cards:
		var owned := actor.squad_data.get_owned_card(card_data)
		if owned == null:
			return false
		team_cards.append(owned)
	if team_cards.is_empty():
		return false
	for owned: OwnedCard in team_cards:
		var owner := BattleEffectOwnerRef.for_owned_card_in_state(actor, owned)
		if not record_pending_permanent_growth(
			owner,
			stat,
			amount,
			effect_id,
			actor.runtime_id,
			logical_time_us
		):
			return false
		if not owned.apply_permanent_growth(_map_chaos_growth_stat(stat), amount):
			return false
		if owned == actor.squad_data.get_vitals_source_instance():
			match stat:
				BattlePermanentGrowthLedger.STAT_BASE_ARMOR:
					actor.current_armor += amount
				BattlePermanentGrowthLedger.STAT_MAX_HEALTH:
					actor.current_health += amount
	return true


func _map_chaos_growth_stat(stat: StringName) -> StringName:
	match stat:
		BattlePermanentGrowthLedger.STAT_BASE_VALUE:
			return OwnedCard.STAT_BASE_VALUE
		BattlePermanentGrowthLedger.STAT_BASE_ARMOR:
			return OwnedCard.STAT_BASE_ARMOR
		BattlePermanentGrowthLedger.STAT_MAX_HEALTH:
			return OwnedCard.STAT_MAX_HEALTH
	return &""


func get_chaos_reward_records() -> Dictionary:
	return _chaos_reward_records.duplicate(true)


func get_owned_card_change_entries_for_settlement() -> Array[Dictionary]:
	var entries := owned_card_change_ledger.get_entries()
	for entry: Dictionary in entries:
		if entry.get("kind") != BattleOwnedCardChangeLedger.KIND_HEAL_RANDOM_SQUAD_WOUND:
			continue
		var source_state: BattleSquadState
		for candidate: BattleSquadState in player_states:
			if candidate.runtime_id == int(entry.get("owner_runtime_id", -1)):
				source_state = candidate
				break
		if source_state == null or source_state.squad_data == null:
			continue
		var active_injury_ids: Dictionary = {}
		for injury_id: StringName in source_state.battle_active_injury_ids:
			active_injury_ids[injury_id] = true
		var unmasked_injury_ids: Dictionary = {}
		for injury_id: StringName in source_state.get_unmasked_active_injuries():
			unmasked_injury_ids[injury_id] = true
		var visible_wound_slot_keys: Dictionary = {}
		for slot: Dictionary in source_state.squad_data.get_visible_wound_slots():
			var slot_card := slot.get("card") as CardData
			var slot_owner := source_state.squad_data.get_owned_card(slot_card)
			if slot_owner == null:
				continue
			var slot_key := StringName(
				"%s:wound:%d" % [slot_owner.instance_id, int(slot.get("slot_index", -1))]
			)
			visible_wound_slot_keys[slot_key] = true
		var masked_slot_keys: Array[StringName] = []
		for card_data: CardData in source_state.squad_data.horizontal_cards:
			var owned := source_state.squad_data.get_owned_card(card_data)
			if owned == null:
				continue
			for wound_index: int in owned.wound_slots.size():
				if owned.wound_slots[wound_index].is_empty():
					continue
				var injury_id := StringName("%s:wound:%d" % [owned.instance_id, wound_index])
				if (
					not visible_wound_slot_keys.has(injury_id)
					or (active_injury_ids.has(injury_id) and not unmasked_injury_ids.has(injury_id))
				):
					masked_slot_keys.append(injury_id)
		var parameters := entry.get("parameters", {}) as Dictionary
		parameters["masked_wound_slot_keys"] = masked_slot_keys
		entry["parameters"] = parameters
	return entries


func record_pending_equipment_consumption(
	owner: BattleEffectOwnerRef,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int
) -> bool:
	return owned_card_change_ledger.record_equipment_consumption(
		owner, effect_id, source_runtime_id, logical_time_us, battle_instance_id
	)


func record_pending_emblem_progress(
	owner: BattleEffectOwnerRef,
	emblem_instance_id: StringName,
	amount: int,
	effect_id: StringName,
	source_runtime_id: int,
	logical_time_us: int
) -> bool:
	if not owned_card_change_ledger.record_emblem_progress(
		owner,
		emblem_instance_id,
		amount,
		effect_id,
		source_runtime_id,
		logical_time_us,
		battle_instance_id
	):
		return false
	var entries := owned_card_change_ledger.get_entries()
	pending_owned_card_change_recorded.emit(entries[-1])
	return true


func _resolve_battle_instance_id(requested_id: StringName) -> StringName:
	if not requested_id.is_empty():
		return requested_id
	var result := StringName("controller_battle_%06d" % _next_local_battle_sequence)
	_next_local_battle_sequence += 1
	return result


func advance_time(delta: float) -> void:
	if not performance_trace_enabled:
		_advance_time_unprofiled(delta)
		return
	var profile_started_usec := Time.get_ticks_usec()
	_advance_time_unprofiled(delta)
	performance_trace_advance_total_usec += Time.get_ticks_usec() - profile_started_usec


func _advance_time_unprofiled(delta: float) -> void:
	var time_left := maxf(delta, 0.0)
	if _opening_spell_active:
		time_left = _advance_opening_spell_phase(time_left)
		if time_left <= COOLDOWN_EPSILON or _opening_spell_active:
			return
	while _running and time_left > COOLDOWN_EPSILON:
		var next_time := _get_next_event_delay()
		if not is_finite(next_time):
			return
		if time_left + COOLDOWN_EPSILON < next_time:
			_decrease_living_cooldowns(time_left)
			elapsed_seconds += time_left
			states_changed.emit()
			return
		_decrease_living_cooldowns(next_time)
		elapsed_seconds += next_time
		time_left -= next_time
		_resolve_ready_batch()


func resolve_next_batch() -> bool:
	if _opening_spell_active:
		advance_time(OPENING_SPELL_PRESENTATION_SECONDS)
		return true
	if not _running:
		return false
	var next_time := _get_next_event_delay()
	if not is_finite(next_time):
		return false
	_decrease_living_cooldowns(next_time)
	elapsed_seconds += next_time
	_resolve_ready_batch()
	return true


func choose_weighted_target(candidates: Array[BattleSquadState], forced_roll: int = -1) -> BattleSquadState:
	var valid: Array[BattleSquadState] = []
	var total_weight := 0
	for candidate: BattleSquadState in candidates:
		if candidate != null and candidate.alive and candidate.current_health > 0.0:
			valid.append(candidate)
			total_weight += get_effective_target_weight(candidate)
	if valid.is_empty() or total_weight <= 0:
		return null
	var roll := clampi(forced_roll, 0, total_weight - 1) if forced_roll >= 0 else _random.randi_range(0, total_weight - 1)
	var boundary := 0
	for candidate: BattleSquadState in valid:
		boundary += get_effective_target_weight(candidate)
		if roll < boundary:
			return candidate
	return valid[-1]


func choose_base_target(
	actor: BattleSquadState,
	candidates: Array[BattleSquadState],
	action_type: CardData.ActionType,
	forced_roll: int = -1
) -> BattleSquadState:
	# 治疗和防御选友军，不能让敌方攻击的耀眼规则改写它们的目标池。
	if action_type in [CardData.ActionType.HEAL, CardData.ActionType.DEFENSE]:
		return choose_weighted_target(candidates, forced_roll)
	if actor == null:
		return null
	var preference := actor.get_target_action_type_preference()
	var beast_attack := actor.has_effective_race(CardData.RaceType.BEAST)
	var candidates_by_tier: Array[Array] = [[], [], [], [], []]
	for candidate: BattleSquadState in candidates:
		if candidate == null or not candidate.alive or candidate.current_health <= 0.0 or candidate.moon_shadowed or candidate.has_runtime_keyword(&"emblem_shadow"):
			continue
		var tier := _attack_target_tier(candidate, preference, beast_attack)
		(candidates_by_tier[tier] as Array).append(candidate)
	for tier: int in range(5):
		var tier_candidates: Array[BattleSquadState] = []
		for candidate: BattleSquadState in candidates_by_tier[tier]:
			tier_candidates.append(candidate)
		var total_weight := 0
		for candidate: BattleSquadState in tier_candidates:
			total_weight += get_effective_target_weight(candidate)
		if total_weight > 0:
			return choose_weighted_target(tier_candidates, forced_roll)
	return null


func _choose_attack_target_with_resources(
	actor: BattleSquadState,
	candidates: Array[BattleSquadState],
	resources: Array[RefCounted]
) -> Dictionary:
	var preference := actor.get_target_action_type_preference()
	var beast_attack := actor.has_effective_race(CardData.RaceType.BEAST)
	var squad_tiers: Array[Array] = [[], [], [], [], []]
	for candidate: BattleSquadState in candidates:
		if candidate == null or not candidate.alive or candidate.current_health <= 0.0 or candidate.moon_shadowed or candidate.has_runtime_keyword(&"emblem_shadow"):
			continue
		(squad_tiers[_attack_target_tier(candidate, preference, beast_attack)] as Array).append(candidate)
	var resource_tier := 3 if preference >= 0 else 1
	for tier in 5:
		var available_resources: Array[RefCounted] = []
		if tier == resource_tier:
			for resource: RefCounted in resources:
				if not resource.get("destroyed") and int(resource.get("current_health")) > 0:
					available_resources.append(resource)
		var tier_weight := available_resources.size()
		for candidate: BattleSquadState in squad_tiers[tier]:
			tier_weight += get_effective_target_weight(candidate)
		if tier_weight <= 0:
			continue
		var roll := _random.randi_range(0, tier_weight - 1)
		var boundary := 0
		for candidate: BattleSquadState in squad_tiers[tier]:
			boundary += get_effective_target_weight(candidate)
			if roll < boundary:
				return {"target": candidate, "resource_target": null}
		roll -= boundary
		return {"target": null, "resource_target": available_resources[roll]}
	return {"target": null, "resource_target": null}


func _attack_target_tier(candidate: BattleSquadState, preference: int, beast_attack: bool) -> int:
	# “野兽不会优先攻击”高于耀眼及常规类型偏好，但并不使目标永久不可选。
	if beast_attack and candidate.has_targeting_keyword(&"beast_last"):
		return 4
	var dazzling := has_effective_dazzling(candidate)
	if preference >= 0:
		if candidate.get_effective_action_type() == preference:
			return 0 if dazzling else 1
		return 2 if dazzling else 3
	return 0 if dazzling else 1


func has_effective_dazzling(candidate: BattleSquadState) -> bool:
	if candidate.squad_data.has_indicator(CelestialIndicator.Kind.SUN):
		return true
	for state: BattleSquadState in get_all_states():
		if state.alive and state.current_health > 0.0 and state.squad_data.has_indicator(CelestialIndicator.Kind.SUN):
			return false
	return candidate.squad_data.has_indicator(CelestialIndicator.Kind.STAR) or candidate.has_targeting_keyword(&"dazzling")


func _on_indicator_action_launched(actor: BattleSquadState) -> void:
	if actor == null or not actor.squad_data.has_indicator(CelestialIndicator.Kind.MOON):
		return
	actor.moon_shadowed = false
	if not is_finite(actor.moon_restore_time):
		actor.moon_restore_time = elapsed_seconds + CelestialIndicator.MOON_RESTORE_SECONDS


func _clear_emblem_shadows_for_state(state: BattleSquadState) -> void:
	if state == null:
		return
	for source_id_value: Variant in state.emblem_shadow_source_ids.keys():
		var source_id := int(source_id_value)
		for registration: Dictionary in _emblem_registrations:
			if registration.get("state") == state and int(registration.get("keyword_source_id", -1)) == source_id:
				var definition := registration.get("definition", {}) as Dictionary
				if bool(definition.get("release_shadow_on_action", false)) or bool(definition.get("release_shadow_on_damage", false)):
					state.revoke_runtime_keyword(&"emblem_shadow", source_id)
					registration["shadow_until"] = INF
					state.emblem_shadow_source_ids.erase(source_id)


func _expire_emblem_shadows() -> void:
	for registration: Dictionary in _emblem_registrations:
		var state := registration.get("state") as BattleSquadState
		var shadow_until := float(registration.get("shadow_until", INF))
		if state == null or not state.alive or not is_finite(shadow_until) or shadow_until > elapsed_seconds + COOLDOWN_EPSILON:
			continue
		var source_id := int(registration.get("keyword_source_id", 0))
		if source_id > 0:
			state.revoke_runtime_keyword(&"emblem_shadow", source_id)
			state.emblem_shadow_source_ids.erase(source_id)
		registration["shadow_until"] = INF


func _collect_due_emblem_events() -> Array[BattleEffectEvent]:
	_sync_emblem_registration_visibility()
	var events: Array[BattleEffectEvent] = []
	for registration: Dictionary in _emblem_registrations:
		var state := registration.get("state") as BattleSquadState
		var definition: Dictionary = registration.get("definition", {})
		var tick_time := float(registration.get("next_time", INF))
		if not _is_emblem_registration_visible(registration) or not is_finite(tick_time) or tick_time > elapsed_seconds + COOLDOWN_EPSILON:
			continue
		if state == null or not state.alive or state.current_health <= 0.0:
			registration["next_time"] = INF
			continue
		var interval := float(definition.get("heal_interval", definition.get("armor_interval", INF)))
		if not is_finite(interval) or interval <= 0.0:
			registration["next_time"] = INF
			continue
		registration["next_time"] = tick_time + interval
		var event := BattleEffectEvent.new()
		event.group_id = _take_group_id()
		event.sequence_index = events.size()
		event.timestamp = elapsed_seconds
		event.source = state
		event.target = state
		event.source_emblem_instance_id = StringName(String(registration.get("instance_id", "")))
		var owner := registration.get("owner") as OwnedCard
		event.source_owned_card_instance_id = owner.instance_id if owner != null else &""
		event.is_continuous = true
		if definition.has("heal_amount"):
			event.effect_kind = BattleEffectEvent.EffectKind.HEALING
			event.exact_amount = float(definition["heal_amount"])
			event.action_type = CardData.ActionType.HEAL
		else:
			event.effect_kind = BattleEffectEvent.EffectKind.ARMOR
			event.exact_amount = float(definition.get("armor_amount", 0.0))
			event.action_type = CardData.ActionType.DEFENSE
		event.formula = _make_emblem_periodic_formula(event, registration)
		event.log_qualifier = "纹章：%s（实例 %s）" % [registration.get("emblem_id", ""), registration.get("instance_id", "")]
		events.append(event)
	return events


func _make_emblem_periodic_formula(
	event: BattleEffectEvent,
	registration: Dictionary
) -> BattleFormulaData:
	var display_name := "治疗" if event.effect_kind == BattleEffectEvent.EffectKind.HEALING else "护甲"
	var formula := BattleFormulaData.create(
		display_name,
		event.action_type,
		event.exact_amount,
		1.0,
		1.0,
		event.source,
		event.target
	)
	var owner := registration.get("owner") as OwnedCard
	var source_card := owner.card_data if owner != null else null
	formula.base_value_sources.append({
		"source_kind": "emblem_periodic_value",
		"source_card_id": String(source_card.id) if source_card != null else "",
		"source_card_name": source_card.display_name if source_card != null else "未知来源",
		"source_owned_card_instance_id": String(owner.instance_id) if owner != null else "",
		"source_name": String(registration.get("emblem_id", "未知纹章")),
		"trigger_name": "周期治疗" if event.effect_kind == BattleEffectEvent.EffectKind.HEALING else "周期护甲",
		"amount": event.exact_amount,
		"source_status": "resolved" if source_card != null else "unknown",
		"source_resolution_reason": "显现纹章实例的周期注册记录",
	})
	return formula


func _stop_emblem_periods_for_state(state: BattleSquadState) -> void:
	for registration: Dictionary in _emblem_registrations:
		if registration.get("state") == state:
			registration["next_time"] = INF
			registration["paused_remaining"] = INF
			registration["shadow_until"] = INF
			registration["shadow_paused_remaining"] = INF
	for source_id_value: Variant in state.emblem_shadow_source_ids.keys():
		state.revoke_runtime_keyword(&"emblem_shadow", int(source_id_value))
	state.emblem_shadow_source_ids.clear()
	state.sleep_source_until.clear()


func _transfer_defeated_star(source: BattleSquadState) -> void:
	if not source.squad_data.has_indicator(CelestialIndicator.Kind.STAR):
		return
	var candidates: Array[BattleSquadState] = []
	for target: BattleSquadState in get_all_states():
		if target != source and target.side == source.side and target.alive and target.current_health > 0.0 and not target.squad_data.has_indicator(CelestialIndicator.Kind.STAR):
			candidates.append(target)
	if candidates.is_empty():
		return
	var target := candidates[_random.randi_range(0, candidates.size() - 1)]
	for attachment: Dictionary in source.squad_data.indicator_attachments:
		var indicator := attachment["indicator"] as CelestialIndicator
		if indicator.kind != CelestialIndicator.Kind.STAR:
			continue
		indicator.star_transfer_count += 1
		target.squad_data.attach_indicator(indicator, attachment["position"], int(attachment["order"]))
		source.squad_data.detach_indicator(indicator.instance_id)
		var bonus := BattleModifier.new()
		bonus.stat = BattleModifier.Stat.ACTION_VALUE
		bonus.value = float(indicator.star_transfer_count)
		bonus.effect_id = &"star_transfer"
		bonus.source_runtime_id = source.runtime_id
		target.modifiers.add_modifier(bonus)
		indicator_transferred.emit(indicator, source, target)
		break


func get_effective_target_weight(state: BattleSquadState) -> int:
	var base_weight := state.get_target_weight()
	if base_weight <= 0:
		return 0
	var penalty := 1 if is_back_row(state.row_key) and get_front_cover_ratio(state) > BattleRules.FRONT_COVER_THRESHOLD else 0
	return maxi(base_weight - penalty, 1)


func recalculate_logical_layout() -> void:
	var rows: Dictionary = {}
	for state: BattleSquadState in get_all_states():
		if state.alive and state.current_health > 0.0:
			if not rows.has(state.row_key):
				rows[state.row_key] = []
			(rows[state.row_key] as Array).append(state)
	for row_value: Variant in rows.values():
		var row_states: Array = row_value as Array
		row_states.sort_custom(func(left: BattleSquadState, right: BattleSquadState) -> bool: return left.formation_index < right.formation_index)
		var total_width := BattleRules.LOGICAL_SQUAD_GAP * maxf(float(row_states.size() - 1), 0.0)
		for state: BattleSquadState in row_states:
			total_width += float(state.squad_data.get_display_width())
		var cursor := (BattleRules.LOGICAL_ROW_WIDTH - total_width) * 0.5
		for state: BattleSquadState in row_states:
			var width := float(state.squad_data.get_display_width())
			state.logical_left = cursor
			state.logical_right = cursor + width
			state.logical_center = cursor + width * 0.5
			cursor += width + BattleRules.LOGICAL_SQUAD_GAP


func get_front_cover_ratio(back_state: BattleSquadState) -> float:
	if back_state == null or not is_back_row(back_state.row_key):
		return 0.0
	var width := back_state.logical_right - back_state.logical_left
	if width <= 0.0:
		return 0.0
	var intervals: Array[Vector2] = []
	var front_key := _front_row_for_side(back_state.side)
	for state: BattleSquadState in get_all_states():
		if state.side != back_state.side or state.row_key != front_key or not state.alive or state.current_health <= 0.0:
			continue
		var left := maxf(back_state.logical_left, state.logical_left)
		var right := minf(back_state.logical_right, state.logical_right)
		if right > left:
			intervals.append(Vector2(left, right))
	if intervals.is_empty():
		return 0.0
	intervals.sort_custom(func(left: Vector2, right: Vector2) -> bool: return left.x < right.x)
	var covered := 0.0
	var union_left := intervals[0].x
	var union_right := intervals[0].y
	for index: int in range(1, intervals.size()):
		if intervals[index].x <= union_right:
			union_right = maxf(union_right, intervals[index].y)
		else:
			covered += union_right - union_left
			union_left = intervals[index].x
			union_right = intervals[index].y
	covered += union_right - union_left
	return covered / width


static func is_back_row(row_key: StringName) -> bool:
	return String(row_key).ends_with("_back")


func _create_states(formation: Array[Dictionary], side: int) -> Array[BattleSquadState]:
	var states: Array[BattleSquadState] = []
	for entry: Dictionary in formation:
		var squad := entry.get("squad_data") as SquadData
		if squad == null or not squad.is_valid():
			continue
		var state := BattleSquadState.new()
		state.runtime_id = _next_state_runtime_id
		_next_state_runtime_id += 1
		state.initialize(
			squad,
			side,
			StringName(entry.get("row_key", &"")),
			int(entry.get("formation_index", states.size())),
			float(entry.get("base_cooldown_override", -1.0))
		)
		state.integer_settlement_committed.connect(_on_integer_settlement_committed)
		state.health_lost_accumulated.connect(_on_health_lost_accumulated)
		state.armor_depleted.connect(_on_state_armor_depleted)
		state.injury_mask_changed.connect(_on_injury_mask_changed)
		states.append(state)
	return states


func _on_state_armor_depleted(state: BattleSquadState) -> void:
	if state == null or not state.has_unmasked_wound(&"晶体化"):
		return
	var vitals_owner := state.squad_data.get_vitals_source_instance() if state.squad_data != null else null
	if vitals_owner == null or vitals_owner.card_data == null:
		return
	# 晶体化只扣基础生命；正向永久生命成长先作为“额外生命”转成护甲。
	var current_base_health := float(vitals_owner.card_data.max_health - vitals_owner.crystallization_health_loss)
	current_base_health += minf(vitals_owner.get_permanent_growth(OwnedCard.STAT_MAX_HEALTH), 0.0)
	current_base_health -= float(state.buff_stacks.get(&"crystallization_health_loss", 0))
	if current_base_health <= 1.0:
		return
	var health_loss := -1.0
	if state.side == BattleSquadState.Side.PLAYER:
		var health_owner := BattleEffectOwnerRef.for_owned_card_in_state(state, vitals_owner)
		var armor_owner := BattleEffectOwnerRef.for_owned_card_in_state(state, vitals_owner)
		var logical_time_us := roundi(elapsed_seconds * 1000000.0)
		if not record_pending_permanent_growth(
			health_owner,
			BattlePermanentGrowthLedger.STAT_CRYSTALLIZATION_HEALTH_LOSS,
			health_loss,
			&"crystallization_armor_break",
			state.runtime_id,
			logical_time_us
		):
			return
		if not record_pending_permanent_growth(
			armor_owner,
			BattlePermanentGrowthLedger.STAT_BASE_ARMOR,
			1.0,
			&"crystallization_armor_break",
			state.runtime_id,
			logical_time_us
		):
			return
	var runtime_health_loss := BattleModifier.new()
	runtime_health_loss.stat = BattleModifier.Stat.MAX_HEALTH
	runtime_health_loss.mode = BattleModifier.Mode.ADD
	runtime_health_loss.value = health_loss
	runtime_health_loss.effect_id = &"crystallization_armor_break"
	state.modifiers.add_modifier(runtime_health_loss)
	state.buff_stacks[&"crystallization_health_loss"] = int(state.buff_stacks.get(&"crystallization_health_loss", 0)) + 1
	state.current_armor += 1.0


func _on_injury_mask_changed(_state: BattleSquadState, _injury_id: StringName, _masked: bool) -> void:
	_sync_wound_registration_visibility()
	states_changed.emit()


func _sync_wound_registration_visibility() -> void:
	# 战斗效果遮蔽与卡面堆叠遮挡都读取同一份当前有效伤势列表。
	for status: Dictionary in _wound_periodic_effects:
		var state := status.get("state") as BattleSquadState
		var active := state != null and state.get_unmasked_active_injuries().has(status.get("instance_id", &""))
		if active == bool(status.get("active", true)):
			continue
		status["active"] = active
		if not active:
			status["paused_remaining"] = maxf(float(status.get("next_time", INF)) - elapsed_seconds, 0.0)
			status["next_time"] = INF
		else:
			var remaining := float(status.get("paused_remaining", INF))
			if is_finite(remaining):
				status["next_time"] = elapsed_seconds + remaining
				status["paused_remaining"] = INF
	for registration: Dictionary in _wound_registrations:
		var state := registration.get("state") as BattleSquadState
		var active := state != null and state.get_unmasked_active_injuries().has(registration.get("instance_id", &""))
		if active == bool(registration.get("active", true)):
			continue
		registration["active"] = active
		var source_id := int(registration.get("armor_modifier_source_id", 0))
		if state != null and source_id != 0:
			state.modifiers.set_source_instance_active(source_id, active)


func _get_next_cooldown() -> float:
	var next_time := INF
	for state: BattleSquadState in get_all_states():
		if state.alive and state.current_health > 0.0 and not state.is_sleeping(elapsed_seconds):
			next_time = minf(next_time, maxf(state.remaining_cooldown, 0.0))
	return next_time


func _get_next_event_delay() -> float:
	_sync_emblem_registration_visibility()
	_sync_wound_registration_visibility()
	for state: BattleSquadState in get_all_states():
		state.sync_fire_rune_reinforcement_activity()
	var next_time := _get_next_cooldown()
	for spell: OwnedCard in _get_all_prepared_spell_instances():
		if spell == null or spell.card_data == null or _elapsed_spell_attempted.has(spell.instance_id):
			continue
		var attempt_time := get_elapsed_spell_trigger_seconds(spell.card_data)
		if is_finite(attempt_time):
			next_time = minf(next_time, maxf(attempt_time - elapsed_seconds, 0.0))
	for state: BattleSquadState in get_all_states():
		if state.alive and is_finite(state.moon_restore_time):
			next_time = minf(next_time, maxf(state.moon_restore_time - elapsed_seconds, 0.0))
	for registration: Dictionary in _emblem_registrations:
		var state := registration.get("state") as BattleSquadState
		var tick_time := float(registration.get("next_time", INF))
		if state != null and state.alive and is_finite(tick_time):
			next_time = minf(next_time, maxf(tick_time - elapsed_seconds, 0.0))
		var shadow_until := float(registration.get("shadow_until", INF))
		if state != null and state.alive and is_finite(shadow_until):
			next_time = minf(next_time, maxf(shadow_until - elapsed_seconds, 0.0))
	for wound_status: Dictionary in _wound_periodic_effects:
		var wound_state := wound_status.get("state") as BattleSquadState
		if wound_state != null and wound_state.alive and wound_state.get_unmasked_active_injuries().has(wound_status.get("instance_id", &"")):
			next_time = minf(next_time, maxf(float(wound_status.get("next_time", INF)) - elapsed_seconds, 0.0))
	for state: BattleSquadState in get_all_states():
		if state.alive:
			for until_value: Variant in state.sleep_source_until.values():
				next_time = minf(next_time, maxf(float(until_value) - elapsed_seconds, 0.0))
	var next_effect_time := effect_runtime.get_next_event_time_seconds()
	if is_finite(next_effect_time):
		next_time = minf(next_time, maxf(next_effect_time - elapsed_seconds, 0.0))
	for event_value: Variant in _pending_projectile_contexts:
		var event := event_value as BattleEffectEvent
		next_time = minf(next_time, maxf(event.impact_time - elapsed_seconds, 0.0))
	next_time = minf(next_time, maxf(_next_fatigue_stack_seconds - elapsed_seconds, 0.0))
	next_time = minf(next_time, maxf(_next_fatigue_damage_seconds - elapsed_seconds, 0.0))
	for status: Dictionary in active_continuous_effects:
		next_time = minf(next_time, maxf(float(status["next_time"]) - elapsed_seconds, 0.0))
	return next_time


func _decrease_living_cooldowns(amount: float) -> void:
	for state: BattleSquadState in get_all_states():
		if state.alive and not state.is_sleeping(elapsed_seconds):
			state.advance_action_cooldown(amount)


func _resolve_ready_batch() -> void:
	_sync_emblem_registration_visibility()
	_sync_wound_registration_visibility()
	for state: BattleSquadState in get_all_states():
		state.sync_fire_rune_reinforcement_activity()
	_expire_emblem_shadows()
	for state: BattleSquadState in get_all_states():
		state.expire_sleep_sources(elapsed_seconds)
		if state.alive and state.moon_restore_time <= elapsed_seconds + COOLDOWN_EPSILON:
			state.moon_shadowed = state.squad_data.has_indicator(CelestialIndicator.Kind.MOON)
			state.moon_restore_time = INF
	effect_runtime.process_due(elapsed_seconds)
	_resolve_due_prepared_spells()
	if use_projectile_timing:
		_resolve_ready_projectile_batch()
		return
	recalculate_logical_layout()
	var living_snapshot := get_all_states().filter(
		func(state: BattleSquadState) -> bool:
			return state.alive and state.current_health > 0.0
	)
	var actors: Array[BattleSquadState] = []
	for state: BattleSquadState in living_snapshot:
		if state.remaining_cooldown <= COOLDOWN_EPSILON and not state.is_sleeping(elapsed_seconds):
			actors.append(state)
	actors.sort_custom(_is_actor_before)
	var actions := _select_base_actions(actors, living_snapshot)
	for action: Dictionary in actions:
		_on_indicator_action_launched(action["actor"])
		effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": action["actor"]})
		_apply_emblem_echo_effects(action["actor"])
		_apply_wound_echo_effects(action["actor"])
	var layer_zero: Array[BattleEffectEvent] = _collect_due_continuous_events()
	layer_zero.append_array(_collect_due_emblem_events())
	layer_zero.append_array(_collect_due_wound_periodic_events())
	var fatigue_events := _prepare_fatigue_events(living_snapshot)
	layer_zero.append_array(fatigue_events)
	for action: Dictionary in actions:
		layer_zero.append(action["base_event"] as BattleEffectEvent)
	_resolve_effect_layer(layer_zero)
	for event: BattleEffectEvent in fatigue_events:
		direct_damage_resolved.emit(event.target, BattleRules.FATIGUE_BUFF_ID, roundi(event.effective_amount))

	var carriers_by_action: Array[Array] = []
	for action: Dictionary in actions:
		carriers_by_action.append([action["base_event"] as BattleEffectEvent])
	# 两个元素组最多形成两个额外逻辑层。每层必须先为全部行动者选完目标，
	# 才统一执行数值，不能让 actions 数组顺序形成隐性先手。
	for group_index: int in 2:
		var layer_events: Array[BattleEffectEvent] = []
		if group_index == 0:
			layer_events.append_array(_build_due_continuous_followups())
		var next_carriers: Array[Array] = []
		next_carriers.resize(actions.size())
		for action_index: int in actions.size():
			var action: Dictionary = actions[action_index]
			var groups := action["element_groups"] as Array
			var action_events: Array[BattleEffectEvent] = []
			if group_index < groups.size():
				for carrier_value: Variant in carriers_by_action[action_index]:
					action_events.append_array(_build_element_events(action, carrier_value as BattleEffectEvent, groups[group_index], group_index + 1))
			elif group_index == 0 and (action["pattern"] as RunePatternResult).pattern_type == RunePatternResult.PatternType.STRAIGHT:
				action_events.append_array(_build_straight_bonus_events(action, action["base_event"] as BattleEffectEvent, group_index + 1))
			next_carriers[action_index] = action_events
			layer_events.append_array(action_events)
		_resolve_effect_layer(layer_events)
		carriers_by_action = next_carriers
		recalculate_logical_layout()

	_finalize_batch()
	batch_count += 1
	states_changed.emit()
	_check_battle_result()


func _resolve_ready_projectile_batch() -> void:
	## 固定逻辑时轴先处理已到达弹道，再处理同刻计时事件和新行动。
	recalculate_logical_layout()
	_resolve_due_projectile_impacts()
	if not _running:
		return
	_resolve_due_prepared_spells()
	var living_snapshot := get_all_states().filter(
		func(state: BattleSquadState) -> bool:
			return state.alive and state.current_health > 0.0
	)
	var actors: Array[BattleSquadState] = []
	for state: BattleSquadState in living_snapshot:
		if state.remaining_cooldown <= COOLDOWN_EPSILON and not state.is_sleeping(elapsed_seconds):
			actors.append(state)
	actors.sort_custom(_is_actor_before)
	var actions := _select_base_actions(actors, living_snapshot)
	var immediate_events: Array[BattleEffectEvent] = _collect_due_continuous_events()
	immediate_events.append_array(_collect_due_emblem_events())
	immediate_events.append_array(_collect_due_wound_periodic_events())
	var fatigue_events := _prepare_fatigue_events(living_snapshot)
	immediate_events.append_array(fatigue_events)
	if actions.is_empty() and immediate_events.is_empty():
		return
	_resolve_effect_layer(immediate_events)
	for event: BattleEffectEvent in fatigue_events:
		direct_damage_resolved.emit(event.target, BattleRules.FATIGUE_BUFF_ID, roundi(event.effective_amount))
	if actions.is_empty():
		_finalize_batch()
		batch_count += 1
		states_changed.emit()
		_check_battle_result()
		return
	var projectile_batch_id := _next_projectile_batch_id
	_next_projectile_batch_id += 1
	_pending_projectile_batch_counts[projectile_batch_id] = 0
	var base_events: Array[BattleEffectEvent] = []
	for action: Dictionary in actions:
		var event := action["base_event"] as BattleEffectEvent
		_register_projectile(event, action, 0, projectile_batch_id)
		base_events.append(event)
	if base_events.is_empty():
		_complete_projectile_batch(projectile_batch_id)
		return
	_launch_registered_projectiles(base_events)


func _resolve_projectile_impact(event: BattleEffectEvent) -> void:
	if not _pending_projectile_contexts.has(event):
		return
	var context := _pending_projectile_contexts[event] as Dictionary
	var projectile_batch_id := int(context["projectile_batch_id"])
	_pending_projectile_contexts.erase(event)
	_pending_projectile_batch_counts[projectile_batch_id] = int(_pending_projectile_batch_counts[projectile_batch_id]) - 1
	event.timestamp = elapsed_seconds
	_resolve_arrived_event(event)
	var followups := _build_projectile_followups(event, context)
	for followup: BattleEffectEvent in followups:
		_register_projectile(
			followup,
			context["action"] as Dictionary,
			int(context["next_group_index"]) + 1,
			projectile_batch_id
		)
	if not followups.is_empty():
		_launch_registered_projectiles(followups)
	if int(_pending_projectile_batch_counts.get(projectile_batch_id, 0)) <= 0:
		_complete_projectile_batch(projectile_batch_id)


func _resolve_due_projectile_impacts() -> void:
	var due_events: Array[BattleEffectEvent] = []
	for event_value: Variant in _pending_projectile_contexts:
		var event := event_value as BattleEffectEvent
		if event.impact_time <= elapsed_seconds + COOLDOWN_EPSILON:
			due_events.append(event)
	due_events.sort_custom(func(left: BattleEffectEvent, right: BattleEffectEvent) -> bool:
		if not is_equal_approx(left.impact_time, right.impact_time):
			return left.impact_time < right.impact_time
		return left.launch_sequence < right.launch_sequence
	)
	for event: BattleEffectEvent in due_events:
		_resolve_projectile_impact(event)


func _register_projectile(event: BattleEffectEvent, action: Dictionary, next_group_index: int, projectile_batch_id: int) -> void:
	event.launch_sequence = _next_projectile_launch_sequence
	_next_projectile_launch_sequence += 1
	event.projectile_speed_variant = _random.randi_range(
		0,
		BattleProjectileTiming.TRAVEL_SPEED_VARIANT_COUNT - 1
	)
	var profile := BattleAttackEffectProfiles.get_profile(_visual_kind_for_event(event))
	event.projectile_impact_delay = BattleProjectileTiming.calculate_impact_delay(
		profile,
		event.projectile_speed_variant
	)
	event.impact_time = elapsed_seconds + event.projectile_impact_delay
	_pending_projectile_contexts[event] = {
		"action": action,
		"next_group_index": next_group_index,
		"projectile_batch_id": projectile_batch_id,
	}
	_pending_projectile_batch_counts[projectile_batch_id] = int(_pending_projectile_batch_counts.get(projectile_batch_id, 0)) + 1


func _launch_registered_projectiles(events: Array[BattleEffectEvent]) -> void:
	for event: BattleEffectEvent in events:
		if event.effect_kind == BattleEffectEvent.EffectKind.PLACEHOLDER:
			_resolve_projectile_impact(event)
		else:
			projectile_launched.emit(event)
			if event.is_base_action:
				var context := _pending_projectile_contexts.get(event, {}) as Dictionary
				var action := context.get("action", {}) as Dictionary
				if not action.is_empty():
					_record_chaos_pattern_participation(
						event.source,
						action.get("pattern") as RunePatternResult
					)
				_on_indicator_action_launched(event.source)
				effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": event.source})
				_apply_emblem_echo_effects(event.source)
				_apply_wound_echo_effects(event.source)
				effect_runtime.process_due(elapsed_seconds)


func _resolve_arrived_event(event: BattleEffectEvent) -> void:
	if event.resource_target != null:
		if event.resource_target.destroyed or event.resource_target.current_health <= 0:
			event.missed = true
			event.effective_amount = 0.0
			_ensure_formula_source_snapshots(event)
			effect_resolved.emit(event)
			if event.is_base_action:
				action_resolved.emit(event.source, null, event.action_type, 0)
			return
		_apply_effect_event(event)
		return
	# 生命归零、正式退场或放逐都会让已锁定的主效果命中空位；元素链仍以原锚点继续判断。
	if event.target == null or not event.target.alive or event.target.current_health <= 0.0:
		event.missed = true
		event.effective_amount = 0.0
		_ensure_formula_source_snapshots(event)
		effect_resolved.emit(event)
		if event.is_base_action:
			action_resolved.emit(event.source, event.target, event.action_type, 0)
		return
	_apply_effect_event(event)


func _build_projectile_followups(event: BattleEffectEvent, context: Dictionary) -> Array[BattleEffectEvent]:
	if event.resource_target != null:
		return []
	var action := context["action"] as Dictionary
	var group_index := int(context["next_group_index"])
	var groups := action["element_groups"] as Array
	if group_index < groups.size():
		return _build_element_events(action, event, groups[group_index], group_index + 1)
	if group_index == 0 and (action["pattern"] as RunePatternResult).pattern_type == RunePatternResult.PatternType.STRAIGHT:
		return _build_straight_bonus_events(action, event, 1)
	return []


func _complete_projectile_batch(projectile_batch_id: int) -> void:
	_pending_projectile_batch_counts.erase(projectile_batch_id)
	_finalize_batch()
	batch_count += 1
	states_changed.emit()
	if _pending_projectile_contexts.is_empty():
		_check_battle_result()


func _select_base_actions(actors: Array[BattleSquadState], living_snapshot: Array) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for actor: BattleSquadState in actors:
		if actor.skip_next_ordinary_action:
			actor.skip_next_ordinary_action = false
			actor.reset_action_cooldown()
			continue
		var blind_result := _roll_action_blindness(actor)
		if bool(blind_result.get("failed", false)):
			actor.reset_action_cooldown()
			continue
		var action := _build_action(
			actor,
			living_snapshot,
			actor.get_effective_action_type(),
			float(blind_result.get("reinforcement", 0)),
			{
				"source_kind": "wound_action_roll",
				"source_name": "致盲行动掷骰",
				"amount": int(blind_result.get("reinforcement", 0)),
			}
		)
		if not action.is_empty():
			_consume_reinforcement_for_action(actor, action)
			actions.append(action)
			_clear_emblem_shadows_for_state(actor)
			if actor.has_unmasked_wound(&"内伤Ⅲ"):
				actor.skip_next_ordinary_action = true
		actor.reset_action_cooldown()
	return actions


func _roll_action_blindness(actor: BattleSquadState) -> Dictionary:
	var reinforcement := 0
	for wound_id: StringName in _get_unmasked_wound_ids(actor):
		var sides := 0
		var failure_below := 0
		var success_above := 6
		var success_reinforcement := 0
		match wound_id:
			&"致盲Ⅰ":
				sides = 8
				failure_below = 3
				success_reinforcement = 2
			&"致盲Ⅱ":
				sides = 8
				failure_below = 4
				success_reinforcement = 3
		if sides <= 0:
			continue
		var roll_result := _roll_probability(actor, sides, 1)
		var roll := int(roll_result.get("total", 0))
		if roll < failure_below:
			return {"failed": true, "reinforcement": 0, "roll": roll, "wound_id": wound_id, "roll_result": roll_result}
		if roll > success_above:
			reinforcement += success_reinforcement
	return {"failed": false, "reinforcement": reinforcement}


func notify_spell_triggered(spell_instance_id: StringName, activation_index: int) -> bool:
	# 法术执行器以稳定实例与触发序号调用；重复通知同一释放不会重复启咒。
	if spell_instance_id.is_empty() or activation_index < 0 or current_result != Result.NONE:
		return false
	var spell_event_id := StringName("%s:spell:%s:%d" % [battle_instance_id, spell_instance_id, activation_index])
	if _processed_spell_event_ids.has(spell_event_id):
		return false
	_processed_spell_event_ids[spell_event_id] = true
	var third_tier_squads: Dictionary = {}
	for registration: Dictionary in _wound_registrations:
		var state := registration.get("state") as BattleSquadState
		var instance_id := registration.get("instance_id", &"") as StringName
		if state == null or not state.get_unmasked_active_injuries().has(instance_id):
			continue
		var definition := registration.get("definition", {}) as Dictionary
		var damage := int(definition.get("spell_damage", 0))
		var reinforcement := int(definition.get("spell_reinforcement", 0))
		if damage <= 0 or reinforcement <= 0:
			continue
		_emit_wound_damage(
			state,
			state,
			float(damage),
			registration.get("wound_id", &"魔痕") as StringName,
			"wound_magic_mark",
			_take_group_id(),
			false
		)
		_add_status_reinforcement(state, registration, reinforcement, "启咒", "魔痕强化")
		if int(definition.get("spell_stun_every", 0)) > 0:
			third_tier_squads[state.runtime_id] = {
				"state": state,
				"registration": registration,
				"every": int(definition.get("spell_stun_every", 0)),
				"duration": float(definition.get("spell_stun_duration", 0.0)),
			}
	for runtime_id: int in third_tier_squads:
		var stun: Dictionary = third_tier_squads[runtime_id]
		var state := stun.get("state") as BattleSquadState
		var registration := stun.get("registration", {}) as Dictionary
		if state == null:
			continue
		var count := int(state.buff_stacks.get(&"magic_mark_spell_count", 0)) + 1
		var every := maxi(int(stun.get("every", 5)), 1)
		if count >= every:
			count -= every
			var instance_id := registration.get("instance_id", &"") as StringName
			state.apply_sleep(StringName("magic_mark_stun:%s" % instance_id), elapsed_seconds + float(stun.get("duration", 3.0)))
		state.buff_stacks[&"magic_mark_spell_count"] = count
	return true


func _resolve_opening_spell(spell: OwnedCard, side: int) -> bool:
	if spell == null or spell.card_data == null:
		return false
	match spell.card_data.id:
		&"side_by_side":
			var recipients := get_living_states(side)
			if recipients.is_empty():
				return false
			if not notify_spell_triggered(spell.instance_id, 0):
				return false
			for state: BattleSquadState in recipients:
				_side_by_side_grants.append({
					"spell_instance_id": spell.instance_id,
					"state": state,
				})
			return true
		_:
			return false


func _resolve_due_prepared_spells() -> void:
	for spell: OwnedCard in _get_all_prepared_spell_instances():
		if (
			spell == null
			or spell.card_data == null
			or _elapsed_spell_attempted.has(spell.instance_id)
		):
			continue
		var attempt_time := get_elapsed_spell_trigger_seconds(spell.card_data)
		if not is_finite(attempt_time) or elapsed_seconds + COOLDOWN_EPSILON < attempt_time:
			continue
		_elapsed_spell_attempted[spell.instance_id] = true
		_resolve_elapsed_spell(spell)


func get_elapsed_spell_trigger_seconds(card: CardData) -> float:
	if card == null or effect_catalog == null:
		return INF
	var earliest_time := INF
	for effect_id: StringName in card.effect_ids:
		var definition := effect_catalog.get_definition(effect_id)
		if definition == null or definition.trigger != BattleEffectDefinition.Trigger.ELAPSED_BATTLE_TIME:
			continue
		var trigger_time := float(definition.parameters.get("at_seconds", INF))
		if trigger_time >= 0.0:
			earliest_time = minf(earliest_time, trigger_time)
	return earliest_time


func _resolve_elapsed_spell(spell: OwnedCard) -> void:
	var side := int(_spell_side_by_instance.get(spell.instance_id, BattleSquadState.Side.PLAYER))
	for effect_index: int in spell.card_data.effect_ids.size():
		var definition := effect_catalog.get_definition(spell.card_data.effect_ids[effect_index])
		if (
			definition == null
			or definition.trigger != BattleEffectDefinition.Trigger.ELAPSED_BATTLE_TIME
			or elapsed_seconds + COOLDOWN_EPSILON < float(definition.parameters.get("at_seconds", INF))
		):
			continue
		var did_resolve := false
		if (
			definition.operation == BattleEffectDefinition.Operation.IMMEDIATE_ACTION
			and definition.target == BattleEffectDefinition.Target.BACK_ROW_RANGED_ALLIES
		):
			var allies := _get_ranged_back_row_allies(side)
			if not allies.is_empty():
				did_resolve = notify_spell_triggered(spell.instance_id, effect_index)
				if did_resolve:
					for ally: BattleSquadState in allies:
						execute_immediate_action(ally, CardData.ActionType.RANGED)
		elif (
			definition.operation == BattleEffectDefinition.Operation.REVIVE
			and definition.target == BattleEffectDefinition.Target.LATEST_DEAD_NONDERIVED_ALLY
		):
			var target := _get_latest_dead_nonderived_ally(side)
			if target != null and _revive_prepared_spell_target(target):
				did_resolve = notify_spell_triggered(spell.instance_id, effect_index)
		if did_resolve:
			_present_nonpausing_spell(spell)
			return


func _present_nonpausing_spell(spell: OwnedCard) -> void:
	if spell == null or spell.card_data == null:
		return
	spell_cast_started.emit(
		spell,
		_battle_generation,
		OPENING_SPELL_PRESENTATION_SECONDS
	)


func _get_all_prepared_spell_instances() -> Array[OwnedCard]:
	var result: Array[OwnedCard] = []
	result.append_array(_prepared_spell_instances)
	result.append_array(_enemy_prepared_spell_instances)
	return result


func _has_living_ranged_back_row_ally(side: int) -> bool:
	return not _get_ranged_back_row_allies(side).is_empty()


func _get_ranged_back_row_allies(side: int) -> Array[BattleSquadState]:
	var result: Array[BattleSquadState] = []
	for state: BattleSquadState in get_living_states(side):
		if is_back_row(state.row_key) and state.get_effective_action_type() == CardData.ActionType.RANGED:
			result.append(state)
	result.sort_custom(_is_actor_before)
	return result


func _get_latest_dead_nonderived_ally(side: int) -> BattleSquadState:
	for index: int in range(_death_history.size() - 1, -1, -1):
		var entry: Dictionary = _death_history[index]
		var state := entry.get("state") as BattleSquadState
		if (
			state != null
			and state.side == side
			and not state.alive
			and state.current_health <= 0.0
			and not _is_derived_state(state)
		):
			return state
	return null


func _is_derived_state(state: BattleSquadState) -> bool:
	if state == null or state.squad_data == null:
		return false
	for card: CardData in state.squad_data.horizontal_cards:
		if card != null and card.is_derived:
			return true
	return false


func _revive_prepared_spell_target(target: BattleSquadState) -> bool:
	if target == null or target.alive or target.current_health > 0.0:
		return false
	var original_index := target.formation_index
	var row_units := target.squad_data.get_unit_count() if target.squad_data != null else 0
	var position_is_open := true
	for state: BattleSquadState in get_living_states(target.side):
		if state.row_key == target.row_key and state.squad_data != null:
			row_units += state.squad_data.get_unit_count()
		if state.row_key == target.row_key and state.formation_index == original_index:
			position_is_open = false
	if row_units > 21:
		return false
	if not position_is_open:
		var rightmost_index := original_index
		for state: BattleSquadState in get_living_states(target.side):
			if state.row_key == target.row_key:
				rightmost_index = maxi(rightmost_index, state.formation_index)
		target.formation_index = rightmost_index + 1
	var revived := revive_state_at_original_position(
		target,
		float(target.get_max_health()) * 0.5,
		false
	)
	if not revived:
		target.formation_index = original_index
	return revived


func _roll_probability(state: BattleSquadState, sides: int, dice_count: int = 1) -> Dictionary:
	if state == null or sides <= 0 or dice_count <= 0:
		return {"faces": [], "total": 0, "candidate_sets": [], "advantage_delta": 0}
	var advantage_count := _has_emblem_effect(state, &"advantage_dice").size()
	var misfortune_registrations: Array[Dictionary] = []
	var active_wounds := state.get_unmasked_active_injuries()
	for registration: Dictionary in _wound_registrations:
		if registration.get("state") == state \
			and registration.get("wound_id") == &"厄运缠身" \
			and active_wounds.has(registration.get("instance_id", &"")):
			misfortune_registrations.append(registration)
	var advantage_delta := advantage_count - misfortune_registrations.size()
	var candidate_count := absi(advantage_delta) + 1
	var candidate_sets: Array[Array] = []
	var candidate_totals: Array[int] = []
	for _candidate_index: int in candidate_count:
		var faces: Array[int] = []
		var total := 0
		for _die_index: int in dice_count:
			var face := _random.randi_range(1, sides)
			faces.append(face)
			total += face
		candidate_sets.append(faces)
		candidate_totals.append(total)
	var adopted_index := 0
	for index: int in range(1, candidate_totals.size()):
		if advantage_delta > 0 and candidate_totals[index] > candidate_totals[adopted_index]:
			adopted_index = index
		elif advantage_delta < 0 and candidate_totals[index] < candidate_totals[adopted_index]:
			adopted_index = index
	var adopted_faces: Array[int] = candidate_sets[adopted_index]
	var result := {
		"faces": adopted_faces.duplicate(),
		"total": candidate_totals[adopted_index],
		"candidate_sets": candidate_sets.duplicate(true),
		"advantage_delta": advantage_delta,
	}
	if not misfortune_registrations.is_empty() and state.side == BattleSquadState.Side.PLAYER:
		_record_misfortune_roll(state, misfortune_registrations, adopted_faces)
	var roll_id := _next_probability_roll_sequence
	_next_probability_roll_sequence += 1
	_emit_probability_roll_log(state, sides, dice_count, result, roll_id)
	return result


func _record_misfortune_roll(
	state: BattleSquadState,
	registrations: Array[Dictionary],
	adopted_faces: Array[int]
) -> void:
	var ones := 0
	for face: int in adopted_faces:
		if face == 1:
			ones += 1
	var logical_time_us := roundi(elapsed_seconds * 1000000.0)
	for registration: Dictionary in registrations:
		var owner := registration.get("owner") as OwnedCard
		if owner == null:
			continue
		var instance_id := registration.get("instance_id", &"") as StringName
		var counter_key := StringName("misfortune:%s" % instance_id)
		var count := int(owner.wound_battle_counters.get(counter_key, 0))
		if ones > 0:
			count += ones
			while count >= 3:
				var reward_owner := BattleEffectOwnerRef.for_state(
					state,
					BattleEffectDefinition.OwnerKind.OWNING_PLAYER
				)
				if not record_pending_run_reward(
					reward_owner,
					BattleRunRewardLedger.KIND_GOLD,
					30,
					&"wound_misfortune",
					state.runtime_id,
					logical_time_us,
					{"wound_instance_id": instance_id, "counter_key": counter_key}
				):
					break
				count -= 3
		else:
			count = 0
		if not record_pending_wound_battle_counter(
			BattleEffectOwnerRef.for_owned_card_in_state(state, owner),
			counter_key,
			count,
			&"wound_misfortune_roll",
			state.runtime_id,
			logical_time_us
		):
			continue
		owner.wound_battle_counters[counter_key] = count


func _emit_probability_roll_log(
	state: BattleSquadState,
	sides: int,
	dice_count: int,
	roll_result: Dictionary,
	roll_id: int
) -> void:
	var source := state.get_action_source()
	var candidate_strings: Array[String] = []
	for value: Variant in roll_result.get("candidate_sets", []):
		var faces := value as Array
		candidate_strings.append("[%s]" % ",".join(_int_array_to_strings(faces)))
	var adopted_faces := roll_result.get("faces", []) as Array
	special_effect_resolved.emit({
		"kind": "roll",
		"roll_id": roll_id,
		"logical_time_seconds": elapsed_seconds,
		"source_card_name": source.display_name if source != null else "未知来源",
		"target_card_name": "结果%d" % int(roll_result.get("total", 0)),
		"effect_reading": "%dd%d 候选 %s；采用 [%s]，总和%d%s" % [
			dice_count,
			sides,
			" / ".join(candidate_strings),
			",".join(_int_array_to_strings(adopted_faces)),
			int(roll_result.get("total", 0)),
			"（优势）" if int(roll_result.get("advantage_delta", 0)) > 0 else ("（劣势）" if int(roll_result.get("advantage_delta", 0)) < 0 else ""),
		],
		"source_status": "resolved",
	})


func _int_array_to_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(int(value)))
	return result


func _get_unmasked_wound_ids(state: BattleSquadState) -> Array[StringName]:
	var result: Array[StringName] = []
	if state == null or state.squad_data == null:
		return result
	var active_ids := state.get_unmasked_active_injuries()
	for slot: Dictionary in state.squad_data.get_visible_wound_slots():
		var owner := state.squad_data.get_owned_card(slot.get("card") as CardData)
		var slot_index := int(slot.get("slot_index", -1))
		if owner == null or slot_index < 0 or slot_index >= owner.wound_slots.size():
			continue
		var injury_id := StringName("%s:wound:%d" % [owner.instance_id, slot_index])
		if not active_ids.has(injury_id):
			continue
		var wound_id := StringName(String(owner.wound_slots[slot_index].get("wound_id", "")))
		if not wound_id.is_empty():
			result.append(wound_id)
	return result


func execute_immediate_action(
	actor: BattleSquadState,
	action_type: CardData.ActionType,
	reinforcement_delta: float = 0.0,
	reinforcement_source: Dictionary = {}
) -> bool:
	if actor == null or not actor.alive or actor.current_health <= 0.0:
		return false
	var living_snapshot := get_all_states().filter(
		func(state: BattleSquadState) -> bool:
			return state.alive and state.current_health > 0.0
	)
	var reinforcement_modifier: BattleModifier
	if not is_zero_approx(reinforcement_delta):
		reinforcement_modifier = _add_immediate_action_reinforcement(
			actor,
			reinforcement_delta,
			reinforcement_source
		)
	var action := _build_action(actor, living_snapshot, action_type)
	if action.is_empty():
		if reinforcement_modifier != null:
			actor.modifiers.remove_modifier_ids([reinforcement_modifier.modifier_id])
		return false
	_consume_reinforcement_for_action(actor, action)
	_clear_emblem_shadows_for_state(actor)
	actor.reset_action_cooldown()
	var base_event := action["base_event"] as BattleEffectEvent
	if use_projectile_timing:
		var projectile_batch_id := _next_projectile_batch_id
		_next_projectile_batch_id += 1
		_pending_projectile_batch_counts[projectile_batch_id] = 0
		_register_projectile(base_event, action, 0, projectile_batch_id)
		_launch_registered_projectiles([base_event])
		return true
	# 无弹道计时时仍发出“已发射”信号，再同步结算命中，保持事件语义一致。
	projectile_launched.emit(base_event)
	_record_chaos_pattern_participation(actor, action.get("pattern") as RunePatternResult)
	_on_indicator_action_launched(actor)
	effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": actor})
	_apply_emblem_echo_effects(actor)
	_apply_wound_echo_effects(actor)
	effect_runtime.process_due(elapsed_seconds)
	_resolve_effect_layer([base_event])
	var carriers: Array[BattleEffectEvent] = [base_event]
	var groups := action["element_groups"] as Array
	for group_index: int in 2:
		var layer_events: Array[BattleEffectEvent] = []
		if group_index < groups.size():
			for carrier: BattleEffectEvent in carriers:
				layer_events.append_array(_build_element_events(action, carrier, groups[group_index], group_index + 1))
		elif group_index == 0 and (action["pattern"] as RunePatternResult).pattern_type == RunePatternResult.PatternType.STRAIGHT:
			layer_events.append_array(_build_straight_bonus_events(action, base_event, 1))
		_resolve_effect_layer(layer_events)
		carriers.assign(layer_events)
	_finalize_batch()
	batch_count += 1
	states_changed.emit()
	_check_battle_result()
	return true


func _add_immediate_action_reinforcement(
	actor: BattleSquadState,
	amount: float,
	source: Dictionary
) -> BattleModifier:
	var modifier := BattleModifier.new()
	modifier.stat = BattleModifier.Stat.REINFORCEMENT
	modifier.mode = BattleModifier.Mode.ADD
	modifier.value = amount
	modifier.source_instance_id = int(source.get("effect_instance_id", 0))
	modifier.effect_id = StringName(String(source.get("effect_id", "immediate_action_reinforcement")))
	modifier.source_runtime_id = int(source.get("source_runtime_id", actor.runtime_id))
	modifier.contribution_sources.append({
		"role": "强化",
		"amount": amount,
		"source_name": String(source.get("source_name", "突击")),
		"source_card_name": String(source.get("source_card_name", "未知来源")),
		"source_card_id": String(source.get("source_card_id", "")),
		"source_owned_card_instance_id": String(source.get("source_owned_card_instance_id", "")),
		"trigger_name": String(source.get("trigger_name", "突击")),
		"source_status": String(source.get("source_status", "resolved")),
	})
	return actor.modifiers.add_modifier(modifier)


func _build_action(
	actor: BattleSquadState,
	living_snapshot: Array,
	action_type: CardData.ActionType,
	action_value_delta: float = 0.0,
	action_value_source: Dictionary = {}
) -> Dictionary:
	if actor.get_action_source() == null:
		return {}
	var candidates: Array[BattleSquadState] = []
	for value: Variant in living_snapshot:
		var candidate := value as BattleSquadState
		if _is_base_candidate(actor, candidate, action_type):
			candidates.append(candidate)
	if action_type == CardData.ActionType.HEAL:
		var wounded: Array[BattleSquadState] = []
		for candidate: BattleSquadState in candidates:
			if candidate.current_health < float(candidate.get_max_health()):
				wounded.append(candidate)
		if not wounded.is_empty():
			var largest_missing_ratio := -1.0
			for candidate: BattleSquadState in wounded:
				largest_missing_ratio = maxf(largest_missing_ratio, _missing_health_ratio(candidate))
			candidates.clear()
			for candidate: BattleSquadState in wounded:
				if is_equal_approx(_missing_health_ratio(candidate), largest_missing_ratio):
					candidates.append(candidate)
	var confused_random_target := false
	if actor.has_unmasked_wound(&"混乱"):
		confused_random_target = _random.randi_range(0, 1) == 0
		if confused_random_target:
			candidates.clear()
			for value: Variant in living_snapshot:
				var living_target := value as BattleSquadState
				if living_target == null or not living_target.alive or living_target.current_health <= 0.0:
					continue
				if (
					living_target.side != actor.side
					and (living_target.moon_shadowed or living_target.has_runtime_keyword(&"emblem_shadow"))
				):
					continue
				candidates.append(living_target)
	var target: BattleSquadState
	var resource_target: RefCounted
	var mining_forced := false
	var mining_candidates: Array[RefCounted] = []
	var mining_uses_left := int(mining_actions_remaining_by_runtime_id.get(actor.runtime_id, 0))
	if mining_uses_left > 0:
		for resource_side: Array in [player_resource_states, enemy_resource_states]:
			for resource: RefCounted in resource_side:
				if not resource.destroyed and resource.current_health > 0: mining_candidates.append(resource)
	if not mining_candidates.is_empty():
		resource_target = mining_candidates[_random.randi_range(0, mining_candidates.size() - 1)]
		mining_forced = true
	if mining_forced:
		target = null
	elif confused_random_target:
		target = candidates[_random.randi_range(0, candidates.size() - 1)] if not candidates.is_empty() else null
	elif action_type in [CardData.ActionType.MELEE, CardData.ActionType.RANGED, CardData.ActionType.MAGIC]:
		# 普通攻击能把敌我两侧资源都作为独立中立目标参与权重选择。
		var resources: Array[RefCounted] = []
		resources.append_array(player_resource_states)
		resources.append_array(enemy_resource_states)
		var target_choice := _choose_attack_target_with_resources(actor, candidates, resources)
		target = target_choice.get("target") as BattleSquadState
		resource_target = target_choice.get("resource_target") as RefCounted
	else:
		target = choose_base_target(actor, candidates, action_type)
	if target == null and resource_target == null:
		return {}
	var concussion_bonus := 0.0
	var concussion_rolls: Array[int] = []
	for wound_id: StringName in _get_unmasked_wound_ids(actor):
		if wound_id == &"脑震荡":
			var concussion_result := _roll_probability(actor, 10, 1)
			var concussion_roll := int(concussion_result.get("total", 0))
			concussion_bonus += concussion_roll
			concussion_rolls.append(concussion_roll)
	var wound_action_source := action_value_source.duplicate(true)
	if concussion_bonus > 0.0:
		wound_action_source["source_kind"] = "wound_action_roll"
		wound_action_source["source_name"] = "伤势行动掷骰"
		wound_action_source["amount"] = float(wound_action_source.get("amount", 0.0)) + concussion_bonus
		wound_action_source["roll_results"] = concussion_rolls.duplicate()
	var pattern := actor.get_rune_pattern_result()
	var action := {
		"actor": actor,
		"target": target,
		"resource_target": resource_target,
		"is_mining": mining_forced,
		"action_type": action_type,
		"pattern": pattern,
		"group_id": _take_group_id(),
		"action_value_delta": action_value_delta + concussion_bonus,
		"action_value_source": wound_action_source,
	}
	var groups: Array[Dictionary] = []
	if resource_target == null:
		groups = BattleElementResolver.get_element_groups(pattern)
	action["element_groups"] = groups
	var pierces := not groups.is_empty() and int(groups[0]["element"]) == CardData.ElementType.WOOD and int(groups[0]["count"]) == 5 and action_type in [CardData.ActionType.MELEE, CardData.ActionType.RANGED, CardData.ActionType.MAGIC]
	action["base_event"] = _make_value_event(action, target, 1.0, 0, true, pierces)
	if resource_target != null:
		if mining_forced:
			mining_actions_remaining_by_runtime_id[actor.runtime_id] = mining_uses_left - 1
		var resource_event := action["base_event"] as BattleEffectEvent
		resource_event.resource_target = resource_target
		resource_event.is_mining = mining_forced
		resource_event.effect_kind = BattleEffectEvent.EffectKind.DAMAGE
		resource_event.uses_attack_type_multiplier = false
		resource_event.exact_amount = float(resource_target.current_health) if mining_forced else 1.0
		resource_event.visual_kind = &"resource_mining" if mining_forced else &"resource_attack"
		resource_event.formula = BattleFormulaData.new()
		resource_event.formula.display_name = "开采" if mining_forced else "资源固定伤害"
		resource_event.formula.exact_result = resource_event.exact_amount
	if resource_target == null:
		_apply_primary_healing_wound_bonus(action["base_event"] as BattleEffectEvent, actor, action_type)
	return action


func _apply_primary_healing_wound_bonus(
	event: BattleEffectEvent,
	actor: BattleSquadState,
	action_type: CardData.ActionType
) -> void:
	if event == null or event.formula == null or actor == null or action_type != CardData.ActionType.HEAL:
		return
	var bonus := 0
	var contributing_wounds: Array[String] = []
	for wound_id: StringName in _get_unmasked_wound_ids(actor):
		match wound_id:
			&"内伤Ⅰ": bonus += 1
			&"内伤Ⅱ": bonus += 2
			&"内伤Ⅲ": bonus += 3
		if wound_id in [&"内伤Ⅰ", &"内伤Ⅱ", &"内伤Ⅲ"]:
			contributing_wounds.append(String(wound_id))
	if bonus <= 0:
		return
	event.formula.final_flat_bonus += bonus
	event.formula.final_flat_bonus_sources.append({
		"source_kind": "wound_primary_healing_bonus",
		"source_name": ", ".join(contributing_wounds),
		"amount": bonus,
		"source_status": "resolved",
	})
	event.formula.exact_result = maxf(event.formula.calculate_result(), 0.0)
	event.exact_amount = event.formula.exact_result


func _missing_health_ratio(state: BattleSquadState) -> float:
	if state == null or state.get_max_health() <= 0:
		return 0.0
	return clampf(1.0 - state.current_health / float(state.get_max_health()), 0.0, 1.0)


func _is_actor_before(left: BattleSquadState, right: BattleSquadState) -> bool:
	if left.side != right.side:
		return left.side == BattleSquadState.Side.PLAYER
	var left_back := is_back_row(left.row_key)
	var right_back := is_back_row(right.row_key)
	if left_back != right_back:
		return not left_back
	return left.formation_index < right.formation_index


func _is_base_candidate(actor: BattleSquadState, candidate: BattleSquadState, action_type: CardData.ActionType) -> bool:
	if candidate == null or not candidate.alive:
		return false
	if action_type in [CardData.ActionType.HEAL, CardData.ActionType.DEFENSE]:
		return candidate.side == actor.side
	return candidate.side != actor.side and not candidate.moon_shadowed and not candidate.has_runtime_keyword(&"emblem_shadow")


func _make_value_event(action: Dictionary, target: BattleSquadState, element_multiplier: float, layer: int, base_action: bool = false, pierces: bool = false) -> BattleEffectEvent:
	var actor := action["actor"] as BattleSquadState
	var action_type := action["action_type"] as CardData.ActionType
	var pattern := action["pattern"] as RunePatternResult
	var event := BattleEffectEvent.new()
	event.group_id = int(action["group_id"])
	event.logical_layer = layer
	event.timestamp = elapsed_seconds
	event.source = actor
	event.target = target
	event.anchor = target
	event.action_type = action_type
	event.effect_kind = _kind_for_action(action_type)
	event.uses_attack_type_multiplier = event.effect_kind == BattleEffectEvent.EffectKind.DAMAGE
	event.is_base_action = base_action
	event.pierces_armor = pierces
	var action_formula_snapshot := action.get("action_formula_snapshot") as BattleFormulaData
	if action_formula_snapshot != null:
		event.formula = action_formula_snapshot.duplicate_for_target(target)
		event.formula.display_name = _value_name_for_action(action_type)
		event.formula.action_type = action_type
		event.formula.element_multiplier = element_multiplier
		event.formula.exact_result = event.formula.calculate_result()
	else:
		var additions: Array[Dictionary] = []
		var action_bonus := actor.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE)
		var reinforcement := actor.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)
		var immediate_action_delta := float(action.get("action_value_delta", 0.0))
		if not is_zero_approx(action_bonus):
			additions.append({"name": "效果数值修正", "value": action_bonus})
		if not is_zero_approx(reinforcement):
			additions.append({"name": "强化", "value": reinforcement})
		if not is_zero_approx(immediate_action_delta):
			additions.append({"name": "即时行动数值修正", "value": immediate_action_delta})
		event.formula = BattleFormulaData.create(
			_value_name_for_action(action_type),
			action_type,
			float(actor.get_action_base_value()),
			BattleRules.get_pattern_multiplier(pattern.pattern_type),
			element_multiplier,
			actor,
			target,
			_action_multipliers(actor),
			additions
		)
		event.formula.action_value_modifier_sources = _capture_modifier_sources(
			actor,
			BattleModifier.Stat.ACTION_VALUE
		)
		event.formula.reinforcement_modifier_sources = _capture_modifier_sources(
			actor,
			BattleModifier.Stat.REINFORCEMENT
		)
		event.formula.immediate_action_source = (
			action.get("action_value_source", {}) as Dictionary
		).duplicate(true)
		event.formula.base_value_sources = _capture_action_base_sources(actor)
		event.formula.pattern_multiplier_sources = _capture_pattern_sources(actor, pattern)
		event.formula.element_multiplier_sources = _capture_element_sources(actor)
		if base_action:
			action["action_formula_snapshot"] = event.formula.duplicate_for_target(target)
	event.exact_amount = event.formula.exact_result
	return event


func _capture_action_base_sources(state: BattleSquadState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state == null or state.squad_data == null:
		return result
	var squad := state.squad_data
	var active_injury_ids := state.get_unmasked_active_injuries()
	var action_card := squad.get_action_source()
	var action_owner := squad.get_action_source_instance()
	if state.has_unmasked_wound(&"贪婪"):
		for registration: Dictionary in _wound_registrations:
			if registration.get("state") != state or registration.get("wound_id") != &"贪婪":
				continue
			var greed_owner := registration.get("owner") as OwnedCard
			if not active_injury_ids.has(registration.get("instance_id", &"")):
				continue
			result.append({
				"source_kind": "wound_static_modifier",
				"source_status_id": "贪婪",
				"source_name": "贪婪",
				"source_card_id": String(greed_owner.card_data.id) if greed_owner != null and greed_owner.card_data != null else "",
				"source_card_name": greed_owner.card_data.display_name if greed_owner != null and greed_owner.card_data != null else "未知来源",
				"source_owned_card_instance_id": String(greed_owner.instance_id) if greed_owner != null else "",
				"attribute": "锁定行动基础数值",
				"amount": 1,
				"source_status": "resolved",
			})
		return result
	if action_card != null:
		result.append({
			"source_kind": "card_base_attribute",
			"source_card_id": String(action_card.id),
			"source_card_name": action_card.display_name,
			"source_owned_card_instance_id": String(action_owner.instance_id) if action_owner != null else "",
			"attribute": "基础行动值（本场倍率后）" if not is_equal_approx(state.runtime_base_action_multiplier, 1.0) else "基础行动值",
			"amount": float(action_card.base_value) * state.runtime_base_action_multiplier,
			"source_status": "resolved",
		})
	if action_owner != null:
		var growth := action_owner.get_permanent_growth(OwnedCard.STAT_BASE_VALUE)
		if not is_zero_approx(growth):
			result.append({
				"source_kind": "permanent_growth",
				"source_card_id": String(action_card.id) if action_card != null else "",
				"source_card_name": action_card.display_name if action_card != null else "未知卡牌",
				"source_owned_card_instance_id": String(action_owner.instance_id),
				"attribute": "永久成长：行动值",
				"amount": growth * state.runtime_base_action_multiplier,
				"source_status": "resolved",
			})
	if not is_zero_approx(state.runtime_permanent_action_growth):
		result.append({
			"source_kind": "permanent_growth",
			"source_card_id": String(action_card.id) if action_card != null else "",
			"source_card_name": action_card.display_name if action_card != null else "未知卡牌",
			"source_owned_card_instance_id": String(action_owner.instance_id) if action_owner != null else "",
			"attribute": "本场已获得永久成长（基础倍率后）",
			"amount": state.runtime_permanent_action_growth * state.runtime_base_action_multiplier,
			"source_status": "resolved",
		})
	for card: CardData in squad.horizontal_cards:
		var owner := squad.get_owned_card(card)
		if owner == null:
			continue
		for slot_index: int in squad.get_visible_emblem_slot_indices(card):
			if slot_index < 0 or slot_index >= owner.emblem_slots.size():
				continue
			var emblem_id := StringName(String(owner.emblem_slots[slot_index].get("emblem_id", "")))
			var amount := EmblemLibraryData.get_static_modifier(emblem_id, &"base_value")
			if amount != 0:
				result.append({
					"source_kind": "emblem_static_modifier",
					"source_status_id": String(emblem_id),
					"source_name": String(emblem_id),
					"source_card_id": String(card.id),
					"source_card_name": card.display_name,
					"source_owned_card_instance_id": String(owner.instance_id),
					"slot_index": slot_index,
					"attribute": "基础行动值",
					"amount": amount,
					"source_status": "resolved",
				})
		for wound_slot: Dictionary in squad.get_visible_wound_slots():
			if wound_slot.get("card") != card:
				continue
			var slot_index := int(wound_slot.get("slot_index", -1))
			if slot_index < 0 or slot_index >= owner.wound_slots.size():
				continue
			var injury_id := StringName("%s:wound:%d" % [owner.instance_id, slot_index])
			if not active_injury_ids.has(injury_id):
				continue
			var wound_id := StringName(String(owner.wound_slots[slot_index].get("wound_id", "")))
			var amount := EmblemLibraryData.get_wound_static_modifier(wound_id, &"base_value")
			if amount != 0:
				result.append({
					"source_kind": "wound_static_modifier",
					"source_status_id": String(wound_id),
					"source_name": String(wound_id),
					"source_card_id": String(card.id),
					"source_card_name": card.display_name,
					"source_owned_card_instance_id": String(owner.instance_id),
					"slot_index": slot_index,
					"attribute": "基础行动值",
					"amount": amount,
					"source_status": "resolved",
				})
	var equipment := squad.get_equipped_item()
	if equipment != null and equipment.card_data != null and equipment.card_data.equipment_action_delta != 0:
		result.append({
			"source_kind": "equipment_static_modifier",
			"source_card_id": String(equipment.card_data.id),
			"source_card_name": equipment.card_data.display_name,
			"source_owned_card_instance_id": String(equipment.instance_id),
			"attribute": "装备行动值",
			"amount": equipment.card_data.equipment_action_delta,
			"source_status": "resolved",
		})
	for attachment: Dictionary in squad.indicator_attachments:
		var indicator := attachment.get("indicator") as CelestialIndicator
		if indicator == null or indicator.kind not in [CelestialIndicator.Kind.SUN, CelestialIndicator.Kind.STAR]:
			continue
		var amount := CelestialIndicator.SUN_VALUE if indicator.kind == CelestialIndicator.Kind.SUN else CelestialIndicator.STAR_VALUE
		result.append({
			"source_kind": "celestial_indicator",
			"source_name": "太阳" if indicator.kind == CelestialIndicator.Kind.SUN else "星星",
			"source_indicator_instance_id": String(indicator.instance_id),
			"attribute": "基础行动值",
			"amount": amount,
			"source_status": "resolved",
		})
	return result


func _capture_pattern_sources(
	state: BattleSquadState,
	pattern: RunePatternResult
) -> Array[Dictionary]:
	var rune_sources: Array[Dictionary] = []
	if state != null:
		for slot: Dictionary in state.get_active_rune_slots():
			var card := slot.get("card") as CardData
			rune_sources.append({
				"source_card_id": String(card.id) if card != null else "",
				"source_card_name": card.display_name if card != null else "未知卡牌",
				"rune_index": int(slot.get("rune_index", -1)),
				"element": int(slot.get("element", -1)),
				"element_name": card.get_element_type_name(int(slot.get("element", -1))) if card != null else "未知元素",
			})
	return [{
		"source_kind": "rune_pattern",
		"source_name": pattern.get_pattern_name() if pattern != null else "未知牌型",
		"pattern_type": int(pattern.pattern_type) if pattern != null else -1,
		"runes": rune_sources,
	}]


func _capture_element_sources(state: BattleSquadState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state == null:
		return result
	for slot: Dictionary in state.get_active_rune_slots():
		var card := slot.get("card") as CardData
		result.append({
			"source_card_id": String(card.id) if card != null else "",
			"source_card_name": card.display_name if card != null else "未知卡牌",
			"rune_index": int(slot.get("rune_index", -1)),
			"element_name": card.get_element_type_name(int(slot.get("element", -1))) if card != null else "未知元素",
		})
	return result


func _capture_modifier_sources(
	state: BattleSquadState,
	stat: BattleModifier.Stat,
	mode: BattleModifier.Mode = BattleModifier.Mode.ADD
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state == null:
		return result
	for modifier: BattleModifier in state.modifiers.modifiers:
		if not modifier.active or modifier.stat != stat or modifier.mode != mode:
			continue
		var source := {
			"modifier_id": modifier.modifier_id,
			"source_instance_id": modifier.source_instance_id,
			"effect_id": modifier.effect_id,
			"source_runtime_id": modifier.source_runtime_id,
			"value": modifier.value,
			"contribution_sources": modifier.contribution_sources.duplicate(true),
			"source_status": "unknown",
			"source_resolution_reason": "来源实例无法在公式构建时映射到卡牌或指示物",
		}
		var found := false
		for instance: BattleEffectInstance in effect_runtime.active_instances:
			if instance.instance_id != modifier.source_instance_id or instance.definition == null:
				continue
			var owner := instance.source
			source["effect_id"] = instance.definition.effect_id
			source["effect_instance_id"] = instance.instance_id
			source["source_owner_kind"] = int(owner.owner_kind) if owner != null else -1
			source["source_owned_card_instance_id"] = String(owner.owned_card_instance_id) if owner != null else ""
			source["source_card_id"] = String(owner.card_data.id) if owner != null and owner.card_data != null else ""
			source["source_card_name"] = owner.card_data.display_name if owner != null and owner.card_data != null else "未知来源"
			source["trigger_name"] = _trigger_display_name(instance.definition.trigger)
			source["tags"] = instance.definition.tags.duplicate()
			source["reading"] = instance.definition.reading
			if modifier.contribution_sources.is_empty():
				source["contribution_sources"] = instance.contribution_sources.duplicate(true)
			else:
				source["contribution_sources"] = modifier.contribution_sources.duplicate(true)
			source["source_status"] = "resolved" if owner != null and owner.card_data != null else "partially_resolved"
			source["source_resolution_reason"] = "活动效果实例提供了来源卡快照"
			found = true
			break
		if not found:
			for registration: Dictionary in _emblem_registrations:
				if modifier.effect_id != StringName("emblem_%s" % registration.get("instance_id", "")):
					continue
				var owner := registration.get("owner") as OwnedCard
				source["source_kind"] = "emblem"
				source["source_emblem_instance_id"] = String(registration.get("instance_id", ""))
				source["source_owned_card_instance_id"] = String(owner.instance_id) if owner != null else ""
				source["source_card_id"] = String(owner.card_data.id) if owner != null and owner.card_data != null else ""
				source["source_card_name"] = owner.card_data.display_name if owner != null and owner.card_data != null else "未知纹章来源"
				source["source_name"] = String(registration.get("emblem_id", "未知纹章"))
				source["source_status"] = "resolved"
				source["source_resolution_reason"] = "纹章登记记录匹配修正来源"
				found = true
				break
		if not found:
			for registration: Dictionary in _wound_registrations:
				if modifier.effect_id != StringName("wound_%s" % registration.get("instance_id", "")):
					continue
				var owner := registration.get("owner") as OwnedCard
				source["source_kind"] = "wound"
				source["source_wound_instance_id"] = String(registration.get("instance_id", ""))
				source["source_owned_card_instance_id"] = String(owner.instance_id) if owner != null else ""
				source["source_card_id"] = String(owner.card_data.id) if owner != null and owner.card_data != null else ""
				source["source_card_name"] = owner.card_data.display_name if owner != null and owner.card_data != null else "未知伤势来源"
				source["source_name"] = String(registration.get("wound_id", "未知伤势"))
				source["source_status"] = "resolved"
				source["source_resolution_reason"] = "伤势登记记录匹配修正来源"
				found = true
				break
		if not found and modifier.effect_id == &"star_transfer":
			var attachments: Array[Dictionary] = state.squad_data.indicator_attachments if state.squad_data != null else []
			for attachment: Dictionary in attachments:
				var indicator := attachment.get("indicator") as CelestialIndicator
				if indicator == null or indicator.kind != CelestialIndicator.Kind.STAR:
					continue
				source["source_kind"] = "celestial_indicator"
				source["source_indicator_instance_id"] = String(indicator.instance_id)
				source["source_status"] = "partially_resolved"
				source["source_resolution_reason"] = "星指示物已解析；转移前来源位置未保存在修正对象中"
				found = true
				break
		result.append(source)
	return result


func _trigger_display_name(trigger: BattleEffectDefinition.Trigger) -> String:
	match trigger:
		BattleEffectDefinition.Trigger.RUSH:
			return "突击"
		BattleEffectDefinition.Trigger.ECHO:
			return "回响"
		BattleEffectDefinition.Trigger.CONTINUOUS:
			return "持续"
		BattleEffectDefinition.Trigger.LAST_WISH:
			return "遗愿"
		BattleEffectDefinition.Trigger.ELAPSED_BATTLE_TIME:
			return "战斗计时"
		BattleEffectDefinition.Trigger.BATTLE_START_SPELL:
			return "开场法术"
	return "条件触发"


func _consume_reinforcement_for_action(actor: BattleSquadState, action: Dictionary) -> void:
	if bool(action.get("is_mining", false)):
		return
	# _build_action 已把旧强化写进公式；这里只移除这次行动前的实例。
	# 回响等后置事件新增的强化不在快照中，留给下一次普通行动。
	if actor == null or action.is_empty():
		return
	var modifier_ids := actor.modifiers.get_active_modifier_ids(BattleModifier.Stat.REINFORCEMENT)
	action["consumed_reinforcement_modifier_ids"] = modifier_ids.duplicate()
	actor.modifiers.remove_modifier_ids(modifier_ids)


func _apply_wound_echo_effects(actor: BattleSquadState) -> void:
	if actor == null:
		return
	for wound_id: StringName in _get_unmasked_wound_ids(actor):
		var self_damage := 0
		match wound_id:
			&"撕裂Ⅰ": self_damage = 1
			&"撕裂Ⅱ": self_damage = 3
			&"撕裂Ⅲ": self_damage = 4
		if self_damage > 0:
			_emit_wound_damage(actor, actor, float(self_damage), wound_id, "wound_tear_echo", _take_group_id(), false)
	for registration: Dictionary in _wound_registrations:
		if registration.get("state") != actor:
			continue
		if not actor.get_unmasked_active_injuries().has(registration.get("instance_id", &"")):
			continue
		var duration := float((registration.get("definition", {}) as Dictionary).get("echo_sleep_duration", 0.0))
		if duration <= 0.0:
			continue
		actor.apply_sleep(StringName(String(registration.get("instance_id", ""))), elapsed_seconds + duration)


func _apply_emblem_echo_effects(actor: BattleSquadState) -> void:
	if actor == null:
		return
	for registration: Dictionary in _emblem_registrations:
		if registration.get("state") != actor or not _is_emblem_registration_visible(registration):
			continue
		var definition := registration.get("definition", {}) as Dictionary
		var sides := int(definition.get("echo_roll_sides", 0))
		if sides <= 0:
			continue
		var roll := int(_roll_probability(actor, sides, 1).get("total", 0))
		if roll == int(definition.get("echo_success_roll", sides)):
			_add_emblem_reinforcement(actor, registration, int(definition.get("echo_reinforcement", 0)), "回响")


func _convert_rightmost_rune_to_fire(state: BattleSquadState) -> void:
	if state == null:
		return
	var slots := state.get_active_rune_slots()
	if slots.is_empty():
		return
	var rightmost := slots[-1] as Dictionary
	state.set_runtime_rune_override(
		rightmost.get("card") as CardData,
		int(rightmost.get("rune_index", -1)),
		CardData.ElementType.FIRE
	)


func _build_element_events(action: Dictionary, carrier: BattleEffectEvent, group: Dictionary, layer: int) -> Array[BattleEffectEvent]:
	if not carrier.can_trigger_element_chain:
		return []
	if carrier.visual_kind == &"fire_burn":
		# 火作为主元素时，副元素跟随每一次真实 DOT/持续治疗/持续护甲，
		# 而不是在施加状态当下凭空结算一次未乘火倍率的效果。
		for status: Dictionary in active_continuous_effects:
			if status.get("marker") == carrier:
				status["secondary_group"] = group.duplicate(true)
				status["secondary_action"] = action.duplicate(true)
				break
		return []
	var element := int(group["element"]) as CardData.ElementType
	var count := int(group["count"])
	var config := BattleRules.get_element_config(element, count)
	if config.is_empty():
		return []
	match element:
		CardData.ElementType.FIRE:
			return _build_fire_events(action, carrier, count, config, layer)
		CardData.ElementType.WATER:
			return _build_water_events(action, carrier, count, config, layer)
		CardData.ElementType.DARK:
			return _build_dark_events(action, carrier, count, config, layer)
		CardData.ElementType.LIGHT:
			return _build_light_events(action, carrier, count, config, layer)
		CardData.ElementType.WOOD:
			return _build_wood_events(action, carrier, count, config, layer)
		_:
			return []


func _build_fire_events(action: Dictionary, carrier: BattleEffectEvent, count: int, config: Dictionary, layer: int) -> Array[BattleEffectEvent]:
	if carrier.target == null or carrier.target.current_health <= 0.0:
		return []
	var tick_multiplier := float(config["tick_multiplier"])
	var marker := _copy_carrier_event(action, carrier, carrier.target, carrier.formula.element_multiplier, layer)
	marker.effect_kind = BattleEffectEvent.EffectKind.PLACEHOLDER
	marker.element_type = CardData.ElementType.FIRE
	marker.element_count = count
	marker.visual_kind = &"fire_burn"
	marker.log_qualifier = "施加灼烧" if marker.action_type not in [CardData.ActionType.HEAL, CardData.ActionType.DEFENSE] else "施加持续效果"
	active_continuous_effects.append({
		"source": action["actor"], "target": carrier.target, "action_type": action["action_type"],
		"base_value": carrier.formula.base_value, "pattern_multiplier": carrier.formula.pattern_multiplier,
		"element_multiplier": carrier.formula.element_multiplier * tick_multiplier,
		"ticks_remaining": int(config["ticks"]), "interval": float(config["interval"]),
		"duration": float(config["ticks"]) * float(config["interval"]), "applied_at": elapsed_seconds,
		"next_time": elapsed_seconds + float(config["interval"]),
		"finisher_multiplier": carrier.formula.element_multiplier * float(config["finisher_multiplier"]),
		"element_count": count, "pierces_armor": carrier.pierces_armor, "marker": marker,
		"can_trigger_element_chain": bool(config.get("can_trigger_element_chain", true)),
	})
	marker.can_trigger_element_chain = bool(config.get("can_trigger_element_chain", true))
	return [marker]


func _build_straight_bonus_events(action: Dictionary, carrier: BattleEffectEvent, layer: int) -> Array[BattleEffectEvent]:
	if carrier.resource_target != null or bool(action.get("is_mining", false)):
		return []
	# 顺子一次性选择五类追加效果；返回事件不会作为下一元素层载体。
	var config := BattleRules.STRAIGHT_BONUS_CONFIG
	var result: Array[BattleEffectEvent] = []
	result.append_array(_build_dark_events(action, carrier, 1, config["dark"] as Dictionary, layer))
	result.append_array(_build_water_events(action, carrier, 1, config["water"] as Dictionary, layer))
	result.append_array(_build_wood_events(action, carrier, 1, config["wood"] as Dictionary, layer))
	result.append_array(_build_light_events(action, carrier, 1, config["light"] as Dictionary, layer))
	result.append_array(_build_fire_events(action, carrier, 1, config["fire"] as Dictionary, layer))
	for event: BattleEffectEvent in result:
		event.can_trigger_element_chain = false
		if event.visual_kind == &"dark_repeat": event.log_qualifier = "顺子·连击"
		elif event.visual_kind == &"water_spread": event.log_qualifier = "顺子·扩散"
		elif event.visual_kind == &"wood_pierce": event.log_qualifier = "顺子·穿刺"
		elif event.visual_kind == &"light_reflect": event.log_qualifier = "顺子·折射"
		elif event.visual_kind == &"fire_burn": event.log_qualifier = "顺子·施加灼烧"
	return result


func _build_water_events(action: Dictionary, carrier: BattleEffectEvent, count: int, config: Dictionary, layer: int) -> Array[BattleEffectEvent]:
	var targets := _water_targets(carrier.target, config)
	var result: Array[BattleEffectEvent] = []
	for target: BattleSquadState in targets:
		var event := _copy_carrier_event(action, carrier, target, carrier.formula.element_multiplier * float(config["multiplier"]), layer)
		event.element_type = CardData.ElementType.WATER
		event.element_count = count
		event.visual_kind = &"water_spread"
		event.log_qualifier = "扩散"
		result.append(event)
	return result


func _build_dark_events(action: Dictionary, carrier: BattleEffectEvent, count: int, config: Dictionary, layer: int) -> Array[BattleEffectEvent]:
	if carrier.target == null or carrier.target.current_health <= 0.0:
		return []
	var result: Array[BattleEffectEvent] = []
	for index: int in int(config["count"]):
		var event := _copy_carrier_event(action, carrier, carrier.target, carrier.formula.element_multiplier * float(config["multiplier"]), layer)
		event.element_type = CardData.ElementType.DARK
		event.element_count = count
		event.sequence_index = index
		event.visual_kind = &"dark_repeat"
		event.log_qualifier = "暗追加"
		result.append(event)
	return result


func _build_light_events(action: Dictionary, carrier: BattleEffectEvent, count: int, config: Dictionary, layer: int) -> Array[BattleEffectEvent]:
	var candidates: Array[BattleSquadState] = []
	for state: BattleSquadState in get_all_states():
		if state.side == carrier.target.side and state != carrier.target and state.alive and state.current_health > 0.0:
			candidates.append(state)
	var result: Array[BattleEffectEvent] = []
	for _bounce: int in mini(int(config["count"]), candidates.size()):
		var index := _random.randi_range(0, candidates.size() - 1)
		var target := candidates.pop_at(index) as BattleSquadState
		var event := _copy_carrier_event(action, carrier, target, carrier.formula.element_multiplier * float(config["multiplier"]), layer)
		event.element_type = CardData.ElementType.LIGHT
		event.element_count = count
		event.visual_kind = &"light_reflect"
		event.log_qualifier = "折射"
		result.append(event)
	return result


func _build_wood_events(action: Dictionary, carrier: BattleEffectEvent, count: int, config: Dictionary, layer: int) -> Array[BattleEffectEvent]:
	var target := _wood_projection_target(carrier.target)
	if target == null:
		return []
	var result: Array[BattleEffectEvent] = []
	var multiplier := carrier.formula.element_multiplier * float(config["multiplier"])
	var event := _copy_carrier_event(action, carrier, target, multiplier, layer)
	event.element_type = CardData.ElementType.WOOD
	event.element_count = count
	event.pierces_armor = bool(config["pierces_armor"])
	event.visual_kind = &"wood_pierce"
	event.log_qualifier = "跨排穿刺" if event.pierces_armor else "跨排"
	result.append(event)
	if count >= 3 and event.effect_kind in [BattleEffectEvent.EffectKind.HEALING, BattleEffectEvent.EffectKind.ARMOR]:
		var converted := _copy_carrier_event(action, carrier, target, multiplier, layer)
		converted.element_type = CardData.ElementType.WOOD
		converted.element_count = count
		converted.effect_kind = BattleEffectEvent.EffectKind.ARMOR if event.effect_kind == BattleEffectEvent.EffectKind.HEALING else BattleEffectEvent.EffectKind.HEALING
		converted.visual_kind = &"wood_pierce"
		converted.log_qualifier = "木额外转换"
		converted.formula.display_name = "护甲" if converted.effect_kind == BattleEffectEvent.EffectKind.ARMOR else "治疗"
		result.append(converted)
	return result


func _copy_carrier_event(action: Dictionary, carrier: BattleEffectEvent, target: BattleSquadState, element_multiplier: float, layer: int) -> BattleEffectEvent:
	var event := _make_value_event(action, target, element_multiplier, layer)
	event.anchor = carrier.target
	return event


func _water_targets(anchor: BattleSquadState, config: Dictionary) -> Array[BattleSquadState]:
	if anchor == null:
		return []
	var left: Array[BattleSquadState] = []
	var right: Array[BattleSquadState] = []
	for state: BattleSquadState in get_all_states():
		if state == anchor or state.side != anchor.side or state.row_key != anchor.row_key or not state.alive or state.current_health <= 0.0:
			continue
		if state.logical_center < anchor.logical_center:
			left.append(state)
		else:
			right.append(state)
	left.sort_custom(func(a: BattleSquadState, b: BattleSquadState) -> bool: return a.logical_center > b.logical_center)
	right.sort_custom(func(a: BattleSquadState, b: BattleSquadState) -> bool: return a.logical_center < b.logical_center)
	if bool(config["random_one_side"]):
		var nearest: Array[BattleSquadState] = []
		if not left.is_empty(): nearest.append(left[0])
		if not right.is_empty(): nearest.append(right[0])
		var selected: Array[BattleSquadState] = []
		if not nearest.is_empty():
			selected.append(nearest[_random.randi_range(0, nearest.size() - 1)])
		return selected
	var result: Array[BattleSquadState] = []
	for index: int in mini(int(config["left"]), left.size()): result.append(left[index])
	for index: int in mini(int(config["right"]), right.size()): result.append(right[index])
	return result


func _wood_projection_target(anchor: BattleSquadState) -> BattleSquadState:
	if anchor == null:
		return null
	var other_row := _back_row_for_side(anchor.side) if not is_back_row(anchor.row_key) else _front_row_for_side(anchor.side)
	for state: BattleSquadState in get_all_states():
		if state.side != anchor.side or state.row_key != other_row or not state.alive or state.current_health <= 0.0:
			continue
		if anchor.logical_center >= state.logical_left and anchor.logical_center < state.logical_right:
			return state
	return null


func _resolve_effect_layer(events: Array[BattleEffectEvent]) -> void:
	var ordered: Array[BattleEffectEvent] = []
	for event: BattleEffectEvent in events:
		if event.effect_kind == BattleEffectEvent.EffectKind.DAMAGE: ordered.append(event)
	for event: BattleEffectEvent in events:
		if event.effect_kind in [BattleEffectEvent.EffectKind.HEALING, BattleEffectEvent.EffectKind.ARMOR]: ordered.append(event)
	for event: BattleEffectEvent in events:
		if event.effect_kind == BattleEffectEvent.EffectKind.PLACEHOLDER: ordered.append(event)
	var cancelled_dark_groups: Dictionary = {}
	for event: BattleEffectEvent in ordered:
		if event.log_qualifier == "暗追加" and event.sequence_index > 0 and cancelled_dark_groups.has(event.group_id):
			continue
		_apply_effect_event(event)
		if event.log_qualifier == "暗追加" and event.target.current_health <= 0.0:
			cancelled_dark_groups[event.group_id] = true


func _apply_resource_break_reinforcement(actor: BattleSquadState) -> void:
	if actor == null or actor.squad_data == null:
		return
	var card := actor.squad_data.get_effect_source()
	if card == null:
		return
	var hook: Dictionary = card.deferred_effect_hooks.get("mining_succeeded", {})
	if hook.is_empty():
		return
	var owned := actor.squad_data.get_effect_source_instance()
	var modifier := BattleModifier.new()
	modifier.stat = BattleModifier.Stat.REINFORCEMENT
	modifier.mode = BattleModifier.Mode.ADD
	modifier.value = float(hook.get("amount", 1))
	modifier.effect_id = &"resource_break_reinforcement"
	modifier.source_runtime_id = actor.runtime_id
	modifier.contribution_sources.append({
		"role": "强化",
		"amount": modifier.value,
		"source_name": card.display_name,
		"source_card_id": String(card.id),
		"source_owned_card_instance_id": String(owned.instance_id) if owned != null else "",
		"source_status": "resolved",
	})
	actor.modifiers.add_modifier(modifier)


func _resolve_resource_harvest(event: BattleEffectEvent) -> void:
	var resource := event.resource_target
	if resource == null or bool(resource.get("harvested")):
		return
	resource.set("harvested", true)
	var actor := event.source
	# NPC 的整个奖励入口在此早退；潮汐射手的战斗内强化由独立触发处理。
	if actor == null or actor.side != BattleSquadState.Side.PLAYER:
		return
	var resource_owned := resource.get("owned_card") as OwnedCard
	if resource_owned == null or resource_owned.card_data == null:
		return
	var owner := BattleEffectOwnerRef.for_state(actor, BattleEffectDefinition.OwnerKind.OWNING_PLAYER)
	var timestamp := roundi(elapsed_seconds * 1000000.0)
	var reward_id := StringName("resource_harvest_%s" % resource_owned.instance_id)
	match resource_owned.card_data.id:
		&"fire_element_shard":
			_record_resource_permanent_growth(actor, BattlePermanentGrowthLedger.STAT_BASE_VALUE, 1.0, reward_id, timestamp)
		&"water_element_shard":
			_record_resource_permanent_growth(actor, BattlePermanentGrowthLedger.STAT_MAX_HEALTH, 2.0, reward_id, timestamp)
		&"wood_element_shard":
			_record_resource_permanent_growth(actor, BattlePermanentGrowthLedger.STAT_BASE_ARMOR, 1.0, reward_id, timestamp)
		&"dark_element_shard":
			_record_resource_wound_heal(actor, owner, reward_id, timestamp)
		&"light_element_shard":
			record_pending_run_reward(owner, BattleRunRewardLedger.KIND_GOLD, 2, reward_id, actor.runtime_id, timestamp)
		&"rainbow_gold_ore":
			var roll := _roll_probability(actor, 10, 2)
			var total := int(roll.get("total", 0))
			var extra_gold := 20 if total == 20 else (10 if total > 18 else (5 if total > 15 else 0))
			var base_recorded := record_pending_run_reward(owner, BattleRunRewardLedger.KIND_GOLD, 1, reward_id, actor.runtime_id, timestamp, {"reward_part": "base", "roll_total": total, "roll_details": roll})
			var extra_recorded := extra_gold == 0 or record_pending_run_reward(owner, BattleRunRewardLedger.KIND_GOLD, extra_gold, reward_id, actor.runtime_id, timestamp, {"reward_part": "highest_bonus", "roll_total": total, "roll_details": roll})
			if base_recorded and extra_recorded:
				event.log_qualifier += "，掷出%d并获得基础1金币%s" % [total, "与额外%d金币" % extra_gold if extra_gold > 0 else ""]
		&"stone_of_greed":
			var roll := _roll_probability(actor, 10)
			var roll_total := int(roll.get("total", 0))
			var delta := 10 if roll_total == 10 else (3 if roll_total >= 6 else -2)
			var kind := BattleRunRewardLedger.KIND_GOLD if delta > 0 else BattleRunRewardLedger.KIND_GOLD_DELTA
			var reward_amount := delta if delta > 0 else -delta
			if record_pending_run_reward(owner, kind, reward_amount, reward_id, actor.runtime_id, timestamp, {"gold_delta": delta, "roll": roll_total, "roll_details": roll}):
				event.log_qualifier += "，掷出%d，金币变化%+d" % [roll_total, delta]
		&"crystallized_remains":
			var roll := _roll_probability(actor, 10)
			var roll_total := int(roll.get("total", 0))
			if roll_total <= 8:
				var shard := _random_shard_definition()
				if shard != null: _record_resource_card_award(owner, shard, reward_id, actor, timestamp)
			else:
				var emblem := _random_emblem_definition()
				if not emblem.is_empty():
					var instance_id := StringName("%s:resource_emblem:%d" % [battle_instance_id, _next_reward_instance_sequence])
					_next_reward_instance_sequence += 1
					record_pending_run_reward(owner, BattleRunRewardLedger.KIND_RANDOM_EMBLEM_INSTANCE, 1, reward_id, actor.runtime_id, timestamp, {"emblem_id": emblem.get("id", &""), "emblem_instance_id": instance_id, "source": "resource:%s" % resource_owned.instance_id, "roll": roll})
		&"abandoned_toolbox":
			var equipment := _random_equipment_definition(CardData.Rarity.I)
			if equipment != null: _record_resource_card_award(owner, equipment, reward_id, actor, timestamp)
	if event.log_qualifier.contains("击碎了"):
		event.log_qualifier += "；获得收获"


func _record_resource_permanent_growth(actor: BattleSquadState, stat: StringName, amount: float, effect_id: StringName, timestamp: int) -> bool:
	if actor.squad_data == null or actor.squad_data.horizontal_cards.is_empty(): return false
	var recipient := actor.squad_data.get_action_source_instance() if stat == BattlePermanentGrowthLedger.STAT_BASE_VALUE else actor.squad_data.get_vitals_source_instance()
	if recipient == null: return false
	if not record_pending_permanent_growth(BattleEffectOwnerRef.for_owned_card_in_state(actor, recipient), stat, amount, effect_id, actor.runtime_id, timestamp): return false
	if not recipient.apply_permanent_growth(_map_chaos_growth_stat(stat), amount): return false
	match stat:
		BattlePermanentGrowthLedger.STAT_MAX_HEALTH: actor.current_health += amount
		BattlePermanentGrowthLedger.STAT_BASE_ARMOR:
			actor.current_armor += amount
	return true


func _record_resource_wound_heal(actor: BattleSquadState, owner: BattleEffectOwnerRef, effect_id: StringName, timestamp: int) -> bool:
	var candidates: Array[Dictionary] = []
	if actor.squad_data == null: return false
	for slot: Dictionary in actor.squad_data.get_visible_wound_slots():
		var card := slot.get("card") as CardData
		var owned := actor.squad_data.get_owned_card(card)
		var index := int(slot.get("slot_index", -1))
		if owned == null or index < 0 or index >= owned.wound_slots.size() or owned.wound_slots[index].is_empty(): continue
		var key := StringName("%s:wound:%d" % [owned.instance_id, index])
		if not actor.is_injury_masked(key): candidates.append({"state": actor, "owned": owned, "index": index})
	if candidates.is_empty(): return false
	var selected: Dictionary = candidates[_random.randi_range(0, candidates.size() - 1)]
	var target_state := selected.get("state") as BattleSquadState
	var target_owned := selected.get("owned") as OwnedCard
	var slot_index := int(selected.get("index", -1))
	if not record_pending_owned_card_slot_change(BattleEffectOwnerRef.for_owned_card_in_state(target_state, target_owned), BattleOwnedCardChangeLedger.KIND_SET_WOUND_SLOT, slot_index, {}, effect_id, actor.runtime_id, timestamp): return false
	if not target_owned.set_wound_slot(slot_index, {}): return false
	_sync_wound_registration_visibility()
	return true


func _record_resource_card_award(owner: BattleEffectOwnerRef, card: CardData, effect_id: StringName, actor: BattleSquadState, timestamp: int) -> void:
	if card == null: return
	record_pending_run_reward(owner, BattleRunRewardLedger.KIND_OWNED_CARD_AWARD, 1, effect_id, actor.runtime_id, timestamp, {"card_id": card.id, "card_name": card.display_name})


func _random_shard_definition() -> CardData:
	var shards: Array[CardData] = []
	for card: CardData in _reward_card_catalog:
		if card.card_type == CardData.CardType.RESOURCE and card.id in [&"fire_element_shard", &"light_element_shard", &"dark_element_shard", &"water_element_shard", &"wood_element_shard"]: shards.append(card)
	return shards[_random.randi_range(0, shards.size() - 1)] if not shards.is_empty() else null


func _random_equipment_definition(requested_rarity: int = -1) -> CardData:
	var by_rarity: Dictionary = {}
	for rarity in 4: by_rarity[rarity] = []
	for card: CardData in _reward_card_catalog:
		if card.card_type != CardData.CardType.EQUIPMENT or not card.is_available or card.is_derived or card.rarity > CardData.Rarity.IV or card.pack_id == &"development_test" or not CardPackRegistryScript.PACKS.has(card.pack_id): continue
		if requested_rarity >= 0 and int(card.rarity) != requested_rarity: continue
		if int(card.rarity) == CardData.Rarity.IV and _player_owned_card_ids.has(card.id): continue
		if int(card.rarity) == CardData.Rarity.IV and _has_same_battle_equipment_award(card.id): continue
		(by_rarity[int(card.rarity)] as Array).append(card)
	if requested_rarity >= 0:
		var requested: Array = by_rarity.get(requested_rarity, [])
		return requested[_random.randi_range(0, requested.size() - 1)] as CardData if not requested.is_empty() else null
	var weights := [75, 20, 4, 1]
	var available_weight := 0
	for rarity in 4:
		if not (by_rarity[rarity] as Array).is_empty(): available_weight += weights[rarity]
	if available_weight == 0: return null
	var roll := _random.randi_range(1, available_weight)
	for rarity in 4:
		if (by_rarity[rarity] as Array).is_empty(): continue
		roll -= weights[rarity]
		if roll <= 0:
			var candidates: Array = by_rarity[rarity]
			return candidates[_random.randi_range(0, candidates.size() - 1)] as CardData
	return null


func _has_same_battle_equipment_award(card_id: StringName) -> bool:
	for entry: Dictionary in run_reward_ledger.get_entries():
		if entry.get("kind") != BattleRunRewardLedger.KIND_OWNED_CARD_AWARD:
			continue
		if StringName(String((entry.get("parameters", {}) as Dictionary).get("card_id", ""))) == card_id:
			return true
	return false


func _random_emblem_definition(requested_rarity: int = -1) -> Dictionary:
	var by_rarity: Dictionary = {0: [], 1: [], 2: []}
	for definition: Dictionary in EmblemLibraryData.DEFINITIONS:
		if definition.get("target", "") == "rune" or int(definition.get("rarity", -1)) not in [0, 1, 2]: continue
		(by_rarity[int(definition.rarity)] as Array).append(definition)
	if requested_rarity >= 0:
		if requested_rarity not in [0, 1, 2]: return {}
		var requested_pool: Array = by_rarity[requested_rarity]
		return requested_pool[_random.randi_range(0, requested_pool.size() - 1)] as Dictionary if not requested_pool.is_empty() else {}
	var weights := [85, 13, 2]
	var total := 0
	for rarity in 3:
		if not (by_rarity[rarity] as Array).is_empty(): total += weights[rarity]
	if total <= 0: return {}
	var roll := _random.randi_range(1, total)
	for rarity in 3:
		if (by_rarity[rarity] as Array).is_empty(): continue
		roll -= weights[rarity]
		if roll <= 0:
			var candidates: Array = by_rarity[rarity]
			return candidates[_random.randi_range(0, candidates.size() - 1)] as Dictionary
	return {}


func _apply_effect_event(event: BattleEffectEvent) -> void:
	if event.resource_target != null:
		if event.resource_target.destroyed or event.resource_target.current_health <= 0:
			event.missed = true
		else:
			var damage: int = int(event.resource_target.current_health) if event.is_mining else 1
			event.exact_amount = float(damage)
			event.effective_amount = float(event.resource_target.apply_damage(damage))
			event.health_amount = event.effective_amount
			if event.resource_target.destroyed:
				event.log_qualifier = ("开采击碎了%s" if event.is_mining else "击碎了%s") % event.resource_target.get_display_name()
				_apply_resource_break_reinforcement(event.source)
				_resolve_resource_harvest(event)
		_record_battle_statistics(event)
		_ensure_formula_source_snapshots(event)
		effect_resolved.emit(event)
		if event.is_base_action:
			action_resolved.emit(event.source, null, event.action_type, roundi(event.effective_amount))
			effect_runtime.notify_action_after(event.source)
			effect_runtime.process_due(elapsed_seconds)
		return
	if event.target == null:
		return
	if event.is_continuous and (not event.target.alive or event.target.current_health <= 0.0):
		event.missed = true
		event.effective_amount = 0.0
		_ensure_formula_source_snapshots(event)
		effect_resolved.emit(event)
		return
	if event.effect_kind == BattleEffectEvent.EffectKind.HEALING and event.target.has_unmasked_wound(&"暗蚀"):
		event.missed = true
		event.effective_amount = 0.0
		_ensure_formula_source_snapshots(event)
		effect_resolved.emit(event)
		return
	_apply_wound_continuous_adjustments(event)
	match event.effect_kind:
		BattleEffectEvent.EffectKind.DAMAGE:
			_apply_attack_type_multiplier(event)
			var incoming_multiplier := event.target.modifiers.get_multiplier(BattleModifier.Stat.INCOMING_DAMAGE)
			var incoming_addition := event.target.modifiers.get_additive(BattleModifier.Stat.INCOMING_DAMAGE)
			if event.formula != null and not is_equal_approx(incoming_multiplier, 1.0):
				event.formula.other_multipliers.append({
					"name": "承伤修正",
					"value": incoming_multiplier,
					"sources": _capture_modifier_sources(event.target, BattleModifier.Stat.INCOMING_DAMAGE, BattleModifier.Mode.MULTIPLY),
				})
			if event.formula != null and not is_zero_approx(incoming_addition):
				event.formula.final_flat_bonus += incoming_addition
				for source: Dictionary in _capture_modifier_sources(event.target, BattleModifier.Stat.INCOMING_DAMAGE):
					event.formula.final_flat_bonus_sources.append(source)
			if event.formula != null:
				event.formula.exact_result = maxf(event.formula.calculate_result(), 0.0)
				event.exact_amount = event.formula.exact_result
			_apply_side_by_side_reduction(event)
			var pre_hit_armor: float = event.target.current_armor
			if event.is_base_action and event.source != null and event.action_type in [CardData.ActionType.MELEE, CardData.ActionType.RANGED, CardData.ActionType.MAGIC]:
				_apply_emblem_armor_break(event)
			var prevented := _try_consume_damage_prevention(event)
			if prevented:
				event.missed = true
				event.effective_amount = 0.0
				event.exact_amount = 0.0
			else:
				_apply_battle_fury_minimum_health(event)
				var split := event.target.apply_damage_exact(event.exact_amount, event.source, event, event.pierces_armor)
				event.armor_amount = float(split["armor_damage"])
				event.health_amount = float(split["health_damage"])
				event.effective_amount = float(split["total"])
				if event.is_base_action and event.action_type == CardData.ActionType.MELEE and event.source != null and event.effective_amount > 0.0:
					_apply_thorns_retaliation(event, pre_hit_armor)
			if event.effective_amount > 0.0:
				_clear_emblem_shadows_for_state(event.target)
			if event.is_base_action and event.effective_amount > 0.0:
				# 装备反伤由每次受击触发，而非只在装备者阵亡时触发。
				effect_runtime.emit_trigger(
					BattleEffectDefinition.Trigger.EQUIPPED_UNIT_AFTER_BASIC_ACTION_DAMAGE,
					{
						"actor": event.target,
						"damage_source": event.source,
						"current_armor_after_damage": event.target.current_armor,
					}
				)
			if event.target.current_health <= 0.0:
				_stop_emblem_periods_for_state(event.target)
		BattleEffectEvent.EffectKind.HEALING:
			event.effective_amount = event.target.apply_healing_exact(event.exact_amount, event.source, event)
			if event.is_base_action:
				effect_runtime.emit_trigger(
					BattleEffectDefinition.Trigger.AFTER_BASIC_HEAL,
					{"actor": event.source, "healed_target": event.target}
				)
		BattleEffectEvent.EffectKind.ARMOR:
			var armor_multiplier := event.target.modifiers.get_multiplier(BattleModifier.Stat.ARMOR_GAIN)
			var armor_addition := event.target.modifiers.get_additive(BattleModifier.Stat.ARMOR_GAIN)
			var effect_adjustments := effect_runtime.resolve_armor_gain_modifiers(event.target)
			armor_multiplier *= float(effect_adjustments["multiplier"])
			armor_addition += float(effect_adjustments["addition"])
			if event.formula != null and not is_equal_approx(armor_multiplier, 1.0):
				var armor_multiplier_sources := _capture_modifier_sources(
					event.target,
					BattleModifier.Stat.ARMOR_GAIN,
					BattleModifier.Mode.MULTIPLY
				)
				armor_multiplier_sources.append_array(
					BattleFormulaData.source_snapshots_from(
						effect_adjustments.get("multiplier_sources", []),
						"护甲获得乘法修正"
					)
				)
				event.formula.other_multipliers.append({
					"name": "获得护甲乘法修正",
					"value": armor_multiplier,
					"sources": armor_multiplier_sources,
				})
			if event.formula != null and not is_zero_approx(armor_addition):
				event.formula.final_flat_bonus += armor_addition
				var armor_addition_sources := _capture_modifier_sources(
					event.target,
					BattleModifier.Stat.ARMOR_GAIN
				)
				armor_addition_sources.append_array(
					BattleFormulaData.source_snapshots_from(
						effect_adjustments.get("addition_sources", []),
						"护甲获得固定修正"
					)
				)
				event.formula.final_flat_bonus_sources.append_array(armor_addition_sources)
			if event.formula != null:
				event.formula.exact_result = maxf(event.formula.calculate_result(), 0.0)
				event.exact_amount = event.formula.exact_result
			event.effective_amount = event.target.apply_armor_exact(event.exact_amount, event.source, event)
			if event.effective_amount > 0.0:
				effect_runtime.emit_trigger(
					BattleEffectDefinition.Trigger.SOURCE_ARMOR_GAINED,
					{"actor": event.target, "amount": event.effective_amount}
				)
		BattleEffectEvent.EffectKind.PLACEHOLDER:
			event.effective_amount = 0.0
	_record_battle_statistics(event)
	effect_runtime.recheck_continuous_conditions()
	effect_runtime.process_due(elapsed_seconds)
	_ensure_formula_source_snapshots(event)
	effect_resolved.emit(event)
	if event.is_base_action:
		action_resolved.emit(event.source, event.target, event.action_type, roundi(event.effective_amount))
		_apply_wound_poison_action_damage(event)
		effect_runtime.notify_action_after(event.source)
		effect_runtime.process_due(elapsed_seconds)


func _apply_wound_continuous_adjustments(event: BattleEffectEvent) -> void:
	if event == null or not event.is_continuous or event.formula == null:
		return
	var flat_adjustment := 0.0
	if event.target != null:
		for wound_id: StringName in _get_unmasked_wound_ids(event.target):
			if wound_id == &"烧伤Ⅰ":
				flat_adjustment += 1.0
			elif wound_id == &"烧伤Ⅱ":
				flat_adjustment += 2.0
	if (
		event.effect_kind == BattleEffectEvent.EffectKind.DAMAGE
		and event.visual_kind in [&"fire_tick", &"fire_finish"]
		and event.target.has_unmasked_wound(&"冻僵")
	):
		flat_adjustment -= 1.0
	if is_zero_approx(flat_adjustment):
		return
	event.formula.final_flat_bonus += flat_adjustment
	event.formula.final_flat_bonus_sources.append({
		"source_kind": "wound_continuous_adjustment",
		"source_name": "伤势持续效果修正",
		"amount": flat_adjustment,
		"source_status": "resolved",
	})
	event.formula.exact_result = maxf(event.formula.calculate_result(), 0.0)
	event.exact_amount = event.formula.exact_result


func _has_emblem_effect(state: BattleSquadState, effect_key: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state == null:
		return result
	for registration: Dictionary in _emblem_registrations:
		if registration.get("state") == state and _is_emblem_registration_visible(registration) and bool((registration.get("definition", {}) as Dictionary).get(effect_key, false)):
			result.append(registration)
	return result


func _apply_emblem_armor_break(event: BattleEffectEvent) -> void:
	for registration: Dictionary in _has_emblem_effect(event.source, &"attack_armor_break"):
		var amount := int((registration.get("definition", {}) as Dictionary).get("attack_armor_break", 0))
		if amount > 0:
			event.target.destroy_armor_exact(amount, event.source, event)


func _try_consume_damage_prevention(event: BattleEffectEvent) -> bool:
	if event.exact_amount <= 0.0:
		return false
	if event.target.consume_protection():
		return true
	if event.action_type == CardData.ActionType.MELEE:
		for registration: Dictionary in _has_emblem_effect(event.target, &"melee_immunity_once"):
			if bool(registration.get("melee_immunity_used", false)):
				continue
			registration["melee_immunity_used"] = true
			return true
	var predicted_health_damage := event.exact_amount if event.pierces_armor else maxf(event.exact_amount - event.target.current_armor, 0.0)
	if event.target.current_health - predicted_health_damage <= 0.0:
		for registration: Dictionary in _has_emblem_effect(event.target, &"lethal_coin_save"):
			if bool(registration.get("lethal_coin_used", false)):
				continue
			registration["lethal_coin_used"] = true
			if _random.randi_range(0, 1) == 1:
				return true
	return false


func _apply_side_by_side_reduction(event: BattleEffectEvent) -> void:
	if event == null or not event.is_base_action or event.target == null:
		return
	var has_grant := false
	for grant: Dictionary in _side_by_side_grants:
		if grant.get("state") == event.target:
			has_grant = true
			break
	if not has_grant or _get_adjacent_allies(event.target).is_empty():
		return
	var reduced_amount := maxf(event.exact_amount - 1.0, 0.0)
	if event.formula != null:
		event.formula.final_flat_bonus -= minf(event.exact_amount, 1.0)
		event.formula.final_flat_bonus_sources.append({
			"source_name": "并肩作战：乡邻",
			"amount": -minf(event.exact_amount, 1.0),
			"source_status": "resolved",
		})
		event.formula.exact_result = reduced_amount
	event.exact_amount = reduced_amount


func _apply_battle_fury_minimum_health(event: BattleEffectEvent) -> void:
	if event == null or event.target == null or event.exact_amount <= 0.0:
		return
	var target := event.target
	var health_damage := event.exact_amount if event.pierces_armor else maxf(event.exact_amount - target.current_armor, 0.0)
	if target.current_health - health_damage > 0.0:
		return
	var active_until := float(_minimum_health_until.get(target, 0.0))
	if active_until <= elapsed_seconds + COOLDOWN_EPSILON:
		for spell: OwnedCard in _get_all_prepared_spell_instances():
			if (
				spell == null
				or spell.card_data == null
				or spell.card_data.id != &"battle_fury"
				or int(_spell_side_by_instance.get(spell.instance_id, BattleSquadState.Side.PLAYER)) != target.side
				or _processed_spell_event_ids.has(StringName("%s:spell:%s:0" % [battle_instance_id, spell.instance_id]))
			):
				continue
			if notify_spell_triggered(spell.instance_id, 0):
				_present_nonpausing_spell(spell)
				active_until = maxf(active_until, elapsed_seconds + SPELL_MINIMUM_HEALTH_SECONDS)
				for ally: BattleSquadState in get_living_states(target.side):
					_minimum_health_until[ally] = maxf(
						float(_minimum_health_until.get(ally, 0.0)),
						active_until
					)
	if active_until <= elapsed_seconds + COOLDOWN_EPSILON:
		return
	var maximum_damage := maxf(target.current_health + (0.0 if event.pierces_armor else target.current_armor) - 1.0, 0.0)
	if event.exact_amount > maximum_damage:
		event.exact_amount = maximum_damage
		if event.formula != null:
			event.formula.exact_result = maximum_damage


func _apply_thorns_retaliation(event: BattleEffectEvent, armor_before_hit: float) -> void:
	var retaliation := 0.0
	for registration: Dictionary in _has_emblem_effect(event.target, &"thorns_base"):
		var definition := registration.get("definition", {}) as Dictionary
		retaliation += float(definition.get("thorns_base", 0.0)) + armor_before_hit * float(definition.get("thorns_armor_ratio", 0.0))
	if retaliation <= 0.0 or event.source == null or not event.source.alive:
		return
	var retaliation_event := BattleEffectEvent.new()
	retaliation_event.source = event.target
	retaliation_event.target = event.source
	retaliation_event.action_type = CardData.ActionType.MELEE
	retaliation_event.effect_kind = BattleEffectEvent.EffectKind.DAMAGE
	retaliation_event.log_qualifier = "刺盾返还"
	retaliation_event.exact_amount = retaliation
	retaliation_event.pierces_armor = true
	retaliation_event.formula = BattleFormulaData.create("刺盾返还伤害", CardData.ActionType.MELEE, retaliation, 1.0, 1.0, event.target, event.source)
	event.source.apply_direct_health_damage_exact(retaliation, event.target, retaliation_event)


func _apply_attack_type_multiplier(event: BattleEffectEvent) -> void:
	if not event.uses_attack_type_multiplier or event.formula == null:
		return
	event.target_had_armor_on_impact = event.target.current_armor > 0.0
	event.attack_type_multiplier = BattleRules.get_attack_type_multiplier(
		event.action_type,
		event.target_had_armor_on_impact
	)
	var attack_type_sources: Array[Dictionary] = [{
		"source_name": "攻击类型规则",
		"source_status": "resolved",
		"source_resolution_reason": "BattleRules 按行动方式和命中时护甲状态选择倍率",
	}]
	event.formula.other_multipliers.append({
		"name": "攻击类型（%s）" % ("有护甲" if event.target_had_armor_on_impact else "无护甲"),
		"value": event.attack_type_multiplier,
		"sources": attack_type_sources,
	})
	event.formula.exact_result = event.formula.calculate_result()
	event.exact_amount = event.formula.exact_result


func _ensure_formula_source_snapshots(event: BattleEffectEvent) -> void:
	if event == null or event.formula == null:
		return
	if event.formula.base_value_sources.is_empty():
		var card := event.source.get_effect_source() if event.source != null else null
		if card != null:
			event.formula.base_value_sources.append({
				"source_kind": "effect_source_card",
				"source_card_id": String(card.id),
				"source_card_name": card.display_name,
				"amount": event.formula.base_value,
				"source_status": "resolved",
			})
		elif not event.source_owned_card_instance_id.is_empty() or not event.source_emblem_instance_id.is_empty():
			event.formula.base_value_sources.append({
				"source_name": "纹章来源" if not event.source_emblem_instance_id.is_empty() else "装备或卡牌实例",
				"amount": event.formula.base_value,
				"source_status": "partially_resolved",
				"source_resolution_reason": "实例身份已记录，但该事件未提供卡牌显示快照",
			})
		else:
			event.formula.base_value_sources.append({
				"source_name": event.log_qualifier if not event.log_qualifier.is_empty() else "未知来源",
				"amount": event.formula.base_value,
				"source_status": "unknown",
				"source_resolution_reason": "特殊事件没有可追溯到卡牌、纹章或装备的来源引用",
			})
	if not is_zero_approx(event.formula.final_flat_bonus) and event.formula.final_flat_bonus_sources.is_empty():
		event.formula.final_flat_bonus_sources.append({
			"source_name": "未知固定加成来源",
			"value": event.formula.final_flat_bonus,
			"source_status": "unknown",
			"source_resolution_reason": "事件没有保留该固定加成的来源引用",
		})


func _record_battle_statistics(event: BattleEffectEvent) -> void:
	# 统计只记录实际生效值，因此不会把过量治疗、护甲溢出或占位效果算入战绩。
	var effective := maxf(event.effective_amount, 0.0)
	if effective <= 0.0:
		return
	match event.effect_kind:
		BattleEffectEvent.EffectKind.DAMAGE:
			# 伤害统计由 BattleSquadState.apply_damage_exact 的实际扣减入口统一记录，
			# 这里不再重复累计；治疗与护甲仍在各自控制器事件中归属来源。
			pass
		BattleEffectEvent.EffectKind.HEALING:
			if event.source != null:
				event.source.battle_healing_done += effective
		BattleEffectEvent.EffectKind.ARMOR:
			if event.source != null:
				event.source.battle_armor_granted += effective


func _collect_due_continuous_events() -> Array[BattleEffectEvent]:
	var events: Array[BattleEffectEvent] = []
	_continuous_followups.clear()
	var remaining: Array[Dictionary] = []
	for status: Dictionary in active_continuous_effects:
		var target := status["target"] as BattleSquadState
		if target == null or not target.alive or target.current_health <= 0.0:
			continue
		if elapsed_seconds + COOLDOWN_EPSILON < float(status["next_time"]):
			remaining.append(status)
			continue
		var group_id := _take_group_id()
		var event := _make_continuous_event(status, group_id, false)
		events.append(event)
		if status.has("secondary_group"):
			_continuous_followups[event] = {"group": status["secondary_group"], "action": status["secondary_action"]}
		status["ticks_remaining"] = int(status["ticks_remaining"]) - 1
		if int(status["ticks_remaining"]) <= 0:
			if float(status["finisher_multiplier"]) > 0.0:
				var finisher := _make_continuous_event(status, group_id, true)
				events.append(finisher)
				if status.has("secondary_group"):
					_continuous_followups[finisher] = {"group": status["secondary_group"], "action": status["secondary_action"]}
		else:
			status["next_time"] = float(status["next_time"]) + float(status["interval"])
			remaining.append(status)
	active_continuous_effects = remaining
	return events


func _collect_due_wound_periodic_events() -> Array[BattleEffectEvent]:
	var events: Array[BattleEffectEvent] = []
	for wound_status: Dictionary in _wound_periodic_effects:
		var state := wound_status.get("state") as BattleSquadState
		var next_time := float(wound_status.get("next_time", INF))
		if state == null or not state.alive or state.current_health <= 0.0 or not state.get_unmasked_active_injuries().has(wound_status.get("instance_id", &"")) or next_time > elapsed_seconds + COOLDOWN_EPSILON:
			continue
		wound_status["next_time"] = next_time + 2.0
		_emit_wound_damage(
			state,
			state,
			float(wound_status.get("damage", 0)),
			StringName(String(wound_status.get("wound_id", "中毒"))),
			"wound_poison_tick",
			_take_group_id(),
			true
		)
	return events


func _apply_wound_poison_action_damage(action_event: BattleEffectEvent) -> void:
	if action_event == null or action_event.source == null or action_event.target == null:
		return
	for wound_id: StringName in _get_unmasked_wound_ids(action_event.source):
		var damage := 0
		match wound_id:
			&"中毒Ⅰ": damage = 2
			&"中毒Ⅱ": damage = 3
			&"中毒Ⅲ": damage = 4
		if damage > 0:
			_emit_wound_damage(
				action_event.source,
				action_event.target,
				float(damage),
				wound_id,
				"wound_poison_action",
				action_event.group_id,
				true
			)


func _emit_wound_damage(
	source: BattleSquadState,
	target: BattleSquadState,
	amount: float,
	wound_id: StringName,
	visual_id: StringName,
	group_id: int,
	pierces_armor: bool
) -> void:
	if target == null or not target.alive or target.current_health <= 0.0 or amount <= 0.0:
		return
	var event := BattleEffectEvent.new()
	event.group_id = group_id
	event.sequence_index = 1
	event.timestamp = elapsed_seconds
	event.source = source
	event.target = target
	event.anchor = target
	event.action_type = CardData.ActionType.MELEE
	event.effect_kind = BattleEffectEvent.EffectKind.DAMAGE
	event.exact_amount = amount
	event.pierces_armor = pierces_armor
	event.is_continuous = visual_id == &"wound_poison_tick"
	event.visual_kind = visual_id
	event.log_qualifier = "中毒周期伤害" if visual_id == &"wound_poison_tick" else ("中毒行动附伤" if visual_id == &"wound_poison_action" else "撕裂回响自伤")
	event.formula = BattleFormulaData.create(
		"伤势伤害",
		CardData.ActionType.MELEE,
		amount,
		1.0,
		1.0,
		source,
		target
	)
	var split := target.apply_damage_exact(amount, source, event, pierces_armor)
	event.health_amount = float(split.get("health_damage", 0.0))
	event.effective_amount = event.health_amount
	_record_battle_statistics(event)
	if event.effective_amount > 0.0:
		_clear_emblem_shadows_for_state(target)
	if target.current_health <= 0.0:
		_stop_emblem_periods_for_state(target)
	_ensure_formula_source_snapshots(event)
	effect_resolved.emit(event)
	direct_damage_resolved.emit(target, wound_id, roundi(event.effective_amount))


func _build_due_continuous_followups() -> Array[BattleEffectEvent]:
	var events: Array[BattleEffectEvent] = []
	for carrier_value: Variant in _continuous_followups:
		var carrier := carrier_value as BattleEffectEvent
		var followup := _continuous_followups[carrier] as Dictionary
		var action := (followup["action"] as Dictionary).duplicate(true)
		action["group_id"] = carrier.group_id
		events.append_array(_build_element_events(action, carrier, followup["group"] as Dictionary, 1))
	return events


func _make_continuous_event(status: Dictionary, group_id: int, finisher: bool) -> BattleEffectEvent:
	var source := status["source"] as BattleSquadState
	var target := status["target"] as BattleSquadState
	var action_type := status["action_type"] as CardData.ActionType
	var multiplier := float(status["finisher_multiplier"] if finisher else status["element_multiplier"])
	var event := BattleEffectEvent.new()
	event.group_id = group_id
	event.timestamp = elapsed_seconds
	event.source = source
	event.target = target
	event.anchor = target
	event.action_type = action_type
	event.effect_kind = _kind_for_action(action_type)
	event.uses_attack_type_multiplier = event.effect_kind == BattleEffectEvent.EffectKind.DAMAGE
	event.element_type = CardData.ElementType.FIRE
	event.element_count = int(status["element_count"])
	event.is_continuous = true
	event.is_finisher = finisher
	event.can_trigger_element_chain = bool(status.get("can_trigger_element_chain", true))
	event.pierces_armor = bool(status["pierces_armor"])
	event.visual_kind = &"fire_finish" if finisher else &"fire_tick"
	event.log_qualifier = "灼烧终结" if finisher else "灼烧"
	event.formula = BattleFormulaData.create(_value_name_for_action(action_type), action_type, float(status["base_value"]), float(status["pattern_multiplier"]), multiplier, source, target)
	event.exact_amount = event.formula.exact_result
	return event


func _prepare_fatigue_events(living_snapshot: Array) -> Array[BattleEffectEvent]:
	var events: Array[BattleEffectEvent] = []
	var stack_due := elapsed_seconds + COOLDOWN_EPSILON >= _next_fatigue_stack_seconds
	var damage_due := elapsed_seconds + COOLDOWN_EPSILON >= _next_fatigue_damage_seconds
	if stack_due:
		for value: Variant in living_snapshot:
			var state := value as BattleSquadState
			var stacks := state.add_buff_stacks(BattleRules.FATIGUE_BUFF_ID)
			buff_stacks_changed.emit(state, BattleRules.FATIGUE_BUFF_ID, stacks)
		while elapsed_seconds + COOLDOWN_EPSILON >= _next_fatigue_stack_seconds:
			_next_fatigue_stack_seconds += BattleRules.FATIGUE_STACK_INTERVAL_SECONDS
	if damage_due:
		for value: Variant in living_snapshot:
			var state := value as BattleSquadState
			var damage := float(state.get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) * BattleRules.FATIGUE_DAMAGE_PER_STACK)
			var event := BattleEffectEvent.new()
			event.group_id = _take_group_id()
			event.timestamp = elapsed_seconds
			event.target = state
			event.anchor = state
			event.effect_kind = BattleEffectEvent.EffectKind.DAMAGE
			event.exact_amount = damage
			event.pierces_armor = true
			event.log_qualifier = "疲劳"
			event.formula = BattleFormulaData.create("伤害", CardData.ActionType.MELEE, damage, 1.0, 1.0, null, state)
			events.append(event)
		while elapsed_seconds + COOLDOWN_EPSILON >= _next_fatigue_damage_seconds:
			_next_fatigue_damage_seconds += BattleRules.FATIGUE_DAMAGE_INTERVAL_SECONDS
	return events


func _finalize_batch() -> void:
	var defeated: Array[BattleSquadState] = []
	for state: BattleSquadState in get_all_states():
		state.finalize_batch_survival()
		if state.alive and state.current_health <= 0.0:
			state.alive = false
			state.battle_ever_defeated = true
			state.force_boundary_sync()
			defeated.append(state)
			if (
				state.pending_kill_event != null
				and state.pending_kill_source != null
				and state.pending_kill_source.alive
				and state.pending_kill_source.current_health > 0.0
			):
				kill_resolved.emit(state.pending_kill_source, state, state.pending_kill_event)
	recalculate_logical_layout()
	for state: BattleSquadState in defeated:
		_death_sequence += 1
		_death_history.append({"state": state, "sequence": _death_sequence, "time": elapsed_seconds})
		_transfer_defeated_star(state)
		squad_defeated.emit(state)
		effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.LAST_WISH, {"actor": state})
		_record_emblem_last_wish_rewards(state)
		_apply_wound_corpse_effects(state)
		effect_runtime.notify_source_defeated(state)
		effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ADJACENT_ALLY_DESTROYED, {"actor": state})
		effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.OTHER_ALLY_DESTROYED, {"actor": state})
	effect_runtime.recheck_continuous_conditions()
	effect_runtime.process_due(elapsed_seconds)


func _record_emblem_last_wish_rewards(state: BattleSquadState) -> void:
	if state == null or state.side != BattleSquadState.Side.PLAYER:
		return
	var owner := BattleEffectOwnerRef.for_state(state, BattleEffectDefinition.OwnerKind.OWNING_PLAYER)
	var logical_time_us := roundi(elapsed_seconds * 1000000.0)
	for registration: Dictionary in _emblem_registrations:
		if registration.get("state") != state or not _is_emblem_registration_visible(registration):
			continue
		var definition := registration.get("definition", {}) as Dictionary
		var gold := int(definition.get("last_wish_gold", 0))
		if gold > 0:
			record_pending_run_reward(owner, BattleRunRewardLedger.KIND_GOLD, gold, StringName("emblem_%s_last_wish" % registration.get("instance_id", "")), state.runtime_id, logical_time_us)
		if bool(definition.get("last_wish_random_basic_emblem", false)):
			var pool := EmblemLibraryData.get_basic_emblem_ids()
			if pool.is_empty():
				continue
			var emblem_id := pool[_random.randi_range(0, pool.size() - 1)] as StringName
			var reward_instance_id := StringName("%s:emblem_reward:%d" % [battle_instance_id, _next_reward_instance_sequence])
			_next_reward_instance_sequence += 1
			record_pending_run_reward(
				owner,
				BattleRunRewardLedger.KIND_RANDOM_EMBLEM_INSTANCE,
				1,
				StringName("emblem_%s_last_wish" % registration.get("instance_id", "")),
				state.runtime_id,
				logical_time_us,
				{"emblem_id": emblem_id, "emblem_instance_id": reward_instance_id, "source": "treasure_last_wish"}
			)


func _apply_wound_corpse_effects(state: BattleSquadState) -> void:
	if state == null:
		return
	for registration: Dictionary in _wound_registrations:
		if registration.get("state") != state:
			continue
		if not state.get_unmasked_active_injuries().has(registration.get("instance_id", &"")):
			continue
		var definition := registration.get("definition", {}) as Dictionary
		var poison_tier := int(definition.get("corpse_poison_tier", 0))
		if poison_tier <= 0:
			continue
		for ally: BattleSquadState in _get_adjacent_allies(state):
			if int(definition.get("corpse_adjacent_damage", 0)) > 0:
				_emit_wound_damage(
					state,
					ally,
					float(definition["corpse_adjacent_damage"]),
					registration.get("wound_id", &"尸毒Ⅱ") as StringName,
					"wound_corpse_damage",
					_take_group_id(),
					false
				)
			_apply_temporary_poison(ally, poison_tier)


func _apply_temporary_poison(state: BattleSquadState, poison_tier: int) -> void:
	if state == null or state.squad_data == null or poison_tier <= 0:
		return
	var poison_ids: Array[StringName] = [&"中毒Ⅰ", &"中毒Ⅱ", &"中毒Ⅲ"]
	var active_ids := state.get_unmasked_active_injuries()
	var poison_slot: Dictionary = {}
	var highest_tier := 0
	var empty_slot: Dictionary = {}
	for visible_slot: Dictionary in state.squad_data.get_visible_wound_slots():
		var card := visible_slot.get("card") as CardData
		var owner := state.squad_data.get_owned_card(card)
		var slot_index := int(visible_slot.get("slot_index", -1))
		if owner == null or slot_index < 0 or slot_index >= owner.wound_slots.size():
			continue
		var wound_state: Dictionary = owner.wound_slots[slot_index]
		var current_id := StringName(String(wound_state.get("wound_id", "")))
		var current_tier := poison_ids.find(current_id) + 1
		var instance_key := StringName("%s:wound:%d" % [owner.instance_id, slot_index])
		if current_tier > 0 and active_ids.has(instance_key) and current_tier > highest_tier:
			highest_tier = current_tier
			poison_slot = {"owner": owner, "slot_index": slot_index, "wound_state": wound_state.duplicate(true)}
		elif current_id.is_empty() and empty_slot.is_empty():
			empty_slot = {"owner": owner, "slot_index": slot_index}
	if highest_tier >= poison_tier:
		return
	var target_slot := poison_slot if highest_tier > 0 else empty_slot
	if target_slot.is_empty():
		return
	var owner := target_slot.get("owner") as OwnedCard
	var slot_index := int(target_slot.get("slot_index", -1))
	if owner == null or slot_index < 0:
		return
	var original_state: Dictionary = target_slot.get("wound_state", {}) as Dictionary
	var mutation_exists := false
	for mutation: Dictionary in _temporary_wound_slot_mutations:
		if mutation.get("owner") == owner and int(mutation.get("slot_index", -1)) == slot_index:
			mutation_exists = true
			break
	if not mutation_exists:
		_temporary_wound_slot_mutations.append({
			"state": state,
			"owner": owner,
			"slot_index": slot_index,
			"original_state": original_state.duplicate(true),
		})
	var wound_id := poison_ids[poison_tier - 1]
	owner.set_wound_slot(slot_index, {
		"wound_id": wound_id,
		"level": 1,
		"temporary": true,
	})
	state._load_owned_card_injuries()
	var wound_instance_id := StringName("%s:wound:%d" % [owner.instance_id, slot_index])
	var periodic_found := false
	for wound_status: Dictionary in _wound_periodic_effects:
		if wound_status.get("state") != state or wound_status.get("instance_id") != wound_instance_id:
			continue
		wound_status["wound_id"] = wound_id
		wound_status["damage"] = poison_tier
		wound_status["next_time"] = elapsed_seconds + 2.0
		wound_status["paused_remaining"] = INF
		periodic_found = true
		break
	if not periodic_found:
		_wound_periodic_effects.append({
			"state": state,
			"owner": owner,
			"wound_id": wound_id,
			"instance_id": wound_instance_id,
			"damage": poison_tier,
			"next_time": elapsed_seconds + 2.0,
			"paused_remaining": INF,
		})


func _restore_temporary_wound_slots() -> void:
	for mutation: Dictionary in _temporary_wound_slot_mutations:
		var owner := mutation.get("owner") as OwnedCard
		var slot_index := int(mutation.get("slot_index", -1))
		if owner == null or slot_index < 0:
			continue
		owner.set_wound_slot(slot_index, mutation.get("original_state", {}) as Dictionary)
		var state := mutation.get("state") as BattleSquadState
		if state != null:
			state._load_owned_card_injuries()
	_temporary_wound_slot_mutations.clear()
	_wound_periodic_effects.clear()


func _action_multipliers(actor: BattleSquadState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var multiplier_bonus := actor.modifiers.get_additive(BattleModifier.Stat.ACTION_MULTIPLIER)
	if not is_zero_approx(multiplier_bonus):
		result.append({
			"name": "行动倍率修正",
			"value": maxf(0.0, 1.0 + multiplier_bonus),
			"sources": _capture_modifier_sources(actor, BattleModifier.Stat.ACTION_MULTIPLIER),
		})
	return result


func _kind_for_action(action_type: CardData.ActionType) -> BattleEffectEvent.EffectKind:
	if action_type == CardData.ActionType.HEAL:
		return BattleEffectEvent.EffectKind.HEALING
	if action_type == CardData.ActionType.DEFENSE:
		return BattleEffectEvent.EffectKind.ARMOR
	return BattleEffectEvent.EffectKind.DAMAGE


func _value_name_for_action(action_type: CardData.ActionType) -> String:
	if action_type == CardData.ActionType.HEAL:
		return "治疗"
	if action_type == CardData.ActionType.DEFENSE:
		return "护甲"
	return "%s伤害" % ["近战", "远程", "法术"][action_type]


func _visual_kind_for_event(event: BattleEffectEvent) -> StringName:
	if event.visual_kind != &"":
		return event.visual_kind
	match event.action_type:
		CardData.ActionType.RANGED:
			return &"ranged_attack"
		CardData.ActionType.MAGIC:
			return &"magic_attack"
		CardData.ActionType.HEAL:
			return &"heal_action"
		CardData.ActionType.DEFENSE:
			return &"defense_action"
		_:
			return &"melee_attack"


func _front_row_for_side(side: int) -> StringName:
	return &"player_front" if side == BattleSquadState.Side.PLAYER else &"enemy_front"


func _back_row_for_side(side: int) -> StringName:
	return &"player_back" if side == BattleSquadState.Side.PLAYER else &"enemy_back"


func _take_group_id() -> int:
	var result := _next_group_id
	_next_group_id += 1
	return result


func _on_integer_settlement_committed(event: Dictionary) -> void:
	integer_settlement_resolved.emit(event)


func _on_health_lost_accumulated(event: Dictionary) -> void:
	var state := event.get("state") as BattleSquadState
	if state == null:
		return
	effect_runtime.emit_trigger(
		BattleEffectDefinition.Trigger.SOURCE_HEALTH_LOST_ACCUMULATED,
		{
			"actor": state,
			"amount": float(event.get("amount", 0.0)),
			"accumulated_health_loss": float(event.get("accumulated_health_loss", 0.0)),
			"damage_source": event.get("source"),
			"effect_event": event.get("effect_event"),
		}
	)


func _on_effect_trace_emitted(entry: BattleEffectTraceEntry) -> void:
	effect_trace_emitted.emit(entry)


func _on_runtime_direct_effect_resolved(record: Dictionary) -> void:
	special_effect_resolved.emit(record.duplicate(true))


func _check_battle_result() -> void:
	if current_result != Result.NONE:
		return
	var player_alive := not get_living_states(BattleSquadState.Side.PLAYER).is_empty()
	var enemy_alive := not get_living_states(BattleSquadState.Side.ENEMY).is_empty()
	if player_alive and enemy_alive:
		return
	if not player_alive and not enemy_alive:
		current_result = Result.DRAW
	elif player_alive:
		current_result = Result.PLAYER_VICTORY
	else:
		current_result = Result.PLAYER_DEFEAT
	if current_result == Result.PLAYER_VICTORY:
		effect_runtime.emit_trigger(
			BattleEffectDefinition.Trigger.BATTLE_WON,
			{"winner_side": BattleSquadState.Side.PLAYER}
		)
		effect_runtime.process_due(elapsed_seconds)
	_resolve_seed_progress_before_battle_finish()
	_resolve_fracture_growth_before_battle_finish()
	effect_runtime.notify_battle_end()
	effect_runtime.process_due(elapsed_seconds)
	_restore_temporary_wound_slots()
	stop_battle()
	for state: BattleSquadState in get_all_states():
		state.force_boundary_sync()
	battle_finished.emit(current_result)


func _resolve_fracture_growth_before_battle_finish() -> void:
	for participation: Dictionary in _fracture_participation:
		var state := participation.get("state") as BattleSquadState
		var owner := participation.get("owner") as OwnedCard
		if state == null or owner == null or not state.battle_participated:
			continue
		var instance_key := String(participation.get("instance_id", ""))
		if instance_key.is_empty():
			continue
		var count := int(owner.wound_battle_counters.get(instance_key, 0)) + 1
		var threshold := maxi(int(participation.get("threshold", 0)), 1)
		var state_owner := BattleEffectOwnerRef.for_owned_card_in_state(state, owner)
		var logical_time_us := roundi(elapsed_seconds * 1000000.0)
		if count >= threshold:
			count -= threshold
			var vitals_owner := state.squad_data.get_vitals_source_instance() if state.squad_data != null else null
			if vitals_owner != null:
				var growth_owner := BattleEffectOwnerRef.for_owned_card_in_state(state, vitals_owner)
				if record_pending_permanent_growth(
					growth_owner,
					BattlePermanentGrowthLedger.STAT_BASE_ARMOR,
					1.0,
					&"fracture_battle_growth",
					state.runtime_id,
					logical_time_us
				):
					vitals_owner.apply_permanent_growth(OwnedCard.STAT_BASE_ARMOR, 1.0)
					state.current_armor += 1.0
		if record_pending_wound_battle_counter(
			state_owner,
			StringName(instance_key),
			count,
			&"fracture_battle_counter",
			state.runtime_id,
			logical_time_us
		):
			owner.wound_battle_counters[instance_key] = count


func _resolve_seed_progress_before_battle_finish() -> void:
	for registration: Dictionary in _emblem_registrations:
		var state := registration.get("state") as BattleSquadState
		var owner := registration.get("owner") as OwnedCard
		if state == null or owner == null or state.side != BattleSquadState.Side.PLAYER or not state.battle_participated or state.battle_ever_defeated or not _is_emblem_registration_visible(registration):
			continue
		var definition := registration.get("definition", {}) as Dictionary
		if not bool(definition.get("seed_progress", false)):
			continue
		var slot_index := int(registration.get("slot_index", -1))
		if slot_index < 0 or slot_index >= owner.emblem_slots.size() or owner.emblem_slots[slot_index].is_empty():
			continue
		var instance_id := registration.get("instance_id", &"") as StringName
		var current_progress := int(owner.progress_by_source.get(instance_id, 0))
		if current_progress >= 3:
			continue
		var owner_ref := BattleEffectOwnerRef.for_owned_card_in_state(state, owner)
		var effect_id := StringName("seed_growth_%s" % instance_id)
		var logical_time_us := roundi(elapsed_seconds * 1000000.0)
		if not record_pending_emblem_progress(owner_ref, instance_id, 1, effect_id, state.runtime_id, logical_time_us):
			continue
		if current_progress + 1 >= 3:
			record_pending_owned_card_slot_change(
				owner_ref,
				BattleOwnedCardChangeLedger.KIND_SET_EMBLEM_SLOT,
				slot_index,
				{"emblem_id": &"树", "instance_id": instance_id},
				effect_id,
				state.runtime_id,
				logical_time_us
			)
