class_name GustField
extends Node3D
## 风场状态机：GUST/CALM 由状态表驱动，sample() 输出随阵风锋面推进的世界风向量。


signal wind_state_changed(state_name: String)


class GustState extends Resource:
	@export var name: String = "CALM"
	@export_range(0.0, 1.2, 0.01) var amplitude_mean: float = 0.1
	@export_range(0.0, 1.2, 0.01) var amplitude_variance: float = 0.05
	@export_range(0.05, 600.0, 0.05) var duration_mean: float = 6.0
	@export_range(0.0, 600.0, 0.05) var duration_variance: float = 3.0
	@export_range(-180.0, 180.0, 0.1) var direction_center_degrees: float = 0.0
	@export_range(0.0, 180.0, 0.1) var direction_spread_degrees: float = 30.0


@export var states: Array[GustState] = []
@export var cycle_seed: int = 11
@export var damping: float = 3.0
@export_range(0.1, 30.0, 0.1) var wave_speed: float = 6.0
@export_range(0.5, 40.0, 0.5) var wave_length: float = 9.0

var _rng := RandomNumberGenerator.new()
var _state_index: int = 0
var _state_time_left: float = 0.0
var _amplitude: float = 0.0
var _target_amplitude: float = 0.0
var _target_direction := Vector3(1.0, 0.0, 0.0)
var _direction := Vector3(1.0, 0.0, 0.0)
var _time: float = 0.0
var _settled := false


func _ready() -> void:
	_rng.seed = cycle_seed
	if states.is_empty():
		states = _default_states()
	_settled = true
	_reset_to_state(0)


static func _default_states() -> Array[GustState]:
	var calm := GustState.new()
	calm.name = "CALM"
	calm.amplitude_mean = 0.08
	calm.amplitude_variance = 0.04
	calm.duration_mean = 5.0
	calm.duration_variance = 2.0
	var gust := GustState.new()
	gust.name = "GUST"
	gust.amplitude_mean = 0.85
	gust.amplitude_variance = 0.25
	gust.duration_mean = 3.0
	gust.duration_variance = 1.5
	gust.direction_spread_degrees = 20.0
	return [calm, gust]


func _process(delta: float) -> void:
	_time += delta
	if not _settled:
		return
	_state_time_left -= delta
	if _state_time_left <= 0.0:
		_pick_next_state()
	var blend := 1.0 - exp(-damping * delta)
	_amplitude = lerpf(_amplitude, _target_amplitude, blend)
	_direction = _direction.slerp(_target_direction, blend).normalized()


func sample(pos: Vector3, t: float) -> Vector3:
	# 沿风向推进的锋面相位：阵风以波前扫过草地，而不是全域同时起伏。
	var wave_number := TAU / maxf(wave_length, 0.1)
	var phase := t * wave_speed - (pos.x * _direction.x + pos.z * _direction.z) * wave_number
	var envelope := 0.5 + 0.5 * sin(phase)
	var magnitude := _amplitude * (0.35 + 0.65 * envelope)
	return _direction * magnitude


func strength() -> float:
	return _amplitude


func direction() -> Vector3:
	return _direction


func current_state() -> String:
	if not _settled:
		return ""
	return states[_state_index].name


func _reset_to_state(index: int) -> void:
	_state_index = index
	_enter_state()


func _pick_next_state() -> void:
	var next := (_state_index + 1) % states.size()
	_reset_to_state(next)
	wind_state_changed.emit(states[next].name)


func _enter_state() -> void:
	var state := states[_state_index]
	_target_amplitude = clampf(
		state.amplitude_mean + _rng.randf_range(-state.amplitude_variance, state.amplitude_variance),
		0.0, 1.2
	)
	_state_time_left = maxf(
		state.duration_mean + _rng.randf_range(-state.duration_variance, state.duration_variance),
		0.05
	)
	var yaw := deg_to_rad(
		state.direction_center_degrees
		+ _rng.randf_range(-state.direction_spread_degrees, state.direction_spread_degrees)
	)
	_target_direction = Vector3(cos(yaw), 0.0, sin(yaw)).normalized()
