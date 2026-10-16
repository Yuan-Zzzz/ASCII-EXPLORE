extends SceneTree

const OpticsScript = preload("res://features/moon_walk/black_hole_optics.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not await _call_site_radii():
		return
	if not await _call_site_doppler():
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
