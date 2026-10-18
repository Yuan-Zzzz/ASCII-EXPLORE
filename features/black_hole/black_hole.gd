@tool
class_name BlackHole
extends Node3D

const LENS_SHADER := preload("res://features/black_hole/black_hole_lens.gdshader")
const DEFAULT_RAMP := preload("res://features/ascii/ascii_ramp.tres")
const _EditorPreviewShell := preload("res://features/black_hole/editor_preview_shell.gd")
const _LENS_NAME := "Lens"
const _MOON_LENS_NAME := "MoonLens"
const _LIGHT_NAME := "DiskLight"
## Spot cone vs event-horizon angular size. 1 is physical; >1 softens the lit/unlit ground seam.
const _light_spread := 1.6
const SKY_SLOTS := 2
const _SKY_RADIUS := 90000.0
## Matches MoonWalk.LENS_LAYER so the lunar lens samples sky without the moon mesh.
const _LENS_LAYER := 10
const _MIN_LENS_PX := 2.0

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
	"u_glow_energy",
]

const LUNAR_KEYS := [
	"u_view_frame",
	"u_occlude",
	"u_occluder_center",
	"u_occluder_radius",
	"u_sky_count",
	"u_sky_center_0",
	"u_sky_center_1",
	"u_sky_height_0",
	"u_sky_height_1",
	"u_sky_radius_0",
	"u_sky_radius_1",
	"u_beam_lit",
	"u_beam_energy",
	"u_beam_inner",
	"u_beam_outer",
	"u_beam_disk_normal",
	"u_beam_slant_sin",
	"u_beam_shadow_cos",
	"u_beam_shadow_width",
	"u_beam_ring_energy",
	"u_beam_ring_cos",
	"u_beam_ring_sigma",
	"u_beam_flat_dark",
	"u_beam_min_distance",
	"u_beam_distance_falloff",
	"u_beam_sun_cos",
	"u_beam_core_radius",
	"u_beam_disk_outer",
]

@export_group("Optics")
@export var optics: BlackHoleOptics:
	set(value):
		optics = value
		_ensure_shell()
		_shell.bind(value)

@export_tool_button("Frame black hole", "Camera3D") var frame_black_hole_button: Callable = frame_black_hole

@export_group("Presentation")
@export var ramp: AsciiRamp:
	set(value):
		ramp = value
		_apply_presentation()
@export var animate: bool = true
@export_range(0.0, 4.0, 0.01) var spin_speed: float = 0.55
@export var glyph_px: float = 14.0:
	set(value):
		glyph_px = value
		_apply_presentation()
@export_range(0.0, 12.0, 0.01) var glow_energy: float = 2.4:
	set(value):
		glow_energy = value
		_apply_presentation()
@export_enum("ASCII 3D", "Bayer Model", "ASCII + Bayer") var surface_render_mode: int = 2:
	set(value):
		surface_render_mode = value
		_apply_presentation()
@export_range(1.0, 8.0, 1.0) var dither_pixel_size: float = 1.0:
	set(value):
		dither_pixel_size = value
		_apply_presentation()
@export_range(2.0, 16.0, 1.0) var dither_color_levels: float = 4.0:
	set(value):
		dither_color_levels = value
		_apply_presentation()
@export_range(0.0, 4.0, 0.01) var light_energy: float = 1.2:
	set(value):
		light_energy = value
		_publish_light()
@export_range(0.0, 2.0, 0.01) var light_falloff_power: float = 1.0
@export_range(0.0, 180.0, 1.0) var light_tilt_degrees: float = 62.0
@export_range(0.0, 4.0, 0.01) var ring_energy: float = 1.0
@export_range(0.0, 2.0, 0.01) var ring_glint: float = 0.0

@export_group("")
@export var moon_path: NodePath = ^"../../Moon"
@export var observer_path: NodePath = ^"../../Player/Camera3D"
@export var sun_path: NodePath = ^"../SunHost"
@export var sky_body_paths: Array[NodePath] = [^"../Earth", ^"../SunHost"]

var _shell: RefCounted
var _lens_material: ShaderMaterial
var _light: SpotLight3D
var _moon_lens: MeshInstance3D
var _moon_lens_material: ShaderMaterial
var _disk_phase: float = 0.0
var _time: float = 0.0


func _init() -> void:
	_ensure_shell()


## A saved Callable would call the instance that was alive when the scene was written.
func _validate_property(property: Dictionary) -> void:
	if property.name == &"frame_black_hole_button":
		property.usage = int(property.usage) & ~PROPERTY_USAGE_STORAGE

func _enter_tree() -> void:
	# @tool reload clears RefCounted members without re-running _init on the live node.
	_ensure_shell()


func _ready() -> void:
	_ensure_shell()
	if get_node_or_null("GlyphField") != null:
		push_error("BlackHole must not own a GlyphField")
	if not basis.is_equal_approx(Basis.IDENTITY):
		push_error("BlackHole basis is ignored; disk orientation comes from optics")
		basis = Basis.IDENTITY
	for child in get_children():
		var visual := child as VisualInstance3D
		if visual != null:
			visual.layers |= 1 << (_LENS_LAYER - 1)
	if optics == null:
		optics = BlackHoleOptics.new()
	if ramp == null:
		ramp = DEFAULT_RAMP
	_ensure_lens()
	_apply_uniforms()


func _process(delta: float) -> void:
	_ensure_shell()
	_shell.tick(delta)


func _advance_disk(step: float) -> void:
	_time += step
	_disk_phase = wrapf(_disk_phase + spin_speed * step, 0.0, TAU)


func frame_black_hole() -> Transform3D:
	_ensure_shell()
	return _shell.frame_black_hole()


## Editor script reload wipes _shell; rebuild and rebind the current optics.
func _ensure_shell() -> void:
	if _shell != null:
		return
	var shell := _EditorPreviewShell.new()
	_shell = shell
	shell.attach(self)
	if optics != null:
		shell.bind(optics)


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
	_publish_light()


func _apply_presentation() -> void:
	if _lens_material == null:
		return
	# Same mode enum as MoonWalk: 0 ASCII, 1 Bayer model, 2 ASCII + Bayer.
	var ascii_on := 0.0 if surface_render_mode == 1 else 1.0
	var dither_on := 0.0 if surface_render_mode == 0 else 1.0
	_lens_material.set_shader_parameter("u_time", _time)
	_lens_material.set_shader_parameter("u_disk_phase", _disk_phase)
	_lens_material.set_shader_parameter("u_ascii", ascii_on)
	_lens_material.set_shader_parameter("u_dither", dither_on)
	_lens_material.set_shader_parameter("u_dither_pixel_size", dither_pixel_size)
	_lens_material.set_shader_parameter("u_dither_color_levels", dither_color_levels)
	_lens_material.set_shader_parameter("u_glyph_px", glyph_px)
	_lens_material.set_shader_parameter("u_glow_energy", glow_energy)
	if ramp != null and ramp.atlas != null:
		_lens_material.set_shader_parameter("u_atlas", ramp.atlas)
		_lens_material.set_shader_parameter("u_char_count", ramp.char_count)
	else:
		_lens_material.set_shader_parameter("u_char_count", 10)


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


func _publish_light() -> void:
	if light_energy <= 0.0:
		if _light != null:
			_light.visible = false
		return
	var moon := _resolve(moon_path)
	if moon == null or optics == null:
		return
	# Editor may briefly hold a placeholder optics instance during script reload.
	var shadow := BlackHoleOptics.shadow_per_rs() * optics.rs
	if shadow <= 0.0:
		return
	_ensure_light()
	var moon_center := moon.global_position
	var distance := maxf(global_position.distance_to(moon_center), 1.0)
	_light.visible = true
	_light.light_energy = light_energy
	_light.light_color = BlackHoleOptics.COLOR_INNER
	_light.spot_range = maxf(distance * 1.5, shadow * 4.0)
	_light.spot_angle = clampf(rad_to_deg(asin(minf(shadow * _light_spread / distance, 0.999))), 1.0, 179.0)
	_light.spot_angle_attenuation = 0.0
	_light.spot_attenuation = 0.0
	if not _light.global_position.is_equal_approx(global_position):
		_light.global_position = global_position
	var aim := moon_center - global_position
	if aim.length_squared() > 1.0e-6:
		_light.look_at(moon_center, Vector3.UP)


func _ensure_light() -> void:
	if _light != null:
		return
	_light = SpotLight3D.new()
	_light.name = _LIGHT_NAME
	_light.shadow_enabled = false
	_light.spot_range = 100000.0
	add_child(_light)


func light_source() -> SpotLight3D:
	return _light


func light_direction(_frame: Basis) -> Vector3:
	var base := (-global_position).normalized()
	if base.length_squared() < 1.0e-6:
		return Vector3.UP
	return base.rotated(Vector3.UP, deg_to_rad(light_tilt_degrees)).normalized()


func _sun_cos(disk_direction: Vector3, observer: Vector3) -> float:
	var sun := _resolve(sun_path)
	if sun == null:
		return 1.0
	var to_sun := sun.global_position - observer
	if to_sun.length_squared() < 1.0e-6:
		return 1.0
	return clampf(to_sun.normalized().dot(disk_direction), -1.0, 1.0)


func _moon_anchor() -> Node3D:
	return _resolve(observer_path)


func _resolve(path: NodePath) -> Node3D:
	if path.is_empty():
		return null
	return get_node_or_null(path) as Node3D


func sky_bodies(observer: Vector3) -> Array:
	var out := []
	for path in sky_body_paths:
		var node := _resolve(path)
		if node == null or node == self:
			continue
		var body := node as MeshInstance3D
		if body == null or body.mesh == null:
			continue
		var center := body.global_position
		var direction := center - observer
		if direction.length_squared() < 1.0e-6:
			continue
		out.append({
			"node": body,
			"center": center,
			"direction": direction.normalized(),
			"height": observer + direction.normalized() * _SKY_RADIUS,
			"radius": _body_radius(body),
		})
	return out


static func _body_radius(body: MeshInstance3D) -> float:
	if body.get("radius") != null:
		return float(body.get("radius"))
	var aabb := body.get_aabb()
	return aabb.size.length() * 0.5


func _publish_moon_view() -> void:
	if optics == null or not optics.consistent():
		return
	if not is_inside_tree() or Engine.is_editor_hint():
		if _moon_lens != null:
			_moon_lens.visible = false
		return
	var camera := _moon_anchor() as Camera3D
	var moon := _resolve(moon_path)
	if camera == null or moon == null:
		return
	_ensure_moon_lens()
	var inside := camera.is_position_in_frustum(global_position)
	var radius := optics.shadow_radius()
	var focal := (camera.get_viewport().get_visible_rect().size.y * 0.5) / tan(deg_to_rad(camera.fov) * 0.5)
	var radius_px := focal * radius / maxf(camera.global_position.distance_to(global_position), 1.0)
	_moon_lens.visible = inside and radius_px >= _MIN_LENS_PX
	light_source().visible = light_energy > 0.0
	if not _moon_lens.visible:
		return
	var moon_radius := float(moon.get("radius")) if moon.get("radius") != null else 1.0
	var view := _moon_lens_material
	var frame := optics.black_hole_frame()
	var scale := _lens_world_scale(radius, camera, radius_px)
	var bodies := sky_bodies(camera.global_position)
	for slot in SKY_SLOTS:
		if slot < bodies.size():
			var body: Dictionary = bodies[slot]
			var height: Vector3 = body["height"]
			view.set_shader_parameter("u_sky_center_%d" % slot, (body["node"] as Node3D).global_position)
			view.set_shader_parameter("u_sky_height_%d" % slot, height * scale)
			view.set_shader_parameter("u_sky_radius_%d" % slot, float(body["radius"]))
		else:
			view.set_shader_parameter("u_sky_radius_%d" % slot, 0.0)
	view.set_shader_parameter("u_sky_count", bodies.size())
	view.set_shader_parameter("u_sky_radius", _SKY_RADIUS * scale)
	for key in optics.uniform_block():
		view.set_shader_parameter(key, optics.uniform_block()[key])
	view.set_shader_parameter("u_view_frame", frame)
	view.set_shader_parameter("u_occlude", true)
	view.set_shader_parameter("u_occluder_center", Vector3.ZERO)
	view.set_shader_parameter("u_occluder_radius", moon_radius)
	view.set_shader_parameter("u_lens_radius", _SKY_RADIUS * scale)
	var state := optics.beam_state(Vector3.ZERO, false)
	var direction := light_direction(frame)
	var moon_face := (-global_position).normalized()
	var slant := clampf(direction.dot(moon_face), -1.0, 1.0)
	var cover := absf(acos(slant))
	var shadow_cos := cos(float(state["shadow_cone"]))
	view.set_shader_parameter("u_beam_lit", light_energy)
	view.set_shader_parameter("u_beam_energy", optics.COLOR_INNER * light_energy)
	view.set_shader_parameter("u_beam_inner", optics.COLOR_INNER)
	view.set_shader_parameter("u_beam_outer", optics.COLOR_OUTER)
	view.set_shader_parameter("u_beam_disk_normal", -direction)
	view.set_shader_parameter("u_beam_slant_sin", sin(cover))
	view.set_shader_parameter("u_beam_shadow_cos", shadow_cos)
	view.set_shader_parameter("u_beam_shadow_width", 0.02)
	view.set_shader_parameter("u_beam_core_radius", shadow_cos)
	view.set_shader_parameter("u_beam_disk_outer", cos(cover))
	view.set_shader_parameter("u_beam_ring_energy", ring_glint)
	view.set_shader_parameter("u_beam_ring_cos", shadow_cos)
	view.set_shader_parameter("u_beam_ring_sigma", 0.01)
	view.set_shader_parameter("u_beam_flat_dark", 0.08)
	view.set_shader_parameter("u_beam_min_distance", 1.0)
	view.set_shader_parameter("u_beam_distance_falloff", 0.0)
	view.set_shader_parameter("u_beam_sun_cos", _sun_cos(direction, camera.global_position))
	_moon_lens.extra_cull_margin = _SKY_RADIUS * scale


func _ensure_moon_lens() -> void:
	if _moon_lens == null:
		_moon_lens = MeshInstance3D.new()
		_moon_lens.name = _MOON_LENS_NAME
		var quad := QuadMesh.new()
		quad.size = Vector2(2, 2)
		_moon_lens.mesh = quad
		_moon_lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_moon_lens.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_moon_lens_material = ShaderMaterial.new()
		_moon_lens_material.shader = LENS_SHADER
		_moon_lens.material_override = _moon_lens_material
		_moon_lens.layers = 1 << (_LENS_LAYER - 1)
		add_child(_moon_lens)
	elif _moon_lens_material == null:
		_moon_lens_material = _moon_lens.material_override as ShaderMaterial


func moon_lens() -> MeshInstance3D:
	return _moon_lens


## Sky-shell scale only. Screen angle stays on u_lens_radius.
func _lens_world_scale(shadow_radius: float, _camera: Camera3D, _radius_px: float) -> float:
	return maxf(4.0, _SKY_RADIUS / maxf(shadow_radius, 1.0) * 0.02)


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
