extends "res://tests/service_interaction_revision_20261020_test.gd"

## 真实收藏、GPU与原生输入；原槽仍负责命中，只有当前悬停卡创建检视画布。
const Appearance = preload("res://scripts/data/card_appearance.gd")
const SAVE := "/private/tmp/project-card-collection-card-tilt.json"

func hover(view: CardView, fraction: Vector2) -> void:
	await _motion(view.get_global_transform_with_canvas() * (view.card_size * fraction))
	await create_timer(0.18).timeout

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("收藏倾斜专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K if "2k" in OS.get_cmdline_user_args() else shell.DisplayMode.WINDOW_720P)
	await create_timer(0.65).timeout
	main.set_world_view(main.WorldView.COLLECTION, false)
	var definition := load("res://resources/cards/militia.tres") as CardData
	var cards: Array[OwnedCard] = []
	for art: int in Appearance.Art.size():
		for face: int in Appearance.Surface.size():
			var owned: OwnedCard = main.owned_card_collection.create_card(definition, main.ordinary_shop_service.rng)
			owned.surface_finish = face as Appearance.Surface
			owned.art_finish = art as Appearance.Art
			cards.append(owned)
	var rng: int = main.ordinary_shop_service.rng.state
	var total: int = main.owned_card_collection.size()
	for owned: OwnedCard in cards:
		await _motion(Vector2(1270, 700))
		var view := _show_owned(owned)
		await process_frame
		var resting := view.position
		var original_parent := view.get_parent()
		await hover(view, Vector2(0.75, 0.3))
		var surface = view._collection_hover_surface
		check(is_instance_valid(surface), "真实鼠标悬停创建卡面检视倾斜")
		if not is_instance_valid(surface): quit(1); return
		check(view.position == resting and view.get_parent() == original_parent and view._external_lift == 0 and view.rotation == 0, "原卡保持原位置与原父节点，不再跳起或平面轻晃")
		check(surface.card.get_owned_card() == owned and surface.mouse_filter == Control.MOUSE_FILTER_IGNORE and surface.card.is_snapshot_mode() and view.modulate.a == 0, "显示副本引用同一实例，固定原卡接收输入")
		check(surface.force.x > 0.2 and surface.force.y < -0.1 and surface.card._finish_controller._art_material.get_shader_parameter("pointer_force") == surface.force, "鼠标位置同时驱动透视与内层罕贵度光照")
		check(bool(surface.effect.get_shader_parameter("use_flash")) == (owned.surface_finish in [Appearance.Surface.SILVER, Appearance.Surface.GOLD, Appearance.Surface.RAINBOW]) and bool(surface.effect.get_shader_parameter("use_fractured")) == (owned.surface_finish == Appearance.Surface.FRACTURED), "实际卡面工艺在收藏悬停中生效")
		check(surface.card._finish_controller._overframe_clip.visible == (owned.art_finish == Appearance.Art.OVERFRAME), "超框与普通／全息卡图仍按实例组合")
		check(surface.viewport.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST, "悬停原画保持最近邻硬像素")
		await hover(view, Vector2(0.25, 0.65))
		check(surface.force.x < -0.2 and surface.force.y > 0.1 and view._collection_hover_surface == surface, "卡内移动反向倾斜，复用同一活动画布")
		await create_timer(0.2).timeout
		check(surface.card.showing_effect == view.showing_effect, "原悬停描述切换同步到倾斜卡面")
		if owned.surface_finish == Appearance.Surface.FRACTURED and owned.art_finish == Appearance.Art.HOLOGRAPHIC:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/private/tmp/project-card-collection-tilt.png")
		await _motion(Vector2(1270, 700))
		await create_timer(0.4).timeout
		check(not is_instance_valid(view._collection_hover_surface) and view.modulate == Color.WHITE and view.position == resting, "移开平滑回正后清理活动画布并恢复原卡显示")
	check(main.owned_card_collection.size() == total and main.ordinary_shop_service.rng.state == rng, "18种组合悬停不生成实际卡或消耗玩法随机流")
	var first := _show_owned(cards[0])
	await process_frame
	await hover(first, Vector2(0.5, 0.5))
	await _click(first)
	check(not main._click_carry_data.is_empty() and not is_instance_valid(first._collection_hover_surface) and first.modulate.a > 0, "真实单击仍携带原卡，拿起前清理倾斜画布")
	main._cancel_click_carry()
	await create_timer(0.4).timeout
	first = _show_owned(cards[0])
	await process_frame
	await hover(first, Vector2(0.6, 0.4))
	await native_pick(first)
	check(not is_instance_valid(first._collection_hover_surface), "原生长按拖动时清理倾斜，不复制拖拽来源")
	await _motion(Vector2(1270, 700), true)
	await _mouse(Vector2(1270, 700), false)
	await create_timer(0.4).timeout
	first = _show_owned(cards[0])
	await process_frame
	await hover(first, Vector2(0.6, 0.4))
	var point := first.get_global_transform_with_canvas() * (first.card_size * 0.5)
	var event := InputEventMouseButton.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await create_timer(0.4).timeout
	check(is_instance_valid(main._inspection_surface) and main._inspection_owned_card == cards[0] and not is_instance_valid(first._collection_hover_surface), "右键仍打开原实例检视，原悬停画布清理")
	main._close_card_inspection(true)
	await create_timer(0.35).timeout
	first = _show_owned(cards[0])
	await process_frame
	await hover(first, Vector2(0.5, 0.5))
	main._build_collection_cards()
	await process_frame
	check(not is_instance_valid(CardView._collection_hover_owner), "翻页或重建收藏时旧悬停与静态引用释放")
	shell.queue_free()
	await process_frame
	await process_frame
	for path: String in [SAVE + ".diagnostics.jsonl", SAVE + ".diagnostics.jsonl.previous"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("收藏悬停倾斜：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
