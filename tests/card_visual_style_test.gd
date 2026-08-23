extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const CARD_TEXT_FONT: Font = preload("res://assets/fonts/chill_7.ttf")
const LARGE_NUMBER_FONT: Font = preload("res://assets/fonts/pixel_numbers_large.fnt")
const SMALL_NUMBER_FONT: Font = preload("res://assets/fonts/pixel_numbers_small.fnt")
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
			card.value_label.get_theme_font("font") == LARGE_NUMBER_FONT
			and card.health_label.get_theme_font("font") == LARGE_NUMBER_FONT
			and card.armor_label.get_theme_font("font") == SMALL_NUMBER_FONT
			and card.health_label.get_theme_font_size("font_size") == card.value_font_size
			and card.armor_label.get_theme_font_size("font_size") == card.stats_font_size,
			"行动值与生命使用大数字，护甲恢复对称的小数字字体"
		)
		main.effect_line_spacing_spin_box.value = 2
		main.effect_color_button.color = Color("38c7ff")
		main._on_effect_color_changed(main.effect_color_button.color)
		main.effect_text_toggle.button_pressed = true
		await process_frame
		_expect(
			card.effect_text_label.get_theme_constant("line_spacing") == 2
			and card.effect_text_label.get_theme_color("font_color").is_equal_approx(
				Color("38c7ff")
			)
			and card.effect_text_label.visible,
			"左下角仍可现场调试效果文字行距、颜色与显示状态"
		)

	_expect(
		main.card_text_debug_panel != null
		and main.get_node_or_null("%FontCandidateSelector") == null
		and main.get_node_or_null("%FontPreviousButton") == null
		and main.get_node_or_null("%FontNextButton") == null
		and main.get_node_or_null("%FontSizeSpinBox") == null,
		"字体候选、前后切换和字号调试控件均已删除"
	)

	root.remove_child(main)
	main.queue_free()
	await process_frame
	CardView.debug_effect_line_spacing = 0
	CardView.debug_effect_text_color = Color.WHITE
	CardView.debug_force_effect_text = false
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
