extends SceneTree

## 正式卖价入口的unit检查，并用真实卡池、保底和实例生成抽样核算大包经济。
const MAIN = preload("res://scenes/Main.tscn")
const Appearance = preload("res://scripts/data/card_appearance.gd")
const SURFACE_EXPECTED := [0, 1, 2, 4, 8, 8]
const ART_EXPECTED := [0, 8, 8]
var assertions := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var main = MAIN.instantiate()
	main.run_save_path = "/private/tmp/project-card-appearance-sale-unit.json"
	root.add_child(main)
	await process_frame
	await process_frame
	check(main._shop_card_sale_price(null) == 0 and main._shop_card_sale_price(OwnedCard.new()) == 0, "空卡不能获得外观卖价")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026102708
	# 使用真实定义的独立资源副本构造各品级unit输入，不改磁盘或共享CardData。
	for path: String in ["militia", "damage_fireball", "mining_pick", "crystallized_remains"]:
		var source := load("res://resources/cards/" + path + ".tres") as CardData
		var bytes := FileAccess.get_file_as_bytes(source.resource_path)
		for rarity: int in CardData.Rarity.size():
			var definition := source.duplicate() as CardData
			definition.rarity = rarity as CardData.Rarity
			var owned := OwnedCard.new()
			owned.initialize(definition, &"sale_unit", 0, rng)
			var base: int = [1, 2, 4, 8, 16][rarity]
			for surface: int in Appearance.Surface.size():
				for art: int in Appearance.Art.size():
					owned.surface_finish = surface as Appearance.Surface
					owned.art_finish = art as Appearance.Art
					check(main._shop_card_sale_price(owned) == base + SURFACE_EXPECTED[surface] + ART_EXPECTED[art], "%s品级%d外观%d/%d沿用同一卖价" % [path, rarity, surface, art])
					if definition.card_type == CardData.CardType.SPELL:
						for remaining: int in range(rarity + 1):
							owned.spell_durability = remaining
							var original := maxi(1, ceili(float(base * remaining) / float(rarity + 1)))
							check(main._shop_card_sale_price(owned) == original + SURFACE_EXPECTED[surface] + ART_EXPECTED[art], "法术剩余%d次先折算、保底，再加外观" % remaining)
						owned.spell_durability = rarity + 1
		check(FileAccess.get_file_as_bytes(source.resource_path) == bytes, "价格测试不改写共享定义：" + path)
	var normal: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/militia.tres"), rng)
	normal.set_emblem_slot(0, {"instance_id": "sale_emblem", "emblem_id": "火把"})
	normal.set_rune_sticker(0, {"instance_id": "sale_rune", "emblem_id": "火贴纸", "element_sticker": true, "element": 0})
	normal.rune_revealed[0] = true
	normal.wound_slots[0] = {"instance_id": "sale_wound", "wound_id": "中毒Ⅰ"}
	normal.surface_finish = Appearance.Surface.FRACTURED
	normal.art_finish = Appearance.Art.OVERFRAME
	check(main._shop_card_sale_price(normal) == 19, "基础1＋纹章1＋贴纸1＋刮开1－伤势1，再追加16＝19")
	normal.emblem_slots.fill({})
	normal.rune_stickers.fill({})
	normal.rune_revealed.fill(false)
	check(main._shop_card_sale_price(normal) == 17, "伤势使原卖价触底后仍追加16，得到17")
	var state := normal.capture_state()
	state.erase("surface_finish")
	state.erase("art_finish")
	check(normal.restore_state(state) and main._shop_card_sale_price(normal) == 1, "旧内存快照缺省外观按普通计价")
	# 配置是数值唯一来源；不在OwnedCard或UI再硬编码第二份加价。
	main.ordinary_shop_service.config.card_sale.surface_bonuses.silver = 3
	normal.surface_finish = Appearance.Surface.SILVER
	check(main._shop_card_sale_price(normal) == 4, "改集中配置即可改变正式报价")
	main.ordinary_shop_service.load_config()
	var expected_bonus := 0.0
	for index: int in SURFACE_EXPECTED.size(): expected_bonus += Appearance.SURFACE_WEIGHTS[index] * SURFACE_EXPECTED[index] / 100.0
	for index: int in ART_EXPECTED.size(): expected_bonus += Appearance.ART_WEIGHTS[index] * ART_EXPECTED[index] / 100.0
	check(is_equal_approx(expected_bonus, 2.55), "单张外观平均加价2.55金币，大包共12.75")
	check(main.ordinary_shop_service.config.card_pack_prices.large == 18 and main.ordinary_shop_service.config.card_pack_sizes.large == 5, "大包仍为18金币5张，不调整经济配置")
	verify_pack_economy(main, rng)
	main.queue_free()
	await process_frame
	await process_frame
	print("卡牌外观卖价unit：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func verify_pack_economy(main: Node, rng: RandomNumberGenerator) -> void:
	var shop: OrdinaryShopService = main.ordinary_shop_service
	var all_definitions: Array[CardData] = main._get_shop_card_definitions()
	for pack_id: String in shop.config.allowed_pack_ids:
		var pool: Array[CardData] = []
		for definition: CardData in all_definitions:
			if String(definition.pack_id) == pack_id: pool.append(definition)
		var total := 0
		var base_total := 0
		var profitable := 0
		var valid := true
		for iteration: int in 2000:
			var result := shop.draw_card_pack(pool, true, 5, rng)
			if not result.success:
				valid = false
				break
			var collection := OwnedCardCollection.new()
			var value := 0
			var base := 0
			var guaranteed := false
			for definition: CardData in result.cards:
				var owned := collection.create_card(definition, rng, result.cards, true)
				valid = valid and owned != null
				if owned == null: break
				value += main._shop_card_sale_price(owned)
				base += int(shop.config.card_sale.base_prices[shop._rarity_key(definition.rarity)])
				guaranteed = guaranteed or definition.rarity >= CardData.Rarity.II
			valid = valid and guaranteed
			total += value
			base_total += base
			if value > 18: profitable += 1
		check(valid, "真实卡包池遵守大包至少II级保底：" + pack_id)
		print("经济抽样 %s：2000包，平均品级卖价%.4f、含外观%.4f、平均净额%.4f、盈利比例%.2f%%" % [pack_id, base_total / 2000.0, total / 2000.0, total / 2000.0 - 18, profitable / 20.0])
