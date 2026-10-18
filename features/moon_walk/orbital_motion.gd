class_name OrbitalMotion
extends Node3D
## Nested orbits from initial node positions. Moon stays fixed; other bodies counter-translate.

@export_range(1.0, 100000.0, 1.0, "or_greater") var sun_period: float = 600.0
@export_range(1.0, 100000.0, 1.0, "or_greater") var earth_period: float = 240.0
@export_range(1.0, 100000.0, 1.0, "or_greater") var moon_period: float = 60.0
@export_range(0.0, 20.0, 0.01) var time_scale: float = 1.0
@export var running: bool = true

@export var black_hole_path: NodePath = ^"../SkyPivot/BlackHole"
@export var sun_path: NodePath = ^"../SkyPivot/SunHost"
@export var earth_path: NodePath = ^"../SkyPivot/Earth"
@export var moon_path: NodePath = ^"../Moon"
@export var sun_light_path: NodePath = ^"../SkyPivot/SunHost/SunLight"

var _black_hole: Node3D
var _sun: Node3D
var _earth: Node3D
var _moon: Node3D
var _sun_light: DirectionalLight3D

## Each link orbits its parent. Offset is measured at bind time.
var _links: Array[Dictionary] = []
var _moon_home := Vector3.ZERO
var _black_hole_home := Vector3.ZERO
var _time := 0.0
var _initialized := false


func _ready() -> void:
	_bind()


func _physics_process(delta: float) -> void:
	if not running or not _initialized:
		return
	_time += delta * time_scale
	_apply(_time)


func evaluate_at(seconds: float) -> void:
	if not _initialized:
		_bind()
	if not _initialized:
		return
	_time = seconds
	_apply(_time)


func orbit_time() -> float:
	return _time


func _bind() -> void:
	_black_hole = get_node_or_null(black_hole_path) as Node3D
	_sun = get_node_or_null(sun_path) as Node3D
	_earth = get_node_or_null(earth_path) as Node3D
	_moon = get_node_or_null(moon_path) as Node3D
	_sun_light = get_node_or_null(sun_light_path) as DirectionalLight3D
	if _black_hole == null or _sun == null or _earth == null or _moon == null:
		push_error("OrbitalMotion: invalid black hole, sun, earth, or moon path")
		return
	_black_hole_home = _black_hole.global_position
	_moon_home = _moon.global_position
	_links = [
		{"body": _sun, "parent_home": _black_hole_home, "period": sun_period, "offset": _sun.global_position - _black_hole_home},
		{"body": _earth, "parent_body": _sun, "period": earth_period, "offset": _earth.global_position - _sun.global_position},
		{"body": _moon, "parent_body": _earth, "period": moon_period, "offset": _moon.global_position - _earth.global_position},
	]
	_initialized = true


func _apply(seconds: float) -> void:
	var positions: Dictionary = {}
	positions[_black_hole] = _black_hole_home
	for link in _links:
		var parent_pos: Vector3
		if link.has("parent_home"):
			parent_pos = link["parent_home"]
		else:
			parent_pos = positions[link["parent_body"]]
		var turns := seconds / maxf(float(link["period"]), 0.001)
		positions[link["body"]] = parent_pos + _orbit_offset(link["offset"], turns)

	var moon_shift: Vector3 = positions[_moon] - _moon_home
	_black_hole.global_position = positions[_black_hole] - moon_shift
	_sun.global_position = positions[_sun] - moon_shift
	_earth.global_position = positions[_earth] - moon_shift

	if _sun_light != null:
		_sun_light.global_position = positions[_sun] - moon_shift
		_aim_light_at(_moon_home)


static func _orbit_offset(offset: Vector3, turns: float) -> Vector3:
	var radius := Vector2(offset.x, offset.z).length()
	if radius <= 0.000001:
		return offset
	var phase := atan2(offset.x, offset.z) + turns * TAU
	return Vector3(sin(phase) * radius, offset.y, cos(phase) * radius)


func _aim_light_at(target: Vector3) -> void:
	var up := Vector3.UP
	var direction := target - _sun_light.global_position
	if direction.length_squared() <= 0.000001:
		return
	if absf(direction.normalized().dot(up)) > 0.999:
		up = Vector3.FORWARD
	_sun_light.look_at(target, up)
