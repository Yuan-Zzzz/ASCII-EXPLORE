extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/moon_walk.tscn") as PackedScene
	if packed == null:
		_fail("failed to load scenes/moon_walk.tscn")
		return

	var moon: Node = packed.instantiate()
	root.add_child(moon)
	await process_frame
	await process_frame

	var player := moon.get_node_or_null("Player")
	if not (player is CharacterBody3D):
		_fail("player CharacterBody3D missing")
		return

	var moon_field := _field(moon, ^"Moon/MoonMesh/GlyphField")
	var earth_field := _field(moon, ^"SkyPivot/Earth/GlyphField")
	var sun_field := _field(moon, ^"SkyPivot/SunHost/GlyphField")
	if moon_field < 0 or earth_field < 0 or sun_field < 0:
		_fail("glyph field missing moon=%d earth=%d sun=%d" % [moon_field, earth_field, sun_field])
		return
	if moon_field <= 100 or moon_field >= 80000:
		_fail("moon glyph count %d outside 100..80000" % moon_field)
		return
	if earth_field <= 0 or sun_field <= 0:
		_fail("earth=%d sun=%d" % [earth_field, sun_field])
		return

	var shape_node := moon.get_node("Moon/CollisionShape3D") as CollisionShape3D
	var sphere := shape_node.shape as SphereShape3D
	var dist := (player as Node3D).global_position.length()
	var expected := sphere.radius + 1.5
	if absf(dist - expected) > 0.5:
		_fail("player dist %.3f expected %.3f" % [dist, expected])
		return

	print("SMOKE_MOON_WALK player_dist=%.3f expected=%.3f moon=%d earth=%d sun=%d" % [dist, expected, moon_field, earth_field, sun_field])
	quit(0)


func _field(moon: Node, path: NodePath) -> int:
	var node := moon.get_node_or_null(path)
	if node == null:
		return -1
	var mesh: MultiMesh = node.get("multimesh") as MultiMesh
	if mesh == null:
		return 0
	return mesh.instance_count


func _fail(message: String) -> void:
	printerr("SMOKE_MOON_WALK " + message)
	quit(1)
