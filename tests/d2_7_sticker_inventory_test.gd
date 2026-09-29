extends SceneTree

const StickerInventory = preload("res://scripts/data/emblem_sticker_inventory.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error(message)


func _run() -> void:
	var bag := StickerInventory.new()
	var initial_items: Array[Dictionary] = []
	var all_items_added := true
	for index: int in StickerInventory.COLUMN_COUNT * StickerInventory.ROW_COUNT:
		var state := {
			"instance_id": StringName("ordinary_%02d" % index),
			"emblem_id": &"火把",
			"element_sticker": false,
		}
		initial_items.append(state)
		all_items_added = bag.add(state) and all_items_added
	var placed := bag.get_items()
	check(all_items_added and placed.size() == 28, "28枚普通贴纸进入4列×7行的固定容量")
	check(
		placed[27].get("grid_x") == 3 and placed[27].get("grid_y") == 6,
		"固定占格坐标按行优先保存至右下角"
	)
	check(
		not bag.add({"instance_id": &"overflow", "emblem_id": &"火把"})
		and bag.get_items().size() == 28,
		"第29枚贴纸被拒绝且原库存不变"
	)
	check(
		not bag.add({"instance_id": &"ordinary_00", "emblem_id": &"火把"}),
		"同一实例身份不能重复加入"
	)
	bag.remove(&"ordinary_00")
	check(
		not bag.add({"instance_id": &"element_fragmented", "emblem_id": &"光贴纸", "element_sticker": true})
		and bag.get_items().size() == 27,
		"只空出一个单格时，2×2元素贴纸无法挤入"
	)
	var positioned_bag := StickerInventory.new()
	check(
	positioned_bag.add({"instance_id": &"element_position", "emblem_id": &"光贴纸", "element_sticker": true, "grid_x": 2, "grid_y": 4})
		and positioned_bag.add({"instance_id": &"ordinary_position", "emblem_id": &"长剑", "element_sticker": false, "grid_x": 0, "grid_y": 0}),
		"元素实例一次占2×2格，普通实例占1×1格"
	)
	check(
		positioned_bag.can_move(&"ordinary_position", Vector2i(1, 0))
		and not positioned_bag.can_move(&"ordinary_position", Vector2i(2, 4))
		and not positioned_bag.can_move(&"ordinary_position", Vector2i(4, 0))
		and positioned_bag.can_move(&"element_position", Vector2i(2, 4))
		and not positioned_bag.can_move(&"element_position", Vector2i(3, 5)),
		"允许原地重叠，拒绝与其他实例冲突和跨边界放置"
	)
	check(
		not positioned_bag.move(&"ordinary_position", Vector2i(3, 5))
		and positioned_bag.get_item(&"ordinary_position").get("grid_x") == 0,
		"无效落点取消后实例仍留在原格"
	)
	check(positioned_bag.move(&"ordinary_position", Vector2i(1, 0)), "合法移动只更新目标实例坐标")
	var restored := StickerInventory.new()
	check(
		restored.restore(positioned_bag.get_items())
		and restored.get_item(&"element_position").get("grid_x") == 2
		and restored.get_item(&"element_position").get("grid_y") == 4
		and restored.get_item(&"ordinary_position").get("grid_x") == 1,
		"存档恢复保留独立实例和原有占格坐标"
	)
	check(
		not restored.restore(initial_items + [{"instance_id": &"overflow", "emblem_id": &"火把"}]),
		"读取超出固定容量的旧库存时拒绝迁移而不隐藏额外实例"
	)
	var wound := {"kind": "wound", "instance_id": &"wound_one", "wound_id": &"中毒Ⅱ", "level": 2}
	check(
		bag.remove(&"ordinary_01").size() > 0
		and bag.add(wound)
		and bag.get_item(&"wound_one").get("wound_id") == &"中毒Ⅱ"
		and bag.get_item(&"wound_one").get("level") == 2,
		"伤势使用真实独立实例占一个单格，身份与等级随存档状态保留"
	)
	check(
		bag.cell_for_local_position(Vector2(15.5, 0)) == Vector2i(1, 0)
		and bag.cell_for_local_position(Vector2(-9, 0)) == Vector2i(-1, -1),
		"格间隙按17像素步长吸附最近候选格，越出吸附范围才无候选"
	)
	print("Sticker inventory failures: ", failures)
	quit(1 if failures else 0)
