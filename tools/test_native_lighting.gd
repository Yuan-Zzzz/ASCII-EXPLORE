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
	field.tint = Color(0.9, 0.9, 0.9)
	host.add_child(field)
	await process_frame
	await process_frame

	field.surface_render_mode = 0
	await process_frame
	await process_frame
	assert(field.visible)
	assert(host.material_override is StandardMaterial3D)
	assert((host.material_override as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert(host.material_overlay == null)
	assert(field.material_overlay == null)

	field.surface_render_mode = 1
	await process_frame
	await process_frame
	assert(not field.visible)
	assert(host.material_overlay is ShaderMaterial)
	assert((host.material_overlay as ShaderMaterial).shader.resource_path.ends_with("bayer_model.gdshader"))

	field.surface_render_mode = 2
	await process_frame
	await process_frame
	assert(field.visible)
	assert(field.material_overlay is ShaderMaterial)
	assert(host.material_overlay == null)

	field.effect_enabled = false
	await process_frame
	await process_frame
	assert(not field.visible)
	assert(host.material_override == original)

	print("NATIVE_LIGHTING_OK: GlyphField surface modes manage host materials and restore originals")
	quit()
