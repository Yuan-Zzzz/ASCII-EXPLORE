@tool
extends Node3D

const GlyphFieldScript = preload("res://features/ascii/glyph_field.gd")
const ModelDitherShader = preload("res://features/dither/bayer_model.gdshader")

@export_enum("ASCII 3D", "Bayer Model", "ASCII + Bayer") var surface_render_mode: int = 2
@export_range(1.0, 8.0, 1.0) var dither_pixel_size: float = 2.0
@export_range(2.0, 16.0, 1.0) var dither_color_levels: float = 4.0

var _active_surface_mode: int = -1

@onready var sun_light: DirectionalLight3D = $SkyPivot/SunLight
@onready var moon_mesh: MeshInstance3D = $Moon/MoonMesh
@onready var earth: MeshInstance3D = $SkyPivot/Earth
@onready var sun_host: MeshInstance3D = $SkyPivot/SunHost

var _glyph_fields: Array[Node] = []


func _ready() -> void:
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 平行光沿本地 -Z 射出。
	sun_light.look_at(Vector3.ZERO, Vector3.UP)
	_apply_depth_hosts()
	_collect_glyph_fields()
	_sync_light_to_glyphs()


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


func _collect_glyph_fields() -> void:
	_glyph_fields.clear()
	for host in [moon_mesh, earth, sun_host]:
		for child in host.get_children():
			if child.get_script() == GlyphFieldScript:
				_glyph_fields.append(child)


func _apply_depth_hosts() -> void:
	_active_surface_mode = surface_render_mode
	for host in [moon_mesh, earth, sun_host]:
		var field := host.get_node("GlyphField") as GlyphField
		field.visible = surface_render_mode != 1
		field.emission_energy = 1.0 if host == sun_host else 0.0
		var material := StandardMaterial3D.new()
		material.roughness = 1.0
		if surface_render_mode != 1:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = field.tint if surface_render_mode == 1 else Color(0.01, 0.012, 0.02)
		if host == sun_host:
			material.emission_enabled = true
			material.emission = field.tint
		host.material_override = material
		host.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if host == sun_host else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		host.material_overlay = null
		if surface_render_mode == 1:
			var overlay := ShaderMaterial.new()
			overlay.shader = ModelDitherShader
			host.material_overlay = overlay


func _sync_light_to_glyphs() -> void:
	# Native Light3D and WorldEnvironment own all lighting calculations.
	for host in [moon_mesh, earth, sun_host]:
		var field := host.get_node("GlyphField") as GlyphField
		field.sync_viewport_size()
		field.dither_enabled = surface_render_mode == 2
		field.dither_pixel_size = dither_pixel_size
		field.dither_color_levels = dither_color_levels
		field._apply_params()
		if surface_render_mode != 1:
			continue
		var material := host.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = field.tint
			if host == sun_host:
				material.emission = field.tint
		var overlay := host.material_overlay as ShaderMaterial
		if overlay != null:
			overlay.set_shader_parameter("u_pixel_size", dither_pixel_size)
			overlay.set_shader_parameter("u_color_levels", dither_color_levels)
