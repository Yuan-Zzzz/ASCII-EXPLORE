class_name WaterPlane
extends MeshInstance3D
## 水面：细分 PlaneMesh + Gerstner-lite 三波着色器，波向跟随风场方向。


const WaterShader := preload("res://features/meadow/water.gdshader")

@export var size: Vector2 = Vector2(40.0, 40.0)
@export_range(1, 256) var subdivisions: int = 96
@export var wave_steepness: Array[float] = [0.18, 0.14, 0.10]
@export var wave_lengths: Array[float] = [11.0, 6.5, 3.8]

var _material: ShaderMaterial
var _time: float = 0.0
var _wind_strength: float = 0.0
var _wind_direction := Vector3(1.0, 0.0, 0.0)
var _wave_dirs: Array[Vector2] = [Vector2(1.0, 0.3), Vector2(-0.7, 0.8), Vector2(0.2, -1.0)]


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	mesh = plane
	_material = ShaderMaterial.new()
	_material.shader = WaterShader
	material_override = _material
	_push_waves()


func _process(delta: float) -> void:
	_time += delta
	_material.set_shader_parameter("u_time", _time)
	_material.set_shader_parameter("u_wind_strength", _wind_strength)


func set_wind(strength: float, dir: Vector3) -> void:
	_wind_strength = clampf(strength, 0.0, 1.2)
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 1.0e-8:
		return
	flat = flat.normalized()
	var angle := _wind_direction.signed_angle_to(flat, Vector3.UP)
	if absf(angle) > deg_to_rad(10.0):
		for i in _wave_dirs.size():
			_wave_dirs[i] = _wave_dirs[i].rotated(angle * 0.5)
		_wind_direction = _wind_direction.rotated(Vector3.UP, angle * 0.5).normalized()
		_push_waves()


func wave_normal_at(pos: Vector3) -> Vector3:
	# 与顶点着色器同式的解析法线：供测试与浮动物体使用。
	var local := global_transform.affine_inverse() * pos
	var normal := Vector3(0.0, 1.0, 0.0)
	var amp_scale := 0.2 + 0.8 * _wind_strength
	for i in _wave_dirs.size():
		var dir := _wave_dirs[i].normalized()
		var steep := wave_steepness[i] * amp_scale
		var wavelength: float = wave_lengths[i]
		var k := TAU / wavelength
		var phase_speed := sqrt(9.8 / k)
		var phase := k * dir.dot(Vector2(local.x, local.z)) - _time * phase_speed * (0.8 + 0.4 * _wind_strength)
		normal.x -= dir.x * steep * cos(phase)
		normal.z -= dir.y * steep * cos(phase)
	return global_basis * normal.normalized()


func _push_waves() -> void:
	if _material == null:
		return
	var packed: Array[Vector4] = []
	for i in _wave_dirs.size():
		packed.append(Vector4(_wave_dirs[i].x, _wave_dirs[i].y, wave_steepness[i], wave_lengths[i]))
	_material.set_shader_parameter("u_waves", packed)
