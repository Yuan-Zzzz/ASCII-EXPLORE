extends Node3D

## 全屏后处理 ASCII：屏幕亮度 → 阶梯字符

@export var ramp: AsciiRamp
@export var glyph_px: float = 12.0
@export var mono: bool = false
@export var ascii_enabled: bool = true

@onready var overlay: ColorRect = $AsciiLayer/AsciiOverlay
@onready var hint: Label = $AsciiLayer/Hint
@onready var camera: Camera3D = $Camera3D
@onready var pivot: Node3D = $Pivot

var _mat: ShaderMaterial
var _yaw := 0.35
var _pitch := -0.25
var _dragging := false


func _ready() -> void:
	if ramp == null:
		ramp = load("res://ascii/ascii_ramp.tres") as AsciiRamp
	_mat = overlay.material as ShaderMaterial
	_apply_ramp()
	_update_camera()
	_set_ascii_visible(ascii_enabled)
	_refresh_hint()


func _process(delta: float) -> void:
	if pivot and Input.is_key_pressed(KEY_SPACE):
		pivot.rotate_y(delta * 0.35)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			glyph_px = clampf(glyph_px - 1.0, 6.0, 32.0)
			_mat.set_shader_parameter("u_glyph_px", glyph_px)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			glyph_px = clampf(glyph_px + 1.0, 6.0, 32.0)
			_mat.set_shader_parameter("u_glyph_px", glyph_px)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.005
		_pitch = clampf(_pitch - mm.relative.y * 0.005, -1.2, 1.2)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				mono = not mono
				_mat.set_shader_parameter("u_mono", 1.0 if mono else 0.0)
			KEY_T:
				_set_ascii_visible(not ascii_enabled)
				_refresh_hint()
			KEY_ESCAPE:
				get_tree().quit()


func _apply_ramp() -> void:
	_mat.set_shader_parameter("u_atlas", ramp.atlas)
	_mat.set_shader_parameter("u_char_count", ramp.char_count)
	_mat.set_shader_parameter("u_glyph_px", glyph_px)
	_mat.set_shader_parameter("u_mono", 1.0 if mono else 0.0)


func _set_ascii_visible(on: bool) -> void:
	ascii_enabled = on
	overlay.visible = on


func _refresh_hint() -> void:
	var mode := "全屏ASCII" if ascii_enabled else "原始3D"
	hint.text = "ASCII Post  [%s]\n拖拽旋转 · 滚轮字号 · 空格慢转 · T 开关ASCII · C 单色 · Esc 退出" % mode


func _update_camera() -> void:
	var dist := 6.0
	camera.position = Vector3(
		dist * cos(_pitch) * sin(_yaw),
		dist * sin(_pitch) + 1.2,
		dist * cos(_pitch) * cos(_yaw),
	)
	camera.look_at(Vector3(0.0, 0.6, 0.0), Vector3.UP)
