extends SceneTree

## 阶段 4 的无窗口集成回归脚本。
##
## 每个用例都会实例化真实 Main 场景，模拟输入或直接调用公开事务入口，
## 再检查像素布局、收藏顺序、拖拽视觉和阶段锁定。失败数最终作为进程退出码。

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const CARD_ART_TUNER_SCENE: PackedScene = preload(
	"res://scenes/tools/CardArtTuner.tscn"
)
const CARD_SNAPSHOT_VISUAL_SCRIPT: Script = preload(
	"res://scripts/ui/card_snapshot_visual.gd"
)

var _failure_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_test_virtual_canvas_settings()
	await _test_balatro_drag_preview_feel()
	await _test_native_collection_drag_callbacks()
	await _test_click_carry_and_drop_animation()
	await _test_card_art_tuner_preview()
	await _test_collection_placement_and_preview_positions()
	await _test_board_move_return_and_cancel()
	await _test_full_row_rules_and_width()

	if _failure_count == 0:
		print("Stage 4 integration checks passed.")
	else:
		push_error("Stage 4 integration checks failed: %d" % _failure_count)
	quit(_failure_count)


# --- 画布、卡面像素与调节工具 ---
func _test_virtual_canvas_settings() -> void:
	_expect(
		ProjectSettings.get_setting("display/window/size/viewport_width") == 1280
		and ProjectSettings.get_setting("display/window/size/viewport_height") == 720,
		"项目使用 1280×720 固定逻辑画布"
	)
	_expect(
		ProjectSettings.get_setting("display/window/size/mode")
		== DisplayServer.WINDOW_MODE_WINDOWED,
		"项目默认以固定 1080p 窗口启动"
	)
	_expect(
		ProjectSettings.get_setting("display/window/size/window_width_override") == 1920
		and ProjectSettings.get_setting("display/window/size/window_height_override") == 1080
		and not ProjectSettings.get_setting("display/window/size/resizable"),
		"默认窗口为不可拖动缩放的 1920×1080"
	)
	_expect(
		ProjectSettings.get_setting("display/window/stretch/mode") == "disabled"
		and ProjectSettings.get_setting("display/window/stretch/scale_mode") == "fractional",
		"逻辑画布保持 16:9，由 1280×720 显示壳直接适配实际窗口客户区"
	)
	_expect(
		ProjectSettings.get_setting(
			"rendering/textures/canvas_textures/default_texture_filter"
		) == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR,
		"项目默认开启线性像素平滑，分数缩放时混合相邻四个纹理像素"
	)


func _test_card_pixel_layout() -> void:
	var main: Variant = await _create_main()
	var card_view := main.get_node("%SelectedCardView") as CardView
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var row_display_area := front_row.get_node("%RowDisplayArea") as Control
	_expect(
		front_row.size.x == 832.0
		and row_display_area.size.x == 801.0
		and row_display_area.size.x / front_row.size.x > 0.96,
		"1280px 画布中，832px 战场行紧密容纳 801px 满排"
	)
	_expect(card_view.card_size == Vector2(99, 136), "裸卡尺寸保持 99×136px")
	_expect(
		card_view.art_panel.position == Vector2(10, 5)
		and card_view.art_panel.size == Vector2(79, 95),
		"背景和人物只显示在卡框内部 (10,5,79,95)"
	)
	_expect(
		card_view.health_label.position
		== CardView.get_health_value_position(card_view.card_data.max_health)
		and card_view.health_label.size == card_view.health_label.get_rendered_size(),
		"生命数字按当前数值选择已确认的绝对坐标和真实字形宽度"
	)
	_expect(
		card_view.health_icon.position == Vector2(85, 88)
		and card_view.health_icon.size == Vector2(20, 17)
		and card_view.health_icon.texture.get_size() == Vector2(20, 17),
		"20×17px 新版生命图标位于 (85,88)"
	)
	_expect(
		card_view.armor_label.position
		== CardView.get_armor_value_position(card_view.card_data.armor)
		and card_view.armor_label.size == card_view.armor_label.get_rendered_size(),
		"护甲数字按当前数值选择已确认的绝对坐标和真实字形宽度"
	)
	_expect(
		card_view.armor_icon.position == Vector2(88, 71)
		and card_view.armor_icon.size == Vector2(14, 16)
		and card_view.armor_icon.texture.get_size() == Vector2(14, 16),
		"14×16px 新版护甲图标位于 (88,71)"
	)
	_expect(
		card_view.cooldown_icon.position == card_view.cooldown_icon_position
		and card_view.cooldown_icon.position == Vector2(-1, 22)
		and card_view.cooldown_icon.size == card_view.cooldown_icon_size
		and card_view.cooldown_icon.texture.get_size() == Vector2(12, 16)
		and card_view.cooldown_label.position == Vector2(-3, 24)
		and card_view.cooldown_label.size
		== card_view.cooldown_label.get_rendered_size(),
		"12×16px 沙漏与冷却秒数固定放在卡面左上区域"
	)
	_expect(
		card_view.value_label.number_style == RuneNumberDisplay.NumberStyle.LARGE
		and card_view.health_label.number_style == RuneNumberDisplay.NumberStyle.LARGE
		and card_view.armor_label.number_style == RuneNumberDisplay.NumberStyle.MEDIUM
		and card_view.cooldown_label.number_style
		== RuneNumberDisplay.NumberStyle.COOLDOWN
		and card_view.cooldown_label.text == CardView.format_cooldown_seconds(
			card_view.card_data.cooldown_seconds
		),
		"行动/生命/护甲/冷却分别使用大/大/中/混合卢恩图片数字"
	)
	_expect(
		not card_view.priority_label.visible,
		"常驻卡面不再额外挤入受击优先级文字"
	)

	var layout_cases: Array[Dictionary] = [
		{
			"type": CardData.ActionType.MAGIC,
			"position": Vector2(-7, -4),
			"size": Vector2(25, 25),
		},
		{
			"type": CardData.ActionType.DEFENSE,
			"position": Vector2(-6, -4),
			"size": Vector2(24, 25),
		},
		{
			"type": CardData.ActionType.RANGED,
			"position": Vector2(-4, -4),
			"size": Vector2(25, 25),
		},
		{
			"type": CardData.ActionType.MELEE,
			"position": Vector2(-4, -4),
			"size": Vector2(25, 25),
		},
		{
			"type": CardData.ActionType.HEAL,
			"position": Vector2(-8, -4),
			"size": Vector2(25, 28),
		},
	]
	var layout_card := (
		(main.collection_cards[0] as CardData).duplicate() as CardData
	)
	for layout_case: Dictionary in layout_cases:
		layout_card.action_type = int(layout_case["type"])
		card_view.set_card_data(layout_card)
		_expect(
			card_view.action_icon.position == layout_case["position"]
			and card_view.action_icon.size == layout_case["size"]
			and card_view.action_icon.texture.get_size()
			== layout_case["size"],
			"%s行动区域为 (%s,%s)"
			% [
				layout_card.get_action_type_name(),
				layout_case["position"],
				layout_case["size"],
			]
		)

	await process_frame
	_expect(card_view.rune_row.get_child_count() == 3, "卡牌始终保留三个固定符文位")
	var expected_rune_centers: Array[Vector2] = [
		Vector2(19.5, 119.5),
		Vector2(49.5, 119.5),
		Vector2(79.5, 119.5),
	]
	for slot_index: int in 3:
		var rune_slot := card_view.rune_row.get_child(slot_index) as Control
		var rune_icon := rune_slot.get_child(0) as TextureRect
		var center_in_card := (
			card_view.bottom_panel.position
			+ card_view.rune_row.position
			+ rune_slot.position
			+ rune_slot.size * 0.5
		)
		_expect(
			center_in_card == expected_rune_centers[slot_index],
			"第 %d 枚符文对准底部圆形空腔中心 %s"
			% [slot_index + 1, expected_rune_centers[slot_index]]
		)
		_expect(
			rune_slot.size == Vector2(23, 23),
			"第 %d 个符文空腔布局槽为 23×23px" % [slot_index + 1]
		)
		_expect(
			rune_icon.size == Vector2(23, 23)
			and rune_icon.texture.get_size() == Vector2(23, 23),
			"第 %d 枚符文使用原生 23×23px 透明纹理"
			% [slot_index + 1]
		)

	var race_sizes := {
		"human": Vector2(11, 11),
		"elf": Vector2(13, 12),
		"dwarf": Vector2(13, 12),
		"construct": Vector2(13, 14),
		"elemental": Vector2(11, 14),
		"undead": Vector2(11, 12),
		"demon": Vector2(11, 12),
		"beast": Vector2(11, 10),
		"plant": Vector2(9, 9),
	}
	var rarity_names: Array[String] = ["i", "ii", "iii", "iv", "v"]
	for race_name: String in race_sizes:
		var all_rarities_match := true
		for rarity_name: String in rarity_names:
			var texture := load(
				"res://assets/races/%s/race_%s_%s.png"
				% [race_name, race_name, rarity_name]
			) as Texture2D
			if (
				texture == null
				or texture.get_size() != race_sizes[race_name]
			):
				all_rarities_match = false
				break
		_expect(
			all_rarities_match,
			"%s的 I～V 稀有度图标均保持原生尺寸 %s"
			% [race_name, race_sizes[race_name]]
		)

	var all_test_cards_have_visual_data := true
	for test_card: CardData in main.collection_cards:
		if (
			test_card.art_texture == null
			or test_card.race_type < CardData.RaceType.HUMAN
			or test_card.race_type > CardData.RaceType.PLANT
			or test_card.rarity < CardData.Rarity.I
			or test_card.rarity > CardData.Rarity.V
		):
			all_test_cards_have_visual_data = false
			break
	_expect(
		all_test_cards_have_visual_data,
		"所有测试卡均配置卡面、种族和 I～V 稀有度"
	)
	_expect(
		card_view.art_texture.visible
		and card_view.art_texture.texture == layout_card.art_texture
		and not card_view.art_label.visible,
		"测试卡面人物纹理已正确载入"
	)
	_expect(
		card_view.art_panel.clip_contents
		and card_view.art_texture.stretch_mode
		== TextureRect.STRETCH_SCALE,
		"人物保持 1×逻辑尺寸并由 79×95px 卡框内窗裁切"
	)
	var art_texture_size := layout_card.art_texture.get_size()
	var expected_centered_art_position := Vector2(
		floori((card_view.art_area_size.x - art_texture_size.x) * 0.5),
		floori((card_view.art_area_size.y - art_texture_size.y) * 0.5)
	)
	layout_card.art_offset = Vector2i(3, 7)
	card_view.set_card_data(layout_card)
	_expect(
		card_view.art_texture.position
		== expected_centered_art_position + Vector2(3, 7),
		"单张卡可通过 art_offset 在裁切窗口内调整人物取景"
	)
	_expect(
		card_view.art_background.visible
		and card_view.art_background.texture
		== CardView.DEFAULT_ART_BACKGROUND_TEXTURE
		and card_view.art_background.texture.get_size() == Vector2(97, 102),
		"新卡面背景以原生 97×102px 垫在透明人物下方"
	)
	var all_card_frames_match := true
	for rarity_key: String in ["i", "ii", "iii", "iv", "v"]:
		var frame_texture := load(
			"res://assets/card_frames/card_frame_%s.png" % rarity_key
		) as Texture2D
		if frame_texture == null or frame_texture.get_size() != Vector2(99, 136):
			all_card_frames_match = false
			break
	_expect(
		all_card_frames_match,
		"I～V 五张卡牌框均保持原生 99×136px"
	)
	_expect(
		card_view.card_frame.visible
		and card_view.card_frame.position == Vector2.ZERO
		and card_view.card_frame.size == Vector2(99, 136)
		and card_view.card_frame.texture.get_size() == Vector2(99, 136),
		"当前稀有度卡牌框完整覆盖 99×136px 裸卡"
	)
	_expect(
		card_view.card_name_frame.visible
		and card_view.card_name_frame.position == Vector2(0, 4)
		and card_view.card_name_frame.size == Vector2(83, 11)
		and card_view.card_name_frame.texture.get_size() == Vector2(83, 11),
		"卡牌名框以原生 83×11px 紧贴左边并距离顶端 4px"
	)
	var longest_name_card := layout_card.duplicate() as CardData
	longest_name_card.display_name = "影弦游击手"
	card_view.set_card_data(longest_name_card)
	var fitted_title_size := card_view.name_label.get_theme_font_size("font_size")
	var fitted_title_font := card_view.name_label.get_theme_font("font")
	var fitted_text_size := fitted_title_font.get_string_size(
		longest_name_card.display_name,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1.0,
		fitted_title_size
	)
	_expect(
		card_view.name_clip.position == Vector2(21, 4)
		and card_view.name_clip.size == Vector2(61, 10)
		and card_view.name_clip.clip_contents
		and card_view.name_label.size.x == 61.0
		and card_view.name_label.horizontal_alignment
		== HORIZONTAL_ALIGNMENT_CENTER
		and card_view.name_label.vertical_alignment
		== VERTICAL_ALIGNMENT_CENTER
		and card_view.name_label.clip_text
		and fitted_title_size >= card_view.title_font_min_size
		and fitted_title_size <= card_view.title_font_size
		and fitted_text_size.x <= card_view.name_clip.size.x,
		"卡牌名字在名字框内居中，五字名称会按可用宽度自动缩小"
	)
	card_view.set_card_data(layout_card)
	_expect(
		card_view.art_panel.z_index < card_view.card_frame.z_index
		and card_view.card_frame.z_index < card_view.card_name_frame.z_index
		and card_view.card_name_frame.z_index < card_view.top_row.z_index
		and card_view.card_frame.z_index < card_view.race_icon.z_index
		and card_view.card_frame.z_index < card_view.bottom_panel.z_index,
		"显示层级保持背景与人物 → 卡牌框 → 卡牌名框 → 文字与图标"
	)
	var expected_race_key := layout_card.get_race_asset_key()
	var expected_race_texture := load(
		"res://assets/races/%s/race_%s_%s.png"
		% [
			expected_race_key,
			expected_race_key,
			layout_card.get_rarity_asset_key(),
		]
	) as Texture2D
	_expect(
		card_view.race_icon.visible
		and card_view.race_icon.texture == expected_race_texture,
		"种族图标颜色由测试卡的种族和稀有度共同决定"
	)
	_expect(
		card_view.race_icon.position
		+ Vector2(
			floori(card_view.race_icon.size.x * 0.5),
			floori(card_view.race_icon.size.y * 0.5)
		)
		== Vector2(49, 100),
		"不同尺寸的种族图标都以卡牌像素坐标 (49,100) 对齐"
	)

	var collection_card := _collection_card_view(main, 0)
	var collection_slot := collection_card.get_parent() as Control
	var safe_slot_rect := collection_slot.get_global_rect().grow(0.1)
	var card_transform := collection_card.get_global_transform_with_canvas()
	var visual_is_inside_slot := true
	for corner: Vector2 in [
		Vector2(-8, -4),
		Vector2(collection_card.card_size.x + 5, -4),
		Vector2(collection_card.card_size.x + 5, collection_card.card_size.y),
		Vector2(-8, collection_card.card_size.y),
	]:
		if not safe_slot_rect.has_point(card_transform * corner):
			visual_is_inside_slot = false
			break
	_expect(
		visual_is_inside_slot,
		"收藏槽为抬起阴影和越界图标预留安全边，不会裁掉卡牌内容"
	)
	var collection_viewport := main.get_node(
		"WorldContent/CollectionSection/BookPanel/CollectionViewport"
	) as Control
	var collection_viewport_rect := collection_viewport.get_global_rect().grow(0.1)
	var collection_slot_rect := collection_slot.get_global_rect()
	_expect(
		collection_slot_rect.position.y >= collection_viewport_rect.position.y
		and collection_slot_rect.end.y <= collection_viewport_rect.end.y,
		"收藏滚动区高度包含抬起安全边"
	)
	collection_card._reset_interaction_visual()

	await _dispose_main(main)


func _test_card_art_tuner_preview() -> void:
	var tuner := CARD_ART_TUNER_SCENE.instantiate()
	root.add_child(tuner)
	await process_frame
	await process_frame
	var source_card := tuner.get("card_data") as CardData
	var preview_card := tuner.get_node("%PreviewCard") as CardView
	var preview_viewport := tuner.get_node("%PreviewViewport") as SubViewport
	var preview_display := tuner.get_node("%PreviewDisplay") as TextureRect
	var workspace := tuner.get_node("CenterContainer/Workspace") as Control
	_expect(
		workspace.custom_minimum_size == Vector2(1280, 720)
		and preview_viewport.size == Vector2i(123, 149)
		and preview_card.scale == Vector2.ONE
		and preview_card.position
		== preview_card.get_max_visual_capture_padding_top_left()
		and preview_display.scale == Vector2(4, 4)
		and preview_viewport.canvas_item_default_texture_filter
		== Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		and preview_display.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
		and preview_card.pivot_offset == Vector2.ZERO,
		"卡面调整器用最近邻把完整 SubViewport 精确放大 4 倍，保持像素边缘清晰"
	)
	var preview_bounds := Rect2(Vector2.ZERO, Vector2(preview_viewport.size))
	var preview_action_data := source_card.duplicate() as CardData
	var all_action_visuals_inside := true
	for action_type: CardData.ActionType in [
		CardData.ActionType.MELEE,
		CardData.ActionType.RANGED,
		CardData.ActionType.MAGIC,
		CardData.ActionType.HEAL,
		CardData.ActionType.DEFENSE,
	]:
		preview_action_data.action_type = action_type
		preview_card.set_card_data(preview_action_data)
		var icon_rect := Rect2(
			preview_card.position + preview_card.action_icon.position,
			preview_card.action_icon.size
		)
		var value_rect := Rect2(
			preview_card.position + preview_card.value_label.position,
			preview_card.value_label.size
		)
		if not preview_bounds.encloses(icon_rect) or not preview_bounds.encloses(value_rect):
			all_action_visuals_inside = false
			break
	_expect(
		all_action_visuals_inside,
		"近战、远程、法术、治疗、防御的行动图标与行动数字都不会被 4 倍预览裁切"
	)
	var healing_data := source_card.duplicate() as CardData
	healing_data.action_type = CardData.ActionType.HEAL
	var healing_card := (
		load("res://scenes/ui/CardView.tscn") as PackedScene
	).instantiate() as CardView
	healing_card.set_card_data(healing_data)
	var healing_snapshot := CARD_SNAPSHOT_VISUAL_SCRIPT.new() as CardSnapshotVisual
	root.add_child(healing_snapshot)
	healing_snapshot.configure(healing_card, healing_card.card_size)
	await process_frame
	_expect(
		healing_snapshot.get_card_origin_in_texture()
		== healing_card.get_visual_capture_padding_top_left()
		and healing_snapshot.get_card_origin_in_texture() == Vector2(9, 4),
		"拖拽快照与调整器共用新版行动数字和状态数值的完整越界边界"
	)
	healing_snapshot.queue_free()
	await process_frame
	var preview_material := preview_display.material as ShaderMaterial
	var preview_shader_code := preview_material.shader.code
	var use_3d_check := tuner.get_node("%Use3DCheck") as CheckButton
	var use_flash_check := tuner.get_node("%UseFlashCheck") as CheckButton
	var flash_type_selector := tuner.get_node("%FlashTypeSelector") as OptionButton
	_expect(
		preview_material != null
		and preview_material.shader.resource_path
		== "res://shaders/card_preview_3d.gdshader"
		and bool(preview_material.get_shader_parameter("use_3d"))
		== use_3d_check.button_pressed
		and bool(preview_material.get_shader_parameter("use_flash"))
		== use_flash_check.button_pressed
		and int(preview_material.get_shader_parameter("flash_type"))
		== flash_type_selector.get_selected_id()
		and not bool(preview_material.get_shader_parameter("use_normal_texture"))
		and is_zero_approx(float(preview_material.get_shader_parameter("inset")))
		and is_equal_approx(float(preview_material.get_shader_parameter("stripe_spacing")), 7.0)
		and is_equal_approx(float(preview_material.get_shader_parameter("stripe_width")), 2.4)
		and is_equal_approx(float(preview_material.get_shader_parameter("flash_intensity")), 0.32)
		and not preview_shader_code.contains("character_mask")
		and preview_shader_code.contains("sample_uv.x * 0.85 + sample_uv.y * 0.55"),
		"4 倍预览整卡共用 Shader，3D 开关不缩小卡牌，并使用更少、更宽、更弱的光带"
	)
	var original_offset: Vector2i = source_card.art_offset
	tuner.set("preview_art_offset", Vector2i(4, 9))
	await process_frame
	_expect(
		preview_card.card_data != source_card
		and preview_card.card_data.art_offset == Vector2i(4, 9),
		"卡面调整器修改检查器数值时会实时刷新资源副本预览"
	)
	_expect(
		source_card.art_offset == original_offset,
		"实时预览不会在点击保存前修改真实卡牌资源"
	)
	var card_type_selector := tuner.get_node("%CardTypeSelector") as OptionButton
	var card_selector := tuner.get_node("%CardSelector") as ItemList
	_expect(
		card_type_selector.item_count == 3
		and card_selector.item_count == 24,
		"运行时调整器把 53 张卡分为三类，并用固定高度滚动列表显示随从"
	)
	var nudge_right_button := tuner.get_node("%NudgeRightButton") as Button
	nudge_right_button.emit_signal("pressed")
	await process_frame
	_expect(
		tuner.get("preview_art_offset") == Vector2i(5, 9)
		and preview_card.card_data.art_offset == Vector2i(5, 9),
		"方向按钮会以 1px 为单位实时调整人物取景"
	)
	var keyboard_up := InputEventKey.new()
	keyboard_up.keycode = KEY_UP
	keyboard_up.pressed = true
	tuner._input(keyboard_up)
	await process_frame
	_expect(
		tuner.get("preview_art_offset") == Vector2i(5, 8)
		and preview_card.card_data.art_offset == Vector2i(5, 8),
		"键盘上下左右键与 1px 方向按钮共用同一人物微调入口"
	)
	use_3d_check.button_pressed = false
	_expect(
		not bool(preview_material.get_shader_parameter("use_3d")),
		"卡面调整器可即时关闭 3D 透视并保留普通像素预览"
	)
	_expect(
		tuner.get_node_or_null("%BackButton") != null,
		"卡面调整器提供返回主界面的入口"
	)
	tuner.queue_free()
	await process_frame


# --- 拖拽输入、点击携带和收藏让位 ---
func _test_balatro_drag_preview_feel() -> void:
	var main: Variant = await _create_main()
	var collection_card := _collection_card_view(main, 0)
	var resting_scale := collection_card.scale
	var resting_position := collection_card.position
	collection_card._on_mouse_entered()
	await create_timer(0.04).timeout
	var interaction_shadow := collection_card.get_node(
		"InteractionShadow"
	) as Panel
	var hover_punch_tween := collection_card.get("_hover_punch_tween") as Tween
	_expect(
		interaction_shadow.visible
		and hover_punch_tween != null
		and hover_punch_tween.is_valid(),
		"收藏鼠标进入时显示阴影并播放一次短促方向轻晃"
	)
	_expect(
		collection_card._get_hover_punch_direction(10.0) < 0.0
		and collection_card._get_hover_punch_direction(90.0) > 0.0,
		"鼠标从卡牌左/右半边进入时分别向同方向倾斜"
	)
	await create_timer(CardView.HOVER_PUNCH_DURATION + 0.05).timeout
	_expect(
		collection_card.scale.distance_to(resting_scale) < 0.01,
		"悬停轻晃不恢复放大效果，卡牌始终保持原始比例"
	)
	_expect(absf(collection_card.rotation_degrees) < 0.1, "收藏单次轻晃结束后自动回正")
	_expect(
		collection_card.z_index == CardView.CARD_LAYER_Z_STEP,
		"收藏悬停会按整卡层级提升，避免与邻卡内部图层交错"
	)
	_expect(
		collection_card.position.is_equal_approx(
			resting_position + Vector2(0.0, -CardView.COLLECTION_HOVER_LIFT_OFFSET)
		),
		"收藏悬停时会像抽牌一样向上移出"
	)
	collection_card._on_mouse_exited()
	await create_timer(0.12).timeout
	_expect(
		collection_card.scale.distance_to(resting_scale) < 0.01,
		"鼠标离开后卡牌恢复原有显示比例"
	)
	_expect(
		collection_card.position.is_equal_approx(resting_position),
		"鼠标离开后收藏会回到原位"
	)
	_expect(not interaction_shadow.visible, "鼠标离开后悬停阴影隐藏")

	var grab_local_position := collection_card.size * Vector2(0.75, 0.25)
	var drag_data := collection_card._build_drag_data(grab_local_position)
	var drag_visual := CardView.create_drag_visual(drag_data)
	root.add_child(drag_visual)
	drag_visual.global_position = Vector2(640.0, 420.0)
	await process_frame
	drag_visual.set_process(false)
	drag_visual._process(1.0 / 60.0)

	var preview_card := drag_visual.get_card_visual() as TextureRect
	var snapshot_card := drag_visual.get_source_card_view() as CardView
	var snapshot_visual: Variant = drag_visual.get_node(
		"CardSnapshotVisual"
	)
	var snapshot_viewport := snapshot_visual.get_node(
		"CardSnapshotViewport"
	) as SubViewport
	_expect(
		preview_card != null and snapshot_card != null,
		"拖拽预览会把独立 CardView 合成为一张完整纹理"
	)
	_expect(
		drag_visual.get_child_count() == 2
		and drag_visual.get_children().any(
			func(child: Node) -> bool: return child is Panel
		),
		"拖拽卡牌下方会创建轻量阴影"
	)
	_expect(
		snapshot_viewport.size
		== Vector2i(
			snapshot_visual.get_capture_size()
			* CARD_SNAPSHOT_VISUAL_SCRIPT.SUPERSAMPLE_FACTOR
		)
		and snapshot_card.scale
		== Vector2.ONE * CARD_SNAPSHOT_VISUAL_SCRIPT.SUPERSAMPLE_FACTOR
		and preview_card.texture_filter
		== CanvasItem.TEXTURE_FILTER_LINEAR,
		"活动卡先按整数倍率渲染，再作为完整纹理执行平滑变换"
	)
	_expect(
		snapshot_card.pivot_offset == Vector2.ZERO,
		"拖拽快照使用左上角缩放支点，不会把卡面推出捕获区域（实际：%s）"
		% snapshot_card.pivot_offset
	)
	var source_scale: Vector2 = drag_data["preview_scale"]
	_expect(
		preview_card.scale.distance_to(source_scale) < 0.01,
		"鼠标拖动中的实体卡保持原始尺寸，不再放大像素"
	)
	var transformed_grab_position: Vector2 = (
		preview_card.get_global_transform_with_canvas()
		* (
			grab_local_position
			+ snapshot_visual.get_card_origin_in_texture()
		)
	)
	_expect(
		transformed_grab_position.distance_to(drag_visual.global_position) < 1.0,
		"拖拽实体仍以实际鼠标按下位置为支点"
	)

	drag_visual.global_position += Vector2(80.0, 0.0)
	drag_visual._process(1.0 / 60.0)
	transformed_grab_position = (
		preview_card.get_global_transform_with_canvas()
		* (
			grab_local_position
			+ snapshot_visual.get_card_origin_in_texture()
		)
	)
	var moving_distance: float = transformed_grab_position.distance_to(
		drag_visual.global_position
	)
	_expect(moving_distance > 1.0, "快速移动时卡牌视觉会轻微滞后")
	var preview_shadow := drag_visual.get("_shadow") as Panel
	_expect(
		preview_card.rotation_degrees > 0.1
		and is_instance_valid(preview_shadow)
		and is_equal_approx(
			preview_shadow.rotation_degrees,
			preview_card.rotation_degrees
		),
		"活动卡向右移动时顺时针倾斜，显式阴影使用同一角度"
	)

	for frame_index: int in 20:
		drag_visual._process(1.0 / 60.0)
	transformed_grab_position = (
		preview_card.get_global_transform_with_canvas()
		* (
			grab_local_position
			+ snapshot_visual.get_card_origin_in_texture()
		)
	)
	_expect(
		transformed_grab_position.distance_to(drag_visual.global_position)
		< moving_distance,
		"停止移动后卡牌会平滑追上鼠标"
	)
	_expect(absf(preview_card.rotation_degrees) < 0.1, "停止移动后活动卡平滑回正")

	drag_visual.global_position += Vector2(-80.0, 0.0)
	drag_visual._process(1.0 / 60.0)
	_expect(
		preview_card.rotation_degrees < -0.1
		and is_equal_approx(
			preview_shadow.rotation_degrees,
			preview_card.rotation_degrees
		),
		"活动卡向左移动时逆时针倾斜，显式阴影继续同步"
	)
	for frame_index: int in 20:
		drag_visual._process(1.0 / 60.0)
	_expect(absf(preview_card.rotation_degrees) < 0.1, "向左移动停止后活动卡同样平滑回正")

	drag_visual.queue_free()
	await _dispose_main(main)


func _test_native_collection_drag_callbacks() -> void:
	var main: Variant = await _create_main()
	var collection_card := _collection_card_view(main, 0)
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var back_row := main.get_node("%BackRow") as BattlefieldRow
	var collection_card_rect := collection_card.get_global_rect()
	var source_position := (
		collection_card_rect.position
		+ collection_card_rect.size * Vector2(0.75, 0.25)
	)
	var target_position := front_row.row_display_area.get_global_rect().get_center()
	var initial_collection_count: int = main.collection_cards.size()
	var original_collection_slot := collection_card.get_parent() as Control
	var second_collection_card := _collection_card_view(main, 1)

	await _send_mouse_motion(source_position, Vector2.ZERO, 0)
	await _send_left_button(source_position, true)
	await _send_mouse_motion(
		source_position + Vector2(32.0, -16.0),
		Vector2(32.0, -16.0),
		MOUSE_BUTTON_MASK_LEFT
	)
	_expect(
		original_collection_slot.visible
		and is_equal_approx(
			original_collection_slot.modulate.a,
			CardView.COLLECTION_DRAG_GHOST_ALPHA
		),
		"拖起收藏后原位置保留半透明卡面虚影"
	)
	_expect(not second_collection_card.is_layout_animating(), "拖走收藏时其余收藏不再补位")
	var active_drag_data := root.gui_get_drag_data() as Dictionary
	_expect(
		active_drag_data.get("drag_visual") is CardDragPreview,
		"原生拖拽与点击携带共用教程式拖拽视觉"
	)
	var grab_local_position: Vector2 = active_drag_data["grab_local_position"]
	var preview_scale: Vector2 = active_drag_data["preview_scale"]
	var expected_preview_offset := grab_local_position * preview_scale
	var actual_preview_offset: Vector2 = active_drag_data["preview_offset"]
	_expect(
		actual_preview_offset.distance_to(expected_preview_offset) < 1.0,
		"拖拽预览保留旋转卡牌上的实际局部按下位置，不再固定吸附左上角"
	)
	root.gui_cancel_drag()
	await process_frame
	await process_frame
	_expect(
		original_collection_slot.visible
		and is_equal_approx(original_collection_slot.modulate.a, 1.0),
		"取消收藏拖动后原位置恢复实体"
	)
	_expect(not second_collection_card.is_layout_animating(), "取消拖动时其余收藏始终保持原位")
	_expect(collection_card.is_layout_animating(), "取消原生拖动时卡牌从鼠标位置飞回收藏")
	_expect(
		collection_card.z_index == CardDragPreview.DRAG_PREVIEW_Z_INDEX,
		"取消原生拖动的回位卡进入统一拖拽层，不被筛选按钮遮挡"
	)
	var collection_viewport := main.get_node("%CollectionViewport") as Control
	_expect(
		not collection_viewport.clip_contents,
		"取消原生拖动不会改变收藏视口的长期非裁切状态"
	)
	_expect(main.collection_cards.size() == initial_collection_count, "取消收藏拖动不修改真实数据")
	await create_timer(CardView.LAYOUT_TWEEN_DURATION + 0.05).timeout
	_expect(collection_card.z_index == 0, "原生拖动回位完成后恢复普通收藏层级")

	collection_card_rect = collection_card.get_global_rect()
	source_position = (
		collection_card_rect.position
		+ collection_card_rect.size * Vector2(0.75, 0.25)
	)
	await _send_mouse_motion(source_position, Vector2.ZERO, 0)
	await _send_left_button(source_position, true)
	await _send_mouse_motion(
		source_position + Vector2(32.0, -16.0),
		Vector2(32.0, -16.0),
		MOUSE_BUTTON_MASK_LEFT
	)
	_expect(
		is_equal_approx(
			original_collection_slot.modulate.a,
			CardView.COLLECTION_DRAG_GHOST_ALPHA
		),
		"再次拖动时收藏原位置继续显示虚影"
	)
	await _send_mouse_motion(
		target_position,
		target_position - source_position,
		MOUSE_BUTTON_MASK_LEFT
	)
	await process_frame
	_expect(root.gui_is_dragging(), "原生 Control 拖拽已由鼠标移动启动")
	_expect(_preview_slot(front_row) != null, "原生 _can_drop_data 显示棋盘虚影")

	await _send_left_button(target_position, false)
	await process_frame
	_expect(front_row.get_card_count() == 1, "原生 _drop_data 把卡牌提交到前排")
	_expect(main.collection_cards.size() == initial_collection_count, "原生 drop 成功后仍保留收藏所有权")
	await create_timer(0.2).timeout

	var front_slot := _real_slots(front_row)[0]
	source_position = front_slot.card_view.get_global_rect().get_center()
	target_position = back_row.row_display_area.get_global_rect().get_center()
	await _send_mouse_motion(source_position, Vector2.ZERO, 0)
	await _send_left_button(source_position, true)
	await _send_mouse_motion(
		source_position + Vector2(24.0, 16.0),
		Vector2(24.0, 16.0),
		MOUSE_BUTTON_MASK_LEFT
	)
	_expect(not front_slot.visible, "原生场上拖动会临时隐藏来源卡并收拢")
	await _send_mouse_motion(
		target_position,
		target_position - source_position,
		MOUSE_BUTTON_MASK_LEFT
	)
	await process_frame
	_expect(_preview_slot(back_row) != null, "原生跨排拖动显示目标排虚影")
	await _send_left_button(target_position, false)
	await process_frame
	_expect(front_row.get_card_count() == 0, "原生跨排 drop 从来源排移除")
	_expect(back_row.get_card_count() == 1, "原生跨排 drop 加入目标排")
	await create_timer(0.2).timeout

	var back_slot := _real_slots(back_row)[0]
	var collection_drop_zone := main.get_node("%CollectionDropZone") as Control
	source_position = back_slot.card_view.get_global_rect().get_center()
	target_position = collection_drop_zone.get_global_rect().get_center()
	await _send_mouse_motion(source_position, Vector2.ZERO, 0)
	await _send_left_button(source_position, true)
	await _send_mouse_motion(
		source_position + Vector2(24.0, 16.0),
		Vector2(24.0, 16.0),
		MOUSE_BUTTON_MASK_LEFT
	)
	await _send_mouse_motion(
		target_position,
		target_position - source_position,
		MOUSE_BUTTON_MASK_LEFT
	)
	await process_frame
	_expect(bool(collection_drop_zone.get("_highlighted")), "场上卡拖到收藏区域时显示有效高亮")
	var returned_card := back_slot.get_card_data()
	var returned_drag_data := root.gui_get_drag_data() as Dictionary
	collection_drop_zone.preview_card_drop(target_position, returned_drag_data)
	collection_drop_zone.commit_card_drop(target_position, returned_drag_data)
	root.gui_cancel_drag()
	await process_frame
	await process_frame
	_expect(back_row.get_card_count() == 0, "原生拖回收藏后从棋盘移除")
	_expect(main.collection_cards.size() == initial_collection_count, "原生拖回收藏后所有权数量不变")
	_expect(
		main.collection_cards.has(returned_card),
		"原生拖回收藏后原卡位恢复同一张卡"
	)
	var returned_insert_index: int = main.get_filtered_collection_cards().find(returned_card)
	_expect(
		_collection_card_view(main, returned_insert_index).is_layout_animating(),
		"拖入收藏的新卡从松手位置移动到插入位置"
	)
	var returned_collection_view := _collection_card_view(main, returned_insert_index)
	collection_viewport = main.get_node(
		"WorldContent/CollectionSection/BookPanel/CollectionViewport"
	) as Control
	_expect(
		not collection_viewport.clip_contents,
		"场上卡飞回收藏期间临时解除滚动区裁切"
	)
	_expect(
		returned_collection_view.z_index == CardDragPreview.DRAG_PREVIEW_Z_INDEX,
		"场上卡飞回收藏期间位于其他收藏上层"
	)
	await create_timer(CardView.LAYOUT_TWEEN_DURATION + 0.02).timeout
	_expect(not collection_viewport.clip_contents, "回手动画结束后收藏视口继续允许越界图标显示")
	_expect(returned_collection_view.z_index == 0, "回手动画结束后恢复普通收藏层级")

	var cards: Array[CardData] = main.collection_cards.duplicate()
	main._transfer_card(_collection_drag(cards[0]), &"board", front_row, 0)
	main._transfer_card(_collection_drag(cards[1]), &"board", front_row, 1)
	await process_frame
	await process_frame
	var populated_slots := _real_slots(front_row)
	var between_x: float = (
		populated_slots[0].position.x
		+ populated_slots[0].size.x
		+ populated_slots[1].position.x
	) * 0.5
	target_position = (
		front_row.row_display_area.global_position
		+ Vector2(between_x, front_row.row_display_area.size.y * 0.5)
	)
	collection_card = _collection_card_view(main, 0)
	collection_card_rect = collection_card.get_global_rect()
	source_position = collection_card_rect.get_center()
	await _send_mouse_motion(source_position, Vector2.ZERO, 0)
	await _send_left_button(source_position, true)
	await _send_mouse_motion(
		source_position + Vector2(24.0, -16.0),
		Vector2(24.0, -16.0),
		MOUSE_BUTTON_MASK_LEFT
	)
	await _send_mouse_motion(
		target_position,
		target_position - source_position,
		MOUSE_BUTTON_MASK_LEFT
	)
	await process_frame
	_expect(_preview_slot(front_row) != null, "收藏拖到已有卡牌之间时显示战场虚影")
	var battlefield_cards_are_moving := false
	for slot: BoardSlot in _real_slots(front_row):
		if slot.is_layout_animating():
			battlefield_cards_are_moving = true
			break
	_expect(battlefield_cards_are_moving, "收藏虚影进入战场时其他卡牌会让位")
	root.gui_cancel_drag()
	await process_frame
	_expect(front_row.get_card_count() == 2, "取消带虚影的收藏拖动后战场数据不变")
	await _dispose_main(main)


func _test_click_carry_and_drop_animation() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var back_row := main.get_node("%BackRow") as BattlefieldRow
	var collection_drop_zone := main.get_node("%CollectionDropZone") as Control
	var initial_collection_count: int = main.collection_cards.size()

	var collection_card := _collection_card_view(main, 0)
	var collection_source_slot := collection_card.get_parent() as Control
	var source_position := collection_card.get_global_rect().get_center()
	await _send_mouse_motion(source_position, Vector2.ZERO, 0)
	await _send_simple_left_click(source_position)
	_expect(
		not (main.get("_click_carry_data") as Dictionary).is_empty(),
		"单击收藏后进入鼠标携带状态"
	)
	_expect(
		collection_source_slot.visible
		and is_equal_approx(
			collection_source_slot.modulate.a,
			CardView.COLLECTION_DRAG_GHOST_ALPHA
		),
		"点击携带时原收藏卡位保留虚影"
	)
	_expect(
		is_instance_valid(main.get("_click_carry_preview")),
		"点击携带时创建跟随鼠标的卡牌预览"
	)

	var target_position := front_row.row_display_area.get_global_rect().get_center()
	await _send_mouse_motion(
		target_position,
		target_position - source_position,
		0
	)
	_expect(_preview_slot(front_row) != null, "点击携带进入前排时显示虚影")
	await _send_simple_left_click(target_position)
	await process_frame
	await process_frame
	_expect(
		(main.get("_click_carry_data") as Dictionary).is_empty(),
		"第二次单击后结束鼠标携带状态"
	)
	_expect(front_row.get_card_count() == 1, "点击携带可把收藏放入前排")
	_expect(
		main.collection_cards.size() == initial_collection_count,
		"点击放入前排后真实收藏仍保留唯一所有权"
	)
	var front_slot := _real_slots(front_row)[0]
	_expect(
		front_slot.is_layout_animating(),
		"确认放入前排后，真实卡从鼠标位置飞向目标槽位"
	)

	await create_timer(0.2).timeout
	source_position = front_slot.card_view.get_global_rect().get_center()
	await _send_mouse_motion(source_position, Vector2.ZERO, 0)
	await _send_simple_left_click(source_position)
	_expect(not front_slot.visible, "单击场上卡后来源排临时收拢")
	target_position = back_row.row_display_area.get_global_rect().get_center()
	await _send_mouse_motion(
		target_position,
		target_position - source_position,
		0
	)
	_expect(_preview_slot(back_row) != null, "点击携带跨排时显示目标排虚影")
	await _send_simple_left_click(target_position)
	await process_frame
	await process_frame
	_expect(front_row.get_card_count() == 0, "点击跨排后从前排移除")
	_expect(back_row.get_card_count() == 1, "点击跨排后进入后排")
	var back_slot := _real_slots(back_row)[0]
	_expect(
		back_slot.is_layout_animating(),
		"确认跨排后，真实卡从鼠标位置飞向后排槽位"
	)

	await create_timer(0.2).timeout
	source_position = back_slot.card_view.get_global_rect().get_center()
	await _send_mouse_motion(source_position, Vector2.ZERO, 0)
	await _send_simple_left_click(source_position)
	target_position = collection_drop_zone.get_global_rect().get_center()
	await _send_mouse_motion(
		target_position,
		target_position - source_position,
		0
	)
	_expect(
		bool(collection_drop_zone.get("_highlighted")),
		"点击携带场上卡进入收藏区时显示高亮"
	)
	var click_return_card := back_slot.get_card_data()
	await _send_simple_left_click(target_position)
	await process_frame
	await process_frame
	_expect(back_row.get_card_count() == 0, "点击放回收藏后从后排移除")
	_expect(
		main.collection_cards.size() == initial_collection_count,
		"点击放回收藏后所有权数量不变"
	)
	var click_return_index: int = main.get_filtered_collection_cards().find(click_return_card)
	_expect(
		main.collection_cards.has(click_return_card),
		"点击放回收藏后原排序卡位恢复实体"
	)
	_expect(
		_collection_card_view(main, click_return_index).is_layout_animating(),
		"确认放回收藏后，卡牌从鼠标位置飞向插入位置"
	)

	await create_timer(0.2).timeout
	var before_cancel: Array[CardData] = main.collection_cards.duplicate()
	collection_card = _collection_card_view(main, 0)
	collection_source_slot = collection_card.get_parent() as Control
	source_position = collection_card.get_global_rect().get_center()
	await _send_mouse_motion(source_position, Vector2.ZERO, 0)
	await _send_simple_left_click(source_position)
	await _send_simple_left_click(Vector2(10.0, 10.0))
	await process_frame
	await process_frame
	_expect(main.collection_cards == before_cancel, "点击携带在无效区域释放时数据不变")
	_expect(collection_source_slot.visible, "无效点击释放后恢复真实来源卡")
	_expect(
		collection_card.is_layout_animating(),
		"点击携带在无效区域释放时，卡牌从鼠标位置飞回收藏"
	)
	_expect(
		collection_card.z_index == CardDragPreview.DRAG_PREVIEW_Z_INDEX
		and not (main.get_node("%CollectionViewport") as Control).clip_contents,
		"点击携带失败与原生拖拽共用高层级、非裁切回位规则"
	)
	_expect(
		(main.get("_click_carry_data") as Dictionary).is_empty(),
		"无效点击释放后退出携带状态"
	)
	await create_timer(CardView.LAYOUT_TWEEN_DURATION + 0.05).timeout
	_expect(
		collection_card.z_index == 0
		and not (main.get_node("%CollectionViewport") as Control).clip_contents,
		"点击携带回位结束后只恢复卡牌层级，不泄漏视口裁切状态"
	)

	var board_cards: Array[CardData] = main.collection_cards.duplicate()
	main._transfer_card(_collection_drag(board_cards[0]), &"board", front_row, 0)
	main._transfer_card(_collection_drag(board_cards[1]), &"board", front_row, 1)
	await process_frame
	await process_frame
	var same_row_source := _real_slots(front_row)[0]
	source_position = same_row_source.card_view.get_global_rect().get_center()
	await _send_mouse_motion(source_position, Vector2.ZERO, 0)
	await _send_simple_left_click(source_position)
	var row_rect := front_row.placement_overlay.get_global_rect()
	target_position = (
		row_rect.position
		+ Vector2(row_rect.size.x - 4.0, row_rect.size.y * 0.5)
	)
	await _send_mouse_motion(
		target_position,
		target_position - source_position,
		0
	)
	await _send_simple_left_click(target_position)
	await process_frame
	await process_frame
	_expect(
		_row_cards(front_row) == [board_cards[1], board_cards[0]],
		"点击携带可完成同排换序"
	)
	_expect(
		same_row_source.is_layout_animating(),
		"确认同排换序后，真实卡从鼠标位置飞向虚影位置"
	)
	await _dispose_main(main)


func _test_collection_placement_and_preview_positions() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var back_row := main.get_node("%BackRow") as BattlefieldRow
	var original_cards: Array[CardData] = main.collection_cards.duplicate()

	_expect(
		main._transfer_card(_collection_drag(original_cards[0]), &"board", front_row, 0),
		"收藏可放入空前排"
	)
	_expect(
		main._transfer_card(_collection_drag(original_cards[1]), &"board", back_row, 0),
		"收藏可放入空后排"
	)
	_expect(front_row.get_card_count() == 1, "空前排放置后真实数量为 1")
	_expect(back_row.get_card_count() == 1, "空后排放置后真实数量为 1")
	_expect(
		not (main.selected_board_slot as BoardSlot).is_layout_animating(),
		"新放入的真实卡不再从临时左侧位置横向滑入"
	)

	_expect(
		main._transfer_card(_collection_drag(original_cards[2]), &"board", front_row, 1),
		"第二张收藏可放入前排"
	)
	await process_frame

	var preview_data := _collection_drag(original_cards[3])
	_expect(
		front_row.preview_card_drop(Vector2(0.0, 68.0), preview_data),
		"最左侧显示有效虚影"
	)
	_expect(_preview_index(front_row) == 0, "最左侧虚影位于 index 0")
	front_row.clear_drop_preview()

	var real_slots := _real_slots(front_row)
	var between_x: float = (
		real_slots[0].position.x
		+ real_slots[0].size.x
		+ real_slots[1].position.x
	) * 0.5
	_expect(
		front_row.preview_card_drop(Vector2(between_x, 68.0), preview_data),
		"两张卡之间显示有效虚影"
	)
	var preview_slot := _preview_slot(front_row)
	_expect(_preview_index(front_row) == 1, "中间虚影位于 index 1")
	_expect(preview_slot != null and preview_slot.size.x == 99.0, "虚影宽度为 99px")
	_expect(
		preview_slot != null and is_equal_approx(preview_slot.card_view.modulate.a, 0.4),
		"虚影透明度为 40%"
	)
	_expect(front_row.get_card_count() == 2, "虚影不计入真实卡牌数量")
	front_row.clear_drop_preview()

	_expect(
		front_row.preview_card_drop(Vector2(801.0, 68.0), preview_data),
		"最右侧显示有效虚影"
	)
	_expect(_preview_index(front_row) == 2, "最右侧虚影位于末尾")
	front_row.clear_drop_preview()
	await _dispose_main(main)


# --- 战场往返、满排容量与非准备阶段锁定 ---
func _test_board_move_return_and_cancel() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var back_row := main.get_node("%BackRow") as BattlefieldRow
	var original_cards: Array[CardData] = main.collection_cards.duplicate()
	for index: int in 3:
		_expect(
			main._transfer_card(_collection_drag(original_cards[index]), &"board", front_row, index),
			"建立换序测试阵容 %d" % index
		)
	await process_frame

	var source_slot := _real_slots(front_row)[0]
	var reorder_data := _board_drag(front_row, source_slot)
	front_row._begin_card_drag(reorder_data)
	_expect(not source_slot.visible, "拖起场上卡牌时来源位置临时收拢")
	_expect(front_row.get_card_count() == 3, "拖起时真实数量不变")
	_expect(
		front_row.preview_card_drop(Vector2(801.0, 68.0), reorder_data),
		"满排规则之外的同排末尾预览有效"
	)
	# 预览预留位的让位 Tween 是延后一帧启动的；等待真实空闲状态，
	# 避免仅靠固定秒数时把慢帧中的旧动画误判为提交后新动画。
	for _attempt: int in 12:
		if not _row_has_layout_animation(front_row):
			break
		await create_timer(0.05).timeout
	front_row.commit_card_drop(Vector2(801.0, 68.0), reorder_data)
	_expect(
		_row_cards(front_row) == [original_cards[1], original_cards[2], original_cards[0]],
		"同排拖动可把第一张移到末尾"
	)
	var same_row_started_extra_animation := false
	for slot: BoardSlot in _real_slots(front_row):
		if slot.is_layout_animating():
			same_row_started_extra_animation = true
			break
	_expect(
		not same_row_started_extra_animation,
		"同排松手时真实卡直接替换虚影，不再额外从左向右滑动"
	)
	var cross_source := _real_slots(front_row)[1]
	var cross_data := _board_drag(front_row, cross_source)
	front_row._begin_card_drag(cross_data)
	_expect(
		back_row.preview_card_drop(Vector2(400.0, 68.0), cross_data),
		"跨排目标有容量时显示虚影"
	)
	back_row.commit_card_drop(Vector2(400.0, 68.0), cross_data)
	_expect(front_row.get_card_count() == 2, "跨排后来源排减少一张")
	_expect(back_row.get_card_count() == 1, "跨排后目标排增加一张")

	var returned_slot := _real_slots(back_row)[0]
	var returned_card := returned_slot.get_card_data()
	var hand_zone := main.get_node("%CollectionDropZone") as Control
	var hand_slots: Array[Control] = main._get_collection_card_slots()
	var hand_insert_position := (
		hand_slots[1].get_global_rect().get_center()
		- Vector2(1.0, 0.0)
	)
	var return_data := _board_drag(back_row, returned_slot)
	_expect(
		hand_zone.preview_card_drop(hand_insert_position, return_data),
		"场上卡进入收藏区域时显示有效回收高亮"
	)
	hand_zone.commit_card_drop(hand_insert_position, return_data)
	_expect(back_row.get_card_count() == 0, "拖回收藏后场上移除")
	_expect(main.collection_cards.has(returned_card), "拖回的卡牌重新加入真实收藏")
	var sorted_collection: Array[CardData] = main.get_filtered_collection_cards()
	var rarity_descending := true
	for index: int in range(1, sorted_collection.size()):
		if sorted_collection[index - 1].rarity < sorted_collection[index].rarity:
			rarity_descending = false
			break
	_expect(rarity_descending, "拖回后收藏继续按稀有度 V→I 显示")

	var cancel_slot := _real_slots(front_row)[0]
	var before_cancel := _row_cards(front_row)
	var hand_count_before_cancel: int = main.collection_cards.size()
	var cancel_data := _board_drag(front_row, cancel_slot)
	front_row._begin_card_drag(cancel_data)
	front_row.preview_card_drop(Vector2(400.0, 68.0), cancel_data)
	front_row._finish_card_drag(Vector2(10.0, 10.0))
	await process_frame
	await process_frame
	_expect(cancel_slot.visible, "取消拖动后来源卡恢复显示")
	_expect(
		cancel_slot.is_layout_animating(),
		"场上卡在战场外取消时从鼠标位置飞回来源槽位"
	)
	_expect(_preview_slot(front_row) == null, "取消拖动后虚影移除")
	_expect(_row_cards(front_row) == before_cancel, "取消拖动后顺序不变")
	_expect(main.collection_cards.size() == hand_count_before_cancel, "取消拖动后收藏不丢失或复制")
	await _dispose_main(main)


func _test_full_row_rules_and_width() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var back_row := main.get_node("%BackRow") as BattlefieldRow
	var original_cards: Array[CardData] = main.collection_cards.duplicate()
	for index: int in 7:
		_expect(
			main._transfer_card(_collection_drag(original_cards[index]), &"board", front_row, index),
			"建立 7 张满排 %d" % index
		)
	await process_frame
	await process_frame

	var full_slots := _real_slots(front_row)
	var display_width: float = (
		full_slots[-1].position.x
		+ full_slots[-1].size.x
		- full_slots[0].position.x
	)
	_expect(front_row.get_card_count() == 7, "21 单元等于 7 张单卡")
	_expect(is_equal_approx(display_width, 801.0), "7 张满排显示宽度保持 801px")
	_expect(not front_row.has_capacity_for_single_card(), "满排拒绝新增单卡")

	var rejected_collection_card := _collection_card_view(main, 0)
	var rejected_collection_slot := rejected_collection_card.get_parent() as Control
	var rejected_card := rejected_collection_card.card_data
	var source_position := rejected_collection_card.get_global_rect().get_center()
	var rejected_target := front_row.row_display_area.get_global_rect().get_center()
	await _send_mouse_motion(source_position, Vector2.ZERO, 0)
	await _send_left_button(source_position, true)
	await _send_mouse_motion(
		source_position + Vector2(24.0, -16.0),
		Vector2(24.0, -16.0),
		MOUSE_BUTTON_MASK_LEFT
	)
	await _send_mouse_motion(
		rejected_target,
		rejected_target - source_position,
		MOUSE_BUTTON_MASK_LEFT
	)
	await process_frame
	_expect(_preview_slot(front_row) == null, "收藏拖向满排时不显示有效虚影")
	await _send_left_button(rejected_target, false)
	await process_frame
	await process_frame
	_expect(rejected_collection_slot.visible, "满排拒绝后恢复来源收藏")
	_expect(
		rejected_collection_card.is_layout_animating(),
		"满排拒绝后卡牌从鼠标位置飞回收藏"
	)
	_expect(main.collection_cards.has(rejected_card), "满排拒绝后真实收藏数据不变")
	_expect(front_row.get_card_count() == 7, "满排拒绝后场上数量不变")
	await create_timer(0.2).timeout

	_expect(
		main._transfer_card(_collection_drag(original_cards[7]), &"board", back_row, 0),
		"第 8 张卡可放到另一排"
	)
	var cross_slot := _real_slots(back_row)[0]
	var cross_data := _board_drag(back_row, cross_slot)
	back_row._begin_card_drag(cross_data)
	_expect(
		not front_row.preview_card_drop(Vector2(400.0, 68.0), cross_data),
		"跨排目标已满时拒绝预览"
	)
	_expect(_preview_slot(front_row) == null, "满排跨排无有效虚影")
	back_row._finish_card_drag()
	_expect(front_row.get_card_count() == 7, "拒绝跨排后满排数量不变")
	_expect(back_row.get_card_count() == 1, "拒绝跨排后来源排数量不变")

	var reorder_slot := _real_slots(front_row)[0]
	var reorder_data := _board_drag(front_row, reorder_slot)
	front_row._begin_card_drag(reorder_data)
	_expect(
		front_row.preview_card_drop(Vector2(801.0, 68.0), reorder_data),
		"7 张满排仍允许内部换序预览"
	)
	_expect(front_row.get_card_count() == 7, "满排内部虚影不增加真实占用")
	var visible_item_count: int = 0
	for child: Node in front_row.get_squad_container().get_children():
		if child is Control and (child as Control).visible:
			visible_item_count += 1
	_expect(visible_item_count == 7, "满排拖动时 6 张真实卡加 1 张虚影仍为 7 个可见项")
	front_row.commit_card_drop(Vector2(801.0, 68.0), reorder_data)
	_expect(_row_cards(front_row)[-1] == original_cards[0], "满排内部换序成功")
	await _dispose_main(main)


func _test_phase_click_and_button_regressions() -> void:
	var main: Variant = await _create_main()
	var front_row := main.get_node("%FrontRow") as BattlefieldRow
	var original_cards: Array[CardData] = main.collection_cards.duplicate()
	var second_collection_card_view := _collection_card_view(main, 1)

	var left_click := InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.pressed = true
	second_collection_card_view._gui_input(left_click)
	_expect(main.selected_card == original_cards[1], "左键点击仍更新卡牌预览")

	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	var previous_effect_state: bool = second_collection_card_view.showing_effect
	second_collection_card_view._gui_input(right_click)
	_expect(
		second_collection_card_view.showing_effect != previous_effect_state,
		"右键仍可切换符文/效果显示"
	)

	_expect(
		main._transfer_card(_collection_drag(original_cards[0]), &"board", front_row, 0),
		"建立场上选中测试卡牌"
	)
	var board_slot := _real_slots(front_row)[0]
	board_slot.card_view._gui_input(left_click)
	_expect(main.selected_board_slot == board_slot, "点击场上卡牌仍可选中")
	_expect(
		main.get_node_or_null("%ReturnToCollectionButton") == null,
		"旧的收回收藏按钮已移除"
	)

	var phase_button := main.get_node("%StartBattleButton") as Button
	var tuner_button := main.get_node("%CardArtTunerButton") as Button
	_expect(tuner_button.text == "卡面调整器", "主界面提供卡面调整器入口")
	phase_button.emit_signal("pressed")
	_expect(main.current_phase == 1, "阶段按钮可进入战斗阶段")
	var battle_collection_card_view := _collection_card_view(main, 0)
	_expect(
		battle_collection_card_view._get_drag_data(Vector2(10.0, 10.0)) == null,
		"战斗阶段禁止从收藏开始拖动"
	)
	_expect(
		not front_row.can_receive_card_drag(_collection_drag(main.collection_cards[0])),
		"战斗阶段棋盘不接收放置反馈"
	)
	_expect(_preview_slot(front_row) == null, "战斗阶段放置反馈隐藏")

	phase_button.emit_signal("pressed")
	_expect(main.current_phase == 2, "阶段按钮可进入结算阶段")
	_expect(
		_collection_card_view(main, 0)._get_drag_data(Vector2(10.0, 10.0)) == null,
		"结算阶段禁止拖动"
	)
	phase_button.emit_signal("pressed")
	_expect(main.current_phase == 0, "阶段按钮可回到准备阶段")
	await _dispose_main(main)


# --- 场景夹具、拖拽数据与输入事件辅助函数 ---
func _create_main() -> Variant:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_expect(main.get_script() != null, "Main 场景脚本成功加载")
	return main


func _dispose_main(main: Variant) -> void:
	main.queue_free()
	await process_frame


func _collection_drag(card_data: CardData) -> Dictionary:
	return {
		"kind": &"card",
		"card_data": card_data,
		"source_type": &"collection",
		"source_row": null,
		"source_slot": null,
	}


func _board_drag(row: BattlefieldRow, slot: BoardSlot) -> Dictionary:
	return {
		"kind": &"card",
		"card_data": slot.get_card_data(),
		"source_type": &"board",
		"source_row": row,
		"source_slot": slot,
	}


func _real_slots(row: BattlefieldRow) -> Array[BoardSlot]:
	var slots: Array[BoardSlot] = []
	for child: Node in row.get_squad_container().get_children():
		var slot := child as BoardSlot
		if slot != null and not slot.is_preview():
			slots.append(slot)
	return slots


func _preview_slot(row: BattlefieldRow) -> BoardSlot:
	for child: Node in row.get_squad_container().get_children():
		var slot := child as BoardSlot
		if slot != null and slot.is_preview():
			return slot
		for nested_child: Node in child.get_children():
			var nested_slot := nested_child as BoardSlot
			if nested_slot != null and nested_slot.is_preview():
				return nested_slot
	return null


func _preview_index(row: BattlefieldRow) -> int:
	var visual_index: int = 0
	for child: Node in row.get_squad_container().get_children():
		var slot := child as BoardSlot
		if slot == null:
			for nested_child: Node in child.get_children():
				var nested_slot := nested_child as BoardSlot
				if nested_slot != null and nested_slot.is_preview():
					return visual_index
			continue
		if not slot.visible:
			continue
		if slot.is_preview():
			return visual_index
		visual_index += 1
	return -1


func _row_cards(row: BattlefieldRow) -> Array[CardData]:
	var cards: Array[CardData] = []
	for slot: BoardSlot in _real_slots(row):
		cards.append(slot.get_card_data())
	return cards


func _row_has_layout_animation(row: BattlefieldRow) -> bool:
	for slot: BoardSlot in _real_slots(row):
		if slot.is_layout_animating():
			return true
	return false


func _collection_card_view(main: Variant, index: int) -> CardView:
	var hand_slot: Node = main.get_node("%CollectionCardRow").get_child(index)
	return hand_slot.get_child(0) as CardView


func _send_left_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame


func _send_simple_left_click(position: Vector2) -> void:
	await _send_left_button(position, true)
	await _send_left_button(position, false)


func _send_mouse_motion(position: Vector2, relative: Vector2, button_mask: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	event.button_mask = button_mask
	root.push_input(event, true)
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return

	_failure_count += 1
	push_error("FAIL: %s" % message)
