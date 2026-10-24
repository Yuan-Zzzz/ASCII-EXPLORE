extends SceneTree
## 场景级 GlyphField：挂在父节点下应覆盖子树全部 Mesh，并采到棱边点。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root_n := Node3D.new()
	root.add_child(root_n)

	var a := MeshInstance3D.new()
	a.name = "PartA"
	a.mesh = BoxMesh.new()
	(a.mesh as BoxMesh).material = StandardMaterial3D.new()
	(a.mesh as BoxMesh).material.albedo_color = Color(1, 0.2, 0.1)
	root_n.add_child(a)

	var b := MeshInstance3D.new()
	b.name = "PartB"
	b.mesh = SphereMesh.new()
	(b.mesh as SphereMesh).radius = 0.5
	(b.mesh as SphereMesh).height = 1.0
	(b.mesh as SphereMesh).material = StandardMaterial3D.new()
	(b.mesh as SphereMesh).material.albedo_color = Color(0.2, 0.6, 1.0)
	root_n.add_child(b)

	var field := GlyphField.new()
	field.spacing = 0.35
	field.edge_step = 0.2
	field.sample_surface = true
	field.sample_edges = true
	root_n.add_child(field)

	var deadline := Time.get_ticks_msec() + 15000
	while field._preview_dirty or field._preview_thread != null or field._managed.is_empty():
		assert(Time.get_ticks_msec() < deadline, "Scene-mode preview timed out")
		await process_frame

	assert(field._managed.size() == 2, "Scene mode must cover both meshes, got %d" % field._managed.size())
	assert(field.multimesh == null, "Scene-mode GlyphField should not own a root MultiMesh")

	var edge_total := 0
	for entry in field._managed:
		var surface: MultiMeshInstance3D = entry["surface"]
		var edge: MultiMeshInstance3D = entry["edge"]
		assert(is_instance_valid(surface) and surface.multimesh != null and surface.multimesh.instance_count > 0)
		assert(is_instance_valid(edge) and edge.multimesh != null and edge.multimesh.instance_count > 0)
		edge_total += edge.multimesh.instance_count
		assert(surface.get_parent() is MeshInstance3D)
	assert(edge_total > 0, "Feature edges must produce glyph points")

	print("GLYPH_SCENE_MODE_OK hosts=%d edges=%d" % [field._managed.size(), edge_total])
	root_n.free()
	quit(0)
