extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not Engine.is_editor_hint():
		printerr("Run this check with --headless --editor --script")
		quit(1)
		return
	var scene := (load("res://scenes/moon_walk.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	root.add_child(scene)
	await process_frame
	var field := scene.get_node("Moon/MoonMesh/GlyphField") as GlyphField
	await _settle(field)
	assert(field.multimesh != null and field.multimesh.instance_count > 3000, "Editor must generate moon glyphs")
	# 使用明确的有效间距，避免场景中的美术调参影响预览测试。
	field.spacing = 1.1
	await create_timer(0.3).timeout
	await _settle(field)
	var initial := field.multimesh.instance_count
	var earth := scene.get_node("SkyPivot/Earth/GlyphField") as GlyphField
	assert(earth.multimesh != null and earth.multimesh.instance_count > 50)
	var depth := scene.get_node("Moon/MoonMesh").material_override as StandardMaterial3D
	assert(depth.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	field.spacing *= 1.5
	await create_timer(0.3).timeout
	await _settle(field)
	assert(field.multimesh.instance_count < initial, "Inspector spacing must rebuild preview")
	field.glyph_px = 9.0
	field.tint = Color(0.8, 0.6, 0.4)
	await process_frame
	await process_frame
	var mat := field.material_override as ShaderMaterial
	assert(is_equal_approx(mat.get_shader_parameter("u_glyph_px"), 9.0))
	assert(mat.get_shader_parameter("u_tint") == Vector3(0.8, 0.6, 0.4))
	var sun := scene.get_node("SkyPivot/SunHost/SunLight") as DirectionalLight3D
	sun.rotate_y(0.5)
	await process_frame
	await process_frame
	assert(field.light_dir.normalized().dot(sun.global_basis.z.normalized()) > 0.999)
	assert(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "Editor must keep mouse free")
	print("EDITOR_PREVIEW_OK moon=%d earth=%d" % [field.multimesh.instance_count, earth.multimesh.instance_count])
	scene.free()
	quit(0)


func _settle(field: GlyphField) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while field._preview_dirty or field._preview_thread != null:
		assert(Time.get_ticks_msec() < deadline, "Preview task timed out")
		await process_frame
