extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = load("res://scenes/moon_walk.tscn").instantiate()
	for path in ["Moon/MoonMesh/GlyphField", "SkyPivot/Earth/GlyphField", "SkyPivot/SunHost/GlyphField"]:
		main.get_node(path).spacing = 2.0
	root.add_child(main)
	await process_frame
	await process_frame
	assert(main.surface_render_mode == 2)
	assert(not main.has_node("BayerDither"))
	var sun_corona := main.get_node("SkyPivot/SunHost/Corona") as VisualInstance3D
	assert(not sun_corona.visible, "ASCII modes must hide the soft corona")
	for path in ["Moon/MoonMesh", "SkyPivot/Earth", "SkyPivot/SunHost"]:
		var host = main.get_node(path)
		var field = host.get_node("GlyphField") as GlyphField
		assert(field.visible and field.multimesh.instance_count > 0)
		assert(host.material_overlay == null)
		if field.emissive_body:
			assert(field.material_overlay == null)
			var core := host.material_override as StandardMaterial3D
			assert(core != null and not core.emission_enabled, "ASCII sun uses glyph emission, not a lit core")
			assert(core.albedo_color.r < 0.05)
		else:
			assert(field.material_overlay is ShaderMaterial)
			assert(field.material_overlay.shader.resource_path.ends_with("glyph_bayer_overlay.gdshader"))
	main.dither_pixel_size = 3.0
	main.dither_color_levels = 5.0
	await process_frame
	await process_frame
	var field = main.get_node("Moon/MoonMesh/GlyphField")
	assert(field.material_overlay.get_shader_parameter("u_dither_pixel_size") == 3.0)
	assert(field.material_overlay.get_shader_parameter("u_dither_color_levels") == 5.0)
	main.surface_render_mode = 0
	await process_frame
	await process_frame
	assert(field.visible and field.material_overlay == null)
	main.surface_render_mode = 1
	await process_frame
	await process_frame
	assert(not field.visible)
	assert(main.get_node("Moon/MoonMesh").material_overlay is ShaderMaterial)
	assert(sun_corona.visible, "Bayer model may show the soft corona")
	var sun_core := main.get_node("SkyPivot/SunHost").material_override as StandardMaterial3D
	assert(sun_core.emission_enabled, "Bayer sun keeps the emissive core")
	main.surface_render_mode = 2
	await process_frame
	await process_frame
	assert(field.visible and field.material_overlay is ShaderMaterial)
	assert(not sun_corona.visible)
	print("ASCII_BAYER_OK combined geometry, independent UI, parameter updates and three mode transitions")
	quit()
