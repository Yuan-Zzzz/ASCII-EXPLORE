extends SceneTree

const OpticsScript = preload("res://features/black_hole/black_hole_optics.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not await _call_site_radii():
		return
	if not await _call_site_doppler():
		return
	if not await _call_site_occlusion():
		return
	if not await _rejects_inconsistent_pair():
		return
	print("OPTICS_OK")
	quit(0)


func _call_site_radii() -> bool:
	var optics = OpticsScript.new()
	optics.inclination = 0.0
	await process_frame
	var cam := Vector3(0, 200, 0)
	var center := Vector3.ZERO
	if not is_equal_approx(optics.photon_sphere_radius(), 1.5 * optics.rs):
		return _fail("photon sphere %s" % optics.photon_sphere_radius())
	if not is_equal_approx(optics.shadow_radius(), 0.5 * sqrt(27.0) * optics.rs):
		return _fail("shadow %s" % optics.shadow_radius())
	var horizon = optics.trace(center, OpticsScript.Ray.with_impact(cam, center, optics.photon_sphere_radius(), Vector3.RIGHT))
	if not (horizon.valid and horizon.captured and not horizon.shows_background):
		return _fail("photon sphere ray should be captured")
	var edge = optics.trace(center, OpticsScript.Ray.with_impact(cam, center, optics.shadow_radius(), Vector3.RIGHT))
	if not (edge.valid and edge.captured and not edge.shows_background):
		return _fail("capture at b_c impact=%s captured=%s" % [edge.impact, edge.captured])
	var ring = optics.trace(center, OpticsScript.Ray.with_impact(cam, center, optics.shadow_radius() * 1.01, Vector3.RIGHT))
	if ring.captured or not ring.shows_background or ring.ring_radiance <= 0.0:
		return _fail("ring just outside captured=%s bg=%s rad=%s" % [ring.captured, ring.shows_background, ring.ring_radiance])
	if ring.deflection <= 2.0 * optics.rs / ring.impact:
		return _fail("strong deflection %s weak %s" % [ring.deflection, 2.0 * optics.rs / ring.impact])
	var lens = optics.trace(center, OpticsScript.Ray.with_impact(cam, center, optics.shadow_radius() * 5.0, Vector3.RIGHT))
	if not lens.shows_background:
		return _fail("5 b_c should show background")
	if not is_equal_approx(lens.deflection, 2.0 * optics.rs / lens.impact):
		return _fail("weak deflection %s want %s" % [lens.deflection, 2.0 * optics.rs / lens.impact])
	if lens.sample_scale <= 0.0 or lens.sample_scale >= 1.0:
		return _fail("sample_scale %s" % lens.sample_scale)
	return true


func _call_site_doppler() -> bool:
	var optics = OpticsScript.new()
	optics.inclination = 1.15
	optics.node_longitude = 0.0
	await process_frame
	var center := Vector3.ZERO
	var cam := Vector3(0, 40, 180)
	var approach = optics.trace(center, OpticsScript.Ray.looking(cam, Vector3(-12, 0, 0)))
	var recede = optics.trace(center, OpticsScript.Ray.looking(cam, Vector3(12, 0, 0)))
	if not is_equal_approx(approach.disk_radius, 12.0):
		return _fail("approach disk_radius %s captured=%s" % [approach.disk_radius, approach.captured])
	if not is_equal_approx(recede.disk_radius, 12.0):
		return _fail("recede disk_radius %s" % recede.disk_radius)
	if approach.disk_g <= recede.disk_g:
		return _fail("doppler g approach=%s recede=%s" % [approach.disk_g, recede.disk_g])
	if approach.albedo.r <= recede.albedo.r:
		return _fail("doppler albedo approach=%s recede=%s" % [approach.albedo.r, recede.albedo.r])
	return true


func _call_site_occlusion() -> bool:
	## Far-side primary must not paint inside b_crit; near-side may still cross the silhouette.
	var optics = OpticsScript.new()
	optics.rs = 115.47
	optics.inclination = 0.75
	optics.node_longitude = 0.35
	optics.emissivity_exponent = 1.2
	optics.emissivity_peak = 6.0
	await process_frame
	var center := Vector3.ZERO
	var cam := Vector3(0.0, 400.0, 800.0)
	var b_crit: float = optics.shadow_radius()
	var far_fill := 0
	for i in 24:
		for j in 24:
			var u := (float(i) / 23.0 - 0.5) * 2.0
			var v := (float(j) / 23.0 - 0.5) * 2.0
			var target := Vector3(u * b_crit * 0.9, v * b_crit * 0.9, 0.0)
			var hit = optics.trace(center, OpticsScript.Ray.looking(cam, target))
			if hit.disk_radius > 0.0 and hit.impact <= b_crit + 1.0e-3 and not hit.captured:
				far_fill += 1
	if far_fill > 0:
		return _fail("far disk filled shadow in %s samples" % far_fill)
	var deep = optics.trace(center, OpticsScript.Ray.with_impact(cam, center, b_crit * 0.5, Vector3.RIGHT))
	if not (deep.valid and deep.captured and deep.disk_radius <= 0.0):
		return _fail("0.5 b_c should capture without disk captured=%s disk_r=%s" % [deep.captured, deep.disk_radius])
	var near = optics.trace(center, OpticsScript.Ray.looking(cam, Vector3(-optics.disk_inner_radius() * 1.2, 0.0, 0.0)))
	if not near.valid or near.captured or near.disk_radius <= 0.0:
		return _fail("near primary missing disk_r=%s captured=%s" % [near.disk_radius, near.captured])
	var outer = optics.trace(center, OpticsScript.Ray.with_impact(cam, center, b_crit * 1.05, Vector3.UP))
	if outer.captured:
		return _fail("just outside b_c must not capture")
	return true


func _rejects_inconsistent_pair() -> bool:
	var optics = OpticsScript.new()
	var kept_inner: float = optics.disk_inner_rs
	var kept_outer: float = optics.disk_outer_rs
	optics.disk_outer_rs = 4.0
	optics.disk_inner_rs = 5.0
	await process_frame
	if not is_equal_approx(optics.disk_inner_rs, kept_inner) or not is_equal_approx(optics.disk_outer_rs, kept_outer):
		return _fail("inconsistent edit stuck at inner=%s outer=%s" % [optics.disk_inner_rs, optics.disk_outer_rs])
	var rs_before: float = optics.rs
	optics.rs = -1.0
	if not is_equal_approx(optics.rs, rs_before):
		return _fail("negative rs was stored")
	return true


func _fail(message: String) -> bool:
	print("OPTICS_FAIL: %s" % message)
	quit(1)
	return false
