extends "res://tests/d3_4_ui_test.gd"

const Catalog = preload("res://scripts/ui/developer_tool_catalog.gd")
const TEMP := "/private/tmp/project-card-start-menu-tools"


func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("主界面开发工具专项超时"); quit(1))
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = TEMP
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_720P)
	await frames()
	var selection := FileAccess.get_file_as_bytes(TEMP.path_join("selection.cfg")) if FileAccess.file_exists(TEMP.path_join("selection.cfg")) else PackedByteArray()
	check(shell.main_screen == null and shell.start_menu.visible, "不载入对局即可进入主界面")
	await click_control(shell.start_menu.find_child("SettingsButton", true, false))
	var settings: Control = shell._settings_panel
	check(settings.visible and settings.find_child("SettingsDeveloperToolsButton", true, false).visible, "主界面设置显示开发工具入口")
	await click_control(settings.find_child("SettingsDeveloperToolsButton", true, false))
	check(settings._tools.visible, "实际点击进入开发工具子页")
	for entry: Array in Catalog.ENTRIES:
		var button: Button = settings.find_child(entry[1], true, false)
		check(button.is_visible_in_tree() and Rect2(0, 0, 1280, 720).encloses(button.get_global_rect()), "工具入口完整位于画布：" + entry[0])
		await click_control(button)
		while shell.screen_transition.busy: await process_frame
		check(shell.is_developer_tool_open() and shell.main_screen == null and not settings.visible and not shell.start_menu.visible, "从主菜单直接打开工具：" + entry[0])
		await key_escape()
		while shell.screen_transition.busy: await process_frame
		check(not shell.is_developer_tool_open() and settings.visible and settings._tools.visible and shell.start_menu.visible and shell.main_screen == null, "Esc退出回到设置工具页且未进入对局：" + entry[0])
	var preview_dir := "res://docs/previews/start_menu_tools_20261106"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(preview_dir))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preview_dir.path_join("01_tools_in_settings.png"))
	await key_escape()
	check(settings.visible and not settings._tools.visible, "Esc从开发工具子页回到普通设置")
	await key_escape()
	check(not settings.visible and shell.start_menu.visible, "再按Esc关闭设置，仍在主界面")
	check(shell.slot_progress == null and not FileAccess.file_exists(shell.run_slots.get_slot_path(0)), "全过程不创建玩家对局存档")
	var after := FileAccess.get_file_as_bytes(TEMP.path_join("selection.cfg")) if FileAccess.file_exists(TEMP.path_join("selection.cfg")) else PackedByteArray()
	check(after == selection, "调试不改变存档选择记录")
	shell.free()
	print("Start menu developer tools: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
