extends SceneTree
const Effect = preload("res://features/ascii/ascii_effect_3d.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var model := Node3D.new()
	root.add_child(model)
	var a := MeshInstance3D.new()
	a.mesh = BoxMesh.new()
	var original := StandardMaterial3D.new()
	a.material_override = original
	model.add_child(a)
	var b := MeshInstance3D.new()
	b.mesh = SphereMesh.new()
	b.position.x = 3.0
	model.add_child(b)
	var effect := Effect.new()
	model.add_child(effect)
	await process_frame
	await create_timer(0.8).timeout
	assert(effect._entries.size() == 2)
	var fa: GlyphField = effect._entries[a].field
	var fb: GlyphField = effect._entries[b].field
	assert(fa.multimesh.instance_count > 0 and fb.multimesh.instance_count > 0)
	var count := fa.multimesh.instance_count
	var other := MeshInstance3D.new()
	other.mesh = BoxMesh.new()
	root.add_child(other)
	var second := Effect.new()
	other.add_child(second)
	await process_frame
	effect.glyph_px = 21.0
	effect.density = 4.0
	await create_timer(0.8).timeout
	assert(fa.multimesh.instance_count > count)
	assert(fa.material_override != second._entries[other].field.material_override)
	assert(fa.material_override.get_shader_parameter("u_glyph_px") == 21.0)
	assert(second.glyph_px == 12.0 and second.density == 1.0)
	effect.enabled = false
	await process_frame
	await process_frame
	assert(a.material_override == original and not fa.visible)
	effect.enabled = true
	await process_frame
	await process_frame
	effect.queue_free()
	await process_frame
	await process_frame
	assert(a.material_override == original)
	# Both surfaces of an imported-style ArrayMesh must contribute.
	var mesh := ArrayMesh.new()
	var primitive := BoxMesh.new()
	var arrays := primitive.get_mesh_arrays()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in points.size():
		points[i].x += 10.0
	arrays[Mesh.ARRAY_VERTEX] = points
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var sampled := SurfaceSampler.sample_mesh(mesh)
	var left := false
	var right := false
	for point in sampled.positions:
		left = left or point.x < 2.0
		right = right or point.x > 8.0
	assert(left and right)
	model.free()
	other.free()
	print("ASCII_EFFECT_OK independent parameters, density rebuild, restoration, multiple meshes/surfaces")
	quit()
