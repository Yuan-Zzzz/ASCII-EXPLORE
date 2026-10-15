extends SceneTree

const SETTLED_FRAMES := 120


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

	var moon_shape := main.get_node("Moon/CollisionShape3D").shape as SphereShape3D
	var moon_mesh := main.get_node("Moon/MoonMesh").mesh as SphereMesh
	if moon_shape == null or moon_mesh == null:
		_fail("moon collision or mesh missing")
		return
	if absf(moon_shape.radius - moon_mesh.radius) > 0.001:
		_fail("radius mismatch")
		return
	if moon_shape.radius < 40.0 or moon_shape.radius > 55.0:
		_fail("moon radius %s" % moon_shape.radius)
		return

	var player := main.get_node("Player") as CharacterBody3D
	var dist := player.global_position.length()
	if dist <= moon_shape.radius:
		_fail("player inside moon dist=%s" % dist)
		return
	if dist > moon_shape.radius + 4.0:
		_fail("player too far dist=%s" % dist)
		return
	if not player.is_on_floor():
		_fail("player not on floor dist=%s" % dist)
		return

	var camera := player.get_node("Camera3D") as Camera3D
	if camera.global_position.length() <= moon_shape.radius:
		_fail("camera inside moon")
		return

	var sun_host := main.get_node("SkyPivot/SunHost") as MeshInstance3D
	var sun_mat := sun_host.material_override as StandardMaterial3D
	if sun_mat == null or not sun_mat.emission_enabled:
		_fail("sun missing emissive material")
		return
	if _field(main, ^"SkyPivot/SunHost") != null:
		_fail("sun must not use GlyphField")
		return

	var moon_field := _field(main, ^"Moon/MoonMesh")
	var earth_field := _field(main, ^"SkyPivot/Earth")
	if moon_field == null or earth_field == null:
		_fail("missing moon/earth glyph field")
		return
	if moon_field.spacing < 0.8 or moon_field.spacing > 1.6:
		_fail("moon spacing %s" % moon_field.spacing)
		return

	var moon_n := _count(moon_field)
	var earth_n := _count(earth_field)
	if moon_n < 3000 or moon_n > 80000:
		_fail("moon instances %s" % moon_n)
		return
	if earth_n < 50 or earth_n > 20000:
		_fail("earth instances %s" % earth_n)
		return

	var light := main.get_node("SkyPivot/SunLight") as DirectionalLight3D
	var light_z := light.global_transform.basis.z.normalized()
	var moon_light: Vector3 = moon_field.light_dir.normalized()
	if moon_light.dot(light_z) < 0.999:
		_fail("glyph light_dir not synced")
		return

	print(
		"SMOKE_OK moon=%d earth=%d player_radius=%.4f moon_radius=%.4f"
		% [moon_n, earth_n, dist, moon_shape.radius]
	)
	quit(0)


func _field(main: Node, host_path: NodePath) -> GlyphField:
	var host := main.get_node_or_null(host_path)
	if host == null:
		return null
	for child in host.get_children():
		if child is GlyphField:
			return child as GlyphField
	return null


func _count(field: GlyphField) -> int:
	var mm := field.multimesh
	if mm == null:
		return 0
	return mm.instance_count


func _fail(reason: String) -> void:
	printerr("SMOKE_FAIL %s" % reason)
	quit(1)
