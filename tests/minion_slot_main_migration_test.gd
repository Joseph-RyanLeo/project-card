extends SceneTree

## 正式Main读档会保存迁移标记，并把超额状态放进工具箱而非静默丢失。
const DISPLAY := preload("res://scenes/GameDisplay.tscn")
const SAVE := preload("res://scripts/data/run_save_service.gd")
const PATH := "/private/tmp/project-card-slot-main-migration.json"
var assertions := 0
var failures := 0
func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("主流程槽位迁移超时"); quit(2))
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error(message)
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var shell = DISPLAY.instantiate()
	var main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = PATH
	root.add_child(shell)
	await process_frame
	main.maze_controller.new_run(77)
	check(main.maze_controller.choose_talent("sentry_guard"), "正式主流程选择初始天赋")
	var old := (load("res://resources/cards/ore_appraiser.tres") as CardData).duplicate(true) as CardData
	old.runes.resize(2)
	old.wound_slot_count = 3
	old.emblem_slot_count = 1
	var owned := OwnedCard.new()
	owned.initialize(old, &"run_card_0100", 100)
	owned.resolved_runes.assign([4, 1])
	owned.rune_revealed[0] = true
	owned.record_rune_scrape_pixels(1, [Vector2i(11, 11)])
	var mask := owned.rune_scrape_masks[1]
	owned.rune_stickers[1] = {"emblem_id": &"火元素", "element": 0, "instance_id": &"old_element_main"}
	for index: int in owned.wound_slots.size():
		owned.wound_slots[index] = {"wound_id": &"中毒Ⅰ", "level": 1, "instance_id": StringName("old_wound_main_%d" % index)}
	check(main.owned_card_collection.add_existing(owned), "真实收藏添加旧规则实例")
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	main._sync_legacy_collection_cards()
	check(main.save_run_to_path(PATH) == OK, "正式主流程保存旧规则实例与部署")
	var service := SAVE.new()
	var checkpoint: Dictionary = service.load_checkpoint(PATH).checkpoint
	checkpoint.schema_version = 8
	checkpoint.status_slot_migration_version = 1
	check(service.save_checkpoint(PATH, checkpoint) == OK, "写入原版本标记")
	shell.queue_free()
	await process_frame
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = PATH
	root.add_child(shell)
	await process_frame
	check(main.load_run_from_path(PATH), "新主场景真实载入旧存档")
	var current: OwnedCard = main.owned_card_collection.get_by_instance_id(&"run_card_0100")
	if current == null: print(main._last_run_persistence_result); shell.queue_free(); quit(1); return
	check(current.resolved_runes.size() == 3 and current.resolved_runes.slice(0, 2) == [4, 1] and current.rune_revealed == [true, false, false], "主流程补齐第三槽且不重抽原符文")
	check(current.rune_scrape_masks[1] == mask and current.rune_stickers[1].instance_id == "old_element_main", "主流程保留付费擦痕和原元素贴纸")
	check(current.wound_slots.size() == 2 and current.emblem_slots.size() == 2, "拥有实例与卡面统一2／2")
	var returned: Array = main.emblem_library.get_inventory_state().filter(func(item: Dictionary) -> bool: return String(item.instance_id).begins_with("old_wound_main_"))
	check(returned.size() == 3 and returned.all(func(item: Dictionary) -> bool: return item.kind == "wound" and item.wound_id == &"中毒Ⅰ"), "超额伤势按既有开发模式规则完整退回工具箱")
	var updated: Dictionary = service.load_checkpoint(PATH).checkpoint
	check(int(updated.schema_version) == SAVE.SCHEMA_VERSION and int(updated.status_slot_migration_version) == SAVE.STATUS_SLOT_MIGRATION_VERSION, "载入成功后立即保存新版迁移标记")
	var runes := current.resolved_runes.duplicate()
	check(main.load_run_from_path(PATH), "新版存档可再次载入")
	current = main.owned_card_collection.get_by_instance_id(&"run_card_0100")
	check(current.resolved_runes == runes and main.emblem_library.get_inventory_state().filter(func(item: Dictionary) -> bool: return String(item.instance_id).begins_with("old_wound_main_")).size() == 3, "重复载入不重抽符文、不重复返还伤势")
	shell.queue_free()
	await process_frame
	print("主流程槽位迁移：%d项，%d失败" % [assertions, failures])
	quit(failures)
