extends SceneTree
func _initialize() -> void:
	var host := MeshInstance3D.new()
	host.mesh = load("res://features/moon_walk/models/moon_craters.res")
	var field := GlyphField.new()
	field.rebuild_on_ready = false
	host.add_child(field)
	for gap in [1.1, 0.05]:
		field.spacing = gap
		var start := Time.get_ticks_usec()
		field.rebuild()
		print("SPACING_BENCH spacing=%s count=%s main_ms=%.2f" % [gap, field.multimesh.instance_count, (Time.get_ticks_usec()-start)/1000.0])
	host.free()
	quit()
