@tool
class_name GlyphField
extends MultiMeshInstance3D
## 在 Mesh 表面 / 特征棱生成字符点（对齐 threejs GlyphField）。
## 单网格：挂在 MeshInstance3D 下。场景级：挂在父节点下，自动覆盖子树全部网格。
## 颜色取自宿主材质 albedo；无 tint。

signal rebuilt

const SurfaceSamplerScript = preload("res://features/ascii/surface_sampler.gd")
const LENS_LAYER := 10
const VOID_SHELL_COLOR := Color(0, 0, 0, 1)
const EDGE_CHILD := &"__GlyphEdge"
const MANAGED_META := &"_glyph_field_owner"

@export var ramp: AsciiRamp
@export_range(0.02, 10.0, 0.005, "or_greater") var spacing: float = 0.35
@export_range(0.008, 10.0, 0.001, "or_greater") var edge_step: float = 0.2
@export_range(1.0, 89.0, 0.5) var edge_threshold: float = 25.0
@export var sample_surface: bool = true
@export var sample_edges: bool = true
@export var seed: int = 1
## 开启后 seed 随时间递增，驱动采样与字符抖动持续变化。
@export var animate_seed: bool = false
## 每隔多少秒将 seed +1（越小变化越快）。
@export_range(0.05, 10.0, 0.05, "or_greater", "suffix:s") var seed_interval: float = 0.5
@export var glyph_px: float = 12.0
## 近距密烘焙 + 远处 shader 抽稀/字号钳制；关闭时仅用 glyph_px，不抽稀。
@export var lod_enabled: bool = false
@export_range(0.1, 500.0, 0.1, "or_greater") var lod_near: float = 2.0
@export_range(0.2, 2000.0, 0.1, "or_greater") var lod_far: float = 40.0
@export_range(1.0, 128.0, 0.5) var glyph_px_near: float = 28.0
@export_range(1.0, 128.0, 0.5) var glyph_px_far: float = 14.0
@export_range(0.01, 1.0, 0.01) var keep_near: float = 1.0
@export_range(0.01, 1.0, 0.01) var keep_far: float = 0.2
## 棱边默认不抽稀（shader 内轮廓点始终保留）；保留导出以便特殊场景手动削弱。
@export_range(0.01, 1.0, 0.01) var edge_keep_near: float = 1.0
@export_range(0.01, 1.0, 0.01) var edge_keep_far: float = 1.0
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
@export var light_direction: Vector3 = Vector3(0.45, 0.75, 0.4)
@export_range(0.0, 1.0, 0.01) var ambient: float = 0.22
## 场景模式下采样根；空则用本节点的父节点。
@export var root_path: NodePath = NodePath()
@export var rebuild_on_ready: bool = true:
	set(value):
		rebuild_on_ready = value
		notify_property_list_changed()

var _preview_wait: float = 0.0
var _preview_dirty: bool = false
var _preview_thread: Thread
var _preview_revision: int = 0
var _running_revision: int = 0
var _preview_signature: Array = []
var _pending_jobs: Array = []

# host_id -> { override, overlay, albedo, emissive, emission_color }
var _host_state: Dictionary = {}
var _managed: Array[Dictionary] = []
var _mono: float = 0.0
var _dither_cache: Dictionary = {}  # key "edge"|"surface" -> ShaderMaterial
var _seed_accum: float = 0.0


func _validate_property(property: Dictionary) -> void:
	if rebuild_on_ready and property.name in [&"multimesh", &"material_override", &"material_overlay"]:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_STORAGE


func _ready() -> void:
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	if hide_from_lens:
		for host in _iter_hosts():
			host.layers = host.layers & ~(1 << (LENS_LAYER - 1))
	_sync_all_hosts(true)
	if rebuild_on_ready:
		# 表面+棱边采样可能很重：编辑器与运行时都走后台线程，避免卡住主线程。
		_queue_preview()
		if not Engine.is_editor_hint():
			_preview_wait = 0.0


func _process(delta: float) -> void:
	_tick_animate_seed(delta)
	var signature := _input_signature()
	if signature != _preview_signature:
		_preview_signature = signature
		_queue_preview()
	_poll_preview()
	if _preview_dirty:
		_preview_wait -= delta
		if _preview_wait <= 0.0 and _preview_thread == null:
			_preview_dirty = false
			_start_preview()
	_sync_all_hosts(false)
	_apply_params_all()


func _tick_animate_seed(delta: float) -> void:
	if not animate_seed or not effect_enabled:
		_seed_accum = 0.0
		return
	var interval := maxf(seed_interval, 0.05)
	_seed_accum += delta
	if _seed_accum < interval:
		return
	var steps := int(_seed_accum / interval)
	_seed_accum -= float(steps) * interval
	seed = seed + steps


func _queue_preview() -> void:
	_preview_revision += 1
	_preview_dirty = true
	_preview_wait = 0.25


func _exit_tree() -> void:
	if _preview_thread != null:
		_preview_thread.wait_to_finish()
		_preview_thread = null
	_restore_all_hosts()
	_clear_managed()


func _is_scene_mode() -> bool:
	var parent_mesh := get_parent() as MeshInstance3D
	return parent_mesh == null or parent_mesh.mesh == null


func _sample_root() -> Node:
	if root_path != NodePath() and has_node(root_path):
		return get_node(root_path)
	if _is_scene_mode():
		return get_parent()
	return get_parent()


func _iter_hosts() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if not _is_scene_mode():
		var host := get_parent() as MeshInstance3D
		if host != null and host.mesh != null:
			out.append(host)
		return out
	var root := _sample_root()
	if root == null:
		return out
	_collect_meshes(root, out)
	return out


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and not _is_managed_node(mi):
			out.append(mi)
	for child in node.get_children():
		if child == self:
			continue
		if child is GlyphField:
			continue
		_collect_meshes(child, out)


func _is_managed_node(node: Node) -> bool:
	return node.has_meta(MANAGED_META)


func _input_signature() -> Array:
	var meshes: Array = []
	for host in _iter_hosts():
		meshes.append(host.mesh)
	return [meshes, spacing, edge_step, edge_threshold, sample_surface, sample_edges, seed]


func _start_preview() -> void:
	var jobs: Array = []
	for host in _iter_hosts():
		jobs.append({
			"host_id": host.get_instance_id(),
			"arrays": SurfaceSamplerScript._mesh_arrays(host.mesh),
			"albedo": _resolve_albedo(host),
			"emissive": _resolve_emissive(host),
		})
	if jobs.is_empty():
		_clear_outputs()
		return
	_running_revision = _preview_revision
	_preview_thread = Thread.new()
	var error := _preview_thread.start(
		_build_jobs.bind(jobs, spacing, edge_step, edge_threshold, sample_surface, sample_edges, seed),
		Thread.PRIORITY_LOW
	)
	if error != OK:
		_preview_thread = null
		push_warning("无法启动字形预览线程：%s" % error)


func _poll_preview() -> void:
	if _preview_thread == null or _preview_thread.is_alive():
		return
	var result: Array = _preview_thread.wait_to_finish()
	_preview_thread = null
	if _running_revision == _preview_revision:
		_apply_jobs(result)


func rebuild() -> void:
	if is_inside_tree():
		_queue_preview()
		return
	_rebuild_sync()


func _rebuild_sync() -> void:
	var jobs: Array = []
	for host in _iter_hosts():
		jobs.append({
			"host_id": host.get_instance_id(),
			"arrays": SurfaceSamplerScript._mesh_arrays(host.mesh),
			"albedo": _resolve_albedo(host),
			"emissive": _resolve_emissive(host),
		})
	if jobs.is_empty():
		_clear_outputs()
		push_warning("GlyphField 未找到可采样的 MeshInstance3D")
		return
	_apply_jobs(_build_jobs(jobs, spacing, edge_step, edge_threshold, sample_surface, sample_edges, seed))


static func _build_jobs(
	jobs: Array,
	gap: float,
	estep: float,
	ethresh: float,
	do_surface: bool,
	do_edges: bool,
	sample_seed: int
) -> Array:
	var out: Array = []
	for job in jobs:
		var built := _build_host_buffers(
			job["arrays"],
			gap,
			estep,
			ethresh,
			do_surface,
			do_edges,
			sample_seed,
			job["albedo"],
			job.get("emissive", false)
		)
		built["host_id"] = job["host_id"]
		built["albedo"] = job["albedo"]
		built["emissive"] = job.get("emissive", false)
		out.append(built)
	return out


static func _build_buffer(arrays: Array, gap: float, sample_seed: int) -> Dictionary:
	## 兼容旧测试：仅表面采样。
	var built := _build_host_buffers(arrays, gap, gap * 0.6, 25.0, true, false, sample_seed, Color.WHITE, false)
	return {"buffer": built["surface_buffer"], "count": built["surface_count"], "stride": 20}


static func _build_host_buffers(
	arrays: Array,
	gap: float,
	estep: float,
	ethresh: float,
	do_surface: bool,
	do_edges: bool,
	sample_seed: int,
	albedo: Color,
	emissive: bool
) -> Dictionary:
	var surface_buffer := PackedFloat32Array()
	var surface_count := 0
	var edge_buffer := PackedFloat32Array()
	var edge_count := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = sample_seed + 17
	var color := albedo
	if emissive:
		color = Color(
			minf(albedo.r * 1.4, 2.0),
			minf(albedo.g * 1.4, 2.0),
			minf(albedo.b * 1.4, 2.0),
			1.0
		)

	# MultiMesh stride: transform(12) + color(4) + custom(4) = 20
	const STRIDE := 20

	if do_surface:
		var sampled: Dictionary = SurfaceSamplerScript.sample_arrays(arrays, maxf(gap, 0.02), sample_seed)
		var positions: PackedVector3Array = sampled["positions"]
		var normals: PackedVector3Array = sampled["normals"]
		surface_count = positions.size()
		surface_buffer.resize(surface_count * STRIDE)
		for i in surface_count:
			_pack_instance(surface_buffer, i * STRIDE, positions[i], normals[i], color, rng.randf())

	if do_edges:
		var edges: Dictionary = SurfaceSamplerScript.sample_edges(arrays, maxf(estep, 0.008), ethresh)
		var epos: PackedVector3Array = edges["positions"]
		var edir: PackedVector3Array = edges["directions"]
		edge_count = epos.size()
		edge_buffer.resize(edge_count * STRIDE)
		for i in edge_count:
			_pack_instance(edge_buffer, i * STRIDE, epos[i], edir[i], color, rng.randf())

	return {
		"surface_buffer": surface_buffer,
		"surface_count": surface_count,
		"edge_buffer": edge_buffer,
		"edge_count": edge_count,
	}


static func _pack_instance(
	buffer: PackedFloat32Array,
	offset: int,
	p: Vector3,
	custom_xyz: Vector3,
	color: Color,
	seed_v: float
) -> void:
	buffer[offset] = 1.0
	buffer[offset + 3] = p.x
	buffer[offset + 5] = 1.0
	buffer[offset + 7] = p.y
	buffer[offset + 10] = 1.0
	buffer[offset + 11] = p.z
	buffer[offset + 12] = color.r
	buffer[offset + 13] = color.g
	buffer[offset + 14] = color.b
	buffer[offset + 15] = color.a
	buffer[offset + 16] = custom_xyz.x
	buffer[offset + 17] = custom_xyz.y
	buffer[offset + 18] = custom_xyz.z
	buffer[offset + 19] = seed_v


func _apply_jobs(results: Array) -> void:
	if ramp == null:
		ramp = load("res://features/ascii/ascii_ramp.tres") as AsciiRamp
	_clear_managed()
	_managed.clear()

	if _is_scene_mode():
		multimesh = null
		material_override = null
		material_overlay = null
		for result in results:
			var host := instance_from_id(result["host_id"]) as MeshInstance3D
			if host == null or not is_instance_valid(host):
				continue
			var surface_mmi := _make_mmi(host, false)
			var edge_mmi := _make_mmi(host, true)
			_fill_mmi(surface_mmi, result["surface_buffer"], result["surface_count"], false)
			_fill_mmi(edge_mmi, result["edge_buffer"], result["edge_count"], true)
			_managed.append({
				"host": host,
				"surface": surface_mmi,
				"edge": edge_mmi,
				"emissive": result.get("emissive", false) or emissive_body,
			})
	else:
		var result: Dictionary = results[0] if not results.is_empty() else {}
		if result.is_empty():
			_clear_outputs()
			rebuilt.emit()
			return
		_fill_self(result["surface_buffer"], result["surface_count"], false)
		var edge_mmi := get_node_or_null(NodePath(EDGE_CHILD)) as MultiMeshInstance3D
		if edge_mmi == null:
			edge_mmi = MultiMeshInstance3D.new()
			edge_mmi.name = String(EDGE_CHILD)
			edge_mmi.cast_shadow = SHADOW_CASTING_SETTING_OFF
			add_child(edge_mmi)
			if Engine.is_editor_hint():
				edge_mmi.owner = owner
		_fill_mmi(edge_mmi, result["edge_buffer"], result["edge_count"], true)
		_managed.append({
			"host": get_parent(),
			"surface": self,
			"edge": edge_mmi,
			"emissive": result.get("emissive", false) or emissive_body,
		})

	_apply_params_all()
	_sync_all_hosts(true)
	rebuilt.emit()


func _make_mmi(host: MeshInstance3D, is_edge: bool) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "__GlyphEdge" if is_edge else "__GlyphSurface"
	mmi.cast_shadow = SHADOW_CASTING_SETTING_OFF
	# 棱边略靠前排序，避免被表面点盖住
	if is_edge:
		mmi.sorting_offset = 0.08
	mmi.set_meta(MANAGED_META, get_instance_id())
	host.add_child(mmi)
	if Engine.is_editor_hint():
		mmi.owner = owner
	return mmi


func _fill_self(buffer: PackedFloat32Array, count: int, is_edge: bool) -> void:
	if count <= 0:
		multimesh = null
		return
	multimesh = _new_multimesh(buffer, count)
	_ensure_material(self, is_edge)


func _fill_mmi(mmi: MultiMeshInstance3D, buffer: PackedFloat32Array, count: int, is_edge: bool) -> void:
	if mmi == null:
		return
	if count <= 0:
		mmi.multimesh = null
		mmi.visible = false
		return
	mmi.visible = effect_enabled
	mmi.multimesh = _new_multimesh(buffer, count)
	_ensure_material(mmi, is_edge)


func _new_multimesh(buffer: PackedFloat32Array, count: int) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = count
	mm.buffer = buffer
	return mm


func _ensure_material(mmi: MultiMeshInstance3D, is_edge: bool) -> void:
	var sh: Shader = load("res://features/ascii/glyph_billboard.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = sh
	if is_edge:
		mat.render_priority = 1
	mmi.material_override = mat
	mmi.set_meta(&"_is_edge", is_edge)


func _clear_outputs() -> void:
	multimesh = null
	material_override = null
	material_overlay = null
	_clear_managed()
	var edge := get_node_or_null(NodePath(EDGE_CHILD)) as MultiMeshInstance3D
	if edge != null:
		edge.multimesh = null


func _clear_managed() -> void:
	for entry in _managed:
		if entry.get("surface") == self:
			continue
		var surface: MultiMeshInstance3D = entry.get("surface")
		var edge: MultiMeshInstance3D = entry.get("edge")
		if is_instance_valid(surface) and surface != self:
			surface.queue_free()
		if is_instance_valid(edge) and edge.get_parent() != self:
			edge.queue_free()
		elif is_instance_valid(edge) and edge.get_parent() == self and _is_scene_mode():
			edge.queue_free()
	_managed.clear()
	# 清理残留托管节点
	for host in _iter_hosts():
		for child in host.get_children():
			if child.has_meta(MANAGED_META) and child.get_meta(MANAGED_META) == get_instance_id():
				child.queue_free()


func _glyph_targets() -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	if _managed.is_empty():
		if multimesh != null:
			out.append(self)
		var edge := get_node_or_null(NodePath(EDGE_CHILD)) as MultiMeshInstance3D
		if edge != null:
			out.append(edge)
		return out
	for entry in _managed:
		var surface: MultiMeshInstance3D = entry.get("surface")
		var edge: MultiMeshInstance3D = entry.get("edge")
		if is_instance_valid(surface):
			out.append(surface)
		if is_instance_valid(edge):
			out.append(edge)
	return out


func _apply_params_all() -> void:
	if ramp == null:
		return
	for entry in _managed:
		var surface: MultiMeshInstance3D = entry.get("surface")
		var edge: MultiMeshInstance3D = entry.get("edge")
		var host_emissive: bool = entry.get("emissive", false)
		if is_instance_valid(surface):
			_apply_params_to(surface, false, host_emissive)
		if is_instance_valid(edge):
			_apply_params_to(edge, true, host_emissive)
	if _managed.is_empty() and material_override is ShaderMaterial:
		_apply_params_to(self, false, emissive_body)


func _apply_params_to(mmi: MultiMeshInstance3D, is_edge: bool, host_emissive: bool) -> void:
	var mat := mmi.material_override as ShaderMaterial
	if mat == null:
		_ensure_material(mmi, is_edge)
		mat = mmi.material_override as ShaderMaterial
	if mat == null or ramp == null:
		return
	_set_common_params(mat, is_edge)
	if is_edge:
		mat.render_priority = 1
		mmi.sorting_offset = 0.08
	# 棱边不加 Bayer，保持 -/|\ 笔画干净
	var want_dither := effect_enabled and not host_emissive and not emissive_body and not is_edge
	if want_dither:
		var key := "edge" if is_edge else "surface"
		if not _dither_cache.has(key):
			var dither := ShaderMaterial.new()
			dither.shader = preload("res://features/ascii/glyph_bayer_overlay.gdshader")
			_dither_cache[key] = dither
		var dither_mat: ShaderMaterial = _dither_cache[key]
		_set_common_params(dither_mat, is_edge)
		dither_mat.set_shader_parameter("u_dither_pixel_size", dither_pixel_size)
		dither_mat.set_shader_parameter("u_dither_color_levels", dither_color_levels)
		mmi.material_overlay = dither_mat
	else:
		mmi.material_overlay = null
	mmi.visible = effect_enabled


func _set_common_params(mat: ShaderMaterial, is_edge: bool) -> void:
	mat.set_shader_parameter("u_atlas", ramp.atlas)
	mat.set_shader_parameter("u_char_count", ramp.char_count)
	mat.set_shader_parameter("u_edge_count", ramp.edge_count)
	mat.set_shader_parameter("u_glyph_px", glyph_px)
	mat.set_shader_parameter("u_emission_energy", emission_energy)
	mat.set_shader_parameter("u_edge_mode", 1.0 if is_edge else 0.0)
	mat.set_shader_parameter("u_light_dir", light_direction.normalized())
	mat.set_shader_parameter("u_ambient", ambient)
	mat.set_shader_parameter("u_mono", _mono)
	mat.set_shader_parameter("u_lod_enabled", 1.0 if lod_enabled else 0.0)
	mat.set_shader_parameter("u_lod_near", lod_near)
	mat.set_shader_parameter("u_lod_far", maxf(lod_far, lod_near + 0.01))
	mat.set_shader_parameter("u_glyph_px_near", glyph_px_near)
	mat.set_shader_parameter("u_glyph_px_far", glyph_px_far)
	mat.set_shader_parameter("u_keep_near", keep_near)
	mat.set_shader_parameter("u_keep_far", keep_far)
	# 棱边保留不低于表面（同端点）
	mat.set_shader_parameter("u_edge_keep_near", maxf(edge_keep_near, keep_near))
	mat.set_shader_parameter("u_edge_keep_far", maxf(edge_keep_far, keep_far))
	var vp := get_viewport()
	if vp:
		mat.set_shader_parameter("u_viewport_size", vp.get_visible_rect().size)


## 与 shader `_lod_t` / mix 一致，供测试与调试。
static func lod_mix(d: float, near_d: float, far_d: float, v_near: float, v_far: float) -> float:
	var n := minf(near_d, far_d - 0.001)
	var f := maxf(far_d, n + 0.001)
	var t := smoothstep(n, f, d)
	return lerpf(v_near, v_far, t)


func _resolve_albedo(host: MeshInstance3D) -> Color:
	_capture_host(host)
	var state: Dictionary = _host_state.get(host.get_instance_id(), {})
	if state.has("albedo"):
		return state["albedo"]
	return _read_albedo_from_host(host)


func _resolve_emissive(host: MeshInstance3D) -> bool:
	if emissive_body:
		return true
	_capture_host(host)
	var state: Dictionary = _host_state.get(host.get_instance_id(), {})
	return state.get("emissive", false)


func _host_source_material(host: MeshInstance3D) -> Material:
	# material_override 由 GlyphField 写成 void shell，颜色只从表面覆盖 / 网格材质读。
	var surface_override := host.get_surface_override_material(0)
	if surface_override != null:
		return surface_override
	if host.mesh != null and host.mesh.get_surface_count() > 0:
		var surface_mat := host.mesh.surface_get_material(0)
		if surface_mat != null:
			return surface_mat
	if host.mesh is PrimitiveMesh:
		var prim := host.mesh as PrimitiveMesh
		if prim.material != null:
			return prim.material
	return null


func _read_albedo_from_host(host: MeshInstance3D) -> Color:
	var mat := _host_source_material(host)
	if mat is BaseMaterial3D:
		var base := mat as BaseMaterial3D
		if base.emission_enabled:
			return base.emission
		return base.albedo_color
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		var c = sm.get_shader_parameter("albedo")
		if c is Color:
			return c
	return Color(0.85, 0.9, 1.0)


func _read_emissive_flag(host: MeshInstance3D) -> bool:
	var mat := _host_source_material(host)
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).emission_enabled
	return false


func _capture_host(host: MeshInstance3D) -> void:
	var id := host.get_instance_id()
	if _host_state.has(id):
		return
	_host_state[id] = {
		"override": host.material_override,
		"overlay": host.material_overlay,
		"albedo": _read_albedo_from_host(host),
		"emissive": _read_emissive_flag(host),
		"emission_color": _read_albedo_from_host(host),
	}


func _sync_all_hosts(force: bool) -> void:
	for host in _iter_hosts():
		_sync_host_surface(host, force)


func _sync_host_surface(host: MeshInstance3D, force: bool) -> void:
	_capture_host(host)
	var id := host.get_instance_id()
	var state: Dictionary = _host_state[id]
	var host_emissive: bool = emissive_body or state.get("emissive", false)
	var albedo: Color = state.get("albedo", Color.WHITE)
	var signature := [effect_enabled, host_emissive, shell_color, core_energy, emission_energy, albedo]
	if not force and state.get("signature") == signature:
		return
	state["signature"] = signature
	if not effect_enabled:
		visible = false
		_restore_host(host)
		return
	visible = true
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if host_emissive:
		material.albedo_color = Color(
			albedo.r * core_energy,
			albedo.g * core_energy,
			albedo.b * core_energy,
			1.0
		)
		material.emission_enabled = true
		material.emission = albedo
		material.emission_energy_multiplier = core_energy
		host.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		material.albedo_color = shell_color
		host.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	host.material_override = material
	host.material_overlay = null


func _restore_all_hosts() -> void:
	for id in _host_state.keys():
		var host := instance_from_id(id) as MeshInstance3D
		if host != null and is_instance_valid(host):
			_restore_host(host)
	_host_state.clear()


func _restore_host(host: MeshInstance3D) -> void:
	var id := host.get_instance_id()
	if not _host_state.has(id):
		return
	var state: Dictionary = _host_state[id]
	host.material_override = state.get("override")
	host.material_overlay = state.get("overlay")


func set_glyph_px(px: float) -> void:
	glyph_px = px
	if lod_enabled:
		glyph_px_near = px
	_apply_params_all()


func set_mono(on: bool) -> void:
	_mono = 1.0 if on else 0.0
	_apply_params_all()


func sync_viewport_size() -> void:
	_apply_params_all()
