class_name ScreenTransition
extends CanvasLayer

signal finished
signal covered

const FADE_OUT_SECONDS: float = 0.18 # 旧画面逐渐变黑的时长
const FADE_IN_SECONDS: float = 0.24 # 新画面逐渐亮起的时长
const MIN_LOADING_SECONDS: float = 0.35 # 加载动画最短展示时间，避免快速加载时闪一下就消失
const WALK_SCALE: float = 2.0 # 行走人物相对原始47×76像素的逻辑放大倍率
const LABEL_GAP: float = 100.0 # 加载文字相对画面中心的向下偏移
const OVERLAY_LAYER: int = 100 # 黑场位于显示模式入口和游戏内部所有界面之上
const WALK_FRAMES: SpriteFrames = preload("res://resources/ui/loading_walk.tres")
const FONT: Font = preload("res://assets/fonts/chill_7.ttf")

var busy := false
var is_covered := false
var _veil: ColorRect
var _loading: Control
var _walker: AnimatedSprite2D
var _caption: Label


static func change_scene(tree: SceneTree, path: String) -> void:
	var transition := ScreenTransition.new()
	tree.root.add_child(transition)
	await transition.change(transition._load_scene.bind(path), true)
	transition.queue_free()


func _load_scene(path: String) -> Error:
	var error := get_tree().change_scene_to_file(path)
	if error == OK:
		await get_tree().scene_changed
		get_tree().root.move_child(self, -1)
	return error


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = OVERLAY_LAYER
	_veil = ColorRect.new()
	_veil.name = "FadeVeil"
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.color = Color.BLACK
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_veil.hide()
	add_child(_veil)
	_loading = Control.new()
	_loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.add_child(_loading)
	_walker = AnimatedSprite2D.new()
	_walker.name = "LoadingWalker"
	_walker.sprite_frames = WALK_FRAMES
	_walker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_loading.add_child(_walker)
	_caption = Label.new()
	_caption.text = "正在加载……"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_override("font", FONT)
	_caption.add_theme_font_size_override("font_size", 16) # 加载提示的像素字号
	_caption.add_theme_color_override("font_color", Color("dcb77d")) # 加载提示沿用主菜单暖金色
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading.add_child(_caption)
	_loading.hide()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var ratio := minf(viewport_size.x / 1280.0, viewport_size.y / 720.0)
	_loading.position = viewport_size * 0.5
	_loading.scale = Vector2.ONE * ratio
	_walker.scale = Vector2.ONE * WALK_SCALE
	_caption.position = Vector2(-240, LABEL_GAP) # 提示文字水平居中，预留足够行宽
	_caption.size = Vector2(480, 32) # 加载提示的逻辑文本框尺寸


func change(action: Callable, show_loading: bool = false) -> Variant:
	if busy or not action.is_valid():
		return null
	busy = true
	is_covered = false
	_veil.modulate.a = 0.0
	_veil.show()
	await _fade(1.0, FADE_OUT_SECONDS)
	is_covered = true
	if show_loading:
		_loading.show()
		_walker.play(&"walk")
	covered.emit()
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var loading_started := Time.get_ticks_usec()
	var result: Variant = await action.call()
	if show_loading:
		var remaining := MIN_LOADING_SECONDS - (Time.get_ticks_usec() - loading_started) / 1000000.0
		if remaining > 0.0:
			await get_tree().create_timer(remaining, true, false, true).timeout
	_loading.hide()
	_walker.stop()
	await get_tree().process_frame
	is_covered = false
	await _fade(0.0, FADE_IN_SECONDS)
	_veil.hide()
	busy = false
	finished.emit()
	return result


func _fade(alpha: float, seconds: float) -> void:
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	tween.tween_property(_veil, "modulate:a", alpha, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func _input(_event: InputEvent) -> void:
	if busy:
		get_viewport().set_input_as_handled()
