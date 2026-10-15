extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := (load("res://scenes/moon_walk.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var controls = scene.get_node("AsciiLayer/GlyphControls")
	var field = scene.get_node("Moon/MoonMesh/GlyphField")
	var initial: int = field.multimesh.instance_count
	controls._density.value = 2.0
	await create_timer(0.35).timeout
	assert(field.multimesh.instance_count > initial, "Density must increase glyph count")
	assert(absf(field.spacing - 1.1 / sqrt(2.0)) < 0.001)
	controls._set_glyph_size(8.0)
	assert(field.glyph_px == 8.0)
	assert(field.material_override.get_shader_parameter("u_glyph_px") == 8.0)
	controls._density.value = 0.5
	await create_timer(0.35).timeout
	assert(field.multimesh.instance_count < initial, "Density must decrease glyph count")
	print("GLYPH_CONTROLS_OK initial=%d reduced=%d" % [initial, field.multimesh.instance_count])
	quit()
