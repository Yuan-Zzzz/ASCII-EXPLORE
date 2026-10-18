# Black Hole Disk Occlusion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the event-horizon shadow free of far-side disk paint; only near-side primary may cross the silhouette, with far-side secondary only for `b > b_crit`.

**Architecture:** Shared thin-disk pick order in `BlackHoleOptics._pick_disk` and `black_hole_lens.gdshader`: near primary → shadow if `b ≤ b_crit` → far primary / secondary outside the critical curve. Near-side test: `dot(hit - center, camera - center) > 0`.

**Tech Stack:** Godot 4.7 GDScript + spatial shader; headless scripts under `tools/`.

**Spec:** `docs/superpowers/specs/2026-10-18-black-hole-disk-occlusion-design.md`

---

### Task 1: Failing occlusion regression tests

**Files:**
- Modify: `tools/test_black_hole_optics.gd`

- [ ] **Step 1: Add `_call_site_occlusion` and wire it into `_run`**

```gdscript
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


func _call_site_occlusion() -> bool:
	var optics = OpticsScript.new()
	# Face-on-ish tilt so far/near hemispheres are clear along +Z view.
	optics.inclination = 1.15
	optics.node_longitude = 0.0
	await process_frame
	var center := Vector3.ZERO
	var cam := Vector3(0.0, 0.0, 200.0)
	var b_crit: float = optics.shadow_radius()
	# Ray into the shadow that can still pierce the geometric far annulus past rs.
	var deep := optics.trace(center, OpticsScript.Ray.with_impact(cam, center, b_crit * 0.5, Vector3.RIGHT))
	if deep.valid and not deep.captured and deep.disk_radius > 0.0:
		return _fail("far disk must not fill shadow b=0.5 b_c disk_r=%s" % deep.disk_radius)
	if not (deep.valid and deep.captured):
		return _fail("expected capture at 0.5 b_c captured=%s" % deep.captured)
	# Just outside critical curve: secondary / ring path must not be forced-captured.
	var outer := optics.trace(center, OpticsScript.Ray.with_impact(cam, center, b_crit * 1.02, Vector3.UP))
	if outer.captured:
		return _fail("just outside b_c must not capture")
	# Near-side looking ray that hits the front annulus should still see disk.
	var near = optics.trace(center, OpticsScript.Ray.looking(cam, Vector3(0.0, optics.disk_inner_radius() * 1.2, 0.0)))
	if not near.valid or near.captured or near.disk_radius <= 0.0:
		return _fail("near primary missing disk_r=%s captured=%s" % [near.disk_radius, near.captured])
	return true
```

- [ ] **Step 2: Run test — expect FAIL on far-disk-in-shadow**

Run: `godot --headless --path . --script res://tools/test_black_hole_optics.gd`

Expected: `OPTICS_FAIL: far disk must not fill shadow...` (or similar) before optics fix.

- [ ] **Step 3: Commit test**

```bash
git add tools/test_black_hole_optics.gd
git commit -m "test(moon_walk): assert far disk does not fill the shadow"
```

---

### Task 2: Fix `BlackHoleOptics._pick_disk`

**Files:**
- Modify: `features/black_hole/black_hole_optics.gd` (`_pick_disk`, add `_disk_is_near`)

- [ ] **Step 1: Implement near-side helper and pick order**

```gdscript
func _disk_is_near(point: Vector3, camera: Vector3, center: Vector3) -> bool:
	return (point - center).dot(camera - center) > 0.0


func _pick_disk(cam: Vector3, dir: Vector3, center: Vector3, b: float, b_vec: Vector3, closest: Vector3) -> Dictionary:
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
	if b > shadow_radius() and b_vec.length_squared() > 1.0e-8:
		var turned := _rotate_toward(dir, -b_vec.normalized(), minf(_deflection_angle(b), PI))
		var egress := _disk_hit_on_ray(closest, turned, center, 0.0, INF)
		if not egress.is_empty():
			var egress_dist: float = (egress["point"] as Vector3).distance_to(cam)
			if chosen.is_empty() or egress_dist < (chosen["point"] as Vector3).distance_to(cam):
				chosen = egress
	return chosen
```

- [ ] **Step 2: Run optics tests — expect PASS**

Run: `godot --headless --path . --script res://tools/test_black_hole_optics.gd`

Expected: `OPTICS_OK`

- [ ] **Step 3: Commit**

```bash
git add features/black_hole/black_hole_optics.gd
git commit -m "fix(moon_walk): keep far-side disk out of the critical shadow"
```

---

### Task 3: Mirror pick order in the lens shader

**Files:**
- Modify: `features/black_hole/black_hole_lens.gdshader` (helpers + main disk branch ~502–531)

- [ ] **Step 1: Add `disk_is_near` and reorder disk selection**

```glsl
bool disk_is_near(vec3 point, vec3 camera, vec3 center) {
	return dot(point - center, camera - center) > 0.0;
}
```

Replace the `have_disk` block so that:

1. Primary hit + `clears_horizon` + `disk_is_near` → accept and skip secondary.
2. Else if `b <= u_b_crit` → no disk (fall through to black).
3. Else accept far primary if cleared; then secondary as today (may replace far primary by distance).

- [ ] **Step 2: Run smoke + light**

```bash
godot --headless --path . --script res://tools/smoke_black_hole.gd
godot --headless --path . --script res://tools/test_black_hole_light.gd
```

Expected: both print `*_OK` (or project's existing success tags).

- [ ] **Step 3: Commit**

```bash
git add features/black_hole/black_hole_lens.gdshader
git commit -m "fix(moon_walk): match lens disk occlusion to optics pick order"
```

---

### Task 4: Plan + optional shot check

**Files:**
- Create: `docs/superpowers/plans/2026-10-18-black-hole-disk-occlusion.md` (this file)

- [ ] **Step 1: Commit plan if not already committed**

- [ ] **Step 2 (optional):** `godot --path . --script res://tools/shot_black_hole.gd` and confirm shadow interior has no far-disk fill.
