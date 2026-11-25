class_name CollectionPageCurl
extends Control

## 活动纸页正反面由卡位或菜单合成一帧；随后只更新沿书脊弯曲的网格。
const STRIPS := 28 # 从书脊到纸边的网格分片数
const CURL_RADIANS := 1.15 # 纸张抬起时，纸边和近书脊处的最大弯曲角差
const TOP_LIFT := 0.070 # 深度折算到纸页上沿抬升的比例
const BOTTOM_LIFT := 0.018 # 纸页下沿抬升的比例，避免盖住底部纸叠
const SHADOW_WIDTH := 46.0 # 纸页活动边的最大投影宽度
const SHADOW_ALPHA := 0.29 # 纸页最高处的投影峰值透明度
const PAGE_SHADE := 0.28 # 翻起的纸面最大压暗幅度
const LEAF_DELAY := 0.16 # 相邻纸张开始翻动的间隔，占整段动画的比例
const PANEL_SHADOW := Color("352516")

var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()
var right_bookmark: TextureButton

var _page_size: Vector2
var _direction: int
var _face_count: int
var _leaf_count: int
var _faces: SubViewport


func setup(
	front: Control, back: Control, turns_forward: bool, leaves: int,
	blank_front: Texture2D, blank_back: Texture2D, menu_spread: SubViewport = null
) -> void:
	_page_size = front.size
	_direction = 1 if turns_forward else -1
	_leaf_count = leaves
	_face_count = 2 if leaves == 1 else 4
	size = _page_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_faces = SubViewport.new()
	_faces.name = "PageFaces"
	_faces.size = Vector2i(_page_size) * Vector2i(_face_count, 1)
	_faces.disable_3d = true
	_faces.transparent_bg = true
	_faces.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_faces.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_faces)
	# 作为子视口先绘制菜单，再让纸页视口从中取样。
	if menu_spread != null:
		_faces.add_child(menu_spread)
	_add_face(front, 0)
	_add_face(back, 1)
	if _face_count == 4:
		_add_face(_blank(blank_front), 2)
		_add_face(_blank(blank_back), 3)
	queue_redraw()


func _add_face(face: Control, index: int) -> void:
	_faces.add_child(face)
	face.position = Vector2(index * _page_size.x, 0)


func _blank(texture: Texture2D) -> TextureRect:
	var face := TextureRect.new()
	face.texture = texture
	face.size = _page_size
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return face


func _draw() -> void:
	if _faces == null:
		return
	var leaf_duration := 1.0 - LEAF_DELAY * (_leaf_count - 1)
	var turns := PackedFloat32Array()
	for leaf: int in _leaf_count:
		var angle := clampf((progress - leaf * LEAF_DELAY) / leaf_duration, 0.0, 1.0)
		turns.append(angle)
		_draw_shadow(angle)
	# 已翻到书脊另一侧的纸从先到后叠放，出发侧则先画叠在下面的纸。
	for leaf: int in _leaf_count:
		if turns[leaf] >= 0.5: _draw_numbered_leaf(leaf, turns[leaf])
	for leaf: int in range(_leaf_count - 1, -1, -1):
		if turns[leaf] < 0.5: _draw_numbered_leaf(leaf, turns[leaf])


func _draw_numbered_leaf(leaf: int, at: float) -> void:
	_draw_leaf(at, 0 if leaf == 0 else 2, 1 if leaf == _leaf_count - 1 else 3)


func _draw_leaf(at: float, front_index: int, back_index: int) -> void:
	var turn := PI * at
	var bend := CURL_RADIANS * sin(turn)
	var span := _page_size.x / STRIPS
	# 沿纸面逐段累加固定长度的切线，弯曲时纸张仍保持原来的长度。
	var columns := PackedVector2Array([Vector2.ZERO])
	var angles := PackedFloat32Array()
	var order: Array[int] = []
	for index: int in STRIPS:
		var offset := (index + 0.5) / STRIPS
		var angle := turn + bend * (offset * offset - 0.30)
		columns.append(columns[index] + Vector2(cos(angle), sin(angle)) * span)
		angles.append(angle)
		order.append(index)
	# 弯边和纸面在屏幕上可以重叠；靠近观察者的分片最后画。
	order.sort_custom(func(a: int, b: int) -> bool: return columns[a].y + columns[a + 1].y < columns[b].y + columns[b + 1].y)
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for strip: int in order:
		var facing := cos(angles[strip])
		var front_visible := facing >= 0.0
		var texture_index := front_index if front_visible else back_index
		var flip_texture := (front_visible and _direction < 0) or (not front_visible and _direction > 0)
		var shade := 1.0 - PAGE_SHADE * sin(turn) * (0.35 + 0.65 * (1.0 - absf(facing)))
		var first_vertex := points.size()
		for column: int in range(strip, strip + 2):
			var offset := float(column) / STRIPS
			var face_u := 1.0 - offset if flip_texture else offset
			var u := (texture_index + face_u) / _face_count
			var edge := columns[column]
			points.append(Vector2(edge.x * _direction, -edge.y * TOP_LIFT))
			points.append(Vector2(edge.x * _direction, _page_size.y - edge.y * BOTTOM_LIFT))
			uvs.append(Vector2(u, 0))
			uvs.append(Vector2(u, 1))
			colors.append(Color(shade, shade, shade))
			colors.append(Color(shade, shade, shade))
		indices.append_array(PackedInt32Array([first_vertex, first_vertex + 1, first_vertex + 2, first_vertex + 2, first_vertex + 1, first_vertex + 3]))
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors, uvs, PackedInt32Array(), PackedFloat32Array(), _faces.get_texture().get_rid())
	# 正翻时旧右页是第一张的正面，反翻时新右页是最后一张的背面。
	if right_bookmark != null and (front_index == 0 if _direction > 0 else back_index == 1):
		_draw_right_bookmark(columns[STRIPS].x * _direction)


func _draw_right_bookmark(paper_edge_x: float) -> void:
	var texture := right_bookmark.texture_normal
	var offset := right_bookmark.position - position
	var width := clampf(paper_edge_x - offset.x, 0.0, texture.get_width())
	if width <= 0.0:
		return
	var visible_size := Vector2(width, texture.get_height())
	# 固定书签坐标，只按这张纸卷边的位置改变露出的宽度。
	draw_texture_rect_region(texture, Rect2(offset, visible_size), Rect2(Vector2.ZERO, visible_size))


func _draw_shadow(at: float) -> void:
	var height := sin(PI * at)
	if height <= 0.0:
		return
	var edge := cos(PI * at) * _page_size.x * _direction
	var spread := SHADOW_WIDTH * height
	var outer := clampf(edge + spread * (1.0 if edge >= 0.0 else -1.0), -_page_size.x, _page_size.x)
	if is_equal_approx(edge, outer):
		return
	var dark := Color(PANEL_SHADOW, height * SHADOW_ALPHA)
	var clear := Color(PANEL_SHADOW, 0.0)
	draw_polygon(
		PackedVector2Array([Vector2(edge, 0), Vector2(outer, 0), Vector2(outer, _page_size.y), Vector2(edge, _page_size.y)]),
		PackedColorArray([dark, clear, clear, dark])
	)
