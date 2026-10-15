extends SceneTree
## 离线修改月球模型并保存碰撞体：godot --headless --path . --script res://tools/bake_moon_model.gd

func _initialize() -> void:
	var builder := preload("res://features/moon_walk/moon_terrain.gd").new()
	var mesh: ArrayMesh = builder.build_mesh()
	mesh.resource_name = "Moon crater terrain"
	var collision := mesh.create_trimesh_shape()
	collision.resource_name = "Moon crater collision"
	var folder := "res://features/moon_walk/models"
	DirAccess.make_dir_recursive_absolute(folder)
	var mesh_error := ResourceSaver.save(mesh, folder + "/moon_craters.res", ResourceSaver.FLAG_COMPRESS)
	var collision_error := ResourceSaver.save(collision, folder + "/moon_craters_collision.res", ResourceSaver.FLAG_COMPRESS)
	builder.free()
	if mesh_error != OK or collision_error != OK:
		printerr("MODEL_BAKE_FAILED mesh=%s collision=%s" % [mesh_error, collision_error])
		quit(1)
		return
	print("MODEL_BAKE_OK vertices=%d" % mesh.surface_get_array_len(0))
	quit(0)
