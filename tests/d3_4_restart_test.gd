extends SceneTree

## 新进程读取前面真实挑战留下的文件，核对永久状态而不在本进程授予任务。
var checks := 0
var failures := 0


func _initialize() -> void: _run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func read_progress(path: String) -> ProfileProgress:
	var loaded := RunSaveService.new().load_checkpoint(path)
	check(loaded.get("success", false), "独立进程读取真实文件：" + path.get_base_dir().get_file())
	if not loaded.get("success", false): return null
	var result := ProfileProgress.new()
	check(result.restore_state(loaded.checkpoint.profile_progress), "局外数据通过严格恢复验证")
	var state := ShortMazeRunState.new()
	if loaded.checkpoint.has("short_maze"): check(state.restore_state(loaded.checkpoint.short_maze.run), "本局路线／结算历史通过严格恢复验证")
	return result


func _run() -> void:
	var p := read_progress("/private/tmp/project-card-d3-4-loop-test/project_card_run.json")
	if p != null:
		check(p.profile.tutorial.actually_completed and p.profile.tasks.supply_first.completed, "新进程保留真实M1／M2通关结果")
		check(p.profile.receipts.tutorial_guidance == 1000 and p.profile.unlocks.packs.has("emblem_pack"), "引导奖励凭证与纹章包永久资格保持一致")
		check(p.profile.receipts.keys().all(func(id: String): return not id.contains("fixture")), "M1→M2连续挑战没有注入测试积分")
	p = read_progress("/private/tmp/project-card-d3-4-lantern-trial-test/project_card_run.json")
	if p != null: check(p.profile.tasks.deep_survey.completed and p.profile.unlocks.routes.has("second_floor"), "新进程保留M3青灯目标与第二层资格")
	p = read_progress("/private/tmp/project-card-d3-4-second-floor-test/project_card_run.json")
	if p != null: check(p.profile.tasks.ironwall_support.completed and p.profile.tasks.temple_boon.completed and p.profile.unlocks.packs.has("ironwall_inscription") and p.profile.unlocks.packs.has("silvermoon_chapter"), "新进程保留M4／M5及两个正式卡包")
	p = read_progress("/private/tmp/project-card-d3-4-fusion-test/project_card_run.json")
	if p != null: check(p.profile.tasks.witch_cauldron.completed and p.profile.unlocks.items.has("emblem_fusion"), "新进程保留S1成功融合资格")
	p = read_progress("/private/tmp/project-card-d3-4-transactions-test/project_card_run.json")
	if p != null: check(p.profile.tasks.portable_runes.completed and p.profile.unlocks.items.has("光贴纸"), "新进程保留S2与五元素资格")
	print("D3-4 restart: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
