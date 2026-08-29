extends SceneTree

## 1×内部画布、正式运行素材与四档显示模式集成检查。

const DISPLAY_SCENE: PackedScene = preload("res://scenes/GameDisplay.tscn")

var _failure_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_test_project_window_defaults()
	await _test_display_scene()
	if _failure_count == 0:
		print("Game display checks passed.")
	else:
		push_error("Game display checks failed: %d" % _failure_count)
	quit(_failure_count)


func _test_project_window_defaults() -> void:
	_expect(
		ProjectSettings.get_setting("application/run/main_scene")
		== "res://scenes/GameDisplay.tscn",
		"项目从 1×内部画布显示壳启动"
	)
	_expect(
		ProjectSettings.get_setting("display/window/size/mode")
		== DisplayServer.WINDOW_MODE_WINDOWED
		and ProjectSettings.get_setting_with_override("display/window/size/mode")
		== DisplayServer.WINDOW_MODE_WINDOWED
		and ProjectSettings.get_setting("display/window/size/window_width_override") == 1920
		and ProjectSettings.get_setting("display/window/size/window_height_override") == 1080
		and not ProjectSettings.get_setting("display/window/size/resizable"),
		"编辑器与导出版本都从真实 1080p 窗口启动，不再先进入伪全屏"
	)


func _test_display_scene() -> void:
	var display := DISPLAY_SCENE.instantiate() as GameDisplay
	root.add_child(display)
	await process_frame
	await process_frame
	await _test_direct_output_sizes(display)
	var render_container := display.get_node("RenderContainer") as SubViewportContainer
	var main := display.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	var card := _find_real_card(main)
	_expect(card != null, "1×显示壳中的 Main 已创建真实卡牌")
	if card == null:
		display.queue_free()
		await process_frame
		return
	var first_rune := card.rune_row.get_child(0).get_child(0) as TextureRect
	var wood_world := main.get_node("WorldContent/WoodWorld") as TextureRect
	var first_action_tab := main.action_filter_tabs.get_child(0) as Control
	var action_filter_icon := first_action_tab.get_node("ActionIcon") as TextureRect
	_expect(
		display.internal_viewport.size == Vector2i(1280, 720)
		and display.design_canvas.size == Vector2(1280, 720)
		and display.design_canvas.scale == Vector2.ONE
		and display.internal_viewport.canvas_item_default_texture_filter
		== Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		and render_container.size == Vector2(1280, 720)
		and render_container.scale == Vector2(
			display.size.x / 1280.0,
			display.size.y / 720.0
		)
		and render_container.texture_filter
		== CanvasItem.TEXTURE_FILTER_NEAREST
		and not render_container.stretch
		and ProjectSettings.get_setting("display/window/stretch/mode") == "disabled",
		"内部1×像素先以最近邻合成，2K整数倍率继续使用最近邻输出"
	)
	_expect(
		display.size == Vector2(display.get_window().size)
		and render_container.mouse_filter != Control.MOUSE_FILTER_IGNORE
		and not display.internal_viewport.gui_disable_input,
		"SubViewportContainer 负责 1×内部视口到客户区的一次缩放与输入反映射"
	)
	_expect(
		card.card_frame.texture.get_size() == Vector2(99, 136)
		and first_rune.texture.get_size() == Vector2(23, 23),
		"显示壳内的真实 CardView 直接使用正式 1×卡框和符文"
	)
	_expect(
		card.card_size == Vector2(99, 136)
		and card.card_frame.size == Vector2(99, 136)
		and first_rune.size == Vector2(23, 23),
		"1×运行纹理不改变卡牌、符文与玩法的设计坐标"
	)
	_expect(
		card.value_label.number_style == RuneNumberDisplay.NumberStyle.LARGE
		and card.health_label.number_style == RuneNumberDisplay.NumberStyle.LARGE
		and card.armor_label.number_style == RuneNumberDisplay.NumberStyle.MEDIUM
		and card.cooldown_label.number_style
		== RuneNumberDisplay.NumberStyle.COOLDOWN,
		"运行时行动、生命、护甲与冷却使用新版1×卢恩图片数字"
	)
	_expect(
		wood_world.texture.get_size() == Vector2(1280, 1240)
		and wood_world.size == Vector2(1280, 1240),
		"1×世界背景保持原来的 1280×1240 逻辑尺寸"
	)
	_expect(
		action_filter_icon.texture == main.ACTION_FILTER_TEXTURES[CardData.ActionType.MELEE]
		and action_filter_icon.position
		== main.get_action_tab_icon_rect(CardData.ActionType.MELEE).position
		and action_filter_icon.size
		== main.get_action_tab_icon_rect(CardData.ActionType.MELEE).size
		and action_filter_icon.stretch_mode == TextureRect.STRETCH_KEEP
		and action_filter_icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"1×运行素材的行动筛选图标使用原图尺寸与整数像素坐标"
	)
	var grab_local_position := card.card_size * Vector2(0.75, 0.25)
	var native_drag_data := card._build_drag_data(grab_local_position)
	card._apply_native_drag_visual_metrics(native_drag_data)
	var native_drag_visual := CardView.create_drag_visual(native_drag_data)
	display.internal_viewport.add_child(native_drag_visual)
	native_drag_visual.global_position = Vector2(2560, 1440)
	await process_frame
	var native_drag_card := native_drag_visual.get_card_visual() as TextureRect
	var native_snapshot := native_drag_visual.get_node("CardSnapshotVisual")
	var transformed_grab_position: Vector2 = (
		native_drag_card.get_global_transform_with_canvas()
		* (
			grab_local_position
			+ native_snapshot.get_card_origin_in_texture()
		)
	)
	_expect(
		native_drag_data["preview_scale"] == Vector2.ONE
		and native_drag_data["drag_visual_scale"] == Vector2.ONE
		and native_drag_data["drag_visual_offset"]
		== grab_local_position
		and native_drag_card.scale == Vector2.ONE,
		"原生长按拖拽视觉与当前 1×画布一致，堆叠规则尺寸仍保持逻辑 1×"
	)
	_expect(
		transformed_grab_position.distance_to(native_drag_visual.global_position) < 1.0,
		"1×原生拖拽预览仍以实际鼠标按下位置为支点"
	)
	native_drag_visual.queue_free()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var animation_slot := front_row.add_card(main.collection_cards[0], 0)
	await process_frame
	await process_frame
	var slot_canvas_position := (
		animation_slot.card_visual_layer
		.get_global_transform_with_canvas()
		.origin
	)
	animation_slot.animate_from_global_position(
		slot_canvas_position - Vector2(120, 0)
	)
	_expect(
		is_equal_approx(animation_slot.card_visual_layer.position.x, -120.0),
		"1×内部画布的 120px 全局位移保持为 120px 本地让位"
	)
	var card_resting_position := card.position
	var card_canvas_position := card.get_global_transform_with_canvas().origin
	card.animate_from_global_position(card_canvas_position + Vector2(80, 0))
	_expect(
		is_equal_approx(card.position.x - card_resting_position.x, 80.0),
		"1×内部画布的收藏飞入起点保持逻辑距离"
	)
	_expect(
		display.display_mode_option.item_count == 4
		and display.get_window_size_for_mode(GameDisplay.DisplayMode.WINDOW_720P)
		== Vector2i(1280, 720)
		and display.get_window_size_for_mode(GameDisplay.DisplayMode.WINDOW_1080P)
		== Vector2i(1920, 1080)
		and display.get_window_size_for_mode(GameDisplay.DisplayMode.WINDOW_2K)
		== Vector2i(2560, 1440)
		and display.get_window_size_for_mode(GameDisplay.DisplayMode.ADAPTIVE_FULLSCREEN)
		== Vector2i.ZERO,
		"显示菜单提供 720p、1080p、2K窗口与自适应全屏四档"
	)

	display.apply_display_mode(GameDisplay.DisplayMode.WINDOW_720P)
	_expect(
		display.current_display_mode == GameDisplay.DisplayMode.WINDOW_720P,
		"无窗口测试中也能确定性切换显示模式状态"
	)
	main._on_card_art_tuner_button_pressed()
	await process_frame
	await process_frame
	_expect(
		display.is_card_art_tuner_open()
		and not main.visible
		and display.display_mode_option.visible
		and display.display_mode_option.is_inside_tree(),
		"进入卡面调整器时保留外层显示菜单并暂停显示 Main"
	)
	var tuner := display.design_canvas.get_node("CardArtTuner") as CardArtTuner
	tuner._on_back_button_pressed()
	await process_frame
	_expect(
		not display.is_card_art_tuner_open()
		and main.visible
		and display.display_mode_option.visible,
		"从卡面调整器返回时恢复原 Main，显示菜单与当前界面不被销毁"
	)
	display.queue_free()
	await process_frame


func _find_real_card(main: Node) -> CardView:
	for node: Node in get_nodes_in_group("card_views"):
		if (
			node is CardView
			and main.is_ancestor_of(node)
			and (node as CardView).card_data != null
		):
			return node as CardView
	return null


func _test_direct_output_sizes(display: GameDisplay) -> void:
	for output_size: Vector2i in [
		Vector2i(1280, 720),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
	]:
		root.size = output_size
		await process_frame
		var render_container := display.get_node("RenderContainer") as SubViewportContainer
		var expected_scale := Vector2(output_size) / Vector2(1280, 720)
		var expected_filter := (
			CanvasItem.TEXTURE_FILTER_NEAREST
			if output_size in [Vector2i(1280, 720), Vector2i(2560, 1440)]
			else CanvasItem.TEXTURE_FILTER_LINEAR
		)
		_expect(
			display.size == Vector2(output_size)
			and display.internal_viewport.size == Vector2i(1280, 720)
			and render_container.size == Vector2(1280, 720)
			and render_container.scale.is_equal_approx(expected_scale)
			and render_container.texture_filter == expected_filter,
			"%dx%d 使用与实际缩放倍率匹配的最近邻或线性过滤"
			% [output_size.x, output_size.y]
		)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failure_count += 1
	push_error("FAIL: %s" % message)
