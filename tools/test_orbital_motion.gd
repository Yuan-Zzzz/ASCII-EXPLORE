extends SceneTree
## 轨道层级回归：太阳绕黑洞、地球绕太阳、月球绕地球，角色随月球移动。

const OrbitalMotionScript = preload("res://features/moon_walk/orbital_motion.gd")
const EPSILON := 0.001


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/moon_walk.tscn") as PackedScene
	if packed == null:
		return _fail("加载 moon_walk.tscn")
	var main := packed.instantiate()

	# 在进树前读取场景里保存的初始变换，作为 t=0 的基准。
	var sun_authored: Vector3 = (main.get_node("SkyPivot/SunHost") as Node3D).transform.origin
	var earth_authored: Vector3 = (main.get_node("SkyPivot/Earth") as Node3D).transform.origin
	var moon_authored: Vector3 = (main.get_node("Moon") as Node3D).transform.origin
	root.add_child(main)
	await process_frame

	var motion = main.get_node_or_null("Orbits")
	var black_hole := main.get_node_or_null("SkyPivot/BlackHole") as Node3D
	var sun := main.get_node_or_null("SkyPivot/SunHost") as Node3D
	var earth := main.get_node_or_null("SkyPivot/Earth") as Node3D
	var moon := main.get_node_or_null("Moon") as Node3D
	var light := main.get_node_or_null("SkyPivot/SunHost/SunLight") as DirectionalLight3D
	var player := main.get_node_or_null("Player") as CharacterBody3D
	if motion == null or black_hole == null or sun == null or earth == null or moon == null:
		return _fail("缺少轨道节点")
	if motion.get_script() != OrbitalMotionScript:
		return _fail("Orbits 节点脚本错误")
	if light == null or player == null:
		return _fail("缺少太阳光或玩家")

	motion.running = false
	motion.evaluate_at(0.0)
	if not (sun.global_position as Vector3).is_equal_approx(sun_authored):
		return _fail("t=0 太阳位置 %s != %s" % [sun.global_position, sun_authored])
	if not (earth.global_position as Vector3).is_equal_approx(earth_authored):
		return _fail("t=0 地球位置 %s != %s" % [earth.global_position, earth_authored])
	if not (moon.global_position as Vector3).is_equal_approx(moon_authored):
		return _fail("t=0 月球位置 %s != %s" % [moon.global_position, moon_authored])

	var black_hole_pos := black_hole.global_position
	var sun_radius := sun.global_position.distance_to(black_hole_pos)
	var earth_radius := earth.global_position.distance_to(sun.global_position)
	var moon_radius := moon.global_position.distance_to(earth.global_position)
	var player_offset := player.global_position - moon.global_position

	if sun_radius < 1.0 or earth_radius < 1.0 or moon_radius < 1.0:
		return _fail("轨道半径无效")
	if absf((moon.global_position as Vector3).y) > EPSILON:
		return _fail("月球初始高度 %s" % moon.global_position.y)

	# 月球 1/4 圈时，地球只转了 1/16 圈，太阳只转了 1/40 圈。
	var quarter: float = motion.moon_period * 0.25
	motion.evaluate_at(quarter)
	if sun.global_position.distance_to(black_hole_pos) > sun_radius + EPSILON:
		return _fail("太阳绕黑洞半径漂移")
	if absf(earth.global_position.distance_to(sun.global_position) - earth_radius) > EPSILON:
		return _fail("地球绕太阳半径漂移")
	if absf(moon.global_position.distance_to(earth.global_position) - moon_radius) > EPSILON:
		return _fail("月球绕地球半径漂移")

	var moon_angle := _orbit_angle(moon.global_position - earth.global_position)
	var moon_angle0 := _orbit_angle(-(earth_authored - moon_authored))
	if absf(wrapf(moon_angle - moon_angle0, -PI, PI) - PI * 0.5) > 0.01:
		return _fail("月球没有在 1/4 周期内转过 90°: %s -> %s" % [moon_angle0, moon_angle])

	var earth_angle := _orbit_angle(earth.global_position - sun.global_position)
	var earth_angle0 := _orbit_angle(earth_authored - sun_authored)
	var earth_expected: float = quarter / motion.earth_period * TAU
	if absf(wrapf(earth_angle - earth_angle0, -PI, PI) - earth_expected) > 0.01:
		return _fail("地球轨道角速度错误: %s" % wrapf(earth_angle - earth_angle0, -PI, PI))

	var sun_angle := _orbit_angle(sun.global_position - black_hole_pos)
	var sun_angle0 := _orbit_angle(sun_authored - black_hole_pos)
	var sun_expected: float = quarter / motion.sun_period * TAU
	if absf(wrapf(sun_angle - sun_angle0, -PI, PI) - sun_expected) > 0.01:
		return _fail("太阳轨道角速度错误: %s" % wrapf(sun_angle - sun_angle0, -PI, PI))

	# 玩家与月面保持相对位置，月球高度不变。
	if not (player.global_position - moon.global_position).is_equal_approx(player_offset):
		return _fail("玩家没有被月球正确携带")
	if absf((moon.global_position as Vector3).y) > EPSILON:
		return _fail("月球高度在运动中漂移: %s" % moon.global_position.y)

	# 平行光跟随太阳，并始终照向月球。
	if light.global_position.distance_to(sun.global_position) > EPSILON:
		return _fail("太阳光没有跟随太阳")
	var aim := (-light.global_basis.z).normalized()
	if aim.dot((moon.global_position - sun.global_position).normalized()) < 0.999:
		return _fail("太阳光方向错误 aim=%s" % aim)

	# 真实物理帧里让轨道跑起来，确认角色仍站在移动的月球上。
	motion.running = true
	motion.time_scale = 4.0
	var moon_start := moon.global_position
	for _i in 180:
		await physics_frame
	if moon.global_position.distance_to(moon_start) < 1.0:
		return _fail("物理帧期间月球没有移动")
	if not player.is_on_floor():
		return _fail("角色没有站在移动的月球上")
	var dist := player.global_position.distance_to(moon.global_position)
	if dist <= moon.radius or dist > moon.radius + 4.0:
		return _fail("角色相对月心距离异常 %s" % dist)

	# 在移动的月面上继续行走，确认输入、碰撞和轨道携带可以同时工作。
	var walk_start := player.global_position - moon.global_position
	Input.action_press("move_forward")
	for _i in 120:
		await physics_frame
	Input.action_release("move_forward")
	var walk_delta := (player.global_position - moon.global_position) - walk_start
	if walk_delta.length() < 5.0:
		return _fail("在移动月面上行走距离过短 %s" % walk_delta.length())
	if not player.is_on_floor():
		return _fail("行走后离开月面")

	print(
		"ORBIT_OK sun_r=%.2f earth_r=%.2f moon_r=%.2f player_r=%.2f moved=%.2f walk=%.2f"
		% [sun_radius, earth_radius, moon_radius, dist, moon.global_position.distance_to(moon_start), walk_delta.length()]
	)
	quit(0)


func _orbit_angle(offset: Vector3) -> float:
	return atan2(offset.x, offset.z)


func _fail(reason: String) -> void:
	printerr("ORBIT_FAIL %s" % reason)
	quit(1)
