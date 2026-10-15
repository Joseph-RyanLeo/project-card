extends SceneTree

## 使用真实法术资源和战斗控制器验证队列，不替换任何效果执行器。
const Controller = preload("res://scripts/battle/battle_controller.gd")
const VOLLEY = preload("res://resources/cards/volley_order.tres")
const BOULDER = preload("res://resources/cards/giant_boulder.tres")
const STARFIRE = preload("res://resources/cards/starfire.tres")
const NIGHTFALL = preload("res://resources/cards/nightfall.tres")
var failures: int = 0
var casts: Array[Dictionary] = []
var serial: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_example(false)
	_test_example(true)
	_test_shared_queue()
	_test_empty_attempt()
	_test_projectiles()
	_test_sides()
	_test_periodic()
	_test_content_times()
	_test_late_nightfall()
	_test_current_card_times()
	print("准备法术队列：%d个失败" % failures)
	quit(1 if failures > 0 else 0)

func _spell(source: CardData, seconds: float) -> OwnedCard:
	serial += 1
	var card := source.duplicate(true) as CardData
	card.spell_preparation_seconds = seconds
	var owned := OwnedCard.new()
	owned.initialize(card, StringName("queue_spell_%d" % serial), serial)
	return owned

func _entry(side: StringName, action: int = CardData.ActionType.RANGED) -> Dictionary:
	var card := CardData.new()
	card.id = &"queue_survivor"
	card.max_health = 999
	card.base_value = 0
	card.action_type = action
	card.cooldown_seconds = 99.0
	return {"squad_data": SquadData.from_card(card), "row_key": side, "formation_index": 0, "base_cooldown_override": 99.0}

func _battle(spells: Array[OwnedCard], double: bool = false, enemy_spells: Array[OwnedCard] = [], timed: bool = false, action: int = CardData.ActionType.RANGED) -> BattleController:
	casts.clear()
	var c := Controller.new()
	root.add_child(c)
	c.use_projectile_timing = timed
	c.spell_cast_started.connect(func(spell: OwnedCard, _generation: int, _duration: float) -> void:
		casts.append({"id": spell.instance_id, "time": c.elapsed_seconds})
	)
	var context: Dictionary = {"talents": ["one_handed_casting"]} if double else {}
	c.start_battle([_entry(&"player_back", action)], [_entry(&"enemy_front")], 10010, false, &"queue_test", spells, enemy_spells, [], [], [], [], context)
	return c

func _release_times() -> Array[float]:
	var times: Array[float] = []
	for cast: Dictionary in casts: times.append(cast.time)
	return times

func _free(c: BattleController) -> void:
	c.clear_battle()
	check(c._prepared_spell_schedule.is_empty(), "清场丢弃上一场释放计划")
	c.free()

func _test_example(double: bool) -> void:
	var spells: Array[OwnedCard] = []
	for seconds: float in [3.0, 2.0, 1.0, 4.0]: spells.append(_spell(VOLLEY, seconds))
	var c := _battle(spells, double)
	c.advance_time(10.0)
	var expected: Array = [2.0, 3.0, 3.0, 7.0] if double else [3.0, 5.0, 6.0, 10.0]
	check(_release_times() == expected, "3/2/1/4秒例子：" + str(expected))
	if double:
		check(casts[1].id == spells[0].instance_id and casts[2].id == spells[2].instance_id, "同秒先释放原队列第1张，再第3张")
	else:
		check(casts[0].id == spells[0].instance_id and casts[3].id == spells[3].instance_id, "普通队列保留原顺序")
	_free(c)

func _test_shared_queue() -> void:
	var spells: Array[OwnedCard] = []
	for seconds: float in [5.0, 1.0, 1.0, 1.0]: spells.append(_spell(VOLLEY, seconds))
	var c := _battle(spells, true)
	c.advance_time(5.0)
	check(_release_times() == [1.0, 2.0, 3.0, 5.0], "后续卡总接到最早空闲的位置，不固定分奇偶组")
	_free(c)

func _test_empty_attempt() -> void:
	var empty := _spell(VOLLEY, 2.0)
	var next := _spell(BOULDER, 1.0)
	var c := _battle([empty, next], false, [], false, CardData.ActionType.MELEE)
	c.advance_time(3.0)
	check(c._elapsed_spell_attempted.has(empty.instance_id) and casts.size() == 1 and casts[0].id == next.instance_id and casts[0].time == 3.0, "无目标仍消耗机会，下一张继续读秒")
	c.player_states[0].set_runtime_action_type(CardData.ActionType.RANGED)
	c.advance_time(1.0)
	check(casts.size() == 1, "无目标法术不稍后补放")
	_free(c)

func _test_projectiles() -> void:
	var first := _spell(BOULDER, 1.0)
	var second := _spell(BOULDER, 1.0)
	var c := _battle([first, second], true, [], true)
	c.advance_time(1.0)
	check(_release_times() == [1.0, 1.0] and c._pending_projectile_contexts.size() == 2, "同秒两张立即发射，前一张弹道仍未命中")
	_free(c)

func _test_sides() -> void:
	var p1 := _spell(VOLLEY, 1.0)
	var p2 := _spell(VOLLEY, 1.0)
	var e1 := _spell(BOULDER, 1.0)
	var c := _battle([p1, p2], true, [e1])
	c.advance_time(1.0)
	check(casts.size() == 3 and casts[0].id == p1.instance_id and casts[1].id == e1.instance_id and casts[2].id == p2.instance_id, "双方独立读秒，同批玩家先且逐张交替")
	_free(c)

func _test_periodic() -> void:
	var first := _spell(VOLLEY, 2.0)
	var star := _spell(STARFIRE, 3.0)
	var next := _spell(VOLLEY, 1.0)
	var c := _battle([first, star, next])
	c.advance_time(8.0)
	check(_release_times() == [2.0, 5.0, 6.0, 8.0] and casts[1].id == star.instance_id and casts[3].id == star.instance_id, "星火首次排队第5秒，后续第8秒；第6秒下一张正常释放")
	_free(c)

func _test_content_times() -> void:
	var first := _spell(VOLLEY, 2.0)
	var boulder := _spell(BOULDER, 1.0)
	var night := _spell(NIGHTFALL, 1.0)
	var c := _battle([first, boulder, night])
	c.advance_time(4.0)
	check(_release_times() == [2.0, 3.0, 4.0] and c.fatigue_start_seconds == 20.0, "落石与黑夜使用各自准备时间，取消硬编码第8/20秒")
	_free(c)

func _test_late_nightfall() -> void:
	var c := _battle([_spell(NIGHTFALL, 28.0)])
	c.advance_time(28.0)
	check(c.fatigue_start_seconds == 28.0 and c._next_fatigue_damage_seconds > 28.0, "黑夜第28秒释放时立即启动风暴，不追补第20秒伤害")
	_free(c)
	c = _battle([_spell(NIGHTFALL, 31.0)])
	c.advance_time(31.0)
	check(c.fatigue_start_seconds == 30.0 and casts.is_empty(), "风暴已开始时黑夜无效，不追加伤害或启咒")
	_free(c)

func _test_current_card_times() -> void:
	var cards: Array[CardData] = [VOLLEY, preload("res://resources/cards/return_to_battlefield.tres"), BOULDER, NIGHTFALL, STARFIRE]
	var spells: Array[OwnedCard] = []
	for card: CardData in cards: spells.append(_spell(card, card.spell_preparation_seconds))
	var c := _battle(spells)
	var scheduled_times: Array[float] = []
	for entry: Dictionary in c._prepared_spell_schedule: scheduled_times.append(entry.release_time)
	check(scheduled_times == [5.0, 15.0, 19.0, 29.0, 32.0], "正式资源新版5/10/4/10/3秒生成正确累计时刻")
	c.advance_time(32.0)
	check(c._elapsed_spell_attempted.size() == 5 and c.fatigue_start_seconds == 29.0, "真实队列复活无目标仍继续，延迟黑夜在第29秒立即启动风暴")
	check(c.silvermoon.periodic_spells[spells[4].instance_id] == 35.0, "实际星火第32秒首次释放，第35秒再次释放")
	_free(c)

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
