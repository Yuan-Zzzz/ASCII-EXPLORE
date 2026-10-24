extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/moon_walk.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	var fields: Array[GlyphField] = []
	for path in ["Moon/MoonMesh", "SkyPivot/Earth", "SkyPivot/SunHost"]:
		fields.append(main.get_node(path).get_node("GlyphField") as GlyphField)
	var deadline := Time.get_ticks_msec() + 30000
	for field in fields:
		while field._preview_dirty or field._preview_thread != null:
			assert(Time.get_ticks_msec() < deadline, "Glyph preview timed out")
			await process_frame
	assert(not main.has_node("BayerDither"), "Full-screen effect must be removed")
	for path in ["Moon/MoonMesh", "SkyPivot/Earth", "SkyPivot/SunHost"]:
		var host := main.get_node(path) as MeshInstance3D
		assert(host.material_override is StandardMaterial3D, "Host needs depth shell material")
		assert(host.material_overlay == null, "Bayer Model host overlay must be gone")
		var field := host.get_node("GlyphField") as GlyphField
		assert(field.visible, "ASCII glyphs must stay visible")
		if field.emissive_body:
			assert(field.material_overlay == null, "Emissive bodies skip glyph Bayer")
		else:
			assert(field.material_overlay is ShaderMaterial)
			assert(field.material_overlay.shader.resource_path.ends_with("glyph_bayer_overlay.gdshader"))
	main.dither_pixel_size = 3.0
	await process_frame
	await process_frame
	var material := main.get_node("Moon/MoonMesh/GlyphField").material_overlay as ShaderMaterial
	assert(material != null)
	assert(is_equal_approx(material.get_shader_parameter("u_dither_pixel_size"), 3.0))
	var sun_light := main.get_node("SkyPivot/SunHost/SunLight") as DirectionalLight3D
	assert(sun_light.shadow_enabled, "Native shadows must be enabled")
	print("MODEL_DITHER_OK: default ASCII+Bayer, no host bayer_model, dither params and lighting")
	quit()
