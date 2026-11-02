extends "res://tests/service_interaction_revision_20261020_test.gd"

const Settings = preload("res://scripts/ui/card_text_display_settings.gd")
const PREVIEWS := "res://docs/previews/card_feedback_20261102"

func capture_feedback(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEWS))
	root.get_texture().get_image().save_png(PREVIEWS.path_join(name + ".png"))

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("卡牌反馈专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-feedback-revision.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_720P)
	Settings.set_mode(self, Settings.Mode.POPUP, false)
	for owned: OwnedCard in main.owned_card_collection.get_cards(): main.owned_card_collection.remove_by_instance_id(owned.instance_id)
	var moon: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/moon_hawk.tres"))
	var gun: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
	var beer: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/beer_mug.tres"))
	moon.surface_finish = CardAppearance.Surface.FRACTURED
	moon.is_new = false
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	main.set_world_view(main.WorldView.COLLECTION, false)
	await create_timer(0.4).timeout
	var view: CardView = main._find_collection_slot_for_owned_card(moon).get_child(0)
	var other: CardView = main._find_collection_slot_for_owned_card(gun).get_child(0)
	var mug: CardView = main._find_collection_slot_for_owned_card(beer).get_child(0)
	check(beer.card_data.display_name == "啤酒杯" and mug.cooldown_label.text == "0", "移除啤酒杯emoji，零热诚只显示0")
	check(is_instance_valid(view._finish_controller._rest_flash) and view._finish_controller._rest_flash.visible and view._finish_controller._rest_flash.material.get_shader_parameter("use_fractured"), "局内收藏静止碎闪有真实绘制节点")
	await _motion(Vector2(1270, 700))
	await capture_feedback("01_collection_rest")
	await _motion(view.get_global_transform_with_canvas() * Vector2(75, 45))
	await create_timer(0.35).timeout
	await _click(view)
	check(not main._click_carry_data.is_empty() and main._click_carry_preview.get_parent() == main._click_carry_layer, "真实抓牌进入最高携带层")
	await _motion(other.get_global_transform_with_canvas() * Vector2(70, 50))
	await create_timer(0.8).timeout
	var popup = get_first_node_in_group(&"card_effect_popup")
	check(popup == null or not popup.panel.visible, "抓牌经过其他卡时不触发效果提示")
	check(not shell.get_collection_hover_surface().visible and not is_instance_valid(other._collection_hover_surface), "抓牌时不创建盖在手持卡上方的悬停层")
	await capture_feedback("02_carry_above")
	main._cancel_click_carry()
	main.front_row.clear_squads()
	var squad := SquadData.from_cards([moon.get_battlefield_card(), gun.get_battlefield_card()])
	squad.bind_owned_card(moon.get_battlefield_card(), moon)
	squad.bind_owned_card(gun.get_battlefield_card(), gun)
	main.front_row.add_squad(squad, 0)
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	main._refresh_drag_availability()
	await create_timer(0.4).timeout
	var slot: SquadView = main.front_row.get_squads()[0]
	slot.set_prefer_minion(true)
	var front: CardView = slot.get_card_view(moon.get_battlefield_card())
	check(front._finish_controller._rest_flash.visible and front._finish_controller._rest_flash.material.get_shader_parameter("use_fractured"), "战场实体卡也显示静止碎闪")
	await _motion(front.get_global_transform_with_canvas() * Vector2(65, 45))
	await create_timer(0.4).timeout
	popup = get_first_node_in_group(&"card_effect_popup")
	check(popup != null and popup.panel.visible and popup.source == front, "堆叠卡悬停出现目标卡效果提示")
	await create_timer(0.6).timeout
	check(slot.get_active_drag_kind() == &"squad" and popup.panel.visible and popup.source == front, "切换选中小队后仍保留原目标卡效果提示")
	var force: Vector2 = front._finish_controller._rest_flash.material.get_shader_parameter("pointer_force")
	check(force.length() > 0.1, "战场碎闪响应真实鼠标指向")
	await capture_feedback("03_squad_effect_and_fractured")
	await _motion(Vector2(1270, 700))
	await create_timer(0.2).timeout
	check(not popup.panel.visible, "真正移开小队时提示正确消失")
	shell.queue_free()
	await process_frame
	await process_frame
	print("卡牌反馈修正：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
