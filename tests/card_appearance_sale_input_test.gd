extends "res://tests/service_interaction_revision_20261020_test.gd"

## 实际窗口、鼠标成交、正式交易回滚与磁盘读档；只使用隔离临时存档。
const SAVE := "/private/tmp/project-card-appearance-sale-input.json"
const LEGACY := "/private/tmp/project-card-appearance-sale-legacy.json"
const Appearance = preload("res://scripts/data/card_appearance.gd")

func place(owned: OwnedCard) -> void:
	_show_owned(owned)
	main._select_shop_service_card({"kind": &"card", "owned_card": owned})
	await create_timer(0.55).timeout

func disk_card(path: String, id: StringName) -> Dictionary:
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for state: Dictionary in disk.collection.cards:
		if StringName(state.instance_id) == id: return state
	return {}

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("外观出售专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.6).timeout
	main.run_reward_state.gold = 1000
	main.ordinary_shop_service.rng.seed = 12
	main._generate_ordinary_shop(false)
	main._toggle_ordinary_shop()
	await create_timer(0.6).timeout
	main._open_shop_card_services()
	var action: Button = main._shop_board_view._service_action
	var ids: Array[StringName] = []
	var expected: Array[int] = []
	for index: int in 4:
		var definition := load("res://resources/cards/" + ["militia", "damage_fireball", "mining_pick", "crystallized_remains"][index] + ".tres") as CardData
		var owned: OwnedCard = main.owned_card_collection.create_card(definition, main.ordinary_shop_service.rng)
		owned.surface_finish = [Appearance.Surface.FRACTURED, Appearance.Surface.GOLD, Appearance.Surface.RAINBOW, Appearance.Surface.SILVER][index] as Appearance.Surface
		owned.art_finish = [Appearance.Art.OVERFRAME, Appearance.Art.HOLOGRAPHIC, Appearance.Art.PLAIN, Appearance.Art.OVERFRAME][index] as Appearance.Art
		if definition.card_type == CardData.CardType.SPELL: owned.spell_durability = 1
		var value: int = [17, 11, 5, 11][index]
		ids.append(owned.instance_id)
		expected.append(value)
		await place(owned)
		var snapshot := owned.capture_state()
		var gold: int = main.run_reward_state.gold
		var rng: int = main.ordinary_shop_service.rng.state
		check(action.text == "出售" and not action.disabled and main._shop_board_view._amount.text == "+%d" % value and main._shop_card_sale_price(owned) == value, "四类卡服务页报价正确：" + definition.display_name)
		if index == 0:
			await capture("appearance-sale-17")
			main._execute_shop_sale(owned.instance_id, value - 16)
			check(main.owned_card_collection.get_by_instance_id(owned.instance_id) == owned and main.run_reward_state.gold == gold, "旧的未加价报价不能成交")
			main.run_save_path = "/private/tmp/project-card-appearance-sale-absent/run.json"
			await _click(action)
			check(main.owned_card_collection.get_by_instance_id(owned.instance_id) == owned and owned.capture_state() == snapshot and main.run_reward_state.gold == gold and main._shop_service_undo.is_empty(), "出售保存失败完整回滚外观、卡牌和金币")
			main.run_save_path = SAVE
			await place(owned)
		await _click(action)
		check(main.owned_card_collection.get_by_instance_id(owned.instance_id) == null and main.run_reward_state.gold == gold + value and action.text == "撤销" and main._shop_board_view._amount.text == "-%d" % value, "实际鼠标出售按显示金额结算并提供同额撤销")
		var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		check(disk_card(SAVE, owned.instance_id).is_empty() and int(disk.reward_state.gold) == gold + value, "实际成交卡牌移除与含外观金币一起落盘")
		if index == 0:
			main.run_save_path = "/private/tmp/project-card-appearance-sale-absent/run.json"
			await _click(action)
			check(main.owned_card_collection.get_by_instance_id(owned.instance_id) == null and main.run_reward_state.gold == gold + value and action.text == "撤销", "撤销保存失败保留原成交与重试机会")
			main.run_save_path = SAVE
		await _click(action)
		check(main.owned_card_collection.get_by_instance_id(owned.instance_id) == owned and owned.capture_state() == snapshot and main.run_reward_state.gold == gold, "实际鼠标撤销返还原身份、原外观并扣回全额")
		var restored := disk_card(SAVE, owned.instance_id)
		check(restored.get("surface_finish") == Appearance.SURFACE_KEYS[owned.surface_finish] and restored.get("art_finish") == Appearance.ART_KEYS[owned.art_finish] and main.ordinary_shop_service.rng.state == rng, "撤销保存两维稳定键且不推进随机流")
	main._close_shop_card_services()
	check(main.save_run_to_path(SAVE) == OK, "保存四类外观卡供正式读档")
	var saved_gold: int = main.run_reward_state.gold
	for id: StringName in ids:
		main.owned_card_collection.get_by_instance_id(id).surface_finish = Appearance.Surface.PLAIN
		main.owned_card_collection.get_by_instance_id(id).art_finish = Appearance.Art.PLAIN
	main.run_reward_state.gold = 0
	check(main.load_run_from_path(SAVE) and main.run_reward_state.gold == saved_gold, "正式读档恢复金币及拥有卡牌")
	for index: int in ids.size():
		check(main._shop_card_sale_price(main.owned_card_collection.get_by_instance_id(ids[index])) == expected[index], "四类卡读档后卖价和外观一致")
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	for state: Dictionary in old.collection.cards:
		if state.instance_id == String(ids[0]):
			state.erase("surface_finish")
			state.erase("art_finish")
	var file := FileAccess.open(LEGACY, FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	check(main.load_run_from_path(LEGACY) and main._shop_card_sale_price(main.owned_card_collection.get_by_instance_id(ids[0])) == 1, "完整旧档缺少外观字段时普通I级仍卖1金币")
	if not main.ordinary_shop_open: main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	main._open_shop_card_services()
	await place(main.owned_card_collection.get_by_instance_id(ids[0]))
	check(main._shop_board_view._amount.text == "+1", "旧档普通外观在真实服务页显示1金币")
	# 最后验证真实卡包实例可直接按本身外观出售，未用指定外观替换抽取结果。
	main._close_shop_card_services()
	await verify_pack_sale()
	main._close_shop_card_services()
	var final_gold: int = main.run_reward_state.gold
	check(main.load_run_from_path(SAVE) and main.run_reward_state.gold == final_gold, "出售完成后读档保持成交结果，不重复结算金币")
	shell.queue_free()
	await process_frame
	await process_frame
	for path: String in [SAVE, LEGACY, SAVE + ".diagnostics.jsonl", SAVE + ".diagnostics.jsonl.previous"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("卡牌外观出售真实输入：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func verify_pack_sale() -> void:
	var selected := -1
	for seed_value: int in range(1, 30):
		main.ordinary_shop_service.rng.seed = seed_value
		main._generate_ordinary_shop(false)
		for index: int in main.ordinary_shop_service.offers.size():
			var offer: Dictionary = main.ordinary_shop_service.offers[index]
			if offer.kind == "card_pack" and offer.size == "large": selected = index; break
		if selected >= 0: break
	check(selected >= 0, "从实际商店生成规则找到大包")
	if selected < 0: return
	var offer: Dictionary = main.ordinary_shop_service.offers[selected]
	var acquired: Array[OwnedCard] = main._buy_shop_card_pack(selected, offer)
	check(acquired.size() == 5 and offer.price == 18, "正式购买18金币大包，得到5个实际外观实例")
	main._open_shop_card_services()
	for owned: OwnedCard in acquired:
		var surface: int = [0, 1, 2, 4, 8, 8][owned.surface_finish]
		var art: int = [0, 8, 8][owned.art_finish]
		var value: int = [1, 2, 4, 8, 16][int(owned.card_data.rarity)] + surface + art
		await place(owned)
		var gold: int = main.run_reward_state.gold
		check(main._shop_board_view._amount.text == "+%d" % value, "开包真实外观直接用于服务页报价")
		await _click(main._shop_board_view._service_action)
		check(main.owned_card_collection.get_by_instance_id(owned.instance_id) == null and main.run_reward_state.gold == gold + value and disk_card(SAVE, owned.instance_id).is_empty(), "包内卡按其实际外观完成出售并保存")
