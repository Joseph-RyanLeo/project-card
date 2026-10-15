extends SceneTree

## 旧商品保留抽卡结果和报价；真正获得／读取的实例采用当前固定行动定义。
var failures := 0
var checks := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)
func _run() -> void:
	var tree := load("res://resources/cards/moonlight_treant.tres") as CardData
	var pendant := load("res://resources/cards/ironheart_pendant.tres") as CardData
	var shop := OrdinaryShopService.new()
	shop.initialize(1013)
	var definitions: Array[CardData] = [tree, pendant]
	var ids: Array[String] = ["moonlight_treant", "ironheart_pendant"]
	var pack := {"offer_id": "old_tree_pack", "kind": "card_pack", "size": "small", "price": 12, "procurement_action": 3, "cards": ["moonlight_treant", "moonlight_treant", "moonlight_treant"]}
	var saved := {"offers": [pack]}
	check(shop.validate_saved_state(saved, ids, [], definitions), "旧治疗类月华树人卡包可读档")
	check(not shop.supports_action(tree, CardData.ActionType.HEAL) and shop.supports_action(tree, CardData.ActionType.MELEE), "新卡池只允许近战月华树人")
	pack.procurement_action = 1
	check(not shop.validate_saved_state(saved, ids, [], definitions), "仍拒绝未知的旧远程分类")
	var old_single := {"offer_id": "old_tree", "kind": "single_card", "price": 8, "hidden": true, "hint": "action_type", "hint_value": "治疗", "resolved_action_type": 3, "procurement_action": 3, "instance_seed": "123", "card_id": "moonlight_treant"}
	check(shop.validate_saved_state({"offers": [old_single]}, ids, [], definitions), "旧治疗提示月华树人单卡可读档")
	var instance := OwnedCard.new()
	instance.initialize(tree, &"old_tree", 0)
	var snapshot := instance.capture_state()
	snapshot.resolved_action_type = CardData.ActionType.HEAL
	var restored := OwnedCard.new()
	check(restored.restore_state(snapshot) and restored.resolved_action_type == CardData.ActionType.MELEE and SquadData.from_owned_card(restored).get_effective_action_type() == CardData.ActionType.MELEE, "旧收藏树人的治疗实例改用当前近战定义")
	restored.set_acquired_action_type(CardData.ActionType.HEAL)
	check(restored.resolved_action_type == CardData.ActionType.MELEE, "购买旧治疗商品时不把树人改回治疗")
	var flexible := OwnedCard.new()
	flexible.initialize(load("res://resources/cards/fireman.tres"), &"flexible", 0)
	flexible.set_acquired_action_type(CardData.ActionType.MAGIC)
	var flexible_copy := OwnedCard.new()
	check(flexible_copy.restore_state(flexible.capture_state()) and flexible_copy.resolved_action_type == CardData.ActionType.MAGIC, "多行动卡仍保留获得时选择，不重新随机")
	var old_pendant := {"offer_id": "old_pendant", "kind": "single_card", "price": int(shop.config.visible_card_prices.III), "hidden": false, "hint": "", "hint_value": "", "instance_seed": "123", "card_id": "ironheart_pendant"}
	check(shop.validate_saved_state({"offers": [old_pendant]}, ids, [], definitions), "旧III级铁心吊坠报价可读档")
	old_pendant.hidden = true
	old_pendant.hint = "rarity"
	old_pendant.hint_value = "III"
	old_pendant.price = int(shop.config.hidden_card_rarity_hint_prices.III)
	check(shop.validate_saved_state({"offers": [old_pendant]}, ids, [], definitions), "旧III级吊坠暗牌提示可读档")
	old_pendant.hint_value = "V"
	check(not shop.validate_saved_state({"offers": [old_pendant]}, ids, [], definitions), "未知等级提示仍被拒绝")
	check(pendant.rarity == CardData.Rarity.II and tree.action_type == CardData.ActionType.MELEE, "旧商品校验不污染当前共享卡牌定义")
	print("平衡旧存档兼容：%d项，%d失败" % [checks, failures])
	quit(failures)
