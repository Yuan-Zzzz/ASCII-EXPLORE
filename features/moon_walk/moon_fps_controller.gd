class_name MoonFpsController
extends CharacterBody3D

## 球心与半径。每帧行走只用球心求当地的上方向。
class WorldFrame:
	var center: Vector3 = Vector3.ZERO
	var radius: float = 48.0

	func up_at(pos: Vector3) -> Vector3:
		var offset := pos - center
		if offset.length_squared() < 0.00000001:
			return Vector3.UP
		return offset.normalized()


@export var moon_body_path: NodePath = NodePath("../Moon")
@export var walk_speed: float = 6.5
@export var sprint_speed: float = 11.0
@export var jump_speed: float = 4.0
@export var gravity: float = 4.2
@export var mouse_sensitivity: float = 0.0022

var _frame: WorldFrame
var _yaw_delta := 0.0
var _pitch := 0.0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	var body := get_node(moon_body_path) as StaticBody3D
	var shape_node := body.get_node("CollisionShape3D") as CollisionShape3D
	var sphere := shape_node.shape as SphereShape3D
	_frame = WorldFrame.new()
	_frame.center = body.global_position
	_frame.radius = sphere.radius


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_yaw_delta -= motion.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.2, 1.2)
		_camera.rotation = Vector3(_pitch, 0.0, 0.0)


func _physics_process(delta: float) -> void:
	var up := _frame.up_at(global_position)
	_align_up(up)
	var vertical := velocity.dot(up)
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := global_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	wish = wish.slide(up)
	if wish.length_squared() > 0.0001:
		wish = wish.normalized() * speed
	else:
		wish = Vector3.ZERO
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		vertical = jump_speed
	else:
		vertical -= gravity * delta
	velocity = wish + up * vertical
	up_direction = up
	move_and_slide()


func _align_up(up: Vector3) -> void:
	var y := up.normalized()
	var forward := (-global_basis.z).slide(y)
	if forward.length_squared() < 0.00000001:
		forward = global_basis.x.slide(y)
	if forward.length_squared() < 0.00000001:
		forward = Vector3.FORWARD.slide(y)
	forward = forward.normalized().rotated(y, _yaw_delta)
	_yaw_delta = 0.0
	var z := -forward
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	global_basis = Basis(x, y, z)
