extends SceneTree

const EYE_HEIGHT := 1.7
const SETTLED_FRAMES := 90


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
		_fail("collision radius %s != mesh radius %s" % [moon_shape.radius, moon_mesh.radius])
		return
	if moon_shape.radius < 40.0 or moon_shape.radius > 50.0:
		_fail("moon radius %s" % moon_shape.radius)
		return

	var player := main.get_node("Player") as CharacterBody3D
	var dist := player.global_position.length()
	var expected := moon_shape.radius + EYE_HEIGHT
	if dist <= moon_shape.radius:
		_fail("player inside moon dist=%s radius=%s" % [dist, moon_shape.radius])
		return
	if absf(dist - expected) > 0.02:
		_fail("player dist %s expected %s" % [dist, expected])
		return
	if not player.is_on_floor():
		_fail("player not on floor dist=%s" % dist)
		return

	var camera := player.get_node("Camera3D") as Camera3D
	if camera.global_position.length() <= moon_shape.radius:
		_fail("camera inside moon dist=%s" % camera.global_position.length())
		return

	var sun := main.get_node("SkyPivot/Sun") as DirectionalLight3D
	var sun_ball := main.get_node("SkyPivot/SunBall") as MeshInstance3D
	var sun_dir := sun_ball.global_position.normalized()
	var light_z := sun.global_transform.basis.z.normalized()
	if sun_dir.dot(light_z) < 0.999:
		_fail("sun +Z dot %s" % sun_dir.dot(light_z))
		return

	var moon_field := _field(main, ^"Moon/MoonMesh")
	var earth_field := _field(main, ^"SkyPivot/Earth")
	var sun_field := _field(main, ^"SkyPivot/SunBall")
	if moon_field == null or earth_field == null or sun_field == null:
		_fail("missing glyph field")
		return

	var moon_n := _count(moon_field)
	var earth_n := _count(earth_field)
	var sun_n := _count(sun_field)
	if moon_field.spacing < 0.8 or moon_field.spacing > 1.2:
		_fail("moon spacing %s" % moon_field.spacing)
		return
	if earth_field.spacing < 0.3 or earth_field.spacing > 0.5 or sun_field.spacing < 0.3 or sun_field.spacing > 0.5:
		_fail("distant spacing earth=%s sun=%s" % [earth_field.spacing, sun_field.spacing])
		return
	if moon_n != 14447 or earth_n != 256 or sun_n != 213:
		_fail("instances moon=%s earth=%s sun=%s" % [moon_n, earth_n, sun_n])
		return

	var moon_light: Vector3 = moon_field.light_dir.normalized()
	if moon_light.dot(light_z) < 0.999:
		_fail("glyph light_dir dot %s" % moon_light.dot(light_z))
		return

	print(
		"SMOKE_OK moon=%d earth=%d sun=%d player_radius=%.4f moon_radius=%.4f"
		% [moon_n, earth_n, sun_n, dist, moon_shape.radius]
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
