extends SceneTree
## Fail until GLYPHS presentation (depth hosts + sun light) can be applied
## without relying on a running game process loop.
## godot --path . --headless -s tools/check_glyphs_mode_presentation.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	if not main.has_method("apply_glyphs_presentation"):
		printerr("PARITY_FAIL missing Main.apply_glyphs_presentation")
		quit(1)
		return

	# Reset to scene-authored look (what the editor shows when Main is not @tool).
	_reset_to_scene_authored(main)
	await process_frame

	main.call("apply_glyphs_presentation")
	await process_frame

	var sun: DirectionalLight3D = main.get_node("Sun")
	var sun_dir: Vector3 = sun.global_transform.basis.z.normalized()
	var GlyphFieldScript = load("res://features/ascii/glyph_field.gd")
	var hosts: Array[NodePath] = [^"Pivot/Ground", ^"Pivot/Earth", ^"Pivot/SunBall"]
	for host_path in hosts:
		var host := main.get_node(host_path) as MeshInstance3D
		var mat := host.material_override as StandardMaterial3D
		if mat == null or mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			printerr("PARITY_FAIL %s not unshaded depth shell" % host_path)
			quit(1)
			return
		var c := mat.albedo_color
		if c.r > 0.05 or c.g > 0.05 or c.b > 0.08:
			printerr("PARITY_FAIL %s albedo not near-black: %s" % [host_path, c])
			quit(1)
			return
		var field: Node = null
		for child in host.get_children():
			if child.get_script() == GlyphFieldScript:
				field = child
				break
		if field == null:
			printerr("PARITY_FAIL %s missing GlyphField" % host_path)
			quit(1)
			return
		var ld: Vector3 = (field.get("light_dir") as Vector3).normalized()
		if ld.distance_to(sun_dir) > 0.001:
			printerr("PARITY_FAIL %s light_dir %s != sun %s" % [host_path, ld, sun_dir])
			quit(1)
			return

	print("PARITY_OK")
	quit(0)


func _reset_to_scene_authored(main: Node) -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var fresh: Node = packed.instantiate()
	var GlyphFieldScript = load("res://features/ascii/glyph_field.gd")
	for path in [^"Pivot/Ground", ^"Pivot/Earth", ^"Pivot/SunBall"]:
		var src := fresh.get_node(path) as MeshInstance3D
		var dst := main.get_node(path) as MeshInstance3D
		dst.material_override = src.material_override
		for child in dst.get_children():
			if child.get_script() == GlyphFieldScript:
				child.set("light_dir", Vector3(0.4, 0.8, 0.3))
	fresh.free()
