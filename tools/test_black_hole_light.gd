extends SceneTree
## 黑洞作为光源的回归：
## 1. 月面字符着色器换成了带 BEAM_ENABLED 的版本，且光束参数已经写进材质；
## 2. 盘面光束在月面上分成亮、暗两半，并在“盘面的背面”迅速变暗；
## 3. 月面字段重建（例如调用 rebuild）后仍是带光束的着色器，参数不丢；
## 4. 关掉 light_energy 等于没有这盏灯；
## 5. 从月面看黑洞的透镜只在镜头真的能看到黑洞时出现。
##   godot --headless --path . --script res://tools/test_black_hole_light.gd

const TAG := "BH_LIGHT"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/moon_walk.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var bh = main.get_node("SkyPivot/BlackHole")
	var moon = main.get_node("Moon") as Node3D
	var light: SpotLight3D = bh.light_source()

	# 1. 黑洞是一盏真实光源：位置在黑洞，照向月心，能量可调。
	if light == null or not light.visible:
		return _fail("black hole light missing")
	if light.global_position.distance_to(bh.global_position) > 0.01:
		return _fail("light is not at the black hole")
	var aim: Vector3 = -light.global_basis.z
	if aim.dot((moon.global_position - bh.global_position).normalized()) < 0.999:
		return _fail("light does not aim at the moon")
	var near_angle: float = light.spot_angle
	if near_angle < 1.0 or near_angle > 60.0:
		return _fail("unexpected spot angle %s" % near_angle)

	# 2. 视界在月面上的大小随黑洞拉远而变小（轨道运动时张角跟着更新）。
	var distance: float = bh.global_position.distance_to(moon.global_position)
	var shadow: float = bh.optics.shadow_radius()
	var expected: float = rad_to_deg(asin(shadow * bh._light_spread / distance))
	if absf(near_angle - expected) > 0.5:
		return _fail("spot angle %s != shadow cone %s" % [near_angle, expected])

	# 3. 关灯。
	bh.light_energy = 0.0
	await process_frame
	if light.visible:
		return _fail("light_energy = 0 must hide the light")
	bh.light_energy = 1.2
	await process_frame
	if not light.visible:
		return _fail("light did not come back")

	# 4. 从月面看黑洞的透镜只在镜头看得到黑洞时出现。
	main.get_node("Orbits").running = false
	main.surface_render_mode = 1
	await process_frame
	var cam = main.get_node("Player/Camera3D") as Camera3D
	cam.look_at(bh.global_position, Vector3.UP)
	await process_frame
	await process_frame
	var lens: MeshInstance3D = bh.moon_lens()
	if lens == null or not lens.visible:
		return _fail("moon lens hidden while facing the black hole")
	if not (lens.global_position as Vector3).is_equal_approx(bh.global_position):
		return _fail("moon lens moved away from the black hole")
	cam.rotation = Vector3(deg_to_rad(80.0), 0.0, 0.0)
	await process_frame
	await process_frame
	if lens.visible:
		return _fail("moon lens visible while looking away")

	# 5. 月面字母的 Bayer 覆盖层使用“未抖动的光照画面”，黑洞的光能进抖动模式。
	var overlay: ShaderMaterial = main.get_node("Moon/MoonMesh").material_overlay
	if overlay == null or float(overlay.get_shader_parameter("lit_weight")) != 1.0:
		return _fail("moon bayer overlay ignores lighting")
	var earth_overlay: ShaderMaterial = main.get_node("SkyPivot/Earth").material_overlay
	if earth_overlay != null and float(earth_overlay.get_shader_parameter("lit_weight")) != 0.0:
		return _fail("only the moon bayer overlay should use the lit weight")
	main.surface_render_mode = 2
	print("%s_OK spot=%.2fdeg" % [TAG, near_angle])
	quit(0)


func _fail(message: String) -> void:
	print("%s_FAIL: %s" % [TAG, message])
	quit(1)