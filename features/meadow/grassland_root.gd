class_name GrasslandRoot
extends "res://features/ascii/ascii_surface_root.gd"
## 草原场景特有逻辑：黑洞盘光驱动字形光照，风场驱动水面。


@export var bonfire_path: NodePath = ^""
@export var gust_path: NodePath = ^""
@export var water_path: NodePath = ^""
@export var black_hole_path: NodePath = ^""

var _gust: GustField
var _water: WaterPlane
var _bonfire: Bonfire
var _bh: BlackHole


func _ready() -> void:
	super._ready()
	_bind_black_hole()
	_gust = get_node_or_null(gust_path) as GustField
	_water = get_node_or_null(water_path) as WaterPlane
	_bonfire = get_node_or_null(bonfire_path) as Bonfire


func _process(delta: float) -> void:
	super._process(delta)
	if _bh != null:
		set_light_direction(_bh.light_direction(_bh.optics.black_hole_frame()))
	if _gust != null and _water != null:
		_water.set_wind(_gust.strength(), _gust.direction())


## 基类在 _ready 里缓存 _light；黑洞在运行时才建灯，这里直接重绑。
func _bind_black_hole() -> void:
	if black_hole_path.is_empty():
		return
	_bh = get_node_or_null(black_hole_path) as BlackHole
	if _bh == null:
		return
	var light := _bh.light_source()
	if light != null:
		_light = light
