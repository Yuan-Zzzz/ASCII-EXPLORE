extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _brightness(viewport: SubViewport) -> float:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var total := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			total += color.r + color.g + color.b
	return total

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.position.z = 3.0
	viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	viewport.add_child(light)
	var host := MeshInstance3D.new()
	host.mesh = SphereMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	host.material_override = material
	viewport.add_child(host)
	var field := GlyphField.new()
	field.spacing = 0.15
	field.glyph_px = 8.0
	host.add_child(field)
	for mode in 3:
		field.visible = mode != 1
		field.dither_enabled = mode == 2
		material.albedo_color = Color.WHITE if mode == 1 else Color.BLACK
		host.material_overlay = null
		if mode == 1:
			var overlay := ShaderMaterial.new()
			overlay.shader = load("res://features/dither/bayer_model.gdshader")
			host.material_overlay = overlay
		light.light_energy = 0.0
		var dark: float = await _brightness(viewport)
		light.light_energy = 2.0
		var bright: float = await _brightness(viewport)
		print("NATIVE_LIGHT mode=%d off=%.2f on=%.2f" % [mode, dark, bright])
		if bright <= dark + 10.0:
			push_error("Native light energy did not change rendered brightness")
			quit(1)
			return
	print("NATIVE_LIGHTING_OK: native light energy changes ASCII, Bayer and combined rendered pixels")
	quit()
