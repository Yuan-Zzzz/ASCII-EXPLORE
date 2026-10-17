extends SceneTree
## 被黑洞照亮的月面：把太阳光关掉，只留黑洞的盘面光束。
##   godot --path . --script res://tools/shot_lit_moon.gd
## 写出 res://moon_lit_sun.png（太阳 + 黑洞）与 res://moon_lit_bh.png（只有黑洞）。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/moon_walk.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	main.get_node("Orbits").running = false
	var player := main.get_node("Player") as Node3D
	var cam := main.get_node("Player/Camera3D") as Camera3D
	var sun := main.get_node("SkyPivot/SunHost/SunLight") as DirectionalLight3D
	# 面向黑洞：盘面光束从那边照过来。
	var bh := main.get_node("SkyPivot/BlackHole") as Node3D
	# 沿月面往黑洞的反方向走一段，再用相机自己的朝向（出生点默认朝向月心方向之下）。
	player.global_position = Vector3(2.0, 50.4, -2.0)
	var away: Vector3 = (-(bh.global_position as Vector3)).normalized()
	cam.look_at(cam.global_position + away * 100.0 + Vector3.DOWN * 25.0, Vector3.UP)
	await _settle(40)
	_save(cam, "res://moon_lit_sun.png")
	sun.light_energy = 0.0
	await _settle(6)
	_save(cam, "res://moon_lit_bh.png")
	print("LIT_OK")
	quit(0)


func _save(cam: Camera3D, path: String) -> void:
	cam.get_viewport().get_texture().get_image().save_png(path)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw