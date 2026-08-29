extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")

var _failure_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_world_rows_views_and_lock()
	await _test_collection_pages_filters_and_transactions()
	if _failure_count == 0:
		print("Stage 6.5 integration checks passed.")
	else:
		push_error("Stage 6.5 integration checks failed: %d" % _failure_count)
	quit(_failure_count)


func _test_world_rows_views_and_lock() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	_expect(
		ProjectSettings.get_setting("display/window/size/viewport_width") == 1280
		and ProjectSettings.get_setting("display/window/size/viewport_height") == 720,
		"项目虚拟画布保持 1280×720"
	)
	_expect(main.world_content.size == Vector2(1280, 1080), "上下视角共用 1280×1080 纵向世界，屏幕仍只显示 1280×720")
	_expect(
		main.get_node("WorldContent/WoodWorld") != null
		and main.get_node("WorldContent/BattlefieldBackground") != null
		and main.get_node("WorldContent/TableclothDecor") != null
		and main.get_node("WorldContent/BattlefieldWoodPad") != null
		and main.get_node("WorldContent/BattlefieldBrocade") != null
		and main.get_node("%BookPanel/BookBaseArt") != null
		and main.get_node("%BookPanel/RegularPagesArt") != null
		and main.get_node("%BookPanel/RecentLeftPageArt") != null
		and main.get_node("%BookPanel/RecentRightPageArt") != null
		and main.get_node("%RecentBookmarkButton") != null,
		"高清桌面、战场四层、书皮、普通书页与最近使用书签页均为独立纹理节点"
	)
	_expect(main.enemy_avatar != null and main.player_avatar_button != null, "敌我两个人物同时存在")
	_expect(
		(main.enemy_avatar.texture as AtlasTexture).region == main.CHARACTER_FRONT_REGION,
		"敌方人物固定显示正面且只读"
	)
	_expect(
		(main.player_avatar_button.texture_normal as AtlasTexture).region == main.CHARACTER_FRONT_REGION,
		"准备视图中我方人物显示正面"
	)
	var enemy_back: BattlefieldRow = main.enemy_back_row
	var enemy_front: BattlefieldRow = main.enemy_front_row
	var player_front: BattlefieldRow = main.front_row
	var player_back: BattlefieldRow = main.back_row
	_expect(enemy_back.global_position.y < enemy_front.global_position.y, "敌方后排位于敌方前排上方")
	_expect(enemy_front.global_position.y < player_front.global_position.y, "敌方前排位于我方前排上方")
	_expect(player_front.global_position.y < player_back.global_position.y, "我方前排位于我方后排上方")
	_expect(BattlefieldRow.BATTLEFIELD_UNIT_COUNT == 21, "敌我四排继续使用 21 单元容量")
	_expect(enemy_back.get_squad_count() > 0 and enemy_front.get_squad_count() > 0, "敌方固定测试阵容使用 SquadData 建立")
	var enemy_card := enemy_back.get_squads()[0].get_squad_data().horizontal_cards[0]
	_expect(
		is_equal_approx(
			enemy_back.row_display_area.global_position.y - main.world_content.global_position.y,
			main.ENEMY_BACK_CARD_TOP_Y
		)
		and is_equal_approx(
			enemy_front.row_display_area.global_position.y - main.world_content.global_position.y,
			main.ENEMY_FRONT_CARD_TOP_Y
		)
		and is_equal_approx(
			player_front.row_display_area.global_position.y - main.world_content.global_position.y,
			main.PLAYER_FRONT_CARD_TOP_Y
		)
		and is_equal_approx(
			player_back.row_display_area.global_position.y - main.world_content.global_position.y,
			main.PLAYER_BACK_CARD_TOP_Y
		),
		"敌我四排使用校准后的世界绝对 Y 坐标"
	)
	_expect(not enemy_back.can_receive_card_drag(_collection_drag(enemy_card)), "敌方战场完全只读")
	_expect(main.current_world_view == main.WorldView.COLLECTION and is_equal_approx(main.world_content.position.y, -360.0), "准备阶段默认显示我方战场与收藏")
	_expect(main.player_avatar_button.global_position.y < 360.0, "准备视图人物按钮位于屏幕右上区域")
	main.set_phase_for_test(main.GamePhase.BATTLE)
	await create_timer(main.VIEW_TWEEN_DURATION + 0.05).timeout
	_expect(main.current_world_view == main.WorldView.BATTLEFIELDS and is_zero_approx(main.world_content.position.y), "战斗阶段默认显示敌我战场并平滑完成切换")
	_expect(main.player_avatar_button.global_position.y >= 360.0, "战斗视图人物按钮位于屏幕右下区域")
	_expect(
		(main.player_avatar_button.texture_normal as AtlasTexture).region == main.CHARACTER_BACK_REGION,
		"战斗视图中我方人物显示背面"
	)
	main.player_avatar_button.pressed.emit()
	await create_timer(main.VIEW_TWEEN_DURATION + 0.05).timeout
	_expect(
		main.current_world_view == main.WorldView.COLLECTION
		and (main.player_avatar_button.texture_normal as AtlasTexture).region == main.CHARACTER_FRONT_REGION,
		"点击我方人物会同步翻为正面并平滑切到下视图"
	)
	_expect(not player_front.can_receive_card_drag(_collection_drag(main.collection_cards[0])), "战斗阶段禁止调整我方卡牌")
	_expect(not bool(main.collection_drop_zone.get("drop_enabled")), "战斗阶段收藏只能查看")
	main.set_phase_for_test(main.GamePhase.RESULT)
	_expect(not player_back.can_receive_card_drag(_collection_drag(main.collection_cards[0])), "结算阶段继续只读")
	_expect(
		main.get_node_or_null("%StartBattleButton") != null
		and main.start_battle_button.text == "开始战斗",
		"阶段 7 新增正式开始战斗按钮，不恢复旧阶段循环调试按钮"
	)
	_expect(main.get_node_or_null("%SelectedCardView") == null and main.get_node_or_null("%HandCardRow") == null, "旧大卡预览与手牌 UI 已删除")
	_expect(main.card_art_tuner_button != null and main.get_node("%BadgePanel") != null, "卡面调整器与强化徽章预留节点保留")
	main.queue_free()
	await process_frame


func _test_collection_pages_filters_and_transactions() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	_expect(main.collection_cards.size() == 53, "Demo 收藏使用 53 张卡名与卡面均不重复的卡牌")
	var unique_card_objects: Dictionary = {}
	var unique_card_names: Dictionary = {}
	var unique_card_art: Dictionary = {}
	for card: CardData in main.collection_cards:
		unique_card_objects[card] = true
		unique_card_names[card.display_name] = true
		unique_card_art[card.art_texture.resource_path] = true
	_expect(
		unique_card_objects.size() == 53
		and unique_card_names.size() == 53
		and unique_card_art.size() == 53,
		"53 张 Demo 卡拥有独立对象、名称和卡面资源"
	)
	_expect(main.collection_card_row.get_child_count() == 12, "空位也保留：每组左右书页固定 12 个卡位")
	_expect(main.action_filter_tabs.get_child_count() == 5, "顶部五个标签分别建立五种行动方式筛选")
	for tab_index: int in main.action_filter_tabs.get_child_count():
		var action_tab := main.action_filter_tabs.get_child(tab_index) as Control
		var action_icon := action_tab.get_node("ActionIcon") as TextureRect
		var expected_icon_rect: Rect2 = main.get_action_tab_icon_rect(tab_index)
		_expect(
			action_icon.texture == main.ACTION_FILTER_TEXTURES[tab_index]
			and action_icon.position == expected_icon_rect.position
			and action_icon.size == expected_icon_rect.size
			and action_icon.stretch_mode == TextureRect.STRETCH_KEEP
			and action_icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"第 %d 个行动筛选图标使用原图尺寸与整数像素坐标" % [tab_index + 1]
		)
	var book_panel := main.get_node("%BookPanel") as Control
	_expect(
		main.left_edge_button.size.x >= 48.0
		and main.right_edge_button.size.x >= 48.0
		and main.left_edge_button.position.x <= 0.0
		and main.right_edge_button.position.x <= book_panel.size.x - main.right_edge_button.size.x,
		"左右翻页热区扩大到两侧卡牌外沿附近"
	)
	var search_filter_art := main.search_filter_art as TextureRect
	_expect(
		main.search_edit.get_parent().z_index > book_panel.z_index
		and search_filter_art.texture != null
		and search_filter_art.position == main.SEARCH_FILTER_POSITION
		and main.search_edit.get_parent().get_index() == main.search_edit.get_parent().get_parent().get_child_count() - 1
		and main.search_button.z_index > main.search_edit.z_index
		and main.search_button.position == main.SEARCH_FILTER_POSITION + main.SEARCH_ICON_HOTSPOT_REGION.position
		and main.search_button.size == main.SEARCH_ICON_HOTSPOT_REGION.size
		and main.search_edit.position == main.SEARCH_FILTER_POSITION + main.SEARCH_TEXT_HOTSPOT_REGION.position
		and main.search_edit.size * main.search_edit.scale == main.SEARCH_TEXT_HOTSPOT_REGION.size,
		"搜索交互层位于书本上方且排在末尾，放大镜与输入范围严格对齐独立搜索图"
	)
	main.search_edit.text = main.collection_cards[0].display_name
	var search_click := InputEventMouseButton.new()
	search_click.button_index = MOUSE_BUTTON_LEFT
	search_click.position = main.search_button.get_global_rect().get_center()
	search_click.pressed = true
	main.get_viewport().push_input(search_click)
	await process_frame
	search_click.pressed = false
	main.get_viewport().push_input(search_click)
	await process_frame
	_expect(
		main.search_query == main.collection_cards[0].display_name.to_lower(),
		"搜索输入即时生效，最上层放大镜仍可重复执行当前搜索"
	)
	main.clear_search()
	var first_rarity_button := main.rarity_buttons.get_child(0) as TextureButton
	var first_element_button := main.element_buttons.get_child(0) as TextureButton
	_expect(
		main.rarity_buttons.get_child_count() == 5
		and main.rarity_buttons.position == main.RARITY_FILTER_POSITION
		and main.element_buttons.position == main.ELEMENT_FILTER_POSITION
		and first_rarity_button.texture_normal is AtlasTexture
		and (first_rarity_button.texture_normal as AtlasTexture).region == main.RARITY_FILTER_REGIONS[0]
		and first_element_button.texture_normal is AtlasTexture
		and (first_element_button.texture_normal as AtlasTexture).region == main.ELEMENT_FILTER_REGIONS[0]
		and first_rarity_button.position == Vector2.ZERO
		and first_element_button.position == Vector2.ZERO
		and first_rarity_button.has_node("SelectedMark"),
		"稀有度与元素的每枚图集裁片都由自己的 TextureButton 显示并点击"
	)
	var first_type_tab := main.card_type_filter_tabs.get_child(0) as TextureButton
	_expect(
		main.card_type_filter_tabs.get_child_count() == 4
		and main.element_buttons.get_child_count() == 5
		and main.card_type_filter_tabs.position == main.CARD_TYPE_TABS_POSITION
		and first_type_tab.texture_normal is AtlasTexture
		and (first_type_tab.texture_normal as AtlasTexture).atlas == main.CARD_TYPE_TABS_TEXTURE
		and main.card_type_filter_tabs.z_index < main.regular_pages_art.z_index,
		"四个卡牌种类书签使用新素材并位于普通书页下方"
	)
	var book_art := main.get_node("%BookPanel/BookBaseArt") as TextureRect
	var regular_pages_art := main.get_node("%BookPanel/RegularPagesArt") as Control
	var recent_left_art := main.get_node("%BookPanel/RecentLeftPageArt") as TextureRect
	_expect(
		book_art.z_index < main.recent_bookmark_button.z_index
		and main.recent_bookmark_button.z_index < regular_pages_art.z_index
		and main.regular_left_page_art.texture == main.COLLECTION_LEFT_PAGE_FRONT_TEXTURE
		and main.regular_right_page_art.texture == main.COLLECTION_RIGHT_PAGE_FRONT_TEXTURE
		and main.regular_left_page_art.position == main.COLLECTION_LEFT_PAGE_POSITION
		and main.regular_right_page_art.position == main.COLLECTION_RIGHT_PAGE_POSITION
		and regular_pages_art.z_index < main.collection_card_row.z_index
		and not recent_left_art.visible,
		"普通收藏层级固定为书皮、书签、独立左右书页、收藏卡"
	)
	var persistent_effect_card_view := _find_collection_card_view(main)
	_expect(
		persistent_effect_card_view != null,
		"当前收藏页存在可验证效果面持久状态的随从卡"
	)
	if persistent_effect_card_view != null:
		var persistent_effect_card := persistent_effect_card_view.card_data
		var right_click := InputEventMouseButton.new()
		right_click.button_index = MOUSE_BUTTON_RIGHT
		right_click.pressed = true
		persistent_effect_card_view._gui_input(right_click)
		await create_timer(
			persistent_effect_card_view.effect_transition_duration + 0.05
		).timeout
		_expect(
			persistent_effect_card_view.showing_effect
			and persistent_effect_card_view.effect_text_label.visible,
			"收藏随从首次右键后持续显示效果文字"
		)
		main.turn_collection_page(1, &"direct")
		main._clear_page_turn_overlay()
		main.turn_collection_page(0, &"direct")
		main._clear_page_turn_overlay()
		var rebuilt_effect_card_view := _find_collection_card_view(
			main,
			persistent_effect_card
		)
		_expect(
			rebuilt_effect_card_view != null
			and rebuilt_effect_card_view != persistent_effect_card_view
			and rebuilt_effect_card_view.showing_effect
			and rebuilt_effect_card_view.effect_text_label.visible
			and is_equal_approx(
				rebuilt_effect_card_view.rune_row.modulate.a,
				rebuilt_effect_card_view.effect_rune_dim_alpha
			),
			"翻页销毁并重建收藏卡后仍恢复效果文字与20%符文"
		)
		if rebuilt_effect_card_view != null:
			rebuilt_effect_card_view._gui_input(right_click)
			await create_timer(
				rebuilt_effect_card_view.effect_transition_duration + 0.05
			).timeout
			main.turn_collection_page(1, &"direct")
			main._clear_page_turn_overlay()
			main.turn_collection_page(0, &"direct")
			main._clear_page_turn_overlay()
			var restored_rune_card_view := _find_collection_card_view(
				main,
				persistent_effect_card
			)
			_expect(
				restored_rune_card_view != null
				and not restored_rune_card_view.showing_effect
				and not restored_rune_card_view.effect_text_label.visible
				and is_equal_approx(restored_rune_card_view.rune_row.modulate.a, 1.0),
				"第二次右键清除持久效果面，之后翻页继续显示完整符文"
			)
	var first_tab := main.action_filter_tabs.get_child(0) as Control
	var second_tab := main.action_filter_tabs.get_child(1) as Control
	_expect(
		main.action_filter_tabs.position == main.ACTION_TABS_POSITION
		and (first_tab.get_node("ActionIcon") as TextureRect).position
		== main.get_action_tab_icon_rect(CardData.ActionType.MELEE).position
		and is_equal_approx(first_tab.position.y, main.ACTION_TAB_REST_Y)
		and is_equal_approx(second_tab.position.y, main.ACTION_TAB_REST_Y),
		"行动方式书签组与书签内图标都使用集中可调位置"
	)
	main.toggle_action_filter(CardData.ActionType.MELEE)
	_expect(
		main.is_action_tab_transitioning()
		and float(first_tab.get_meta("tab_overshoot_target_y")) < main.ACTION_TAB_SELECTED_Y,
		"行动方式书签会先越过选中位置再回弹"
	)
	await create_timer(main.TAB_OVERSHOOT_DURATION * 0.5).timeout
	_expect(
		is_equal_approx(second_tab.position.y, main.ACTION_TAB_REST_Y),
		"行动书签补间只驱动状态变化项，未选中的兄弟标签不抖动"
	)
	await create_timer(main.ACTION_TAB_TWEEN_DURATION + 0.05).timeout
	_expect(
		is_equal_approx(first_tab.position.y, main.ACTION_TAB_SELECTED_Y)
		and is_equal_approx(second_tab.position.y, main.ACTION_TAB_REST_Y),
		"行动方式书签越位后回弹到选中位置"
	)
	main.toggle_action_filter(CardData.ActionType.MELEE)
	await create_timer(main.ACTION_TAB_TWEEN_DURATION + 0.05).timeout
	_expect(
		is_equal_approx(first_type_tab.position.y, main.CARD_TYPE_TAB_REST_Y),
		"卡牌种类书签默认保持缩回位置"
	)
	main.toggle_card_type_filter(CardData.CardType.MINION)
	_expect(
		main.is_card_type_tab_transitioning()
		and float(first_type_tab.get_meta("tab_overshoot_target_y")) < main.CARD_TYPE_TAB_SELECTED_Y,
		"卡牌种类书签会先越过选中位置再回弹"
	)
	await create_timer(main.CARD_TYPE_TAB_TWEEN_DURATION + 0.05).timeout
	_expect(
		is_equal_approx(first_type_tab.position.y, main.CARD_TYPE_TAB_SELECTED_Y),
		"卡牌种类书签回弹到选中位置"
	)
	main.toggle_card_type_filter(CardData.CardType.MINION)
	await create_timer(main.CARD_TYPE_TAB_TWEEN_DURATION + 0.05).timeout
	var forward_started: bool = main.turn_collection_page(1, &"edge")
	_expect(
		forward_started,
		"普通收藏存在下一组书页时可以启动整体单页翻转"
	)
	var forward_overlay := main._page_turn_overlay as Control
	if not is_instance_valid(forward_overlay):
		main.queue_free()
		await process_frame
		return
	var forward_page := forward_overlay.get_node("MovingPage") as Control
	var forward_old_fixed := forward_overlay.get_node("StaticOldPage") as Control
	var forward_target_fixed := forward_overlay.get_node("StaticTargetPage") as Control
	var forward_target_card := (
		(forward_target_fixed.get_node("CardLayer") as Control)
		.get_child(0)
		.get_child(0) as CardView
	)
	var forward_shadow := forward_overlay.get_node("PageTurnShadow") as ColorRect
	var forward_old_number := forward_old_fixed.get_node("PageNumberLabel") as Label
	var forward_target_number := forward_target_fixed.get_node("PageNumberLabel") as Label
	var forward_moving_number := forward_page.get_node("PageNumberLabel") as Label
	_expect(
		main.is_page_turning()
		and int(forward_overlay.get_meta("direction")) == 1
		and int(forward_old_fixed.get_meta("physical_page")) == 1
		and int(forward_target_fixed.get_meta("physical_page")) == 4
		and int(forward_page.get_meta("physical_page")) == 2
		and (forward_target_fixed.get_node("CardLayer") as Control).get_child_count() == 6
		and forward_page.z_index
		> (forward_target_card.get_node("StatsRow") as Control).z_index
		and forward_shadow.z_index
		> (forward_target_card.get_node("StatsRow") as Control).z_index
		and forward_old_number.text == "1"
		and forward_target_number.text == "4"
		and forward_moving_number.text == "2"
		and forward_moving_number.get_theme_font("font") == main.PAGE_NUMBER_FONT
		and forward_moving_number.vertical_alignment
		== main.right_page_number_label.vertical_alignment
		and is_equal_approx(
			forward_moving_number.global_position.y,
			main.right_page_number_label.global_position.y
		)
		and not main.collection_card_row.visible,
		"活动页码随纸张收起，且字体、垂直对齐与正常页码完全一致"
	)
	_expect(
		not main.turn_collection_page(0, &"edge"),
		"单页动画进行中禁止再次切页"
	)
	await create_timer(main.PAGE_TURN_HALF_DURATION + 0.03).timeout
	_expect(
		forward_page.position == main.COLLECTION_LEFT_PAGE_POSITION
		and is_equal_approx(forward_page.pivot_offset.x, main.COLLECTION_PAGE_SIZE.x)
		and int(forward_page.get_meta("physical_page")) == 3
		and (forward_page.get_node("CardLayer") as Control).get_child_count() == 6
		and (forward_page.get_node("PageNumberLabel") as Label).text == "3"
		and forward_page.z_index > forward_old_fixed.z_index
		and forward_page.z_index
		> (
			(
				(forward_old_fixed.get_node("CardLayer") as Control)
				.get_child(0)
				.get_child(0) as CardView
			).get_node("StatsRow") as Control
		).z_index
		and forward_page.has_node("PageFreeEdge"),
		"活动页中点切为第 3 页，页码 3 随纸张展开并遮住第 1 页"
	)
	await create_timer(main.PAGE_TURN_HALF_DURATION + 0.10).timeout
	_expect(
		main._get_collection_card_slots().size() == 12
		and main.collection_card_row.visible
		and main.left_page_number_label.visible
		and main.right_page_number_label.visible,
		"动画结束后恢复真实第 3、4 页卡层与固定页码"
	)
	main.turn_collection_page(0, &"edge")
	var backward_overlay := main._page_turn_overlay as Control
	var backward_page := backward_overlay.get_node("MovingPage") as Control
	var backward_old_fixed := backward_overlay.get_node("StaticOldPage") as Control
	var backward_target_fixed := backward_overlay.get_node("StaticTargetPage") as Control
	_expect(
		int(backward_overlay.get_meta("direction")) == -1
		and int(backward_old_fixed.get_meta("physical_page")) == 4
		and int(backward_target_fixed.get_meta("physical_page")) == 1
		and int(backward_page.get_meta("physical_page")) == 3
		and (backward_old_fixed.get_node("PageNumberLabel") as Label).text == "4"
		and (backward_target_fixed.get_node("PageNumberLabel") as Label).text == "1"
		and (backward_page.get_node("PageNumberLabel") as Label).text == "3"
		and (backward_target_fixed.get_node("CardLayer") as Control).get_child_count() == 6,
		"向前翻页固定页码 1、4，唯一活动页码从第 3 页开始"
	)
	await create_timer(main.PAGE_TURN_HALF_DURATION + 0.03).timeout
	_expect(
		backward_page.position == main.COLLECTION_RIGHT_PAGE_POSITION
		and is_zero_approx(backward_page.pivot_offset.x)
		and int(backward_page.get_meta("physical_page")) == 2
		and (backward_page.get_node("PageNumberLabel") as Label).text == "2"
		and (backward_page.get_node("CardLayer") as Control).get_child_count() == 6
		and backward_page.z_index > backward_old_fixed.z_index
		and backward_page.has_node("PageFreeEdge"),
		"活动页中点切为第 2 页，并在第 4 页上方从书脊向右覆盖"
	)
	await create_timer(main.PAGE_TURN_HALF_DURATION + 0.05).timeout
	main.turn_collection_page(1, &"direct")
	_expect(main._get_collection_card_slots().size() == 12, "第二页保持 12 张真实收藏卡可用于翻页调试")
	_expect(
		main.get_collection_physical_page_count() == 9
		and main.get_collection_spread_count() == 5
		and main.left_page_number_label.text == "3"
		and main.right_page_number_label.text == "4",
		"53 张卡动态生成 9 个物理页（5 组展开页），左右下角显示独立物理页码"
	)
	main._clear_page_turn_overlay()
	main.turn_collection_page(0, &"direct")
	main._clear_page_turn_overlay()
	var originals: Array[CardData] = main.collection_cards.duplicate()
	main.collection_cards.clear()
	main._build_collection_cards()
	_expect(
		main.collection_card_row.get_child_count() == 12
		and main._get_collection_card_slots().is_empty()
		and main.get_collection_spread_count() == 1
		and not main.right_page_number_label.visible,
		"空收藏保留基础书面但不显示额外空白物理页"
	)
	for index: int in 600:
		main.collection_cards.append(originals[index % originals.size()])
	main._build_collection_cards()
	_expect(
		main.collection_cards.size() == 600
		and main.get_collection_physical_page_count() == 100
		and main.get_collection_spread_count() == 50,
		"收藏边界改为最多 100 个物理单页、600 张卡"
	)
	_expect(main.turn_collection_page(1, &"direct") and main.last_page_turn_method == &"direct", "直接分页入口有效")
	main._clear_page_turn_overlay()
	_expect(main.turn_collection_page(2, &"edge") and main.last_page_turn_method == &"edge", "书页边缘翻页入口有效")
	main._clear_page_turn_overlay()
	_expect(main.turn_collection_page(3, &"wheel") and main.last_page_turn_method == &"wheel", "鼠标滚轮翻页入口有效")
	main._clear_page_turn_overlay()
	main.turn_collection_page(49)
	main._clear_page_turn_overlay()
	_expect(not main.turn_collection_page(50) and main.current_collection_page == 49, "第一百个物理页之后不再循环")
	main._click_carry_data = {"kind": &"card"}
	_expect(not main.turn_collection_page(3) and main.current_collection_page == 49, "拖拽期间禁止跨页")
	main._click_carry_data = {}
	main.collection_cards.assign(originals)
	for visual_index: int in main.CARD_TYPE_FILTER_TYPES.size():
		originals[visual_index].card_type = main.CARD_TYPE_FILTER_TYPES[visual_index]
	main.current_collection_page = 4
	main.toggle_card_type_filter(CardData.CardType.SPELL)
	main.toggle_card_type_filter(CardData.CardType.EQUIPMENT)
	var type_filtered: Array[CardData] = main.get_filtered_collection_cards()
	_expect(
		main.current_collection_page == 0
		and not type_filtered.is_empty()
		and main.active_card_type_filters == [CardData.CardType.EQUIPMENT]
		and type_filtered.all(func(card: CardData) -> bool: return card.card_type == CardData.CardType.EQUIPMENT)
		and not (main.card_type_filter_tabs.get_child(1) as BaseButton).button_pressed
		and (main.card_type_filter_tabs.get_child(2) as BaseButton).button_pressed,
		"卡牌种类书签互斥选择，新选择替换旧选择并回到第一页"
	)
	main.toggle_action_filter(CardData.ActionType.MELEE)
	await create_timer(main.ACTION_TAB_TWEEN_DURATION + 0.02).timeout
	_expect(
		main.active_action_filters == [CardData.ActionType.MELEE]
		and main.active_card_type_filters == [CardData.CardType.MINION]
		and (main.card_type_filter_tabs.get_child(0) as BaseButton).button_pressed
		and not (main.card_type_filter_tabs.get_child(2) as BaseButton).button_pressed
		and (main.action_filter_tabs.get_child(CardData.ActionType.MELEE).get_node("Hotspot") as Button).button_pressed
		and is_equal_approx(
			(main.card_type_filter_tabs.get_child(0) as Control).position.y,
			main.CARD_TYPE_TAB_SELECTED_Y
		),
		"行动筛选会在同一事务中弹起随从标签并弹回非随从标签"
	)
	main.toggle_card_type_filter(CardData.CardType.SPELL)
	await create_timer(main.CARD_TYPE_TAB_TWEEN_DURATION + 0.02).timeout
	_expect(
		main.active_card_type_filters == [CardData.CardType.SPELL]
		and main.active_action_filters.is_empty()
		and not (main.card_type_filter_tabs.get_child(0) as BaseButton).button_pressed
		and (main.card_type_filter_tabs.get_child(1) as BaseButton).button_pressed
		and is_equal_approx(
			(main.card_type_filter_tabs.get_child(0) as Control).position.y,
			main.CARD_TYPE_TAB_REST_Y
		),
		"选择非随从类型会同时弹回随从和行动方式标签"
	)
	main.toggle_element_filter(CardData.ElementType.FIRE)
	_expect(
		main.active_card_type_filters == [CardData.CardType.MINION]
		and main.active_element_filters == [CardData.ElementType.FIRE]
		and not (main.card_type_filter_tabs.get_child(1) as BaseButton).button_pressed,
		"元素筛选同样自动切到随从，避免非随从类型与随从专属条件冲突"
	)
	main.toggle_card_type_filter(CardData.CardType.EQUIPMENT)
	_expect(
		main.active_card_type_filters == [CardData.CardType.EQUIPMENT]
		and main.active_action_filters.is_empty()
		and main.active_element_filters.is_empty(),
		"选择装备会一次清空行动与元素两组随从专属筛选"
	)
	main.toggle_card_type_filter(CardData.CardType.EQUIPMENT)
	main.toggle_rarity_filter(CardData.Rarity.I)
	main.toggle_rarity_filter(CardData.Rarity.III)
	var rarity_filtered: Array[CardData] = main.get_filtered_collection_cards()
	_expect(
		main.active_rarity_filters == [CardData.Rarity.III]
		and rarity_filtered.all(func(card: CardData) -> bool: return card.rarity == CardData.Rarity.III)
		and not (main.rarity_buttons.get_child(CardData.Rarity.I).get_node("SelectedMark") as Label).visible
		and (main.rarity_buttons.get_child(CardData.Rarity.III).get_node("SelectedMark") as Label).visible,
		"稀有度互斥选择，只保留新选择及其勾标记"
	)
	var selected_actions: Array[int] = []
	for card: CardData in rarity_filtered:
		if not selected_actions.has(card.action_type):
			selected_actions.append(card.action_type)
		if selected_actions.size() == 2:
			break
	for action_type: int in selected_actions:
		main.toggle_action_filter(action_type)
	var action_filtered: Array[CardData] = main.get_filtered_collection_cards()
	var final_action: int = selected_actions[-1]
	_expect(
		main.active_action_filters == [final_action]
		and action_filtered.all(func(card: CardData) -> bool: return card.action_type == final_action)
		and action_filtered.all(func(card: CardData) -> bool: return card.rarity == CardData.Rarity.III),
		"行动方式互斥选择，并与当前稀有度使用 AND"
	)
	main.toggle_action_filter(final_action)
	var element_source: CardData = null
	for candidate: CardData in rarity_filtered:
		if candidate.card_type == CardData.CardType.MINION and candidate.runes.size() >= 2:
			element_source = candidate
			break
	_expect(element_source != null, "元素筛选使用仍包含至少两个符文的随从样本")
	if element_source == null:
		return
	var selected_elements: Array[int] = []
	for rune: CardData.ElementType in element_source.runes:
		if not selected_elements.has(rune):
			selected_elements.append(rune)
		if selected_elements.size() == 2:
			break
	main.current_collection_page = 3
	for element_type: int in selected_elements:
		main.toggle_element_filter(element_type)
	var element_filtered: Array[CardData] = main.get_filtered_collection_cards()
	var element_and_valid := true
	for card: CardData in element_filtered:
		if card.rarity != CardData.Rarity.III:
			element_and_valid = false
			break
		for element_type: int in selected_elements:
			if not card.runes.has(element_type):
				element_and_valid = false
				break
	_expect(
		main.current_collection_page == 0
		and element_filtered.has(element_source)
		and element_and_valid,
		"多元素筛选要求同时包含全部所选符文，并与稀有度筛选使用 AND"
	)
	for element_type: int in selected_elements:
		main.toggle_element_filter(element_type)
	var first_element_filter_button := main.element_buttons.get_child(0) as TextureButton
	main.current_collection_page = 4
	first_element_filter_button.pressed.emit()
	_expect(
		main.active_element_filters.has(main.ELEMENT_FILTER_TYPES[0])
		and main.current_collection_page == 0,
		"元素图标点击可切换筛选并回到第一页"
	)
	first_element_filter_button.pressed.emit()
	main.search_edit.text = "不存在的即时词"
	main.search_edit.text_changed.emit(main.search_edit.text)
	_expect(main.get_filtered_collection_cards().is_empty(), "搜索文字变化会立即执行筛选")
	main.search_edit.text = originals[0].get_race_name()
	main.search_edit.text_changed.emit(main.search_edit.text)
	_expect(main.current_collection_page == 0 and main.get_filtered_collection_cards().all(func(card: CardData) -> bool: return card.get_race_name().contains(originals[0].get_race_name())), "即时搜索与稀有度筛选使用 AND")
	main.clear_search_button.pressed.emit()
	_expect(main.search_query.is_empty() and main.current_collection_page == 0, "X 清除输入与搜索筛选并回到第一页")
	main.search_edit.text = originals[0].display_name
	main.search_edit.text_submitted.emit(main.search_edit.text)
	_expect(
		main.search_query == originals[0].display_name.to_lower(),
		"搜索框按回车仍可重复执行已经即时生效的输入"
	)
	main.clear_search_button.pressed.emit()
	main.active_rarity_filters.clear()
	main._build_collection_cards()
	var sorted_cards: Array[CardData] = main.get_filtered_collection_cards()
	var rarity_descending := true
	for index: int in range(1, sorted_cards.size()):
		if sorted_cards[index - 1].rarity < sorted_cards[index].rarity:
			rarity_descending = false
			break
	_expect(rarity_descending, "收藏默认按稀有度 V→I 排列")
	var moving: CardData = sorted_cards[0]
	var source_slot: Control = main._get_collection_card_slots()[0]
	var other_slot_positions: Array[Vector2] = []
	for slot: Control in main._get_collection_card_slots():
		other_slot_positions.append(slot.position)
	main._click_carry_data = {
		"kind": &"card",
		"card_data": moving,
		"source_type": &"collection",
		"source_slot": source_slot,
	}
	main._ghost_click_carry_source()
	_expect(
		source_slot.visible
		and is_equal_approx(source_slot.modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA),
		"收藏卡拖起后原槽保留半透明卡面虚影"
	)
	var slots_stayed_put := true
	var current_slots: Array[Control] = main._get_collection_card_slots()
	for index: int in current_slots.size():
		if current_slots[index].position != other_slot_positions[index]:
			slots_stayed_put = false
			break
	_expect(slots_stayed_put, "收藏卡拖起后其余卡牌不再缩进补位")
	_expect(
		not main.collection_drop_zone.preview_card_drop(Vector2.ZERO, _collection_drag(moving)),
		"收藏区域拒绝收藏来源卡，玩家不能拖拽换序"
	)
	main._finish_click_carry(false)
	_expect(is_equal_approx(source_slot.modulate.a, 1.0), "取消拖拽后原位卡面恢复不透明")
	var board_card: CardData
	for card: CardData in sorted_cards:
		if card.rarity != CardData.Rarity.V:
			board_card = card
			break
	if board_card == null:
		board_card = sorted_cards[-1]
	var owned_count_before_deploy: int = main.collection_cards.size()
	_expect(main._transfer_card(_collection_drag(board_card), &"board", main.front_row, 0), "收藏卡可拖入我方战场")
	_expect(main.collection_cards.size() == owned_count_before_deploy, "上场卡仍保留在真实收藏所有权列表")
	var deployed_ghost_found := false
	for slot: Control in main._get_collection_card_slots():
		if (
			slot.get_child_count() > 0
			and (slot.get_child(0) as CardView).card_data == board_card
			and bool(slot.get_meta("is_deployed_ghost", false))
		):
			deployed_ghost_found = true
			break
	_expect(deployed_ghost_found, "卡牌上场后原排序卡位持续显示不可拖动虚影")
	main.active_rarity_filters.assign([CardData.Rarity.V])
	main._build_collection_cards()
	var board_slot: BoardSlot = main.front_row.get_squads()[0]
	_expect(main._transfer_card(_board_drag(main.front_row, board_slot, board_card), &"collection", null, 1), "筛选状态下场上卡仍可放回真实收藏")
	_expect(main.collection_cards.has(board_card) and not main.get_filtered_collection_cards().has(board_card), "不符合筛选的放回卡暂时隐藏但真实收藏已更新")
	main.active_rarity_filters.clear()
	main._build_collection_cards()
	var restored_entity_found := false
	for slot: Control in main._get_collection_card_slots():
		if (
			slot.get_child_count() > 0
			and (slot.get_child(0) as CardView).card_data == board_card
			and not bool(slot.get_meta("is_deployed_ghost", false))
		):
			restored_entity_found = true
			break
	_expect(restored_entity_found, "场上卡回收后原排序卡位恢复为可用实体")
	_expect(
		main.recently_returned_cards[0] == board_card,
		"成功从战场放回收藏的卡会进入最近使用列表首位"
	)
	_expect(main.is_recent_bookmark_shaking(), "卡牌从战场回收时最近使用书签会小幅抖动")
	main.recently_returned_cards.clear()
	for index: int in 13:
		main._record_recently_returned_card(originals[index])
	_expect(
		main.recently_returned_cards.size() == 12
		and main.recently_returned_cards[0] == originals[12]
		and not main.recently_returned_cards.has(originals[0]),
		"最近使用按最新优先去重，并只保留左右两页共 12 张"
	)
	main._record_recently_returned_card(originals[5])
	_expect(
		main.recently_returned_cards[0] == originals[5]
		and main.recently_returned_cards.count(originals[5]) == 1,
		"同一张卡再次放回时移到最前且不重复"
	)
	await create_timer(main.RECENT_BOOKMARK_SHAKE_STEP_DURATION * 4.0 + 0.05).timeout
	main.current_collection_page = 1
	var bookmark_click := InputEventMouseButton.new()
	bookmark_click.button_index = MOUSE_BUTTON_LEFT
	bookmark_click.position = main.recent_bookmark_button.get_global_rect().get_center()
	bookmark_click.pressed = true
	main.get_viewport().push_input(bookmark_click)
	await process_frame
	bookmark_click.pressed = false
	main.get_viewport().push_input(bookmark_click)
	await process_frame
	_expect(
		main.collection_bookmark_active
		and main.is_recent_bookmark_transitioning()
		and main.current_collection_page == 0
		and main._get_collection_card_slots().size() == 12
		and main.recent_left_page_art.visible
		and not main.regular_pages_art.visible
		and main.left_page_number_label.text == "最近 1"
		and main.right_page_number_label.text == "最近 2",
		"点击书签切到两页最近使用并显示独立页码"
	)
	await create_timer(main.ACTION_TAB_TWEEN_DURATION + 0.05).timeout
	var bookmark_rest_position: Vector2 = book_panel.position + main.RECENT_BOOKMARK_POSITION
	_expect(
		main.recent_bookmark_button.position == bookmark_rest_position + main.RECENT_BOOKMARK_SELECTED_OFFSET,
		"最近使用书签抽出后回弹到选中位置"
	)
	_expect(
		main.recent_bookmark_button.z_index > main.recent_left_page_art.z_index,
		"书签页层级固定为书皮、书签页、最上层书签"
	)
	_expect(not main.turn_collection_page(1, &"edge"), "最近使用书签页不参与普通收藏分页")
	main.toggle_recent_bookmark()
	await create_timer(main.ACTION_TAB_TWEEN_DURATION + 0.05).timeout
	_expect(
		not main.collection_bookmark_active
		and main.current_collection_page == 1
		and main.regular_pages_art.visible
		and main.recent_bookmark_button.position == bookmark_rest_position
		and main.recent_bookmark_button.z_index < main.regular_pages_art.z_index,
		"再次点击书签返回此前普通收藏页并恢复普通层级"
	)
	main.queue_free()
	await process_frame


func _collection_drag(card: CardData) -> Dictionary:
	return {"kind": &"card", "card_data": card, "source_type": &"collection"}


func _find_collection_card_view(
	main,
	card_data: CardData = null
) -> CardView:
	for slot: Control in main._get_collection_card_slots():
		var card_view := slot.get_child(0) as CardView
		if card_view == null or card_view.card_data == null:
			continue
		if card_data != null and card_view.card_data != card_data:
			continue
		if card_view.card_data.card_type == CardData.CardType.MINION:
			return card_view
	return null


func _board_drag(row: BattlefieldRow, slot: BoardSlot, card: CardData) -> Dictionary:
	return {"kind": &"card", "card_data": card, "source_type": &"board", "source_row": row, "source_slot": slot}


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failure_count += 1
	push_error("FAIL: %s" % message)
