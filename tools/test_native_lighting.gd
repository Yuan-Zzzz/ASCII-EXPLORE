extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := MeshInstance3D.new()
	host.mesh = SphereMesh.new()
	var original := StandardMaterial3D.new()
	original.albedo_color = Color.WHITE
	host.material_override = original
	root.add_child(host)
	var field := GlyphField.new()
	field.spacing = 0.5
	field.glyph_px = 8.0
	host.add_child(field)
	var deadline := Time.get_ticks_msec() + 10000
	while field._preview_dirty or field._preview_thread != null:
		assert(Time.get_ticks_msec() < deadline, "Glyph preview timed out")
		await process_frame

	assert(field.visible)
	assert(host.material_override is StandardMaterial3D)
	assert((host.material_override as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert(host.material_overlay == null)
	assert(field.material_overlay is ShaderMaterial)
	assert((field.material_overlay as ShaderMaterial).shader.resource_path.ends_with("glyph_bayer_overlay.gdshader"))

	field.effect_enabled = false
	await process_frame
	await process_frame
	assert(not field.visible)
	assert(host.material_override == original)

	print("NATIVE_LIGHTING_OK: GlyphField applies ASCII+Bayer and restores host materials when disabled")
	quit()
