@tool
class_name BlackHoleOptics
extends Resource
## 史瓦西光学。只存独立量。阴影、光子球、盘法线和红移都从这些量推出。
## 位置不在这份资源里。trace 的 center 是 BlackHole 的原点。
## 盘法线只由 inclination 和 node_longitude 决定，不读节点的 basis。
## 盘面朝向由黑潮坐标系的 node_longitude 决定；观察者绕同一节点轴转 180°，
## 盘的镜像姿态完全复现，从月面看黑洞就像从黑洞看月面，所以黑洞可以作为光源。

const ISCO_IN_RS := 3.0
const PHOTON_SPHERE_IN_RS := 1.5
const LENS_SHADOW_MULTIPLE := 8.0
const APODIZE_START_FRACTION := 0.75
const MAX_RADIUS_OVER_DISTANCE := 0.45
const IMPACT_X_FLOOR := 1.0e-4
const COLOR_INNER := Color(1.0, 0.82, 0.55)
const COLOR_OUTER := Color(0.85, 0.22, 0.04)
## 射线归一化后，正好落在内缘上的交点会比半径小几个 ulp。闭合环带，避免合法内缘被丢掉。
const ANNULUS_EPS := 1.0e-3
## 阴影角半径的上限。用 to_black_hole_frame 把观察者塞到靠近黑洞时，缺口半径可以超过这个值。
const SHADOW_CONE_LIMIT := 2.5

var _good_rs: float
var _good_disk_inner_rs: float
var _good_disk_outer_rs: float
var _good_inclination: float
var _good_node_longitude: float
var _good_emissivity_exponent: float
var _good_emissivity_peak: float
var _good_photon_ring_width_rs: float
var _good_photon_ring_gain: float
var _commit_queued: bool = false
var _restoring: bool = false

@export var rs: float = 4.0:
	set(value):
		if value <= 0.0:
			push_error("BlackHoleOptics.rs must be > 0")
			return
		rs = value
		_queue_commit()

@export var disk_inner_rs: float = 3.0:
	set(value):
		if value < ISCO_IN_RS:
			push_error("BlackHoleOptics.disk_inner_rs below ISCO")
			return
		disk_inner_rs = value
		_queue_commit()

@export var disk_outer_rs: float = 7.0:
	set(value):
		if value <= ISCO_IN_RS:
			push_error("BlackHoleOptics.disk_outer_rs too small")
			return
		disk_outer_rs = value
		_queue_commit()

@export_range(0.0, 1.5707963) var inclination: float = 1.15:
	set(value):
		if value < 0.0 or value > PI * 0.5:
			push_error("BlackHoleOptics.inclination out of range")
			return
		inclination = value
		_queue_commit()

@export var node_longitude: float = 0.0:
	set(value):
		node_longitude = wrapf(value, 0.0, TAU)
		_queue_commit()

@export var emissivity_exponent: float = 2.0:
	set(value):
		if value <= 0.0:
			push_error("BlackHoleOptics.emissivity_exponent must be > 0")
			return
		emissivity_exponent = value
		_queue_commit()

@export var emissivity_peak: float = 2.0:
	set(value):
		if value <= 0.0:
			push_error("BlackHoleOptics.emissivity_peak must be > 0")
			return
		emissivity_peak = value
		_queue_commit()

@export var photon_ring_width_rs: float = 0.12:
	set(value):
		if value <= 0.0:
			push_error("BlackHoleOptics.photon_ring_width_rs must be > 0")
			return
		photon_ring_width_rs = value
		_queue_commit()

@export var photon_ring_gain: float = 1.5:
	set(value):
		if value < 0.0:
			push_error("BlackHoleOptics.photon_ring_gain < 0")
			return
		photon_ring_gain = value
		_queue_commit()


func _init() -> void:
	_remember()


func _queue_commit() -> void:
	if _restoring:
		return
	if _commit_queued:
		return
	_commit_queued = true
	call_deferred("_commit")


func _commit() -> void:
	_commit_queued = false
	if not consistent():
		_restoring = true
		rs = _good_rs
		disk_inner_rs = _good_disk_inner_rs
		disk_outer_rs = _good_disk_outer_rs
		inclination = _good_inclination
		node_longitude = _good_node_longitude
		emissivity_exponent = _good_emissivity_exponent
		emissivity_peak = _good_emissivity_peak
		photon_ring_width_rs = _good_photon_ring_width_rs
		photon_ring_gain = _good_photon_ring_gain
		_restoring = false
		push_error("BlackHoleOptics rejected an inconsistent edit")
		return
	_remember()
	emit_changed()


func _remember() -> void:
	_good_rs = rs
	_good_disk_inner_rs = disk_inner_rs
	_good_disk_outer_rs = disk_outer_rs
	_good_inclination = inclination
	_good_node_longitude = node_longitude
	_good_emissivity_exponent = emissivity_exponent
	_good_emissivity_peak = emissivity_peak
	_good_photon_ring_width_rs = photon_ring_width_rs
	_good_photon_ring_gain = photon_ring_gain


func consistent() -> bool:
	if rs <= 0.0:
		return false
	if disk_inner_rs < ISCO_IN_RS:
		return false
	if disk_inner_rs >= disk_outer_rs:
		return false
	if disk_outer_rs > max_disk_outer_rs():
		return false
	if inclination < 0.0 or inclination > PI * 0.5:
		return false
	if emissivity_exponent <= 0.0 or emissivity_peak <= 0.0:
		return false
	if photon_ring_width_rs <= 0.0:
		return false
	if photon_ring_gain < 0.0:
		return false
	return true


static func shadow_per_rs() -> float:
	return 0.5 * sqrt(27.0)


static func max_disk_outer_rs() -> float:
	return APODIZE_START_FRACTION * LENS_SHADOW_MULTIPLE * shadow_per_rs()


static func bozza_offset() -> float:
	return log(216.0 * (7.0 - 4.0 * sqrt(3.0))) - PI


func shadow_radius() -> float:
	return shadow_per_rs() * rs


func photon_sphere_radius() -> float:
	return PHOTON_SPHERE_IN_RS * rs


func disk_inner_radius() -> float:
	return disk_inner_rs * rs


func disk_outer_radius() -> float:
	return disk_outer_rs * rs


func disk_normal() -> Vector3:
	var normal := Vector3(
		sin(inclination) * sin(node_longitude),
		cos(inclination),
		sin(inclination) * cos(node_longitude)
	)
	return normal.normalized()


func lens_radius() -> float:
	return LENS_SHADOW_MULTIPLE * shadow_radius()


## 节点轴：倾斜角衡量它与盘法线的夹角。盘面绕它旋转 node_longitude。
func node_axis() -> Vector3:
	return disk_normal().cross(Vector3.UP).normalized()


## 观察者坐标系到黑洞坐标系的旋转：绕节点轴转 node_longitude，
## 让倾斜量落在 x 轴上（与 BlackHole 里 -Z 指向观察者的默认朝向一致）。
static func to_black_hole_frame(node_longitude: float) -> Basis:
	return Basis(Vector3.UP, node_longitude)


func black_hole_frame() -> Basis:
	return to_black_hole_frame(node_longitude)


## 观察者坐标系里作为光源的盘：法线取盘法线的反号。
## 观察者在 -Z 一侧等于从盘的上方看；观察者翻到 +Z 一侧时，
## 盘法线由 (sin i sin n, cos i, sin i cos n) 变成 (-sin i sin n, cos i, -sin i cos n)，
## 正好是镜像的黑洞。着色器里的 accretion_glow() 用同一组角度重建，因此两边亮度一致。
func light_disk_normal() -> Vector3:
	return (black_hole_frame() * -disk_normal()).normalized()


## 遮蔽角半径：视线侧倾超过它就被事件视界挡住。大 b 处接近 1.5 * rs / b。
func shadow_cone_radius(distance: float) -> float:
	if distance <= rs:
		return PI * 0.5
	return minf(asin(shadow_radius() / distance), SHADOW_CONE_LIMIT)


## 从观察者看到的盘面光束辐射：d = 覆盖比例，cone = 视线侧倾角，
## los = 观察者视线在盘面内的速度投影（多普勒），g_shift = 红移。
## 与 black_hole_lens.gdshader 的 accretion_glow() 同形：近侧辉光更亮，远侧更暗。
func beam_radiance(g_shift: float, cone: float, coverage: float, los: float) -> Color:
	var beaming := pow(maxf(g_shift, 0.2), 4.0)
	return COLOR_INNER * emissivity_peak * beaming * beam_shape(cone, coverage)


static func beam_shape(cone: float, coverage: float) -> float:
	var slant := sin(cone)
	var ring_halo := exp(-pow(clampf(1.0 - slant, 0.0, 1.0) / 1.15, 2.0))
	var outer_halo := exp(-pow(clampf(1.0 - slant, 0.0, 1.0) / 3.2, 2.0))
	return maxf(coverage, 0.0) * (ring_halo + 0.18 * outer_halo)


## 观察者坐标系的 Beam：光源位置、光束张角、衰减强度与径向色带。
## 与 light_disk_normal() 同一套角度，所以画出来的颜色和打在月面上的光一致。
func beam_state(observer: Vector3, with_shadow: bool = true) -> Dictionary:
	var center := -observer
	var distance := center.length()
	var dir := light_disk_normal()
	var cone := acos(clampf((-center / maxf(distance, 1.0e-6)).dot(dir), -1.0, 1.0))
	var coverage := 1.0
	var shadow_cone := PI * 0.5
	if with_shadow:
		shadow_cone = shadow_cone_radius(distance)
		coverage = smoothstep(shadow_cone * 0.92, shadow_cone, cone)
	var g_shift := _redshift(disk_inner_radius(), _orbital_los(disk_inner_radius() * dir, Vector3.ZERO, observer))
	return {
		"alive": true,
		"with_shadow": with_shadow,
		"center": center,
		"direction": dir,
		"distance": distance,
		"cone": cone,
		"coverage": coverage,
		"shadow_cone": shadow_cone,
		"radiance": beam_radiance(g_shift, cone, coverage, 0.0),
		"inner": COLOR_INNER,
		"outer": COLOR_OUTER,
	}


func uniform_block() -> Dictionary:
	if not consistent():
		return {}
	return {
		"u_rs": rs,
		"u_b_crit": shadow_radius(),
		"u_disk_inner": disk_inner_radius(),
		"u_disk_outer": disk_outer_radius(),
		"u_disk_normal": disk_normal(),
		"u_emissivity_exponent": emissivity_exponent,
		"u_emissivity_peak": emissivity_peak,
		"u_photon_sigma": photon_ring_width_rs * rs,
		"u_photon_gain": photon_ring_gain,
		"u_color_inner": COLOR_INNER,
		"u_color_outer": COLOR_OUTER,
		"u_lens_radius": lens_radius(),
		"u_max_radius_over_distance": MAX_RADIUS_OVER_DISTANCE,
		"u_apodize_start": APODIZE_START_FRACTION,
		"u_bozza_offset": bozza_offset(),
		"u_impact_eps": IMPACT_X_FLOOR,
	}


func trace(center: Vector3, ray: Ray) -> Hit:
	if not consistent() or ray == null or ray.direction.length_squared() == 0.0:
		return Hit.invalid()
	var cam := ray.origin
	var dir := ray.direction
	var to_center := center - cam
	var distance := to_center.length()
	if distance <= 1.0e-6:
		return Hit.invalid()
	var t_ca := to_center.dot(dir)
	var closest := cam + t_ca * dir
	var b_vec := closest - center
	var impact := b_vec.length()
	var radius := _effective_lens_radius(distance)
	var alpha := _apodized_deflection(impact, radius)
	var axis := to_center / distance
	var psi_app := acos(clampf(dir.dot(axis), -1.0, 1.0))
	var scale := _sample_scale(psi_app, alpha)
	var disk := _pick_disk(cam, dir, center, impact, b_vec, closest)
	var hit := Hit.new()
	hit.valid = true
	hit.impact = impact
	hit.deflection = alpha
	hit.sample_scale = scale
	if not disk.is_empty():
		hit.captured = false
		hit.shows_background = false
		hit.disk_radius = disk["r"]
		hit.disk_g = _redshift(disk["r"], _orbital_los(disk["point"], center, cam))
		hit.ring_radiance = 0.0
		hit.albedo = _disk_color(disk["r"], hit.disk_g)
		return hit
	if impact <= shadow_radius():
		hit.captured = true
		hit.shows_background = false
		hit.albedo = Color.BLACK
		return hit
	hit.captured = false
	hit.shows_background = true
	hit.ring_radiance = _ring_radiance(impact, b_vec, cam, center)
	hit.albedo = COLOR_INNER * hit.ring_radiance
	return hit


func _effective_lens_radius(camera_distance: float) -> float:
	return minf(lens_radius(), MAX_RADIUS_OVER_DISTANCE * camera_distance)


func _deflection_angle(b: float) -> float:
	if b <= shadow_radius():
		return 0.0
	var weak := 2.0 * rs / b
	var x := maxf(b / shadow_radius() - 1.0, IMPACT_X_FLOOR)
	var strong := -log(x) + bozza_offset()
	return maxf(weak, strong)


func _apodized_deflection(b: float, radius: float) -> float:
	var raw := _deflection_angle(b)
	if radius <= 0.0:
		return 0.0
	var t := smoothstep(APODIZE_START_FRACTION * radius, radius, b)
	return raw * (1.0 - t)


func _sample_scale(psi_app: float, alpha: float) -> float:
	if psi_app <= 1.0e-4:
		return 1.0
	# 一次反演之后的缠绕进光子环，UV 停在对径。
	var psi_src := psi_app - minf(alpha, 2.0 * psi_app)
	return psi_src / psi_app


func _redshift(radius: float, los: float) -> float:
	var mass := rs * 0.5
	var beta := sqrt(mass / (radius - 2.0 * mass))
	var grav := sqrt(1.0 - 3.0 * mass / radius)
	return grav / (1.0 - beta * clampf(los, -1.0, 1.0))


func _orbital_los(point: Vector3, center: Vector3, camera: Vector3) -> float:
	var normal := disk_normal()
	var radial := point - center
	radial = radial - normal * radial.dot(normal)
	if radial.length_squared() < 1.0e-8:
		return 0.0
	var v_hat := normal.cross(radial).normalized()
	return v_hat.dot((camera - point).normalized())


func _ring_radiance(b: float, b_vec: Vector3, camera: Vector3, center: Vector3) -> float:
	if b <= shadow_radius():
		return 0.0
	var sigma := photon_ring_width_rs * rs
	var los := _ring_los(b_vec, camera, center)
	var g_shift := _redshift(disk_inner_radius(), los)
	var falloff := exp(-pow((b - shadow_radius()) / sigma, 2.0))
	return photon_ring_gain * emissivity_peak * pow(g_shift, 4.0) * falloff


func _ring_los(b_vec: Vector3, _camera: Vector3, _center: Vector3) -> float:
	if b_vec.length_squared() < 1.0e-8:
		return 0.0
	var tangent := disk_normal().cross(Vector3.UP)
	if tangent.length_squared() < 1.0e-6:
		tangent = disk_normal().cross(Vector3.RIGHT)
	return tangent.normalized().dot(b_vec.normalized())


func _disk_color(radius: float, g_shift: float) -> Color:
	var span := disk_outer_radius() - disk_inner_radius()
	var t := clampf((radius - disk_inner_radius()) / span, 0.0, 1.0)
	var energy := emissivity_peak * pow(disk_inner_radius() / radius, emissivity_exponent) * pow(g_shift, 4.0)
	return COLOR_INNER.lerp(COLOR_OUTER, t) * energy


func _disk_hit_on_ray(origin: Vector3, dir: Vector3, center: Vector3, t_min: float, t_max: float) -> Dictionary:
	var normal := disk_normal()
	var denom := dir.dot(normal)
	if absf(denom) < 1.0e-4:
		return {}
	var t := (center - origin).dot(normal) / denom
	if t <= t_min or t >= t_max:
		return {}
	var point := origin + t * dir
	var radius := point.distance_to(center)
	if radius < disk_inner_radius() - ANNULUS_EPS or radius > disk_outer_radius() + ANNULUS_EPS:
		return {}
	return {"t": t, "point": point, "r": radius}


func _segment_clears_horizon(camera: Vector3, point: Vector3, center: Vector3) -> bool:
	var seg := point - camera
	if seg.length_squared() < 1.0e-8:
		return camera.distance_to(center) >= rs
	var t := clampf((center - camera).dot(seg) / seg.length_squared(), 0.0, 1.0)
	return camera.lerp(point, t).distance_to(center) >= rs


func _disk_is_near(point: Vector3, camera: Vector3, center: Vector3) -> bool:
	## 交点在相机相对黑洞中心的同一半球 → 近侧一次像。
	return (point - center).dot(camera - center) > 0.0


func _pick_disk(cam: Vector3, dir: Vector3, center: Vector3, b: float, b_vec: Vector3, closest: Vector3) -> Dictionary:
	## 优先级与真实薄盘成像一致：近侧一次像 → b≤b_crit 阴影无盘 → 轮廓外远侧一次/二次像。
	var ingress := _disk_hit_on_ray(cam, dir, center, 0.0, INF)
	if not ingress.is_empty() and _segment_clears_horizon(cam, ingress["point"], center):
		if _disk_is_near(ingress["point"], cam, center):
			return ingress
		if b <= shadow_radius():
			return {}
	elif b <= shadow_radius():
		return {}
	var chosen := {}
	if not ingress.is_empty() and _segment_clears_horizon(cam, ingress["point"], center):
		chosen = ingress
	# 远侧二次像：未渐晕偏折。渐晕只收背景 UV，不改盘的弯折。
	if b > shadow_radius() and b_vec.length_squared() > 1.0e-8:
		var turned := _rotate_toward(dir, -b_vec.normalized(), minf(_deflection_angle(b), PI))
		var egress := _disk_hit_on_ray(closest, turned, center, 0.0, INF)
		if not egress.is_empty():
			var egress_dist: float = (egress["point"] as Vector3).distance_to(cam)
			if chosen.is_empty() or egress_dist < (chosen["point"] as Vector3).distance_to(cam):
				chosen = egress
	return chosen


static func _rotate_toward(dir: Vector3, toward: Vector3, angle: float) -> Vector3:
	var axis := dir.cross(toward)
	if axis.length_squared() < 1.0e-8:
		return dir
	axis = axis.normalized()
	var cosine := cos(angle)
	var sine := sin(angle)
	return dir * cosine + axis.cross(dir) * sine + axis * axis.dot(dir) * (1.0 - cosine)


class Ray:
	var origin: Vector3
	var direction: Vector3

	static func looking(from: Vector3, toward: Vector3) -> Ray:
		var ray := Ray.new()
		ray.origin = from
		var delta := toward - from
		if delta.length_squared() == 0.0:
			push_error("BlackHoleOptics.Ray.looking degenerate")
			return ray
		ray.direction = delta.normalized()
		return ray

	static func with_impact(camera: Vector3, center: Vector3, impact: float, axis_hint: Vector3) -> Ray:
		var to_center := center - camera
		var distance := to_center.length()
		if impact < 0.0 or impact >= distance or axis_hint.length_squared() == 0.0:
			push_error("BlackHoleOptics.Ray.with_impact out of range")
			return Ray.new()
		var parallel := to_center * (-impact * impact / (distance * distance))
		var hint := axis_hint - to_center * (axis_hint.dot(to_center) / (distance * distance))
		if hint.length_squared() < 1.0e-8:
			push_error("BlackHoleOptics.Ray.with_impact hint parallel to center")
			return Ray.new()
		hint = hint.normalized()
		var perp_len := impact * sqrt(1.0 - (impact * impact) / (distance * distance))
		var b_vec := parallel + hint * perp_len
		return looking(camera, center + b_vec)


class Hit:
	var valid: bool = false
	var impact: float = 0.0
	var captured: bool = false
	var shows_background: bool = false
	var deflection: float = 0.0
	var sample_scale: float = 1.0
	var disk_radius: float = 0.0
	var disk_g: float = 0.0
	var ring_radiance: float = 0.0
	var albedo: Color = Color.BLACK

	static func invalid() -> Hit:
		var hit := Hit.new()
		hit.valid = false
		return hit
