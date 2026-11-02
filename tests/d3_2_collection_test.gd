extends "res://tests/d3_2_flow_test.gd"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = DIR
	var read_mode := OS.get_cmdline_user_args().has("read")
	if not read_mode:
		shell.run_slots.delete_slot(2)
		var progress := ProfileProgress.new()
		var collection := OwnedCardCollection.new()
		progress.start_run()
		var definition: CardData = load("res://resources/cards/musketeer.tres")
		var old: Array[OwnedCard] = []
		for index: int in 3:
			var card := collection.create_card(definition)
			card.surface_finish = index as CardAppearance.Surface
			card.acquired_at = 1700000000 + index
			old.append(card)
		progress.begin_collection(old)
		var choices: Array = []
		for index: int in 3: choices.append({"candidate_id": String(old[index].instance_id), "slot": index})
		check(progress.set_selection(choices) and progress.show_preview() and progress.confirm_collection(), "用正式单卡建立三个固定旧收藏位")
		progress.start_run()
		var candidate := collection.create_card(definition)
		candidate.surface_finish = CardAppearance.Surface.FRACTURED
		candidate.art_finish = CardAppearance.Art.OVERFRAME
		candidate.acquired_at = 1800000000
		candidate.lifetime_stats = {"damage_dealt": 123.5, "battles": 8, "kills": 9}
		var cards: Array[OwnedCard] = [candidate]
		check(progress.finish_run(cards, [], 123, "abandoned", 3, [], 2) and progress.show_selection(), "真实结算生成有旧收藏的候选")
		check(RunSaveService.new().save_checkpoint(shell.run_slots.get_slot_path(2), {"schema_version": RunSaveService.SCHEMA_VERSION, "profile_progress": progress.capture_state()}) == OK, "写入独立临时档夹具")
	root.add_child(shell)
	await frames()
	check(await shell.start_slot(2), "恢复待选卡或集合档")
	var original: Dictionary = shell.slot_progress.profile.collection.duplicate(true)
	var balance: int = shell.slot_progress.profile.points
	if read_mode:
		check(shell.main_screen == null and shell.slot_progress.run.stage == "preview", "独立进程直接恢复集合，无本局副作用")
		check(shell.slot_progress.run.selection.size() == 1 and shell.slot_progress.run.selection[0].slot == 1 and shell.slot_progress.run.selection[0].replaced_id == original.musketeer[1].archive_id, "重启保留明确新旧替换关系")
		await capture("10_replacement_preview_restarted")
		await click(button("CollectionBackButton"))
		var candidate_id: String = shell.slot_progress.run.selection[0].candidate_id
		await click(shell._slot_progress_panel._cells[candidate_id].view)
		check(shell.slot_progress.run.selection.is_empty() and shell.slot_progress.profile.collection == original, "恢复后可取消已确认替换，旧收藏不变")
		await click(shell._slot_progress_panel._cells[candidate_id].view)
		var inspection := shell._slot_progress_panel.find_child("CollectionComparison", true, false) as Control
		await click(inspection.find_child("ReplaceSlot1Button", true, false))
		var confirmation := inspection.find_child("ReplaceConfirmation", true, false) as ConfirmationDialog
		await click(confirmation.get_ok_button())
		await click(button("CollectionPreviewButton"))
		var selected_id: String = shell.slot_progress.run.selection[0].candidate_id
		var new_archive: String = shell.slot_progress.run.candidates[selected_id].archive_id
		await click(button("CollectionConfirmButton"))
		check(shell.slot_progress.run.stage == "hub" and shell.slot_progress.profile.points == balance, "独立进程最终确认后回大厅且积分不重复")
		var slots: Array = shell.slot_progress.profile.collection.musketeer
		check(slots.size() == 3 and slots[0] == original.musketeer[0] and slots[2] == original.musketeer[2] and slots[1].archive_id == new_archive, "仅原收藏位2替换，不排序、不移动其他位")
		check(slots[1].acquired_at == 1800000000 and slots[1].lifetime_stats.damage_dealt == 123.5 and slots[1].surface_finish == "fractured", "完整外观、时间、战绩随实例入藏")
	else:
		var id: String = shell.slot_progress.run.candidates.keys()[0]
		await click(shell._slot_progress_panel._cells[id].view)
		var inspect := shell._slot_progress_panel.find_child("CollectionComparison", true, false) as Control
		check(inspect != null and inspect.find_child("SelectCandidateButton", true, false) == null, "满三位必须并排检视后明确替换")
		await capture("08_comparison")
		await click(inspect.find_child("ReplaceSlot1Button", true, false))
		check(shell.slot_progress.run.selection.is_empty(), "首次点击替换不立即记录选择")
		var confirmation := inspect.find_child("ReplaceConfirmation", true, false) as ConfirmationDialog
		check(confirmation != null and confirmation.visible, "替换关系二次确认窗口真实显示")
		await capture("09_replace_confirmation")
		await click(confirmation.get_ok_button())
		check(shell.slot_progress.run.selection.size() == 1 and shell.slot_progress.run.selection[0].slot == 1, "第二次确认才保存待替换计划")
		check(shell.slot_progress.profile.collection == original, "替换计划不移除旧收藏")
		await click(button("CollectionPreviewButton"))
		check(shell.slot_progress.run.stage == "preview" and shell.slot_progress.profile.collection == original, "集合预览仍保留旧收藏")
		shell.return_to_start_menu()
		await frames()
		var checkpoint: Dictionary = RunSaveService.new().load_checkpoint(shell.run_slots.get_slot_path(2)).checkpoint
		check(checkpoint.profile_progress.run.stage == "preview" and checkpoint.profile_progress.profile.collection == original, "独立文件保存集合阶段与旧收藏，供下一进程验证")
	print("D3-2 collection %s checks: %d, failures: %d" % ["read" if read_mode else "write", checks, failures])
	shell.free()
	await process_frame
	quit(1 if failures else 0)
