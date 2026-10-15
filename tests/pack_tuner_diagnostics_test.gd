extends "res://tests/card_pack_opening_test.gd"

## 真实失败交易及磁盘导出，验证日志来自预览商店、包含现场且不会覆盖存档。
func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("开包诊断验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = false
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K)
	await create_timer(.7).timeout
	main = shell.main_screen
	var original_cards: Dictionary = main.owned_card_collection.capture_state()
	var original_gold: int = main.run_reward_state.gold
	shell.open_pack_effect_tuner()
	await create_timer(.5).timeout
	var tuner: Control = shell._pack_effect_tuner
	var lab: Control = tuner.preview_shop
	var portable: String = lab.run_save_path
	check(portable.begins_with("user://rare-shop-test-") and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(portable).get_base_dir()), "测试存档使用Godot跨平台用户目录")
	# 用确实不存在的目录复现Windows旧路径引起的保存失败，不模拟文件API。
	lab.run_save_path = "/private/tmp/project-card-missing-%d/rare.json" % Time.get_ticks_usec()
	await click(tuner.find_child("PreviewNormal", true, false).get_global_rect().get_center())
	await process_frame
	check(lab.owned_card_collection.size() == 0 and not is_instance_valid(lab._card_pack_opening) and not lab.ordinary_shop_service.offers[0].get("sold", false), "不可写路径真实导致购买回滚并且不进入动画")
	check(lab.ordinary_shop_status.text.begins_with("存档失败"), "现场提示明确记录存档失败")
	tuner.controls.tear_shake_pixels.slider.value = 2.5
	await click(tuner.find_child("ExportPackDiagnostics", true, false).get_global_rect().get_center())
	check(is_instance_valid(tuner._diagnostic_dialog) and tuner._diagnostic_dialog.visible and shell.is_pack_effect_tuner_open(), "调试器内真实点击可直接打开导出对话框，不退出现场")
	var output := "/private/tmp/project-card-pack-diagnostics-test.json"
	tuner._diagnostic_dialog.file_selected.emit(output)
	tuner._diagnostic_dialog.hide()
	await process_frame
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output))
	check(document.kind == "project_card_run_diagnostics" and document.current_state.pack_test.status.begins_with("存档失败") and not document.current_state.pack_test.save_directory_exists, "JSON导出包含预览商店失败状态与无效存档目录")
	check(document.current_state.pack_tuner.effects.tear_shake_pixels == 2.5 and document.current_state.pack_tuner.has("window_size") and document.current_state.pack_tuner.has("preview_scale"), "JSON包含当前特效草稿、窗口及预览缩放")
	var attempt := false
	var result := false
	var pointer := false
	for event: Dictionary in document.recent_events:
		attempt = attempt or event.kind == "pack_purchase_attempt"
		result = result or (event.kind == "pack_purchase_result" and event.detail.acquired_count == 0)
		pointer = pointer or event.kind == "pack_tuner_pointer"
	check(attempt and result and pointer, "导出保留点击、真实购买尝试与失败结果")
	check(lab.owned_card_collection.size() == 0 and lab.run_save_path != portable and not is_instance_valid(lab._inspection_overlay), "导出不重新购买、保存或关闭故障状态")
	check(tuner.status_label.text.begins_with("诊断日志已导出"), "导出结果显示在调试器状态栏")
	lab.run_save_path = portable
	await click(tuner.find_child("PreviewRare", true, false).get_global_rect().get_center())
	await create_timer(.4).timeout
	check(lab.owned_card_collection.size() == 5 and FileAccess.file_exists(portable) and is_instance_valid(lab._card_pack_opening), "换成跨平台路径后同一真实交易成功保存五张卡并开始开包")
	var bytes := FileAccess.get_file_as_bytes(portable)
	tuner._save_diagnostics(portable)
	check(FileAccess.get_file_as_bytes(portable) == bytes and tuner.status_label.text.contains("不能覆盖"), "诊断导出拒绝覆盖测试交易存档")
	await click(tuner.find_child("ExportPackDiagnostics", true, false).get_global_rect().get_center())
	tuner._diagnostic_dialog.file_selected.emit(output)
	tuner._diagnostic_dialog.hide()
	await process_frame
	document = JSON.parse_string(FileAccess.get_file_as_string(output))
	check(document.current_state.pack_test.sequence.card_count == 5 and document.current_state.pack_test.sequence.has_rare and document.current_state.pack_test.sequence.has("phase"), "成功开包现场导出阶段、品级与预绘卡数")
	await key(KEY_ESCAPE)
	await process_frame
	check(main.owned_card_collection.capture_state() == original_cards and main.run_reward_state.gold == original_gold and not FileAccess.file_exists(portable), "退出清理跨平台临时文件并保持正式收藏与金币不变")
	DirAccess.remove_absolute(output)
	shell.queue_free()
	await process_frame
	print("Pack tuner diagnostic failures: ", failures)
	quit(1 if failures else 0)
