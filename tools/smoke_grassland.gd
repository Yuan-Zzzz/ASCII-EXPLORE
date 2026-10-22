extends SceneTree
## 草原场景契约：组件齐全、风与火在动、水面有波、字形场建成、黑洞灯驱动光照。

const SETTLED_FRAMES := 90


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/grassland.tscn") as PackedScene
	if packed == null:
		_fail("load grassland.tscn")
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	for _i in SETTLED_FRAMES:
		await process_frame

	var gust := main.get_node_or_null("GustField") as GustField
	if gust == null:
		_fail("gust field missing")
		return
	if gust.current_state() == "":
		_fail("gust state machine not settled")
		return
	var wind := gust.sample(Vector3(3, 0, 3), 1.0)
	if wind.length_squared() <= 0.0:
		_fail("gust sample returns zero wind")
		return

	var grass := main.get_node_or_null("GrassPatch") as GrassPatch
	if grass == null or grass.multimesh == null:
		_fail("grass patch missing")
		return
	if grass.multimesh.instance_count < 1000:
		_fail("grass instances %s" % grass.multimesh.instance_count)
		return

	var fire := main.get_node_or_null("Bonfire") as Bonfire
	if fire == null:
		_fail("bonfire missing")
		return
	if fire.flame_particle_count() < 10:
		_fail("flame particles %s" % fire.flame_particle_count())
		return
	if fire.get_node_or_null("FireLight") == null:
		_fail("fire light missing")
		return
	var light := fire.get_node("FireLight") as OmniLight3D
	var e0 := light.light_energy
	for _i in 12:
		await process_frame
	if is_equal_approx(light.light_energy, e0):
		_fail("fire light does not flicker")
		return

	var pond := main.get_node_or_null("Pond") as WaterPlane
	if pond == null:
		_fail("pond missing")
		return
	# root 每帧用 gust 覆盖水面风；断言走真实链路：CALM 基线 → 强制 GUST。
	var gust_states: Array = gust.states
	var calm_idx := -1
	var gust_idx := -1
	for i in gust_states.size():
		if gust_states[i].name == "CALM":
			calm_idx = i
		elif gust_states[i].name == "GUST":
			gust_idx = i
	gust._reset_to_state(calm_idx)
	for _i in 30:
		await process_frame
	var calm := pond.wave_normal_at(pond.global_position + Vector3(2, 0, 2))
	if absf(calm.angle_to(Vector3.UP)) > deg_to_rad(35.0):
		_fail("calm water not near-up %s" % calm)
		return
	gust._reset_to_state(gust_idx)
	for _i in 30:
		await process_frame
	var blown := pond.wave_normal_at(pond.global_position + Vector3(2, 0, 2))
	if blown.angle_to(calm) < deg_to_rad(2.0):
		_fail("water normal ignores wind")
		return

	var bh := main.get_node_or_null("BlackHole")
	if bh == null:
		_fail("black hole missing")
		return
	var bh_light: Light3D = bh.light_source()
	if bh_light == null or not bh_light.visible:
		_fail("black hole light missing")
		return

	var fields: Array[GlyphField] = []
	_collect_fields(main, fields)
	if fields.is_empty():
		_fail("no glyph field in scene")
		return
	var lit := fields[0].light_dir.normalized()
	if lit.dot((bh.global_position - fields[0].global_position).normalized()) < 0.0:
		_fail("glyph light does not come from the black hole %s" % lit)
		return

	var player := main.get_node("Player") as CharacterBody3D
	for _i in 60:
		await physics_frame
	if not player.is_on_floor():
		_fail("player not on floor")
		return

	print(
		"SMOKE_OK grass=%d flames=%d wind=%.2f bh_lit=%.2f"
		% [grass.multimesh.instance_count, fire.flame_particle_count(), gust.strength(), lit.length()]
	)
	quit(0)


func _collect_fields(node: Node, out: Array[GlyphField]) -> void:
	if node is GlyphField:
		out.append(node as GlyphField)
	for child in node.get_children():
		_collect_fields(child, out)


func _fail(reason: String) -> void:
	printerr("SMOKE_FAIL %s" % reason)
	quit(1)
