extends SceneTree

## 真实场景与鼠标输入：场外头像生命周期、通知队列、Esc定位及存档失败回滚。
const DISPLAY = preload("res://scenes/GameDisplay.tscn")
const Hint = preload("res://scripts/ui/task_hint_overlay.gd")
const Portrait = preload("res://scripts/ui/character_portrait.gd")
const Toast = preload("res://scripts/ui/gameplay_teaching_toast.gd")
const DIR := "/private/tmp/project-card-communication-test"
const PREVIEWS := "res://docs/previews/communication_20261107"
var checks := 0
var failures := 0
var shell
var main
var shrinking_seen := false

func _initialize() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func frames() -> void:
	for index: int in 5: await process_frame

func finish_teaching_open() -> void:
	if is_instance_valid(main._view_tween) and main._view_tween.is_running(): await main._view_tween.finished
	if main.is_page_turning(): await main._page_tween.finished

func move_mouse(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)

func control_center(control: Control) -> Vector2:
	return shell.render_container.get_global_transform_with_canvas() * control.get_global_transform_with_canvas() * (control.size * 0.5)

func click(control: Control) -> void:
	var at := control_center(control)
	move_mouse(at)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame
	await frames()

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEWS))
	root.get_texture().get_image().save_png(PREVIEWS.path_join(label + ".png"))

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("角色对白与玩法教学专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(DIR)
	shell = DISPLAY.instantiate()
	shell.run_slots.directory = DIR
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = DIR.path_join("run.json")
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_720P)
	await frames()
	if "rune-only" in OS.get_cmdline_user_args():
		await _verify_rune_discovery()
		_finish()
		return
	var key := "tutorial:step:rune_basics"
	var second_key := "rune_pattern:pair"
	main.profile_progress.profile.tutorial.read_hints.clear()
	main.profile_progress.profile.tutorial.hint_texts.clear()
	var toast = main._gameplay_teaching_toast
	check(main.show_gameplay_teaching(key, 1.0), "通过正式入口保存并展示非必要教学")
	check(not paused and toast.visible and toast.current_key == key, "通知不暂停、不盖暗幕，保留对应编号")
	await create_timer(Toast.APPEAR_SECONDS * 0.5).timeout
	check(toast.scale.x > Toast.RESTING_SCALE and toast.scale.x < Toast.PEAK_SCALE and toast.modulate.a > 0.0 and toast.modulate.a < 1.0, "提示条放大并渐显")
	check(not main.show_gameplay_teaching(key), "同一已提示条目不重复自动弹出")
	check(main.show_gameplay_teaching(second_key, 2.0), "连续教学入队，不覆盖前一条")
	await create_timer(Toast.APPEAR_SECONDS * 0.5 + 0.02).timeout
	check(is_equal_approx(toast.scale.x, Toast.PEAK_SCALE) and is_zero_approx(toast.progress), "入场放大超过正常大小并停顿")
	await create_timer(Toast.PEAK_HOLD_SECONDS + Toast.SETTLE_SECONDS + 0.04).timeout
	check(is_equal_approx(toast.scale.x, 1.0) and toast.progress > 0.0 and toast.progress < 1.0, "入场回到正常大小后，正方形周长进度开始增长")
	await capture("01_teaching_toast")
	var before_hover: float = toast.progress
	move_mouse(control_center(toast.title_label))
	await create_timer(Toast.HOVER_SECONDS + 0.04).timeout
	check(is_equal_approx(toast.scale.x, Toast.HOVER_SCALE) and toast.progress > before_hover, "鼠标移到标题上时整条放大，倒计时继续")
	move_mouse(Vector2.ZERO)
	await create_timer(Toast.HOVER_SECONDS + 0.04).timeout
	check(is_equal_approx(toast.scale.x, 1.0), "鼠标移出后提示条回到正常大小")
	var previous: float = toast.progress
	main._escape_menu_pause_requested = true
	main._escape_pause_menu.open_menu()
	main._sync_battle_pause_owners()
	await create_timer(0.3).timeout
	check(is_equal_approx(previous, toast.progress) and not toast.visible, "Esc菜单隐藏通知并冻结倒计时")
	main._close_escape_pause_menu()
	await frames()
	await click(toast.title_label)
	await finish_teaching_open()
	check(main._escape_pause_menu.is_menu_open() and paused and main._escape_pause_menu.selected_teaching_key == key, "真实点击提示条标题区域直接打开对应教学并沿用暂停")
	var page = main._escape_pause_menu.find_child("TutorialHelpPage", true, false)
	var text: Label = page.find_child("TaskInfoText", true, false)
	check(text.text.contains("强化+2") and not text.text.contains("伊奥恩："), "独立正文来自现行规则且不混入剧情")
	check(main._escape_pause_menu.find_child("Teaching_tutorial_step_deploy", true, false) != null, "教学目录包含尚未自动弹出的全部已编写条目")
	await capture("02_teaching_detail")
	check(toast.current_key == second_key, "点击第一条后仍保留后续通知")
	main._close_escape_pause_menu()
	while toast.progress < 1.0:
		await process_frame
	await create_timer(Toast.EXIT_GROW_SECONDS + 0.02).timeout
	check(is_equal_approx(toast.scale.x, Toast.PEAK_SCALE) and is_equal_approx(toast.modulate.a, 1.0), "计时结束后先放大并停顿，保持可见")
	await create_timer(Toast.PEAK_HOLD_SECONDS + Toast.DISAPPEAR_SECONDS * 0.4).timeout
	check(toast.visible and toast.scale.x < Toast.PEAK_SCALE and toast.modulate.a > 0.0 and toast.modulate.a < 1.0, "退场停顿后提示条缩小并渐隐")
	await click(toast.title_label)
	check(not main._escape_pause_menu.is_menu_open(), "退场期间点击不再跳转")
	await create_timer(Toast.DISAPPEAR_SECONDS).timeout
	check(not toast.visible and toast.current_key.is_empty(), "倒计时走完自动消失，不打开教学页")
	main._escape_pause_menu.open_teaching(second_key)
	check(main._escape_pause_menu.selected_teaching_key == second_key, "通知消失后仍可从Esc定位回看")
	main._escape_pause_menu.close_menu()
	var saved := RunSaveService.new().load_checkpoint(main.run_save_path)
	var restored := ProfileProgress.new()
	check(saved.success and restored.restore_state(saved.checkpoint.profile_progress) and restored.profile.tutorial.read_hints.has(key), "真实JSON往返后保留教学通知记录")
	DirAccess.make_dir_absolute(main.run_save_path + ".tmp")
	check(not main.show_gameplay_teaching("tutorial:step:formation") and not main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:formation") and toast.current_key.is_empty(), "落盘失败回滚教学记录，不展示未保存通知")
	DirAccess.remove_absolute(main.run_save_path + ".tmp")

	var dialog = Hint.new()
	dialog.title = "场外角色对白"
	dialog.content = {"dialogue": [{"speaker": "后勤机器人", "text": "补给已送达。"}, {"speaker": "暂缺立绘角色", "text": "收到。"}], "instruction": "", "dim": false}
	dialog.portrait_resolver = main.character_portrait
	main.add_child(dialog)
	dialog.confirmed.connect(dialog.dismiss)
	var dialog_ref: WeakRef = weakref(dialog)
	var watch_shrink := func():
		var active: Control = dialog_ref.get_ref()
		if active != null and is_instance_valid(active.speech) and active.portrait.visible and active.speech._speaker == null and active.portrait.scale.x > Portrait.MIN_SCALE and active.portrait.scale.x < 0.8:
			shrinking_seen = true
	process_frame.connect(watch_shrink)
	check(dialog.portrait.visible and dialog.portrait.scale.x < 0.1, "不在场的角色从接近零尺寸弹出头像")
	await create_timer(0.12).timeout
	check(dialog.portrait.scale.x > 0.1, "头像实际经历由小变大的中间状态")
	await create_timer(Portrait.APPEAR_SECONDS).timeout
	check(dialog.portrait._art.texture.atlas == main.character_portrait("后勤机器人") and dialog.speech._speaker == dialog.portrait, "直接复用角色卡图并把原有气泡锚定到弹出头像")
	await dialog.speech._text_reveal.finished
	await capture("03_offstage_portrait")
	for mode: int in [shell.DisplayMode.WINDOW_1080P, shell.DisplayMode.WINDOW_2K]:
		shell.apply_display_mode(mode)
		await frames()
		check(dialog.speech.text_label.get_theme_font_size("font_size") == roundi(14 * shell.render_container.scale.x), "放大窗口仍使用原有原生分辨率气泡文字")
		await capture("03_portrait_%d" % root.size.x)
	main._escape_menu_pause_requested = true
	main._escape_pause_menu.open_menu()
	main._sync_battle_pause_owners()
	await create_timer(0.15).timeout
	check(not dialog._portrait_layer.visible and not dialog.speech._visual.visible, "Esc期间头像与原生气泡都隐藏")
	await create_timer(3.2).timeout
	check(dialog._hero_line_index == 0, "Esc暂停期间不跳过未读对白")
	main._close_escape_pause_menu()
	shell.apply_display_mode(shell.DisplayMode.WINDOW_720P)
	while is_instance_valid(dialog) and dialog._hero_line_index == 0: await process_frame
	await create_timer(0.4).timeout
	check(dialog.portrait._initial.visible and dialog.portrait._initial.text == "暂", "没有立绘时明确使用姓名占位，不借用其他角色")
	await dialog.tree_exited
	process_frame.disconnect(watch_shrink)
	await process_frame
	check(shrinking_seen, "台词读完后头像实际经历缩小退场的中间状态")
	check(not is_instance_valid(dialog), "最后一句说完自动缩小并释放对白节点")
	# 在场发言者继续使用现有锚点，不生成重复头像。
	main.set_world_view(main.WorldView.COLLECTION, false)
	var anchored = Hint.new()
	anchored.content = {"dialogue": [{"speaker": "主角", "text": "出发。"}], "instruction": "继续操作", "dim": false}
	anchored.speaker = main.player_avatar_button
	main.add_child(anchored)
	await frames()
	check(not anchored.portrait.visible and anchored.speech._speaker == main.player_avatar_button, "可见的场上角色继续复用原头像与气泡")
	anchored.dismiss()
	await anchored.tree_exited
	await _verify_rune_discovery()
	_finish()


func _finish() -> void:
	paused = false
	shell.free()
	print("Communication UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _verify_rune_discovery() -> void:
	var toast: Control = main._gameplay_teaching_toast
	var owned: OwnedCard
	for candidate: OwnedCard in main.owned_card_collection.get_cards():
		if candidate.card_data.card_type == CardData.CardType.MINION and candidate.resolved_runes.size() == 3:
			owned = candidate
			break
	check(owned != null, "全局牌型测试取得实际拥有的随从")
	if owned == null: return
	var chaos_key := "rune_pattern:chaos"
	var triple_key := "rune_pattern:three_of_a_kind"
	check(main.save_run_to_path(main.run_save_path) == OK, "为牌型发现建立隔离的原始检查点")
	var before := RunSaveService.new().load_checkpoint(main.run_save_path)
	owned.resolved_runes.assign([CardData.ElementType.WATER, CardData.ElementType.FIRE, CardData.ElementType.WATER])
	main._refresh_owned_card_status_visuals(owned)
	await frames()
	check(not main.profile_progress.profile.tutorial.read_hints.has(chaos_key), "未揭晓的收藏随从和敌方牌型不计为首次达成")
	owned.rune_revealed[0] = true
	main._refresh_owned_card_status_visuals(owned)
	await frames()
	check(toast.current_key == chaos_key and not main._hero_speech.visible, "收藏随从首次有有效符文但未成组时，只弹混沌教学")
	var after := RunSaveService.new().load_checkpoint(main.run_save_path)
	check(before.success and after.success and before.checkpoint.collection == after.checkpoint.collection and after.checkpoint.profile_progress.profile.tutorial.read_hints.has(chaos_key), "即时保存教学记录，不把当前刮擦写进原来的检查点")
	await create_timer(Toast.APPEAR_SECONDS + Toast.PEAK_HOLD_SECONDS + Toast.SETTLE_SECONDS).timeout
	await click(toast.title_label)
	await finish_teaching_open()
	check(main._escape_pause_menu.selected_teaching_key == chaos_key, "混沌提示直达对应条目")
	main._close_escape_pause_menu()

	owned.rune_revealed.assign([true, true, true])
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	check(main.start_battle(17, false), "使用真实阵容开始战斗")
	var state: BattleSquadState = main.battle_controller.player_states[0]
	state.set_runtime_rune_override(state.squad_data.horizontal_cards[0], 1, CardData.ElementType.WATER)
	main.battle_controller.states_changed.emit()
	await frames()
	check(toast.current_key == triple_key and main._hero_speech.text_label.text == "三相...进阶的元素运用能让你力量更强" and not paused, "战中实际牌型首次变化，同时出现英雄短对白和三相提示且不中断战斗")
	var checkpoint := RunSaveService.new().load_checkpoint(main.run_save_path)
	var progress := ProfileProgress.new()
	check(checkpoint.success and progress.restore_state(checkpoint.checkpoint.profile_progress) and progress.profile.tutorial.read_hints.has(triple_key), "战中发现记录写入战前恢复档，读档后不重复提示")
	await create_timer(Toast.APPEAR_SECONDS + Toast.PEAK_HOLD_SECONDS + Toast.SETTLE_SECONDS).timeout
	var capture_rune := DisplayServer.get_name() != "headless" and "rune-only" in OS.get_cmdline_user_args()
	if capture_rune:
		if is_instance_valid(main._hero_speech._text_reveal) and main._hero_speech._text_reveal.is_running():
			await main._hero_speech._text_reveal.finished
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-rune-teaching-toast.png")
	await click(toast.title_label)
	await finish_teaching_open()
	var page: Control = main._escape_pause_menu.find_child("TutorialHelpPage", true, false)
	var description: Label = page.find_child("TaskInfoText", true, false)
	var table: Control = page.find_child("TeachingElementTable", true, false)
	var grid := table.get_child(2) as GridContainer
	check(main._escape_pause_menu.selected_teaching_key == triple_key and description.text.contains("三枚相同元素连续排列") and description.text.contains("×2"), "三相提示打开包含条件和倍率的对应说明")
	check(not main._hero_speech._visual.visible, "打开教学页时英雄气泡不盖住正文")
	var relevant := grid.get_child(2) as PanelContainer
	var other := grid.get_child(1) as PanelContainer
	check(grid.get_child_count() == 36 and relevant.get_theme_stylebox("panel").bg_color != other.get_theme_stylebox("panel").bg_color, "完整六行六列元素表标亮三相／同源双环档")
	check(grid.get_rect().end.x <= table.size.x + 1.0, "720p教学表格完整落在正文区内")
	if capture_rune:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-rune-teaching-detail.png")
	main._close_escape_pause_menu()
	main.battle_controller.states_changed.emit()
	await frames()
	check(toast.current_key.is_empty(), "相同牌型再次刷新不会重复弹出")
