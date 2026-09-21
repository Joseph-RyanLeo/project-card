extends SceneTree

## 使用真实战斗状态验证耀眼目标层级；层内继续沿用既有受击权重。

const OwnedCard = preload("res://scripts/data/owned_card.gd")

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var controller := BattleController.new()
	root.add_child(controller)
	var actor := _state(_card(&"attacker", CardData.ActionType.MELEE), BattleSquadState.Side.PLAYER, 0)
	var targets: Array[BattleSquadState] = [
		_state(_card(&"weight_3", CardData.ActionType.MAGIC), BattleSquadState.Side.ENEMY, 0),
		_state(_card(&"weight_1", CardData.ActionType.HEAL), BattleSquadState.Side.ENEMY, 1),
		_state(_card(&"weight_2", CardData.ActionType.RANGED), BattleSquadState.Side.ENEMY, 2),
		_state(_card(&"weight_4", CardData.ActionType.MELEE), BattleSquadState.Side.ENEMY, 3),
	]
	targets[1].grant_runtime_keyword(&"dazzling", 1)
	targets[2].grant_runtime_keyword(&"dazzling", 2)
	_expect(
		controller.choose_base_target(actor, targets, CardData.ActionType.MELEE, 0) == targets[1]
		and controller.choose_base_target(actor, targets, CardData.ActionType.MELEE, 1) == targets[2]
		and controller.choose_base_target(actor, targets, CardData.ActionType.MELEE, 2) == targets[2],
		"普通攻击只在权重1和2的耀眼单位中按1/3、2/3选取"
	)
	var built_action := controller._build_action(actor, targets, CardData.ActionType.MELEE)
	_expect(built_action.get("target") in [targets[1], targets[2]], "实际基础行动从耀眼目标层选主目标")

	actor.get_action_source().preferred_target_action_type = CardData.ActionType.RANGED
	_expect(controller.choose_base_target(actor, targets, CardData.ActionType.MELEE, 0) == targets[2], "明确优先远程时，远程耀眼高于其他耀眼")
	targets[2].revoke_runtime_keyword(&"dazzling", 2)
	_expect(controller.choose_base_target(actor, targets, CardData.ActionType.MELEE, 0) == targets[2], "普通远程高于非远程耀眼")
	targets[2].current_health = 0.0
	_expect(controller.choose_base_target(actor, targets, CardData.ActionType.MELEE, 0) == targets[1], "没有合法远程时才选择其他耀眼")
	targets[1].revoke_runtime_keyword(&"dazzling", 1)
	_expect(controller.choose_base_target(actor, targets, CardData.ActionType.MELEE, 0) == targets[0], "没有目标偏好与耀眼时仍按原权重选择普通单位")

	var healer := _state(_card(&"healer", CardData.ActionType.HEAL), BattleSquadState.Side.PLAYER, 1)
	var less_wounded := _state(_card(&"less_wounded", CardData.ActionType.MELEE), BattleSquadState.Side.PLAYER, 2)
	var more_wounded := _state(_card(&"more_wounded", CardData.ActionType.MELEE), BattleSquadState.Side.PLAYER, 3)
	less_wounded.grant_runtime_keyword(&"dazzling", 3)
	less_wounded.current_health = 8.0
	more_wounded.current_health = 4.0
	var heal_action := controller._build_action(healer, [healer, less_wounded, more_wounded], CardData.ActionType.HEAL)
	_expect(heal_action.get("target") == more_wounded, "治疗无视耀眼，优先治疗已损失生命百分比最高者")

	var beast := _state(_card(&"beast_attacker", CardData.ActionType.MELEE, CardData.RaceType.BEAST), BattleSquadState.Side.PLAYER, 4)
	var protected_squad := SquadData.from_card(_card(&"protected", CardData.ActionType.RANGED))
	var pelt := CardData.new()
	pelt.id = &"test_frostwolf_pelt"
	pelt.card_type = CardData.CardType.EQUIPMENT
	pelt.keywords = [&"beast_last"]
	var owned_pelt := OwnedCard.new()
	owned_pelt.initialize(pelt, &"test_frostwolf_pelt_1", 0)
	_expect(protected_squad.equip_item(owned_pelt), "测试用霜狼皮效果作为真实装备进入小队")
	var protected := BattleSquadState.new()
	protected.initialize(protected_squad, BattleSquadState.Side.ENEMY, &"enemy_front", 5)
	protected.grant_runtime_keyword(&"dazzling", 4)
	var ordinary := _state(_card(&"ordinary", CardData.ActionType.MELEE), BattleSquadState.Side.ENEMY, 6)
	_expect(controller.choose_base_target(beast, [protected, ordinary], CardData.ActionType.MELEE, 0) == ordinary, "野兽先攻击其他普通目标，霜狼皮即使叠有耀眼仍排最后")
	ordinary.current_health = 0.0
	_expect(controller.choose_base_target(beast, [protected, ordinary], CardData.ActionType.MELEE, 0) == protected, "霜狼皮仅降低优先层级，不令目标永久不可攻击")
	protected.current_health = 10.0
	_expect(controller.choose_base_target(actor, [protected, ordinary], CardData.ActionType.MELEE, 0) == protected, "非野兽不受霜狼皮的目标偏好影响")

	controller.queue_free()
	if failures == 0:
		print("D2-6B dazzling targeting checks passed.")
	else:
		push_error("D2-6B dazzling targeting checks failed: %d" % failures)
	quit(failures)


func _card(card_id: StringName, action_type: CardData.ActionType, race: CardData.RaceType = CardData.RaceType.HUMAN) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = String(card_id)
	card.action_type = action_type
	card.race_type = race
	card.max_health = 10
	return card


func _state(card: CardData, side: BattleSquadState.Side, index: int) -> BattleSquadState:
	var state := BattleSquadState.new()
	state.initialize(SquadData.from_card(card), side, &"player_front" if side == BattleSquadState.Side.PLAYER else &"enemy_front", index)
	return state


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
