class_name GrassPatch
extends MultiMeshInstance3D
## 草地 MultiMesh：抖动网格撒叶，每叶一个随机朝向的四边形，风采样自 GustField。


const BladeShader := preload("res://features/meadow/grass_blades.gdshader")

@export var patch_size: Vector2 = Vector2(24.0, 24.0)
@export_range(0.1, 4.0, 0.05) var blade_height: float = 1.0
@export_range(0.01, 0.5, 0.005) var blade_width: float = 0.06
@export_range(1, 60000) var blade_count: int = 4000
@export var seed: int = 7
@export var gust_path: NodePath = ^""
@export_range(0.0, 4.0, 0.05) var sway_amount: float = 1.0
@export var tint_a: Color = Color(0.16, 0.34, 0.10)
@export var tint_b: Color = Color(0.55, 0.62, 0.22)

var _gust: GustField
var _material: ShaderMaterial
var _time: float = 0.0


func _ready() -> void:
	_gust = get_node_or_null(gust_path) as GustField
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = BladeShader
		material_override = _material
	rebuild()


func _process(delta: float) -> void:
	_time += delta
	if _gust == null:
		return
	var center := global_transform * Vector3(patch_size.x * 0.5, 0.0, patch_size.y * 0.5)
	var wind := _gust.sample(center, _time)
	_material.set_shader_parameter("u_wind", wind)
	_material.set_shader_parameter("u_gust_strength", _gust.strength())
	_material.set_shader_parameter("u_time", _time)


func rebuild() -> void:
	if _material == null:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(blade_width, blade_height)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = blade_count
	_material.set_shader_parameter("u_blade_height", blade_height)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var grid := maxf(1.0, ceilf(sqrt(float(blade_count))))
	for i in blade_count:
		var cx := float(i % int(grid))
		var cz := float(i / int(grid))
		var x := ((cx + rng.randf() * 0.9) / grid - 0.5) * patch_size.x
		var z := ((cz + rng.randf() * 0.9) / grid - 0.5) * patch_size.y
		var t := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), Vector3(x, 0.0, z))
		mm.set_instance_transform(i, t)
		mm.set_instance_custom_data(
			i,
			Color(rng.randf(), rng.randf_range(-1.0, 1.0), rng.randf(), rng.randf_range(0.7, 1.3))
		)
	multimesh = mm
	_material.set_shader_parameter("u_sway", sway_amount)
	_material.set_shader_parameter("u_tint_a", Vector3(tint_a.r, tint_a.g, tint_a.b))
	_material.set_shader_parameter("u_tint_b", Vector3(tint_b.r, tint_b.g, tint_b.b))
