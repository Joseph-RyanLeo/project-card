extends PanelContainer

## 日志悬停动画独立于战斗暂停；文字、滚动条与公式链接仍使用原有子控件。
const HOVER_SCALE: float = 2.0 # 鼠标指向日志时，整个面板与文字放大的倍率
const HOVER_SECONDS: float = 0.22 # 日志放大或缩回原尺寸的动画时长
var _hovered: bool = false
var _hover_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visibility_changed.connect(_reset_if_hidden)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	# 按动画中的实际范围判断，移到文字、滚动条或放大后新增的区域不会闪缩。
	var pointer := get_global_transform_with_canvas().affine_inverse() * get_viewport().get_mouse_position()
	var hovered := Rect2(Vector2.ZERO, size).has_point(pointer)
	if hovered == _hovered:
		return
	_hovered = hovered
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	var target := Vector2.ONE * (HOVER_SCALE if hovered else 1.0)
	_hover_tween = create_tween()
	_hover_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "scale", target, HOVER_SECONDS)


func _reset_if_hidden() -> void:
	if is_visible_in_tree():
		return
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hovered = false
	scale = Vector2.ONE
