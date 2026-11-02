extends SceneTree

## 真实控制器与旧算法逐次对照，覆盖强制抽签边界和查询之间的状态变动。
const CONTROLLER := preload("res://tests/performance/battle_target_parity_controller.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var battle := CONTROLLER.new()
	root.add_child(battle)
	var player: Array[Dictionary] = []
	var enemy: Array[Dictionary] = []
	for index: int in 10:
		var card := CardData.new()
		card.id = StringName("query_%d" % index)
		card.card_type = CardData.CardType.MINION
		card.max_health = 99
		card.action_type = (index % 5) as CardData.ActionType
		card.runes.assign([CardData.ElementType.WATER, CardData.ElementType.WATER, CardData.ElementType.WATER])
		var entry := {"squad_data": SquadData.from_card(card), "row_key": &"player_front" if index == 0 else (&"enemy_front" if index < 5 else &"enemy_back"), "formation_index": 0 if index == 0 else index % 5}
		if index == 0: player.append(entry)
		else: enemy.append(entry)
	battle.start_battle(player, enemy, 251028, false)
	battle.set_process(false)
	var actor: BattleSquadState = battle.player_states[0]
	var targets: Array[BattleSquadState] = []
	targets.assign(battle.enemy_states)
	targets.append(null)
	var ignored := targets[0]
	ignored.grant_runtime_keyword(&"target_priority", 1001)
	ignored.runtime_base_target_multiplier = 0.0
	check(battle.get_effective_target_weight(ignored) == 0, "真实零权重候选")
	targets[1].grant_runtime_keyword(&"dazzling", 1002)
	targets[2].grant_runtime_keyword(&"emblem_shadow", 1003)
	targets[3].is_banished = true
	targets[4].current_health = 0.0
	var sun := CelestialIndicator.new()
	sun.instance_id = &"query_sun"
	sun.kind = CelestialIndicator.Kind.SUN
	var star := CelestialIndicator.new()
	star.instance_id = &"query_star"
	star.kind = CelestialIndicator.Kind.STAR
	check(targets[5].squad_data.attach_indicator(star, Vector2(49, 60), 1), "真实星星候选")
	for phase: int in 4:
		if phase == 1:
			check(targets[6].squad_data.attach_indicator(sun, Vector2(49, 60), 2), "查询间加入真实太阳")
		elif phase == 2:
			targets[6].current_health = 0.0
			targets[2].revoke_runtime_keyword(&"emblem_shadow", 1003)
		elif phase == 3:
			targets[6].current_health = 99.0
			actor.squad_data.get_action_source().preferred_target_action_type = CardData.ActionType.MAGIC
		for roll: int in range(-1, 81):
			battle.choose_weighted_target(targets, roll)
			battle.choose_base_target(actor, targets, CardData.ActionType.MELEE, roll)
			battle.choose_base_target(actor, targets, CardData.ActionType.HEAL, roll)
			battle._choose_attack_target_with_resources(actor, targets, [])
	check(battle.parity_checks > 1000 and battle.parity_failures == 0, "所有目标、零权重跳过及随机消耗与旧算法一致")
	var empty: Array[BattleSquadState] = []
	var before := battle._random.state
	check(battle.choose_weighted_target(empty) == null and battle.choose_base_target(actor, empty, CardData.ActionType.MELEE) == null, "空目标池仍返回空")
	check(battle._random.state == before, "空目标池不消耗随机数")
	print("目标查询专项：%d次对照，%d失败" % [battle.parity_checks, failures + battle.parity_failures])
	battle.clear_battle()
	battle.queue_free()
	await process_frame
	quit(failures)
