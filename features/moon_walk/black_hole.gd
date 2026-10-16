class_name BlackHole
extends Node3D
## SkyPivot 下的远景。原点是黑洞中心。basis 不参与盘面。
## 唯一的 ShaderMaterial 写入者。不进入宿主三元组，不创建 GlyphField。

const LENS_SHADER := preload("res://features/moon_walk/black_hole_lens.gdshader")
const _LENS_NAME := "Lens"

@export var optics: BlackHoleOptics

var _lens_material: ShaderMaterial


func _ready() -> void:
	if get_node_or_null("GlyphField") != null:
		push_error("BlackHole must not own a GlyphField")
	if not basis.is_equal_approx(Basis.IDENTITY):
		push_error("BlackHole basis is ignored; disk orientation comes from optics")
		basis = Basis.IDENTITY
	if optics == null:
		optics = BlackHoleOptics.new()
	if not optics.changed.is_connected(_upload):
		optics.changed.connect(_upload)
	_ensure_lens()
	_apply_uniforms()


func _ensure_lens() -> void:
	var lens := get_node_or_null(_LENS_NAME) as MeshInstance3D
	if lens == null:
		lens = MeshInstance3D.new()
		lens.name = _LENS_NAME
		var quad := QuadMesh.new()
		quad.size = Vector2(2, 2)
		lens.mesh = quad
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lens.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_lens_material = ShaderMaterial.new()
		_lens_material.shader = LENS_SHADER
		lens.material_override = _lens_material
		add_child(lens)
	else:
		_lens_material = lens.material_override as ShaderMaterial
		if _lens_material == null:
			_lens_material = ShaderMaterial.new()
			_lens_material.shader = LENS_SHADER
			lens.material_override = _lens_material
	if optics != null:
		lens.extra_cull_margin = optics.lens_radius()


func _upload() -> void:
	# changed 可能在进树之前发出。进树之后的 _ready 会再写一次。
	if not is_inside_tree():
		return
	_apply_uniforms()


func _apply_uniforms() -> void:
	if optics == null or not optics.consistent():
		return
	_ensure_lens()
	var lens := get_node(_LENS_NAME) as MeshInstance3D
	lens.extra_cull_margin = optics.lens_radius()
	var block := optics.uniform_block()
	for key in block:
		_lens_material.set_shader_parameter(key, block[key])


func uniform_snapshot() -> Dictionary:
	var snap := {}
	if _lens_material == null or optics == null:
		return snap
	var block := optics.uniform_block()
	for key in block:
		snap[key] = _lens_material.get_shader_parameter(key)
	return snap


func lens_material() -> ShaderMaterial:
	return _lens_material


func project_shadow(camera: Camera3D) -> Dictionary:
	var origin := global_position
	var shadow := 0.0
	if optics != null and optics.consistent():
		shadow = optics.shadow_radius()
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var ahead := not camera.is_position_behind(origin)
	var center := camera.unproject_position(origin)
	var cam_dist := camera.global_position.distance_to(origin)
	var half_fov := deg_to_rad(camera.fov) * 0.5
	var focal := (viewport_size.y * 0.5) / tan(half_fov)
	var radius_px := 0.0
	if cam_dist > 0.001:
		radius_px = focal * shadow / cam_dist
	var in_frustum := (
		ahead
		and cam_dist > camera.near
		and cam_dist < camera.far
		and center.x >= 0.0
		and center.y >= 0.0
		and center.x <= viewport_size.x
		and center.y <= viewport_size.y
	)
	return {
		"in_front": ahead,
		"in_frustum": in_frustum,
		"center": center,
		"radius_px": radius_px,
	}
