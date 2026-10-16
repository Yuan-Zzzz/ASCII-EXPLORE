extends SceneTree

const OpticsScript = preload("res://features/moon_walk/black_hole_optics.gd")
const BlackHoleScript = preload("res://features/moon_walk/black_hole.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not await _scene_contract():
		return
	if not await _optics_contract():
		return
	print("SMOKE_OK")
	quit(0)


func _scene_contract() -> bool:
	var packed := load("res://scenes/moon_walk.tscn") as PackedScene
	if packed == null:
		return _fail("load moon_walk.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	if main.has_node("BayerDither"):
		return _fail("BayerDither must stay out of moon_walk")
	var root_src := FileAccess.get_file_as_string("res://features/moon_walk/moon_walk_root.gd")
	if root_src.contains("BlackHole") or root_src.contains("black_hole"):
		return _fail("moon_walk_root names the black hole")

	var bh = main.get_node_or_null("SkyPivot/BlackHole")
	if bh == null or bh.get_script() != BlackHoleScript:
		return _fail("missing SkyPivot/BlackHole")
	if not (bh.global_position as Vector3).is_equal_approx(Vector3(168, 72, -96)):
		return _fail("origin %s" % bh.global_position)
	if bh.get_node_or_null("GlyphField") != null:
		return _fail("BlackHole must not own GlyphField")
	for path in ["Moon/MoonMesh", "SkyPivot/Earth", "SkyPivot/SunHost"]:
		if main.get_node(path) == bh or main.get_node_or_null("%s/BlackHole" % path) != null:
			return _fail("BlackHole is on host path %s" % path)
	if main.has_method("_surface_hosts"):
		for host in main.call("_surface_hosts"):
			if host == bh:
				return _fail("BlackHole is in the host list")

	var mat: ShaderMaterial = bh.lens_material()
	if mat == null:
		return _fail("missing lens ShaderMaterial")
	main.surface_render_mode = 0
	await process_frame
	main.surface_render_mode = 1
	await process_frame
	main.surface_render_mode = 2
	await process_frame
	if bh.lens_material() != mat:
		return _fail("lens material replaced by surface_render_mode")

	var block: Dictionary = bh.optics.uniform_block()
	for key in block:
		var got = mat.get_shader_parameter(key)
		var want = block[key]
		if not _same(got, want):
			return _fail("uniform %s got=%s want=%s" % [key, got, want])
	var snap: Dictionary = bh.uniform_snapshot()
	for key in block:
		if not _same(snap[key], block[key]):
			return _fail("snapshot %s" % key)

	var listed := {}
	for item in mat.shader.get_shader_uniform_list():
		listed[String(item["name"])] = true
	for key in block:
		if not listed.has(String(key)):
			return _fail("shader missing %s" % key)
	for uname in listed:
		if String(uname).begins_with("u_") and not block.has(String(uname)):
			return _fail("extra shader uniform %s" % uname)

	var cam := main.get_node("Player/Camera3D") as Camera3D
	cam.look_at(bh.global_position, Vector3.UP)
	var proj: Dictionary = bh.project_shadow(cam)
	if not proj["in_frustum"]:
		return _fail("shadow not in frustum center=%s" % proj["center"])
	if float(proj["radius_px"]) <= 8.0:
		return _fail("shadow radius_px %s" % proj["radius_px"])
	return true


func _optics_contract() -> bool:
	var optics = OpticsScript.new()
	optics.inclination = 0.0
	await process_frame
	if not is_equal_approx(optics.photon_sphere_radius(), 1.5 * optics.rs):
		return _fail("photon sphere")
	if not is_equal_approx(optics.shadow_radius(), 0.5 * sqrt(27.0) * optics.rs):
		return _fail("shadow radius")
	var center := Vector3.ZERO
	var cam := Vector3(0, 200, 0)
	var horizon = optics.trace(center, OpticsScript.Ray.with_impact(cam, center, optics.shadow_radius(), Vector3.RIGHT))
	if not (horizon.valid and horizon.captured and not horizon.shows_background):
		return _fail("capture at b_c")
	var ring = optics.trace(center, OpticsScript.Ray.with_impact(cam, center, optics.shadow_radius() * 1.01, Vector3.RIGHT))
	if ring.captured or not ring.shows_background or ring.ring_radiance <= 0.0:
		return _fail("ring just outside")
	if ring.deflection <= 2.0 * optics.rs / ring.impact:
		return _fail("strong deflection")
	var lens = optics.trace(center, OpticsScript.Ray.with_impact(cam, center, optics.shadow_radius() * 5.0, Vector3.RIGHT))
	if not lens.shows_background or not is_equal_approx(lens.deflection, 2.0 * optics.rs / lens.impact):
		return _fail("weak deflection")
	if lens.sample_scale <= 0.0 or lens.sample_scale >= 1.0:
		return _fail("sample_scale")

	optics.inclination = 1.15
	optics.node_longitude = 0.0
	await process_frame
	var eye := Vector3(0, 40, 180)
	var approach = optics.trace(center, OpticsScript.Ray.looking(eye, Vector3(-12, 0, 0)))
	var recede = optics.trace(center, OpticsScript.Ray.looking(eye, Vector3(12, 0, 0)))
	if not is_equal_approx(approach.disk_radius, 12.0) or not is_equal_approx(recede.disk_radius, 12.0):
		return _fail("disk radius approach=%s recede=%s" % [approach.disk_radius, recede.disk_radius])
	if approach.disk_g <= recede.disk_g or approach.albedo.r <= recede.albedo.r:
		return _fail("doppler approach g=%s recede g=%s" % [approach.disk_g, recede.disk_g])
	return true


func _same(got, want) -> bool:
	if got == want:
		return true
	if typeof(want) == TYPE_FLOAT and typeof(got) == TYPE_FLOAT:
		return is_equal_approx(got, want)
	if typeof(want) == TYPE_VECTOR3 and typeof(got) == TYPE_VECTOR3:
		return (got as Vector3).is_equal_approx(want)
	if typeof(want) == TYPE_COLOR and typeof(got) == TYPE_COLOR:
		return (got as Color).is_equal_approx(want)
	return false


func _fail(message: String) -> bool:
	print("SMOKE_FAIL: %s" % message)
	quit(1)
	return false
