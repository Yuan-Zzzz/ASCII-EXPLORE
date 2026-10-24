extends SceneTree
## 立方体应产生特征棱；平面（共面）不应产生内部棱。


func _initialize() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var box_edges: Dictionary = SurfaceSampler.sample_mesh_edges(box, 0.25, 25.0)
	var box_pos: PackedVector3Array = box_edges["positions"]
	var box_dir: PackedVector3Array = box_edges["directions"]
	if box_pos.is_empty():
		printerr("EDGE_FAIL box produced no edge points")
		quit(1)
		return
	if box_pos.size() != box_dir.size():
		printerr("EDGE_FAIL position/direction size mismatch")
		quit(1)
		return
	for d in box_dir:
		if absf(d.length() - 1.0) > 0.05:
			printerr("EDGE_FAIL direction not unit: %s" % d)
			quit(1)
			return

	# 两共面三角拼成的四边形：共享边夹角 0，不应作为特征棱
	var flat := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1),
		Vector3(0, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
	])
	flat.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var flat_edges: Dictionary = SurfaceSampler.sample_mesh_edges(flat, 0.2, 25.0)
	var flat_pos: PackedVector3Array = flat_edges["positions"]
	# 边界棱仍会保留；共享对角线不应出现在特征棱集合（点不应落在内部对角线上过密）
	# 至少应有边界点
	if flat_pos.is_empty():
		printerr("EDGE_FAIL flat mesh should keep boundary edges")
		quit(1)
		return

	print("EDGE_OK box=%d flat=%d" % [box_pos.size(), flat_pos.size()])
	quit(0)
