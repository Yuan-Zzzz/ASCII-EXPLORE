extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		printerr("pin_glyph_fields: failed to load main.tscn")
		quit(1)
		return

	var main: Node = packed.instantiate()
	root.add_child(main)

	var GlyphFieldScript = load("res://features/ascii/glyph_field.gd")
	var hosts: Array[NodePath] = [
		^"Ground",
		^"Earth",
		^"SunBall",
	]
	var fields: Array[Dictionary] = []
	var deadline := Time.get_ticks_msec() + 20000
	for host_path in hosts:
		var host := main.get_node_or_null(host_path) as MeshInstance3D
		if host == null:
			fields.append({"host": str(host_path), "error": "missing_host"})
			continue
		var found: Array[Dictionary] = []
		for child in host.get_children():
			if child.get_script() != GlyphFieldScript:
				continue
			var field := child as GlyphField
			while field._preview_dirty or field._preview_thread != null:
				if Time.get_ticks_msec() > deadline:
					break
				await process_frame
			var mm: MultiMesh = child.get("multimesh") as MultiMesh
			found.append({
				"name": child.name,
				"spacing": child.get("spacing"),
				"edge_step": child.get("edge_step"),
				"seed": child.get("seed"),
				"glyph_px": child.get("glyph_px"),
				"rebuild_on_ready": child.get("rebuild_on_ready"),
				"ramp_path": _resource_path(child.get("ramp")),
				"instance_count": mm.instance_count if mm else 0,
				"visible": child.visible,
			})
		fields.append({
			"host": str(host_path),
			"child_count_glyph": found.size(),
			"fields": found,
		})

	var payload := {
		"view_mode": main.get("view_mode"),
		"main_glyph_px": main.get("glyph_px"),
		"main_ramp": _resource_path(main.get("ramp")),
		"hosts": fields,
	}
	print("PIN_GLYPH_FIELDS_JSON=" + JSON.stringify(payload))
	quit(0)


func _color_to_array(c: Variant) -> Array:
	if c is Color:
		var col := c as Color
		return [col.r, col.g, col.b, col.a]
	return []


func _resource_path(res: Variant) -> String:
	if res is Resource:
		return (res as Resource).resource_path
	return ""
