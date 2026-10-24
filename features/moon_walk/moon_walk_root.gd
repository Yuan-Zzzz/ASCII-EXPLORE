@tool
extends Node3D

@export_range(1.0, 8.0, 1.0) var dither_pixel_size: float = 2.0
@export_range(2.0, 16.0, 1.0) var dither_color_levels: float = 4.0
@export_range(0.0, 12.0, 0.1) var sun_core_energy: float = 4.0
@export_range(0.0, 12.0, 0.1) var sun_glyph_emission: float = 3.0
@export var sun_light_path: NodePath = ^"SkyPivot/SunHost/SunLight"
@export var sun_aim_path: NodePath = ^"Moon/MoonMesh"

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
	_broadcast_to_glyphs()


func _process(_delta: float) -> void:
	_broadcast_to_glyphs()


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
	_collect_fields_under(self)


func _collect_fields_under(node: Node) -> void:
	if node is GlyphField:
		_glyph_fields.append(node as GlyphField)
	for child in node.get_children():
		_collect_fields_under(child)


func _broadcast_to_glyphs() -> void:
	for field in _glyph_fields:
		field.core_energy = sun_core_energy
		if field.emissive_body:
			field.emission_energy = sun_glyph_emission
		field.dither_pixel_size = dither_pixel_size
		field.dither_color_levels = dither_color_levels
		field.effect_enabled = true
		field.sync_viewport_size()
