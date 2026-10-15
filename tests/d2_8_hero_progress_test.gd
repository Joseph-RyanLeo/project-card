extends SceneTree

const HeroProgress = preload("res://scripts/data/hero_progress_state.gd")
const SaveService = preload("res://scripts/data/run_save_service.gd")
const SAVE_PATH := "/private/tmp/project-card-d2-8-hero-progress.json"

# 以下曲线与天赋ID仅是纯数据单元测试输入，不是正式英雄配置。
const THRESHOLDS: Array[int] = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90]
var failures: int = 0
var assertions: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _choices() -> Dictionary:
	var result: Dictionary = {}
	for talent_level: int in [1, 4, 7, 10]:
		result[str(talent_level)] = ["test_%d_a" % talent_level, "test_%d_b" % talent_level,
			"test_%d_c" % talent_level, "test_%d_d" % talent_level]
	return result


func _run() -> void:
	var source_config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/demo2/ioann_warden_config.json"))
	_expect(source_config is Dictionary and source_config.initial_card_ids.size() == 5, "正式英雄配置记录五张初始卡")
	var configured := HeroProgress.new()
	_expect(configured.initialize(THRESHOLDS, source_config.talent_choices), "图片录入的完整天赋ID表可供状态脚本使用")
	_expect(configured.get_pending_choices() == ["sentry_guard", "sentry_break", "sentry_sharp", "sentry_spell"], "一级四选一对应护破锐咒")
	var cards_found := true
	for card_id: String in source_config.initial_card_ids:
		var card := load("res://resources/cards/%s.tres" % card_id) as CardData
		cards_found = cards_found and card != null and String(card.id) == card_id
	_expect(cards_found, "五张初始卡均对应已有真实资源")
	var hero := HeroProgress.new()
	_expect(not hero.initialize([], _choices()), "缺失经验曲线拒绝初始化")
	_expect(not hero.initialize(THRESHOLDS, {}), "缺失完整天赋配置拒绝初始化")
	_expect(hero.initialize(THRESHOLDS, _choices()), "完整配置初始化")
	_expect(hero.level == 1 and hero.experience == 0 and hero.pending_talent_levels == [1], "开局先选1级天赋")
	_expect(not hero.choose_talent("test_4_a"), "不能提前选择4级天赋")
	_expect(hero.choose_talent("test_1_b"), "合法初始天赋入账")
	_expect(hero.grant_experience("event_1", 90), "一次事件经验可跨多个等级")
	_expect(hero.level == 10 and hero.pending_talent_levels == [4, 7, 10], "全量经验先入账，再按4、7、10级排队")
	_expect(not hero.grant_experience("event_1", 90) and hero.experience == 90, "重复奖励身份不能再次获得经验")
	_expect(not hero.grant_experience("invalid", -1), "负经验拒绝入账")
	_expect(not hero.choose_talent("test_7_a"), "跨档选择不能跳过4级")
	_expect(hero.choose_talent("test_4_c") and hero.has_talent("test_1_b"), "选择新天赋保留旧天赋")
	var before := hero.capture_state()
	var save := SaveService.new()
	_expect(save.save_checkpoint(SAVE_PATH, {"schema_version": SaveService.SCHEMA_VERSION, "hero_progress": before}) == OK, "真实JSON磁盘保存")
	var restored := HeroProgress.new()
	restored.initialize(THRESHOLDS, _choices())
	var loaded := save.load_checkpoint(SAVE_PATH)
	_expect(bool(loaded.get("success", false)) and restored.restore_state(loaded.checkpoint.hero_progress), "JSON数字转换后恢复成功")
	_expect(restored.capture_state() == before, "读档保留等级、已选、待选和奖励凭证")
	_expect(not restored.grant_experience("event_1", 90), "读档后仍拒绝重复经验")
	var damaged := before.duplicate(true)
	damaged.pending_talent_levels = [10, 7]
	_expect(not restored.restore_state(damaged) and restored.capture_state() == before, "损坏队列拒绝载入且原状态不变")
	damaged = before.duplicate(true)
	damaged.level = 7
	_expect(not restored.restore_state(damaged), "等级与经验不一致拒绝载入")
	damaged = before.duplicate(true)
	damaged.experience = 90.5
	_expect(not restored.restore_state(damaged), "小数经验拒绝载入")
	damaged = before.duplicate(true)
	damaged.selected_talents["7"] = "test_7_a"
	damaged.selected_talents.erase("4")
	_expect(not restored.restore_state(damaged), "已选天赋不能跳过较低档")
	damaged = before.duplicate(true)
	damaged.committed_experience_awards.append("event_1")
	_expect(not restored.restore_state(damaged), "重复凭证拒绝载入")
	_expect(restored.choose_talent("test_7_a") and restored.choose_talent("test_10_d"), "恢复后按顺序完成剩余选择")
	_expect(restored.pending_talent_levels.is_empty() and restored.selected_talents.size() == 4, "所有天赋选择完成")
	_expect(restored.grant_experience("lost_battle_1", 10) and restored.level == 10 and restored.experience == 100, "满级后保留总经验，不超配置最高级")
	DirAccess.remove_absolute(SAVE_PATH)
	print("D2-8 hero progress: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
