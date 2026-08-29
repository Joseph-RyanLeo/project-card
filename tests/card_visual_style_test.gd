extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const CARD_TEXT_FONT: Font = preload("res://assets/fonts/chill_7.ttf")
const NAME_FRAME_TEXTURE: Texture2D = preload("res://assets/card_ui/card_name_frame.png")
const ART_BACKGROUND_TEXTURE: Texture2D = preload(
	"res://assets/card_backgrounds/card_background_placeholder.png"
)

var _failure_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var card := _find_real_card(main)
	_expect(card != null, "Main 中存在可检查最终卡面样式的真实卡牌")
	_expect(
		CardView.format_cooldown_seconds(3.4) == "3.4"
		and CardView.format_cooldown_seconds(4.0) == "4.0"
		and CardView.format_cooldown_seconds(2.96) == "3.0"
		and CardView.format_cooldown_seconds(12.0) == "9.9",
		"冷却始终显示一位小数、向上取到0.1秒且最高9.9"
	)
	if card != null:
		_expect(
			card.name_label.get_theme_font("font") == CARD_TEXT_FONT
			and card.effect_text_label.get_theme_font("font") == CARD_TEXT_FONT
			and card.name_label.get_theme_font_size("font_size") <= 8
			and card.effect_text_label.get_theme_font_size("font_size") == 8,
			"卡名与效果文字固定使用寒蝉点阵 7px，首选字号为 8"
		)
		_expect(
			card.card_name_frame.texture == NAME_FRAME_TEXTURE
			and NAME_FRAME_TEXTURE.get_size() == Vector2(83, 11),
			"卡名显示框替换为 83×11 新素材"
		)
		_expect(
			card.name_label.horizontal_alignment
			== HORIZONTAL_ALIGNMENT_CENTER,
			"卡牌名字在现有文本区域内水平居中"
		)
		_expect(
			card.name_clip.position == Vector2(21, 5),
			"卡牌名字文本框在原位置基础上向下移动 1px"
		)
		_expect(
			card.art_background.texture == ART_BACKGROUND_TEXTURE
			and ART_BACKGROUND_TEXTURE.get_size() == Vector2(97, 102),
			"所有卡牌共用新的 97×102 插画背景"
		)
		_expect(
			card.art_panel.position == Vector2(10, 5)
			and card.art_panel.size == Vector2(79, 95)
			and card.art_panel.clip_contents,
			"背景和人物被裁在卡框内窗，晃动时不会越出外框"
		)
		_expect(
			card.cooldown_icon.position == card.cooldown_icon_position
			and card.cooldown_icon.position == Vector2(-1, 22)
			and card.cooldown_icon.size == card.cooldown_icon_size
			and card.cooldown_icon.texture.get_size() == Vector2(12, 16),
			"12×16px 沙漏常驻卡面左上区域"
		)
		_expect(
			card.cooldown_label.position == Vector2(-3, 24)
			and card.cooldown_label.number_style
			== RuneNumberDisplay.NumberStyle.COOLDOWN
			and card.cooldown_label.get_rendered_size().y == 12,
			"冷却组合数字固定从(-3,24)开始并使用12px统一底边"
		)
		_expect(
			card.cooldown_label.text == CardView.format_cooldown_seconds(
				card.card_data.cooldown_seconds
			),
			"准备阶段直接显示 CardData 基础冷却秒数"
		)
		_expect(
			card.value_label.number_style == RuneNumberDisplay.NumberStyle.LARGE
			and card.health_label.number_style == RuneNumberDisplay.NumberStyle.LARGE
			and card.armor_label.number_style == RuneNumberDisplay.NumberStyle.MEDIUM
			and card.cooldown_label.number_style == RuneNumberDisplay.NumberStyle.COOLDOWN
			and card.value_label.character_spacing == 0
			and card.health_label.character_spacing == 0
			and card.armor_label.character_spacing == 0,
			"行动与生命使用大卢恩图集，护甲使用中图集，冷却混排中/小图集"
		)
		_expect(
			RuneNumberDisplay.LARGE_TEXTURE.get_size() == Vector2(119, 14)
			and RuneNumberDisplay.MEDIUM_TEXTURE.get_size() == Vector2(97, 12)
			and RuneNumberDisplay.SMALL_TEXTURE.get_size() == Vector2(77, 8)
			and RuneNumberDisplay.DECIMAL_POINT_TEXTURE.get_size() == Vector2(3, 3)
			and (RuneNumberDisplay.LARGE_GLYPH_RECTS["1"] as Rect2).size.x == 7
			and (RuneNumberDisplay.LARGE_GLYPH_RECTS["2"] as Rect2).size.x == 10,
			"新版三档卢恩数字和独立小数点按数字1的真实窄字形裁切"
		)
		_expect(
			CardView.get_health_value_position(11) == Vector2(86, 88)
			and CardView.get_health_value_position(111) == Vector2(83, 88)
			and CardView.get_armor_value_position(11) == Vector2(88, 74)
			and CardView.get_armor_value_position(111) == Vector2(84, 74)
			and CardView.get_action_value_position(1) == Vector2(1, 7)
			and CardView.get_action_value_position(99) == Vector2(-5, 7),
			"数字位数与1的数量使用已确认的绝对卡面坐标"
		)
		_expect(
			card.health_icon.position == Vector2(84, 88)
			and card.health_icon.size == Vector2(20, 17)
			and card.armor_icon.position == Vector2(87, 71)
			and card.armor_icon.size == Vector2(14, 16),
			"新版生命和护甲图标使用纠正后的绝对坐标与原生尺寸"
		)
		_expect(
			card.effect_text_label.get_theme_constant("line_spacing") == card.effect_line_spacing
			and card.effect_text_label.get_theme_color("font_color").is_equal_approx(
				card.effect_text_color
			)
			and card.effect_text_label.get_theme_constant("outline_size")
			== card.effect_text_outline_size
			and card.effect_text_label.get_theme_color(
				"font_outline_color"
			).is_equal_approx(card.effect_text_outline_color),
			"效果文字使用正式行距、颜色与2px近黑描边，不再经过运行时调试状态"
		)
		_expect(
			card.rune_row.visible
			and is_equal_approx(card.rune_row.modulate.a, 1.0)
			and not card.effect_text_label.visible,
			"随从卡默认完整显示符文并隐藏效果文字"
		)
		_expect(
			card.toggle_effect_display()
			and card.rune_row.visible
			and card.effect_text_label.visible
			and card.is_effect_transition_animating(),
			"首次右键状态会启动符文与效果文字的并行动画"
		)
		await create_timer(card.effect_transition_duration * 0.5).timeout
		_expect(
			card.rune_row.modulate.a < 1.0
			and card.rune_row.modulate.a > card.effect_rune_dim_alpha
			and card.effect_text_label.self_modulate.a > 0.0
			and card.effect_text_label.self_modulate.a < 1.0,
			"动画中段同时存在逐渐变淡的符文和逐渐显现的文字"
		)
		await create_timer(card.effect_transition_duration * 0.6).timeout
		_expect(
			is_equal_approx(card.rune_row.modulate.a, card.effect_rune_dim_alpha)
			and is_equal_approx(card.effect_text_label.self_modulate.a, 1.0),
			"首次切换完成后符文停在20%且文字完全显示"
		)
		card.toggle_effect_display()
		await create_timer(card.effect_transition_duration + 0.05).timeout
		_expect(
			not card.showing_effect
			and card.rune_row.visible
			and is_equal_approx(card.rune_row.modulate.a, 1.0)
			and not card.effect_text_label.visible,
			"再次切换完成后文字隐藏且符文恢复100%"
		)
		var original_card_data := card.card_data
		var wrapping_card_data := original_card_data.duplicate() as CardData
		wrapping_card_data.effect_text = (
			"行动时对目标造成伤害并为相邻友军提供护盾，随后恢复生命并增加临时护甲"
		)
		card.set_card_data(wrapping_card_data)
		card.showing_effect = true
		card._refresh_bottom_text()
		await process_frame
		_expect(
			card.effect_text_label.autowrap_mode
			== TextServer.AUTOWRAP_WORD_SMART
			and not card.bottom_panel.clip_contents
			and not card.effect_text_label.clip_text
			and card.effect_text_label.max_lines_visible == 3
			and card.effect_text_label.position == card.effect_text_inset
			and card.effect_text_label.size
			== card.bottom_area_size - card.effect_text_inset * 2.0
			and card.effect_text_label.get_line_count() >= 3
			and card.effect_text_label.get_visible_line_count() == 3
			and card.bottom_panel.position + card.rune_row.position
			== card.rune_area_position
			and card.rune_row.size == card.rune_area_size
			and card.rune_row.visible
			and is_equal_approx(card.rune_row.modulate.a, card.effect_rune_dim_alpha)
			and card.effect_text_label.visible
			and is_equal_approx(card.effect_text_label.self_modulate.a, 1.0),
			"文字扩到卡框底栏并保留描边内距，最多显示三行且符文位置不变"
		)

	_expect(
		main.get_node_or_null("%CardTextDebugPanel") == null
		and main.get_node_or_null("%EffectLineSpacingSpinBox") == null
		and main.get_node_or_null("%EffectColorButton") == null
		and main.get_node_or_null("%EffectTextToggle") == null
		and main.get_node_or_null("%TextDebugResetButton") == null
		and main.get_node_or_null("%FontCandidateSelector") == null
		and main.get_node_or_null("%FontPreviousButton") == null
		and main.get_node_or_null("%FontNextButton") == null
		and main.get_node_or_null("%FontSizeSpinBox") == null,
		"卡牌文字调试窗口、状态和旧字体调试控件均已删除"
	)

	root.remove_child(main)
	main.queue_free()
	await process_frame
	if _failure_count == 0:
		print("Card visual style checks passed.")
	else:
		push_error("Card visual style checks failed: %d" % _failure_count)
	quit(_failure_count)


func _find_real_card(main: Node) -> CardView:
	for node: Node in main.get_tree().get_nodes_in_group("card_views"):
		if node is CardView and (node as CardView).card_data != null:
			return node as CardView
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failure_count += 1
	push_error("FAIL: %s" % message)
