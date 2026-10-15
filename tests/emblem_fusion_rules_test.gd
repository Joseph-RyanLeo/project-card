extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if value: print("PASS: " + message)
	else:
		failures += 1
		push_error(message)

func _run() -> void:
	for recipe: Dictionary in EmblemFusionRecipes.RECIPES:
		check(EmblemFusionRecipes.resolve(recipe.a, recipe.b).id == recipe.id and EmblemFusionRecipes.resolve(recipe.b, recipe.a).id == recipe.id, "双向配方：" + recipe.id)
	check(EmblemFusionRecipes.resolve(&"四叶草Ⅱ", &"四叶草Ⅱ").result == &"四叶草Ⅲ", "高阶替代优先三级结果")
	check(EmblemFusionRecipes.resolve(&"盾牌Ⅲ", &"长剑").result == &"刺盾", "任意等级盾牌可合刺盾")
	check(EmblemFusionRecipes.resolve(&"盾牌Ⅱ", &"四叶草Ⅰ").is_empty(), "不同系列不能按稀有度替代")
	check(EmblemFusionRecipes.resolve(&"种子", &"种子").is_empty(), "种子战后进化不误当两材料合成")
	var bag := EmblemStickerInventory.new()
	bag.add({"instance_id": &"source", "emblem_id": &"四叶草Ⅱ", "saved_progress": {"old": 2}, "grid_x": 1, "grid_y": 0})
	var owned := OwnedCard.new()
	owned.initialize(load("res://resources/cards/militia.tres"), &"fusion_card", 0)
	owned.set_emblem_slot(0, {"instance_id": &"target", "emblem_id": &"四叶草Ⅰ"})
	owned.progress_by_source[&"target"] = 2
	for row: int in 7:
		for column: int in 4:
			if Vector2i(column, row) == Vector2i(1, 0): continue
			bag.add({"instance_id": "filler_%d_%d" % [column, row], "emblem_id": &"面包", "grid_x": column, "grid_y": row})
	var before := bag.get_items()
	var old_slots := owned.emblem_slots.duplicate(true)
	check(not bag.has_method("fuse"), "删除工具箱两枚合成接口")
	check(bag.fuse_onto_card(&"source", owned, 0, &"wrong_target").is_empty() and bag.get_items() == before and owned.emblem_slots == old_slots, "失效目标身份拒绝提交，卡槽及库存均不变")
	var result := bag.fuse_onto_card(&"source", owned, 0, &"target")
	check(not result.is_empty() and bag.get_items().size() == 27 and result.emblem_id == &"四叶草Ⅲ", "满工具箱仍可消耗材料在卡上合成")
	check(owned.emblem_slots[0] == result and not result.has("grid_x") and not result.has("saved_progress") and not owned.progress_by_source.has(&"target"), "结果只占原卡槽并清除旧材料成长")
	check(bag.fuse_onto_card(&"source", owned, 0, &"target").is_empty() and bag.get_items().size() == 27, "重复提交不会再消耗")
	var path := "/private/tmp/project-card-emblem-discovery-test.json"
	DirAccess.remove_absolute(path)
	var discovery := EmblemRecipeDiscovery.new()
	discovery.save_path = path
	discovery.load_discoveries()
	check(not discovery.is_known("clover_3"), "首次配方未知")
	discovery.encounter("clover_3")
	check(discovery.is_known("clover_3") and not FileAccess.file_exists(path), "局内见过即展示，取消不写永久记录")
	check(discovery.discover("clover_3"), "成功合成立即保存永久发现")
	var loaded := EmblemRecipeDiscovery.new()
	loaded.save_path = path
	loaded.load_discoveries()
	check(loaded.is_known("clover_3") and not loaded.is_known("clover_2") and not loaded.is_known("sandwich_cheese"), "跨局发现仅揭晓该配方")
	loaded.discover("sandwich_cheese")
	check(not loaded.is_known("sandwich_ham"), "同结果的另一配方独立发现")
	DirAccess.remove_absolute(path)
	print("Emblem fusion rules failures: ", failures)
	quit(1 if failures else 0)
