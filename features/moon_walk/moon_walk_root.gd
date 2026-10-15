@tool
extends Node3D

const GlyphFieldScript = preload("res://features/ascii/glyph_field.gd")

@onready var sun_light: DirectionalLight3D = $SkyPivot/SunLight
@onready var moon_mesh: MeshInstance3D = $Moon/MoonMesh
@onready var earth: MeshInstance3D = $SkyPivot/Earth
@onready var sun_host: MeshInstance3D = $SkyPivot/SunHost

var _glyph_fields: Array[Node] = []


func _ready() -> void:
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 平行光沿本地 -Z 射出。字形 Lambert 要的是指向光源的方向，即 +Z。
	sun_light.look_at(Vector3.ZERO, Vector3.UP)
	_apply_depth_hosts()
	_collect_glyph_fields()
	_sync_light_to_glyphs()


func _process(_delta: float) -> void:
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
	for host in [moon_mesh, earth]:
		for child in host.get_children():
			if child.get_script() == GlyphFieldScript:
				_glyph_fields.append(child)


func _apply_depth_hosts() -> void:
	# Keep the sun emissive. Depth shell is only for glyph hosts.
	for host in [moon_mesh, earth]:
		var depth := StandardMaterial3D.new()
		depth.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		depth.albedo_color = Color(0.01, 0.012, 0.02)
		host.material_override = depth


func _sync_light_to_glyphs() -> void:
	var dir: Vector3 = sun_light.global_transform.basis.z
	for field in _glyph_fields:
		if not is_instance_valid(field):
			continue
		field.set_light_dir(dir)
		field.sync_viewport_size()
