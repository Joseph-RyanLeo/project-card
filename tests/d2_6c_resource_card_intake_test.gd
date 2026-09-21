extends SceneTree

## D2-6C 提前接入的资源卡资料检查；只验证 CardData 字段与原文，不执行开采结算。

const EXPECTED_RESOURCES := {
	&"fire_element_shard": {"name": "火元素碎晶", "rarity": CardData.Rarity.II, "health": 2, "type": CardData.ResourceType.MINERAL, "text": "收获：数值永久+1。"},
	&"light_element_shard": {"name": "光元素碎晶", "rarity": CardData.Rarity.II, "health": 2, "type": CardData.ResourceType.MINERAL, "text": "收获：2金币。"},
	&"dark_element_shard": {"name": "暗元素碎晶", "rarity": CardData.Rarity.II, "health": 2, "type": CardData.ResourceType.MINERAL, "text": "收获：永久治疗一处伤势。"},
	&"water_element_shard": {"name": "水元素碎晶", "rarity": CardData.Rarity.II, "health": 2, "type": CardData.ResourceType.MINERAL, "text": "收获：生命永久+2。"},
	&"wood_element_shard": {"name": "木元素碎晶", "rarity": CardData.Rarity.II, "health": 2, "type": CardData.ResourceType.MINERAL, "text": "收获：护甲永久+1。"},
	&"rainbow_gold_ore": {"name": "彩金矿", "rarity": CardData.Rarity.III, "health": 7, "type": CardData.ResourceType.MINERAL, "text": "收获：1金币，并投2d10；>15额外5金币，>18额外10金币，=20额外20金币。额外奖励不叠加，最高档生效。"},
	&"crystallized_remains": {"name": "晶化残躯", "rarity": CardData.Rarity.II, "health": 6, "type": CardData.ResourceType.MINERAL, "text": "收获：1d10<9获一张元素碎晶，>8获一个纹章。"},
	&"stone_of_greed": {"name": "贪欲之石", "rarity": CardData.Rarity.I, "health": 3, "type": CardData.ResourceType.MINERAL, "text": "收获：1d10<6失去2金币，>5获得3金币，=10获得10金币。"},
	&"abandoned_toolbox": {"name": "废弃工具箱", "rarity": CardData.Rarity.I, "health": 2, "type": CardData.ResourceType.RELIC, "text": "收获：随机一件I级装备。"},
}

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for card_id: StringName in EXPECTED_RESOURCES:
		var card := load("res://resources/cards/%s.tres" % card_id) as CardData
		var expected := EXPECTED_RESOURCES[card_id] as Dictionary
		_expect(card != null and card.id == card_id and card.display_name == expected["name"], "资源卡身份与名称：%s" % card_id)
		_expect(card != null and card.pack_id == &"labyrinth" and card.card_type == CardData.CardType.RESOURCE and card.rarity == expected["rarity"] and card.max_health == expected["health"] and card.resource_type == expected["type"], "资源卡品级、生命和种类：%s" % card_id)
		_expect(card != null and card.effect_text == expected["text"] and card.effect_ids.is_empty(), "资源卡保留原文且不提前绑定未实现效果：%s" % card_id)
	var pick := load("res://resources/cards/mining_pick.tres") as CardData
	_expect(pick != null and pick.display_name == "矿稿" and pick.pack_id == &"labyrinth", "矿稿属于迷宫卡包")
	_expect(pick != null and pick.card_type == CardData.CardType.EQUIPMENT and pick.rarity == CardData.Rarity.I and pick.equipment_type == CardData.EquipmentType.MELEE_WEAPON and pick.equipment_action_delta == 1 and pick.equipment_health_delta == 0 and pick.equipment_armor_delta == 0 and pick.equipment_zeal_delta == 0, "矿稿遵守I级近战武器基础属性")
	_expect(pick != null and pick.keywords == [&"mining"] and pick.effect_text == "开采1。" and int(pick.deferred_effect_hooks["mining"]["uses_per_battle"]) == 1, "矿稿只记录每场一次开采边界，不伪造结算")
	if failures == 0:
		print("D2-6C resource card intake checks passed.")
	else:
		push_error("D2-6C resource card intake checks failed: %d" % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
