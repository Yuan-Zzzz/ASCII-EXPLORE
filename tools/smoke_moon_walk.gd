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

	var moon := main.get_node("Moon")
	var moon_shape := main.get_node("Moon/CollisionShape3D").shape as ConcavePolygonShape3D
	var moon_mesh := main.get_node("Moon/MoonMesh").mesh as ArrayMesh
	if moon_shape == null or moon_mesh == null:
		_fail("terrain collision or mesh missing")
		return
	var moon_radius: float = moon.radius
	var center := Vector3(0.0, cos(0.29), -sin(0.29))
	if moon.surface_radius(center) > moon_radius - 1.5:
		_fail("main crater has no depressed floor")
		return
	var rim_dir := center.rotated(Vector3.RIGHT, -2.0 * asin(8.0 / (2.0 * moon_radius)))
	if moon.surface_radius(rim_dir) <= moon_radius + 0.3:
		_fail("main crater has no raised rim")
		return
	# 验证坑底碰撞与可见网格同源，射线必须击中凹陷表面。
	var moon_origin: Vector3 = moon.global_position
	var query := PhysicsRayQueryParameters3D.create(
		moon_origin + center * 60.0, moon_origin + center * 40.0, 1
	)
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or absf((hit.position - moon_origin).length() - moon.surface_radius(center)) > 0.12:
		_fail("crater floor collision mismatch")
		return

	var player := main.get_node("Player") as CharacterBody3D
	var dist: float = (player.global_position - moon.global_position).length()
	if dist <= moon_radius:
		_fail("player inside moon dist=%s" % dist)
		return
	if dist > moon_radius + 4.0:
		_fail("player too far dist=%s" % dist)
		return
	if not player.is_on_floor():
		_fail("player not on floor dist=%s" % dist)
		return

	var camera := player.get_node("Camera3D") as Camera3D
	if (camera.global_position - moon.global_position).length() <= moon_radius:
		_fail("camera inside moon")
		return

	var sun_host := main.get_node("SkyPivot/SunHost") as MeshInstance3D
	var sun_mat := sun_host.material_override as StandardMaterial3D
	var sun_field := _field(main, ^"SkyPivot/SunHost")
	if sun_field == null:
		_fail("sun glyph field missing")
		return
	if sun_field.emission_energy <= 0.0:
		_fail("sun glyph emission missing")
		return
	var sun_corona := sun_host.get_node_or_null("Corona") as VisualInstance3D
	if sun_corona == null:
		_fail("sun corona missing")
		return
	# Default ASCII+Bayer: dark shell + glyph stroke glow; soft corona stays off.
	if sun_mat == null or sun_mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		_fail("sun shell must be unshaded")
		return
	if sun_mat.emission_enabled or sun_mat.albedo_color.r > 0.05:
		_fail("ASCII sun must not use a lit core")
		return
	if sun_corona.visible:
		_fail("ASCII sun must hide the soft corona")
		return
	main.surface_render_mode = 1
	await process_frame
	await process_frame
	sun_mat = sun_host.material_override as StandardMaterial3D
	if sun_mat == null or not sun_mat.emission_enabled or sun_mat.albedo_color.r <= 1.0:
		_fail("Bayer sun must keep an HDR emissive core")
		return
	if not sun_corona.visible:
		_fail("Bayer sun may show the soft corona")
		return
	main.surface_render_mode = 2
	await process_frame
	await process_frame
	var world_env := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env == null or not world_env.environment.glow_enabled:
		_fail("world glow disabled")
		return

	var moon_field := _field(main, ^"Moon/MoonMesh")
	var earth_field := _field(main, ^"SkyPivot/Earth")
	if moon_field == null or earth_field == null:
		_fail("missing moon/earth glyph field")
		return
	if moon_field.spacing < 0.01 or moon_field.spacing > 1.0:
		_fail("moon spacing %s" % moon_field.spacing)
		return

	var moon_n := _count(moon_field)
	var earth_n := _count(earth_field)
	if moon_n < 3000 or moon_n > 250000:
		_fail("moon instances %s" % moon_n)
		return
	if earth_n < 50 or earth_n > 20000:
		_fail("earth instances %s" % earth_n)
		return

	var light := main.get_node("SkyPivot/SunHost/SunLight") as DirectionalLight3D
	var light_z := light.global_transform.basis.z.normalized()
	var moon_light: Vector3 = moon_field.light_dir.normalized()
	if moon_light.dot(light_z) < 0.999:
		_fail("glyph light_dir not synced")
		return

	# 将角色放到主坑内，确保不会站在原来的隐形球面上；月球仍在轨道上移动。
	player.global_position = moon.global_position + center * (moon_radius + 2.0)
	player.velocity = Vector3.ZERO
	for _i in 150:
		await physics_frame
	var floor_radius: float = moon.surface_radius(center)
	var local_dist: float = (player.global_position - moon.global_position).length()
	if not player.is_on_floor() or local_dist >= moon_radius:
		_fail("player did not settle inside crater")
		return
	if absf(local_dist - floor_radius - 0.85) > 0.2:
		_fail("player crater floor height mismatch")
		return

	print(
		"SMOKE_OK moon=%d earth=%d player_radius=%.4f moon_radius=%.4f"
		% [moon_n, earth_n, local_dist, moon_radius]
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
