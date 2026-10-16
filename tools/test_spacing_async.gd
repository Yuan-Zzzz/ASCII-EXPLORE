extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := MeshInstance3D.new()
	host.mesh = load("res://features/moon_walk/models/moon_craters.res")
	var field := GlyphField.new()
	field.rebuild_on_ready = false
	host.add_child(field)
	root.add_child(host)
	field.set_process(false)
	var max_main_us := 0
	var start := Time.get_ticks_usec()
	field.spacing = 0.05
	field.rebuild()
	max_main_us = maxi(max_main_us, _tick(field, 0.3))
	assert(field._preview_thread != null, "Dense rebuild must run in background")
	# 工作进行中继续拖动，只能发布最后一个请求。
	field.spacing = 0.8
	max_main_us = maxi(max_main_us, _tick(field, 0.01))
	field.spacing = 1.1
	max_main_us = maxi(max_main_us, _tick(field, 0.3))
	while field._preview_thread != null or field._preview_dirty:
		assert(Time.get_ticks_usec() - start < 15000000, "Preview timed out")
		max_main_us = maxi(max_main_us, _tick(field, 0.1))
		if field._preview_thread != null:
			assert(field.multimesh == null, "Stale dense result must not be published")
		await process_frame
	var reference := SurfaceSampler.sample_mesh(host.mesh, 1.1, field.seed)
	assert(field.multimesh.instance_count == reference.positions.size())
	var result := GlyphField._build_buffer(SurfaceSampler._mesh_arrays(host.mesh), 1.1, field.seed)
	var buffer: PackedFloat32Array = result.buffer
	var rng := RandomNumberGenerator.new()
	rng.seed = field.seed + 17
	for i in field.multimesh.instance_count:
		var offset := i * 16
		assert(Vector3(buffer[offset+3], buffer[offset+7], buffer[offset+11]).is_equal_approx(reference.positions[i]))
		var n: Vector3 = reference.normals[i]
		assert(Color(buffer[offset+12], buffer[offset+13], buffer[offset+14], buffer[offset+15]).is_equal_approx(Color(n.x, n.y, n.z, rng.randf())))
	print("SPACING_ASYNC_OK count=%d max_main_ms=%.2f elapsed_ms=%.2f" % [field.multimesh.instance_count, max_main_us/1000.0, (Time.get_ticks_usec()-start)/1000.0])
	assert(max_main_us < 100000, "Spacing update must not block main thread for 100 ms")
	# 节点退出时必须回收仍在运行的任务。
	field.spacing = 0.8
	_tick(field, 0.3)
	assert(field._preview_thread != null)
	host.free()
	quit(0)


func _tick(field: GlyphField, delta: float) -> int:
	var start := Time.get_ticks_usec()
	field._process(delta)
	return Time.get_ticks_usec() - start
