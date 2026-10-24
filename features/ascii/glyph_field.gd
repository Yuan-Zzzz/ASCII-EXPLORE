@tool
class_name GlyphField
extends MultiMeshInstance3D
## 在 MeshInstance3D 表面生成字符点 MultiMesh（Three.js GlyphField 思路）。
## 挂到宿主下即应用 ASCII + Bayer：采样、depth shell、字形 Bayer 由本节点统一处理。

signal rebuilt

const SurfaceSamplerScript = preload("res://features/ascii/surface_sampler.gd")
const LENS_LAYER := 10
const VOID_SHELL_COLOR := Color(0, 0, 0, 1)

@export var ramp: AsciiRamp
@export_range(0.05, 10.0, 0.005, "or_greater") var spacing: float = 0.35
@export var seed: int = 1
@export var glyph_px: float = 12.0
@export var tint: Color = Color(0.85, 0.9, 1.0)
@export var emission_energy: float = 0.0
@export_range(1.0, 8.0, 1.0) var dither_pixel_size: float = 2.0
@export_range(2.0, 16.0, 1.0) var dither_color_levels: float = 4.0
## Host is a light source. Depth shell becomes HDR emissive core; glyph Bayer overlay stays off.
@export var emissive_body: bool = false
## Drop the host mesh from the black-hole lens cull mask so the lens samples sky without this body.
@export var hide_from_lens: bool = false
## When false, restore the host's original materials and hide glyphs (raw / post demos).
@export var effect_enabled: bool = true
## Emissive host core multiplier (HDR albedo / emission energy).
@export_range(0.0, 12.0, 0.1) var core_energy: float = 4.0
@export var shell_color: Color = VOID_SHELL_COLOR
@export var rebuild_on_ready: bool = true:
	set(value):
		rebuild_on_ready = value
		notify_property_list_changed()

var _dither_mat: ShaderMaterial
var _shader_mat: ShaderMaterial
var _preview_mesh: Mesh
var _preview_signature: Array = []
var _preview_wait: float = 0.0
var _preview_dirty: bool = false
var _preview_thread: Thread
var _preview_revision: int = 0
var _running_revision: int = 0
var _saved_host_override: Material
var _saved_host_overlay: Material
var _host_captured: bool = false
var _host_signature: Array = []


# 自动重建的预览资源不写入场景；手动烘焙模式仍保留资源。
func _validate_property(property: Dictionary) -> void:
	if rebuild_on_ready and property.name in [&"multimesh", &"material_override"]:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_STORAGE


func _ready() -> void:
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	var host := get_parent() as MeshInstance3D
	if host != null:
		_preview_signature = [host.mesh, spacing, seed]
		if hide_from_lens:
			host.layers = host.layers & ~(1 << (LENS_LAYER - 1))
	_sync_host_surface(true)
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
	_sync_host_surface(false)
	_apply_params()


func _queue_preview() -> void:
	_preview_revision += 1
	_preview_dirty = true
	_preview_wait = 0.25


func _exit_tree() -> void:
	if _preview_thread != null:
		_preview_thread.wait_to_finish()
		_preview_thread = null
	_restore_host_surface()


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


func _glyph_dither_wanted() -> bool:
	return effect_enabled and not emissive_body


func _apply_params() -> void:
	if _shader_mat == null or ramp == null:
		return
	_shader_mat.set_shader_parameter("u_atlas", ramp.atlas)
	_shader_mat.set_shader_parameter("u_char_count", ramp.char_count)
	_shader_mat.set_shader_parameter("u_glyph_px", glyph_px)
	_shader_mat.set_shader_parameter("u_tint", Vector3(tint.r, tint.g, tint.b))
	_shader_mat.set_shader_parameter("u_emission_energy", emission_energy)
	var vp := get_viewport()
	if vp:
		var sz := vp.get_visible_rect().size
		_shader_mat.set_shader_parameter("u_viewport_size", sz)

	if _glyph_dither_wanted():
		if _dither_mat == null:
			_dither_mat = ShaderMaterial.new()
			_dither_mat.shader = preload("res://features/ascii/glyph_bayer_overlay.gdshader")
		for parameter in ["u_atlas", "u_char_count", "u_glyph_px", "u_depth_pull"]:
			_dither_mat.set_shader_parameter(parameter, _shader_mat.get_shader_parameter(parameter))
		_dither_mat.set_shader_parameter("u_dither_pixel_size", dither_pixel_size)
		_dither_mat.set_shader_parameter("u_dither_color_levels", dither_color_levels)
		material_overlay = _dither_mat
	else:
		material_overlay = null


func _sync_host_surface(force: bool) -> void:
	var host := get_parent() as MeshInstance3D
	if host == null:
		return
	var signature := [
		effect_enabled,
		emissive_body,
		tint,
		shell_color,
		core_energy,
		emission_energy,
		dither_pixel_size,
		dither_color_levels,
	]
	if not force and signature == _host_signature:
		return
	_host_signature = signature
	_capture_host_if_needed(host)
	if not effect_enabled:
		visible = false
		_restore_host_surface()
		return
	visible = true
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	if emissive_body:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = _emissive_core_color(tint)
		material.emission_enabled = true
		material.emission = tint
		material.emission_energy_multiplier = core_energy
		host.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = shell_color
		host.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	host.material_override = material
	host.material_overlay = null


func _emissive_core_color(color: Color) -> Color:
	return Color(color.r * core_energy, color.g * core_energy, color.b * core_energy, 1.0)


func _capture_host_if_needed(host: MeshInstance3D) -> void:
	if _host_captured:
		return
	_saved_host_override = host.material_override
	_saved_host_overlay = host.material_overlay
	_host_captured = true


func _restore_host_surface() -> void:
	if not _host_captured:
		return
	var host := get_parent() as MeshInstance3D
	if host == null:
		return
	host.material_override = _saved_host_override
	host.material_overlay = _saved_host_overlay
	_host_signature = []


func set_glyph_px(px: float) -> void:
	glyph_px = px
	if _shader_mat:
		_shader_mat.set_shader_parameter("u_glyph_px", glyph_px)
	if _dither_mat:
		_dither_mat.set_shader_parameter("u_glyph_px", glyph_px)


func set_mono(on: bool) -> void:
	if _shader_mat:
		_shader_mat.set_shader_parameter("u_mono", 1.0 if on else 0.0)


func sync_viewport_size() -> void:
	if _shader_mat == null:
		return
	var vp := get_viewport()
	if vp:
		_shader_mat.set_shader_parameter("u_viewport_size", vp.get_visible_rect().size)
