extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/moon_walk.tscn") as PackedScene
	var main := scene.instantiate()
	main.surface_render_mode = 1
	root.add_child(main)
	await process_frame
	await process_frame
	assert(not main.has_node("BayerDither"), "Full-screen effect must be removed")
	for path in ["Moon/MoonMesh", "SkyPivot/Earth", "SkyPivot/SunHost"]:
		var host := main.get_node(path) as MeshInstance3D
		assert(host.material_override is StandardMaterial3D, "Model needs native lit material")
		assert(not host.get_node("GlyphField").visible, "Glyphs must not obscure the model")
		assert(host.material_overlay.shader.resource_path.ends_with("bayer_model.gdshader"))
	main.dither_pixel_size = 3.0
	main.surface_render_mode = 0
	await process_frame
	await process_frame
	for path in ["Moon/MoonMesh", "SkyPivot/Earth", "SkyPivot/SunHost"]:
		var host := main.get_node(path) as MeshInstance3D
		assert(host.get_node("GlyphField").visible, "ASCII mode must restore glyphs")
		assert(host.material_override is StandardMaterial3D)
	main.surface_render_mode = 1
	await process_frame
	await process_frame
	var material := main.get_node("Moon/MoonMesh").material_overlay as ShaderMaterial
	assert(material != null)
	assert(is_equal_approx(material.get_shader_parameter("u_pixel_size"), 3.0))
	assert(main.sun_light.shadow_enabled, "Native shadows must be enabled")
	print("MODEL_DITHER_OK: model materials, glyph visibility, mode switching, parameters and lighting")
	quit()

