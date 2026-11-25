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

func click(point: Vector2, button_index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button_index
		event.pressed = pressed
		event.button_mask = (1 << (button_index - 1)) if pressed else 0
		root.push_input(event, true)
		await process_frame
	if shell.screen_transition.busy: await shell.screen_transition.finished

func key(code: Key, unicode: int = 0) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.unicode = unicode
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	if shell.screen_transition.busy: await shell.screen_transition.finished

func menu_button(text: String) -> Button:
	for node: Node in main._escape_pause_menu.find_children("*", "Button", true, false):
		if node.text == text and node.is_visible_in_tree(): return node
	return null

func finish_book_motion() -> void:
	while main._escape_pause_menu.is_transitioning() or main.is_page_turning(): await process_frame

func capture_turn_frame(file_name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/" + file_name)

func verify_inspection_teaching(owned: OwnedCard) -> void:
	main._open_card_inspection(owned.card_data, owned)
	await create_timer(0.34).timeout
	var inspection: Control = main._inspection_overlay
	var card: CardView = main._inspection_card_view
	var effect: Control = inspection.get_node_or_null("InspectionEffectSideBox")
	if main._inspection_library_expanded:
		main.set_inspection_library_expanded(false)
		await main._inspection_tween.finished
	var card_side_x: float = effect.position.x if effect != null else 0.0
	main.set_inspection_library_expanded(true)
	await main._inspection_tween.finished
	check(effect != null and effect.position.x >= inspection.size.x, "普通检视展开工具箱后，原说明滑出右侧")
	var toast: Control = main._gameplay_teaching_toast
	toast.notify("tutorial:step:wounds", "伤势", 10.0, true)
	await create_timer(0.45).timeout
	var canvas: Transform2D = shell.render_container.get_global_transform_with_canvas()
	await click(canvas * toast._button.get_global_rect().get_center())
	var book: Control = main._escape_pause_menu.active_overlay()
	check(is_instance_valid(book) and book.name == "InspectionTeachingBook" and not main._escape_pause_menu.is_menu_open(), "检视中点击提示打开独立教程书")
	if not is_instance_valid(book): return
	check(book.has_node("BookBaseArt") and book.has_node("TutorialHelpPage") and main._inspection_overlay == inspection, "教程书自带完整书页并保留原检视")
	await click(canvas * Vector2(1210, 490), MOUSE_BUTTON_RIGHT)
	await key(KEY_F2)
	check(main._escape_pause_menu.is_teaching_book_open() and main._inspection_overlay == inspection and not main._developer_console.visible, "独立教程书拦截对检视和开发控制台的操作")
	await key(KEY_TAB)
	var focus := shell.internal_viewport.gui_get_focus_owner() as Control
	check(focus != null and book.is_ancestor_of(focus), "Tab焦点留在独立教程书里")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-batch1-inspection-teaching.png")
	await key(KEY_ESCAPE)
	check(not main._escape_pause_menu.is_teaching_book_open() and main._inspection_card_view == card and main._inspection_library_expanded, "首次Esc只关教程，恢复同一张卡和工具箱状态")
	main.set_inspection_library_expanded(false)
	await main._inspection_tween.finished
	check(is_instance_valid(effect) and is_equal_approx(effect.position.x, card_side_x), "收回工具箱后同一说明面板滑回原位置")
	await key(KEY_ESCAPE)
	await create_timer(0.25).timeout
	check(not is_instance_valid(main._inspection_overlay) and not paused, "再次Esc按原顺序退出检视")

func _run() -> void:
	shell = DISPLAY.instantiate()
	DirAccess.make_dir_recursive_absolute("/private/tmp/project-card-escape-input")
	shell.run_slots.directory = "/private/tmp/project-card-escape-input"
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-menu-input-save.json"
	root.add_child(shell)
	await process_frame
	await process_frame
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	for i in range(6): await process_frame
	check(root.size == Vector2i(2560,1440), "真实2K窗口")
	main.set_world_view(main.WorldView.COLLECTION, false)
	# 从最近使用页打开菜单，返回时应保留这批卡槽及原有书签状态。
	var owned: OwnedCard = main.owned_card_collection.create_card(preload("res://resources/cards/militia.tres"))
	main._record_recently_returned_card(owned.card_data, owned)
	main.toggle_action_filter(CardData.ActionType.MELEE)
	main.toggle_element_filter(CardData.ElementType.WATER)
	main.toggle_rarity_filter(CardData.Rarity.I)
	main.search_edit.text = "民兵"
	main.apply_search()
	var bookmark: TextureButton = main.menu_bookmark_button
	var canvas: Transform2D = shell.render_container.get_global_transform_with_canvas()
	while main.is_recent_bookmark_shaking(): await process_frame
	var red_rest := bookmark.get_global_transform_with_canvas().origin
	var blue_rest: Vector2 = main.recent_bookmark_button.get_global_transform_with_canvas().origin
	check(bookmark.z_index == main.recent_bookmark_button.z_index and red_rest.y == blue_rest.y, "两枚收回书签共用纸页层级和高度")
	var blue_bookmark: TextureButton = main.recent_bookmark_button
	await click(canvas * Vector2(blue_bookmark.get_global_rect().get_center().x, blue_rest.y + 12))
	check(main.is_page_turning() and blue_bookmark.get_global_transform_with_canvas().origin.is_equal_approx(blue_rest), "点击露出的蓝签，书签保持原位置并开始翻页")
	await finish_book_motion()
	check(blue_bookmark.z_index == main.BOOKMARK_PAGE_Z and bookmark.z_index == main.BOOKMARK_REST_Z, "最近使用页只把蓝签压在纸面前方")
	await capture_turn_frame("project-card-blue-bookmark-open.png")
	var original_slots: Array[Node] = main.collection_card_row.get_children()
	check(original_slots[0].get_meta("owned_card", null) == owned, "最近使用页包含已加入的真实随从")
	var original_page: int = main.current_collection_page
	await click(canvas * bookmark.get_global_rect().get_center())
	check(main.is_page_turning() and main._page_turn_overlay.get_node("MovingPage")._leaf_count == 3 and main._page_turn_overlay.get_meta("direction") == 1, "蓝签切红签正向翻动三张纸")
	var backdrop: Control = main._escape_pause_menu._menu_backdrop
	await create_timer(0.10).timeout
	check(backdrop.modulate.a > 0.0 and backdrop.modulate.a < 1.0 and not main._escape_pause_menu.is_menu_open(), "展开红签时背景与翻页同步逐渐变暗")
	var turn: Control = main._page_turn_overlay
	var moving: Control = turn.get_node("MovingPage")
	var spread: SubViewport = moving.get_node("PageFaces/PauseMenuSpread")
	check(turn.get_parent() == main.get_node("%BookPanel") and not main._escape_pause_menu._menu.has_node("BookBaseArt"), "暂停卷页和落定后的菜单共用同一套书皮、纸叠和筛选层级")
	check(turn.has_node("StaticTargetPage/PausePageContent") and moving.has_node("PageFaces/BackFace/PausePageContent") and spread.is_ancestor_of(main._escape_pause_menu._home) and spread.is_ancestor_of(main._escape_pause_menu._tasks), "任务已印在目标右页，暂停按钮已印在最后一张纸的背面")
	check(moving.right_bookmark == blue_bookmark and bookmark.z_index < moving.z_index, "正翻时旧右页逐步遮住蓝签，红签从活动纸面后露出")
	check(bookmark.get_global_transform_with_canvas().origin.is_equal_approx(red_rest) and main.recent_bookmark_button.get_global_transform_with_canvas().origin.is_equal_approx(blue_rest), "两枚书签随卷页遮挡而露出，全程保持原位置")
	await capture_turn_frame("project-card-pause-opening.png")
	await finish_book_motion()
	check(paused and main._escape_pause_menu.is_menu_open() and not main.collection_card_row.visible, "红色书签打开收藏内的暂停菜单并替换卡牌")
	var red_selected := bookmark.get_global_transform_with_canvas().origin
	check(red_selected.is_equal_approx(red_rest) and blue_bookmark.get_global_transform_with_canvas().origin.is_equal_approx(blue_rest)
		and bookmark.z_index == main.BOOKMARK_PAGE_Z and blue_bookmark.size.y == main.BOOKMARK_TIP_HEIGHT,
		"暂停页只把红签压在纸面前方，蓝签原处露出上缘")
	var action_tab: Control = main.action_filter_tabs.get_child(CardData.ActionType.MELEE)
	var action_hotspot := action_tab.get_node("Hotspot") as Button
	var rarity_button: BaseButton = main.rarity_buttons.get_child(CardData.Rarity.I)
	var element_index: int = main.ELEMENT_FILTER_TYPES.find(CardData.ElementType.WATER)
	var element_button: BaseButton = main.element_buttons.get_child(element_index)
	check(not action_hotspot.button_pressed and action_tab.position.y == main.ACTION_TAB_REST_Y and not rarity_button.button_pressed and not element_button.button_pressed and main.search_edit.text.is_empty() and main.regular_pages_art.visible, "打开菜单时筛选收回，显示普通收藏纸面")
	var page: Rect2 = main.collection_viewport.get_global_rect()
	check(page.encloses(main._escape_pause_menu._home.get_global_rect()) and page.encloses(main._escape_pause_menu._tasks.get_global_rect()), "暂停首页和任务内容都在收藏书页内")
	check(backdrop.modulate.a == 1.0 and not shell.display_mode_option.get_parent().visible, "暗幕覆盖桌面，外层显示控件关闭")
	await click(canvas * menu_button("玩法教学").get_global_rect().get_center())
	check(page.encloses(main._escape_pause_menu._info.get_global_rect()) and not main._escape_pause_menu.selected_teaching_key.is_empty(), "玩法教学目录与正文都在收藏书页内")
	await key(KEY_ESCAPE)
	await click(canvas * menu_button("设置").get_global_rect().get_center())
	check(page.encloses(main._escape_pause_menu._settings._settings_body.get_global_rect()), "设置子页保留在收藏书页内")
	check(main._escape_pause_menu._settings._settings_body.get_theme_stylebox("panel") is StyleBoxEmpty, "设置使用底下真实书页背景")
	var keys := main._escape_pause_menu._settings.find_child("BattleKeyHints", true, false) as Label
	check(keys != null and page.encloses(keys.get_global_rect()) and keys.text.contains("空格"), "设置书页内显示完整战斗键位")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-collection-menu-settings.png")
	await click(canvas * bookmark.get_global_rect().get_center())
	check(main.is_page_turning() and main._page_turn_overlay.get_node("MovingPage")._leaf_count == 3 and main._page_turn_overlay.get_meta("direction") == -1, "取消红签反向翻动三张纸")
	check(main._page_turn_overlay.get_node("MovingPage/PageFaces/PauseMenuSpread").is_ancestor_of(main._escape_pause_menu._settings), "从设置返回时，设置仍随原纸面一起翻走")
	await finish_book_motion()
	check(not paused and main.collection_card_row.visible and main.collection_bookmark_active and main.current_collection_page == original_page and main.collection_card_row.get_children() == original_slots, "设置页再次点书签可直接恢复原来的最近使用卡槽")
	check(action_hotspot.button_pressed and rarity_button.button_pressed and element_button.button_pressed and main.search_edit.text == "民兵", "回到收藏后恢复筛选外观和搜索内容")
	main.toggle_recent_bookmark()
	await finish_book_motion()
	await click(canvas * bookmark.get_global_rect().get_center())
	moving = main._page_turn_overlay.get_node("MovingPage")
	check(bookmark.z_index < moving.z_index and bookmark.get_global_transform_with_canvas().origin.is_equal_approx(red_rest), "普通收藏翻向红签时，活动纸面可自然掩过固定位置的书签")
	while is_instance_valid(moving) and moving.progress < 0.85: await process_frame
	await capture_turn_frame("project-card-pause-last-leaf.png")
	await finish_book_motion()
	await capture_turn_frame("project-card-pause-open.png")
	await click(canvas * main.recent_bookmark_button.get_global_rect().get_center())
	check(main.is_page_turning() and main._page_turn_overlay.get_meta("direction") == -1, "红签切蓝签走返回方向")
	moving = main._page_turn_overlay.get_node("MovingPage")
	check(moving.right_bookmark == blue_bookmark and bookmark.z_index < moving.z_index, "反翻时新右页逐步露出蓝签，活动纸面盖过红签")
	await finish_book_motion()
	check(not paused and main.collection_bookmark_active and blue_bookmark.z_index == main.BOOKMARK_PAGE_Z
		and bookmark.z_index == main.BOOKMARK_REST_Z and blue_bookmark.size.y == main.RECENT_CARDS_BOOKMARK_TEXTURE.get_height(),
		"从暂停页点击蓝签露出的上缘可进入最近使用页并露出整枚蓝签")
	main.toggle_recent_bookmark()
	await finish_book_motion()
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await verify_inspection_teaching(owned)
	for text: String in ["攻击特效调试器", "卡面调整器", "战斗实验室"]:
		await key(KEY_ESCAPE)
		check(paused and main._escape_pause_menu.is_transitioning() and not main._escape_pause_menu.is_menu_open() and main.world_content.position.y > -main.COLLECTION_VIEW_ORIGIN.y, "上半按Esc先暂停并开始移动，首页等待镜头落定")
		await key(KEY_ESCAPE)
		await finish_book_motion()
		check(paused and main._escape_pause_menu.is_menu_open() and main.current_world_view == main.WorldView.COLLECTION and main._player_avatar_frame_index == 0, "Esc暂停并完成镜头及头像转身后打开收藏菜单")
		await click(shell.render_container.get_global_transform_with_canvas() * menu_button("开发工具").get_global_rect().get_center())
		check(main._escape_pause_menu._tools.is_visible_in_tree() and page.encloses(main._escape_pause_menu._tools.get_global_rect()), "开发工具按钮完整落在收藏书页内")
		if text == "攻击特效调试器" and OS.get_cmdline_user_args().has("screenshots"):
			await RenderingServer.frame_post_draw
			shell.internal_viewport.get_texture().get_image().save_png("res://docs/previews/d3_1_menu_20261102/06_tools.png")
		var button := menu_button(text)
		var point: Vector2 = shell.render_container.get_global_transform_with_canvas() * button.get_global_rect().get_center()
		var received: Array[bool] = []
		button.pressed.connect(func(): received.append(true), CONNECT_ONE_SHOT)
		await click(point)
		print("菜单点击：", text, " pressed=", received, " target=", button.get_path(), " target_process=", button.can_process(), " hover=", shell.internal_viewport.gui_get_hovered_control().get_path() if shell.internal_viewport.gui_get_hovered_control() else "none", " paused=", paused, " main_visible=", main.visible)
		check(not received.is_empty() and not main.visible, text + "真实点击打开工具")
		check(not paused and not main._escape_pause_menu.is_menu_open() and main.current_world_view == main.WorldView.BATTLEFIELDS, "工具接管前关闭书页菜单并恢复原视角")
		check(not main.get_node("EscapeMenuLayer").visible, "工具打开时隐藏Main菜单图层")
		await key(KEY_ESCAPE)
		check(main.visible and not paused, "真实Esc关闭工具回到可操作Main")
		await process_frame
	await key(KEY_ESCAPE)
	await finish_book_motion()
	await click(shell.render_container.get_global_transform_with_canvas() * menu_button("开发工具").get_global_rect().get_center())
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
	await key(KEY_ESCAPE)
	await click(shell.render_container.get_global_transform_with_canvas() * menu_button("继续游戏").get_global_rect().get_center())
	await create_timer(0.10).timeout
	check(backdrop.modulate.a > 0.0 and backdrop.modulate.a < 1.0 and main.is_page_turning(), "合上红签时背景在翻页中逐渐回亮")
	turn = main._page_turn_overlay
	moving = turn.get_node("MovingPage")
	check(turn.has_node("StaticOldPage/PausePageContent") and moving.has_node("PageFaces/FrontFace/PausePageContent"), "继续游戏时任务留在原右页，暂停按钮随第一页翻离")
	await capture_turn_frame("project-card-pause-closing.png")
	await main._page_tween.finished
	var return_camera: Tween = main._view_tween
	check(return_camera != null and return_camera.is_running() and paused and main.world_content.position.is_equal_approx(-main.COLLECTION_VIEW_ORIGIN), "书页翻回后才启动上移，途中仍暂停")
	await create_timer(0.12).timeout
	check(main.world_content.position.y > -main.COLLECTION_VIEW_ORIGIN.y and main.world_content.position.y < 0.0 and paused, "回战场经过中间位置，镜头未瞬移")
	await finish_book_motion()
	check(not paused and main.world_content.position.is_equal_approx(-main.BATTLEFIELD_VIEW_ORIGIN) and backdrop.modulate.a == 0.0, "回到战场后释放暂停并完全恢复亮度")
	shell.queue_free()
	await process_frame
	print("菜单图形输入专项：%d项，失败%d" % [assertions,failures])
	quit(1 if failures else 0)
