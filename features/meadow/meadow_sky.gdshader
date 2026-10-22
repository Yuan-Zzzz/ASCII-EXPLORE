shader_type sky;

const float GRID = 64.0;
const float STAR_CELL_CUTOFF = 0.9965;
const float DISK_RADIUS = 0.20;
const float HORIZON_LOW = -0.08;
const float HORIZON_HIGH = 0.45;
const float DUST_BAND = 8.0;
const float HALO_GAIN = 1.6;

uniform vec3 u_horizon_color : source_color = vec3(0.95, 0.55, 0.25);
uniform vec3 u_zenith_color : source_color = vec3(0.05, 0.08, 0.18);
uniform vec3 u_bh_dir = vec3(0.2673, 0.3118, -0.9110);
uniform float u_bh_angular_radius : hint_range(0.001, 1.5) = 0.06;
uniform vec3 u_bh_glow_color : source_color = vec3(1.0, 0.55, 0.2);
uniform float u_bh_glow_spread : hint_range(0.01, 2.0) = 0.35;
uniform float u_time = 0.0;


float hash(vec3 cell_id) {
	uvec3 q = uvec3(ivec3(cell_id));
	q = q * 1664525u + 1013904223u;
	q.x += q.y * q.z;
	q.y += q.z * q.x;
	q.z += q.x * q.y;
	uint bits = (q.x ^ q.y ^ q.z) & 0x00ffffffu;
	return float(bits) / float(0x01000000u);
}


void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	vec3 base = mix(u_horizon_color, u_zenith_color, smoothstep(HORIZON_LOW, HORIZON_HIGH, h));
	vec3 dust = exp(-abs(h) * DUST_BAND) * u_horizon_color * 0.4;

	float bh_cos = dot(dir, u_bh_dir);
	vec3 halo = u_bh_glow_color * exp((bh_cos - 1.0) / u_bh_glow_spread) * HALO_GAIN;

	vec3 axis = abs(dir);
	vec2 uv;
	float face;
	if (axis.x >= axis.y && axis.x >= axis.z) {
		uv = dir.yz / axis.x;
		face = dir.x > 0.0 ? 0.0 : 1.0;
	} else if (axis.y >= axis.z) {
		uv = dir.xz / axis.y;
		face = dir.y > 0.0 ? 2.0 : 3.0;
	} else {
		uv = dir.xy / axis.z;
		face = dir.z > 0.0 ? 4.0 : 5.0;
	}
	vec2 cell = floor(uv * GRID);
	float keep = step(STAR_CELL_CUTOFF, hash(vec3(cell, face)));
	float star_mask = keep * step(length(fract(uv * GRID) - 0.5), DISK_RADIUS);
	float twinkle = 0.85 + 0.15 * sin(u_time * 2.0 + hash(vec3(cell + 31.0, face)) * TAU);
	vec3 stars = vec3(0.62, 0.72, 0.84) * 0.15 * star_mask * twinkle;

	float inside_silhouette = step(cos(u_bh_angular_radius), bh_cos);
	vec3 color = base + dust + halo + stars;
	color = mix(color, vec3(0.0), inside_silhouette);
	COLOR = color;
}
