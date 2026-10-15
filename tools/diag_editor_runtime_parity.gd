extends SceneTree
## Compare GLYPHS runtime presentation vs editor-open presentation gaps.
## godot --path . --headless -s tools/diag_editor_runtime_parity.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var sun: DirectionalLight3D = main.get_node("Sun")
	var hosts: Array[NodePath] = [^"Pivot/Ground", ^"Pivot/Earth", ^"Pivot/SunBall"]
	var GlyphFieldScript = load("res://features/ascii/glyph_field.gd")

	var runtime_rows: Array = []
	for host_path in hosts:
		var host := main.get_node(host_path) as MeshInstance3D
		var mat := host.material_override as StandardMaterial3D
		var field: Node = null
		for c in host.get_children():
			if c.get_script() == GlyphFieldScript:
				field = c
				break
		var mm: MultiMesh = field.get("multimesh") as MultiMesh if field else null
		var sm: ShaderMaterial = field.get("_shader_mat") as ShaderMaterial if field else null
		if sm == null and field:
			sm = field.material_override as ShaderMaterial
		runtime_rows.append({
			"host": str(host_path),
			"host_albedo": _albedo(mat),
			"host_unshaded": mat != null and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
			"field_light": _vec(field.get("light_dir") if field else null),
			"shader_light": _shader_vec3(sm, "u_light_dir"),
			"instances": mm.instance_count if mm else 0,
			"glyph_px": field.get("glyph_px") if field else null,
		})

	var sun_dir: Vector3 = sun.global_transform.basis.z
	var gaps: Array = []
	for row in runtime_rows:
		# Editor never runs main.gd: hosts keep scene Mat_* (shaded, colored), not depth shell.
		if row["host_unshaded"] and _near_black(row["host_albedo"]):
			pass  # runtime GLYPHS look
		else:
			gaps.append({"kind": "host_not_depth_shell", "host": row["host"], "albedo": row["host_albedo"]})
		var fl: Array = row["field_light"]
		if fl.size() == 3:
			var fld := Vector3(fl[0], fl[1], fl[2])
			if fld.normalized().dot(sun_dir.normalized()) < 0.999:
				# After _process sync they should match; first frames may differ.
				gaps.append({
					"kind": "light_vs_sun_before_sync_note",
					"host": row["host"],
					"field": fl,
					"sun": [sun_dir.x, sun_dir.y, sun_dir.z],
				})

	# Simulate editor gap: what scene hosts look like BEFORE main._apply_view_mode
	# by reading packed scene defaults via a fresh instantiate without waiting for main process.
	var fresh: Node = packed.instantiate()
	var editor_like: Array = []
	for host_path in hosts:
		var host := fresh.get_node(host_path) as MeshInstance3D
		var mat := host.material_override as StandardMaterial3D
		editor_like.append({
			"host": str(host_path),
			"host_albedo": _albedo(mat),
			"host_unshaded": mat != null and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
		})
	fresh.free()

	# After one process frame, lights should match sun.
	await process_frame
	var light_ok := true
	for host_path in hosts:
		var host := main.get_node(host_path) as MeshInstance3D
		for c in host.get_children():
			if c.get_script() != GlyphFieldScript:
				continue
			var ld: Vector3 = c.get("light_dir")
			if ld.normalized().distance_to(sun_dir.normalized()) > 0.001:
				light_ok = false

	var payload := {
		"editor_hint": Engine.is_editor_hint(),
		"runtime_after_ready": runtime_rows,
		"editor_like_scene_materials": editor_like,
		"sun_basis_z": [sun_dir.x, sun_dir.y, sun_dir.z],
		"runtime_light_matches_sun_after_process": light_ok,
		"parity_gaps": {
			"editor_hosts_use_scene_mats_not_depth": true,
			"editor_main_gd_does_not_run": not Engine.is_editor_hint(),
			"editor_light_stays_on_export_default": true,
		},
	}
	print("PARITY_DIAG=" + JSON.stringify(payload))
	quit(0)


func _albedo(mat: StandardMaterial3D) -> Array:
	if mat == null:
		return []
	return [mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b]


func _near_black(a: Array) -> bool:
	if a.size() < 3:
		return false
	return a[0] < 0.05 and a[1] < 0.05 and a[2] < 0.08


func _vec(v: Variant) -> Array:
	if v is Vector3:
		var x := v as Vector3
		return [x.x, x.y, x.z]
	return []


func _shader_vec3(sm: ShaderMaterial, key: String) -> Array:
	if sm == null:
		return []
	var v: Variant = sm.get_shader_parameter(key)
	return _vec(v)
