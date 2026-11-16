extends RefCounted

## 每组面索引按外法线绕序排列。几何只提供骰体，点数仍由事件先结算。
const PHI := 1.61803398875
const INV_PHI := 1.0 / PHI
const D10_POLE_HEIGHT := 1.20 # 十面骰两端的高度，相对于一圈顶点的半径
const D10_CORNER_CUT := 0.16 # 十面骰从每个尖角沿边切去的比例
const CUBE := [
	Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, -1), Vector3(-1, 1, 1),
	Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(1, 1, -1), Vector3(1, 1, 1),
]


static func build(sides: int) -> Dictionary:
	var vertices := PackedVector3Array()
	var faces: Array = []
	match sides:
		4: # 正四面体
			vertices = PackedVector3Array([Vector3(1, 1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1)])
			faces = [[0, 1, 2], [0, 2, 3], [0, 3, 1], [1, 3, 2]]
		6: # 正六面体。相对面相加为 7。
			vertices = PackedVector3Array(CUBE)
			faces = [[0, 1, 3, 2], [0, 2, 6, 4], [0, 4, 5, 1], [2, 3, 7, 6], [1, 5, 7, 3], [4, 6, 7, 5]]
		8: # 正八面体
			vertices = PackedVector3Array([Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD])
			faces = [[0, 2, 4], [0, 3, 5], [0, 4, 3], [0, 5, 2], [1, 2, 5], [1, 3, 4], [1, 4, 2], [1, 5, 3]]
		10: # 五角偏方面体：两个尖顶加一圈上下交错的顶点，每个面都是平面风筝形。
			var ring_angle := TAU / 10.0
			var ring_cos := cos(ring_angle)
			var ring_height := D10_POLE_HEIGHT * (1.0 - ring_cos) / (1.0 + ring_cos)
			vertices.append(Vector3(0, 0, D10_POLE_HEIGHT))
			vertices.append(Vector3(0, 0, -D10_POLE_HEIGHT))
			for i: int in 10:
				vertices.append(Vector3(cos(i * ring_angle), sin(i * ring_angle), ring_height if i % 2 == 0 else -ring_height))
			for i: int in range(0, 10, 2):
				faces.append([0, 2 + i, 2 + (i + 1) % 10, 2 + (i + 2) % 10])
				faces.append([1, 2 + (i + 1) % 10, 2 + i, 2 + posmod(i - 1, 10)])
		12: # 正十二面体
			vertices = PackedVector3Array(CUBE)
			vertices.append_array(_golden_vertices(INV_PHI))
			faces = [
				[0, 8, 4, 15, 9], [0, 9, 1, 16, 10], [0, 10, 2, 14, 8], [1, 9, 15, 5, 11],
				[1, 11, 17, 3, 16], [2, 10, 16, 3, 12], [2, 12, 18, 6, 14], [3, 17, 7, 18, 12],
				[4, 8, 14, 6, 13], [4, 13, 19, 5, 15], [5, 19, 7, 17, 11], [6, 18, 7, 19, 13],
			]
		20: # 正二十面体
			vertices = _golden_vertices(1.0)
			faces = [
				[0, 1, 2], [0, 2, 6], [0, 5, 7], [0, 6, 5], [0, 7, 1],
				[1, 3, 8], [1, 7, 3], [1, 8, 2], [2, 4, 6], [2, 8, 4],
				[3, 7, 11], [3, 9, 8], [3, 11, 9], [4, 8, 9], [4, 9, 10],
				[4, 10, 6], [5, 6, 10], [5, 10, 11], [5, 11, 7], [9, 11, 10],
			]
		_:
			return {}
	var mesh := _cut_corners(vertices, faces) if sides == 10 else {"vertices": vertices, "faces": faces, "caps": []}
	vertices = mesh.vertices
	var radius := 0.0
	for vertex: Vector3 in vertices:
		radius = maxf(radius, vertex.length())
	for i: int in vertices.size():
		vertices[i] /= radius
	mesh.vertices = vertices
	return mesh


static func round_edges(
	vertices: PackedVector3Array, faces: Array, face_normals: PackedVector3Array, radius: float, segments: int
) -> Dictionary:
	var edge_faces := {}
	var corner_normals := PackedVector3Array()
	corner_normals.resize(vertices.size())
	for i: int in faces.size():
		var face: Array = faces[i]
		for j: int in face.size():
			var a: int = face[j]
			var b: int = face[(j + 1) % face.size()]
			var edge := Vector2i(mini(a, b), maxi(a, b))
			if not edge_faces.has(edge): edge_faces[edge] = []
			edge_faces[edge].append(i)
			corner_normals[a] += face_normals[i]
	var mesh := {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "triangle_normals": PackedVector3Array()}
	for edge: Vector2i in edge_faces:
		var neighbors: Array = edge_faces[edge]
		if neighbors.size() != 2: continue
		var first := face_normals[neighbors[0]]
		var last := face_normals[neighbors[1]]
		var a := vertices[edge.x] * (1.0 - radius)
		var b := vertices[edge.y] * (1.0 - radius)
		var cap_a := corner_normals[edge.x].normalized()
		var cap_b := corner_normals[edge.y].normalized()
		var before := first
		for step: int in range(1, segments + 1):
			# 边上两块面的法线之间走圆弧，两端用同一圈采样补齐球面圆角。
			var after := last if step == segments else first.slerp(last, float(step) / segments)
			_add_rounded_triangle(mesh, [a, b, b], [before, before, after], radius)
			_add_rounded_triangle(mesh, [a, b, a], [before, after, after], radius)
			_add_rounded_triangle(mesh, [a, a, a], [cap_a, before, after], radius)
			_add_rounded_triangle(mesh, [b, b, b], [cap_b, before, after], radius)
			before = after
	return mesh


static func _add_rounded_triangle(mesh: Dictionary, corners: Array[Vector3], normals: Array[Vector3], radius: float) -> void:
	var a := corners[0] + normals[0] * radius
	var b := corners[1] + normals[1] * radius
	var c := corners[2] + normals[2] * radius
	var normal := (b - a).cross(c - a).normalized()
	if normal.dot(normals[0] + normals[1] + normals[2]) < 0.0: normal = -normal
	mesh.vertices.append(a)
	mesh.vertices.append(b)
	mesh.vertices.append(c)
	mesh.normals.append_array(PackedVector3Array(normals))
	mesh.triangle_normals.append(normal)


static func _cut_corners(vertices: PackedVector3Array, faces: Array) -> Dictionary:
	var cut_vertices := PackedVector3Array()
	var cut_faces: Array = []
	var corners := {}
	var cap_links: Array[Dictionary] = []
	for i: int in vertices.size():
		cap_links.append({})
	for face: Array in faces:
		var cut_face: Array[int] = []
		for i: int in face.size():
			var corner: int = face[i]
			var prev: int = face[posmod(i - 1, face.size())]
			var next: int = face[(i + 1) % face.size()]
			for neighbor: int in [prev, next]:
				var edge := Vector2i(corner, neighbor)
				if not corners.has(edge):
					corners[edge] = cut_vertices.size()
					cut_vertices.append(vertices[corner].lerp(vertices[neighbor], D10_CORNER_CUT))
				cut_face.append(corners[edge])
			# 切角面与主面共用这条边，沿相反方向连接，保持外法线绕序。
			cap_links[corner][cut_face[-1]] = cut_face[-2]
		cut_faces.append(cut_face)
	var caps: Array = []
	for links: Dictionary in cap_links:
		var cap: Array[int] = []
		var index: int = links.keys()[0]
		for i: int in links.size():
			cap.append(index)
			index = links[index]
		caps.append(cap)
	return {"vertices": cut_vertices, "faces": cut_faces, "caps": caps}


static func _golden_vertices(short_axis: float) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	for a: float in [-short_axis, short_axis]:
		for b: float in [-PHI, PHI]:
			vertices.append(Vector3(0, a, b))
			vertices.append(Vector3(a, b, 0))
			vertices.append(Vector3(b, 0, a))
	return vertices
