extends SceneTree

const DISPLAY := preload("res://scenes/GameDisplay.tscn")
var shell: Control
var main: Control
var failures := 0
var assertions := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	assertions += 1
	print("PASS: " if value else "FAIL: ", label)
	if not value: failures += 1

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame

func key(code: Key, unicode: int = 0) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.unicode = unicode
		event.pressed = pressed
		root.push_input(event)
		await process_frame

func menu_button(text: String) -> Button:
	for node: Node in main._escape_pause_menu.find_children("*", "Button", true, false):
		if node.text == text: return node
	return null

func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-menu-input-save.json"
	root.add_child(shell)
	await process_frame
	await process_frame
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	for i in range(6): await process_frame
	check(root.size == Vector2i(2560,1440), "真实2K窗口")
	for text: String in ["攻击特效调试器", "卡面调整器", "战斗实验室"]:
		await key(KEY_ESCAPE)
		check(paused and main._escape_pause_menu.is_menu_open(), "Esc暂停并打开菜单")
		var button := menu_button(text)
		var point: Vector2 = shell.render_container.get_global_transform_with_canvas() * button.get_global_rect().get_center()
		var received: Array[bool] = []
		button.pressed.connect(func(): received.append(true), CONNECT_ONE_SHOT)
		await click(point)
		print("菜单点击：", text, " pressed=", received, " target=", button.get_path(), " target_process=", button.can_process(), " hover=", shell.internal_viewport.gui_get_hovered_control().get_path() if shell.internal_viewport.gui_get_hovered_control() else "none", " paused=", paused, " main_visible=", main.visible)
		check(not received.is_empty() and not main.visible, text + "真实点击打开工具")
		check(not paused and not main._escape_pause_menu.is_menu_open(), "工具接管前关闭暂停菜单")
		check(not main.get_node("EscapeMenuLayer").visible, "工具打开时隐藏Main菜单图层")
		await key(KEY_ESCAPE)
		check(main.visible and not paused, "真实Esc关闭工具回到可操作Main")
		await process_frame
	await key(KEY_ESCAPE)
	await click(shell.render_container.get_global_transform_with_canvas() * menu_button("导出诊断日志").get_global_rect().get_center())
	var dialog: FileDialog = main._run_diagnostic_dialog
	check(dialog != null and dialog.visible, "真实点击打开诊断文件框")
	if dialog != null:
		print("文件框 process=", dialog.can_process(), " embedded=", dialog.is_embedded(), " position=", dialog.position, " cancel=", dialog.get_cancel_button().get_global_rect())
		await click(Vector2(dialog.position) + dialog.get_cancel_button().get_global_rect().get_center())
		check(not dialog.visible and paused, "真实点击取消文件框，保留菜单暂停")
		await click(shell.render_container.get_global_transform_with_canvas() * menu_button("导出诊断日志").get_global_rect().get_center())
		dialog.current_dir = "/private/tmp"
		dialog.current_file = ""
		await process_frame
		var filename: LineEdit = dialog.get_line_edit()
		await click(Vector2(dialog.position) + filename.get_global_rect().get_center())
		var exported_name := "project-card-ui-export-%d.json" % Time.get_ticks_usec()
		for character: String in exported_name: await key(KEY_NONE, character.unicode_at(0))
		check(filename.text == exported_name, "文件名控件真实键盘输入")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/private/tmp/project-card-menu-file-dialog.png")
		await click(Vector2(dialog.position) + dialog.get_ok_button().get_global_rect().get_center())
		check(FileAccess.file_exists("/private/tmp/" + exported_name), "文件框真实点击保存导出JSON")
		var message: AcceptDialog = main.battle_diagnostic_message_dialog
		check(message != null and message.visible and message.can_process(), "暂停中导出结果提示可以处理输入")
		if message != null:
			await click(Vector2(message.position) + message.get_ok_button().get_global_rect().get_center())
			check(not message.visible, "真实点击关闭导出结果提示")
	await click(shell.render_container.get_global_transform_with_canvas() * menu_button("返回").get_global_rect().get_center())
	await process_frame
	check(not paused, "关闭菜单恢复运行")
	shell.queue_free()
	await process_frame
	print("菜单图形输入专项：%d项，失败%d" % [assertions,failures])
	quit(1 if failures else 0)
