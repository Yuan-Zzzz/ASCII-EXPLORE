@tool
extends Node3D

const ModelDitherShader = preload("res://features/dither/bayer_model.gdshader")

@export_enum("ASCII 3D", "Bayer Model", "ASCII + Bayer") var surface_render_mode: int = 2
@export_range(1.0, 8.0, 1.0) var dither_pixel_size: float = 2.0
@export_range(2.0, 16.0, 1.0) var dither_color_levels: float = 4.0
@export_range(0.0, 12.0, 0.1) var sun_core_energy: float = 4.0
@export_range(0.0, 12.0, 0.1) var sun_glyph_emission: float = 3.0
@export var sun_light_path: NodePath = ^"SkyPivot/SunHost/SunLight"
@export var sun_aim_path: NodePath = ^"Moon/MoonMesh"

const LENS_LAYER := 10

var _active_surface_mode: int = -1
var _glyph_fields: Array[GlyphField] = []
var _sun_light: DirectionalLight3D
var _sun_aim: Node3D


func _ready() -> void:
	_sun_light = get_node_or_null(sun_light_path) as DirectionalLight3D
	_sun_aim = get_node_or_null(sun_aim_path) as Node3D
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _sun_light != null and _sun_aim != null:
		_sun_light.look_at(_sun_aim.global_position, Vector3.UP)
	_collect_glyph_fields()
	_apply_depth_hosts()
	_sync_light_to_glyphs()
	for field in _glyph_fields:
		if not field.hide_from_lens:
			continue
		var host := field.get_parent() as VisualInstance3D
		if host != null:
			host.layers = _lens_layers(host.layers)


func _process(_delta: float) -> void:
	if _active_surface_mode != surface_render_mode:
		_apply_depth_hosts()
	_sync_light_to_glyphs()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			get_tree().quit()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless":
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


static func _lens_layers(layers: int) -> int:
	return layers & ~(1 << (LENS_LAYER - 1))


func _collect_glyph_fields() -> void:
	_glyph_fields.clear()
	_collect_fields_under(self)


func _collect_fields_under(node: Node) -> void:
	if node is GlyphField:
		_glyph_fields.append(node as GlyphField)
	for child in node.get_children():
		_collect_fields_under(child)


func _apply_depth_hosts() -> void:
	_active_surface_mode = surface_render_mode
	for field in _glyph_fields:
		var host := field.get_parent() as MeshInstance3D
		if host == null:
			continue
		field.visible = surface_render_mode != 1
		if field.emissive_body:
			field.emission_energy = sun_glyph_emission
		var material := StandardMaterial3D.new()
		material.roughness = 1.0
		if field.emissive_body:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = _emissive_core_color(field.tint)
			material.emission_enabled = true
			material.emission = field.tint
			material.emission_energy_multiplier = sun_core_energy
			host.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			if surface_render_mode != 1:
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = field.tint if surface_render_mode == 1 else Color(0.01, 0.012, 0.02)
			host.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		host.material_override = material
		host.material_overlay = null
		if surface_render_mode == 1:
			var overlay := ShaderMaterial.new()
			overlay.shader = ModelDitherShader
			host.material_overlay = overlay


func _emissive_core_color(tint: Color) -> Color:
	return Color(
		tint.r * sun_core_energy,
		tint.g * sun_core_energy,
		tint.b * sun_core_energy,
		1.0
	)


func _sync_light_to_glyphs() -> void:
	if _sun_light == null:
		return
	var light_dir := _sun_light.global_basis.z.normalized()
	for field in _glyph_fields:
		var host := field.get_parent() as MeshInstance3D
		field.sync_viewport_size()
		if not field.light_dir.is_equal_approx(light_dir):
			field.light_dir = light_dir
		field.dither_enabled = surface_render_mode == 2 and not field.emissive_body
		field.dither_pixel_size = dither_pixel_size
		field.dither_color_levels = dither_color_levels
		field._apply_params()
		if surface_render_mode != 1 or host == null:
			continue
		var material := host.material_override as StandardMaterial3D
		if material != null:
			if field.emissive_body:
				material.albedo_color = _emissive_core_color(field.tint)
				material.emission = field.tint
				material.emission_energy_multiplier = sun_core_energy
			else:
				material.albedo_color = field.tint
		var overlay := host.material_overlay as ShaderMaterial
		if overlay != null:
			overlay.set_shader_parameter("u_pixel_size", dither_pixel_size)
			overlay.set_shader_parameter("u_color_levels", dither_color_levels)
			overlay.set_shader_parameter("lit_weight", field.dither_lit_weight)
