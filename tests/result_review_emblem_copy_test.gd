extends SceneTree

const DISPLAY := preload("res://scenes/GameDisplay.tscn")
const SAVE_PATH := "/private/tmp/project-card-result-review-test.json"

var shell: Control
var checks := 0
var failures := 0


func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("结算返回与纹章提示专项超时"); quit(2))
	_run.call_deferred()


func _run() -> void:
	_check_emblem_copy()
	shell = DISPLAY.instantiate()
	var main: Control = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = SAVE_PATH
	root.add_child(shell)
	await process_frame
	await process_frame
	if _check(main.emblem_library.return_sticker({"instance_id": &"tooltip_seed", "emblem_id": &"种子"}), "种子可放入工具箱"):
		var entry: EmblemLibraryEntry = main.emblem_library._entries.back()
		var tooltip: String = entry.get_hovered_sticker_help().get("text", "")
		_check(tooltip == "种子\n突击：生长", "工具箱的种子标题只显示纹章名")
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]:
		row.clear_squads()
	var player: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
	player.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 100.0)
	main.front_row.add_squad(SquadData.from_owned_card(player), 0)
	main.enemy_front_row.add_squad(SquadData.from_card(load("res://resources/cards/timid_infantry.tres")), 0)
	await process_frame
	if _check(main.start_battle(7043, false), "通过正式开战入口进入战斗"):
		await _check_result_review(main)
	shell.queue_free()
	await process_frame
	print("结算返回与纹章提示：%d项，%d失败" % [checks, failures])
	quit(1 if failures else 0)


func _check_result_review(main: Control) -> void:
	var return_button: Button = main._return_to_result_button
	_check(not return_button.is_visible_in_tree(), "正常战斗使用普通眼睛")
	var battle: BattleController = main.battle_controller
	for batch: int in 200:
		if battle.current_result != BattleController.Result.NONE:
			break
		battle.resolve_next_batch()
		await process_frame
	if not _check(battle.current_result != BattleController.Result.NONE, "真实战斗正常结束"):
		return
	await create_timer(SquadView.DEATH_DISSOLVE_EDGE_SECONDS + 0.15).timeout
	if not _check(main.battle_result_panel.visible, "自动进入本场战斗结算"):
		return
	var summary: String = main.battle_result_summary_label.text
	var saved_run := FileAccess.get_file_as_string(SAVE_PATH)
	await _click(main.get_node("%ViewResultBattlefieldButton"))
	_check(not main.battle_result_panel.visible and return_button.is_visible_in_tree(), "实际点击查看战场后替换中线按钮")
	_check(
		return_button.get_parent() == main.battle_time_bar
		and return_button.get_global_rect().get_center() == main.battle_time_bar.global_position + Vector2(449, 8)
		and return_button.icon.resource_path.ends_with("/battle_time_return.png"),
		"返回图标使用原图并居中放在时间条上"
	)
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-result-review.png")
	await _click(return_button)
	_check(
		main.battle_result_panel.visible and not return_button.is_visible_in_tree()
		and main.battle_result_summary_label.text == summary and not saved_run.is_empty()
		and FileAccess.get_file_as_string(SAVE_PATH) == saved_run,
		"点击中线返回同一份结算，恢复眼睛且存档内容不变"
	)


func _check_emblem_copy() -> void:
	_check(EmblemLibraryData.get_tooltip(&"种子") == "种子\n突击：生长", "种子的玩家说明只有突击：生长")
	for definition: Dictionary in EmblemLibraryData.get_definitions():
		var emblem_id: StringName = definition.id
		var tooltip := EmblemLibraryData.get_tooltip(emblem_id)
		_check(
			not tooltip.get_slice("\n", 1).is_empty() and not tooltip.contains("资料状态：")
			and not tooltip.contains("已确认") and not tooltip.contains("待确认") and not tooltip.contains("OwnedCard"),
			"%s有实际效果说明且无内部审阅信息" % emblem_id
		)


func _click(button: Control) -> void:
	var point: Vector2 = shell.render_container.get_global_transform_with_canvas() * button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame


func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value
