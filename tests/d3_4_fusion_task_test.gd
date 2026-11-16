extends SceneTree

const SHELL = preload("res://scenes/StartMenu.tscn")
const DIR := "/private/tmp/project-card-d3-4-fusion-test"
var checks := 0
var failures := 0
var main
var owned: OwnedCard


func _initialize() -> void: _run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func fusion(source: Dictionary, target: Dictionary, fail_save: bool = false) -> void:
	if not owned.emblem_slots[0].is_empty(): main.emblem_library.return_sticker(owned.emblem_slots[0])
	owned.set_emblem_slot(0, target)
	main.emblem_library.consume_returned(target)
	main._refresh_owned_card_status_visuals(owned)
	main._refresh_inspection_markers()
	check(main._begin_emblem_fusion(StringName(source.instance_id), 0, {}, Vector2(400, 300)), "开启真实纹章融合演出")
	var overlay = main._emblem_fusion_overlay
	if overlay == null: return
	while overlay.stage == &"opening": await process_frame
	var path: String = main.run_save_path
	if fail_save: DirAccess.make_dir_absolute(path + ".tmp")
	overlay.confirm()
	while is_instance_valid(main._emblem_fusion_overlay): await process_frame
	if fail_save: DirAccess.remove_absolute(path + ".tmp")


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("S1专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(DIR)
	var shell = SHELL.instantiate()
	shell.run_slots.directory = DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	await process_frame
	check(await shell.start_slot(0), "创建S1独立测试档")
	var p: ProfileProgress = shell.slot_progress
	check(p.complete_tutorial() and p.purchase_catalog_task("supply_first") and p.complete_task("supply_first", TaskCatalog.rewards_for("supply_first")), "准备S1已开放的资格夹具")
	check(p.credit_once("fusion_fixture", 4000) and p.purchase_catalog_task("witch_cauldron") and p.select_catalog_tasks("", "witch_cauldron"), "按4000积分购买并选择S1")
	check(await shell.start_new_slot_run(), "正式开启S1专项局")
	await process_frame
	main = shell.main_screen
	main._emblem_recipe_discovery.save_path = DIR.path_join("recipes.json")
	check(main.emblem_library.get_inventory_state().size() == 4 and main.run_item_enabled("emblem_fusion") and not main.profile_progress.profile.unlocks.items.has("emblem_fusion"), "赠送四枚指定材料并仅当局试用融合")
	var view: CardView
	for slot: Control in main._get_collection_card_slots():
		if slot.get_child_count() == 0: continue
		var candidate = slot.get_child(0)
		if candidate is CardView and candidate.get_owned_card().card_data.card_type == CardData.CardType.MINION:
			view = candidate
			break
	owned = view.get_owned_card()
	main._open_card_inspection(view.card_data, owned, view)
	await create_timer(0.4).timeout
	main._toggle_inspection_library()
	await create_timer(0.4).timeout
	var supplies: Array = main.emblem_library.get_inventory_state()
	await fusion(supplies[0], supplies[1])
	check(main.profile_progress.run.tasks.side.progress.get("fusion_count", 0) == 1, "一次成功融合仅计1枚产物，非两枚投入")
	await fusion(supplies[2], supplies[3])
	check(main.profile_progress.run.tasks.side.progress.fusion_count == 2, "初始两组材料完成两次融合")
	for index: int in 3:
		# 窄范围材料夹具验证第3至5次，不伪造融合结果／进度。
		var source := {"instance_id": "fusion_source_%d" % index, "emblem_id": "长剑", "temporary": false, "source": "test_fixture"}
		var target := {"instance_id": "fusion_target_%d" % index, "emblem_id": "盾牌Ⅰ", "temporary": false, "source": "test_fixture"}
		check(main.emblem_library.receive_stickers([source, target]), "准备本次真实配方材料")
		if index == 2:
			await fusion(source, target, true)
			check(main.profile_progress.run.tasks.side.progress.fusion_count == 4 and not main.profile_progress.profile.tasks.witch_cauldron.completed, "第5次保存失败不完成任务")
			check(owned.emblem_slots[0].emblem_id == "盾牌Ⅰ" and not main.emblem_library.get_inventory_item(StringName(source.instance_id)).is_empty(), "融合保存失败还原两枚材料")
		await fusion(source, target)
	check(main.profile_progress.profile.tasks.witch_cauldron.completed and main.profile_progress.run.tasks.side.progress.fusion_count == 5, "第5次成功融合正式完成S1")
	check(main.profile_progress.profile.unlocks.items.has("emblem_fusion") and main.profile_progress.profile.unlocks.items.has("刺盾"), "永久开放融合与对应图鉴内容")
	main._close_card_inspection(true)
	check(main.finish_maze_run("abandoned") and main.profile_progress.profile.tasks.witch_cauldron.completed, "后续主动放弃不撤销已完成S1")
	shell.free()
	print("D3-4 fusion: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
