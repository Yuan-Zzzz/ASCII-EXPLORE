extends SceneTree
## GPU shot of the moon surface from the player camera. Usage:
##   godot --path . --script res://tools/shot_moon_surface.gd
## Writes res://moon_shot.png (default view) and res://moon_shot_side.png.

const TAG := "MOON_SHOT"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/moon_walk.tscn") as PackedScene
	if packed == null:
		printerr(TAG + "_FAIL load")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	var player := main.get_node("Player") as Node3D
	var cam := main.get_node("Player/Camera3D") as Camera3D
	var orbits := main.get_node("Orbits")
	orbits.set("running", false)
	await _settle(60)

	if not await _save(cam, "res://moon_shot.png", TAG):
		return

	# 侧向视角：从月面看天空，能看到天空里的天体。
	player.global_position = Vector3(0, 54, 44)
	cam.look_at(Vector3(0, 70, 0), Vector3.UP)
	var anchor := Node3D.new()
	main.add_child(anchor)
	anchor.global_position = Vector3(0, 50, 0)
	cam.look_at(Vector3(-40000.0, 30000.0, 0.0), Vector3.UP)
	await _settle(30)
	if not await _save(cam, "res://moon_shot_sky.png", TAG):
		return
	print(TAG + "_OK")
	quit(0)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save(cam: Camera3D, path: String, tag: String) -> bool:
	var tex := cam.get_viewport().get_texture()
	if tex == null:
		printerr(tag + "_FAIL no texture")
		quit(1)
		return false
	var img := tex.get_image()
	if img == null:
		printerr(tag + "_FAIL no image")
		quit(1)
		return false
	if img.get_format() != Image.FORMAT_RGB8 and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var err := img.save_png(path)
	if err != OK:
		printerr(tag + "_FAIL save %s" % err)
		quit(1)
		return false
	print("%s_WROTE %s" % [tag, path])
	return true
