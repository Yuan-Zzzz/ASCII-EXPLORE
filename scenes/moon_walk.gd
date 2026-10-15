extends Node3D

const GlyphFieldScript = preload("res://features/ascii/glyph_field.gd")

@onready var sun: DirectionalLight3D = $SkyPivot/Sun
@onready var sun_ball: MeshInstance3D = $SkyPivot/SunBall

var _fields: Array[Node] = []


func _ready() -> void:
	_collect_fields()
	_aim_sun()
	_sync_light()


func _process(_delta: float) -> void:
	_sync_light()


func _collect_fields() -> void:
	_fields.clear()
	for host_path in [^"Moon/MoonMesh", ^"SkyPivot/Earth", ^"SkyPivot/SunBall"]:
		var host := get_node_or_null(host_path)
		if host == null:
			continue
		for child in host.get_children():
			if child.get_script() == GlyphFieldScript:
				_fields.append(child)


func _aim_sun() -> void:
	var dir := sun_ball.global_position
	if dir.length_squared() < 0.000001:
		return
	dir = dir.normalized()
	var reference := Vector3.UP
	if absf(dir.dot(reference)) > 0.98:
		reference = Vector3.FORWARD
	var x := reference.cross(dir).normalized()
	var y := dir.cross(x).normalized()
	sun.global_basis = Basis(x, y, dir)


func _sync_light() -> void:
	# DirectionalLight 光线沿本地 -Z 射出；Lambert 要用「指向光源」的方向 = +Z
	var dir := sun.global_transform.basis.z
	for f in _fields:
		if is_instance_valid(f):
			f.set_light_dir(dir)
			f.sync_viewport_size()
