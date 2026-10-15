extends SceneTree

const Rewards = preload("res://scripts/data/maze_reward_service.gd")
const Hero = preload("res://scripts/data/hero_progress_state.gd")
const Indicator = preload("res://scripts/data/sentry_indicator.gd")
const Style = preload("res://scripts/ui/sentry_indicator_style.gd")
var assertions := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var service := Rewards.new()
	_expect(service.load_config(), "正式奖励配置可读取")
	var thresholds: Array[int] = []
	thresholds.assign(service.config.experience.level_thresholds)
	var hero := Hero.new()
	_expect(hero.initialize(thresholds, service.config.talent_choices), "已确认正式经验曲线接入英雄状态")
	var rng := RandomNumberGenerator.new()
	rng.seed = 103081
	var expected_levels := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	var reached: Dictionary = {1: "1-0"}
	for floor_number: int in range(1, 4):
		for day: int in range(1, 9):
			var reward := service.build_battle_reward(floor_number, true, rng)
			_expect(reward.success and reward.experience == 2 + 4 * (floor_number - 1), "第%d层胜利经验公式" % floor_number)
			var previous := hero.level
			hero.grant_experience("%d-%d" % [floor_number, day], int(reward.experience))
			if hero.level > previous:
				reached[hero.level] = "%d-%d" % [floor_number, day]
	var positions := ["1-0", "1-1", "1-3", "1-6", "2-1", "2-3", "2-5", "2-7", "3-1", "3-3"]
	for index: int in expected_levels.size():
		_expect(reached.get(expected_levels[index]) == positions[index], "全胜正式曲线%d级到达%s" % [index + 1, positions[index]])
	for floor_number: int in range(1, 4):
		var loss := service.build_battle_reward(floor_number, false, rng)
		_expect(loss.success and loss.gold >= 1 and loss.gold <= 6 and loss.drop.is_empty() and loss.experience == floor_number, "失败1～6金币、没有随机掉落且经验等于层数")
	var counts := {"gold": 0, "scraper": 0, "emblem": 0}
	var basic := EmblemLibraryData.get_basic_emblem_ids()
	var valid := true
	for draw: int in 10000:
		var result := service.build_battle_reward(1, true, rng)
		var drop: Dictionary = result.drop
		counts[drop.kind] = int(counts[drop.kind]) + 1
		if drop.kind == "gold":
			valid = valid and int(drop.amount) in [1, 2, 3] and result.gold == 12 + int(drop.amount)
		elif drop.kind == "scraper":
			valid = valid and drop.amount == 1 and result.gold == 12
		else:
			valid = valid and drop.amount == 1 and StringName(drop.emblem_id) in basic and result.gold == 12
	_expect(valid, "一万次真实抽取全部遵守12基础金币和三种掉落规格")
	_expect(absi(int(counts.gold) - 6000) < 200 and absi(int(counts.scraper) - 3000) < 200 and absi(int(counts.emblem) - 1000) < 200, "固定种子抽取分布符合6:3:1权重")
	var replay := RandomNumberGenerator.new()
	replay.seed = rng.seed
	replay.state = rng.state
	_expect(service.build_battle_reward(2, true, rng) == service.build_battle_reward(2, true, replay) and rng.state == replay.state, "完整随机状态恢复后掉落与随机流一致")
	var old_state := rng.state
	_expect(not service.build_battle_reward(0, true, rng).success and rng.state == old_state, "非法层数不消费随机数")
	var collection := OwnedCardCollection.new()
	var first := collection.create_card(load("res://resources/cards/musketeer.tres"), rng)
	var full := collection.create_card(load("res://resources/cards/shieldwall_private.tres"), rng)
	collection.create_card(load("res://resources/cards/coarse_bandage.tres"), rng)
	for index: int in full.wound_slots.size():
		full.set_wound_slot(index, {"wound_id": "中毒Ⅰ", "level": 1, "temporary": false})
	var full_before := full.capture_state()
	var outcome := service.apply_random_event_wound("test_event_1", collection.get_cards(), rng)
	_expect(outcome.success and outcome.applied and outcome.owned_instance_id == String(first.instance_id), "仅选择有空槽的已拥有随从，装备和满槽随从不参与")
	_expect(first.wound_slots[int(outcome.slot_index)].wound_id == outcome.wound_id and not first.wound_slots[int(outcome.slot_index)].temporary, "事件直接写入随从永久伤势槽")
	_expect(full.capture_state() == full_before, "满槽目标不被替换或升级")
	old_state = rng.state
	_expect(not service.apply_random_event_wound("test_event_1", collection.get_cards(), rng).success and rng.state == old_state, "同一事件已添加的伤势不会再重复添加")
	var no_targets: Array[OwnedCard] = [full]
	_expect(service.apply_random_event_wound("test_event_2", no_targets, rng) == {"success": true, "applied": false} and rng.state == old_state, "无目标事件不执行且不消费随机数")
	var empty: Array[OwnedCard] = []
	_expect(not service.apply_random_event_wound("", empty, rng).success, "伤势事件必须具有稳定身份")
	var variants: Dictionary = {}
	for index: int in 400:
		var indicator := Indicator.new()
		indicator.initialize(StringName("sentry_%d" % index), rng)
		variants[indicator.visual_variant] = true
		var restored := Indicator.from_state(JSON.parse_string(JSON.stringify(indicator.capture_state())))
		_expect(restored != null and restored.capture_state() == indicator.capture_state(), "哨位%d外观随实例JSON往返" % index)
	_expect(variants.size() == 4, "四种外观均可随机出现")
	for index: int in 4:
		var texture := Style.get_texture(index)
		_expect(texture != null and texture.get_size() == Vector2(46 if index % 2 == 0 else 47, 54), "哨位第%d款图集切片大小正确" % index)
		var indicator := Indicator.new()
		indicator.visual_variant = index
		var visual := Style.create_visual(indicator)
		_expect(visual.texture == texture and visual.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "哨位按固定外观显示并使用像素采样")
		visual.free()
	_expect(Indicator.from_state({"instance_id": "bad", "visual_variant": 4}) == null and Style.get_texture(-1) == null, "非法外观拒绝恢复和显示")
	print("Reward sample counts: ", counts)
	print("D2-8 rewards/sentry: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
