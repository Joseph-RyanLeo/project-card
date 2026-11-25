extends RefCounted

const MAX_CURVATURE := Vector2(0.0224, 0.0322) # 满强度的四角内弯相当于旧版 14%（0.16、0.23 × 0.14）


static func to_source(point: Vector2, frame_size: Vector2, curvature: Vector2) -> Vector2:
	# 与 crt_display.gdshader 共用屏幕到原画面的采样公式，四角外侧允许落在画布外。
	var centered := point / frame_size * 2.0 - Vector2.ONE
	var across := Vector2(centered.y, centered.x)
	return (centered * (Vector2.ONE + curvature * across * across) + Vector2.ONE) * 0.5 * frame_size


static func viewport_mouse(viewport: Viewport) -> Vector2:
	var window := viewport.get_window()
	var shell := viewport.get_tree().get_first_node_in_group(&"game_display_shell")
	if shell == null or shell._crt_curvature == Vector2.ZERO or window != shell.get_viewport() or not shell.is_visible_in_tree():
		return viewport.get_mouse_position()
	# 节点主动读取鼠标位置时，Godot 仍会查询实体指针。先在窗口换算，再回到节点所在画布。
	var source := to_source(window.get_mouse_position(), window.get_visible_rect().size, shell._crt_curvature)
	if viewport == window: return source
	var window_to_viewport := viewport.get_screen_transform().affine_inverse() * window.get_screen_transform()
	return window_to_viewport * source


static func local_mouse(item: CanvasItem) -> Vector2:
	return item.get_global_transform_with_canvas().affine_inverse() * viewport_mouse(item.get_viewport())


static func canvas_mouse(item: CanvasItem) -> Vector2:
	return item.get_canvas_transform().affine_inverse() * viewport_mouse(item.get_viewport())
