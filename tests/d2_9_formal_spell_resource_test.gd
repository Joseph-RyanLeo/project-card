extends SceneTree

## D2-9 正式法术资源：验证飞书只读快照、效果目录绑定和灰烬征册收藏入口。

const EFFECT_DATA_PATH := "res://data/demo2/ash_ledger_effect_samples.json"
const SOURCE_SNAPSHOT_PATH := "res://data/demo2/formal_spells_source_snapshot.json"
const FORMAL_SPELLS := {
	&"battle_fury": {"name": "战斗怒火", "rarity": CardData.Rarity.IV, "spell_type": CardData.SpellType.SUPPORT, "trigger": CardData.SpellTriggerKind.CONDITIONAL, "effects": [&"battle_fury.effect.01"]},
	&"side_by_side": {"name": "并肩作战", "rarity": CardData.Rarity.III, "spell_type": CardData.SpellType.ENHANCE, "trigger": CardData.SpellTriggerKind.INSTANT, "effects": [&"side_by_side.effect.01", &"side_by_side.effect.02"]},
	&"return_to_battlefield": {"name": "重返战场", "rarity": CardData.Rarity.II, "spell_type": CardData.SpellType.SUMMON, "trigger": CardData.SpellTriggerKind.PREPARED, "effects": [&"return_to_battlefield.effect.01"]},
	&"volley_order": {"name": "齐射令", "rarity": CardData.Rarity.I, "spell_type": CardData.SpellType.ENHANCE, "trigger": CardData.SpellTriggerKind.PREPARED, "effects": [&"volley_order.effect.01"]},
}

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_source_snapshot()
	_test_formal_resources()
	if failures == 0:
		print("D2-9 formal spell resource checks passed.")
	else:
		push_error("D2-9 formal spell resource checks failed: %d" % failures)
	quit(failures)


func _test_source_snapshot() -> void:
	var file := FileAccess.open(SOURCE_SNAPSHOT_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_expect(data is Dictionary, "四张正式法术保留可审计的只读来源快照")
	if not data is Dictionary:
		return
	var source := data as Dictionary
	_expect(source.get("source", {}).get("access") == "read-only", "来源快照标记为只读访问")
	_expect(source.get("source", {}).get("table_id") == "tbl6qIMmgLoYgMpX", "来源快照锁定授权卡牌审阅表")
	var cards := source.get("cards", []) as Array
	_expect(cards.size() == FORMAL_SPELLS.size(), "来源快照只保存四张目标法术")
	for card: Dictionary in cards:
		var id := StringName(card.get("card_id", ""))
		_expect(FORMAL_SPELLS.has(id), "来源快照卡牌ID属于目标四张：%s" % id)
		_expect(_string_ids(card.get("effect_ids", []) as Array) == _string_ids(FORMAL_SPELLS[id]["effects"] as Array), "来源快照效果ID与本地效果目录一致：%s" % id)


func _test_formal_resources() -> void:
	var catalog := BattleEffectCatalog.load_from_file(EFFECT_DATA_PATH)
	_expect(catalog.is_valid(), "灰烬证册效果目录可严格解析")
	for card_id: StringName in FORMAL_SPELLS:
		var expected := FORMAL_SPELLS[card_id] as Dictionary
		var card := load("res://resources/cards/%s.tres" % card_id) as CardData
		_expect(card != null and card.pack_id == &"ash_ledger" and card.is_available, "正式法术资源进入灰烬征册：%s" % card_id)
		if card == null:
			continue
		_expect(card.display_name == expected["name"] and card.rarity == expected["rarity"] and card.spell_type == expected["spell_type"] and card.spell_trigger_kind == expected["trigger"], "正式法术字段来自已确认记录：%s" % card_id)
		_expect(card.effect_ids == expected["effects"] and card.effect_ids == catalog.card_effect_ids.get(card_id, []), "正式法术绑定完整效果组：%s" % card_id)
		_expect(card.effect_text != "", "正式法术保留卡面短文本：%s" % card_id)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)


func _string_ids(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(String(value))
	return result
