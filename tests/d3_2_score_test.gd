extends SceneTree

const Score = preload("res://scripts/data/run_score_service.gd")
const Progress = preload("res://scripts/data/profile_progress.gd")
var checks := 0
var failures := 0

func check(value: bool, title: String) -> void:
	checks += 1
	if value: print("PASS: ", title)
	else:
		failures += 1
		push_error(title)

func _initialize() -> void:
	var card := OwnedCard.new()
	card.initialize(load("res://resources/cards/musketeer.tres"), &"score_card", 0)
	card.surface_finish = CardAppearance.Surface.FRACTURED
	card.art_finish = CardAppearance.Art.OVERFRAME
	card.rune_revealed.fill(true)
	card.resolved_runes.fill(CardData.ElementType.FIRE)
	var original := card.capture_state()
	var plain := Score.card_score(card)
	check(plain.parts.surface == 40 and plain.parts.art == 40, "卡面与卡图使用积分表80分")
	check(plain.parts.runes == 9 and plain.parts.pattern == 20, "单卡三条9+20，不叠对子")
	check(card.capture_state() == original, "计分不改动原实例")
	card.rune_revealed.fill(false)
	card.set_rune_sticker(0, {"emblem_id": &"火贴纸", "element": CardData.ElementType.FIRE})
	var covered := Score.card_score(card)
	check(covered.parts.runes == 3 and covered.parts.stickers == 10, "贴纸覆盖未揭晓槽保留纹章品级和单槽3分")
	card.rune_revealed[0] = true
	check(Score.card_score(card).parts.runes == 3, "覆盖已揭晓槽不重复计算")
	check(Score.sticker_score({"emblem_id": &"宝石"}) == 110, "宝石II级10与效果100相加")
	check(Score.sticker_score({"emblem_id": &"盾牌Ⅲ"}) == 15, "合成纹章按实际V级15分")
	check(Score.sticker_score({"wound_id": &"骨折Ⅰ", "level": 3}) == 5, "伤势不按等级变化")
	var empty: Array[OwnedCard] = []
	var results := [{"day": 1, "won": true, "ending": ""}, {"day": 2, "won": false, "ending": ""}, {"day": 3, "won": false, "ending": "ordinary_loss"}]
	var fail := Score.calculate(empty, {}, [{"emblem_id": &"宝石"}, {"emblem_id": &"宝石", "storage": "drop"}], 13, "failed", 3, results, 0)
	check(fail.base == 123 and fail.total == 147 and fail.multiplier_tenths == 12, "保护失败日算完成，终局失败当天不计；最终一次向下取整")
	check(fail.toolbox.size() == 1, "临时未入包宝石排除")
	var win := Score.calculate(empty, {}, [], 100, "cleared", 8, [{"day": 8, "won": true, "ending": "cleared"}], 2)
	check(win.multiplier_tenths == 20 and win.total == 200, "Boss胜利额外0.5与通关剩余保护0.4")
	check(Score.calculate(empty, {}, [], 100, "abandoned", 2, [], 2).total == 0, "前两天放弃无分")
	check(Score.calculate(empty, {}, [], 100, "abandoned", 3, [], 2).total == 100, "进入第三天即可计分，不加剩余保护")
	var resource := OwnedCard.new()
	resource.initialize(load("res://resources/cards/rainbow_gold_ore.tres"), &"resource", 1)
	var derived := OwnedCard.new()
	derived.initialize(load("res://resources/cards/gear_scrap.tres"), &"derived", 2)
	var held: Array[OwnedCard] = [card, resource, derived]
	var progress := Progress.new()
	progress.start_run()
	var spell := OwnedCard.new()
	spell.initialize(load("res://resources/cards/damage_fireball.tres"), &"spell", 3)
	spell.spell_durability = 0
	check(progress.remember_exhausted_spell(spell), "保存真实耗尽法术")
	progress.note_discovery("cards", "shop_unfinished")
	check(progress.finish_run(held, [], 13, "abandoned", 3, results, 2), "冻结结局与完整候选并自动入账")
	check(progress.run.stage == "summary" and progress.profile.discoveries.cards.has("shop_unfinished"), "结束阶段为总结，未完事件发现保留")
	check(progress.run.summary.cards.size() == 3 and progress.run.candidates.size() == 2, "资源计分不入藏、衍生全排除、耗尽法术纳入")
	var balance: int = progress.profile.points
	check(progress.finish_run(held, [], 999, "abandoned", 3, [], 2) and progress.profile.points == balance, "重复处理同一结局不重发积分或改变明细")
	var restored := Progress.new()
	check(restored.restore_state(JSON.parse_string(JSON.stringify(progress.capture_state()))) and restored.run.stage == "summary", "JSON重启恢复总结与余额")
	check(restored.show_selection() and restored.set_selection([{"candidate_id": "spell", "slot": 0}]) and restored.show_preview(), "可选择耗尽法术并集合")
	check(restored.confirm_collection() and restored.profile.collection.damage_fireball[0].spell_durability == int(spell.card_data.rarity) + 1, "最终入藏恢复法术全新次数")
	check(restored.profile.collection.damage_fireball[0].acquired_at == spell.acquired_at and restored.profile.points == balance, "原获得时间保留且入藏不重发积分")
	check(restored.start_run(), "收藏完成可开下一局")
	for days: int in [4, 8, 16, 24, 28]:
		var history: Array = []
		for day: int in range(1, days + 1): history.append({"day": day, "won": true, "ending": "cleared" if day == days else ""})
		var score := Score.calculate(empty, {}, [], 100, "cleared", days, history, 2)
		check(score.multiplier_tenths == 14 + days + (days / 8 + (1 if days == 28 else 0)) * 5, "%d天既定终点按通关计保护与Boss/半层倍率" % days)
	var final_days: Array = []
	for day: int in range(1, 29): final_days.append({"day": day, "won": day < 28, "ending": "failed" if day == 28 else ""})
	var half_fail := Score.calculate(empty, {}, [], 100, "failed", 28, final_days, 2)
	check(half_fail.completed_days == 27 and half_fail.multiplier_tenths == 52 and half_fail.protection == 0, "进入半层后失败不保留第三层通关保护奖励，终败当天不计")
	var broken := restored.capture_state()
	broken.run["summary"] = {"total": 500}
	check(not Progress.new().restore_state(broken), "损坏总结拒绝恢复，不虚构明细或凭证")
	print("D3-2 score checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
