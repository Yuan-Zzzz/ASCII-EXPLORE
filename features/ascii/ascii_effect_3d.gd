@tool
class_name AsciiEffect3D
extends Node3D
## Add as a child of a MeshInstance3D or imported model root.
## Density is a multiplier of sample count per local surface area.

const Field = preload("res://features/ascii/glyph_field.gd")

@export var enabled: bool = true
@export_range(1.0, 64.0, 0.5) var glyph_px: float = 12.0
@export_range(0.01, 16.0, 0.01) var density: float = 1.0
@export_range(0.05, 10.0, 0.01) var base_spacing: float = 0.35
@export var seed: int = 1
@export var ramp: AsciiRamp = preload("res://features/ascii/ascii_ramp.tres")
@export var tint: Color = Color(0.85, 0.9, 1.0)
@export var light_dir: Vector3 = Vector3(0.4, 0.8, 0.3)
@export_range(0.0, 1.0) var ambient: float = 0.35
@export var background_color: Color = Color(0.02, 0.03, 0.06)
## Empty means parent. Explicit target must be outside this effect's subtree.
@export var target_path: NodePath

var _entries: Dictionary = {}
var _sample_signature: Array = []
var _wait: float = 0.0
var _dirty: bool = true
var _depth: StandardMaterial3D

func _ready() -> void:
	_depth = StandardMaterial3D.new()
	_depth.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rebuild()

func _exit_tree() -> void:
	for host in _entries.keys():
		_release(host)

func _process(delta: float) -> void:
	var hosts: Array[MeshInstance3D] = []
	var target := get_parent() if target_path.is_empty() else get_node_or_null(target_path)
	if target != null and target != self and not is_ancestor_of(target):
		_collect(target, hosts)
	for host in _entries.keys():
		if not is_instance_valid(host) or host not in hosts or host.mesh != _entries[host].mesh:
			_release(host)
	for host in hosts:
		if not _entries.has(host):
			_add(host)
	var signature: Array = [density, base_spacing, seed]
	for host in hosts:
		signature.append(host.mesh)
	if signature != _sample_signature:
		_sample_signature = signature
		_mark_dirty()
	if _dirty:
		_wait -= delta
		if _wait <= 0.0:
			_dirty = false
			for host in _entries:
				var field: GlyphField = _entries[host].field
				field.spacing = maxf(base_spacing / sqrt(maxf(density, 0.01)), 0.05)
				field.seed = seed
				field.rebuild()
	_depth.albedo_color = background_color
	for host in _entries:
		var entry: Dictionary = _entries[host]
		var field: GlyphField = entry.field
		field.visible = enabled and is_visible_in_tree()
		field.glyph_px = glyph_px
		field.ramp = ramp
		field.tint = tint
		field.light_dir = light_dir
		field.ambient = ambient
		field._apply_params()
		host.material_override = _depth if field.visible else entry.material

func rebuild() -> void:
	_sample_signature = []
	_dirty = true
	_wait = 0.0

func _mark_dirty() -> void:
	_dirty = true
	_wait = 0.25

func _collect(node: Node, hosts: Array[MeshInstance3D]) -> void:
	if node == self:
		return
	if node is MeshInstance3D:
		hosts.append(node)
	for child in node.get_children():
		_collect(child, hosts)

func _add(host: MeshInstance3D) -> void:
	var field := Field.new()
	field.name = "_AsciiGlyphs"
	field.rebuild_on_ready = false
	# 字形节点负责后台任务轮询和合并重建。
	field.set_process(true)
	var mesh := host.mesh
	if mesh != null:
		mesh.changed.connect(_mesh_changed.bind(host))
	_entries[host] = {"field": field, "material": host.material_override, "mesh": mesh}
	host.add_child(field, false, Node.INTERNAL_MODE_BACK)

func _release(host: MeshInstance3D) -> void:
	var entry: Dictionary = _entries[host]
	var mesh: Mesh = entry.mesh
	if is_instance_valid(mesh) and mesh.changed.is_connected(_mesh_changed.bind(host)):
		mesh.changed.disconnect(_mesh_changed.bind(host))
	if is_instance_valid(host) and host.material_override == _depth:
		host.material_override = entry.material
	if is_instance_valid(entry.field):
		entry.field.queue_free()
	_entries.erase(host)

func _mesh_changed(_host: MeshInstance3D) -> void:
	_mark_dirty()

