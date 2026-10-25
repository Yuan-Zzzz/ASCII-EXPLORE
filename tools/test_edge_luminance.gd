extends SceneTree
## 棱边改亮度阶梯 + 偏亮：无方向字硬切。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_ramp_no_direction_prefix()
	_test_edge_index_at_brightens()
	await _test_edge_bright_shader_param()
	print("EDGE_LUMINANCE_OK ramp + bright param")
	quit(0)


func _test_ramp_no_direction_prefix() -> void:
	var ramp := AsciiRamp.new()
	ramp.ramp = " .:-=+*#%@"
	ramp.edge_count = 0
	assert(ramp.char_count == 10)
	assert(ramp.surface_count == 10)
	# 暗端跳过空格
	assert(ramp.char_at(ramp.index_at(0.0)) != " ")
	# 亮端落在 @
	assert(ramp.char_at(ramp.index_at(1.0)) == "@")
	# 不再把前缀当方向字
	assert(ramp.edge_index(0) == 0)  # deprecated compat: clamps into ramp


func _test_edge_index_at_brightens() -> void:
	var ramp := AsciiRamp.new()
	ramp.ramp = " .:-=+*#%@"
	ramp.edge_count = 0
	var dark: int = ramp.index_at(0.1)
	var edge_dark: int = ramp.edge_index_at(0.1, 0.35)
	assert(edge_dark >= dark, "edge bright bias must raise or keep index")
	var full: int = ramp.edge_index_at(0.1, 1.0)
	assert(ramp.char_at(full) == "@")
	# 同亮度、无视角档：公式确定，无 atan 四档
	assert(ramp.edge_index_at(0.5, 0.0) == ramp.index_at(0.5))


func _test_edge_bright_shader_param() -> void:
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
	field.edge_bright = 0.42
	field._apply_params_all()
	await process_frame
	assert(is_equal_approx(float(mat.get_shader_parameter("u_edge_bright")), 0.42))
	assert(int(mat.get_shader_parameter("u_edge_count")) == 0)

	host.queue_free()
