class_name OrbitalMotion
extends Node3D
## 运行时轨道动画：太阳系绕黑洞、地球绕太阳、月球绕地球。
##
## 轨道半径与初始相位都从场景里节点的初始位置推导，因此 t=0 时画面与编辑状态一致，
## 不需要在场景里重复保存一份轨道参数。所有轨道都绕世界 Y 轴，月球中心保持在同一水平面。
##
## 渲染以月球为参考系：月球节点保持不动，天空天体按月球轨道的反方向整体平移，
## 因此玩家不会感到脚下的月面在移动，天体之间的相对轨道关系与原来完全一致。
## 每帧只平移天空节点，角色仍由 MoonFpsController 做本地物理。
##
## 该节点只在运行时移动物体；编辑器里不修改节点变换，避免把动画帧写回场景。

## 太阳系绕黑洞一周的秒数。
@export_range(1.0, 100000.0, 1.0, "or_greater") var sun_period: float = 600.0
## 地球绕太阳一周的秒数。
@export_range(1.0, 100000.0, 1.0, "or_greater") var earth_period: float = 240.0
## 月球绕地球一周的秒数。
@export_range(1.0, 100000.0, 1.0, "or_greater") var moon_period: float = 60.0
## 3D 场景时间倍率；0 可暂停，方便观察月面。
@export_range(0.0, 20.0, 0.01) var time_scale: float = 1.0
## 关闭后物体停在当前轨道位置。
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

## 以黑洞为原点的初始偏移。保留 y 分量，使各天体维持场景里原有的高度差。
var _black_hole_pos := Vector3.ZERO
var _sun_orbit := Vector3.ZERO
var _earth_orbit := Vector3.ZERO
var _moon_orbit := Vector3.ZERO
## 月球的场景初始位置。运行时它作为整个天空的渲染原点，不参与平移。
var _moon_home := Vector3.ZERO
var _time := 0.0
var _initialized := false


func _ready() -> void:
	_bind()


func _physics_process(delta: float) -> void:
	if not running or not _initialized:
		return
	_time += delta * time_scale
	_apply(_time)


## 直接求值到指定时刻。回归测试用它跨过长时间，不必真的等待。
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
		push_error("OrbitalMotion: 黑洞、太阳、地球或月球路径无效")
		return
	_black_hole_pos = _black_hole.global_position
	_sun_orbit = _sun.global_position - _black_hole_pos
	_earth_orbit = _earth.global_position - _sun.global_position
	_moon_orbit = _moon.global_position - _earth.global_position
	_moon_home = _moon.global_position
	_initialized = true


func _apply(seconds: float) -> void:
	var sun_turns := seconds / maxf(sun_period, 0.001)
	var earth_turns := seconds / maxf(earth_period, 0.001)
	var moon_turns := seconds / maxf(moon_period, 0.001)
	var sun_pos := _black_hole_pos + _orbit_offset(_sun_orbit, sun_turns)
	var earth_pos := sun_pos + _orbit_offset(_earth_orbit, earth_turns)
	var moon_pos := earth_pos + _orbit_offset(_moon_orbit, moon_turns)
	# 把天空整体反向平移月球轨道的位移：月球留在场景原点，天体相对位置不变。
	var moon_shift := moon_pos - _moon_home

	_black_hole.global_position = _black_hole_pos - moon_shift
	_sun.global_position = sun_pos - moon_shift
	_earth.global_position = earth_pos - moon_shift
	# 月球节点保持不动，玩家不需要每帧传送，月面碰撞与角色物理都留在稳定的局部坐标里。

	if _sun_light != null:
		_sun_light.global_position = sun_pos - moon_shift
		_aim_light_at(_moon_home)


## 绕 Y 轴旋转 offset 的 x/z 分量，保留 y 分量。turns 为圈数。
static func _orbit_offset(offset: Vector3, turns: float) -> Vector3:
	var radius := Vector2(offset.x, offset.z).length()
	if radius <= 0.000001:
		return offset
	var phase := atan2(offset.x, offset.z) + turns * TAU
	return Vector3(sin(phase) * radius, offset.y, cos(phase) * radius)


func _aim_light_at(target: Vector3) -> void:
	# 平行光从太阳射向月球；太阳几乎在正上方时换一个上方向，避免 look_at 退化。
	var up := Vector3.UP
	var direction := target - _sun_light.global_position
	if direction.length_squared() <= 0.000001:
		return
	if absf(direction.normalized().dot(up)) > 0.999:
		up = Vector3.FORWARD
	_sun_light.look_at(target, up)
