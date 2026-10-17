@tool
extends Node3D

const GlyphFieldScript = preload("res://features/ascii/glyph_field.gd")
const ModelDitherShader = preload("res://features/dither/bayer_model.gdshader")

@export_enum("ASCII 3D", "Bayer Model", "ASCII + Bayer") var surface_render_mode: int = 2
@export_range(1.0, 8.0, 1.0) var dither_pixel_size: float = 2.0
@export_range(2.0, 16.0, 1.0) var dither_color_levels: float = 4.0
## 太阳本体的 HDR 自发光强度；高于 1 才能触发环境辉光。
@export_range(0.0, 12.0, 0.1) var sun_core_energy: float = 4.0
## 太阳字符层的自发光强度。
@export_range(0.0, 12.0, 0.1) var sun_glyph_emission: float = 3.0

var _active_surface_mode: int = -1

## 黑洞透镜的渲染层：这一层只留天空、黑洞和它自己的 Lens（月亮本体不在其中）。
const LENS_LAYER := 10

@onready var sun_light: DirectionalLight3D = $SkyPivot/SunHost/SunLight
@onready var moon_mesh: MeshInstance3D = $Moon/MoonMesh
@onready var earth: MeshInstance3D = $SkyPivot/Earth
@onready var sun_host: MeshInstance3D = $SkyPivot/SunHost

var _glyph_fields: Array[Node] = []


func _ready() -> void:
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 平行光沿本地 -Z 射出。
	sun_light.look_at(moon_mesh.global_position, Vector3.UP)
	_apply_depth_hosts()
	_collect_glyph_fields()
	_sync_light_to_glyphs()
	# 月亮本体在黑洞透镜所在的层消失：透镜要取“没有月亮时的天空”，
	# 可见的月面由字符画出，阴影里的月面由透镜画出。
	moon_mesh.layers = _lens_layers(moon_mesh.layers)


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


## 从 layers 里去掉黑洞透镜层。
static func _lens_layers(layers: int) -> int:
	return layers & ~(1 << (LENS_LAYER - 1))


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
		field.emission_energy = sun_glyph_emission if host == sun_host else 0.0
		var material := StandardMaterial3D.new()
		material.roughness = 1.0
		if host == sun_host:
			# 太阳是自发光天体。unshaded 模式只读取 albedo，所以把 HDR 亮度放在这里；
			# 同时保留 emission，Forward+/Mobile 与编辑器预览会得到额外的高光。
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = _sun_core_color(field.tint)
			material.emission_enabled = true
			material.emission = field.tint
			material.emission_energy_multiplier = sun_core_energy
		else:
			if surface_render_mode != 1:
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = field.tint if surface_render_mode == 1 else Color(0.01, 0.012, 0.02)
		host.material_override = material
		host.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if host == sun_host else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		host.material_overlay = null
		if surface_render_mode == 1:
			var overlay := ShaderMaterial.new()
			overlay.shader = ModelDitherShader
			host.material_overlay = overlay


func _sun_core_color(tint: Color) -> Color:
	return Color(
		tint.r * sun_core_energy,
		tint.g * sun_core_energy,
		tint.b * sun_core_energy,
		1.0
	)


func _sync_light_to_glyphs() -> void:
	# Native Light3D and WorldEnvironment own all lighting calculations.
	if sun_light == null:
		return
	var light_dir := sun_light.global_basis.z.normalized()
	for host in [moon_mesh, earth, sun_host]:
		var field := host.get_node("GlyphField") as GlyphField
		field.sync_viewport_size()
		# 轨道运动会让太阳方向持续变化；保留这个只读方向供调试与回归测试使用。
		if not field.light_dir.is_equal_approx(light_dir):
			field.light_dir = light_dir
		# 太阳是光源：不再叠 Bayer 覆盖层，否则覆盖层会用字符后面的暗底把日面涂黑。
		field.dither_enabled = surface_render_mode == 2 and host != sun_host
		field.dither_pixel_size = dither_pixel_size
		field.dither_color_levels = dither_color_levels
		field._apply_params()
		if surface_render_mode != 1:
			continue
		var material := host.material_override as StandardMaterial3D
		if material != null:
			if host == sun_host:
				material.albedo_color = _sun_core_color(field.tint)
				material.emission = field.tint
				material.emission_energy_multiplier = sun_core_energy
			else:
				material.albedo_color = field.tint
		var overlay := host.material_overlay as ShaderMaterial
		if overlay != null:
			overlay.set_shader_parameter("u_pixel_size", dither_pixel_size)
			overlay.set_shader_parameter("u_color_levels", dither_color_levels)
			# 月面被太阳和黑洞同时照亮：抖动的颜色乘上没抖动前的光照画面。
			overlay.set_shader_parameter("lit_weight", 1.0 if host == moon_mesh else 0.0)