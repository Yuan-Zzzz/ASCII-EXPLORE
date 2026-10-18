shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, specular_disabled, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;

uniform float u_rs;
uniform float u_b_crit;
uniform float u_disk_inner;
uniform float u_disk_outer;
uniform vec3 u_disk_normal;
uniform float u_emissivity_exponent;
uniform float u_emissivity_peak;
uniform float u_photon_sigma;
uniform float u_photon_gain;
uniform vec4 u_color_inner;
uniform vec4 u_color_outer;
uniform float u_lens_radius;
uniform float u_max_radius_over_distance;
uniform float u_apodize_start;
uniform float u_bozza_offset;
uniform float u_impact_eps;

// Runtime presentation (not part of BlackHoleOptics.uniform_block).
uniform float u_time = 0.0;
uniform float u_disk_phase = 0.0;
uniform sampler2D u_atlas : source_color, filter_nearest, repeat_disable;
uniform int u_char_count = 10;
uniform float u_glyph_px = 12.0;
uniform float u_ascii = 1.0;
uniform float u_dither = 1.0;
uniform float u_dither_pixel_size = 1.0;
uniform float u_dither_color_levels = 4.0;
uniform float u_glow_energy = 0.18;

// 月面一侧（从月面看黑洞）：
// u_view_frame：观察者坐标系（相机在 (0, 0, -d)，朝黑洞看）到黑洞坐标系的旋转。
// u_occlude：透镜作用在没有月亮的天空上；月面本身由字符着色器绘制。
uniform mat3 u_view_frame = mat3(1.0);
uniform bool u_occlude = false;
uniform vec3 u_occluder_center = vec3(0.0, 0.0, 0.0);
uniform float u_occluder_radius = 1.0;
// 天空天体：黑洞坐标里的实际中心与铺到无限远球壳上的位置，绕黑洞时用来取背景。
uniform int u_sky_count = 0;
uniform vec3 u_sky_center_0 = vec3(0.0);
uniform vec3 u_sky_center_1 = vec3(0.0);
uniform vec3 u_sky_height_0 = vec3(0.0);
uniform vec3 u_sky_height_1 = vec3(0.0);
uniform float u_sky_radius_0 = 0.0;
uniform float u_sky_radius_1 = 0.0;
// 盘面照射月面的光（CPU beam_state / COLOR_INNER 一侧）。
uniform float u_beam_lit = 0.0;
uniform vec3 u_beam_energy = vec3(0.0);
uniform vec3 u_beam_inner = vec3(1.0, 0.82, 0.55);
uniform vec3 u_beam_outer = vec3(0.85, 0.22, 0.04);
uniform vec3 u_beam_disk_normal = vec3(0.0, 0.0, 1.0);
uniform float u_beam_slant_sin = 0.0;
uniform float u_beam_shadow_cos = 0.0;
uniform float u_beam_shadow_width = 0.02;
uniform float u_beam_flat_dark = 0.08;
uniform float u_beam_sun_cos = 1.0;

const float ANNULUS_EPS = 0.001;
const float BAYER_4X4[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

varying vec3 v_world;
varying vec3 v_center;
varying float v_radius;
varying vec3 v_forward;
varying vec3 v_right;
varying vec3 v_up;

float deflection_angle(float b) {
	if (b <= u_b_crit) {
		return 0.0;
	}
	float weak = 2.0 * u_rs / b;
	float x = max(b / u_b_crit - 1.0, u_impact_eps);
	float strong = -log(x) + u_bozza_offset;
	return max(weak, strong);
}

float apodized_deflection(float b, float radius) {
	float raw = deflection_angle(b);
	if (radius <= 0.0) {
		return 0.0;
	}
	float t = smoothstep(u_apodize_start * radius, radius, b);
	return raw * (1.0 - t);
}

float sample_scale(float psi_app, float alpha) {
	if (psi_app <= 0.0001) {
		return 1.0;
	}
	float psi_src = psi_app - min(alpha, 2.0 * psi_app);
	return psi_src / psi_app;
}

vec3 rotate_toward(vec3 dir, vec3 toward, float angle) {
	vec3 axis = cross(dir, toward);
	if (dot(axis, axis) < 1e-8) {
		return dir;
	}
	axis = normalize(axis);
	float cosine = cos(angle);
	float sine = sin(angle);
	return dir * cosine + cross(axis, dir) * sine + axis * dot(axis, dir) * (1.0 - cosine);
}

float redshift_g(float radius, float los) {
	float mass = u_rs * 0.5;
	float beta = sqrt(mass / (radius - 2.0 * mass));
	float grav = sqrt(1.0 - 3.0 * mass / radius);
	return grav / (1.0 - beta * clamp(los, -1.0, 1.0));
}

vec3 spin_basis_x(vec3 normal) {
	vec3 tangent = cross(normal, vec3(0.0, 1.0, 0.0));
	if (dot(tangent, tangent) < 1e-6) {
		tangent = cross(normal, vec3(1.0, 0.0, 0.0));
	}
	return normalize(tangent);
}

vec3 rotate_around_normal(vec3 v, vec3 normal, float angle) {
	vec3 axis = normalize(normal);
	float c = cos(angle);
	float s = sin(angle);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

float orbital_los(vec3 point, vec3 center, vec3 camera) {
	vec3 radial = point - center;
	radial -= u_disk_normal * dot(radial, u_disk_normal);
	if (dot(radial, radial) < 1e-8) {
		return 0.0;
	}
	radial = rotate_around_normal(radial, u_disk_normal, u_disk_phase);
	vec3 v_hat = normalize(cross(u_disk_normal, radial));
	return dot(v_hat, normalize(camera - point));
}

float ring_los(vec3 b_vec) {
	if (dot(b_vec, b_vec) < 1e-8) {
		return 0.0;
	}
	vec3 tangent = spin_basis_x(u_disk_normal);
	tangent = rotate_around_normal(tangent, u_disk_normal, u_disk_phase);
	return dot(normalize(tangent), normalize(b_vec));
}

bool disk_hit(vec3 origin, vec3 dir, vec3 center, out vec3 point, out float radius) {
	float denom = dot(dir, u_disk_normal);
	if (abs(denom) < 0.0001) {
		return false;
	}
	float t = dot(center - origin, u_disk_normal) / denom;
	if (t <= 0.0) {
		return false;
	}
	point = origin + t * dir;
	radius = length(point - center);
	if (radius < u_disk_inner - ANNULUS_EPS || radius > u_disk_outer + ANNULUS_EPS) {
		return false;
	}
	return true;
}

bool clears_horizon(vec3 camera, vec3 point, vec3 center) {
	vec3 seg = point - camera;
	if (dot(seg, seg) < 1e-8) {
		return length(camera - center) >= u_rs;
	}
	float t = clamp(dot(center - camera, seg) / dot(seg, seg), 0.0, 1.0);
	return length(mix(camera, point, t) - center) >= u_rs;
}

bool disk_is_near(vec3 point, vec3 camera, vec3 center) {
	return dot(point - center, camera - center) > 0.0;
}

float disk_swirl(vec3 point, vec3 center, float radius) {
	vec3 radial = point - center;
	radial -= u_disk_normal * dot(radial, u_disk_normal);
	if (dot(radial, radial) < 1e-8) {
		return 1.0;
	}
	radial = rotate_around_normal(radial, u_disk_normal, u_disk_phase);
	vec3 bx = spin_basis_x(u_disk_normal);
	vec3 by = cross(u_disk_normal, bx);
	float az = atan(dot(radial, by), dot(radial, bx));
	// Floor stays high so ASCII still sees a disk between spiral arms.
	float arms = 0.72 + 0.28 * sin(az * 2.0 - u_time * 1.6 + log(max(radius, 0.2)) * 4.0);
	float flicker = 0.9 + 0.1 * sin(u_time * 5.0 + az * 9.0);
	return arms * flicker;
}

vec3 disk_color(vec3 point, vec3 center, float radius, float g_shift) {
	float span = max(u_disk_outer - u_disk_inner, 0.001);
	float t = clamp((radius - u_disk_inner) / span, 0.0, 1.0);
	float radial = pow(u_disk_inner / max(radius, u_disk_inner), u_emissivity_exponent);
	float g4 = pow(max(g_shift, 0.15), 4.0);
	float energy = u_emissivity_peak * mix(0.35, 1.0, radial) * mix(0.45, 1.6, clamp(g4, 0.0, 2.0));
	energy *= disk_swirl(point, center, radius);
	return mix(u_color_inner.rgb, u_color_outer.rgb, t) * energy;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Procedural stars in lensed UV space so an empty WorldEnvironment still shows deflection.
vec3 starfield(vec2 uv) {
	vec2 cell = floor(uv * 110.0);
	float n = hash21(cell);
	float keep = step(0.992, n);
	float spark = pow(hash21(cell + 19.7), 10.0);
	float twinkle = 0.65 + 0.35 * sin(u_time * 6.0 + n * 40.0);
	return vec3(0.72, 0.84, 1.0) * keep * spark * twinkle * 3.2;
}

// Solid glyph stroke plus a soft fringe from the same atlas cell.
// The lens uses screen_texture so it stays in the transparent pass; Environment
// glow often ignores that pass, so the fringe is baked into the color the glyph emits.
vec3 apply_ascii(vec3 col, vec2 frag_xy) {
	float lum = clamp(dot(col, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	if (lum < 0.02) {
		return vec3(0.0);
	}
	float cell = max(u_glyph_px, 4.0);
	vec2 local = fract(frag_xy / cell);
	int n = max(u_char_count, 1);
	int idx = clamp(int(lum * float(n)), 0, n - 1);
	if (idx == 0) {
		idx = 1;
	}
	float du = 1.0 / float(n);
	vec2 atlas_uv = vec2((float(idx) + local.x) * du, local.y);
	float mask = textureLod(u_atlas, atlas_uv, 0.0).r;
	vec3 stroke = vec3(0.0);
	if (mask >= 0.28) {
		stroke = col * smoothstep(0.28, 0.75, mask);
	}
	float glow_mask = 0.0;
	for (int oy = -2; oy <= 2; oy++) {
		for (int ox = -2; ox <= 2; ox++) {
			vec2 o = local + vec2(float(ox), float(oy)) * 0.16;
			if (o.x < 0.0 || o.x > 1.0 || o.y < 0.0 || o.y > 1.0) {
				continue;
			}
			float m = textureLod(u_atlas, vec2((float(idx) + o.x) * du, o.y), 0.0).r;
			float w = exp(-0.5 * float(ox * ox + oy * oy));
			glow_mask += m * w;
		}
	}
	vec3 glow = col * glow_mask * 0.28 * max(u_glow_energy, 0.0);
	return stroke * (1.0 + 0.85 * max(u_glow_energy, 0.0)) + glow;
}

vec3 apply_bayer(vec3 col, vec2 frag_xy) {
	ivec2 cell = ivec2(mod(floor(frag_xy / max(u_dither_pixel_size, 1.0)), 4.0));
	float threshold = (BAYER_4X4[cell.y * 4 + cell.x] + 0.5) / 16.0;
	float steps = max(floor(u_dither_color_levels + 0.5) - 1.0, 1.0);
	return clamp(floor(clamp(col, 0.0, 1.0) * steps + threshold) / steps, 0.0, 1.0);
}

vec3 present(vec3 col, vec2 frag_xy) {
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	if (lum < 0.012) {
		return vec3(0.0);
	}
	col = col / (vec3(1.0) + col);
	if (u_dither > 0.5) {
		col = apply_bayer(col, frag_xy);
	}
	if (u_ascii > 0.5) {
		return apply_ascii(col, frag_xy);
	}
	return col * (1.0 + max(u_glow_energy, 0.0));
}

// ---- 月面一侧的辅助函数 ----
// 观察者坐标系（观察者在原点，朝黑洞看）。
vec3 orbit_dir(vec3 world_dir) {
	return normalize(u_view_frame * world_dir);
}

vec3 orbit_point(vec3 world_point) {
	return u_view_frame * (world_point - v_center);
}

// 观察者坐标系里一点 p 的归一化屏幕坐标（中心 0.5，视野高度 1）。
vec2 screen_uv_of(vec3 p) {
	float f = max(dot(p, v_forward), 1.0e-6);
	return vec2(0.5 + 0.5 * dot(p, v_right) / f, 0.5 + 0.5 * dot(p, v_up) / f);
}

// 观察者坐标系里月面的有向距离（user-defined SDF）。
float map(vec3 p) {
	if (!u_occlude) {
		return 1.0e20;
	}
	return length(p - u_occluder_center) - u_occluder_radius;
}

// SDF 命中测试：从 from 沿 dir 走到月面。
bool sdf_ray(vec3 from, vec3 dir, out vec3 hit_pos, out vec3 hit_normal, out float ray_length) {
	ray_length = 0.0;
	if (!u_occlude) {
		return false;
	}
	vec3 oc = from - u_occluder_center;
	float b = dot(oc, dir);
	float c = dot(oc, oc) - u_occluder_radius * u_occluder_radius;
	float h = b * b - c;
	if (h < 0.0) {
		return false;
	}
	h = sqrt(h);
	ray_length = max(-b - h, 0.0);
	hit_pos = from + dir * ray_length;
	float radius = length(hit_pos - u_occluder_center);
	hit_normal = radius > 1.0e-6 ? (hit_pos - u_occluder_center) / radius : dir;
	return true;
}

// 天空天体：观察者在原点，天体是视角平面上一块角半径 radius / |center| 的圆斑。
// 命中后沿它铺到球壳上的方向取样，透镜才会把天体弯开、拉成环。
bool sky_one(vec3 dir, vec3 center, vec3 height, float radius, out vec3 sky_dir) {
	sky_dir = dir;
	float distance = max(length(center), 1.0e-3);
	if (radius <= 0.0) {
		return false;
	}
	float cone = asin(clamp(radius / distance, 0.0, 0.999));
	if (acos(clamp(dot(dir, center / distance), -1.0, 1.0)) > cone) {
		return false;
	}
	sky_dir = normalize(height);
	return true;
}

bool sky_hit(vec3 dir, out vec3 sky_dir) {
	if (u_sky_count >= 1 && sky_one(dir, u_sky_center_0, u_sky_height_0, u_sky_radius_0, sky_dir)) {
		return true;
	}
	if (u_sky_count >= 2 && sky_one(dir, u_sky_center_1, u_sky_height_1, u_sky_radius_1, sky_dir)) {
		return true;
	}
	sky_dir = dir;
	return false;
}

// 来自黑洞的辐照：盘的近侧更亮；来自黑洞背面、偏离盘法线超过阴影角的点只剩边缘光。
float shadow_light(vec3 e_dir) {
	float slant = dot(u_beam_disk_normal, e_dir);
	float lit = mix(u_beam_flat_dark, 1.0, smoothstep(u_beam_shadow_cos, u_beam_shadow_cos + u_beam_shadow_width, slant));
	lit *= mix(0.25, 1.0, smoothstep(0.0, 0.35, u_beam_sun_cos));
	return lit;
}

// 盘面光束的颜色：近侧亮、远侧暗。
vec3 beam_tint() {
	return u_beam_energy * mix(u_beam_inner, u_beam_outer, u_beam_slant_sin);
}

void vertex() {
	vec3 center_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(CAMERA_POSITION_WORLD - center_world);
	float radius = min(u_lens_radius, u_max_radius_over_distance * dist);
	vec3 forward = vec3(0.0, 0.0, 1.0);
	if (dist > 0.0001) {
		forward = (CAMERA_POSITION_WORLD - center_world) / dist;
	}
	vec3 right = cross(vec3(0.0, 1.0, 0.0), forward);
	if (dot(right, right) < 1e-6) {
		right = cross(vec3(1.0, 0.0, 0.0), forward);
	}
	right = normalize(right);
	vec3 up = normalize(cross(forward, right));
	mat3 to_model = inverse(mat3(MODEL_MATRIX));
	vec3 world_pos;
	if (u_occlude) {
		// 月面一侧：透镜半径可能超出相机远平面，按透镜在屏幕上的大小重铺 quad。
		// world_focus：视野高度 = 2 时的相机空间深度。
		float world_focus = 2.0 / PROJECTION_MATRIX[1][1];
		float aspect = VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0);
		float forward_depth = max(dot(center_world - CAMERA_POSITION_WORLD, forward), 0.0001);
		// 只覆盖透镜半径 radius，加 2% 留边；超出部分的采样 clamp 到屏幕边。
		float keep = clamp(radius / max(forward_depth, 0.0001) * (PROJECTION_MATRIX[1][1] * 0.5) * 1.02, 0.01, 1.0);
		float quad_depth = clamp(forward_depth, 0.25 * world_focus, 0.98 * world_focus);
		float half_height = quad_depth / (PROJECTION_MATRIX[1][1] * 0.5) * keep;
		float half_width = half_height * aspect;
		vec3 view_right = cross(vec3(0.0, 1.0, 0.0), forward);
		if (dot(view_right, view_right) < 1e-6) {
			view_right = right;
		}
		view_right = normalize(view_right);
		vec3 view_up = normalize(cross(forward, view_right));
		world_pos = center_world
			+ forward * (quad_depth - forward_depth)
			+ view_right * (VERTEX.x * half_width)
			+ view_up * (VERTEX.y * half_height);
		right = view_right;
		up = view_up;
	} else {
		VERTEX = (to_model * right) * VERTEX.x * radius + (to_model * up) * VERTEX.y * radius;
		world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
	VERTEX = to_model * (world_pos - center_world);
	v_world = world_pos;
	v_center = center_world;
	v_radius = radius;
	v_forward = forward;
	v_right = right;
	v_up = up;
}

void fragment() {
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(v_center, 1.0);
	if (clip.w <= 0.0) {
		discard;
	}
	vec3 dir = normalize(v_world - CAMERA_POSITION_WORLD);
	if (u_occlude) {
		// 月面一侧：同一套透镜作用在没有月亮的天空上。
		// 追迹到的月面点按屏幕映射映回同一个像素：阴影里的那一格就是黑洞“搬”过来的背景，
		// 可见的月面交给字符着色器，这里只叠加黑洞打来的光。
		vec3 f_dir = orbit_dir(dir);
		vec3 f_cam = orbit_point(CAMERA_POSITION_WORLD);
		vec3 to_center = -f_cam;
		float dist = max(length(to_center), 0.0001);
		vec3 axis = to_center / dist;
		float psi_app = acos(clamp(dot(f_dir, axis), -1.0, 1.0));
		float cos_a = clamp(dot(f_dir, -axis), -1.0, 1.0);
		float b = dist * sqrt(max(1.0 - cos_a * cos_a, 0.0));
		float alpha = apodized_deflection(b, v_radius);
		float scale = sample_scale(psi_app, alpha);
		float xh = screen_uv_of(to_center).x;
		vec3 col = vec3(0.0);
		vec3 light = vec3(0.0);
		vec3 hit_pos;
		vec3 hit_normal;
		float ray_length;
		if (sdf_ray(f_cam, f_dir, hit_pos, hit_normal, ray_length)) {
			// 月面点按“从黑洞反向落回”的方向投到透镜的屏幕映射上（横向向圆心压缩），
			// 得到被黑洞透镜重新排布过的星空。
			vec3 back = -hit_normal;
			float los_cos = clamp(dot(back, -axis), -1.0, 1.0);
			float back_b = dist * sqrt(max(1.0 - los_cos * los_cos, 0.0));
			float back_alpha = apodized_deflection(back_b, v_radius);
			float back_psi = acos(clamp(dot(back, axis), -1.0, 1.0));
			float back_scale = sample_scale(back_psi, back_alpha);
			vec2 source_uv = clamp(vec2(
				xh + (SCREEN_UV.x - 0.5 - xh) * back_scale,
				0.5 + (SCREEN_UV.y - 0.5) * back_scale
			), vec2(0.001), vec2(0.999));
			vec3 background = texture(screen_texture, source_uv).rgb;
			// 天空天体：沿透镜偏折后的方向看。
			vec3 lateral = back - axis * dot(back, axis);
			lateral = length(lateral) > 1.0e-6 ? normalize(lateral) : v_up;
			vec3 sky_dir;
			if (sky_hit(back - lateral * 2.0 * min(back_alpha, 3.0), sky_dir)) {
				background = texture(screen_texture, clamp(screen_uv_of(sky_dir), vec2(0.001), vec2(0.999))).rgb;
			}
			// e：像素方向上落在月面球面上的点。它到轴线的距离 e_b 在事件视界内，这一格就属于黑洞。
			vec3 e_dir = normalize(u_occluder_center + f_dir * max(ray_length, 0.0) - f_cam * 0.0);
			float moon_distance = length(u_occluder_center + f_cam);
			float e_los = dot(e_dir, -axis);
			float e_b = moon_distance * sqrt(max(1.0 - e_los * e_los, 0.0));
				float inside = e_b < u_b_crit ? 1.0 : 0.0;
			col = background * inside;
			light = beam_tint() * u_beam_lit * shadow_light(e_dir) * (1.0 - inside);
		} else if (b > u_b_crit) {
			// 视线擦过黑洞边缘：被抠掉的月面位置换回透镜化的星空。
			vec2 src = vec2((SCREEN_UV.x - xh) * scale, (SCREEN_UV.y - 0.5) * scale);
			vec2 sample_uv = clamp(vec2(xh + src.x, 0.5 + src.y), vec2(0.001), vec2(0.999));
			col = texture(screen_texture, sample_uv).rgb;
		}
		col += light;
		ALBEDO = present(col, SCREEN_UV * VIEWPORT_SIZE);
		EMISSION = ALBEDO;
		ALPHA = 1.0 - smoothstep(v_radius * 0.92, v_radius, b);
	}

	else {
		vec3 to_center = v_center - CAMERA_POSITION_WORLD;
		float t_ca = dot(to_center, dir);
		vec3 closest = CAMERA_POSITION_WORLD + t_ca * dir;
		vec3 b_vec = closest - v_center;
		float b = length(b_vec);
		if (b > v_radius) {
			discard;
		}
		float alpha = apodized_deflection(b, v_radius);
		float dist = max(length(to_center), 0.0001);
		float psi_app = acos(clamp(dot(dir, to_center / dist), -1.0, 1.0));
		float scale = sample_scale(psi_app, alpha);

		// Near primary → shadow if b≤b_crit → far primary / secondary outside critical curve.
		bool have_disk = false;
		float best_dist = 1.0e20;
		vec3 best_point = vec3(0.0);
		float best_radius = 0.0;
		vec3 hit_point;
		float hit_radius;
		bool ingress_ok = disk_hit(CAMERA_POSITION_WORLD, dir, v_center, hit_point, hit_radius)
				&& clears_horizon(CAMERA_POSITION_WORLD, hit_point, v_center);
		if (ingress_ok && disk_is_near(hit_point, CAMERA_POSITION_WORLD, v_center)) {
			have_disk = true;
			best_dist = length(hit_point - CAMERA_POSITION_WORLD);
			best_point = hit_point;
			best_radius = hit_radius;
		} else if (b > u_b_crit) {
			if (ingress_ok) {
				have_disk = true;
				best_dist = length(hit_point - CAMERA_POSITION_WORLD);
				best_point = hit_point;
				best_radius = hit_radius;
			}
			if (dot(b_vec, b_vec) > 1e-8) {
				vec3 turned = rotate_toward(dir, -normalize(b_vec), min(deflection_angle(b), PI));
				if (disk_hit(closest, turned, v_center, hit_point, hit_radius)) {
					float egress_dist = length(hit_point - CAMERA_POSITION_WORLD);
					if (!have_disk || egress_dist < best_dist) {
						have_disk = true;
						best_point = hit_point;
						best_radius = hit_radius;
					}
				}
			}
		}

		vec3 col;
		if (have_disk) {
			float g_shift = redshift_g(best_radius, orbital_los(best_point, v_center, CAMERA_POSITION_WORLD));
			col = disk_color(best_point, v_center, best_radius, g_shift);
		} else if (b <= u_b_crit) {
			col = vec3(0.0);
		} else {
			vec2 ndc = clip.xy / clip.w;
			vec2 bh_uv = ndc * 0.5 + 0.5;
			float aspect = VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0);
			vec2 delta = SCREEN_UV - bh_uv;
			delta.x *= aspect;
			vec2 src = delta * scale;
			src.x /= aspect;
			vec2 sample_uv = clamp(bh_uv + src, vec2(0.001), vec2(0.999));
			vec3 background = texture(screen_texture, sample_uv).rgb;
			// Empty near-black sky: inject stars in the deflected UV so lensing is visible.
			float sky_lum = dot(background, vec3(0.299, 0.587, 0.114));
			vec2 star_uv = (delta * scale) * 0.55 + vec2(u_disk_phase * 0.02, u_time * 0.01);
			background += starfield(star_uv) * mix(1.0, 0.25, smoothstep(0.02, 0.12, sky_lum));
			float los = ring_los(b_vec);
			float g_shift = redshift_g(u_disk_inner, los);
			float falloff = exp(-pow((b - u_b_crit) / max(u_photon_sigma, 0.0001), 2.0));
			float ring = u_photon_gain * u_emissivity_peak * pow(g_shift, 4.0) * falloff;
			float pulse = 0.85 + 0.15 * sin(u_time * 5.0 + b * 3.0);
			col = background + u_color_inner.rgb * ring * pulse * 1.35;
		}

		// Glyph strokes carry baked HDR + atlas fringe glow (transparent screen pass
		// often skips Environment bloom). EMISSION mirrors ALBEDO when the pass allows it.
		ALBEDO = present(col, SCREEN_UV * VIEWPORT_SIZE);
		EMISSION = ALBEDO;
		ALPHA = 1.0;
	}
}