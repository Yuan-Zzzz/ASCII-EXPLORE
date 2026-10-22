extends SceneTree
## 草原组件运行时回归：风场状态机、草叶 MultiMesh、篝火粒子、水面法线、天空着色器。
##   godot --headless --path . --script res://tools/test_meadow.gd

var transitions := 0


func _initialize() -> void:
	call_deferred("_run")


func _on_wind_state(_state_name: String) -> void:
	transitions += 1


func _run() -> void:
	var gust := GustField.new()
	var calm := GustField.GustState.new()
	calm.name = "CALM"
	calm.amplitude_mean = 0.02
	calm.amplitude_variance = 0.0
	calm.duration_mean = 1.5
	calm.duration_variance = 0.0
	var blow := GustField.GustState.new()
	blow.name = "GUST"
	blow.amplitude_mean = 1.0
	blow.amplitude_variance = 0.0
	blow.duration_mean = 0.3
	blow.duration_variance = 0.0
	gust.states = [calm, blow]
	gust.wind_state_changed.connect(_on_wind_state)
	root.add_child(gust)

	var grass := GrassPatch.new()
	grass.blade_count = 64
	root.add_child(grass)

	var fire := Bonfire.new()
	root.add_child(fire)

	var water := WaterPlane.new()
	root.add_child(water)

	for _i in 30:
		await process_frame

	var max_wind := 0.0
	var max_strength := 0.0
	var saw_calm := false
	for _i in 240:
		await process_frame
		var wind := gust.sample(Vector3(3.0, 0.0, -2.0), 1.0)
		max_wind = maxf(max_wind, wind.length())
		max_strength = maxf(max_strength, gust.strength())
		saw_calm = saw_calm or gust.strength() < 0.1
	if transitions < 1:
		return _fail("gust state machine never transitioned (%d)" % transitions)
	if max_strength <= 0.1:
		return _fail("gust envelope never rose (strength=%.3f)" % max_strength)
	if max_wind <= 0.1:
		return _fail("wind sample stayed near zero (%.3f)" % max_wind)
	if not saw_calm:
		return _fail("gust never fell back toward calm")

	var mm := grass.multimesh
	if mm == null or mm.instance_count != grass.blade_count or mm.instance_count <= 0:
		return _fail("grass multimesh count %s" % (mm.instance_count if mm else -1))

	if fire.flame_particle_count() <= 0:
		return _fail("bonfire has no live particles")
	var light := fire.get_node_or_null("FireLight") as OmniLight3D
	if light == null:
		return _fail("FireLight missing")
	if fire.get_node_or_null("FireAudio") == null:
		return _fail("FireAudio missing")
	if fire.get_node_or_null("Flames") == null:
		return _fail("Flames missing")
	var energy_a := light.light_energy
	for _i in 24:
		await process_frame
	var energy_b := light.light_energy
	if is_equal_approx(energy_a, energy_b):
		return _fail("FireLight energy static %.3f" % energy_a)

	water.set_wind(0.0, Vector3.RIGHT)
	var calm_normal := water.wave_normal_at(Vector3(1.3, 0.0, 0.7))
	var calm_tilt := absf(calm_normal.angle_to(Vector3.UP))
	if calm_tilt > deg_to_rad(15.0):
		return _fail("calm normal not near UP (%s)" % calm_normal)
	water.set_wind(1.0, Vector3.RIGHT)
	var max_tilt := 0.0
	for _i in 120:
		await process_frame
		var n := water.wave_normal_at(Vector3(1.3, 0.0, 0.7))
		max_tilt = maxf(max_tilt, absf(n.angle_to(Vector3.UP)))
	if max_tilt <= calm_tilt + deg_to_rad(2.0):
		return _fail("wind did not tilt water (tilt=%.2f deg)" % rad_to_deg(max_tilt))

	var sky_shader := load("res://features/meadow/meadow_sky.gdshader") as Shader
	if sky_shader == null:
		return _fail("meadow_sky failed to load")

	print(
		"MEADOW_OK transitions=%d gust_strength=%.3f blades=%d flames=%d light=%.3f..%.3f tilt=%.2fdeg" % [
			transitions, max_strength, mm.instance_count, fire.flame_particle_count(),
			energy_a, energy_b, rad_to_deg(max_tilt),
		]
	)
	quit(0)


func _fail(reason: String) -> void:
	printerr("MEADOW_FAIL %s" % reason)
	quit(1)
