@tool
class_name AsciiSurfaceRoot
extends Node3D
## 共享的场景根职责：渲染模式切换、深度底壳、字形字段同步、镜头层剔除。
## moon_walk_root.gd 与 grassland_root.gd 都继承它；子类只保留场景特有逻辑。

const ModelDitherShader = preload("res://features/dither/bayer_model.gdshader")

@export_enum("ASCII 3D", "Bayer Model", "ASCII + Bayer") var surface_render_mode: int = 2
@export_range(1.0, 8.0, 1.0) var dither_pixel_size: float = 2.0
@export_range(2.0, 16.0, 1.0) var dither_color_levels: float = 4.0

const LENS_LAYER := 10
const VOID_SHELL_COLOR := Color(0, 0, 0, 1)

## 光源方向由场景自己的光源决定；子类在 _process 中调用 _sync_light_to_glyphs(dir)。
@export var light_path: NodePath = ^""
@export var emissive_core_energy: float = 4.0
@export var emissive_glyph_energy: float = 3.0

var _active_surface_mode: int = -1
var _glyph_fields: Array[GlyphField] = []
var _light: Light3D
var _light_aim: Node3D
var _light_dir_hint: Vector3 = Vector3(0.4, 0.8, 0.3)


func _ready() -> void:
	_light = get_node_or_null(light_path) as Light3D
	if _light != null and _light is DirectionalLight3D:
		var aim := _find_first_mesh_host()
		if aim != null:
			(_light as DirectionalLight3D).look_at(aim.global_position, Vector3.UP)
	_collect_glyph_fields()
	_apply_depth_hosts()
	_sync_light_to_glyphs()
	for field in _glyph_fields:
		if field.hide_from_lens:
			hide_field_from_lens(field)


func _find_first_mesh_host() -> Node3D:
	for field in _glyph_fields:
		var host := field.get_parent() as MeshInstance3D
		if host != null and not field.emissive_body:
			return host
	return null


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


## 端口：场景把主光源方向写进来（每帧或光源变化时）。内部自动归一化。
func set_light_direction(direction: Vector3) -> void:
	if direction.length_squared() < 1.0e-8:
		return
	_light_dir_hint = direction.normalized()


## 场景希望被镜头层剔除的字段（隐藏底壳不进黑洞透镜采样）。
func hide_field_from_lens(field: GlyphField) -> void:
	var host := field.get_parent() as VisualInstance3D
	if host != null:
		host.layers = _lens_layers(host.layers)


func _apply_depth_hosts() -> void:
	_active_surface_mode = surface_render_mode
	for field in _glyph_fields:
		var host := field.get_parent() as MeshInstance3D
		if host == null:
			continue
		field.visible = surface_render_mode != 1
		if field.emissive_body:
			field.emission_energy = emissive_glyph_energy
		var material := StandardMaterial3D.new()
		material.roughness = 1.0
		if field.emissive_body:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = _emissive_core_color(field.tint)
			material.emission_enabled = true
			material.emission = field.tint
			material.emission_energy_multiplier = emissive_core_energy
			host.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			if surface_render_mode != 1:
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = field.tint if surface_render_mode == 1 else VOID_SHELL_COLOR
			host.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		host.material_override = material
		host.material_overlay = null
		if surface_render_mode == 1:
			var overlay := ShaderMaterial.new()
			overlay.shader = ModelDitherShader
			host.material_overlay = overlay


func _emissive_core_color(tint: Color) -> Color:
	return Color(
		tint.r * emissive_core_energy,
		tint.g * emissive_core_energy,
		tint.b * emissive_core_energy,
		1.0
	)


func _sync_light_to_glyphs() -> void:
	var light_dir := _current_light_dir()
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
				material.emission_energy_multiplier = emissive_core_energy
			else:
				material.albedo_color = field.tint
		var overlay := host.material_overlay as ShaderMaterial
		if overlay != null:
			overlay.set_shader_parameter("u_pixel_size", dither_pixel_size)
			overlay.set_shader_parameter("u_color_levels", dither_color_levels)
			overlay.set_shader_parameter("lit_weight", field.dither_lit_weight)


func _current_light_dir() -> Vector3:
	if _light is DirectionalLight3D:
		return (_light as DirectionalLight3D).global_basis.z.normalized()
	if _light is SpotLight3D or _light is OmniLight3D:
		# 点光源没有全局方向；用最近字段宿主到光源的方向作近似。
		var target := _find_first_mesh_host()
		if target != null:
			return (_light.global_position - target.global_position).normalized()
	return _light_dir_hint
