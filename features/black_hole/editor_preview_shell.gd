extends RefCounted
## No class_name: BlackHoleOptics stays the only optics entry point.
## Host is Node3D so this file can preload without cycling through black_hole.gd.

const _EDITOR_STEP := 0.016

var _host: Node3D
var _bound: BlackHoleOptics


func attach(host: Node3D) -> void:
	if host == null or host._shell != self:
		push_error("BlackHole refuses a second editor preview shell")
		return
	_host = host


## Connect next before dropping _bound so a failure between the two still has a listener.
func bind(next: BlackHoleOptics) -> void:
	if _host == null:
		return
	if next == _bound and (next == null or next.changed.is_connected(_host._upload)):
		return
	if next != null and not next.changed.is_connected(_host._upload):
		next.changed.connect(_host._upload)
	if _bound != null and _bound != next and _bound.changed.is_connected(_host._upload):
		_bound.changed.disconnect(_host._upload)
	_bound = next
	if next != null and _host.is_inside_tree():
		_host._upload()


func tick(delta: float) -> void:
	if _host == null:
		return
	var editor := Engine.is_editor_hint()
	# The editor disk uses a fixed step so it does not follow the inspector redraw interval.
	var step := _EDITOR_STEP if editor else delta
	if _host.animate:
		_host._advance_disk(step)
	_host._apply_presentation()
	_host._publish_light()
	if not editor:
		_host._publish_moon_view()


func frame_black_hole() -> Transform3D:
	if _host == null:
		return Transform3D()
	var optics := _host.optics as BlackHoleOptics
	if optics == null or not optics.consistent():
		push_error("BlackHole frame needs consistent optics")
		return Transform3D()
	var pose := _camera_pose(_host.global_position, optics.disk_normal(), optics.lens_radius())
	_write_editor_camera(pose)
	return pose


## Dividing by MAX_RADIUS_OVER_DISTANCE puts the eye on the sky-lens angular cap.
static func _camera_pose(target: Vector3, disk_normal: Vector3, lens_radius: float) -> Transform3D:
	if lens_radius <= 0.0:
		push_error("BlackHole frame needs a positive lens radius")
		return Transform3D()
	var distance := lens_radius / BlackHoleOptics.MAX_RADIUS_OVER_DISTANCE
	var normal := disk_normal.normalized()
	var eye := target + normal * distance
	var up := Vector3.UP
	if absf(normal.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	return Transform3D(Basis.looking_at(target - eye, up), eye)


func _write_editor_camera(pose: Transform3D) -> bool:
	if not Engine.is_editor_hint():
		return false
	var ei := Engine.get_singleton(&"EditorInterface")
	if ei == null or not ei.has_method(&"get_editor_viewport_3d"):
		return false
	var viewport := ei.call(&"get_editor_viewport_3d", 0) as SubViewport
	if viewport == null:
		return false
	var cam := viewport.get_camera_3d()
	if cam == null:
		return false
	cam.global_transform = pose
	return true
