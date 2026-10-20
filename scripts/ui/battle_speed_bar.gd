extends Control

## 只负责四个播放档的输入与演出，实际暂停和倍速仍由Main管理。
signal slot_selected(slot: int)

const TRACK: Texture2D = preload("res://assets/ui/board_revision_20261019/battle_speed_track.png")
const SLIDER: Texture2D = preload("res://assets/ui/board_revision_20261019/battle_speed_slider.png")
const HIGHLIGHTS: Texture2D = preload("res://assets/ui/board_revision_20261019/battle_speed_highlights.png")
const ICON_REGIONS: Array[Rect2] = [Rect2(0, 0, 5, 9), Rect2(40, 0, 6, 9), Rect2(79, 0, 9, 9), Rect2(117, 0, 12, 9)] # 高亮图集四个图标的原生区域
const ICON_ORIGIN := Vector2(19, 3) # 高亮图集相对底板的对齐偏移
const SLIDER_X: Array[float] = [3.0, 44.0, 84.0, 124.0] # 四档选中框的停靠位置
const MOVE_SECONDS: float = 0.20 # 选中框平滑滑动的时长
const FADE_SECONDS: float = 0.16 # 旧图标熄灭、新图标亮起的时长
const SLOT_WIDTH: float = 41.0 # 原生164像素底板四等分的鼠标命中宽度

var buttons: Array[Button] = []
var highlights: Array[TextureRect] = []
var slider: TextureRect
var selected_slot: int = -1
var _transition: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = TRACK.get_size()
	custom_minimum_size = size
	var background := TextureRect.new()
	background.texture = TRACK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	slider = TextureRect.new()
	slider.texture = SLIDER
	slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slider)
	for index: int in 4:
		var atlas := AtlasTexture.new()
		atlas.atlas = HIGHLIGHTS
		atlas.region = ICON_REGIONS[index]
		var highlight := TextureRect.new()
		highlight.texture = atlas
		highlight.position = ICON_ORIGIN + ICON_REGIONS[index].position
		highlight.modulate.a = 0.0
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(highlight)
		highlights.append(highlight)
		var button := Button.new()
		button.name = "PlaybackSlot%d" % index
		button.position = Vector2(index * SLOT_WIDTH, 0)
		button.size = Vector2(SLOT_WIDTH, size.y)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.tooltip_text = ["暂停战斗", "1× 速度", "2× 速度", "3× 速度"][index]
		button.pressed.connect(func() -> void: slot_selected.emit(index))
		add_child(button)
		buttons.append(button)


func sync(speed_index: int, paused: bool, animate: bool = true) -> void:
	buttons[0].tooltip_text = "继续战斗" if paused else "暂停战斗"
	var target_slot := 0 if paused else clampi(speed_index + 1, 1, 3)
	if target_slot == selected_slot:
		return
	var immediate := not animate or selected_slot < 0
	selected_slot = target_slot
	if is_instance_valid(_transition):
		_transition.kill()
	if immediate:
		slider.position.x = SLIDER_X[target_slot]
		for index: int in 4:
			highlights[index].modulate.a = 1.0 if index == target_slot else 0.0
		return
	_transition = create_tween().set_parallel(true).set_ignore_time_scale(true)
	_transition.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition.tween_property(slider, "position:x", SLIDER_X[target_slot], MOVE_SECONDS)
	for index: int in 4:
		_transition.tween_property(highlights[index], "modulate:a", 1.0 if index == target_slot else 0.0, FADE_SECONDS)
