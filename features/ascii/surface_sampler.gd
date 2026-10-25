@tool
class_name SurfaceSampler
extends RefCounted
## 网格表面采样（对齐 threejs sampleSurface）：按面积加权 + 空间哈希去重。


static func sample_mesh(mesh: Mesh, spacing: float = 0.35, seed: int = 1) -> Dictionary:
	## 返回 { "positions": PackedVector3Array, "normals": PackedVector3Array }
	return sample_arrays(_mesh_arrays(mesh), spacing, seed)


# 后台任务只接收主线程快照，不访问 Mesh 或场景树。
static func sample_arrays(arrays: Array, spacing: float, seed: int) -> Dictionary:
	spacing = maxf(spacing, 0.02)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	if arrays.is_empty():
		return {"positions": PackedVector3Array(), "normals": PackedVector3Array()}

	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	if verts.is_empty():
		return {"positions": PackedVector3Array(), "normals": PackedVector3Array()}

	if norms.is_empty():
		norms = PackedVector3Array()
		norms.resize(verts.size())
		for i in verts.size():
			norms[i] = Vector3.UP

	var tris: Array[PackedInt32Array] = []
	if indices.is_empty():
		for i in range(0, verts.size() - 2, 3):
			tris.append(PackedInt32Array([i, i + 1, i + 2]))
	else:
		for i in range(0, indices.size() - 2, 3):
			tris.append(PackedInt32Array([indices[i], indices[i + 1], indices[i + 2]]))

	var areas: PackedFloat32Array = PackedFloat32Array()
	areas.resize(tris.size())
	var total_area := 0.0
	for t in range(tris.size()):
		var a: Vector3 = verts[tris[t][0]]
		var b: Vector3 = verts[tris[t][1]]
		var c: Vector3 = verts[tris[t][2]]
		var area: float = (b - a).cross(c - a).length() * 0.5
		areas[t] = area
		total_area += area

	if total_area <= 0.0:
		return {"positions": PackedVector3Array(), "normals": PackedVector3Array()}

	var target := int(ceil(total_area / maxf(spacing * spacing, 0.0001) * 2.2))
	target = clampi(target, 1, 200000)

	# Build once; each candidate then selects a triangle in O(log triangles).
	var cumulative := PackedFloat64Array()
	cumulative.resize(areas.size())
	var accumulated := 0.0
	for i in areas.size():
		accumulated += areas[i]
		cumulative[i] = accumulated

	var cell := spacing
	var hash_map: Dictionary = {}
	var positions := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var min2 := spacing * spacing * 0.8

	for _i in target:
		var tri_i := _pick_triangle(rng, cumulative, total_area)
		var i0: int = tris[tri_i][0]
		var i1: int = tris[tri_i][1]
		var i2: int = tris[tri_i][2]
		var bary := _random_barycentric(rng)
		var p: Vector3 = verts[i0] * bary.x + verts[i1] * bary.y + verts[i2] * bary.z
		var n: Vector3 = (norms[i0] * bary.x + norms[i1] * bary.y + norms[i2] * bary.z).normalized()
		if n.length_squared() < 0.01:
			n = (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0]).normalized()

		var cx := int(floor(p.x / cell))
		var cy := int(floor(p.y / cell))
		var cz := int(floor(p.z / cell))
		var ok := true
		for dx in range(-1, 2):
			if not ok:
				break
			for dy in range(-1, 2):
				if not ok:
					break
				for dz in range(-1, 2):
					var key := Vector3i(cx + dx, cy + dy, cz + dz)
					if not hash_map.has(key):
						continue
					for q in hash_map[key]:
						if p.distance_squared_to(q) < min2:
							ok = false
							break
					if not ok:
						break
		if not ok:
			continue

		var home := Vector3i(cx, cy, cz)
		if not hash_map.has(home):
			hash_map[home] = []
		hash_map[home].append(p)
		positions.append(p)
		out_normals.append(n)

	return {"positions": positions, "normals": out_normals}


## 特征棱等距采样。返回 { "positions": PackedVector3Array, "directions": PackedVector3Array }
## 棱边下限低于表面，以便轮廓可密于填充。
static func sample_edges(arrays: Array, step: float = 0.2, threshold_deg: float = 25.0) -> Dictionary:
	step = maxf(step, 0.008)
	if arrays.is_empty():
		return {"positions": PackedVector3Array(), "directions": PackedVector3Array()}

	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if verts.is_empty():
		return {"positions": PackedVector3Array(), "directions": PackedVector3Array()}

	var tris: Array[PackedInt32Array] = []
	if indices.is_empty():
		for i in range(0, verts.size() - 2, 3):
			tris.append(PackedInt32Array([i, i + 1, i + 2]))
	else:
		for i in range(0, indices.size() - 2, 3):
			tris.append(PackedInt32Array([indices[i], indices[i + 1], indices[i + 2]]))

	# edge key (min,max) -> list of triangle face normals
	var edge_faces: Dictionary = {}
	for t in tris:
		var a: Vector3 = verts[t[0]]
		var b: Vector3 = verts[t[1]]
		var c: Vector3 = verts[t[2]]
		var fn: Vector3 = (b - a).cross(c - a)
		if fn.length_squared() < 1e-12:
			continue
		fn = fn.normalized()
		_edge_faces_add(edge_faces, t[0], t[1], fn)
		_edge_faces_add(edge_faces, t[1], t[2], fn)
		_edge_faces_add(edge_faces, t[2], t[0], fn)

	var cos_thresh := cos(deg_to_rad(threshold_deg))
	var pos := PackedVector3Array()
	var dir := PackedVector3Array()
	for key in edge_faces:
		var faces: Array = edge_faces[key]
		var keep := false
		if faces.size() == 1:
			keep = true
		elif faces.size() >= 2:
			var n0: Vector3 = faces[0]
			var n1: Vector3 = faces[1]
			# 夹角越大 dot 越小；超过阈值则保留
			keep = n0.dot(n1) < cos_thresh
		if not keep:
			continue
		var i0: int = key.x
		var i1: int = key.y
		var a: Vector3 = verts[i0]
		var b: Vector3 = verts[i1]
		var d: Vector3 = b - a
		var length := d.length()
		if length < 1e-5:
			continue
		d /= length
		var n := maxi(1, int(round(length / step)))
		for k in range(n + 1):
			var t := float(k) / float(n)
			pos.append(a.lerp(b, t))
			dir.append(d)

	return _dedupe_edges(pos, dir, step * 0.45)


static func sample_mesh_edges(mesh: Mesh, step: float = 0.2, threshold_deg: float = 25.0) -> Dictionary:
	return sample_edges(_mesh_arrays(mesh), step, threshold_deg)


static func _edge_faces_add(edge_faces: Dictionary, i0: int, i1: int, fn: Vector3) -> void:
	var key := Vector2i(mini(i0, i1), maxi(i0, i1))
	if not edge_faces.has(key):
		edge_faces[key] = []
	edge_faces[key].append(fn)


static func _dedupe_edges(pos: PackedVector3Array, dir: PackedVector3Array, eps: float) -> Dictionary:
	eps = maxf(eps, 1e-4)
	var seen: Dictionary = {}
	var out_pos := PackedVector3Array()
	var out_dir := PackedVector3Array()
	for i in pos.size():
		var p := pos[i]
		var k := Vector3i(
			int(round(p.x / eps)),
			int(round(p.y / eps)),
			int(round(p.z / eps))
		)
		if seen.has(k):
			continue
		seen[k] = true
		out_pos.append(p)
		out_dir.append(dir[i])
	return {"positions": out_pos, "directions": out_dir}


static func _mesh_arrays(mesh: Mesh) -> Array:
	if mesh == null:
		return []
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for surface in mesh.get_surface_count():
		if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var offset := vertices.size()
		vertices.append_array(points)
		if ns.size() != points.size():
			ns.resize(points.size())
			ns.fill(Vector3.ZERO)
		normals.append_array(ns)
		if ids.is_empty():
			for i in range(0, points.size() - 2, 3):
				indices.append_array(PackedInt32Array([offset + i, offset + i + 1, offset + i + 2]))
		else:
			for i in ids:
				indices.append(offset + i)
	if indices.is_empty():
		return []
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = vertices
	result[Mesh.ARRAY_NORMAL] = normals
	result[Mesh.ARRAY_INDEX] = indices
	return result

static func _pick_triangle(rng: RandomNumberGenerator, cumulative: PackedFloat64Array, total: float) -> int:
	var r := rng.randf() * total
	var low := 0
	var high := cumulative.size() - 1
	while low < high:
		var mid := (low + high) >> 1
		if r <= cumulative[mid]:
			high = mid
		else:
			low = mid + 1
	return low


static func _random_barycentric(rng: RandomNumberGenerator) -> Vector3:
	var u := rng.randf()
	var v := rng.randf()
	if u + v > 1.0:
		u = 1.0 - u
		v = 1.0 - v
	var w := 1.0 - u - v
	return Vector3(u, v, w)
