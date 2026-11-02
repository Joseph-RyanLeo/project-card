extends SceneTree

## 全部文件固定在独立/tmp目录；write/read由两个Godot进程验证真正的重启恢复。
const Progress = preload("res://scripts/data/profile_progress.gd")
const Save = preload("res://scripts/data/run_save_service.gd")
const Slots = preload("res://scripts/data/run_slot_service.gd")
const DIR := "/private/tmp/project-card-d3-1-data-test"
var failures := 0
var checks := 0
var slots := Slots.new()
var save := Save.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	slots.directory = DIR
	DirAccess.make_dir_recursive_absolute(DIR)
	if OS.get_cmdline_user_args().has("read"):
		_read_restart()
	else:
		_write_and_verify()
	print("D3-1 data checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func checkpoint(progress: RefCounted, cards: OwnedCardCollection) -> Dictionary:
	var rows := {}
	for key: StringName in Save.ROW_KEYS: rows[key] = []
	var result := save.create_checkpoint(cards.capture_state(), rows, 42, &"", 1, RunRewardState.new(), RunSettlementJournal.new(), 0)
	result.profile_progress = progress.capture_state()
	return result


func load_progress(index: int) -> RefCounted:
	var loaded := save.load_checkpoint(slots.get_slot_path(index))
	var progress := Progress.new()
	check(loaded.get("success", false) and progress.restore_state(loaded.get("checkpoint", {}).get("profile_progress", {})), "从真实JSON恢复档%d局外数据" % index)
	return progress


func _write_and_verify() -> void:
	for index: int in 3: slots.delete_slot(index)
	var card_data := load("res://resources/cards/heavy_knight.tres") as CardData
	var spells := load("res://resources/cards/damage_fireball.tres") as CardData
	var collection := OwnedCardCollection.new()
	var a := collection.create_card(card_data)
	a.acquired_at = 1793535000
	a.acquisition_source = {"kind": "pack", "pack_id": "ash_ledger", "name": "灰烬证册"}
	a.recruited_by = Progress.INITIAL_HERO
	a.lifetime_stats = {"damage": 150, "healing": 4, "kills": 3, "armor_granted": 8, "damage_taken": 31, "battles": 2, "deaths": 1, "mining": 1, "gold_generated": 9}
	a.apply_permanent_growth(&"base_value", 2)
	a.rune_revealed[0] = true
	a.wound_slots[0] = {"wound_id": &"scar", "level": 1}
	var b := collection.create_card(card_data)
	var c := collection.create_card(card_data)
	var d := collection.create_card(card_data)
	var spell := collection.create_card(spells)
	spell.spell_durability = 0
	for index: int in 3:
		var progress := Progress.new()
		check(progress.profile.points == 0 and progress.profile.unlocks.heroes == [Progress.INITIAL_HERO] and progress.profile.unlocks.packs == ["ash_ledger"], "新档积分0，仅伊奥恩与灰烬证册")
		check(progress.credit_once("fixture", (index + 1) * 1000), "独立积分入账")
		check(not progress.credit_once("fixture", 999), "同凭证不得重复发分")
		check(progress.purchase_task("fixture_task", 100), "资格确认购买才扣分")
		check(not progress.purchase_task("fixture_task", 100), "已购资格不重复扣费")
		check(progress.select_tasks("fixture_task", "") and progress.start_run(), "最多一主线一支线，开局保存所选任务")
		check(not progress.select_tasks("", "fixture_task"), "本局开启后不换任务")
		progress.run.tasks.main.progress = {"gold": 10}
		progress.note_discovery("cards", "heavy_knight")
		check(not progress.profile.discoveries.cards.has("heavy_knight"), "事件中发现尚未永久提交")
		progress.commit_discoveries()
		progress.note_discovery("stickers", "seed")
		check(progress.remember_exhausted_spell(spell), "耗尽法术另存完整实例候选")
		if index == 0:
			check(progress.complete_task("fixture_task", {"packs": ["ironwall_inscription"], "items": ["scraper"], "routes": ["eight_days"], "growth": ["initial_gold_1"]}), "保存资格完成与各类解锁")
			check(progress.begin_collection(collection.get_cards()), "从真实单卡冻结本次候选")
			var snapshot_value: float = progress.run.candidates[String(a.instance_id)].permanent_growth.base_value
			a.permanent_growth[&"base_value"] = 999
			check(progress.run.candidates[String(a.instance_id)].permanent_growth.base_value == snapshot_value, "候选冻结后不随局内实例修改")
			a.permanent_growth[&"base_value"] = snapshot_value
			check(not progress.set_selection([{"candidate_id": "missing", "slot": 0}]), "拒绝不存在的候选")
			check(not progress.set_selection([{"candidate_id": String(a.instance_id), "slot": 1}]), "不得跳过左侧空位")
			check(not progress.set_selection([{"candidate_id": String(a.instance_id), "slot": 0}, {"candidate_id": String(a.instance_id), "slot": 1}]), "同一单卡不重复选择")
			check(progress.set_selection([{"candidate_id": String(a.instance_id), "slot": 0}, {"candidate_id": String(b.instance_id), "slot": 1}, {"candidate_id": String(c.instance_id), "slot": 2}]), "同种按从左到右填满3位置")
			check(progress.show_preview() and progress.profile.collection.is_empty(), "预览不正式入藏")
			check(progress.confirm_collection() and progress.profile.collection.heavy_knight.size() == 3, "最终确认一次提交3张")
			check(progress.start_run() and progress.begin_collection([d, spell]), "下一局收藏身份使用新run_id")
			check(not progress.set_selection([{"candidate_id": String(d.instance_id), "slot": 1}]), "满3张的替换须确认具体旧卡")
			var old_id: String = progress.profile.collection.heavy_knight[1].archive_id
			check(progress.set_selection([{"candidate_id": String(d.instance_id), "slot": 1, "replaced_id": old_id, "replacement_confirmed": true}, {"candidate_id": String(spell.instance_id), "slot": 0}]), "保存新卡与被换旧卡的明确关系")
			check(progress.show_preview() and progress.profile.collection.heavy_knight[1].archive_id == old_id, "替换预览不移除旧收藏")
		elif index == 1:
			check(progress.begin_collection(collection.get_cards()) and progress.set_selection([{"candidate_id": String(a.instance_id), "slot": 0}]), "选卡阶段也可保存已选实例")
		check(save.save_checkpoint(slots.get_slot_path(index), checkpoint(progress, collection)) == OK, "档%d首次落盘" % index)
	# 故障在真实文件系统制造：临时路径被目录占用，不可改写有效主档。
	var path := slots.get_slot_path(2)
	var original := FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	check(save.save_checkpoint(path, {"schema_version": 9, "changed": true}) != OK and FileAccess.get_file_as_string(path) == original, "临时写入失败保护有效原档")
	DirAccess.remove_absolute(path + ".tmp")
	# 备份路径无法复制，同样不许先移走原文件。
	DirAccess.make_dir_absolute(path + ".bak")
	check(save.save_checkpoint(path, {"schema_version": 9, "changed": true}) != OK and FileAccess.get_file_as_string(path) == original, "备份失败保护原档，禁止半份替换")
	DirAccess.remove_absolute(path + ".bak")
	var filter_progress := Progress.new()
	filter_progress.start_run()
	var filtered_collection := OwnedCardCollection.new()
	filtered_collection.create_card(load("res://resources/cards/gear_scrap.tres"))
	filtered_collection.create_card(load("res://resources/cards/militia.tres"))
	check(filtered_collection.acquired_discoveries.get("gear_scrap") == "resources", "实际获得衍生资源仍记录资源图鉴")
	check(filter_progress.begin_collection(filtered_collection.get_cards()) and filter_progress.run.candidates.size() == 1, "资源卡排除在局外候选外")
	var too_many := Progress.new()
	too_many.start_run()
	var many := OwnedCardCollection.new()
	var choices: Array = []
	for index: int in 9:
		var definition := load("res://resources/cards/%s.tres" % ["militia", "heavy_knight", "spark_mage", "field_medic", "diplomat", "fireman", "musketeer", "moon_dancer", "mining_pick"][index]) as CardData
		var owned := many.create_card(definition)
		choices.append({"candidate_id": String(owned.instance_id), "slot": 0})
	check(too_many.begin_collection(many.get_cards()) and not too_many.set_selection(choices), "拒绝一次选择超过8张")
	var invalid := Progress.new()
	var before := invalid.capture_state()
	var broken := before.duplicate(true)
	broken.profile.points = -1
	check(not invalid.restore_state(broken) and invalid.capture_state() == before, "损坏积分拒绝恢复且不污染内存")
	broken = before.duplicate(true)
	broken.run.selection = 7
	check(not invalid.restore_state(broken), "损坏阶段字段拒绝恢复")
	broken = before.duplicate(true)
	broken.version = {}
	check(not invalid.restore_state(broken), "错误类型版本字段拒绝恢复")
	check(not slots.can_skip_tutorial(), "无实际教程通关记录，不从Demo2通关猜测跳过资格")


func _read_restart() -> void:
	var p0 := load_progress(0)
	var p1 := load_progress(1)
	var p2 := load_progress(2)
	check([p0.profile.points, p1.profile.points, p2.profile.points] == [900, 1900, 2900], "进程重启后3档积分独立保留")
	check(p0.run.stage == "preview" and p1.run.stage == "selection" and p2.run.stage == "active", "进程重启精确恢复集合/选卡/本局三个阶段")
	check(p0.profile.tasks.fixture_task.completed and not p1.profile.tasks.fixture_task.completed, "任务完成与购买资格三档隔离")
	check(p0.profile.unlocks.growth == ["initial_gold_1"] and p1.profile.unlocks.growth.is_empty(), "永久成长与解锁三档隔离")
	check(p2.run.tasks.main.progress.gold == 10 and p2.run.pending_discoveries.stickers.seed, "本局任务进度及待提交发现保留")
	p2.run.stage = "hub"
	check(p2.start_run() and p2.run.tasks.main.progress.is_empty() and not p2.profile.tasks.fixture_task.completed, "重试新局清任务进度，保留未完成购买资格")
	var archive: Dictionary = p0.profile.collection.heavy_knight[0]
	check(int(archive.acquired_at) == 1793535000 and archive.acquisition_source.pack_id == "ash_ledger" and archive.recruited_by == Progress.INITIAL_HERO and archive.lifetime_stats.damage == 150, "获得时间、来源、征召英雄和累计战绩完整保留")
	var restored := Save.new()._decode_collection_state({"cards": [archive]}, {}, false, false, Save.SCHEMA_VERSION, false, false)
	var owned := OwnedCard.new()
	check(restored.success and owned.restore_state(restored.state.cards[0]) and owned.permanent_growth[&"base_value"] == 2 and owned.wound_slots[0].wound_id == &"scar" and owned.rune_revealed[0], "收藏实例复用现有解码并保留成长/伤势/符文")
	var left: String = p0.profile.collection.heavy_knight[0].archive_id
	var right: String = p0.profile.collection.heavy_knight[2].archive_id
	var old: String = p0.profile.collection.heavy_knight[1].archive_id
	check(p0.return_to_selection() and p0.show_preview() and p0.confirm_collection(), "集合恢复后可返回改选再确认")
	check(p0.profile.collection.heavy_knight[0].archive_id == left and p0.profile.collection.heavy_knight[2].archive_id == right and p0.profile.collection.heavy_knight[1].archive_id != old, "替换只更新原位置，不重排左右收藏")
	check(int(p0.profile.collection.damage_fireball[0].spell_durability) == int((load("res://resources/cards/damage_fireball.tres") as CardData).rarity) + 1, "法术收藏恢复全新次数")
	check(not p0.confirm_collection() and not p0.credit_once("fixture", 1000), "重复确认和读档不重复入藏/发分")
	var old_run_id: String = p0.run.id
	check(p0.start_run() and p0.run.id != old_run_id and p0.profile.points == 900 and p0.profile.collection.heavy_knight.size() == 3, "新局只清本局，积分和收藏不覆盖")
	check(p0.run.tasks.is_empty() and p0.run.pending_discoveries.cards.is_empty(), "新局重置任务进度与待提交发现")
	var empty_cards: Array[OwnedCard] = []
	check(p0.begin_collection(empty_cards) and p0.set_selection([]) and p0.show_preview() and p0.confirm_collection(), "零张收藏也经过预览和最终确认")
	var path2 := slots.get_slot_path(2)
	var bytes2 := FileAccess.get_file_as_string(path2)
	check(save.save_checkpoint(path2, save.load_checkpoint(path2).checkpoint) == OK, "覆盖成功保留上一版备份")
	check(FileAccess.file_exists(path2 + ".bak"), "覆盖后存在可读旧版备份")
	DirAccess.remove_absolute(path2)
	check(save.load_checkpoint(path2).success and slots.has_slot(2), "旧式写入中断留下备份时仍可识别和读取")
	check(save.save_checkpoint(path2, JSON.parse_string(bytes2)) == OK, "从备份恢复后可重新保存主档")
	var before_other := FileAccess.get_file_as_string(slots.get_slot_path(1))
	check(slots.delete_slot(0) == OK and not slots.has_slot(0) and not FileAccess.file_exists(slots.get_slot_path(0) + ".bak"), "删档清该档本局/局外/备份")
	check(FileAccess.get_file_as_string(slots.get_slot_path(1)) == before_other and slots.has_slot(2), "删档不修改其他两档")
	var tutorial := Progress.new()
	check(not tutorial.complete_tutorial(true), "无资格不能跳过教程领奖")
	check(tutorial.complete_tutorial(false) and not tutorial.complete_tutorial(false), "教程奖励同档仅一次且记录实际通关")
	check(save.save_checkpoint(slots.get_slot_path(0), {"schema_version": 9, "profile_progress": tutorial.capture_state()}) == OK and slots.can_skip_tutorial(), "其他新档的跳过资格只查询真实教程完成记录")
	var skipped := Progress.new()
	skipped.profile.tutorial.skip_eligible_at_creation = slots.can_skip_tutorial()
	check(skipped.complete_tutorial(true) and skipped.profile.tutorial.skipped and not skipped.profile.tutorial.actually_completed and skipped.profile.points == 1000, "跳过标完成并发引导积分，不冒充实际通关")
	for index: int in 3: slots.delete_slot(index)
