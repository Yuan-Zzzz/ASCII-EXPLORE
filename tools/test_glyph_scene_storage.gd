extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/moon_walk.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	var paths := ["Moon/MoonMesh/GlyphField", "SkyPivot/Earth/GlyphField", "SkyPivot/SunHost/GlyphField"]
	var counts: Array[int] = []
	for path in paths:
		var field := scene.get_node(path) as GlyphField
		while field._preview_dirty or field._preview_thread != null:
			await process_frame
		assert(field.multimesh != null and field.multimesh.instance_count > 0)
		counts.append(field.multimesh.instance_count)
	var saved := PackedScene.new()
	assert(saved.pack(scene) == OK)
	var state := saved.get_state()
	for i in state.get_node_count():
		if str(state.get_node_path(i)) in paths:
			for j in state.get_node_property_count(i):
				assert(state.get_node_property_name(i, j) not in [&"multimesh", &"material_override"], "Generated preview must not be stored")
	var target := "user://test_glyph_scene_storage.tscn"
	assert(ResourceSaver.save(saved, target) == OK)
	assert(FileAccess.get_file_as_bytes(target).size() < 65536, "Saved scene must remain small")
	var reloaded := (ResourceLoader.load(target, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(reloaded)
	await process_frame
	for i in paths.size():
		var field := reloaded.get_node(paths[i]) as GlyphField
		while field._preview_dirty or field._preview_thread != null:
			await process_frame
		assert(field.multimesh.instance_count == counts[i], "Reload must regenerate identical glyphs")
	var baked := scene.get_node(paths[0]) as GlyphField
	baked.rebuild_on_ready = false
	var stored_mesh := false
	for property in baked.get_property_list():
		if property.name == &"multimesh":
			stored_mesh = (int(property.usage) & PROPERTY_USAGE_STORAGE) != 0
	assert(stored_mesh, "Manual bake mode must retain mesh storage")
	DirAccess.remove_absolute(target)
	print("GLYPH_SCENE_STORAGE_OK counts=%s" % [counts])
	reloaded.free()
	scene.free()
	quit(0)
