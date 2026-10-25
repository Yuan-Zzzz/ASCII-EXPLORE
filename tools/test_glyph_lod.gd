extends SceneTree
## Glyph 距离 LOD：公式与材质参数接线（不依赖 GPU 视觉）。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_lod_mix()
	await _test_shader_params()
	print("GLYPH_LOD_OK mix + material params")
	quit(0)


func _test_lod_mix() -> void:
	# 近端：keep / px ≈ near
	assert(is_equal_approx(GlyphField.lod_mix(1.0, 2.0, 40.0, 1.0, 0.2), 1.0))
	assert(is_equal_approx(GlyphField.lod_mix(1.0, 2.0, 40.0, 30.0, 12.0), 30.0))
	# 远端：keep / px ≈ far
	assert(is_equal_approx(GlyphField.lod_mix(80.0, 2.0, 40.0, 1.0, 0.2), 0.2))
	assert(is_equal_approx(GlyphField.lod_mix(80.0, 2.0, 40.0, 30.0, 12.0), 12.0))
	# 中间：严格介于近远之间，且随深度下降
	var mid_keep := GlyphField.lod_mix(21.0, 2.0, 40.0, 1.0, 0.2)
	assert(mid_keep < 1.0 and mid_keep > 0.2)
	var nearish := GlyphField.lod_mix(5.0, 2.0, 40.0, 1.0, 0.2)
	var farish := GlyphField.lod_mix(35.0, 2.0, 40.0, 1.0, 0.2)
	assert(nearish > farish)
	# 棱边 keep 端点不低于表面
	var edge_far := 0.5
	var surf_far := 0.18
	assert(edge_far >= surf_far)
	assert(GlyphField.lod_mix(80.0, 2.0, 40.0, 1.0, edge_far) >= GlyphField.lod_mix(80.0, 2.0, 40.0, 1.0, surf_far))


func _test_shader_params() -> void:
	var host := MeshInstance3D.new()
	host.mesh = BoxMesh.new()
	var field := GlyphField.new()
	field.ramp = load("res://features/ascii/ascii_ramp.tres") as AsciiRamp
	field.spacing = 0.8
	field.sample_edges = false
	field.rebuild_on_ready = true
	host.add_child(field)
	root.add_child(host)

	var deadline := Time.get_ticks_msec() + 15000
	while field._preview_dirty or field._preview_thread != null or field.multimesh == null:
		assert(Time.get_ticks_msec() < deadline, "Glyph preview timed out")
		await process_frame

	var mat := field.material_override as ShaderMaterial
	assert(mat != null)
	# LOD off：短路，不启用抽稀；仍用 glyph_px
	field.lod_enabled = false
	field.glyph_px = 16.0
	field._apply_params_all()
	await process_frame
	assert(mat.get_shader_parameter("u_lod_enabled") == 0.0)
	assert(mat.get_shader_parameter("u_glyph_px") == 16.0)

	field.lod_enabled = true
	field.lod_near = 3.0
	field.lod_far = 50.0
	field.glyph_px_near = 30.0
	field.glyph_px_far = 12.0
	field.keep_near = 1.0
	field.keep_far = 0.18
	field.edge_keep_near = 1.0
	field.edge_keep_far = 0.5
	field._apply_params_all()
	await process_frame
	assert(mat.get_shader_parameter("u_lod_enabled") == 1.0)
	assert(mat.get_shader_parameter("u_lod_near") == 3.0)
	assert(mat.get_shader_parameter("u_lod_far") == 50.0)
	assert(mat.get_shader_parameter("u_glyph_px_near") == 30.0)
	assert(mat.get_shader_parameter("u_glyph_px_far") == 12.0)
	assert(mat.get_shader_parameter("u_keep_near") == 1.0)
	assert(mat.get_shader_parameter("u_keep_far") == 0.18)
	assert(mat.get_shader_parameter("u_edge_keep_near") == 1.0)
	assert(mat.get_shader_parameter("u_edge_keep_far") == 0.5)

	# 棱边端点被抬到不低于表面
	field.edge_keep_far = 0.1
	field.keep_far = 0.25
	field._apply_params_all()
	await process_frame
	assert(mat.get_shader_parameter("u_edge_keep_far") == 0.25)

	host.queue_free()
