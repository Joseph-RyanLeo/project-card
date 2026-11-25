extends RefCounted

## 菜单共用现有像素背景与字体，四层界面使用同一套颜色和控件样式。
const BACKGROUND = preload("res://assets/ui/start_menu_background.png")
static var FONT: Font = preload("res://scripts/ui/ui_typography.gd").font()
const GOLD := Color("dcb77d") # 菜单文字与细边框颜色
const BUTTON_SIZE := Vector2(296, 48) # 常规菜单按钮尺寸


static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font = FONT
	result.default_font_size = 24 # 菜单默认字号，使用精细加粗黑体
	result.set_color("font_color", "Label", GOLD)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var fill := Color("161e2a") if state in ["normal", "disabled"] else Color("30333b")
		var style := panel(fill, GOLD if state != "disabled" else Color("665d50"))
		style.content_margin_top = 4 # 黑体行盒较高，按钮上下留白保持紧凑
		style.content_margin_bottom = 4 # 配合48px按钮高度，避免菜单被撑出画布
		result.set_stylebox(state, "Button", style)
	result.set_color("font_color", "Button", GOLD)
	result.set_color("font_hover_color", "Button", Color("fff0c2"))
	result.set_color("font_disabled_color", "Button", Color("817869"))
	result.set_stylebox("panel", "PanelContainer", panel(Color("161e2a"), GOLD))
	return result


static func make_book_theme() -> Theme:
	var result := make_theme()
	result.default_font_size = 16 # 收藏菜单与设置页在原生书页中的字号
	var ink := Color("382319") # 与收藏纸面相配的深褐正文
	result.set_color("font_color", "Label", ink)
	for control_type: String in ["Button", "OptionButton", "CheckButton"]:
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			result.set_color(state, control_type, ink)
		result.set_color("font_disabled_color", control_type, Color("795644"))
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			var surface := Color("edd1af") if state in ["hover", "focus"] else Color("d6ab80")
			if state == "pressed": surface = Color("c49771")
			var button := panel(surface, Color("946849"))
			button.set_border_width_all(1)
			button.set_content_margin_all(5)
			button.content_margin_top = 3
			button.content_margin_bottom = 3
			result.set_stylebox(state, control_type, button)
	var page := StyleBoxEmpty.new()
	page.set_content_margin_all(10) # 给书页纹理留出内边距，由底层普通书页绘制纸色
	result.set_stylebox("panel", "PanelContainer", page)
	return result


static func panel(fill: Color, border: Color) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(2) # 像素面板边框厚度
	result.set_content_margin_all(16) # 面板内容留白
	return result


static func add_background(parent: Control) -> void:
	var background := TextureRect.new()
	background.name = "Background"
	background.texture = BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(background)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.035, 0.045, 0.07, 0.94)) # 左侧文字区域遮罩透明度
	gradient.set_color(1, Color(0.035, 0.045, 0.07, 0.25)) # 右侧保留背景轮廓
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(0.9, 0) # 横向遮罩过渡范围
	var shade := TextureRect.new()
	shade.texture = texture
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shade)


static func button(parent: Control, title: String, node_name: String, action: Callable) -> Button:
	var result := Button.new()
	result.name = node_name
	result.text = title
	result.custom_minimum_size = BUTTON_SIZE
	if action.is_valid(): result.pressed.connect(action)
	parent.add_child(result)
	return result


static func popup_for_display(dialog: Window, logical_size: Vector2i) -> void:
	# 子窗口不经过主界面的SubViewportContainer，需单独采用同一显示倍率。
	var shell := dialog.get_tree().get_first_node_in_group(&"game_display_shell")
	var display_scale: float = shell.render_container.scale.x if shell != null else 1.0
	dialog.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	dialog.content_scale_size = Vector2i.ZERO
	dialog.content_scale_factor = display_scale
	dialog.popup_centered(Vector2i(Vector2(logical_size) * display_scale))
