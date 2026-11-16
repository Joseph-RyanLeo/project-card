extends "res://tests/card_balance_20261008_test.gd"

## 使用真实死亡结算与正式效果资源，验证双方战斗单位及衍生物。
func _run() -> void:
	check(BattleEffectCatalog.load_from_file("res://data/demo2/ash_ledger_effect_samples.json").is_valid(), "正式灰烬效果数据通过严格校验")
	current = BattleController.new()
	root.add_child(current)
	current.use_projectile_timing = false
	var players: Array[Dictionary] = [entry(owned("militia", false), 0), entry(owned("elegy_poet"), 1), entry(owned("militia", false), 2), entry(owned("militia", false), 0, &"player_back")]
	var enemies: Array[Dictionary] = [entry(owned("militia", false), 0, &"enemy_front"), entry(owned("booby_mine", false), 1, &"enemy_front"), entry(owned("militia", false), 2, &"enemy_front"), entry(owned("militia", false), 0, &"enemy_back")]
	current.start_battle(players, enemies, 71106, false)
	var left := current.player_states[0]
	var right := current.player_states[2]
	current.enemy_states[0].current_health = 0
	current._finalize_batch()
	check(left.get_zeal_layers() == 1 and right.get_zeal_layers() == 1, "敌方单位被消灭给诗人相邻友军热诚+1")
	current.enemy_states[1].current_health = 0
	current._finalize_batch()
	check(left.get_zeal_layers() == 2 and right.get_zeal_layers() == 2, "敌方衍生物被消灭同样计入")
	current.player_states[3].current_health = 0
	current._finalize_batch()
	check(left.get_zeal_layers() == 3 and right.get_zeal_layers() == 3, "友方单位被消灭仍正常触发，且没有重复加层")
	check(current.player_states[1].get_zeal_layers() == 0 and current.enemy_states[2].get_zeal_layers() == 0, "诗人自身及敌人不获得相邻友军奖励")
	current.enemy_states[2].current_health = 0
	current.enemy_states[3].current_health = 0
	current._finalize_batch()
	check(left.get_zeal_layers() == 5 and right.get_zeal_layers() == 5, "同一批两名敌人被消灭分别触发一次")
	current.player_states[1].current_health = 0
	current._finalize_batch()
	check(left.get_zeal_layers() == 5 and right.get_zeal_layers() == 5, "诗人自身退场后不再产生奖励")
	current.clear_battle()
	current.free()
	current = null
	await process_frame
	print("Poet unit deaths: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
