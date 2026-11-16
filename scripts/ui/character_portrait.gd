extends Control

## 只负责场外角色头像；台词、逐字显示与句间停留仍由TaskHintOverlay管理。
const Style = preload("res://scripts/ui/menu_style.gd")
const PortraitMask = preload("res://shaders/character_portrait_mask.gdshader")
const PORTRAIT_SIZE := Vector2(144, 172) # 场外头像及姓名牌的整体尺寸
const POPUP_POSITION := Vector2(28, 520) # 固定在左下角，独立于上下战场视角
const APPEAR_SECONDS: float = 0.28 # 头像从小变大的时长
const DISAPPEAR_SECONDS: float = 0.22 # 说完后缩小消失的时长
const MIN_SCALE: float = 0.01 # 收起时接近零的尺寸，避免零缩放导致变换不可逆
const RING_CENTER := Vector2(72, 83) # 圆环在头像控件内的中心位置
const RING_RADIUS: float = 59.0 # 圆环外径的一半
const RIM_WIDTH: float = 7.0 # 金属环边缘的厚度
const RING_DEPTH: float = 4.0 # 金属环向下露出的侧壁厚度
const RING_SEGMENTS: int = 64 # 圆环曲线的细分数量
const RING_SHADOW := Color("4c3329")
const RING_GOLD := Color("b88c55")
const RING_HIGHLIGHT := Color("f0d3a0")

var _motion: Tween
var _art: TextureRect
var _initial: Label
var _name_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = PORTRAIT_SIZE
	position = POPUP_POSITION
	pivot_offset = Vector2(size.x * 0.5, size.y)
	_art = TextureRect.new()
	_art.position = Vector2(3, 0) # 给圆环上方的立绘留出探头空间
	_art.size = Vector2(138, 138) # 场外立绘使用的最大取景尺寸
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mask := ShaderMaterial.new()
	mask.shader = PortraitMask
	mask.set_shader_parameter("ring_center", RING_CENTER - _art.position)
	mask.set_shader_parameter("ring_radius", RING_RADIUS - RIM_WIDTH * 0.5)
	_art.material = mask
	add_child(_art)
	_initial = Label.new()
	_initial.position = RING_CENTER - Vector2.ONE * RING_RADIUS
	_initial.size = Vector2.ONE * RING_RADIUS * 2.0
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_initial.add_theme_font_override("font", Style.FONT)
	_initial.add_theme_font_size_override("font_size", 48) # 暂缺角色图时显示姓名首字的字号
	_initial.add_theme_color_override("font_color", Style.GOLD)
	_initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_initial)
	var front_rim := Control.new()
	front_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front_rim.draw.connect(_draw_front_rim.bind(front_rim))
	add_child(front_rim)
	var nameplate := Panel.new()
	nameplate.position = Vector2(0, 144)
	nameplate.size = Vector2(size.x, 28)
	nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nameplate.add_theme_stylebox_override("panel", Style.panel(Color("172633"), Style.GOLD))
	add_child(nameplate)
	_name_label = Label.new()
	_name_label.position = Vector2(0, 146)
	_name_label.size = Vector2(size.x, 26)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_override("font", Style.FONT)
	_name_label.add_theme_font_size_override("font_size", 16) # 头像下方姓名字号
	_name_label.add_theme_color_override("font_color", Style.GOLD)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)
	hide()


func _draw() -> void:
	draw_circle(RING_CENTER + Vector2(0, RING_DEPTH), RING_RADIUS, RING_SHADOW, true, -1.0, true)
	draw_circle(RING_CENTER, RING_RADIUS, RING_GOLD, true, -1.0, true)
	draw_circle(RING_CENTER, RING_RADIUS - RIM_WIDTH, Color("172633"), true, -1.0, true)
	draw_arc(RING_CENTER, RING_RADIUS - 2.0, PI, TAU, RING_SEGMENTS, RING_HIGHLIGHT, 1.5, true)


func _draw_front_rim(rim: Control) -> void:
	# 前半圈在立绘之后绘制，遮住下半身。上半圈留在人物背后。
	rim.draw_arc(RING_CENTER, RING_RADIUS - RIM_WIDTH * 0.5, 0.0, PI, RING_SEGMENTS, RING_GOLD, RIM_WIDTH, true)
	rim.draw_arc(RING_CENTER, RING_RADIUS - RIM_WIDTH + 1.0, 0.0, PI, RING_SEGMENTS, RING_HIGHLIGHT, 1.5, true)


func present(speaker_name: String, portrait: Texture2D = null) -> Tween:
	if is_instance_valid(_motion): _motion.kill()
	_name_label.text = speaker_name
	_name_label.tooltip_text = speaker_name
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# 卡图常带大块透明留白；AtlasTexture只改变取景，仍引用原像素素材。
	if portrait != null:
		var cropped := AtlasTexture.new()
		cropped.atlas = portrait
		cropped.region = portrait.get_image().get_used_rect()
		_art.texture = cropped
	else: _art.texture = null
	_initial.text = speaker_name.left(1)
	_initial.visible = portrait == null
	scale = Vector2.ONE * MIN_SCALE
	modulate.a = 0.0
	show()
	_motion = create_tween().set_parallel()
	_motion.tween_property(self, "scale", Vector2.ONE, APPEAR_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_motion.tween_property(self, "modulate:a", 1.0, APPEAR_SECONDS)
	return _motion


func dismiss() -> Tween:
	if is_instance_valid(_motion): _motion.kill()
	_motion = create_tween().set_parallel()
	_motion.tween_property(self, "scale", Vector2.ONE * MIN_SCALE, DISAPPEAR_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_motion.tween_property(self, "modulate:a", 0.0, DISAPPEAR_SECONDS)
	_motion.chain().tween_callback(hide)
	return _motion
