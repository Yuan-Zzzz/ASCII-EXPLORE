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
uniform vec3 u_ascii_bg = vec3(0.01, 0.012, 0.02);

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

vec3 apply_ascii(vec3 col, vec2 frag_xy) {
	float lum = clamp(dot(col, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	// Event horizon stays pure black; do not lift it to the near-black shell color.
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
	// Between glyphs keep space black so the silhouette and lensed stars read.
	// Keep a colored floor so the disk stays a disk; glyphs only texture it.
	return mix(col * 0.42, col, step(0.18, mask));
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
	// Keep the disk inside the display range so Bayer and glyphs still see it.
	col = col / (vec3(1.0) + col);
	if (u_dither > 0.5) {
		col = apply_bayer(col, frag_xy);
	}
	if (u_ascii > 0.5) {
		col = apply_ascii(col, frag_xy);
	}
	return col;
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
	VERTEX = (to_model * right) * VERTEX.x * radius + (to_model * up) * VERTEX.y * radius;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_center = center_world;
	v_radius = radius;
}

void fragment() {
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(v_center, 1.0);
	if (clip.w <= 0.0) {
		discard;
	}
	vec3 dir = normalize(v_world - CAMERA_POSITION_WORLD);
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

	bool have_disk = false;
	float best_dist = 1.0e20;
	vec3 best_point = vec3(0.0);
	float best_radius = 0.0;
	vec3 hit_point;
	float hit_radius;
	if (disk_hit(CAMERA_POSITION_WORLD, dir, v_center, hit_point, hit_radius) && clears_horizon(CAMERA_POSITION_WORLD, hit_point, v_center)) {
		have_disk = true;
		best_dist = length(hit_point - CAMERA_POSITION_WORLD);
		best_point = hit_point;
		best_radius = hit_radius;
	}
	if (b > u_b_crit && dot(b_vec, b_vec) > 1e-8) {
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

	ALBEDO = present(col, SCREEN_UV * VIEWPORT_SIZE);
	ALPHA = 1.0;
}
