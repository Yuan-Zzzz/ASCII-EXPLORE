@tool
class_name GlyphField
extends MultiMeshInstance3D
## 在 MeshInstance3D 表面生成字符点 MultiMesh（Three.js GlyphField 思路）。

const SurfaceSamplerScript = preload("res://features/ascii/surface_sampler.gd")
const REBUILD_DELAY_MSEC := 80

@export var ramp: AsciiRamp:
	set(value):
		if ramp == value:
			return
		ramp = value
		_request_rebuild()

@export var spacing: float = 0.35:
	set(value):
		if spacing == value:
			return
		spacing = value
		_request_rebuild()

@export var seed: int = 1:
	set(value):
		if seed == value:
			return
		seed = value
		_request_rebuild()

@export var glyph_px: float = 12.0:
	set(value):
		if glyph_px == value:
			return
		glyph_px = value
		_apply_live_params()

@export var tint: Color = Color(0.85, 0.9, 1.0):
	set(value):
		if tint == value:
			return
		tint = value
		_apply_live_params()

@export var light_dir: Vector3 = Vector3(0.4, 0.8, 0.3):
	set(value):
		if light_dir == value:
			return
		light_dir = value
		_apply_live_params()

@export var rebuild_on_ready: bool = true:
	set(value):
		if rebuild_on_ready == value:
			return
		rebuild_on_ready = value
		_request_rebuild()

var _shader_mat: ShaderMaterial
var _rebuild_at_msec := 0
var _rebuild_waiting := false


func _ready() -> void:
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	if rebuild_on_ready:
		rebuild()


func _notification(what: int) -> void:
	# 编辑器保存会把当前 multimesh 嵌进 tscn，所以先丢掉生成结果。
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_clear_generated()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		if rebuild_on_ready and is_inside_tree():
			rebuild()


func _request_rebuild() -> void:
	if not is_inside_tree() or not rebuild_on_ready:
		return
	_rebuild_at_msec = Time.get_ticks_msec() + REBUILD_DELAY_MSEC
	if _rebuild_waiting:
		return
	_rebuild_waiting = true
	_wait_rebuild()


func _wait_rebuild() -> void:
	# 单帧 delta 很大时，一次 create_timer(0.08) 会在下一帧立刻到期。
	while is_inside_tree() and Time.get_ticks_msec() < _rebuild_at_msec:
		var left_sec := float(_rebuild_at_msec - Time.get_ticks_msec()) / 1000.0
		await get_tree().create_timer(minf(left_sec, 0.05), true).timeout
	_rebuild_waiting = false
	if is_inside_tree() and rebuild_on_ready:
		rebuild()


func _clear_generated() -> void:
	multimesh = null
	material_override = null
	_shader_mat = null


func _apply_live_params() -> void:
	if not is_inside_tree():
		return
	_ensure_material()
	_apply_params()


func rebuild() -> void:
	var host := get_parent() as MeshInstance3D
	if host == null or host.mesh == null:
		push_warning("GlyphField 需要挂在带 mesh 的 MeshInstance3D 下")
		return
	if ramp == null:
		ramp = load("res://features/ascii/ascii_ramp.tres") as AsciiRamp

	var sampled: Dictionary = SurfaceSamplerScript.sample_mesh(host.mesh, spacing, seed)
	var positions: PackedVector3Array = sampled["positions"]
	var normals: PackedVector3Array = sampled["normals"]
	var count: int = positions.size()
	if count == 0:
		multimesh = null
		return

	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = count

	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 17

	for i in count:
		var xf := Transform3D(Basis(), positions[i])
		mm.set_instance_transform(i, xf)
		var n: Vector3 = normals[i]
		mm.set_instance_custom_data(i, Color(n.x, n.y, n.z, rng.randf()))

	multimesh = mm
	_ensure_material()
	_apply_params()


func _ensure_material() -> void:
	if _shader_mat != null:
		material_override = _shader_mat
		return
	var sh: Shader = load("res://features/ascii/glyph_billboard.gdshader") as Shader
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = sh
	material_override = _shader_mat


func _apply_params() -> void:
	if _shader_mat == null or ramp == null:
		return
	_shader_mat.set_shader_parameter("u_atlas", ramp.atlas)
	_shader_mat.set_shader_parameter("u_char_count", ramp.char_count)
	_shader_mat.set_shader_parameter("u_glyph_px", glyph_px)
	_shader_mat.set_shader_parameter("u_tint", Vector3(tint.r, tint.g, tint.b))
	_shader_mat.set_shader_parameter("u_light_dir", light_dir.normalized())
	var vp := get_viewport()
	if vp:
		var sz := vp.get_visible_rect().size
		_shader_mat.set_shader_parameter("u_viewport_size", sz)


func set_glyph_px(px: float) -> void:
	glyph_px = px


func set_mono(on: bool) -> void:
	if _shader_mat:
		_shader_mat.set_shader_parameter("u_mono", 1.0 if on else 0.0)


func set_light_dir(dir: Vector3) -> void:
	light_dir = dir


func sync_viewport_size() -> void:
	if _shader_mat == null:
		return
	var vp := get_viewport()
	if vp:
		_shader_mat.set_shader_parameter("u_viewport_size", vp.get_visible_rect().size)
