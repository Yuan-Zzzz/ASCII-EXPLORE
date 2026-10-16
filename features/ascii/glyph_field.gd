@tool
class_name GlyphField
extends MultiMeshInstance3D
## 在 MeshInstance3D 表面生成字符点 MultiMesh（Three.js GlyphField 思路）。

signal rebuilt

const SurfaceSamplerScript = preload("res://features/ascii/surface_sampler.gd")

@export var ramp: AsciiRamp
@export_range(0.05, 10.0, 0.005, "or_greater") var spacing: float = 0.35
@export var seed: int = 1
@export var glyph_px: float = 12.0
@export var tint: Color = Color(0.85, 0.9, 1.0)
@export var light_dir: Vector3 = Vector3(0.4, 0.8, 0.3)
@export var ambient: float = 0.35
@export var rebuild_on_ready: bool = true:
	set(value):
		rebuild_on_ready = value
		notify_property_list_changed()

var _shader_mat: ShaderMaterial
var _preview_mesh: Mesh
var _preview_signature: Array = []
var _preview_wait: float = 0.0
var _preview_dirty: bool = false
var _preview_thread: Thread
var _preview_revision: int = 0
var _running_revision: int = 0


# 自动重建的预览资源不写入场景；手动烘焙模式仍保留资源。
func _validate_property(property: Dictionary) -> void:
	if rebuild_on_ready and property.name in [&"multimesh", &"material_override"]:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_STORAGE


func _ready() -> void:
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	var host := get_parent() as MeshInstance3D
	if host != null:
		_preview_signature = [host.mesh, spacing, seed]
	if rebuild_on_ready:
		if Engine.is_editor_hint():
			_queue_preview()
		else:
			_rebuild_sync()


# 编辑器只在采样输入变化后重建，拖动检查器参数时合并更新。
func _process(delta: float) -> void:
	var host := get_parent() as MeshInstance3D
	if host == null:
		return
	if _preview_mesh != host.mesh:
		if is_instance_valid(_preview_mesh) and _preview_mesh.changed.is_connected(_queue_preview):
			_preview_mesh.changed.disconnect(_queue_preview)
		_preview_mesh = host.mesh
		if _preview_mesh != null:
			_preview_mesh.changed.connect(_queue_preview)
	var signature := [host.mesh, spacing, seed]
	if signature != _preview_signature:
		_preview_signature = signature
		_queue_preview()
	_poll_preview()
	if _preview_dirty:
		_preview_wait -= delta
		if _preview_wait <= 0.0 and _preview_thread == null:
			_preview_dirty = false
			_start_preview()
	_apply_params()


func _queue_preview() -> void:
	_preview_revision += 1
	_preview_dirty = true
	_preview_wait = 0.25


func _exit_tree() -> void:
	if _preview_thread != null:
		_preview_thread.wait_to_finish()
		_preview_thread = null


func _start_preview() -> void:
	var host := get_parent() as MeshInstance3D
	if host == null or host.mesh == null:
		multimesh = null
		return
	# Mesh 数据只在主线程读取，后台仅计算独立的数组。
	var arrays := SurfaceSamplerScript._mesh_arrays(host.mesh)
	_running_revision = _preview_revision
	_preview_thread = Thread.new()
	var error := _preview_thread.start(_build_buffer.bind(arrays, spacing, seed), Thread.PRIORITY_LOW)
	if error != OK:
		_preview_thread = null
		push_warning("无法启动字形预览线程：%s" % error)


func _poll_preview() -> void:
	if _preview_thread == null or _preview_thread.is_alive():
		return
	var result: Dictionary = _preview_thread.wait_to_finish()
	_preview_thread = null
	if _running_revision == _preview_revision:
		_apply_buffer(result)


func rebuild() -> void:
	# 编辑器和运行时控制面板均合并快速调参，保留旧预览直到新结果完成。
	if is_inside_tree():
		_queue_preview()
		return
	_rebuild_sync()


func _rebuild_sync() -> void:
	var host := get_parent() as MeshInstance3D
	if host == null or host.mesh == null:
		multimesh = null
		push_warning("GlyphField 需要挂在带 mesh 的 MeshInstance3D 下")
		return
	_apply_buffer(_build_buffer(SurfaceSamplerScript._mesh_arrays(host.mesh), spacing, seed))


static func _build_buffer(arrays: Array, gap: float, sample_seed: int) -> Dictionary:
	var sampled: Dictionary = SurfaceSamplerScript.sample_arrays(arrays, maxf(gap, 0.05), sample_seed)
	var positions: PackedVector3Array = sampled["positions"]
	var normals: PackedVector3Array = sampled["normals"]
	var buffer := PackedFloat32Array()
	buffer.resize(positions.size() * 16)
	var rng := RandomNumberGenerator.new()
	rng.seed = sample_seed + 17
	for i in positions.size():
		var offset := i * 16
		var p := positions[i]
		var n := normals[i]
		buffer[offset] = 1.0
		buffer[offset + 3] = p.x
		buffer[offset + 5] = 1.0
		buffer[offset + 7] = p.y
		buffer[offset + 10] = 1.0
		buffer[offset + 11] = p.z
		buffer[offset + 12] = n.x
		buffer[offset + 13] = n.y
		buffer[offset + 14] = n.z
		buffer[offset + 15] = rng.randf()
	return {"buffer": buffer, "count": positions.size()}


func _apply_buffer(result: Dictionary) -> void:
	if ramp == null:
		ramp = load("res://features/ascii/ascii_ramp.tres") as AsciiRamp
	if result.count == 0:
		multimesh = null
		rebuilt.emit()
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = result.count
	mm.buffer = result.buffer
	multimesh = mm
	_ensure_material()
	_apply_params()
	rebuilt.emit()


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
	_shader_mat.set_shader_parameter("u_ambient", ambient)
	var vp := get_viewport()
	if vp:
		var sz := vp.get_visible_rect().size
		_shader_mat.set_shader_parameter("u_viewport_size", sz)


func set_glyph_px(px: float) -> void:
	glyph_px = px
	if _shader_mat:
		_shader_mat.set_shader_parameter("u_glyph_px", glyph_px)


func set_mono(on: bool) -> void:
	if _shader_mat:
		_shader_mat.set_shader_parameter("u_mono", 1.0 if on else 0.0)


func set_light_dir(dir: Vector3) -> void:
	light_dir = dir
	if _shader_mat:
		_shader_mat.set_shader_parameter("u_light_dir", light_dir.normalized())


func set_ambient(amount: float) -> void:
	ambient = amount
	if _shader_mat:
		_shader_mat.set_shader_parameter("u_ambient", ambient)


func sync_viewport_size() -> void:
	if _shader_mat == null:
		return
	var vp := get_viewport()
	if vp:
		_shader_mat.set_shader_parameter("u_viewport_size", vp.get_visible_rect().size)
