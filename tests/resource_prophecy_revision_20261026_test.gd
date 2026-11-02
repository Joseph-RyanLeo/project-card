extends SceneTree

## 真实资源生成与正式Main法术准备入口，不替代业务实现。
const MAIN := preload("res://scenes/Main.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("资源与预言专项超时"); quit(2))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func spell_data(owned: OwnedCard) -> Dictionary:
	return {"kind": &"card", "source_type": &"collection", "card_data": owned.card_data, "owned_card": owned}

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main := MAIN.instantiate()
	check(not main._can_switch_world_view(), "加载未完成时不响应视角快捷键")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-resource-prophecy-revision.json"
	root.add_child(main)
	await process_frame
	await process_frame
	var definitions: Array[CardData] = []
	for definition: CardData in main._build_card_definition_registry().values():
		if definition.card_type == CardData.CardType.RESOURCE: definitions.append(definition)
	var scrap: CardData = load("res://resources/cards/gear_scrap.tres")
	var dew: CardData = load("res://resources/cards/moondew.tres")
	check(scrap.is_derived and definitions.has(scrap) and definitions.has(dew), "原始定义表仍包含衍生物，不靠删除卡牌定义屏蔽")
	check(not main._get_resource_definitions().has(scrap) and not main._get_resource_definitions().has(dew), "自然资源目录排除全部衍生资源")
	var disabled: CardData = load("res://resources/cards/fire_element_shard.tres").duplicate()
	disabled.id = &"disabled_generation_probe"
	disabled.is_available = false
	definitions.append(disabled)
	var generated := 0
	var rng := RandomNumberGenerator.new()
	for seed_value: int in 80:
		rng.seed = 261000 + seed_value
		var board := ResourceBoardState.new()
		check(board.initialize_level(StringName("filter_%d" % seed_value), rng), "真实资源板初始化")
		check(bool(board.generate_level_resources(definitions, rng).get("success", false)), "含衍生及停用定义仍可生成合法自然资源")
		for side: String in ["player", "enemy"]:
			for owned: OwnedCard in board.get_level_resource_cards(side):
				generated += 1
				check(not owned.card_data.is_derived and owned.card_data.is_available, "自然生成不出现齿轮废料、月露及停用资源")
	check(generated > 100, "覆盖双方多次真实自然抽取")
	var victory: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/victory_prophecy.tres"), rng)
	var failure: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/failure_prophecy.tres"), rng)
	var ordinary: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/damage_fireball.tres"), rng)
	var victory_durability := victory.spell_durability
	var failure_durability := failure.spell_durability
	main.prepared_spell_instance_ids.clear()
	main.spell_preparation_capacity = 1
	main._refresh_spell_preparation_tray()
	check(main._on_spell_preparation_drop_requested(spell_data(victory), 0), "先准备胜利预言")
	check(main._resolve_prepared_spell_drop_index(failure, 1) >= 0, "满栏时另一预言替换仍是合法落点")
	check(main.spell_preparation_tray._can_drop_data(Vector2(80, 100), spell_data(failure)), "法术板原生预检不因满栏拒绝互斥替换")
	check(main._on_spell_preparation_drop_requested(spell_data(failure), 1), "失败预言自动替换胜利预言")
	check(main.prepared_spell_instance_ids == [failure.instance_id], "两种预言不同时准备")
	check(main.owned_card_collection.get_by_instance_id(victory.instance_id) == victory and not main._is_spell_prepared(victory), "被替换预言保留收藏和原实例")
	check(main._on_spell_preparation_drop_requested(spell_data(victory), 0) and main.prepared_spell_instance_ids == [victory.instance_id], "反向替换同样生效")
	check(not main._on_spell_preparation_drop_requested(spell_data(ordinary), 0), "普通法术仍遵守满栏限制")
	check(victory.spell_durability == victory_durability and failure.spell_durability == failure_durability, "准备替换不消耗耐久")
	main.spell_preparation_capacity = 3
	check(main._on_spell_preparation_drop_requested(spell_data(ordinary), 0), "普通法术仍可与一种预言共存")
	check(main._on_spell_preparation_drop_requested(spell_data(failure), 2), "带普通法术时也可切换预言")
	check(main.prepared_spell_instance_ids.has(ordinary.instance_id) and main.prepared_spell_instance_ids.has(failure.instance_id) and not main.prepared_spell_instance_ids.has(victory.instance_id), "替换不误移除其他法术")
	main.prepared_spell_instance_ids.assign([victory.instance_id, ordinary.instance_id, failure.instance_id])
	main._normalize_prepared_spell_order()
	check(not main.prepared_spell_instance_ids.has(victory.instance_id) and main.prepared_spell_instance_ids.has(failure.instance_id), "历史双预言队列归一化保留后放入的一种")
	check(main.save_run_to_path(main.run_save_path) == OK and main.load_run_from_path(main.run_save_path), "准备队列真实保存与读取")
	check(main.prepared_spell_instance_ids.has(failure.instance_id) and not main.prepared_spell_instance_ids.has(victory.instance_id), "读档保持互斥及普通法术")
	main.queue_free()
	await process_frame
	await process_frame
	print("资源与预言专项：%d项，%d失败" % [checks, failures])
	quit(failures)
