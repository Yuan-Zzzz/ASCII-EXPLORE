extends Node3D

## 三种显示：3D字符点(MultiMesh) / 原始模型 / 全屏后处理ASCII

const GlyphFieldScript = preload("res://ascii/glyph_field.gd")

enum ViewMode { GLYPHS, RAW, POST }

@export var ramp: AsciiRamp
@export var glyph_px: float = 16.0
@export var mono: bool = false
@export var view_mode: ViewMode = ViewMode.GLYPHS

@onready var overlay: ColorRect = $AsciiLayer/AsciiOverlay
@onready var hint: Label = $AsciiLayer/Hint
@onready var camera: Camera3D = $Camera3D
@onready var pivot: Node3D = $Pivot
@onready var sun: DirectionalLight3D = $Sun
@onready var ground: MeshInstance3D = $Pivot/Ground
@onready var earth: MeshInstance3D = $Pivot/Earth
@onready var sun_ball: MeshInstance3D = $Pivot/SunBall

var _post_mat: ShaderMaterial
var _yaw := 0.35
var _pitch := -0.25
var _dragging := false
var _glyph_fields: Array[Node] = []
var _saved_overrides: Dictionary = {}


func _ready() -> void:
	if ramp == null:
		ramp = load("res://ascii/ascii_ramp.tres") as AsciiRamp

	_post_mat = overlay.material as ShaderMaterial
	_build_glyph_fields()
	_apply_post_params()
	_update_camera()
	_apply_view_mode()
	_refresh_hint()
	get_viewport().size_changed.connect(_on_viewport_resized)

	if "--shot" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var tex := get_viewport().get_texture()
		if tex:
			var img := tex.get_image()
			if img:
				img.save_png("res://ascii_shot.png")
				print("saved ascii_shot.png")
		get_tree().quit()


func _process(delta: float) -> void:
	if pivot and Input.is_key_pressed(KEY_SPACE):
		pivot.rotate_y(delta * 0.35)
	_sync_light_to_glyphs()
	_on_viewport_resized()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_set_glyph_px(glyph_px - 1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_set_glyph_px(glyph_px + 1.0)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.005
		_pitch = clampf(_pitch - mm.relative.y * 0.005, -1.2, 1.2)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				mono = not mono
				_apply_mono()
			KEY_T:
				view_mode = ((int(view_mode) + 1) % 3) as ViewMode
				_apply_view_mode()
				_refresh_hint()
			KEY_ESCAPE:
				get_tree().quit()


func _build_glyph_fields() -> void:
	_glyph_fields.clear()
	_add_field(ground, 0.32, 11, Color(0.78, 0.82, 0.9))
	_add_field(earth, 0.16, 21, Color(0.45, 0.75, 1.0))
	_add_field(sun_ball, 0.14, 31, Color(1.0, 0.88, 0.4))


func _add_field(host: MeshInstance3D, spacing: float, seed: int, tint: Color) -> void:
	for c in host.get_children():
		if c.get_script() == GlyphFieldScript:
			c.queue_free()
	var field: Node = GlyphFieldScript.new()
	field.name = "GlyphField"
	field.set("ramp", ramp)
	field.set("spacing", spacing)
	field.set("seed", seed)
	field.set("glyph_px", glyph_px)
	field.set("tint", tint)
	field.set("rebuild_on_ready", true)
	host.add_child(field)
	_glyph_fields.append(field)


func _apply_view_mode() -> void:
	var glyphs_on := view_mode == ViewMode.GLYPHS
	var post_on := view_mode == ViewMode.POST
	var raw := view_mode == ViewMode.RAW

	overlay.visible = post_on
	for f in _glyph_fields:
		if is_instance_valid(f):
			f.visible = glyphs_on

	# GLYPHS：模型只写深度（近黑），让字符成为画面主体
	_set_mesh_depth_only(glyphs_on and not raw)


func _set_mesh_depth_only(on: bool) -> void:
	for mi in [ground, earth, sun_ball]:
		if on:
			if not _saved_overrides.has(mi):
				_saved_overrides[mi] = mi.material_override
			var depth := StandardMaterial3D.new()
			depth.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			depth.albedo_color = Color(0.02, 0.03, 0.06)
			mi.material_override = depth
		else:
			if _saved_overrides.has(mi):
				mi.material_override = _saved_overrides[mi]


func _apply_post_params() -> void:
	if _post_mat == null or ramp == null:
		return
	_post_mat.set_shader_parameter("u_atlas", ramp.atlas)
	_post_mat.set_shader_parameter("u_char_count", ramp.char_count)
	_post_mat.set_shader_parameter("u_glyph_px", glyph_px)
	_post_mat.set_shader_parameter("u_mono", 1.0 if mono else 0.0)


func _apply_mono() -> void:
	_apply_post_params()
	for f in _glyph_fields:
		if is_instance_valid(f):
			f.set_mono(mono)


func _set_glyph_px(px: float) -> void:
	glyph_px = clampf(px, 6.0, 32.0)
	_apply_post_params()
	for f in _glyph_fields:
		if is_instance_valid(f):
			f.set_glyph_px(glyph_px)


func _sync_light_to_glyphs() -> void:
	# DirectionalLight 光线沿本地 -Z 射出；Lambert 要用「指向光源」的方向 = +Z
	var dir: Vector3 = sun.global_transform.basis.z
	for f in _glyph_fields:
		if is_instance_valid(f):
			f.set_light_dir(dir)


func _on_viewport_resized() -> void:
	for f in _glyph_fields:
		if is_instance_valid(f):
			f.sync_viewport_size()


func _refresh_hint() -> void:
	var names := ["3D字符点", "原始模型", "全屏后处理"]
	var mode_name: String = names[int(view_mode)]
	hint.text = "ASCII GlyphField  [%s]\n拖拽旋转 · 滚轮字号 · 空格慢转 · T 切换模式 · C 单色 · Esc 退出" % mode_name


func _update_camera() -> void:
	var dist := 6.0
	camera.position = Vector3(
		dist * cos(_pitch) * sin(_yaw),
		dist * sin(_pitch) + 1.2,
		dist * cos(_pitch) * cos(_yaw),
	)
	camera.look_at(Vector3(0.0, 0.6, 0.0), Vector3.UP)
