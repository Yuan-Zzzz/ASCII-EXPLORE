extends StaticBody3D
## 地形参数与离线模型构建；运行时直接加载已保存的网格与碰撞资源。

@export var radius: float = 48.0
@export var terrain_seed: int = 4817
@export_range(0, 100) var crater_count: int = 38

var _craters: Array[Vector4] = []


func _enter_tree() -> void:
	_make_craters()


func build_mesh() -> ArrayMesh:
	_make_craters()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 256
	sphere.rings = 128
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in vertices.size():
		var direction := vertices[i].normalized()
		vertices[i] = direction * surface_radius(direction)
		# 坑壁法线让 ASCII 明暗也呈现凹陷与坑缘。
		var tangent := direction.cross(Vector3.UP)
		if tangent.length_squared() < 0.001:
			tangent = direction.cross(Vector3.RIGHT)
		tangent = tangent.normalized()
		var bitangent := direction.cross(tangent).normalized()
		var step := 0.002
		var dx := surface_radius((direction + tangent * step).normalized()) - surface_radius((direction - tangent * step).normalized())
		var dy := surface_radius((direction + bitangent * step).normalized()) - surface_radius((direction - bitangent * step).normalized())
		normals[i] = (direction - (tangent * dx + bitangent * dy) / (2.0 * step * vertices[i].length())).normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var terrain := ArrayMesh.new()
	terrain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return terrain


func _make_craters() -> void:
	_craters.clear()
	# 出生点沿 -Z 前行即可走进主坑，出生区域保留平缓地面。
	_craters.append(Vector4(0.0, cos(0.29), -sin(0.29), 8.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed
	for _i in crater_count:
		var y := rng.randf_range(-1.0, 1.0)
		var angle := rng.randf_range(0.0, TAU)
		var direction := Vector3(sqrt(1.0 - y * y) * cos(angle), y, sqrt(1.0 - y * y) * sin(angle))
		var size := rng.randf_range(2.2, 6.5)
		if direction.distance_to(Vector3.UP) * radius < size * 1.4 + 4.0:
			continue
		_craters.append(Vector4(direction.x, direction.y, direction.z, size))


func surface_radius(direction: Vector3) -> float:
	var height := 0.0
	for crater in _craters:
		var distance := direction.distance_to(Vector3(crater.x, crater.y, crater.z)) * radius
		var t := distance / crater.w
		if t >= 1.4:
			continue
		if t < 1.0:
			height -= crater.w * 0.24 * pow(1.0 - t * t, 2.0)
		var rim := maxf(0.0, 1.0 - absf(t - 1.0) / 0.4)
		height += crater.w * 0.065 * rim * rim * (3.0 - 2.0 * rim)
	return radius + height
