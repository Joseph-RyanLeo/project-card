extends "res://tests/d3_3_gallery_test.gd"

## 必须在d3_3_gallery_test之后用另一Godot进程执行，直接读取其隔离临时档。
func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("展览馆独立进程恢复超时"); quit(1))
	root.size = Vector2i(1280, 720)
	shell = SHELL.instantiate()
	shell.run_slots.directory = GALLERY_DIR
	root.add_child(shell)
	await frames()
	check(await shell.start_slot(0), "独立进程从磁盘恢复真实入藏档")
	var before: Dictionary = shell.slot_progress.capture_state()
	var disk := FileAccess.get_file_as_string(shell.run_slots.get_slot_path(0))
	await click(button("GalleryButton"))
	while shell.screen_transition.busy: await process_frame
	await frames()
	var gallery = shell._gallery_panel
	var id: String = gallery.shown_cards[0].id
	check(gallery.views.size() == 9 and gallery.views[id + ":1"].get_owned_card().lifetime_stats.damage_dealt == 123.5, "独立进程恢复本档完整收藏与累计战绩")
	for index: int in 3:
		check(int(gallery.views[id + ":%d" % (index + 1)].get_owned_card().surface_finish) == index, "重启保留固定收藏位%d与外观" % (index + 1))
	await click(gallery.views[id + ":3"], MOUSE_BUTTON_RIGHT)
	await create_timer(0.9).timeout
	var text := text_rows(gallery._inspection.find_child("CardDetails", true, false))
	check(text.contains("数值 +3") and text.contains("123.5"), "重启检视读取第三位自身成长和战绩")
	await key(KEY_ESCAPE)
	await wait_inspection_closed(gallery)
	await key(KEY_ESCAPE)
	while shell.screen_transition.busy: await process_frame
	await frames()
	check(shell.slot_progress.capture_state() == before and FileAccess.get_file_as_string(shell.run_slots.get_slot_path(0)) == disk, "独立进程浏览后数据与磁盘字节均不变")
	print("D3-3 gallery restore checks: %d, failures: %d" % [checks, failures])
	shell.free()
	await frames()
	quit(1 if failures else 0)
