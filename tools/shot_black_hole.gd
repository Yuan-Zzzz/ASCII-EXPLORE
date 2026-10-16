extends SceneTree
## GPU shot of SkyPivot/BlackHole. Usage:
##   godot --path . --script res://tools/shot_black_hole.gd
## Writes res://bh_shot.png and res://bh_shot_close.png


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/moon_walk.tscn") as PackedScene
	if packed == null:
		printerr("SHOT_FAIL load")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	var bh = main.get_node_or_null("SkyPivot/BlackHole")
	if bh == null:
		printerr("SHOT_FAIL missing BlackHole")
		quit(1)
		return
	var player := main.get_node("Player") as Node3D
	var cam := main.get_node("Player/Camera3D") as Camera3D
	if player == null or cam == null:
		printerr("SHOT_FAIL camera")
		quit(1)
		return

	main.set("surface_render_mode", 2)
	bh.set("animate", true)
	bh.set("spin_speed", 1.4)
	bh.set("glyph_px", 8.0)

	var center: Vector3 = bh.global_position
	var optics = bh.optics
	var normal: Vector3 = optics.disk_normal()
	# Face the disk so the ring is not a thin crescent.
	var view_dir := (normal * 0.75 + Vector3(0.35, 0.1, 0.2)).normalized()

	player.global_position = center + view_dir * 95.0
	cam.look_at(center, Vector3.UP)
	await _settle(100)
	if not await _save(cam, "res://bh_shot.png"):
		return

	player.global_position = center + view_dir * 42.0
	cam.look_at(center, Vector3.UP)
	await _settle(100)
	if not await _save(cam, "res://bh_shot_close.png"):
		return

	main.set("surface_render_mode", 1)
	await _settle(8)
	if not await _save(cam, "res://bh_shot_raw.png"):
		return

	print("SHOT_OK bh=%s normal=%s" % [center, normal])
	quit(0)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save(cam: Camera3D, path: String) -> bool:
	var tex := cam.get_viewport().get_texture()
	if tex == null:
		printerr("SHOT_FAIL no texture %s" % path)
		quit(1)
		return false
	var img := tex.get_image()
	if img == null:
		printerr("SHOT_FAIL no image %s" % path)
		quit(1)
		return false
	if img.get_format() != Image.FORMAT_RGB8 and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var err := img.save_png(path)
	if err != OK:
		printerr("SHOT_FAIL save %s err=%s" % [path, err])
		quit(1)
		return false
	var bright := 0.0
	var warm := 0.0
	var samples := 0
	var step := maxi(img.get_width() / 80, 1)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			bright += lum
			if c.r > c.b + 0.05 and lum > 0.08:
				warm += 1.0
			samples += 1
	print(
		"SHOT_WROTE %s size=%sx%s mean_lum=%.4f warm_frac=%.3f"
		% [path, img.get_width(), img.get_height(), bright / float(samples), warm / float(samples)]
	)
	return true
