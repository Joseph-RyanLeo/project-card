extends "res://tests/performance/battle_load_profiled_controller.gd"

## 旧版纯选目标算法作为对照：同一真实状态与随机起点，逐次核对目标和随机终态。
var parity_checks := 0
var parity_failures := 0

func _check_target_parity(matches: bool) -> void:
	parity_checks += 1
	if not matches:
		parity_failures += 1
		push_error("目标优化前后不一致，逻辑时间：%s" % elapsed_seconds)

func choose_weighted_target(candidates: Array[BattleSquadState], forced_roll: int = -1) -> BattleSquadState:
	var initial := _random.state
	var expected := _legacy_weighted_target(candidates, forced_roll)
	var expected_random := _random.state
	_random.state = initial
	var actual := super.choose_weighted_target(candidates, forced_roll)
	_check_target_parity(actual == expected and _random.state == expected_random)
	return actual

func choose_base_target(actor: BattleSquadState, candidates: Array[BattleSquadState], action_type: CardData.ActionType, forced_roll: int = -1) -> BattleSquadState:
	var initial := _random.state
	var expected := _legacy_base_target(actor, candidates, action_type, forced_roll)
	var expected_random := _random.state
	_random.state = initial
	var actual := super.choose_base_target(actor, candidates, action_type, forced_roll)
	_check_target_parity(actual == expected and _random.state == expected_random)
	return actual

func _choose_attack_target_with_resources(actor: BattleSquadState, candidates: Array[BattleSquadState], resources: Array[RefCounted]) -> Dictionary:
	var initial := _random.state
	var expected := _legacy_resource_target(actor, candidates, resources)
	var expected_random := _random.state
	_random.state = initial
	var actual := super._choose_attack_target_with_resources(actor, candidates, resources)
	_check_target_parity(actual == expected and _random.state == expected_random)
	return actual

func _legacy_weighted_target(candidates: Array[BattleSquadState], forced_roll: int = -1) -> BattleSquadState:
	var valid: Array[BattleSquadState] = []
	var total_weight := 0
	for candidate: BattleSquadState in candidates:
		if candidate != null and candidate.alive and candidate.current_health > 0.0 and not candidate.is_banished:
			valid.append(candidate)
			total_weight += get_effective_target_weight(candidate)
	if valid.is_empty() or total_weight <= 0: return null
	var roll := clampi(forced_roll, 0, total_weight - 1) if forced_roll >= 0 else _random.randi_range(0, total_weight - 1)
	var boundary := 0
	for candidate: BattleSquadState in valid:
		boundary += get_effective_target_weight(candidate)
		if roll < boundary: return candidate
	return valid[-1]

func _legacy_tier(candidate: BattleSquadState, preference: int, beast_attack: bool, ignores_dazzling: bool) -> int:
	if beast_attack and candidate.has_targeting_keyword(&"beast_last"): return 4
	var dazzling := false
	if not ignores_dazzling:
		if candidate.squad_data.has_indicator(CelestialIndicator.Kind.SUN):
			dazzling = true
		else:
			var sun_active := false
			for state: BattleSquadState in get_all_states():
				if state.alive and state.current_health > 0.0 and state.squad_data.has_indicator(CelestialIndicator.Kind.SUN): sun_active = true; break
			dazzling = not sun_active and (candidate.squad_data.has_indicator(CelestialIndicator.Kind.STAR) or candidate.has_targeting_keyword(&"dazzling"))
	if preference >= 0:
		if candidate.get_effective_action_type() == preference: return 0 if dazzling else 1
		return 2 if dazzling else 3
	return 0 if dazzling else 1

func _legacy_base_target(actor: BattleSquadState, candidates: Array[BattleSquadState], action_type: CardData.ActionType, forced_roll: int) -> BattleSquadState:
	if action_type in [CardData.ActionType.HEAL, CardData.ActionType.DEFENSE]: return _legacy_weighted_target(candidates, forced_roll)
	if actor == null: return null
	var preference := actor.get_target_action_type_preference()
	var beast_attack := actor.has_effective_race(CardData.RaceType.BEAST)
	var tiers: Array[Array] = [[], [], [], [], []]
	for candidate: BattleSquadState in candidates:
		if candidate == null or not candidate.alive or candidate.current_health <= 0.0 or candidate.is_banished or candidate.has_effective_shadow(): continue
		tiers[_legacy_tier(candidate, preference, beast_attack, silvermoon != null and silvermoon.active(actor, &"moonblade_scimitar", true))].append(candidate)
	for tier: Array in tiers:
		var typed: Array[BattleSquadState] = []
		typed.assign(tier)
		var total := 0
		for candidate: BattleSquadState in typed: total += get_effective_target_weight(candidate)
		if total > 0: return _legacy_weighted_target(typed, forced_roll)
	return null

func _legacy_resource_target(actor: BattleSquadState, candidates: Array[BattleSquadState], resources: Array[RefCounted]) -> Dictionary:
	var preference := actor.get_target_action_type_preference()
	var beast_attack := actor.has_effective_race(CardData.RaceType.BEAST)
	var tiers: Array[Array] = [[], [], [], [], []]
	for candidate: BattleSquadState in candidates:
		if candidate == null or not candidate.alive or candidate.current_health <= 0.0 or candidate.is_banished or candidate.has_effective_shadow(): continue
		tiers[_legacy_tier(candidate, preference, beast_attack, silvermoon != null and silvermoon.active(actor, &"moonblade_scimitar", true))].append(candidate)
	if twisted_vein != null and twisted_vein.has_lamp_aura(actor): resources = []
	var resource_tier := 3 if preference >= 0 else 1
	for tier: int in 5:
		var available: Array[RefCounted] = []
		if tier == resource_tier:
			for resource: RefCounted in resources:
				if not resource.get("destroyed") and int(resource.get("current_health")) > 0: available.append(resource)
		var total := available.size()
		for candidate: BattleSquadState in tiers[tier]: total += get_effective_target_weight(candidate)
		if total <= 0: continue
		var roll := _random.randi_range(0, total - 1)
		var boundary := 0
		for candidate: BattleSquadState in tiers[tier]:
			boundary += get_effective_target_weight(candidate)
			if roll < boundary: return {"target": candidate, "resource_target": null}
		return {"target": null, "resource_target": available[roll - boundary]}
	return {"target": null, "resource_target": null}
