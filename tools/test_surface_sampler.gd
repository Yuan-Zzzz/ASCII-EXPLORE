extends SceneTree
## Compare weighted selection against the original linear scan, including zero-area triangles.
const Sampler = preload("res://features/ascii/surface_sampler.gd")

func _initialize() -> void:
	for areas in [PackedFloat32Array([0, 0, 1, 0, 2, 0, 4]), PackedFloat32Array([0, 0]), PackedFloat32Array([1])]:
		var cumulative := PackedFloat64Array()
		var total := 0.0
		for area in areas:
			total += area
			cumulative.append(total)
		var reference := RandomNumberGenerator.new()
		var optimized := RandomNumberGenerator.new()
		reference.seed = 48
		optimized.seed = 48
		for i in 10000:
			var r := reference.randf() * total
			var expected: int = areas.size() - 1
			var acc := 0.0
			for j in areas.size():
				acc += areas[j]
				if r <= acc:
					expected = j
					break
			if Sampler._pick_triangle(optimized, cumulative, total) != expected:
				printerr("SAMPLER_FAIL weighted selection changed")
				quit(1)
				return
	print("SAMPLER_OK 30000 weighted selections match linear reference")
	quit(0)

