class_name GameDisplay
extends Control

## 固定 1280×720 内部渲染，再把结果一次缩放到目标窗口。
## Main、DesignCanvas 和运行时素材统一使用 1×逻辑尺寸。

enum DisplayMode {
	WINDOW_720P,
	WINDOW_1080P,
	WINDOW_2K,
	ADAPTIVE_FULLSCREEN,
}

const DESIGN_SIZE := Vector2i(1280, 720)
const INTERNAL_RENDER_SIZE := Vector2i(1280, 720) # 1×内部渲染画幅
const INTEGER_SCALE_EPSILON: float = 0.0001 # 判断客户区是否为等比整数倍率时允许的浮点误差
const CARD_ART_TUNER_SCENE: PackedScene = preload("res://scenes/tools/CardArtTuner.tscn")
const BATTLE_LAB_SCENE: PackedScene = preload("res://scenes/tools/BattleLab.tscn")
const ATTACK_EFFECT_LAB_SCENE: PackedScene = preload("res://scenes/tools/AttackEffectLab.tscn")
const WINDOW_MODE_TRANSITION_MAX_FRAMES: int = 60 # 等待 macOS 退出全屏的最长帧数
const WINDOW_SIZE_BY_MODE := {
	DisplayMode.WINDOW_720P: Vector2i(1280, 720),
	DisplayMode.WINDOW_1080P: Vector2i(1920, 1080),
	DisplayMode.WINDOW_2K: Vector2i(2560, 1440),
}
const DISPLAY_MODE_LABELS := {
	DisplayMode.WINDOW_720P: "720p 窗口",
	DisplayMode.WINDOW_1080P: "1080p 窗口",
	DisplayMode.WINDOW_2K: "2K 窗口",
	DisplayMode.ADAPTIVE_FULLSCREEN: "自适应全屏",
}

@onready var internal_viewport: SubViewport = %InternalViewport
@onready var design_canvas: Control = %DesignCanvas
@onready var render_container: SubViewportContainer = $RenderContainer
@onready var main_screen: Control = $RenderContainer/InternalViewport/DesignCanvas/Main
@onready var display_mode_option: OptionButton = %DisplayModeOption
@onready var display_mode_feedback: Label = %DisplayModeFeedback

var current_display_mode: DisplayMode = DisplayMode.WINDOW_1080P
var _window_resize_request_serial: int = 0
var _window_transition_in_progress: bool = false
var _card_art_tuner: CardArtTuner
var _battle_lab: BattleLab
var _attack_effect_lab: AttackEffectLab


func _enter_tree() -> void:
	# Main 通过这个分组找到固定虚拟画布的显示壳。
	add_to_group(&"game_display_shell")


func _ready() -> void:
	design_canvas.size = Vector2(DESIGN_SIZE)
	design_canvas.scale = Vector2.ONE
	_layout_render_container()
	if not resized.is_connected(_on_root_control_resized):
		resized.connect(_on_root_control_resized)
	_setup_display_mode_option()
	var window := get_window()
	if not window.size_changed.is_connected(_on_root_window_size_changed):
		window.size_changed.connect(_on_root_window_size_changed)
	if DisplayServer.get_name() == "headless":
		apply_display_mode(DisplayMode.WINDOW_1080P)
	elif window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		# 若系统或启动参数已经把窗口设为全屏，菜单必须反映真实状态。
		current_display_mode = DisplayMode.ADAPTIVE_FULLSCREEN
		_select_option_without_signal(current_display_mode)
	else:
		apply_display_mode(DisplayMode.WINDOW_1080P)


func apply_display_mode(mode: DisplayMode) -> void:
	current_display_mode = mode
	_window_resize_request_serial += 1
	_window_transition_in_progress = true
	_select_option_without_signal(mode)
	if DisplayServer.get_name() == "headless":
		_window_transition_in_progress = false
		return
	var window := get_window()
	window.unresizable = true
	if mode == DisplayMode.ADAPTIVE_FULLSCREEN:
		display_mode_feedback.visible = false
		window.mode = Window.MODE_FULLSCREEN
		call_deferred("_verify_fullscreen_mode", _window_resize_request_serial, 0)
		return
	display_mode_feedback.visible = false
	window.mode = Window.MODE_WINDOWED
	# macOS 退出全屏是异步过程；下一帧再写窗口客户区尺寸，避免系统过渡覆盖它。
	call_deferred("_apply_windowed_size", mode, _window_resize_request_serial, 0)


func get_window_size_for_mode(mode: DisplayMode) -> Vector2i:
	return WINDOW_SIZE_BY_MODE.get(mode, Vector2i.ZERO) as Vector2i


func _setup_display_mode_option() -> void:
	display_mode_option.clear()
	for mode: DisplayMode in [
		DisplayMode.WINDOW_720P,
		DisplayMode.WINDOW_1080P,
		DisplayMode.WINDOW_2K,
		DisplayMode.ADAPTIVE_FULLSCREEN,
	]:
		display_mode_option.add_item(DISPLAY_MODE_LABELS[mode], mode)
	display_mode_option.tooltip_text = "固定窗口尺寸；窗口边缘不可拖动调整"
	display_mode_option.item_selected.connect(_on_display_mode_selected)


func _select_option_without_signal(mode: DisplayMode) -> void:
	if not is_instance_valid(display_mode_option):
		return
	for item_index: int in display_mode_option.item_count:
		if display_mode_option.get_item_id(item_index) == mode:
			display_mode_option.select(item_index)
			return


func _on_display_mode_selected(item_index: int) -> void:
	apply_display_mode(display_mode_option.get_item_id(item_index) as DisplayMode)


func _apply_windowed_size(mode: DisplayMode, request_serial: int, attempt: int) -> void:
	if current_display_mode != mode or request_serial != _window_resize_request_serial:
		return
	var window := get_window()
	if window.mode != Window.MODE_WINDOWED:
		if attempt < WINDOW_MODE_TRANSITION_MAX_FRAMES:
			call_deferred("_apply_windowed_size", mode, request_serial, attempt + 1)
		return
	window.size = WINDOW_SIZE_BY_MODE[mode]
	_window_transition_in_progress = false
	_select_option_without_signal(mode)
	call_deferred("_center_window")


func _verify_fullscreen_mode(request_serial: int, attempt: int) -> void:
	if request_serial != _window_resize_request_serial:
		return
	var window := get_window()
	if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		_window_transition_in_progress = false
		current_display_mode = DisplayMode.ADAPTIVE_FULLSCREEN
		_select_option_without_signal(current_display_mode)
		display_mode_feedback.visible = false
		return
	if attempt < WINDOW_MODE_TRANSITION_MAX_FRAMES:
		call_deferred("_verify_fullscreen_mode", request_serial, attempt + 1)
		return
	# 嵌入式游戏无法控制宿主编辑器窗口；恢复真实窗口档位并明确提示原因。
	_window_transition_in_progress = false
	current_display_mode = _get_windowed_mode_for_size(window.size)
	_select_option_without_signal(current_display_mode)
	display_mode_feedback.text = "全屏失败：请重启 Godot 载入原生窗口设置"
	display_mode_feedback.visible = true


func _on_root_window_size_changed() -> void:
	_layout_render_container()
	if _window_transition_in_progress or DisplayServer.get_name() == "headless":
		return
	call_deferred("_sync_display_mode_from_actual_window")


func _on_root_control_resized() -> void:
	_layout_render_container()


func _layout_render_container() -> void:
	if not is_instance_valid(render_container):
		return
	# 根窗口使用 disabled stretch，因此这里的 size 就是真实客户区像素尺寸；
	# 只把固定 1×内部纹理一次性缩放到客户区。等比整数倍率保留硬像素，
	# 1080p 等非整数倍率改用线性过滤，避免同一逻辑像素宽度忽大忽小。
	render_container.size = Vector2(INTERNAL_RENDER_SIZE)
	var render_scale := Vector2(
		size.x / float(INTERNAL_RENDER_SIZE.x),
		size.y / float(INTERNAL_RENDER_SIZE.y)
	)
	render_container.scale = render_scale
	render_container.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if _is_uniform_integer_scale(render_scale)
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)


static func _is_uniform_integer_scale(render_scale: Vector2) -> bool:
	if render_scale.x <= 0.0 or render_scale.y <= 0.0:
		return false
	return (
		absf(render_scale.x - render_scale.y) <= INTEGER_SCALE_EPSILON
		and absf(render_scale.x - roundf(render_scale.x))
		<= INTEGER_SCALE_EPSILON
		and absf(render_scale.y - roundf(render_scale.y))
		<= INTEGER_SCALE_EPSILON
	)


func _sync_display_mode_from_actual_window() -> void:
	if _window_transition_in_progress:
		return
	var window := get_window()
	current_display_mode = (
		DisplayMode.ADAPTIVE_FULLSCREEN
		if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
		else _get_windowed_mode_for_size(window.size)
	)
	_select_option_without_signal(current_display_mode)


func open_card_art_tuner() -> void:
	if is_instance_valid(_card_art_tuner):
		return
	_card_art_tuner = CARD_ART_TUNER_SCENE.instantiate() as CardArtTuner
	_card_art_tuner.name = "CardArtTuner"
	design_canvas.add_child(_card_art_tuner)
	_card_art_tuner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_screen.visible = false


func close_card_art_tuner() -> void:
	if is_instance_valid(_card_art_tuner):
		_card_art_tuner.queue_free()
	_card_art_tuner = null
	main_screen.visible = true


func is_card_art_tuner_open() -> bool:
	return is_instance_valid(_card_art_tuner)


func open_battle_lab() -> void:
	if is_instance_valid(_battle_lab):
		return
	_battle_lab = BATTLE_LAB_SCENE.instantiate() as BattleLab
	_battle_lab.name = "BattleLab"
	design_canvas.add_child(_battle_lab)
	_battle_lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_lab.close_requested.connect(close_battle_lab)
	main_screen.visible = false


func close_battle_lab() -> void:
	if is_instance_valid(_battle_lab):
		_battle_lab.queue_free()
	_battle_lab = null
	main_screen.visible = true


func is_battle_lab_open() -> bool:
	return is_instance_valid(_battle_lab)


func open_attack_effect_lab() -> void:
	if is_instance_valid(_attack_effect_lab):
		return
	_attack_effect_lab = ATTACK_EFFECT_LAB_SCENE.instantiate() as AttackEffectLab
	_attack_effect_lab.name = "AttackEffectLab"
	design_canvas.add_child(_attack_effect_lab)
	_attack_effect_lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_attack_effect_lab.close_requested.connect(close_attack_effect_lab)
	main_screen.visible = false


func close_attack_effect_lab() -> void:
	if is_instance_valid(_attack_effect_lab):
		_attack_effect_lab.queue_free()
	_attack_effect_lab = null
	main_screen.visible = true


func is_attack_effect_lab_open() -> bool:
	return is_instance_valid(_attack_effect_lab)


func _get_windowed_mode_for_size(window_size: Vector2i) -> DisplayMode:
	var closest_mode := DisplayMode.WINDOW_1080P
	var closest_distance := INF
	for mode: DisplayMode in [
		DisplayMode.WINDOW_720P,
		DisplayMode.WINDOW_1080P,
		DisplayMode.WINDOW_2K,
	]:
		var distance := Vector2(window_size).distance_squared_to(
			Vector2(WINDOW_SIZE_BY_MODE[mode])
		)
		if distance < closest_distance:
			closest_distance = distance
			closest_mode = mode
	return closest_mode


func _center_window() -> void:
	var window := get_window()
	if window.mode != Window.MODE_WINDOWED:
		return
	var usable_rect := DisplayServer.screen_get_usable_rect(window.current_screen)
	var centered_offset := (usable_rect.size - window.size) / 2
	window.position = usable_rect.position + Vector2i(
		maxi(centered_offset.x, 0),
		maxi(centered_offset.y, 0)
	)
