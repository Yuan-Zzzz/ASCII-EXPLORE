extends CharacterBody3D

@export var move_speed: float = 5.5
@export var jump_speed: float = 3.4
@export var gravity: float = 2.2
@export var mouse_sensitivity: float = 0.0022

@export var moon_path: NodePath = NodePath("../Moon")

var _pitch: float = 0.0
var _moon_center: Vector3 = Vector3.ZERO
var _jump: bool = false

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	var moon := get_node_or_null(moon_path) as Node3D
	if moon:
		_moon_center = moon.global_position
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_object_local(Vector3.UP, -motion.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.15, 1.15)
		_camera.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_SPACE:
			_jump = true
		elif key.keycode == KEY_ESCAPE:
			get_tree().quit()


func _physics_process(delta: float) -> void:
	var up := _radial_up()
	up_direction = up
	_align_to_up(up)

	velocity -= up * gravity * delta
	if is_on_floor() and _jump:
		var radial := velocity.dot(up)
		velocity += up * (jump_speed - radial)
	_jump = false

	var wish := _wish_dir(up)
	var radial_speed := velocity.dot(up)
	var tangent := velocity - up * radial_speed
	if wish != Vector3.ZERO:
		tangent = wish * move_speed
	else:
		tangent = tangent.move_toward(Vector3.ZERO, move_speed * 8.0 * delta)
	velocity = tangent + up * radial_speed
	move_and_slide()


func _radial_up() -> Vector3:
	var offset := global_position - _moon_center
	if offset.length_squared() < 0.000001:
		return Vector3.UP
	return offset.normalized()


func _align_to_up(up: Vector3) -> void:
	# Floor tests use up_direction. If local Y lags the radius, the ground reads as a wall.
	var current := global_basis.y
	if current.dot(up) > 0.9999:
		return
	global_basis = Basis(Quaternion(current, up)) * global_basis


func _wish_dir(up: Vector3) -> Vector3:
	var wish := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		wish -= global_basis.z
	if Input.is_key_pressed(KEY_S):
		wish += global_basis.z
	if Input.is_key_pressed(KEY_A):
		wish -= global_basis.x
	if Input.is_key_pressed(KEY_D):
		wish += global_basis.x
	wish -= up * wish.dot(up)
	if wish.length_squared() < 0.000001:
		return Vector3.ZERO
	return wish.normalized()
