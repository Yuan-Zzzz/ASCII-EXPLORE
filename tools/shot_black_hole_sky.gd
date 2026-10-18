extends SceneTree
## 从月面看天空里的黑洞：把镜头对着黑洞，写出 res://sky_bh.png。
##   godot --path . --script res://tools/shot_black_hole_sky.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/moon_walk.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	main.get_node("Orbits").running = false
	var bh = main.get_node("SkyPivot/BlackHole")
	var player := main.get_node("Player") as Node3D
	var cam := main.get_node("Player/Camera3D") as Camera3D
	player.global_position = Vector3(0, 50.0, 0)
	await _settle(4)
	cam.look_at(bh.global_position, Vector3.UP)
	bh.animate = false
	await _settle(40)
	_save(cam, "res://sky_bh.png")
	var lens = bh.get_node_or_null("MoonLens")
	print("SKY lens=", lens, " visible=", lens.visible if lens else null, " dist=", cam.global_position.distance_to(bh.global_position))
	if OS.get_environment("SKY_HIDE_BODIES") == "1":
		for path in ["SkyPivot/Earth", "SkyPivot/SunHost"]:
			main.get_node(path).layers = 0
		await _settle(6)
		_save(cam, "res://sky_bh_nobody.png")
	if lens:
		var m: ShaderMaterial = lens.material_override
		print("SKY params occ=", m.get_shader_parameter("u_occlude"), " r=", m.get_shader_parameter("u_occluder_radius"), " beacon=", m.get_shader_parameter("u_beam_lit"), " transit=", m.get_shader_parameter("u_transit"), " hdist=", m.get_shader_parameter("u_sky_height_0"), " count=", m.get_shader_parameter("u_sky_count"))
		_save(cam, "res://sky_bh_ascii.png")
		bh.set("surface_render_mode", 1)
		await _settle(6)
		_save(cam, "res://sky_bh_raw.png")
	print("SKY_OK")
	quit(0)


func _save(cam: Camera3D, path: String) -> void:
	var img := cam.get_viewport().get_texture().get_image()
	img.save_png(path)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
