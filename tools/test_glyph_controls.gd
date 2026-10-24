extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := (load("res://scenes/moon_walk.tscn") as PackedScene).instantiate()
	# 固定测试密度，不依赖用户当前场景中的美术参数。
	scene.get_node("Moon/MoonMesh/GlyphField").spacing = 1.1
	root.add_child(scene)
	var controls = scene.get_node("AsciiLayer/GlyphControls")
	var field = scene.get_node("Moon/MoonMesh/GlyphField")
	var deadline := Time.get_ticks_msec() + 20000
	while field._preview_dirty or field._preview_thread != null or field.multimesh == null:
		assert(Time.get_ticks_msec() < deadline, "Initial glyph preview timed out")
		await process_frame
	var initial: int = field.multimesh.instance_count
	controls._density.value = 2.0
	await create_timer(0.5).timeout
	while field._preview_dirty or field._preview_thread != null:
		await process_frame
	assert(field.multimesh.instance_count > initial, "Density must increase glyph count")
	assert(absf(field.spacing - 1.1 / sqrt(2.0)) < 0.001)
	controls._set_glyph_size(8.0)
	assert(field.glyph_px == 8.0)
	assert(field.material_override.get_shader_parameter("u_glyph_px") == 8.0)
	controls._density.value = 0.5
	await create_timer(0.5).timeout
	while field._preview_dirty or field._preview_thread != null:
		await process_frame
	assert(field.multimesh.instance_count < initial, "Density must decrease glyph count")
	assert(str(field.multimesh.instance_count) in controls._density_label.text)
	assert(not "pending" in controls._density_label.text)
	print("GLYPH_CONTROLS_OK initial=%d reduced=%d" % [initial, field.multimesh.instance_count])
	quit()
