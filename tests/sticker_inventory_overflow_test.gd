extends SceneTree

const Inventory = preload("res://scripts/data/emblem_sticker_inventory.gd")
var failures := 0
var ranks := {"光贴纸": 1, "混沌贴纸": 2, "火把": 0, "长剑": 0, "宝石": 1, "宝藏": 4}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func _run() -> void:
	var bag := Inventory.new()
	var old: Array[Dictionary] = []
	for y: int in 7:
		for x: int in 4:
			if (x + y) % 2 == 0: continue
			old.append({"instance_id": "old_%d_%d" % [x, y], "emblem_id": "长剑" if y % 2 == 0 else "火把", "grid_x": x, "grid_y": y})
	check(bag.restore(old) and bag.free_cell_count() == 14, "棋盘状零散空位按实际面积统计")
	var incoming: Array[Dictionary] = [item("common", "火把"), item("light", "光贴纸", true), item("rare", "宝藏"), item("gem", "宝石"), item("chaos", "混沌贴纸", true)]
	check(bag.receive(incoming, ranks) and bag.get_items().size() == 19, "自动整理完整接收五枚，保留旧实例")
	var packed := bag.get_items()
	check(String(packed[0].emblem_id) == "混沌贴纸" and String(packed[1].emblem_id) == "光贴纸" and String(packed[2].emblem_id) == "宝藏" and String(packed[3].emblem_id) == "宝石", "元素优先，其内按稀有度；普通也从高到低")
	var groups: Array[String] = []
	for state: Dictionary in packed:
		if groups.is_empty() or groups.back() != String(state.emblem_id): groups.append(String(state.emblem_id))
	check(groups.size() == 6, "同名实例连续排序，不与其他种类穿插")
	check(not packed.any(func(state: Dictionary): return Inventory.is_dropped(state)) and bag.free_cell_count() == 3, "2×2元素正确占四格，不重叠、不超界")
	var mirror := Inventory.new()
	check(mirror.restore(JSON.parse_string(JSON.stringify(packed))) and JSON.stringify(mirror.get_items()) == JSON.stringify(packed), "整理后格位可以完整保存并恢复")
	var before := bag.get_items()
	check(not bag.receive([item("common", "长剑")], ranks) and bag.get_items() == before, "重复身份拒绝整批，不修改库存")
	check(not bag.receive([item("invalid", "")], ranks) and bag.get_items() == before, "无效定义身份拒绝且不遗失旧贴纸")
	check(bag.receive([item("overflow_element", "光贴纸", true)], ranks) and Inventory.is_dropped(bag.get_item(&"overflow_element")), "不足元素所需格位时保留为掉落，不阻止获得")
	check(bag.move_to_drop(&"common", Vector2(5, 3)) and bag.move_to_drop(&"rare", Vector2(5, 3)), "两枚掉落可以精确重叠，不互相挤占")
	check(bag.free_cell_count() == 5 and bag.get_item(&"common").drop_position == [5.0, 3.0], "移出格位立即释放空间并保存自由坐标")
	var identity: String = String(bag.get_item(&"common").instance_id)
	check(bag.move(&"common", Vector2i(0, 2)) and not Inventory.is_dropped(bag.get_item(&"common")) and bag.get_item(&"common").instance_id == identity, "掉落回包仍沿用同一实例")
	var count := bag.get_items().size()
	bag.discard_dropped()
	check(bag.get_items().size() == count - 2 and not bag.get_item(&"common").is_empty() and bag.get_item(&"rare").is_empty(), "销毁只移除临时区域，保留格内贴纸")
	# 17枚普通占格，剩11格；全量排序必须能容纳2元素+3普通，不受输入顺序影响。
	var tight := Inventory.new()
	for i: int in 17: tight.add(item("tight_%02d" % i, "火把"))
	check(tight.receive([item("t1", "火把"), item("t2", "火把"), item("t3", "火把"), item("t4", "光贴纸", true), item("t5", "混沌贴纸", true)], ranks) and tight.free_cell_count() == 0 and not tight.get_items().any(func(state: Dictionary): return Inventory.is_dropped(state)), "先放普通会阻塞的11格布局经整理后五枚全部容纳")
	# 新贴纸超出容量时，原有库存优先保留在包内。
	var eight := Inventory.new()
	for i: int in 20: eight.add(item("retained_%02d" % i, "火把"))
	check(eight.receive([item("e1", "光贴纸", true), item("e2", "光贴纸", true), item("e3", "光贴纸", true), item("e4", "光贴纸", true), item("e5", "光贴纸", true)], ranks), "自动整理后仍超额也成功接收")
	check(eight.get_items().filter(func(state: Dictionary): return Inventory.is_dropped(state)).size() == 3 and eight.free_cell_count() == 0, "只把放不下的三枚新元素放入临时区域")
	check(eight.get_items().filter(func(state: Dictionary): return String(state.instance_id).begins_with("retained") and not Inventory.is_dropped(state)).size() == 20, "整理不把任何旧格内贴纸挤到临时区域")
	print("Sticker overflow model failures: ", failures)
	quit(1 if failures else 0)

func item(id: String, emblem: String, element: bool = false) -> Dictionary:
	return {"instance_id": id, "emblem_id": emblem, "element_sticker": element}
