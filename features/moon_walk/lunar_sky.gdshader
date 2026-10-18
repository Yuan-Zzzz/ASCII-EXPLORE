shader_type sky;

const float GRID = 64.0;
const float STAR_CELL_CUTOFF = 0.997;
const float DISK_RADIUS = 0.20;

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
	COLOR = vec3(0.62, 0.72, 0.84) * 0.15 * star_mask;
}
