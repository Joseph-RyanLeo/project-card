extends RefCounted

## 事件骰和查看器共用顶点、骰面编号和二维投影。
const Geometry = preload("res://scripts/ui/event_dice_geometry.gd")
const POINT_MARK_HEIGHT := 22.0 # 基准骰面数字高度，较小的面会按空间缩放
const CORNER_MARK_HEIGHT := 10.0 # 基准 D4 顶角点数高度
const FACE_MARK_DIAMETER := 1.9 # 数字对角线最多占骰面内切圆半径的倍数
const DIGIT_MARK_WIDTH := 0.72 # 6 和 9 的下划线占数字宽度的比例
const LIGHT_DIRECTION := Vector3(-0.42, -0.63, 0.65) # 控制骰面明暗的入射方向
const GOLD := Color("dcb77d") # 骰体边线色
const INK := Color("221829") # 投掷说明文字色
const SHADE := Color("68485f") # 背光面的底色
const LIT := Color("be8e9b") # 受光面的底色
const DESIGN_RADIUS := 46.0 # 原始线宽和字号所用的骰体半径
const ROUND_RADIUS := 0.10 # 圆角半径占骰体半径的比例
const ROUND_SEGMENTS := 6 # 每条圆边法线之间的圆弧分段数

var sides: int
var vertices := PackedVector3Array()
var faces: Array[Dictionary] = []
var _rounding: Dictionary


func set_sides(side_count: int) -> void:
	sides = side_count
	var mesh := Geometry.build(sides)
	vertices = mesh.get("vertices", PackedVector3Array())
	faces.clear()
	_rounding.clear()
	if mesh.is_empty(): return
	var all_faces: Array = mesh.faces + mesh.caps
	var normals := PackedVector3Array()
	for indices: Array in all_faces:
		var center := Vector3.ZERO
		for index: int in indices:
			center += vertices[index]
		center /= indices.size()
		var first := vertices[indices[0]]
		var second := vertices[indices[1]]
		var normal := (second - first).cross(vertices[indices[2]] - first).normalized()
		normals.append(normal)
		# 方形的首边与 D10 主面切过的首角都用边中点确定数字的上方。
		var top := (first + second) * 0.5 if sides in [6, 10] else first
		var down := (center - top).normalized()
		var radius := INF
		for i: int in indices.size():
			var a := vertices[indices[i]]
			var edge := vertices[indices[(i + 1) % indices.size()]] - a
			radius = minf(radius, edge.normalized().cross(center - a).length())
		faces.append({
			"indices": indices,
			"center": center * (1.0 - ROUND_RADIUS) + normal * ROUND_RADIUS,
			"axes": Basis(down.cross(normal), down, normal),
			"radius": radius * (1.0 - ROUND_RADIUS),
		})
	_rounding = Geometry.round_edges(vertices, all_faces, normals, ROUND_RADIUS, ROUND_SEGMENTS)


func support_height(rotation: Basis, direction: Vector3) -> float:
	var lowest := 0.0
	for vertex: Vector3 in vertices:
		lowest = minf(lowest, (rotation * vertex).dot(direction))
	# 圆角骰体是缩小的原骰体加一层圆边，支撑点也按同一尺寸计算。
	return lowest * (1.0 - ROUND_RADIUS) - ROUND_RADIUS


func draw_on(canvas: Control, center: Vector2, rotation: Basis, radius: float, highlighted_face: int = 0) -> void:
	var detail_scale := radius / DESIGN_RADIUS
	var edge_width := 1.3 * detail_scale # 骰面细线随查看倍率缩放
	var projected := PackedVector2Array()
	for vertex: Vector3 in vertices:
		projected.append(center + _xy(rotation * vertex) * (radius * (1.0 - ROUND_RADIUS)))
	_draw_rounding(canvas, center, rotation, radius)
	for i: int in faces.size():
		var face := faces[i]
		var axes: Basis = rotation * (face.axes as Basis)
		if axes.z.z <= 0.001: continue # 凸骰体只需要绘制面向镜头的面。
		var points := PackedVector2Array()
		var face_offset := _xy(axes.z) * (radius * ROUND_RADIUS)
		for index: int in face.indices:
			points.append(projected[index] + face_offset)
		var brightness := _brightness(axes.z)
		var color := SHADE.lerp(LIT, brightness)
		if sides != 4 and i + 1 == highlighted_face:
			color = color.lerp(GOLD, 0.24)
		var edge_color := GOLD.lerp(SHADE, 0.36)
		var face_center: Vector3 = face.center
		# 边线只画在平面内部，接角不会伸出真实圆边。
		canvas.draw_colored_polygon(points, edge_color)
		var projected_center := center + _xy(rotation * face_center) * radius
		var inset := minf(edge_width * 0.5 / (float(face.radius) * radius), 0.35)
		for index: int in points.size():
			points[index] = points[index].lerp(projected_center, inset)
		canvas.draw_colored_polygon(points, color)
		if i >= sides or axes.z.z < 0.24: continue # 切角面不编号，掠视角只保留边线。
		if sides == 4:
			for index: int in face.indices:
				var vertex := vertices[index] * (1.0 - ROUND_RADIUS) + (face.axes as Basis).z * ROUND_RADIUS
				var down := (rotation * (face_center - vertex)).normalized()
				var mark := vertex.lerp(face_center, 0.47)
				var corner_axes := Basis(down.cross(axes.z), down, axes.z)
				var placement := Transform2D(_xy(corner_axes.x), _xy(corner_axes.y), center + _xy(rotation * mark) * radius)
				draw_number(canvas, str(index + 1), placement, CORNER_MARK_HEIGHT * detail_scale)
		else:
			var placement := Transform2D(_xy(axes.x), _xy(axes.y), projected_center)
			var underlined := sides >= 10 and i + 1 in [6, 9]
			draw_number(canvas, str(i + 1), placement, POINT_MARK_HEIGHT * detail_scale, float(face.radius) * radius, underlined)


func _draw_rounding(canvas: Control, center: Vector2, rotation: Basis, radius: float) -> void:
	if _rounding.is_empty(): return
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var triangle_normals: PackedVector3Array = _rounding.triangle_normals
	var round_vertices: PackedVector3Array = _rounding.vertices
	var round_normals: PackedVector3Array = _rounding.normals
	for triangle: int in triangle_normals.size():
		if (rotation * triangle_normals[triangle]).z <= 0.001: continue
		for i: int in range(triangle * 3, triangle * 3 + 3):
			indices.append(points.size())
			points.append(center + _xy(rotation * round_vertices[i]) * radius)
			colors.append(SHADE.lerp(LIT, _brightness(rotation * round_normals[i])))
	if not indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, points, colors)


func _brightness(normal: Vector3) -> float:
	return clampf(0.22 + normal.dot(LIGHT_DIRECTION) * 0.78, 0.0, 1.0)


static func draw_number(canvas: CanvasItem, value: String, placement: Transform2D, height: float, face_radius: float = INF, underlined: bool = false) -> void:
	var glyph_size := RuneNumberDisplay.measure_large_digits(value)
	var fit_size := glyph_size + Vector2(0, 4 if underlined else 0) # 为 6 和 9 下方的记号留出空间
	var glyph_scale := minf(height / glyph_size.y, face_radius * FACE_MARK_DIAMETER / fit_size.length())
	# 缩放投影坐标轴，图集字形就会随骰面一起转动和缩短。
	canvas.draw_set_transform_matrix(Transform2D(placement.x * glyph_scale, placement.y * glyph_scale, placement.origin))
	RuneNumberDisplay.draw_large_digits(canvas, value, -glyph_size * 0.5)
	if underlined:
		var half_width := roundf(glyph_size.x * DIGIT_MARK_WIDTH * 0.5)
		var line := Rect2(-half_width, glyph_size.y * 0.5 + 1.0, half_width * 2.0, 1.0)
		canvas.draw_rect(line.grow(1.0), Color("090909"))
		canvas.draw_rect(line, Color.WHITE)
	canvas.draw_set_transform(Vector2.ZERO)


func _xy(value: Vector3) -> Vector2:
	return Vector2(value.x, value.y)
