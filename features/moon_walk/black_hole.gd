@tool
class_name BlackHole
extends Node3D
## SkyPivot 下的远景。原点是黑洞中心。basis 不参与盘面。
## 唯一的 ShaderMaterial 写入者。不进入宿主三元组，不创建 GlyphField。
## 盘自旋与 ASCII/Bayer 在透镜着色器里完成，跟 MoonWalk 的表面模式对齐。

const LENS_SHADER := preload("res://features/moon_walk/black_hole_lens.gdshader")
const DEFAULT_RAMP := preload("res://features/ascii/ascii_ramp.tres")
const _LENS_NAME := "Lens"

## Extra shader keys outside BlackHoleOptics.uniform_block().
const PRESENTATION_KEYS := [
	"u_time",
	"u_disk_phase",
	"u_atlas",
	"u_char_count",
	"u_glyph_px",
	"u_ascii",
	"u_dither",
	"u_dither_pixel_size",
	"u_dither_color_levels",
	"u_ascii_bg",
]

@export var optics: BlackHoleOptics
@export var ramp: AsciiRamp
@export var animate: bool = true
@export_range(0.0, 4.0, 0.01) var spin_speed: float = 0.55
@export var glyph_px: float = 14.0

var _lens_material: ShaderMaterial
var _disk_phase: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	if get_node_or_null("GlyphField") != null:
		push_error("BlackHole must not own a GlyphField")
	if not basis.is_equal_approx(Basis.IDENTITY):
		push_error("BlackHole basis is ignored; disk orientation comes from optics")
		basis = Basis.IDENTITY
	if optics == null:
		optics = BlackHoleOptics.new()
	if ramp == null:
		ramp = DEFAULT_RAMP
	if not optics.changed.is_connected(_upload):
		optics.changed.connect(_upload)
	_ensure_lens()
	_apply_uniforms()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		# Keep a slow preview spin in the editor without depending on the game clock.
		if animate:
			_time += 0.016
			_disk_phase = wrapf(_disk_phase + spin_speed * 0.016, 0.0, TAU)
			_apply_presentation()
		return
	if animate:
		_time += delta
		_disk_phase = wrapf(_disk_phase + spin_speed * delta, 0.0, TAU)
	_apply_presentation()


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
	_apply_presentation()


func _moon_walk_root() -> Node:
	var node: Node = self
	while node != null:
		if node.get("surface_render_mode") != null and node.get("dither_pixel_size") != null:
			return node
		node = node.get_parent()
	return null


func _apply_presentation() -> void:
	if _lens_material == null:
		return
	var ascii_on := 1.0
	var dither_on := 1.0
	var dither_px := 1.0
	var dither_levels := 4.0
	var root := _moon_walk_root()
	if root != null:
		var mode := int(root.get("surface_render_mode"))
		# Match MoonWalk modes: 0 ASCII, 1 Bayer model, 2 ASCII + Bayer.
		ascii_on = 0.0 if mode == 1 else 1.0
		dither_on = 0.0 if mode == 0 else 1.0
		dither_px = float(root.get("dither_pixel_size"))
		dither_levels = float(root.get("dither_color_levels"))
	_lens_material.set_shader_parameter("u_time", _time)
	_lens_material.set_shader_parameter("u_disk_phase", _disk_phase)
	_lens_material.set_shader_parameter("u_ascii", ascii_on)
	_lens_material.set_shader_parameter("u_dither", dither_on)
	_lens_material.set_shader_parameter("u_dither_pixel_size", dither_px)
	_lens_material.set_shader_parameter("u_dither_color_levels", dither_levels)
	_lens_material.set_shader_parameter("u_glyph_px", glyph_px)
	_lens_material.set_shader_parameter("u_ascii_bg", Vector3(0.01, 0.012, 0.02))
	if ramp != null and ramp.atlas != null:
		_lens_material.set_shader_parameter("u_atlas", ramp.atlas)
		_lens_material.set_shader_parameter("u_char_count", ramp.char_count)
	else:
		_lens_material.set_shader_parameter("u_char_count", 10)


func presentation_block() -> Dictionary:
	## Keys allowed on the lens besides optics.uniform_block().
	var out := {}
	if _lens_material == null:
		return out
	for key in PRESENTATION_KEYS:
		out[key] = _lens_material.get_shader_parameter(key)
	return out


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
