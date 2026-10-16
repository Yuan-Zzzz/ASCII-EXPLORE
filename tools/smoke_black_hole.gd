extends SceneTree

const SETTLED_FRAMES := 60
const BlackHoleScript = preload("res://features/moon_walk/black_hole.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/moon_walk.tscn") as PackedScene
	if packed == null:
		_fail("load moon_walk.tscn")
		return

	var main: Node = packed.instantiate()
	root.add_child(main)
	for _i in SETTLED_FRAMES:
		await process_frame

	if main.has_node("BayerDither"):
		_fail("BayerDither must stay out of moon_walk")
		return
	if main.get_node_or_null("Moon/MoonMesh/BlackHole") != null:
		_fail("BlackHole must not sit under host triad paths")
		return

	var bh_node := main.get_node_or_null("SkyPivot/BlackHole")
	if bh_node == null or bh_node.get_script() != BlackHoleScript:
		_fail("missing SkyPivot/BlackHole")
		return
	if bh_node.get_node_or_null("GlyphField") != null:
		_fail("BlackHole must not own GlyphField")
		return
	var optics = bh_node.optics
	if optics == null or not optics.consistent():
		_fail("optics inconsistent")
		return

	var mat: ShaderMaterial = bh_node.lens_material()
	if mat == null:
		_fail("missing lens ShaderMaterial")
		return

	if main.get("surface_render_mode") != null:
		main.set("surface_render_mode", 0)
		await process_frame
		main.set("surface_render_mode", 1)
		await process_frame
		main.set("surface_render_mode", 2)
		await process_frame
	if bh_node.lens_material() != mat:
		_fail("lens material replaced by surface_render_mode")
		return

	var block: Dictionary = optics.uniform_block()
	var snap: Dictionary = bh_node.uniform_snapshot()
	for key in block:
		if not snap.has(key):
			_fail("uniform missing %s" % key)
			return
		var got = snap[key]
		var want = block[key]
		if typeof(want) == TYPE_FLOAT:
			if not is_equal_approx(float(got), float(want)):
				_fail("uniform %s got=%s want=%s" % [key, got, want])
				return
		elif got != want:
			_fail("uniform %s mismatch" % key)
			return

	var shader_uniforms: Array = mat.shader.get_shader_uniform_list()
	var shader_names := {}
	for item in shader_uniforms:
		if typeof(item) == TYPE_DICTIONARY and item.has("name"):
			shader_names[String(item["name"])] = true
	for key in block:
		if not shader_names.has(String(key)):
			_fail("shader missing uniform %s" % key)
			return

	var cam := main.get_node_or_null("Player/Camera3D") as Camera3D
	if cam == null:
		_fail("missing camera")
		return
	# 出生朝向不一定对着天空槽；对拍前先看向黑洞。
	cam.look_at(bh_node.global_position, Vector3.UP)
	await process_frame
	var proj: Dictionary = bh_node.project_shadow(cam)
	if not proj.get("in_front", false):
		_fail("BH behind camera after look_at")
		return
	var shadow_px: float = float(proj.get("radius_px", 0.0))
	if shadow_px <= 4.0:
		_fail("shadow_radius_px too small %s" % shadow_px)
		return
	if not proj.get("in_frustum", false):
		_fail("BH not in frustum after look_at center=%s" % proj.get("center"))
		return

	if not is_equal_approx(optics.photon_sphere_radius(), 1.5 * optics.rs):
		_fail("photon sphere")
		return
	if not is_equal_approx(optics.shadow_radius(), 0.5 * sqrt(27.0) * optics.rs):
		_fail("shadow radius")
		return

	print(
		"SMOKE_OK bh_rs=%.2f shadow_px=%.1f uniforms=%d"
		% [optics.rs, shadow_px, block.size()]
	)
	quit(0)


func _fail(reason: String) -> void:
	printerr("SMOKE_FAIL %s" % reason)
	quit(1)
