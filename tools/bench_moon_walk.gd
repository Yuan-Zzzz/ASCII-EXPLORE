extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var start := Time.get_ticks_usec()
	var packed := load("res://scenes/moon_walk.tscn") as PackedScene
	var loaded := Time.get_ticks_usec()
	var scene := packed.instantiate()
	root.add_child(scene)
	var ready_time := Time.get_ticks_usec()
	print("BENCH load_ms=%.2f ready_ms=%.2f total_ms=%.2f" % [(loaded-start)/1000.0, (ready_time-loaded)/1000.0, (ready_time-start)/1000.0])
	quit(0 if ready_time-start < 2000000 else 1)
